pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Watches any number of remote Docker stacks, whichever ones the user names, alongside the mise
// tools. For each configured target it runs exactly two remote commands over ssh:
//   <script> check
//   <script> update SERVICE
// The host and script are validated here before they reach a command line, and SERVICE is validated
// here and again by the remote script against its own compose.yaml. With no targets configured this
// singleton starts no process at all and the panel draws no stack section, so the plugin stays
// useful to someone whose stacks are not ours.
Item {
  id: root

  readonly property string sshPath: "/usr/bin/ssh"
  // The configured stacks, filled by the widget from its `services` setting:
  //   [{"id": "media", "name": "Home media", "host": "minipc",
  //     "script": "/srv/home-media/repo/scripts/stack-updates.sh"}]
  // A target whose host or script does not match the shapes below is dropped, never run.
  property var targets: []
  readonly property var hostRe: /^[A-Za-z0-9._@-]{1,128}$/
  readonly property var scriptRe: /^\/[A-Za-z0-9._\/-]{1,300}$/
  readonly property int maxTargets: 16
  readonly property int maxStdoutChars: 262144
  readonly property int checkTimeoutMs: 120000
  // A large image pull (Plex) can take a few minutes on a slow link.
  readonly property int updateTimeoutMs: 900000
  readonly property int panelRefreshMinMs: 60000
  readonly property int sigTerm: 15
  readonly property int sigKill: 9
  readonly property int killGraceMs: 5000
  readonly property var serviceNameRe: /^[a-z0-9][a-z0-9_-]{0,63}$/

  property var consumers: ({})
  property int nextConsumerId: 0
  readonly property int consumerCount: Object.keys(consumers).length
  readonly property bool polling: consumerCount > 0 && !destroying
  property bool destroying: false

  property bool loading: false
  property string errorMessage: ""
  property string lastChecked: ""
  property double lastRefreshAt: 0
  property string checkOutput: ""
  property bool checkAborted: false

  // Targets are checked one at a time, and every row remembers which target produced it: an update
  // has to run on the host that owns the service.
  property int checkTargetAt: 0
  property int checkTotals: 0
  property var checkRows: []
  property var checkErrors: []
  readonly property string checkingTargetName: root.checkTargetAt < root.targets.length
    ? root.targets[root.checkTargetAt].name : ""
  readonly property int targetCount: root.targets.length

  // Rows for services with an update waiting (or a lookup error); totalCount is all services.
  property var rows: []
  property int totalCount: 0
  readonly property int outdatedCount: countWhere(function(r) { return r.outdated })
  readonly property int securityCount: countWhere(function(r) { return r.outdated && r.security !== "" })
  readonly property int breakingCount: countWhere(function(r) { return r.outdated && r.breaking })
  readonly property int safeCount: countWhere(function(r) { return r.outdated && !r.reviewRequired })
  readonly property int reviewCount: countWhere(function(r) { return r.outdated && r.reviewRequired })

  property bool updating: false
  property string updatingService: ""
  property var updateQueue: []
  property int updateTotal: 0
  property var updateFailures: []
  property string updateMessage: ""
  property bool updateFailed: false
  property string confirmService: ""

  function countWhere(pred) {
    var n = 0
    for (var i = 0; i < root.rows.length; i++) if (pred(root.rows[i])) n++
    return n
  }

  function acquire() {
    var token = String(++root.nextConsumerId)
    var next = Object.assign({}, root.consumers)
    next[token] = true
    root.consumers = next
    if (root.consumerCount === 1) root.runRefresh()
    return token
  }

  function release(token) {
    if (!Object.prototype.hasOwnProperty.call(root.consumers, token)) return
    var next = Object.assign({}, root.consumers)
    delete next[token]
    root.consumers = next
    if (root.consumerCount > 0) return
    root.loading = false
    root.lastRefreshAt = 0
    root.abortProc(checkProcess, checkDeadline, checkKill)
  }

  // Accept only well-formed targets: a host goes on an ssh command line and a script goes on a
  // remote command line, so neither may carry shell metacharacters. A rejected entry is dropped and
  // counted in `lastRejected` rather than quietly run.
  property int lastRejected: 0

  function normaliseTargets(list) {
    var out = []
    var rejected = 0
    if (!Array.isArray(list)) {
      root.lastRejected = 0
      return out
    }
    for (var i = 0; i < list.length; i++) {
      if (out.length >= root.maxTargets) { rejected++; continue }
      var item = list[i]
      if (!item || typeof item !== "object") { rejected++; continue }
      var host = root.cleanString(item.host, 128).trim()
      var script = root.cleanString(item.script, 300).trim()
      if (!root.hostRe.test(host) || !root.scriptRe.test(script)) { rejected++; continue }
      out.push({
        id: root.isSafeServiceName(item.id) ? item.id : ("target-" + out.length),
        name: root.cleanString(item.name, 40).trim() || host,
        host: host,
        script: script
      })
    }
    root.lastRejected = rejected
    return out
  }

  // Called by the widget when its `services` setting changes. An unchanged target set restarts
  // nothing, so a settings write that means the same thing costs nothing.
  function configure(list) {
    var next = root.normaliseTargets(list)
    var same = next.length === root.targets.length
    if (same)
      for (var i = 0; i < next.length; i++)
        if (next[i].host !== root.targets[i].host || next[i].script !== root.targets[i].script) same = false
    if (same) return
    root.targets = next
    root.rows = []
    root.totalCount = 0
    root.lastChecked = ""
    root.errorMessage = ""
    if (next.length === 0) {
      root.abortProc(checkProcess, checkDeadline, checkKill)
      root.loading = false
    }
    if (root.polling) root.requestRefresh()
  }

  function targetById(id) {
    for (var i = 0; i < root.targets.length; i++) if (root.targets[i].id === id) return root.targets[i]
    return null
  }

  function sshCommand(target, args) {
    var cmd = [root.sshPath, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
      "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", "-T",
      target.host, target.script]
    for (var i = 0; i < args.length; i++) cmd.push(args[i])
    return cmd
  }

  function processEnvironment() {
    return {"HOME": Quickshell.env("HOME"), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
  }

  function abortProc(proc, deadlineTimer, killTimer) {
    deadlineTimer.stop()
    if (proc && proc.running) {
      proc.signal(root.sigTerm)
      killTimer.restart()
    } else {
      killTimer.stop()
    }
  }

  function isSafeServiceName(name) {
    return typeof name === "string" && root.serviceNameRe.test(name)
  }

  function cleanString(value, max) {
    if (typeof value !== "string") return ""
    return value.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").substring(0, max)
  }

  // Keep only well-formed rows; the panel never renders raw remote data.
  function parseReport(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { return null }
    if (!data || typeof data !== "object" || !Array.isArray(data.services)) return null
    if (data.services.length > 64) return null
    var out = []
    for (var i = 0; i < data.services.length; i++) {
      var s = data.services[i]
      if (!s || !root.isSafeServiceName(s.name)) return null
      var reasons = []
      if (Array.isArray(s.reasons))
        for (var j = 0; j < s.reasons.length && j < 8; j++) reasons.push(root.cleanString(s.reasons[j], 160))
      var url = root.cleanString(s.notesUrl, 300)
      if (url.indexOf("https://") !== 0) url = ""
      out.push({
        name: s.name,
        current: root.cleanString(s.current, 48),
        latest: root.cleanString(s.latest, 48),
        outdated: s.outdated === true,
        security: ["critical", "high", "medium", "low", "mentioned"].indexOf(s.security) >= 0 ? s.security : "",
        breaking: s.breaking === true,
        reviewRequired: s.reviewRequired !== false || s.breaking === true,
        reasons: reasons,
        notesUrl: url,
        error: root.cleanString(s.error, 120)
      })
    }
    return out
  }

  // Rows from every target, tagged with the target that produced them; security first, then
  // breaking, then the rest, grouped by target and alphabetical within each group.
  function applyReports() {
    function weight(r) { return r.security !== "" ? 0 : r.breaking ? 1 : r.outdated ? 2 : 3 }
    var all = root.checkRows.slice()
    all.sort(function(a, b) {
      return weight(a) - weight(b)
        || a.targetName.localeCompare(b.targetName)
        || a.name.localeCompare(b.name)
    })
    root.rows = all
    root.totalCount = root.checkTotals
    root.errorMessage = root.checkErrors.join("; ")
    root.lastChecked = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
  }

  function runRefresh() {
    if (!root.polling || root.updating || checkProcess.running) return
    if (root.targets.length === 0) return
    root.lastRefreshAt = Date.now()
    root.loading = true
    root.errorMessage = ""
    root.checkErrors = []
    root.checkRows = []
    root.checkTotals = 0
    root.checkTargetAt = 0
    root.startNextCheck()
  }

  // One target at a time, sequentially: a stack check is a few ssh round trips, and running them in
  // parallel would multiply the timeout bookkeeping for no real gain.
  function startNextCheck() {
    if (!root.polling) {
      root.loading = false
      return
    }
    if (root.checkTargetAt >= root.targets.length) {
      root.finishCheck()
      return
    }
    root.checkOutput = ""
    root.checkAborted = false
    checkProcess.command = root.sshCommand(root.targets[root.checkTargetAt], ["check"])
    checkDeadline.restart()
    checkProcess.running = true
  }

  function finishCheck() {
    root.checkTargetAt = 0
    root.loading = false
    root.applyReports()
  }

  function requestRefresh() {
    if (!root.polling || root.loading || root.updating) return
    var since = Date.now() - root.lastRefreshAt
    if (root.lastRefreshAt > 0 && since >= 0 && since < root.panelRefreshMinMs && root.errorMessage === "") return
    root.runRefresh()
  }

  function handleCheckExited(exitCode) {
    checkDeadline.stop()
    checkKill.stop()
    var output = root.checkOutput
    root.checkOutput = ""
    if (!root.polling) {
      root.loading = false
      return
    }
    var target = root.targets[root.checkTargetAt]
    var label = target ? target.name : "stack"
    if (root.checkAborted || exitCode !== 0) {
      // Keep the last good rows visible; only report which target failed and how.
      var why = root.checkAborted
        ? "timed out"
        : exitCode === 255 ? "could not be reached over ssh" : "check failed (exit " + exitCode + ")"
      if (target) root.checkErrors = root.checkErrors.concat([label + ": " + why])
    } else {
      var list = root.parseReport(output)
      if (list === null) {
        if (target) root.checkErrors = root.checkErrors.concat([label + ": returned invalid data"])
      } else {
        root.checkTotals += list.length
        for (var i = 0; i < list.length; i++) {
          var row = list[i]
          if (!row.outdated && row.error === "") continue
          row.targetId = target ? target.id : ""
          row.targetName = label
          root.checkRows = root.checkRows.concat([row])
        }
      }
    }
    root.checkTargetAt++
    root.startNextCheck()
  }

  // One click arms a breaking update; a second click on the same service runs it.
  function requestUpdate(name) {
    if (root.updating || !root.isSafeServiceName(name)) return
    var row = null
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].name === name) row = root.rows[i]
    if (!row) return
    if (row.reviewRequired && root.confirmService !== name) {
      root.confirmService = name
      root.updateMessage = name + (row.breaking ? " has possible breaking changes." : " needs manual review.")
        + " Read the notes, then click again to update."
      root.updateFailed = false
      return
    }
    root.confirmService = ""
    root.startQueue([{ name: name, targetId: row.targetId }])
  }

  // Updates only services whose release notes could be reviewed and had no warning.
  function updateSafe() {
    if (root.updating) return
    var items = root.rows
      .filter(function(r) { return r.outdated && !r.reviewRequired })
      .map(function(r) { return { name: r.name, targetId: r.targetId } })
    if (items.length > 0) root.startQueue(items)
  }

  function startQueue(items) {
    root.confirmService = ""
    root.updateFailures = []
    root.updateMessage = ""
    root.updateFailed = false
    root.updating = true
    root.updateTotal = items.length
    if (checkProcess.running) root.abortProc(checkProcess, checkDeadline, checkKill)
    root.updateQueue = items.slice(1)
    root.startUpdate(items[0])
  }

  // An update runs on the host that owns the row: the target comes from the row, never from a
  // global, so one stack's update can only ever touch its own host.
  function startUpdate(item) {
    var target = item ? root.targetById(item.targetId) : null
    if (!item || !target || !root.isSafeServiceName(item.name)) { root.finishQueue(); return }
    root.updatingService = item.name
    updateProcess.command = root.sshCommand(target, ["update", item.name])
    updateDeadline.restart()
    updateProcess.running = true
  }

  function handleUpdateExited(exitCode) {
    updateDeadline.stop()
    updateKill.stop()
    if (root.destroying) return
    if (exitCode !== 0) root.updateFailures = root.updateFailures.concat([root.updatingService])
    if (root.updateQueue.length > 0) {
      var next = root.updateQueue[0]
      root.updateQueue = root.updateQueue.slice(1)
      root.startUpdate(next)
      return
    }
    root.finishQueue()
  }

  function finishQueue() {
    var done = root.updatingService
    root.updating = false
    root.updatingService = ""
    if (root.updateFailures.length > 0) {
      root.updateMessage = "Update failed for " + root.updateFailures.join(", ")
      root.updateFailed = true
    } else {
      root.updateMessage = root.updateTotal > 1 ? "Updated " + root.updateTotal + " services" : "Updated " + done
      root.updateFailed = false
    }
    root.runRefresh()
  }

  Component.onDestruction: {
    root.destroying = true
    root.abortProc(checkProcess, checkDeadline, checkKill)
    root.abortProc(updateProcess, updateDeadline, updateKill)
  }

  Process {
    id: checkProcess
    command: []
    running: false
    clearEnvironment: true
    environment: root.processEnvironment()
    workingDirectory: Quickshell.env("HOME")
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.checkAborted) return
        if (root.checkOutput.length + chunk.length > root.maxStdoutChars) {
          root.checkAborted = true
          root.errorMessage = "Stack check output too large"
          root.abortProc(checkProcess, checkDeadline, checkKill)
          return
        }
        root.checkOutput += chunk
      }
    }
    stderr: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    onExited: function(exitCode) { root.handleCheckExited(exitCode) }
  }

  Timer {
    id: checkDeadline
    interval: root.checkTimeoutMs
    repeat: false
    onTriggered: {
      if (!checkProcess.running) return
      root.checkAborted = true
      root.errorMessage = "Stack check timed out"
      root.abortProc(checkProcess, checkDeadline, checkKill)
    }
  }

  Timer {
    id: checkKill
    interval: root.killGraceMs
    repeat: false
    onTriggered: if (checkProcess.running) checkProcess.signal(root.sigKill)
  }

  Process {
    id: updateProcess
    command: []
    running: false
    clearEnvironment: true
    environment: root.processEnvironment()
    workingDirectory: Quickshell.env("HOME")
    stdout: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    stderr: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    onExited: function(exitCode) { root.handleUpdateExited(exitCode) }
  }

  Timer {
    id: updateDeadline
    interval: root.updateTimeoutMs
    repeat: false
    onTriggered: if (updateProcess.running) root.abortProc(updateProcess, updateDeadline, updateKill)
  }

  Timer {
    id: updateKill
    interval: root.killGraceMs
    repeat: false
    onTriggered: if (updateProcess.running) updateProcess.signal(root.sigKill)
  }

  Timer {
    interval: 4 * 60 * 60 * 1000
    repeat: true
    running: root.polling
    onTriggered: root.requestRefresh()
  }
}

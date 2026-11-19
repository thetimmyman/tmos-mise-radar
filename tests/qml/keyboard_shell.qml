import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Backend

// Drives the real Panel from the keyboard. The panel's own key catcher is told what the keys it
// maps would tell it (a move, or Enter / Space), so the path under test is the panel's cursor, the
// real buttons it highlights and the real stack service behind them. The mise side is a recording
// double, so no upgrade ever runs, and no stack target is configured, so nothing reaches ssh.
Scope {
  id: test

  property var stack: Backend.StackService
  property var panel: null
  property var catcher: null
  property var opened: []
  property int failures: 0
  property int stepAt: 0

  QtObject {
    id: mise
    property bool upgrading: false
    property string upgradingTool: ""
    property int outdatedCount: 2
    property string lastChecked: "12:00"
    property string upgradeMessage: ""
    property bool upgradeFailed: false
    property string errorMessage: ""
    property bool loading: false
    property var calls: []
    property var toolRows: [
      {name: "node", requested: "22", current: "22.1", latest: "22.2", outdated: true},
      {name: "go", requested: "1", current: "1.23", latest: "1.23", outdated: false},
      {name: "python", requested: "3", current: "3.12", latest: "3.13", outdated: true}
    ]
    function requestRefresh() {}
    function upgradeAll() { calls = calls.concat(["all"]) }
    function upgradeTool(name) { calls = calls.concat(["tool:" + name]) }
  }

  function check(condition, message) {
    if (condition) return
    failures++
    console.error("FAIL " + message)
  }

  function row(name, over) {
    var base = {name: name, targetId: "media", targetName: "Media", current: "1.0", latest: "1.1",
      outdated: true, security: "", breaking: false, reviewRequired: false, reasons: [], error: "",
      notesUrl: ""}
    for (var key in over) base[key] = over[key]
    return base
  }

  function findCatcher() {
    for (var i = 0; i < panel.resources.length; i++) {
      var resource = panel.resources[i]
      if ("focusTarget" in resource && resource.focusTarget) return resource.focusTarget
    }
    return null
  }
  function buttons() {
    var found = []
    function walk(item) {
      if ("cursorKey" in item) found.push(item)
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(catcher)
    return found
  }
  function shown() { return buttons().filter(function(b) { return b.visible }) }
  function keysOf(list) { return list.map(function(b) { return b.cursorKey }) }
  function button(key) {
    var list = buttons().filter(function(b) { return b.cursorKey === key && b.visible })
    check(list.length === 1, "exactly one visible button for " + key + ", found " + list.length)
    return list.length ? list[0] : null
  }
  function lit() { return keysOf(buttons().filter(function(b) { return b.hasCursor })) }
  function tooltipOf(b) {
    for (var i = 0; i < b.resources.length; i++)
      if ("panelForeground" in b.resources[i]) return b.resources[i]
    return null
  }
  function tipped() { return keysOf(shown().filter(function(b) { return b.cursorTipShown })) }

  function move(dx, dy) { catcher.moveRequested(dx, dy) }
  // Enter emits returnRequested and then activateRequested, Space only the latter. enter() and
  // space() are one deliberate press and release; enterHeld() is a press whose release has not
  // arrived (a held key, or a second press before the first was let go).
  function enterHeld() { catcher.returnRequested(); catcher.activateRequested() }
  function release(key, autoRepeat) { panel.keyReleased(key, autoRepeat) }
  function enter() { enterHeld(); release(Qt.Key_Return, false) }
  function space() { catcher.activateRequested(); release(Qt.Key_Space, false) }
  // The pointer really moving: the shell's gate needs one sample to prime and a second to count.
  function pointerMoves() { panel.pointerMoved(5, 5); panel.pointerMoved(30, 30) }
  function cursorKey() { return panel.cursorState.active ? panel.cursorState.key : "" }
  function sameList(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

  Component.onCompleted: {
    stack.rows = [
      row("plex", {reviewRequired: true, notesUrl: "https://example.invalid/plex-notes", reasons: ["read the notes"]}),
      row("redis"),
      row("broken", {outdated: false, error: "registry lookup failed"})
    ]
    var component = Qt.createComponent("plugin/Panel.qml")
    if (component.status !== Component.Ready) {
      console.error("FAIL panel: " + component.errorString())
      Qt.quit()
      return
    }
    panel = component.createObject(test, {service: mise, stack: stack})
    catcher = findCatcher()
    check("openUrl" in panel, "the panel lets a test stand in for the browser launch")
    if ("openUrl" in panel) panel.openUrl = function(url) { test.opened = test.opened.concat([url]) }
    stepTimer.start()
  }

  readonly property var steps: [
    function() {
      check(catcher !== null, "the panel exposes its key catcher")
      // The cursor targets are exactly the action buttons on screen, in order, with their gating.
      var expected = ["all", "tool:node", "tool:python", "safe", "notes:media|plex", "stack:media|plex", "stack:media|redis"]
      check(sameList(keysOf(shown()), expected), "visible buttons: " + keysOf(shown()))
      check(sameList(panel.cursorTargets.map(function(t) { return t.key }), expected),
        "cursor targets: " + panel.cursorTargets.map(function(t) { return t.key }))
      panel.cursorTargets.forEach(function(t) {
        check(button(t.key).enabled === t.enabled, "target " + t.key + " has its button's enabled state")
      })
      check(panel.cursorState.active === false, "the panel starts with the cursor off")
      check(lit().length === 0, "nothing is highlighted before an arrow")
    },
    function() {
      // Safety: Enter and Space with the cursor off run nothing, even with every button enabled.
      enter()
      space()
      check(mise.calls.length === 0, "Enter before any arrow runs nothing: " + mise.calls)
      check(stack.updateMessage === "" && stack.confirmService === "" && !stack.updating,
        "Enter before any arrow leaves the stack alone")
      check(test.opened.length === 0, "Enter before any arrow opens nothing")
      check(lit().length === 0, "Enter does not switch the cursor on")
    },
    function() {
      move(0, 1)
      check(cursorKey() === "all", "the first arrow switches the cursor on at the first action, got " + cursorKey())
      check(sameList(lit(), ["all"]), "exactly the targeted button is highlighted: " + lit())
      check(mise.calls.length === 0, "the first arrow runs nothing")
      check(button("all").hasCursor && !button("tool:node").hasCursor, "only the first button has the cursor")
    },
    function() {
      move(0, 1)
      check(sameList(lit(), ["tool:node"]), "down moves to the first tool: " + lit())
      enter()
      check(sameList(mise.calls, ["tool:node"]), "Enter on a tool upgrades that tool: " + mise.calls)
      move(0, 1)
      space()
      check(sameList(mise.calls, ["tool:node", "tool:python"]), "Space runs the highlighted tool too: " + mise.calls)
    },
    function() {
      // A running upgrade disables the buttons: the cursor keeps its place and cannot fire.
      mise.upgrading = true
      check(cursorKey() === "tool:python", "the cursor keeps its key while the button is disabled")
      check(button("tool:python").enabled === false, "the tool button is disabled during an upgrade")
      enter()
      space()
      check(mise.calls.length === 2, "a disabled target never fires: " + mise.calls)
      check(sameList(lit(), ["tool:python"]), "hasCursor stays with the kept key: " + lit())
      check(tipped().length === 0, "a disabled button explains nothing: " + tipped())
      mise.upgrading = false
      check(button("tool:python").enabled, "the button is back")
      enter()
      check(sameList(mise.calls, ["tool:node", "tool:python", "tool:python"]), "and the cursor fires again: " + mise.calls)
    },
    function() {
      // Update all, from the keyboard.
      move(0, -1); move(0, -1)
      check(cursorKey() === "all", "back at the top, got " + cursorKey())
      enter()
      check(mise.calls[mise.calls.length - 1] === "all", "Enter on Update all calls upgradeAll")
      move(0, -1)
      check(cursorKey() === "all", "up at the top clamps")
    },
    function() {
      // Update safe services runs the real queue; with no host configured it reports the failure.
      move(0, 1); move(0, 1); move(0, 1)
      check(cursorKey() === "safe", "down reaches the safe-services button, got " + cursorKey())
      enter()
      check(stack.updateMessage === "Update failed for redis", "Enter on safe services runs updateSafe: " + stack.updateMessage)
      check(!stack.updating, "the queue finished")
      stack.updateMessage = ""
    },
    function() {
      // A review-required stack update is two-step, and so is the keyboard path.
      move(0, 1)
      check(cursorKey() === "notes:media|plex", "down reaches the first stack row at its first action, got " + cursorKey())
      move(1, 0)
      check(cursorKey() === "stack:media|plex", "right moves to the update button, got " + cursorKey())
      move(1, 0)
      check(cursorKey() === "stack:media|plex", "right at the end of the row clamps")
      enter()
      check(stack.confirmService === "media|plex", "the first Enter only arms the row: " + stack.confirmService)
      check(!stack.updating && stack.updateMessage.indexOf("click again") > 0, "arming runs nothing: " + stack.updateMessage)
      check(cursorKey() === "stack:media|plex", "the cursor stays on the update button")
      check(button("stack:media|plex").iconText === "󰄬", "the button now shows the confirm icon")
    },
    function() {
      enter()
      check(stack.confirmService === "" && stack.updateMessage === "Update failed for plex",
        "the second Enter runs the update: " + stack.updateMessage + " / " + stack.confirmService)
      stack.updateMessage = ""
    },
    function() {
      // One activation per physical key press: a held or doubled Enter must not skip the review step.
      enterHeld()
      check(stack.confirmService === "media|plex", "the first press arms the row: " + stack.confirmService)
      enterHeld()
      check(stack.confirmService === "media|plex" && stack.updateMessage.indexOf("click again") > 0,
        "a second press with no release in between runs nothing: " + stack.updateMessage)
      release(Qt.Key_Return, true)
      enterHeld()
      check(stack.confirmService === "media|plex", "an auto-repeat release does not reopen the latch: " + stack.updateMessage)
      release(Qt.Key_Down, false)
      enterHeld()
      check(stack.confirmService === "media|plex", "nor does the release of another key: " + stack.updateMessage)
      release(Qt.Key_Return, false)
      enterHeld()
      check(stack.confirmService === "" && stack.updateMessage === "Update failed for plex",
        "after a real release the second deliberate press runs it: " + stack.updateMessage + " / " + stack.confirmService)
      release(Qt.Key_Return, false)
      stack.updateMessage = ""
      // Release notes: a held key opens the page once, and any of Return, Enter and Space reopens the latch.
      move(-1, 0)
      check(cursorKey() === "notes:media|plex", "left to release notes")
      test.opened = []
      enterHeld(); enterHeld(); enterHeld()
      check(test.opened.length === 1, "a held Enter opens the notes once: " + test.opened)
      release(Qt.Key_Space, false)
      enterHeld()
      check(test.opened.length === 2, "a released Space reopens the latch: " + test.opened)
      release(Qt.Key_Enter, false)
      catcher.activateRequested()
      check(test.opened.length === 3, "so does the keypad Enter: " + test.opened)
      release(Qt.Key_Return, false)
      test.opened = []
      move(1, 0)
      check(cursorKey() === "stack:media|plex", "back on the update button")
    },
    function() {
      // A running update disables the stack buttons but not the release notes.
      stack.updating = true
      enter()
      check(stack.updateMessage === "" && stack.confirmService === "", "a disabled update button never fires")
      move(-1, 0)
      check(cursorKey() === "notes:media|plex", "left reaches release notes")
      enter()
      check(sameList(test.opened, ["https://example.invalid/plex-notes"]), "Enter on release notes opens them: " + test.opened)
      move(1, 0)
      check(cursorKey() === "notes:media|plex", "the disabled update button is skipped")
      move(0, 1)
      check(cursorKey() === "notes:media|plex", "and so is the disabled row below")
      stack.updating = false
    },
    function() {
      // The highlighted icon explains itself; nothing else does.
      move(1, 0)
      check(cursorKey() === "stack:media|plex", "right moves to the update button")
      var b = button("stack:media|plex")
      check(sameList(tipped(), ["stack:media|plex"]), "the keyboard cursor shows one tooltip: " + tipped())
      check(tooltipOf(b) !== null && tooltipOf(b).text === b.tooltipText, "with the button's own text")
      check(b.tooltipText.indexOf("Review needed") === 0 || b.tooltipText.indexOf("Confirm") === 0, "tooltip text unchanged: " + b.tooltipText)
    },
    function() {
      // The pointer shares the cursor, but only once it has really moved since the keyboard last did.
      var b = button("tool:python")
      check(cursorKey() === "stack:media|plex", "keyboard cursor before the pointer steps in, got " + cursorKey())
      b.hovered(true)
      check(cursorKey() === "stack:media|plex", "a hover with no pointer movement leaves the cursor alone, got " + cursorKey())
      panel.pointerMoved(5, 5)
      check(cursorKey() === "stack:media|plex", "the first pointer sample only primes the gate")
      panel.pointerMoved(30, 30)
      check(cursorKey() === "tool:python", "after real movement the hovered button takes the cursor, got " + cursorKey())
      check(sameList(lit(), ["tool:python"]), "one highlight on screen: " + lit())
      check(tipped().length === 0, "no second tooltip under the pointer: " + tipped())
      b.hovered(false)
      check(panel.cursorState.active === false, "the pointer leaving switches off a cursor the pointer placed")
      check(lit().length === 0 && tipped().length === 0, "nothing stays highlighted: " + lit())
      enter()
      check(mise.calls.length === 4, "and Enter then runs nothing: " + mise.calls)
    },
    function() {
      // A cursor the keyboard placed is not the pointer's to take away.
      move(0, 1)
      check(cursorKey() === "all", "the next arrow is a first press again, got " + cursorKey())
      var b = button("tool:python")
      b.hovered(true)
      check(cursorKey() === "all", "no pointer movement since the arrow: hover does not take the cursor")
      b.hovered(false)
      check(cursorKey() === "all", "and leaving does not clear a keyboard cursor")
      var all = button("all")
      all.hovered(true)
      all.hovered(false)
      check(cursorKey() === "all", "leaving the button the keyboard cursor sits on does not clear it either")
      move(0, 1); move(0, 1)
      check(cursorKey() === "tool:python", "keyboard cursor on python, got " + cursorKey())
    },
    function() {
      // One tooltip at a time: while the pointer is over any action button its own tooltip is the
      // only one, wherever the keyboard cursor is.
      var node = button("tool:node")
      var python = button("tool:python")
      check(sameList(tipped(), ["tool:python"]), "keyboard tooltip with the pointer elsewhere: " + tipped())
      node.hovered(true)
      check(cursorKey() === "tool:python", "pointer over another button, no movement: cursor stays")
      check(tipped().length === 0, "the keyboard tooltip yields to the pointer being over any button: " + tipped())
      move(0, -1)
      check(cursorKey() === "tool:node", "keyboard to node while the pointer rests on node")
      check(tipped().length === 0, "still one tooltip (the button's own): " + tipped())
      python.hovered(true)
      node.hovered(false)
      check(tipped().length === 0, "pointer now over python: " + tipped())
      move(0, 1)
      check(cursorKey() === "tool:python" && tipped().length === 0, "keyboard onto the hovered button: " + tipped())
      python.hovered(false)
      check(sameList(tipped(), ["tool:python"]), "pointer gone, the keyboard tooltip returns: " + tipped())
      // A button destroyed under the pointer must not leave the keyboard tooltip suppressed.
      node.hovered(true)
      check(tipped().length === 0, "pointer over node")
      node.hovered(false)
      check(sameList(tipped(), ["tool:python"]), "and gone again: " + tipped())
    },
    function() {
      // A button that is disabled or gone under the pointer is not one the pointer is on, whether or
      // not its hover ever cleared, so it cannot leave the keyboard tooltip suppressed for good.
      move(0, 1)
      check(cursorKey() === "safe", "keyboard cursor on safe services, got " + cursorKey())
      check(sameList(tipped(), ["safe"]), "its tooltip is up: " + tipped())
      button("tool:node").hovered(true)
      check(tipped().length === 0, "pointer over node: the keyboard tooltip yields")
      mise.upgrading = true
      check(sameList(tipped(), ["safe"]), "node was disabled under the pointer: the keyboard tooltip returns: " + tipped())
      mise.upgrading = false
      check(tipped().length === 0, "node is enabled again and the pointer is still over it: " + tipped())
      var rows = mise.toolRows
      mise.toolRows = [rows[1], rows[2]]
      mise.outdatedCount = 1
      check(sameList(tipped(), ["safe"]), "node was removed under the pointer: the keyboard tooltip returns: " + tipped())
      mise.toolRows = rows
      mise.outdatedCount = 2
      check(sameList(tipped(), ["safe"]), "and a rebuilt node button is not under the pointer: " + tipped())
    },
    function() {
      // Rows that change under a pointer that is standing still must not move or switch on the
      // cursor: the pointer has to move again first.
      pointerMoves()
      check(panel.pointerArmed === true, "the pointer has moved")
      var rows = mise.toolRows
      mise.toolRows = [rows[1], rows[2]]
      mise.outdatedCount = 1
      check(panel.pointerArmed === false, "a refresh that changes the buttons disarms the pointer")
      button("tool:python").hovered(true)
      check(cursorKey() === "safe", "a button that slid under the pointer does not take the cursor, got " + cursorKey())
      button("tool:python").hovered(false)
      mise.toolRows = rows
      mise.outdatedCount = 2
      move(0, -1)
      check(cursorKey() === "tool:python", "back on python for the next step, got " + cursorKey())
    },
    function() {
      // A refresh keeps the cursor on the same action and falls back when it is gone.
      var node = button("tool:node")
      node.hovered(false)
      move(0, -1)
      check(cursorKey() === "tool:node", "cursor on node")
      mise.toolRows = [mise.toolRows[1], mise.toolRows[2]]
      mise.outdatedCount = 1
      check(cursorKey() === "tool:python", "when node is upgraded the cursor takes python: " + cursorKey())
      check(sameList(lit(), ["tool:python"]), "and highlights it: " + lit())
      mise.toolRows = []
      mise.outdatedCount = 0
      check(panel.cursorState.active === false, "with every target of its group gone and nothing before it the cursor is off")
      check(lit().length === 0, "nothing is highlighted")
      enter()
      check(mise.calls.length === 4, "and Enter then runs nothing: " + mise.calls)
    },
    function() {
      // Back on the next arrow, at the first enabled action.
      move(0, 1)
      check(cursorKey() === "safe", "the next arrow switches it back on at the first action, got " + cursorKey())
    },
    function() {
      // A mirrored panel lays a row out right to left; the catcher swaps the keys, so the cursor's
      // forward is the next button in that layout.
      var holder = catcher.parent
      check(button("notes:media|plex").x < button("stack:media|plex").x, "unmirrored, the first action sits left of the second")
      var enabled = Qt.createQmlObject('import QtQuick\nBinding { property: "LayoutMirroring.enabled"; value: true }', test)
      var inherit = Qt.createQmlObject('import QtQuick\nBinding { property: "LayoutMirroring.childrenInherit"; value: true }', test)
      enabled.target = holder
      inherit.target = holder
      test.mirror = [enabled, inherit]
    },
    function() {
      var notes = button("notes:media|plex")
      var update = button("stack:media|plex")
      check(notes.x > update.x, "mirrored, the first action sits right of the second: " + notes.x + " / " + update.x)
      move(0, 1)
      check(cursorKey() === "notes:media|plex", "down to the stack row")
      move(1, 0)
      check(cursorKey() === "stack:media|plex", "forward is the next action along the mirrored row")
      test.mirror.forEach(function(b) { b.destroy() })
    },
    function() {
      // Opening (or closing) the panel starts the next session with the cursor off, so an Enter
      // on opening can never run an upgrade. The handler is driven without mapping a window.
      check(panel.cursorState.active === true, "the cursor is on before the panel's open state changes")
      panel.openedChanged()
      check(panel.cursorState.active === false, "an open-state change switches the cursor off")
      check(lit().length === 0, "and nothing is highlighted")
      mise.calls = []
      enter()
      check(mise.calls.length === 0, "Enter after reopening runs nothing")
    },
    function() {
      // Opening or closing also drops a held key's latch and the pointer's movement.
      mise.toolRows = [
        {name: "node", requested: "22", current: "22.1", latest: "22.2", outdated: true},
        {name: "python", requested: "3", current: "3.12", latest: "3.13", outdated: true}
      ]
      mise.outdatedCount = 2
      mise.calls = []
      panel.resetCursor()
      move(0, 1)
      check(cursorKey() === "all", "cursor on update all")
      enterHeld()
      check(sameList(mise.calls, ["all"]), "Enter runs it once: " + mise.calls)
      enterHeld()
      check(sameList(mise.calls, ["all"]), "and not again while held: " + mise.calls)
      panel.openedChanged()
      move(0, 1)
      enterHeld()
      check(sameList(mise.calls, ["all", "all"]), "a panel that has reopened takes a fresh Enter: " + mise.calls)
      release(Qt.Key_Return, false)
      pointerMoves()
      panel.openedChanged()
      button("tool:python").hovered(true)
      check(panel.cursorState.active === false, "a pointer resting where a button appears does not switch the cursor on")
      check(lit().length === 0, "so nothing is highlighted on opening")
      panel.pointerMoved(31, 31)
      panel.pointerMoved(60, 60)
      check(cursorKey() === "tool:python", "until the pointer moves: " + cursorKey())
      button("tool:python").hovered(false)
    }
  ]
  property var mirror: []

  Timer {
    id: stepTimer
    interval: 40
    repeat: true
    onTriggered: {
      if (test.stepAt >= test.steps.length) {
        stepTimer.stop()
        if (test.failures === 0) console.log("KEYBOARD_PANEL_OK")
        Qt.quit()
        return
      }
      try {
        test.steps[test.stepAt]()
      } catch (e) {
        test.failures++
        console.error("FAIL step " + test.stepAt + " threw: " + e)
      }
      test.stepAt++
    }
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: { console.error("FAIL keyboard test timed out at step " + test.stepAt); Qt.quit() }
  }
}

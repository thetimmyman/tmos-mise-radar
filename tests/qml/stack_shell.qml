import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Backend

// Drives the real StackService through the decisions that have nothing to do with ssh: which row a
// click is aimed at, when a second click is armed, and why a failed check says what it says. No
// target is configured and no consumer is acquired, so no process runs for the whole test.
Scope {
  id: test

  property var stack: Backend.StackService
  property int failures: 0

  function check(condition, message) {
    if (condition) return
    failures++
    console.error("FAIL " + message)
  }

  Timer {
    id: start
    interval: 10
    running: true
    onTriggered: test.runChecks()
  }

  Timer {
    id: stop
    interval: 10
    running: false
    onTriggered: Qt.exit(test.failures === 0 ? 0 : 1)
  }

  function runChecks() {
    var rows = [
      {name: "plex", targetId: "media", targetName: "Home media", outdated: true,
        security: "", breaking: false, reviewRequired: true, reasons: []},
      {name: "plex", targetId: "lab", targetName: "Lab", outdated: true,
        security: "", breaking: true, reviewRequired: true, reasons: []}
    ]
    stack.rows = rows

    // A service name is not unique across hosts.
    check(stack.rowKey(rows[0]) === "media|plex", "row key carries the host")
    check(stack.rowKey(rows[1]) === "lab|plex", "the same name on another host has its own key")
    check(stack.rowKey(null) === "", "an absent row has no key")
    check(stack.findRow("plex", "lab").targetId === "lab", "row lookup follows the clicked host")
    check(stack.findRow("plex", "media").targetId === "media", "row lookup follows the other host")
    check(stack.findRow("plex", "absent") === null, "an unknown host never falls back to another host's row")

    // Arming is per row, so one host's warning cannot release another host's update.
    stack.requestUpdate("plex", "media")
    check(stack.confirmService === "media|plex", "the first click arms the clicked row")
    check(!stack.updating, "arming alone starts nothing")
    check(stack.updateMessage.indexOf("click again") > 0, "the arming message asks for a second click")
    stack.requestUpdate("plex", "lab")
    check(stack.confirmService === "lab|plex", "the other host's row arms itself")
    check(!stack.updating, "clicking the other host does not run the armed one")
    stack.requestUpdate("plex", "lab")
    check(!stack.updating, "a finished queue leaves the service idle")
    check(stack.confirmService === "", "running clears the armed row")
    // No target is configured in this run, which is the reconfigured-mid-queue case: the queue must
    // say the pull did not happen rather than claim it did.
    check(stack.updateFailed, "a row whose host is gone does not report success")
    check(stack.updateMessage === "Update failed for plex", "the failure names the service: " + stack.updateMessage)

    // Every abort carries its own reason; the flag alone cannot tell a deadline from a size cap.
    stack.checkAborted = true
    stack.checkAbortReason = "output too large"
    check(stack.checkFailureReason(0) === "output too large", "oversized output is not reported as a timeout")
    stack.checkAbortReason = ""
    check(stack.checkFailureReason(0) === "timed out", "an abort with no recorded reason still says timed out")
    stack.checkAborted = false
    check(stack.checkFailureReason(255) === "could not be reached over ssh", "an ssh failure names ssh")
    check(stack.checkFailureReason(3) === "check failed (exit 3)", "a script failure carries its exit code")

    if (failures === 0) console.log("STACK_RUNTIME_OK")
    stop.start()
  }
}

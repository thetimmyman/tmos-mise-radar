import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import "plugin" as Backend

// The keyboard cursor under real input events: QtTest key and mouse events go through a real
// window, the shell's real key catcher, buttons, hover handling and tooltips. Only the layer-shell
// window around the card is a stand-in (see offscreen/KeyboardPanel.qml), and the mise side is a
// recording double, so no upgrade ever runs. Needs QT_QPA_PLATFORM=offscreen (see offscreen_test.py).
ShellRoot {
  Window {
    id: win
    visible: true
    width: 700
    height: 420

    property var stack: Backend.StackService
    property int failures: 0

    Item { id: anchor; x: 300; y: 0; width: 24; height: 24 }

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
        {name: "python", requested: "3", current: "3.12", latest: "3.13", outdated: true}
      ]
      function requestRefresh() {}
      function upgradeAll() { calls = calls.concat(["all"]) }
      function upgradeTool(name) { calls = calls.concat(["tool:" + name]) }
    }

    TestCase {
      id: t
      name: "MiseRadarOffscreen"
      when: false

      property var panel: null
      property var catcher: null

      function check(condition, message) {
        if (condition) return
        win.failures++
        console.error("FAIL " + message)
      }
      function row(name, over) {
        var base = {name: name, targetId: "media", targetName: "Media", current: "1.0", latest: "1.1",
          outdated: true, security: "", breaking: false, reviewRequired: false, reasons: [], error: "",
          notesUrl: ""}
        for (var key in over) base[key] = over[key]
        return base
      }
      function walk(item, fn) {
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
      }
      function buttons() {
        var found = []
        walk(catcher, function(item) { if ("cursorKey" in item) found.push(item) })
        return found
      }
      function button(key) {
        var list = buttons().filter(function(b) { return b.cursorKey === key && b.visible })
        if (list.length !== 1) throw new Error("expected one visible button " + key + ", found " + list.length)
        return list[0]
      }
      function lit() { return buttons().filter(function(b) { return b.hasCursor }).map(function(b) { return b.cursorKey }) }
      function cursorKey() { return panel.cursorState.active ? panel.cursorState.key : "" }
      // Every tooltip that is really open: the buttons' own and the keyboard cursor's.
      function openTips() {
        var open = []
        buttons().forEach(function(b) {
          for (var i = 0; i < b.resources.length; i++)
            if ("panelForeground" in b.resources[i] && b.resources[i].opened) open.push(b.cursorKey)
        })
        return open
      }
      function centre(b) { return b.mapToItem(win.contentItem, b.width / 2, b.height / 2) }
      function pointerTo(b, dx) {
        var c = centre(b)
        mouseMove(win.contentItem, c.x + dx - 24, c.y)
        wait(30)
        mouseMove(win.contentItem, c.x + dx - 12, c.y)
        wait(30)
        mouseMove(win.contentItem, c.x + dx, c.y)
        wait(60)
      }

      function setup() {
        mise.calls = []
        mise.upgrading = false
        win.stack.confirmService = ""
        win.stack.updateMessage = ""
        win.stack.updating = false
        win.stack.rows = [
          row("plex", {reviewRequired: true, reasons: ["read the notes"]}),
          row("redis")
        ]
        if (panel) { panel.destroy(); wait(60) }
        var component = Qt.createComponent("plugin/Panel.qml")
        if (component.status !== Component.Ready) throw new Error("Panel: " + component.errorString())
        panel = component.createObject(anchor, {service: mise, stack: win.stack})
        // A pointer well away from the card.
        mouseMove(win.contentItem, 20, 400)
        wait(60)
      }
      function openPanel() {
        panel.open()
        tryVerify(function() { return panel.opened }, 2000, "the panel opens")
        wait(150)
        catcher = null
        walk(win.contentItem, function(item) {
          if (!catcher && "tabRequested" in item && "moveRequested" in item) catcher = item
        })
        win.requestActivate()
        if (!catcher.activeFocus) catcher.forceActiveFocus()
        tryVerify(function() { return catcher.activeFocus }, 2000, "the key catcher has focus")
        wait(100)
      }
      function closePanel() {
        panel.close()
        tryVerify(function() { return !panel.opened }, 2000, "the panel closes")
        wait(60)
      }

      function scenarioHeldEnter() {
        setup(); openPanel()
        check(cursorKey() === "" && lit().length === 0, "the cursor is off when the panel opens")
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
        check(cursorKey() === "tool:node", "two arrows reach the first tool, got " + cursorKey())
        // A key held down: presses with no release in between. One upgrade, not several.
        keyPress(Qt.Key_Return); keyPress(Qt.Key_Return); keyPress(Qt.Key_Return)
        check(mise.calls.length === 1 && mise.calls[0] === "tool:node", "a held Enter runs the tool once: " + mise.calls)
        keyRelease(Qt.Key_Return)
        keyClick(Qt.Key_Space)
        check(mise.calls.length === 2, "a fresh press after the release runs it again: " + mise.calls)
        // The review-required stack update: a held Enter arms it and must stop there.
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
        check(cursorKey() === "stack:media|plex", "down to the review-required update, got " + cursorKey())
        keyPress(Qt.Key_Return); keyPress(Qt.Key_Return)
        check(win.stack.confirmService === "media|plex" && !win.stack.updating,
          "a held Enter only arms the review step: " + win.stack.confirmService + " / " + win.stack.updateMessage)
        keyRelease(Qt.Key_Return)
        keyClick(Qt.Key_Return)
        check(win.stack.confirmService === "" && win.stack.updateMessage === "Update failed for plex",
          "a second deliberate press confirms it: " + win.stack.updateMessage)
        // The latch does not outlive the session.
        keyPress(Qt.Key_Return)
        closePanel(); openPanel()
        check(cursorKey() === "" , "a reopened panel starts with the cursor off")
        keyClick(Qt.Key_Down)
        mise.calls = []
        keyPress(Qt.Key_Return)
        check(mise.calls.length === 1 && mise.calls[0] === "all", "a reopened panel takes a fresh Enter: " + mise.calls)
        keyRelease(Qt.Key_Return)
      }

      function scenarioPointerAtOpen() {
        setup(); openPanel()
        var spot = centre(button("tool:python"))
        closePanel()
        // The pointer comes to rest where a button will appear, then the panel opens under it.
        mouseMove(win.contentItem, spot.x - 20, spot.y); wait(30)
        mouseMove(win.contentItem, spot.x, spot.y); wait(60)
        openPanel()
        wait(300)
        check(cursorKey() === "" && lit().length === 0,
          "a pointer resting where a button appears does not switch the cursor on, got " + cursorKey())
        // Real movement hands it the button under it.
        mouseMove(win.contentItem, spot.x + 3, spot.y); wait(30)
        mouseMove(win.contentItem, spot.x + 6, spot.y); wait(60)
        check(cursorKey() === "tool:python" && panel.cursorState.source === "pointer",
          "after the pointer moves the hovered button takes the cursor, got " + cursorKey())
        check(lit().length === 1, "and exactly one button is highlighted: " + lit())
        // The keyboard takes it back, and a pointer that then stays still does not.
        keyClick(Qt.Key_Up)
        check(cursorKey() === "tool:node" && panel.cursorState.source === "keyboard", "the keyboard moves it, got " + cursorKey())
        wait(300)
        check(cursorKey() === "tool:node", "a still pointer does not take it back, got " + cursorKey())
        mouseMove(win.contentItem, spot.x + 4, spot.y); wait(30)
        mouseMove(win.contentItem, spot.x - 3, spot.y); wait(60)
        check(cursorKey() === "tool:python", "but the pointer moving again does, got " + cursorKey())
      }

      function scenarioLeaveAndClick() {
        setup(); openPanel()
        var python = button("tool:python")
        pointerTo(python, 0)
        check(cursorKey() === "tool:python", "the pointer put the cursor on its button, got " + cursorKey())
        // Off the button, onto the card: the cursor goes, so Enter runs nothing.
        var header = catcher.mapToItem(win.contentItem, 40, 8)
        mouseMove(win.contentItem, header.x - 10, header.y); wait(30)
        mouseMove(win.contentItem, header.x, header.y); wait(60)
        check(cursorKey() === "" && lit().length === 0, "leaving the button switches a pointer cursor off, got " + cursorKey())
        keyClick(Qt.Key_Return)
        check(mise.calls.length === 0, "and Enter then runs nothing: " + mise.calls)
        // A pointer that arrives on a button the keyboard has the cursor on has not moved there
        // since the keyboard did, so the cursor stays the keyboard's.
        var node = button("tool:node")
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
        check(cursorKey() === "tool:node" && panel.cursorState.source === "keyboard", "the keyboard put the cursor on node, got " + cursorKey())
        var onNode = centre(node)
        mouseMove(win.contentItem, onNode.x, onNode.y); wait(60)
        check(cursorKey() === "tool:node" && panel.cursorState.source === "keyboard", "a pointer arriving unmoved leaves the keyboard cursor, got " + cursorKey())
        keyClick(Qt.Key_Return)
        check(mise.calls.length === 1 && mise.calls[0] === "tool:node", "and Enter runs that button: " + mise.calls)
        // The shell's own click path is untouched by the pointer handling.
        mise.calls = []
        mouseClick(python)
        check(mise.calls.length === 1 && mise.calls[0] === "tool:python", "a pointer click still runs the button: " + mise.calls)
      }

      function scenarioOneTooltip() {
        setup(); openPanel()
        var node = button("tool:node")
        var python = button("tool:python")
        pointerTo(node, 0)
        check(cursorKey() === "tool:node", "pointer on node, got " + cursorKey())
        // The keyboard moves to python while the pointer stays on node: one tooltip, not two.
        keyClick(Qt.Key_Down)
        check(cursorKey() === "tool:python" && panel.cursorState.source === "keyboard", "keyboard on python, got " + cursorKey())
        wait(900)
        var tips = openTips()
        check(tips.length === 1 && tips[0] === "tool:node", "only the button under the pointer explains itself: " + tips)
        // The pointer goes away: the keyboard cursor's tooltip is back.
        mouseMove(win.contentItem, 20, 400)
        wait(900)
        tips = openTips()
        check(tips.length === 1 && tips[0] === "tool:python", "the keyboard tooltip returns when the pointer is off the buttons: " + tips)
      }

      function runAll() {
        scenarioHeldEnter()
        scenarioPointerAtOpen()
        scenarioLeaveAndClick()
        scenarioOneTooltip()
      }
    }

    Timer {
      interval: 900
      running: true
      onTriggered: {
        try {
          t.runAll()
          if (win.failures === 0) console.log("OFFSCREEN_OK")
          Qt.quit()
        } catch (error) {
          console.error("FAIL threw: " + String(error))
          Qt.quit()
        }
      }
    }
    Timer {
      interval: 60000
      running: true
      onTriggered: { console.error("FAIL offscreen test timed out"); Qt.quit() }
    }
  }
}

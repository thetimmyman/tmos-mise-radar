import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Backend

BarWidget {
  id: root
  moduleName: "tmos.mise-radar"

  // Share one backend across monitors without depending on the bar's shell
  // facade, which cannot expose plugin services under replacement bars.
  readonly property var miseService: Backend.MiseService
  readonly property var stackService: Backend.StackService

  // The stacks to watch, from this widget's `services` setting. Empty by default: with none named,
  // the stack service starts no process at all and the panel draws no stack section — the plugin is
  // complete without any, which is the point of making the target list configurable.
  readonly property var configuredServices: root.setting("services", [])
  onConfiguredServicesChanged: if (stackService) stackService.configure(root.configuredServices)
  readonly property int stackOutdated: stackService ? stackService.outdatedCount : 0
  readonly property int stackSecurity: stackService ? stackService.securityCount : 0
  readonly property int stackBreaking: stackService ? stackService.breakingCount : 0
  readonly property int stackReview: stackService ? stackService.reviewCount : 0
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool loading: miseService ? miseService.loading : true
  readonly property int outdatedCount: miseService ? miseService.outdatedCount : 0
  readonly property bool hasError: miseService ? miseService.errorMessage !== "" : false
  readonly property bool stale: root.outdatedCount > 0 || root.stackOutdated > 0
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  property string serviceSubscription: ""
  property string stackSubscription: ""
  Component.onCompleted: {
    serviceSubscription = miseService.acquire()
    stackSubscription = stackService.acquire()
  }
  Component.onDestruction: {
    miseService.release(serviceSubscription)
    stackService.release(stackSubscription)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.miseService
    if ("stack" in target) target.stack = root.stackService
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onMiseServiceChanged: injectPanel()
  onStackServiceChanged: {
    injectPanel()
    if (stackService) stackService.configure(root.configuredServices)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "radar"
    dimmed: root.loading || root.hasError
    tooltipText: {
      if (!root.miseService) return "mise radar"
      var parts = []
      if (root.hasError) parts.push("mise error")
      else if (root.loading) parts.push("mise loading…")
      else if (root.outdatedCount > 0) parts.push(root.outdatedCount + " mise update" + (root.outdatedCount === 1 ? "" : "s"))
      else parts.push("mise up to date")
      if (root.stackService && root.stackService.errorMessage !== "") parts.push("stack check error")
      else if (root.stackOutdated > 0) {
        var s = root.stackOutdated + " stack update" + (root.stackOutdated === 1 ? "" : "s")
        if (root.stackSecurity > 0) s += ", " + root.stackSecurity + " with security fixes"
        if (root.stackReview > 0) s += ", " + root.stackReview + " need review"
        parts.push(s)
      } else if (root.stackService && root.stackService.lastChecked !== "") parts.push("stack up to date")
      return "mise radar · " + parts.join(" · ")
    }

    iconComponent: Component {
      Item {
        id: radar
        readonly property color ink: root.stale ? Color.urgent : button.foreground

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) - 1
          height: width
          radius: width / 2
          color: "transparent"
          border.color: radar.ink
          border.width: 1.25
          antialiasing: true
        }

        Rectangle {
          width: 1.25
          height: parent.height * 0.39
          radius: width / 2
          color: radar.ink
          x: parent.width / 2 - width / 2
          y: parent.height / 2 - height
          transformOrigin: Item.Bottom
          rotation: 42
          antialiasing: true
        }

        Rectangle {
          width: 2.5
          height: width
          radius: width / 2
          color: radar.ink
          x: parent.width * 0.30 - width / 2
          y: parent.height * 0.65 - height / 2
          antialiasing: true
        }

      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}

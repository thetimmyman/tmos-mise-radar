import QtQuick
import QtQuick.Window

// Offscreen stand-in for the shell's layer-shell KeyboardPanel, which cannot map without a
// compositor. It has the public surface the panel uses, shows the content in a card inside the test
// window and focuses the key catcher when it opens. Everything inside the card is the real panel
// with the shell's real buttons, key catcher and tooltips; only the window around it is faked.
Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int padding: 0
  property int contentWidth: 580
  property int contentHeight: 200
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: holder.children

  readonly property Item hostItem: Window.window ? Window.window.contentItem : null

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }
  function fittedContentWidth(width) { return width }
  function fittedContentHeight(height) { return height }

  onOpenChanged: if (open && focusTarget) Qt.callLater(function() {
    if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
  })

  Item {
    id: holder
    parent: root.hostItem
    visible: root.open
    z: 20
    x: 20
    y: 40
    width: root.contentWidth
    height: root.contentHeight
  }
}

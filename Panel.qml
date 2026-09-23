import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "tmos.mise-radar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property var stack: null

  readonly property bool upgrading: root.service ? root.service.upgrading === true : false
  readonly property int outdatedCount: root.service ? root.service.outdatedCount : 0

  function open() {
    root.controller.show()
    if (root.service) root.service.requestRefresh()
    if (root.stack) root.stack.requestRefresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(6)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: "mise radar"
            color: Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.service && root.service.lastChecked !== ""
            text: root.service ? "last successful check " + root.service.lastChecked : ""
            color: Color.popups.text
            opacity: 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          visible: root.outdatedCount > 0 || root.upgrading
          width: parent.width
          spacing: Style.space(6)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰚰"
            tooltipText: "Run mise upgrade --bump for every outdated tool"
            foreground: Color.popups.text
            hoverColor: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            bordered: true
            enabled: !root.upgrading && root.outdatedCount > 0
            onClicked: if (root.service) root.service.upgradeAll()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.upgrading
              ? "Updating " + (root.service.upgradingTool !== "" ? root.service.upgradingTool : "all tools") + "…"
              : "Update all " + root.outdatedCount + " outdated tool" + (root.outdatedCount === 1 ? "" : "s")
            color: Color.popups.text
            opacity: root.upgrading ? 0.6 : 1
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: root.service && root.service.upgradeMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.service ? root.service.upgradeMessage : ""
          color: root.service && root.service.upgradeFailed ? Color.urgent : Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.service && root.service.errorMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.service ? root.service.errorMessage : ""
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.service && !root.service.loading && root.service.toolRows.length === 0 && root.service.errorMessage === ""
          textFormat: Text.PlainText
          text: "No tools configured"
          color: Color.popups.text
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.service && root.service.loading
          textFormat: Text.PlainText
          text: "Loading…"
          color: Color.popups.text
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          visible: root.service && root.service.toolRows.length > 0
          width: parent.width
          spacing: 0

          Row {
            width: parent.width
            height: Style.font.bodySmall + Style.space(4)
            spacing: 0

            Text {
              width: parent.width * 0.36
              textFormat: Text.PlainText
              text: "tool"
              color: Color.popups.text
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "requested"
              color: Color.popups.text
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "installed"
              color: Color.popups.text
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "latest"
              color: Color.popups.text
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Item { width: parent.width * 0.10; height: 1 }
          }

          Repeater {
            model: root.service ? root.service.toolRows : []

            Rectangle {
              width: parent.width
              height: rowTexts.implicitHeight + Style.space(4)
              color: modelData.outdated ? Util.alpha(Color.accent, 0.12) : "transparent"
              radius: Style.cornerRadius

              Row {
                id: rowTexts
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: 0

                Text {
                  width: parent.width * 0.36
                  textFormat: Text.PlainText
                  text: modelData.name
                  elide: Text.ElideRight
                  color: Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.requested
                  elide: Text.ElideRight
                  color: Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.current
                  elide: Text.ElideRight
                  color: Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.latest !== "" ? modelData.latest : modelData.current
                  elide: Text.ElideRight
                  color: modelData.outdated ? Color.accent : Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.outdated
                }
                Item {
                  width: parent.width * 0.10
                  height: Style.space(18)

                  PanelActionButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.outdated
                    iconText: "󰚰"
                    tooltipText: "mise upgrade --bump " + modelData.name
                    foreground: Color.popups.text
                    hoverColor: Color.accent
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    size: Style.space(18)
                    enabled: !root.upgrading
                    onClicked: if (root.service) root.service.upgradeTool(modelData.name)
                  }
                }
              }
            }
          }
        }

        // ---- Watched stacks (whatever the `services` setting names) -----
        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.text
          opacity: 0.12
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: "media stack"
            color: Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.stack && root.stack.lastChecked !== ""
            text: !root.stack ? "" : (root.stack.targetCount === 1
              ? root.stack.targets[0].name
              : root.stack.targetCount + " stacks") + " · checked " + root.stack.lastChecked
            color: Color.popups.text
            opacity: 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          visible: root.stack && (root.stack.safeCount > 0 || root.stack.updating)
          width: parent.width
          spacing: Style.space(6)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰚰"
            tooltipText: "Pull and recreate updates with reviewed notes and no warnings"
            foreground: Color.popups.text
            hoverColor: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            bordered: true
            enabled: root.stack && !root.stack.updating && root.stack.safeCount > 0
            onClicked: if (root.stack) root.stack.updateSafe()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: !root.stack ? "" : root.stack.updating
              ? "Updating " + root.stack.updatingService + "…"
              : "Update " + root.stack.safeCount + " safe service" + (root.stack.safeCount === 1 ? "" : "s")
                + (root.stack.reviewCount > 0 ? " (" + root.stack.reviewCount + " need review)" : "")
            color: Color.popups.text
            opacity: root.stack && root.stack.updating ? 0.6 : 1
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: root.stack && root.stack.updateMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.stack ? root.stack.updateMessage : ""
          color: root.stack && root.stack.updateFailed ? Color.urgent : Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.stack && root.stack.errorMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.stack ? root.stack.errorMessage : ""
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.stack && root.stack.loading && root.stack.lastChecked === ""
          textFormat: Text.PlainText
          text: "Checking " + (root.stack && root.stack.checkingTargetName !== ""
            ? root.stack.checkingTargetName : "stacks") + "…"
          color: Color.popups.text
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.stack && root.stack.lastChecked !== "" && root.stack.rows.length === 0
          textFormat: Text.PlainText
          text: root.stack ? "All " + root.stack.totalCount + " services are on the latest image" : ""
          color: Color.popups.text
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.stack ? root.stack.rows : []

          Rectangle {
            id: stackRow
            readonly property bool secure: modelData.security !== ""
            readonly property bool armed: root.stack && root.stack.confirmService === modelData.name
            width: parent.width
            height: stackCol.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: stackRow.secure ? Util.alpha(Color.urgent, 0.16)
              : modelData.reviewRequired ? Util.alpha(Color.urgent, 0.08)
              : Util.alpha(Color.accent, 0.10)

            Column {
              id: stackCol
              anchors.verticalCenter: parent.verticalCenter
              x: Style.space(4)
              width: parent.width - Style.space(8)
              spacing: Style.space(2)

              Row {
                width: parent.width
                spacing: 0

                Text {
                  width: parent.width * 0.26
                  textFormat: Text.PlainText
                  text: (stackRow.secure ? "🛡 " : modelData.reviewRequired ? "⚠ " : "") + modelData.name
                  elide: Text.ElideRight
                  color: stackRow.secure ? Color.urgent : Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width * 0.29
                  textFormat: Text.PlainText
                  text: modelData.current
                  elide: Text.ElideRight
                  color: Color.popups.text
                  opacity: 0.7
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.29
                  textFormat: Text.PlainText
                  text: modelData.error !== "" ? modelData.error : "→ " + modelData.latest
                  elide: Text.ElideRight
                  color: modelData.error !== "" ? Color.urgent : Color.accent
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.error === ""
                }
                Item {
                  width: parent.width * 0.16
                  height: Style.space(18)

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    PanelActionButton {
                      visible: modelData.notesUrl !== ""
                      iconText: "󰈙"
                      tooltipText: "Open release notes"
                      foreground: Color.popups.text
                      hoverColor: Color.accent
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      size: Style.space(18)
                      onClicked: Qt.openUrlExternally(modelData.notesUrl)
                    }
                    PanelActionButton {
                      visible: modelData.outdated
                      iconText: stackRow.armed ? "󰄬" : "󰚰"
                      tooltipText: stackRow.armed ? "Confirm: update " + modelData.name + " after review"
                        : modelData.reviewRequired ? "Review needed: click, read the notes, click again"
                        : "Pull and recreate " + modelData.name
                      foreground: stackRow.armed ? Color.urgent : Color.popups.text
                      hoverColor: modelData.reviewRequired ? Color.urgent : Color.accent
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      size: Style.space(18)
                      enabled: root.stack && !root.stack.updating
                      onClicked: if (root.stack) root.stack.requestUpdate(modelData.name)
                    }
                  }
                }
              }

              Repeater {
                model: modelData.reasons.slice(0, 3)

                Text {
                  width: stackCol.width
                  textFormat: Text.PlainText
                  text: "  · " + modelData
                  elide: Text.ElideRight
                  color: Color.popups.text
                  opacity: 0.65
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
  }
}

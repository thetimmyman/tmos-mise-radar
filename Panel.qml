import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
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
    padding: Style.spacing.panelPadding
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: "mise radar"
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.service && root.service.lastChecked !== ""
            text: root.service ? "last successful check " + root.service.lastChecked : ""
            color: Commons.Color.popups.text
            opacity: 0.65
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Row {
          visible: root.outdatedCount > 0 || root.upgrading
          width: parent.width
          spacing: Style.spacing.controlGap

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰚰"
            tooltipText: "Run mise upgrade --bump for every outdated tool"
            foreground: Commons.Color.popups.text
            hoverColor: Commons.Color.accent
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
            color: Commons.Color.popups.text
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
          color: root.service && root.service.upgradeFailed ? Commons.Color.urgent : Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.service && root.service.errorMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.service ? root.service.errorMessage : ""
          color: Commons.Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.service && !root.service.loading && root.service.toolRows.length === 0 && root.service.errorMessage === ""
          textFormat: Text.PlainText
          text: "No tools configured"
          color: Commons.Color.popups.text
          opacity: 0.75
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.service && root.service.loading
          textFormat: Text.PlainText
          text: "Loading…"
          color: Commons.Color.popups.text
          opacity: 0.75
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          visible: root.service && root.service.toolRows.length > 0
          width: parent.width
          spacing: Style.spacing.sm

          Row {
            x: Style.spacing.lg
            width: parent.width - Style.spacing.lg * 2
            height: Style.spacing.controlHeight
            spacing: 0

            Text {
              width: parent.width * 0.36
              textFormat: Text.PlainText
              text: "tool"
              color: Commons.Color.popups.text
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "requested"
              color: Commons.Color.popups.text
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "installed"
              color: Commons.Color.popups.text
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width * 0.18
              textFormat: Text.PlainText
              text: "latest"
              color: Commons.Color.popups.text
              opacity: 0.65
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Item { width: parent.width * 0.10; height: 1 }
          }

          Repeater {
            model: root.service ? root.service.toolRows : []

            Rectangle {
              width: parent.width
              height: Math.max(Style.spacing.popupRowHeight, rowTexts.implicitHeight + Style.spacing.xl)
              color: modelData.outdated ? Util.alpha(Commons.Color.accent, 0.10) : Util.alpha(Commons.Color.popups.text, Style.normalFillAlpha)
              radius: Style.cornerRadius
              border.width: Style.spacing.hairline
              border.color: Util.alpha(modelData.outdated ? Commons.Color.accent : Commons.Color.popups.text, 0.12)

              Row {
                id: rowTexts
                anchors.verticalCenter: parent.verticalCenter
                x: Style.spacing.lg
                width: parent.width - Style.spacing.lg * 2
                spacing: 0

                Text {
                  width: parent.width * 0.36
                  textFormat: Text.PlainText
                  text: modelData.name
                  elide: Text.ElideRight
                  color: Commons.Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.requested
                  elide: Text.ElideRight
                  color: Commons.Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.current
                  elide: Text.ElideRight
                  color: Commons.Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.18
                  textFormat: Text.PlainText
                  text: modelData.latest !== "" ? modelData.latest : modelData.current
                  elide: Text.ElideRight
                  color: modelData.outdated ? Commons.Color.accent : Commons.Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.outdated
                }
                Item {
                  width: parent.width * 0.10
                  height: Style.spacing.controlHeight

                  PanelActionButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.outdated
                    iconText: "󰚰"
                    tooltipText: "mise upgrade --bump " + modelData.name
                    foreground: Commons.Color.popups.text
                    hoverColor: Commons.Color.accent
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    size: Style.spacing.controlHeight
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
          color: Commons.Color.popups.text
          opacity: 0.12
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: "media stack"
            color: Commons.Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: root.stack && root.stack.lastChecked !== ""
            text: !root.stack ? "" : (root.stack.targetCount === 1
              ? root.stack.targets[0].name
              : root.stack.targetCount + " stacks") + " · checked " + root.stack.lastChecked
            color: Commons.Color.popups.text
            opacity: 0.65
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Row {
          visible: root.stack && (root.stack.safeCount > 0 || root.stack.updating)
          width: parent.width
          spacing: Style.spacing.controlGap

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰚰"
            tooltipText: "Pull and recreate updates with reviewed notes and no warnings"
            foreground: Commons.Color.popups.text
            hoverColor: Commons.Color.accent
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
            color: Commons.Color.popups.text
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
          color: root.stack && root.stack.updateFailed ? Commons.Color.urgent : Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.stack && root.stack.errorMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.stack ? root.stack.errorMessage : ""
          color: Commons.Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.stack && root.stack.loading && root.stack.lastChecked === ""
          textFormat: Text.PlainText
          text: "Checking " + (root.stack && root.stack.checkingTargetName !== ""
            ? root.stack.checkingTargetName : "stacks") + "…"
          color: Commons.Color.popups.text
          opacity: 0.75
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.stack && root.stack.lastChecked !== "" && root.stack.rows.length === 0
          textFormat: Text.PlainText
          text: root.stack ? "All " + root.stack.totalCount + " services are on the latest image" : ""
          color: Commons.Color.popups.text
          opacity: 0.75
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
            height: stackCol.implicitHeight + Style.spacing.xxl
            radius: Style.cornerRadius
            border.width: Style.spacing.hairline
            border.color: Util.alpha(stackRow.secure || modelData.reviewRequired ? Commons.Color.urgent : Commons.Color.accent, 0.2)
            color: stackRow.secure ? Util.alpha(Commons.Color.urgent, 0.16)
              : modelData.reviewRequired ? Util.alpha(Commons.Color.urgent, 0.08)
              : Util.alpha(Commons.Color.accent, 0.10)

            Column {
              id: stackCol
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.lg
              width: parent.width - Style.spacing.lg * 2
              spacing: Style.spacing.sm

              Row {
                width: parent.width
                spacing: 0

                Text {
                  width: parent.width * 0.26
                  textFormat: Text.PlainText
                  text: (stackRow.secure ? "🛡 " : modelData.reviewRequired ? "⚠ " : "") + modelData.name
                  elide: Text.ElideRight
                  color: stackRow.secure ? Commons.Color.urgent : Commons.Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width * 0.29
                  textFormat: Text.PlainText
                  text: modelData.current
                  elide: Text.ElideRight
                  color: Commons.Color.popups.text
                  opacity: 0.7
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.29
                  textFormat: Text.PlainText
                  text: modelData.error !== "" ? modelData.error : "→ " + modelData.latest
                  elide: Text.ElideRight
                  color: modelData.error !== "" ? Commons.Color.urgent : Commons.Color.accent
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: modelData.error === ""
                }
                Item {
                  width: parent.width * 0.16
                  height: Style.spacing.controlHeight

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.sm

                    PanelActionButton {
                      visible: modelData.notesUrl !== ""
                      iconText: "󰈙"
                      tooltipText: "Open release notes"
                      foreground: Commons.Color.popups.text
                      hoverColor: Commons.Color.accent
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      size: Style.spacing.controlHeight
                      onClicked: Qt.openUrlExternally(modelData.notesUrl)
                    }
                    PanelActionButton {
                      visible: modelData.outdated
                      iconText: stackRow.armed ? "󰄬" : "󰚰"
                      tooltipText: stackRow.armed ? "Confirm: update " + modelData.name + " after review"
                        : modelData.reviewRequired ? "Review needed: click, read the notes, click again"
                        : "Pull and recreate " + modelData.name
                      foreground: stackRow.armed ? Commons.Color.urgent : Commons.Color.popups.text
                      hoverColor: modelData.reviewRequired ? Commons.Color.urgent : Commons.Color.accent
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      size: Style.spacing.controlHeight
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
                  color: Commons.Color.popups.text
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

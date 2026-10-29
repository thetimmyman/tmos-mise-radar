pragma Singleton

import QtQuick

Item {
  property int consumerCount: 0
  property int outdatedCount: 0
  property int securityCount: 0
  property int breakingCount: 0
  property int reviewCount: 0
  property int safeCount: 0
  property int totalCount: 18
  property bool loading: false
  property bool updating: false
  property string updatingService: ""
  property string errorMessage: ""
  property string updateMessage: ""
  property bool updateFailed: false
  property string confirmService: ""
  property string lastChecked: "12:00"
  property var rows: []

  function acquire() { consumerCount++; return String(consumerCount) }
  function release(token) { consumerCount-- }
  property var targets: []
  // The widget calls configure() with its `services` setting; a fake without it raises a TypeError
  // on every widget creation and leaves the stack section unexercised.
  function configure(list) { targets = Array.isArray(list) ? list : (list ? [list] : []) }
  function requestRefresh() {}
  function updateSafe() {}
  // Mirrors the real singleton: an update is aimed at one host, and the panel asks for the row key.
  function rowKey(row) { return row ? String(row.targetId === undefined ? "" : row.targetId) + "|" + String(row.name) : "" }
  function requestUpdate(name, targetId) { lastUpdate = [name, targetId] }
  property var lastUpdate: null
}

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
  function requestRefresh() {}
  function updateSafe() {}
  function requestUpdate(name) {}
}

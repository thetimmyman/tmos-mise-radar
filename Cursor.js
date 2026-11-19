// The panel's keyboard cursor, as plain data and pure functions.
//
// The cursor sits on an action button, never on a row: every target is the exact control that will
// act. Targets come in reading order and are grouped into rows (a tool has one action, a stack row
// up to two). A state says whether the cursor is on, which key it is on and where that key was, so
// that a refreshing model can move the cursor to the nearest sensible action when its own is gone.
//
// Moves are in reading order: +1 is the next action along a row. PanelKeyCatcher already swaps
// left and right in a mirrored panel, and the rows lay their buttons out in the same mirrored
// order, so nothing here knows about mirroring.

var GROUPS = ["all", "tools", "safe", "stacks"]

function initial() {
  return {active: false, key: "", group: "", groupRow: 0, col: 0, goal: 0, source: ""}
}

// input: {all: {visible, enabled}, tools: [{name, outdated}], toolsEnabled,
//         safe: {visible, enabled}, stacks: [{outdated, notesUrl, ...}], stackEnabled}
// rowKey(row) names a stack row, so two hosts running the same service stay two targets.
// Returns [{key, group, row, col, enabled}] in reading order.
function build(input, rowKey) {
  var targets = []
  if (!input) return targets
  var row = -1
  function add(group, cells) {
    if (cells.length === 0) return
    row++
    for (var col = 0; col < cells.length; col++)
      targets.push({key: cells[col].key, group: group, row: row, col: col, enabled: cells[col].enabled === true})
  }
  if (input.all && input.all.visible === true)
    add("all", [{key: "all", enabled: input.all.enabled}])
  var tools = input.tools || []
  for (var i = 0; i < tools.length; i++)
    if (tools[i] && tools[i].outdated === true)
      add("tools", [{key: "tool:" + tools[i].name, enabled: input.toolsEnabled}])
  if (input.safe && input.safe.visible === true)
    add("safe", [{key: "safe", enabled: input.safe.enabled}])
  var stacks = typeof rowKey === "function" ? (input.stacks || []) : []
  for (var j = 0; j < stacks.length; j++) {
    var stack = stacks[j]
    if (!stack) continue
    var key = rowKey(stack)
    var cells = []
    // Release notes are not gated by a running update, the update button is.
    if (hasNotes(stack)) cells.push({key: "notes:" + key, enabled: true})
    if (stack.outdated === true) cells.push({key: "stack:" + key, enabled: input.stackEnabled})
    add("stacks", cells)
  }
  return targets
}

// Whether a stack row has a release-notes button. The panel hides the button with the same test.
function hasNotes(row) {
  return !!row && typeof row.notesUrl === "string" && row.notesUrl !== ""
}

function indexOfKey(targets, key) {
  for (var i = 0; i < targets.length; i++) if (targets[i].key === key) return i
  return -1
}

function firstRowOfGroup(targets, group) {
  for (var i = 0; i < targets.length; i++) if (targets[i].group === group) return targets[i].row
  return 0
}

// The cursor on targets[index], remembering where it is. `goal` is the column a vertical move
// aims for, so crossing a one-action row does not lose the user's column.
function place(targets, index, source, goal) {
  var target = targets[index]
  return {active: true, key: target.key, group: target.group,
    groupRow: target.row - firstRowOfGroup(targets, target.group), col: target.col,
    goal: goal === undefined ? target.col : goal, source: source}
}

// The target in `row` whose column is nearest `col` (ties go to the earlier one); only enabled
// targets when `enabledOnly`. -1 if the row has none.
function nearestInRow(targets, row, col, enabledOnly) {
  var best = -1
  for (var i = 0; i < targets.length; i++) {
    if (targets[i].row !== row || (enabledOnly && !targets[i].enabled)) continue
    if (best < 0 || Math.abs(targets[i].col - col) < Math.abs(targets[best].col - col)) best = i
  }
  return best
}

function lastIndexOfGroup(targets, group) {
  for (var i = targets.length - 1; i >= 0; i--) if (targets[i].group === group) return i
  return -1
}

// Bring a state up to date with a rebuilt target list. The key is kept even if its button is
// disabled for now. If the key is gone the cursor goes to the nearest remaining action of the same
// group (the row that slid into its place, or the one before it when it was the last), else to the
// last action of the nearest earlier group, else it switches off. It never jumps forward into a
// later section: an Enter pressed out of habit must not run something the user was not looking at.
function resolve(targets, state) {
  if (!state.active) return state
  if (targets.length === 0) return initial()
  var at = indexOfKey(targets, state.key)
  if (at >= 0) return place(targets, at, state.source, state.goal)
  var inGroup = targets.filter(function(t) { return t.group === state.group })
  if (inGroup.length > 0) {
    var rows = []
    for (var i = 0; i < inGroup.length; i++) if (rows.indexOf(inGroup[i].row) < 0) rows.push(inGroup[i].row)
    var row = rows[Math.min(Math.max(state.groupRow, 0), rows.length - 1)]
    return place(targets, nearestInRow(targets, row, state.col, false), state.source, state.col)
  }
  for (var g = GROUPS.indexOf(state.group) - 1; g >= 0; g--) {
    var last = lastIndexOfGroup(targets, GROUPS[g])
    if (last >= 0) return place(targets, last, state.source)
  }
  return initial()
}

// An arrow press. The first one only switches the cursor on, at the first enabled action; later
// ones move between rows (dy) or along a row (dx), skipping disabled targets and stopping at the
// ends. The state's source becomes "keyboard" even when there is nowhere to go, so the highlighted
// action explains itself.
function move(targets, state, dx, dy) {
  var current = resolve(targets, state)
  if (!current.active) {
    for (var i = 0; i < targets.length; i++)
      if (targets[i].enabled) return place(targets, i, "keyboard")
    return current
  }
  var at = indexOfKey(targets, current.key)
  var row = targets[at].row
  if (dy !== 0) {
    var rows = targets[targets.length - 1].row
    for (var r = row + (dy > 0 ? 1 : -1); r >= 0 && r <= rows; r += dy > 0 ? 1 : -1) {
      var hit = nearestInRow(targets, r, current.goal, true)
      if (hit >= 0) return place(targets, hit, "keyboard", current.goal)
    }
  } else if (dx !== 0) {
    var step = dx > 0 ? 1 : -1
    var next = -1
    for (var k = 0; k < targets.length; k++) {
      var t = targets[k]
      if (t.row !== row || !t.enabled || (t.col - targets[at].col) * step <= 0) continue
      if (next < 0 || Math.abs(t.col - targets[at].col) < Math.abs(targets[next].col - targets[at].col)) next = k
    }
    if (next >= 0) return place(targets, next, "keyboard")
  }
  return place(targets, at, "keyboard", current.goal)
}

// The pointer entered a button: the one shared cursor moves there. An unknown key changes nothing.
function point(targets, state, key) {
  var at = indexOfKey(targets, key)
  return at < 0 ? state : place(targets, at, "pointer")
}

// The pointer left a button. A cursor the pointer put on that button goes off with it, so it does
// not stay lit where the pointer no longer is; a cursor the keyboard placed is left alone, and so
// is a cursor on any other button.
function leave(state, key) {
  return state.active && state.source === "pointer" && state.key === key ? initial() : state
}

// The key to run on Enter or Space: "" unless the cursor is on, on a target that exists, and that
// target is enabled.
function activate(targets, state) {
  var current = resolve(targets, state)
  if (!current.active) return ""
  var at = indexOfKey(targets, current.key)
  return at >= 0 && targets[at].enabled ? targets[at].key : ""
}

// The key whose button should explain itself: only a cursor the keyboard put there. Under the
// pointer the button shows its own tooltip, and one explanation at a time is enough.
function tipKey(state) {
  return state.active && state.source === "keyboard" ? state.key : ""
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {initial: initial, build: build, hasNotes: hasNotes, resolve: resolve, move: move,
    point: point, leave: leave, activate: activate, tipKey: tipKey}
}

const { test } = require("node:test");
const assert = require("node:assert");
const Cursor = require("../Cursor.js");

// Synthetic panel contents. Rows, top to bottom:
//   0 all            [all]
//   1 node           [tool:node]
//   2 python         [tool:python]
//   3 safe           [safe]
//   4 web            [notes, stack]
//   5 cache          [stack]            (no release notes)
//   6 db             [notes]            (already current, but notes are still reachable)
// "go" is current, "idle" is current with no notes: neither has an action.
const rowKey = (row) => row.targetId + "|" + row.name;

function input(over) {
  return Object.assign({
    all: { visible: true, enabled: true },
    tools: [
      { name: "node", outdated: true },
      { name: "go", outdated: false },
      { name: "python", outdated: true },
    ],
    toolsEnabled: true,
    safe: { visible: true, enabled: true },
    stacks: [
      { name: "web", targetId: "a", outdated: true, notesUrl: "https://example.invalid/web" },
      { name: "cache", targetId: "a", outdated: true, notesUrl: "" },
      { name: "db", targetId: "b", outdated: false, notesUrl: "https://example.invalid/db" },
      { name: "idle", targetId: "b", outdated: false, notesUrl: "" },
    ],
    stackEnabled: true,
  }, over || {});
}

const build = (over) => Cursor.build(input(over), rowKey);
const keys = (targets) => targets.map((t) => t.key);

// Press a sequence of moves from a state; each step is [dx, dy].
function press(targets, state, steps) {
  for (const [dx, dy] of steps) state = Cursor.move(targets, state, dx, dy);
  return state;
}
const on = (targets, key) => Cursor.point(targets, Cursor.initial(), key);

test("targets are the visible action buttons in reading order, with stable keys", () => {
  const targets = build();
  assert.deepStrictEqual(keys(targets), [
    "all", "tool:node", "tool:python", "safe",
    "notes:a|web", "stack:a|web", "stack:a|cache", "notes:b|db",
  ]);
  // Rows: one per tool, one per stack row; a row's actions share it.
  assert.deepStrictEqual(targets.map((t) => t.row), [0, 1, 2, 3, 4, 4, 5, 6]);
  assert.deepStrictEqual(targets.map((t) => t.col), [0, 0, 0, 0, 0, 1, 0, 0]);
  assert.deepStrictEqual(targets.map((t) => t.group),
    ["all", "tools", "tools", "safe", "stacks", "stacks", "stacks", "stacks"]);
  assert.ok(targets.every((t) => t.enabled === true));
});

test("hidden buttons are not targets", () => {
  assert.deepStrictEqual(keys(build({ all: { visible: false, enabled: false } })).slice(0, 2),
    ["tool:node", "tool:python"]);
  assert.ok(!keys(build({ safe: { visible: false, enabled: false } })).includes("safe"));
  assert.deepStrictEqual(keys(build({ tools: [{ name: "go", outdated: false }] })).slice(0, 2),
    ["all", "safe"]);
});

test("a target carries the same enabled state as its button", () => {
  const byKey = (targets) => Object.fromEntries(targets.map((t) => [t.key, t.enabled]));
  const busy = byKey(build({
    all: { visible: true, enabled: false }, toolsEnabled: false,
    safe: { visible: true, enabled: false }, stackEnabled: false,
  }));
  assert.strictEqual(busy["all"], false);
  assert.strictEqual(busy["tool:node"], false);
  assert.strictEqual(busy["safe"], false);
  assert.strictEqual(busy["stack:a|web"], false);
  // Release notes are not gated by a running update.
  assert.strictEqual(busy["notes:a|web"], true);
});

test("hasNotes is the test the panel uses to show the release-notes button", () => {
  assert.strictEqual(Cursor.hasNotes({ notesUrl: "https://example.invalid/x" }), true);
  assert.strictEqual(Cursor.hasNotes({ notesUrl: "" }), false);
  assert.strictEqual(Cursor.hasNotes({}), false);
  assert.strictEqual(Cursor.hasNotes(null), false);
});

test("a service name on two hosts gets two keys", () => {
  const targets = build({ stacks: [
    { name: "redis", targetId: "a", outdated: true, notesUrl: "" },
    { name: "redis", targetId: "b", outdated: true, notesUrl: "" },
  ] });
  assert.deepStrictEqual(keys(targets).slice(-2), ["stack:a|redis", "stack:b|redis"]);
});

test("nothing to act on builds an empty list, and tolerates missing input", () => {
  const empty = Cursor.build({ all: { visible: false }, tools: [], safe: { visible: false }, stacks: [] }, rowKey);
  assert.deepStrictEqual(empty, []);
  assert.deepStrictEqual(Cursor.build(null, rowKey), []);
  assert.deepStrictEqual(Cursor.build({}, rowKey), []);
  assert.deepStrictEqual(Cursor.build({ stacks: [{ name: "x", targetId: "a", outdated: true, notesUrl: "" }] }, null), []);
});

test("the cursor starts inactive and Enter does nothing until an arrow has been pressed", () => {
  const targets = build();
  const state = Cursor.initial();
  assert.strictEqual(state.active, false);
  assert.strictEqual(Cursor.activate(targets, state), "");
  assert.strictEqual(Cursor.tipKey(state), "");
});

test("a switched-off state never activates, whatever key it still carries", () => {
  const targets = build();
  const stale = { active: false, key: "tool:node", group: "tools", groupRow: 0, col: 0, goal: 0, source: "keyboard" };
  assert.strictEqual(Cursor.activate(targets, stale), "");
  assert.strictEqual(Cursor.resolve(targets, stale), stale);
});

test("the first move only activates the cursor, on the first enabled target, without moving", () => {
  const targets = build();
  for (const [dx, dy] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
    const state = Cursor.move(targets, Cursor.initial(), dx, dy);
    assert.strictEqual(state.active, true, `move ${dx},${dy}`);
    assert.strictEqual(state.key, "all", `move ${dx},${dy}`);
  }
  // Skips a disabled first target.
  const skipped = Cursor.move(build({ all: { visible: true, enabled: false } }), Cursor.initial(), 0, 1);
  assert.strictEqual(skipped.key, "tool:node");
  // Nothing enabled: the cursor stays off rather than sitting on a dead button.
  const dead = build({
    all: { visible: true, enabled: false }, toolsEnabled: false, safe: { visible: true, enabled: false },
    stackEnabled: false, stacks: [{ name: "web", targetId: "a", outdated: true, notesUrl: "" }],
  });
  assert.strictEqual(Cursor.move(dead, Cursor.initial(), 0, 1).active, false);
});

test("Enter after the first arrow runs the highlighted target", () => {
  const targets = build();
  let state = Cursor.move(targets, Cursor.initial(), 0, 1);
  assert.strictEqual(Cursor.activate(targets, state), "all");
  state = Cursor.move(targets, state, 0, 1);
  assert.strictEqual(Cursor.activate(targets, state), "tool:node");
});

test("up and down move between rows and clamp at the ends", () => {
  const targets = build();
  let state = Cursor.move(targets, Cursor.initial(), 0, 1);
  state = press(targets, state, [[0, -1], [0, -1]]);
  assert.strictEqual(state.key, "all", "up at the top stays");
  state = press(targets, state, [[0, 1], [0, 1], [0, 1], [0, 1]]);
  assert.strictEqual(state.key, "notes:a|web", "four rows down");
  state = press(targets, state, [[0, 1], [0, 1], [0, 1], [0, 1], [0, 1]]);
  assert.strictEqual(state.key, "notes:b|db", "down at the bottom stays, no wrap");
});

test("left and right move between the actions in a row and clamp", () => {
  const targets = build();
  let state = on(targets, "notes:a|web");
  state = Cursor.move(targets, state, 1, 0);
  assert.strictEqual(state.key, "stack:a|web");
  state = Cursor.move(targets, state, 1, 0);
  assert.strictEqual(state.key, "stack:a|web", "right at the end of a row stays");
  state = press(targets, state, [[-1, 0], [-1, 0]]);
  assert.strictEqual(state.key, "notes:a|web", "left at the start of a row stays");
  // A single-action row has nowhere to go sideways.
  state = on(targets, "tool:node");
  assert.strictEqual(Cursor.move(targets, state, 1, 0).key, "tool:node");
  assert.strictEqual(Cursor.move(targets, state, -1, 0).key, "tool:node");
});

test("vertical moves keep the column the user chose, like an editor's goal column", () => {
  const targets = build();
  let state = on(targets, "stack:a|web");
  state = Cursor.move(targets, state, 0, 1);
  assert.strictEqual(state.key, "stack:a|cache", "a one-action row clamps");
  state = Cursor.move(targets, state, 0, -1);
  assert.strictEqual(state.key, "stack:a|web", "and the second column comes back");
  // Moving sideways picks a new column.
  state = press(targets, state, [[-1, 0], [0, 1]]);
  assert.strictEqual(state.key, "stack:a|cache");
  state = Cursor.move(targets, state, 0, -1);
  assert.strictEqual(state.key, "notes:a|web");
});

test("moves are in reading order: +1 is the next action along the row", () => {
  // PanelKeyCatcher swaps dx in a right-to-left panel before it emits moveRequested, and the row
  // lays its buttons out in the same mirrored order, so the cursor only ever sees reading order.
  const targets = build();
  const forward = Cursor.move(targets, on(targets, "notes:a|web"), 1, 0);
  const backward = Cursor.move(targets, on(targets, "stack:a|web"), -1, 0);
  assert.strictEqual(forward.key, "stack:a|web");
  assert.strictEqual(backward.key, "notes:a|web");
});

test("navigation skips disabled targets", () => {
  // The upgrade buttons are busy; release notes stay reachable.
  const busy = build({
    all: { visible: true, enabled: false }, toolsEnabled: false,
    safe: { visible: true, enabled: false }, stackEnabled: false,
  });
  let state = Cursor.move(busy, Cursor.initial(), 0, 1);
  assert.strictEqual(state.key, "notes:a|web", "only an enabled target takes the first press");
  state = Cursor.move(busy, state, 1, 0);
  assert.strictEqual(state.key, "notes:a|web", "the disabled update button is skipped sideways");
  state = Cursor.move(busy, state, 0, 1);
  assert.strictEqual(state.key, "notes:b|db", "disabled rows are skipped downward");
  state = Cursor.move(busy, state, 0, -1);
  assert.strictEqual(state.key, "notes:a|web", "and upward");
  state = Cursor.move(busy, state, 0, -1);
  assert.strictEqual(state.key, "notes:a|web", "nothing enabled above, so it stays");
});

test("a disabled target never activates, and the key is kept until it is enabled again", () => {
  let targets = build();
  let state = on(targets, "tool:python");
  assert.strictEqual(Cursor.activate(targets, state), "tool:python");
  // An upgrade starts: every upgrade button is disabled.
  targets = build({ all: { visible: true, enabled: false }, toolsEnabled: false });
  state = Cursor.resolve(targets, state);
  assert.strictEqual(state.active, true);
  assert.strictEqual(state.key, "tool:python", "the key survives being disabled");
  assert.strictEqual(Cursor.activate(targets, state), "", "activation is a no-op meanwhile");
  // It finishes and the button is back.
  targets = build();
  state = Cursor.resolve(targets, state);
  assert.strictEqual(state.key, "tool:python");
  assert.strictEqual(Cursor.activate(targets, state), "tool:python");
  // Still disabled, and a tool above it appears: the key is followed, not the row position.
  targets = build({
    all: { visible: true, enabled: false }, toolsEnabled: false,
    tools: [{ name: "go", outdated: true }, { name: "node", outdated: true }, { name: "python", outdated: true }],
  });
  state = Cursor.resolve(targets, state);
  assert.strictEqual(state.key, "tool:python", "a disabled key is followed to its new row");
});

test("the cursor can leave a disabled target", () => {
  const busy = build({ toolsEnabled: false });
  let state = on(busy, "tool:node");
  assert.strictEqual(Cursor.move(busy, state, 0, 1).key, "safe", "down skips the disabled tool row");
  assert.strictEqual(Cursor.move(busy, state, 0, -1).key, "all");
});

test("a refresh keeps the cursor on the same action even when it moves", () => {
  let targets = build();
  let state = on(targets, "stack:a|cache");
  // The new rows push it down: a tool and a stack row appear above it.
  targets = build({
    tools: [{ name: "go", outdated: true }, { name: "node", outdated: true }, { name: "python", outdated: true }],
    stacks: [{ name: "api", targetId: "a", outdated: true, notesUrl: "" },
      { name: "web", targetId: "a", outdated: true, notesUrl: "https://example.invalid/web" },
      { name: "cache", targetId: "a", outdated: true, notesUrl: "" }],
  });
  state = Cursor.resolve(targets, state);
  assert.strictEqual(state.key, "stack:a|cache");
  assert.strictEqual(state.active, true);
});

test("when the highlighted tool is gone the cursor takes the tool that slid into its place", () => {
  const three = build({ tools: [
    { name: "node", outdated: true }, { name: "python", outdated: true }, { name: "ruby", outdated: true }] });
  const without = (name) => build({ tools: [
    { name: "node", outdated: true }, { name: "python", outdated: true }, { name: "ruby", outdated: true }]
    .filter((t) => t.name !== name) });
  assert.strictEqual(Cursor.resolve(without("python"), on(three, "tool:python")).key, "tool:ruby");
  assert.strictEqual(Cursor.resolve(without("ruby"), on(three, "tool:ruby")).key, "tool:python", "the last one falls back to the one before");
  assert.strictEqual(Cursor.resolve(without("node"), on(three, "tool:node")).key, "tool:python");
});

test("when its whole group is gone the cursor falls back to the previous group, else off", () => {
  const withTool = build({ tools: [{ name: "node", outdated: true }] });
  const gone = build({ tools: [] });
  // "Update all" is still there: fall back to it.
  const back = Cursor.resolve(gone, on(withTool, "tool:node"));
  assert.strictEqual(back.active, true);
  assert.strictEqual(back.key, "all");
  // Nothing precedes the tools: the cursor switches off instead of jumping to the next section.
  const noAll = build({ all: { visible: false, enabled: false }, tools: [] });
  const noAllBefore = build({ all: { visible: false, enabled: false }, tools: [{ name: "node", outdated: true }] });
  const off = Cursor.resolve(noAll, on(noAllBefore, "tool:node"));
  assert.strictEqual(off.active, false);
  assert.strictEqual(Cursor.activate(noAll, off), "");
});

test("a stack row that vanishes hands the cursor to the neighbouring row, same action", () => {
  const rows = (names) => names.map((n) => ({ name: n, targetId: "a", outdated: true, notesUrl: "https://example.invalid/" + n }));
  const three = build({ stacks: rows(["a1", "b2", "c3"]) });
  const withoutMiddle = build({ stacks: rows(["a1", "c3"]) });
  let state = on(three, "stack:a|b2");
  state = Cursor.resolve(withoutMiddle, state);
  assert.strictEqual(state.key, "stack:a|c3");
  const withoutLast = build({ stacks: rows(["a1", "b2"]) });
  state = Cursor.resolve(withoutLast, on(three, "notes:a|c3"));
  assert.strictEqual(state.key, "notes:a|b2");
});

test("no targets at all switches the cursor off, and it comes back on the next arrow", () => {
  const targets = build();
  const none = Cursor.build({}, rowKey);
  let state = on(targets, "tool:node");
  state = Cursor.resolve(none, state);
  assert.strictEqual(state.active, false);
  assert.strictEqual(Cursor.activate(none, state), "");
  assert.strictEqual(Cursor.move(none, state, 0, 1).active, false);
  assert.strictEqual(Cursor.move(targets, state, 0, 1).key, "all");
});

test("a pointer on a button moves the cursor there; keyboard keeps its tooltip, pointer does not", () => {
  const targets = build();
  let state = Cursor.point(targets, Cursor.initial(), "tool:python");
  assert.strictEqual(state.active, true);
  assert.strictEqual(state.key, "tool:python");
  assert.strictEqual(state.source, "pointer");
  assert.strictEqual(Cursor.tipKey(state), "", "the button shows its own tooltip under the pointer");
  state = Cursor.move(targets, state, 0, 1);
  assert.strictEqual(state.key, "safe");
  assert.strictEqual(Cursor.tipKey(state), "safe", "the keyboard cursor explains the action it is on");
  assert.strictEqual(Cursor.point(targets, state, "no-such-key"), state, "an unknown key changes nothing");
});

test("an arrow that cannot move still hands the tooltip to the keyboard", () => {
  const targets = build();
  let state = Cursor.point(targets, Cursor.initial(), "all");
  state = Cursor.move(targets, state, 0, -1);
  assert.strictEqual(state.key, "all");
  assert.strictEqual(Cursor.tipKey(state), "all");
});

test("activate only reports a target that exists and is enabled", () => {
  const targets = build();
  const state = on(targets, "stack:a|web");
  assert.strictEqual(Cursor.activate(targets, state), "stack:a|web");
  assert.strictEqual(Cursor.activate([], state), "");
  assert.strictEqual(Cursor.activate(build({ stackEnabled: false }), state), "");
});

test("states are plain data and moves do not mutate their input", () => {
  const targets = build();
  const before = JSON.stringify(Cursor.initial());
  const state = Cursor.initial();
  Cursor.move(targets, state, 0, 1);
  assert.strictEqual(JSON.stringify(state), before);
  const snapshot = JSON.stringify(targets);
  Cursor.move(targets, on(targets, "all"), 0, 1);
  assert.strictEqual(JSON.stringify(targets), snapshot);
});

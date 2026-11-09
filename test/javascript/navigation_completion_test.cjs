const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

test("completed navigation stops Turbo timers and late bars; new visits and previews stay pending", () => {
  const source = fs.readFileSync("app/javascript/navigation_progress.js", "utf8").replace(/import .*;\n/, "");
  const listeners = {};
  const attributes = new Set();
  let removed = 0;
  let hidden = 0;
  const document = {
    readyState: "loading",
    documentElement: { hasAttribute: (name) => attributes.has(name),
      setAttribute: (name) => attributes.add(name), removeAttribute: (name) => attributes.delete(name) },
    querySelectorAll: () => [{ remove: () => removed++ }],
    addEventListener: (name, callback) => listeners[name] = callback
  };
  const Turbo = { navigator: { currentVisit: { state: "started" } }, session: { adapter: {
    hideVisitProgressBar: () => hidden++, hideFormProgressBar: () => hidden++
  } } };
  vm.runInNewContext(source, { document, Turbo, window: { addEventListener: (name, callback) => listeners[name] = callback } });
  listeners["turbo:visit"]();
  attributes.add("data-turbo-preview");
  listeners["turbo:render"]();
  assert.equal(removed, 0);
  assert.equal(hidden, 0);
  attributes.delete("data-turbo-preview");
  listeners["turbo:render"]();
  assert.equal(hidden, 2);
  assert.equal(removed, 1);
  assert.ok(attributes.has("data-navigation-complete"));
  listeners["turbo:visit"]();
  assert.ok(!attributes.has("data-navigation-complete"));
  Turbo.navigator.currentVisit.state = "completed";
  listeners["turbo:load"]();
  listeners["turbo:submit-start"]();
  assert.ok(!attributes.has("data-navigation-complete"));
  Turbo.navigator = { currentVisit: { state: "started" } };
  listeners["turbo:submit-end"]();
  assert.ok(!attributes.has("data-navigation-complete"));
  listeners.DOMContentLoaded();
  assert.ok(!attributes.has("data-navigation-complete"), "A late initial-ready event must not hide a newer pending visit");
  listeners["turbo:load"]();
  assert.ok(!attributes.has("data-navigation-complete"), "An older load completion must not hide the current visit");
  listeners.pageshow({ persisted: false });
  assert.ok(!attributes.has("data-navigation-complete"));
  listeners.pageshow({ persisted: true });
  assert.ok(attributes.has("data-navigation-complete"), "Restored browser pages must clear stale indicator state");
  listeners["turbo:visit"]();
  Turbo.navigator.currentVisit.state = "completed";
  listeners["turbo:submit-end"]();
  assert.ok(attributes.has("data-navigation-complete"));
  listeners.pageshow();
  assert.equal(removed, 5);
});

test("a cancelled preview clears its stale bar after a fetch failure without hiding an active visit", () => {
  const source = fs.readFileSync("app/javascript/navigation_progress.js", "utf8").replace(/import .*;\n/, "");
  const listeners = {};
  const attributes = new Set(["data-turbo-preview"]);
  let deferred;
  let removed = 0;
  const Turbo = { navigator: { currentVisit: { state: "started" } } };
  const document = { readyState: "loading", documentElement: {
    hasAttribute: (name) => attributes.has(name), setAttribute: (name) => attributes.add(name),
    removeAttribute: (name) => attributes.delete(name)
  }, addEventListener: (name, callback) => listeners[name] = callback,
  querySelectorAll: () => [{ remove: () => removed++ }] };
  vm.runInNewContext(source, { document, Turbo, setTimeout: (callback) => deferred = callback,
    window: { addEventListener() {} } });
  listeners["turbo:fetch-request-error"]();
  deferred();
  assert.equal(removed, 0);
  Turbo.navigator.currentVisit.state = "canceled";
  listeners["turbo:fetch-request-error"]();
  deferred();
  assert.equal(removed, 1);
  assert.ok(attributes.has("data-navigation-complete"));
});

test("password visibility and labels stay in sync and navigation does not duplicate bindings", () => {
  const source = fs.readFileSync("app/javascript/password_toggles.js", "utf8").replace(/export \{ initPasswordToggles \};/, "");
  const input = { type: "password" };
  let click;
  let bindings = 0;
  const button = { dataset: {}, closest: () => ({ querySelector: () => input }),
    addEventListener: (_, handler) => { click = handler; bindings++; },
    setAttribute: (_, label) => button.label = label, classList: { toggle() {} } };
  vm.runInNewContext(source + "\ninitPasswordToggles(); initPasswordToggles();", {
    document: { querySelectorAll: () => [button] }
  });
  assert.equal(bindings, 1);
  click();
  assert.equal(input.type, "text");
  assert.equal(button.label, "Hide password");
  click();
  assert.equal(input.type, "password");
  assert.equal(button.label, "Show password");
});

test("edit works before deferred setup and on restored pages with the same selection rules", () => {
  const source = fs.readFileSync("app/javascript/layout.js", "utf8");
  const start = source.indexOf("// Bind before deferred");
  const end = source.indexOf("const initFastNavigation", start);
  let click;
  let change;
  let selected = [];
  const alerts = [];
  const window = { location: { href: "" }, alert: (message) => alerts.push(message) };
  const document = {
    addEventListener: (name, callback) => { if (name === "click") click = callback; else change = callback; },
    querySelectorAll: () => selected
  };
  vm.runInNewContext(source.slice(start, end), { document, window });
  const event = { target: { closest: () => ({}) }, preventDefault() {} };
  click(event);
  assert.equal(alerts.pop(), "Please select one record only");
  selected = [{ value: "/modules/training-form/12/edit" }];
  click(event);
  assert.equal(window.location.href, selected[0].value);
  selected = [{ value: "/modules/other-target/20/edit" }];
  click(event);
  assert.equal(window.location.href, selected[0].value);
  selected.push({ value: "/modules/other-target/21/edit" });
  click(event);
  assert.equal(alerts.pop(), "Please select one record only");
  assert.equal(window.location.href, "/modules/other-target/20/edit");
  assert.equal(source.includes('moduleEditButton.addEventListener'), false);
  const selectAll = { matches: () => true, checked: true };
  change({ target: selectAll });
  assert.ok(selected.every((checkbox) => checkbox.checked));
  selectAll.checked = false;
  change({ target: selectAll });
  assert.ok(selected.every((checkbox) => !checkbox.checked));
});

test("JJ edit and Select All also work before deferred setup with their original URLs and alerts", () => {
  const source = fs.readFileSync("app/javascript/layout.js", "utf8");
  const start = source.indexOf("// Bind before deferred");
  const end = source.indexOf("const initFastNavigation", start);
  const listeners = {};
  const rows = [{ value: "7" }, { value: "10" }];
  let selected = [];
  const alerts = [];
  const window = { location: {}, alert: (message) => alerts.push(message) };
  const document = {
    addEventListener: (name, callback) => { listeners[name] = callback; },
    querySelectorAll: (selector) => selector.includes(":checked") ? selected : rows
  };
  vm.runInNewContext(source.slice(start, end), { document, window,
    replaceVrpUiText: (value) => value.replace(/VRP/g, "Jeevika Jankar") });
  const event = { target: { closest: () => ({ matches: () => true }) }, preventDefault() {} };
  listeners.click(event);
  assert.equal(alerts.pop(), "Please select one Jeevika Jankar only");
  selected = [rows[1]];
  listeners.click(event);
  assert.equal(window.location.href, "/vrps/10/edit");
  listeners.change({ target: { matches: (selector) => selector === "[data-vrp-select-all]", checked: true } });
  assert.ok(rows.every((row) => row.checked));
  assert.equal(source.includes('editButton.addEventListener("click"'), false);
});

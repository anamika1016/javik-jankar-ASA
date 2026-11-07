const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

test("list actions work before deferred setup and bind once per live or restored body", async () => {
  const source = fs.readFileSync("app/javascript/layout.js", "utf8");
  const start = source.indexOf("const listActionBodies =");
  const end = source.indexOf("const initFastNavigation =", start);
  let click;
  let bindings = 0;
  let reloads = 0;
  const requests = [];
  const button = { addEventListener: (_, handler) => { bindings++; click = handler; } };
  const document = {
    body: {}, getElementById: () => null,
    querySelector: (selector) => selector === "[data-vrp-delete-selected]" ? button :
      selector.startsWith("meta[") ? { content: "csrf" } : null,
    querySelectorAll: (selector) => selector === "[data-vrp-row-select]:checked" ? [{ value: "7" }] : []
  };
  const context = { document, replaceVrpUiText: (text) => text,
    window: { confirm: () => true, alert: (message) => assert.fail(message), location: { reload: () => reloads++ } },
    fetch: async (path, options) => { requests.push([path, options]); return { ok: false, type: "opaqueredirect" }; }
  };
  vm.runInNewContext(source.slice(start, end) + "\nthis.boot = initListActions;", context);
  context.boot();
  context.boot();
  assert.equal(bindings, 1);
  await click();
  // The click callback starts an async deletion without returning its promise.
  await new Promise(setImmediate);
  assert.equal(requests[0][0], "/vrps/7");
  assert.equal(requests[0][1].headers["X-CSRF-Token"], "csrf");
  assert.equal(reloads, 1);
  document.body = {};
  context.boot();
  assert.equal(bindings, 2);
  const boot = source.slice(source.indexOf("const bootLayoutPage ="), source.indexOf("const queueBootLayoutPage ="));
  assert.ok(boot.indexOf("initListActions();") < boot.indexOf("scheduleDeferredLayoutInit();"));
});

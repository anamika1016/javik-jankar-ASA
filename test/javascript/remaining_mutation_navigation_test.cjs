const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

for (const [name, startMarker, endMarker] of [
  ["JJ send", "  const vrpSendButton =", '  document.querySelectorAll("[data-vrp-active-selected]")'],
  ["module status", '  document.querySelectorAll("[data-module-status-selected]")', '  document.querySelectorAll("[data-user-status-selected]")'],
  ["user status", '  document.querySelectorAll("[data-user-status-selected]")', "  // End list action bindings."]
]) {
  test(`${name} reloads once after a redirect and retains HTTP failure handling`, async () => {
    const source = fs.readFileSync("app/javascript/layout.js", "utf8");
    const start = source.indexOf(startMarker);
    const end = source.indexOf(endMarker, start);
    let action;
    let response = { ok: false, type: "opaqueredirect" };
    let reloads = 0;
    const alerts = [];
    const requests = [];
    const button = { dataset: { moduleStatusSelected: "Active", userStatusSelected: "Active" },
      addEventListener: (_, callback) => { action = callback; } };
    const row = { value: "/users/12/edit" };
    vm.runInNewContext(source.slice(start, end), {
      csrfToken: "csrf", replaceVrpUiText: (text) => text, moduleRowPaths: (checkbox) => [checkbox.value],
      document: { querySelector: () => button,
        querySelectorAll: (selector) => selector.includes(":checked") ? [row] : [button] },
      window: { alert: (message) => alerts.push(message), location: { reload: () => reloads++ } },
      fetch: async (path, options) => { requests.push([path, options]); return response; }
    });
    await action();
    assert.equal(reloads, 1);
    assert.equal(alerts.length, 0);
    assert.equal(requests[0][1].redirect, "manual");
    assert.equal(requests[0][1].headers["X-CSRF-Token"], "csrf");
    response = { ok: false, type: "basic", status: 403 };
    await action();
    assert.equal(reloads, 1);
    assert.equal(alerts.length, 1);
  });
}

test("AFL bulk deletion avoids downloading its redirected list before the visible reload", async () => {
  const source = fs.readFileSync("app/javascript/layout.js", "utf8");
  const start = source.indexOf("      if (bulkSelectAll) {");
  const end = source.indexOf("      const paths = aflRows()", start);
  const requests = [];
  let reloads = 0;
  const context = {
    bulkSelectAll: true, csrfToken: "csrf", URL, aflSelectAllKey: () => "selection",
    aflDeleteButton: { dataset: { aflBulkDestroyUrl: "/afls/bulk_destroy" } },
    aflQueryInput: { value: "Farmer" }, sessionStorage: { removeItem() {} },
    window: { confirm: () => true, alert: () => assert.fail("Unexpected failure"),
      location: { origin: "http://example.test", reload: () => reloads++ } },
    fetch: async (url, options) => { requests.push([url, options]); return { ok: false, type: "opaqueredirect" }; }
  };
  vm.runInNewContext(`this.run = async () => { ${source.slice(start, end)} };`, context);
  await context.run();
  assert.equal(reloads, 1);
  assert.equal(requests[0][1].redirect, "manual");
  assert.equal(requests[0][0].searchParams.get("q"), "Farmer");
});

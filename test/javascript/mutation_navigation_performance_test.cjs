const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

for (const [name, endMarker] of [
  ["deleteSelected", "  const vrpDeleteButton"],
  ["patchBillRows", '  document.querySelector("[data-bill-send-selected]")']
]) {
  test(`${name} skips redirect page downloads and reloads once while retaining error handling`, async () => {
    const source = fs.readFileSync("app/javascript/layout.js", "utf8");
    const start = source.indexOf(`  const ${name} =`);
    const end = source.indexOf(endMarker, start);
    const requests = [];
    const alerts = [];
    let reloads = 0;
    let response = { ok: false, type: "opaqueredirect" };
    const context = {
      csrfToken: "csrf", window: { confirm: () => true, alert: (message) => alerts.push(message),
        location: { reload: () => reloads++ } },
      fetch: async (path, options) => { requests.push([path, options]); return response; }
    };
    vm.runInNewContext(source.slice(start, end) + `\nthis.mutate = ${name};`, context);
    await context.mutate(["/records/1", "/records/2"], "Select records");
    assert.equal(reloads, 1);
    assert.equal(alerts.length, 0);
    assert.equal(requests.length, 2);
    assert.ok(requests.every(([, options]) => options.redirect === "manual"));
    assert.ok(requests.every(([, options]) => options.headers["X-CSRF-Token"] === "csrf"));
    response = { ok: false, type: "basic", status: 403 };
    await context.mutate(["/records/3"], "Select records");
    assert.equal(reloads, 1);
    assert.equal(alerts.length, 1);
    await context.mutate([], "Select records");
    assert.equal(requests.length, 3);
    assert.equal(reloads, 1);
  });
}

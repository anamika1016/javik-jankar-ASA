const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync("app/javascript/layout.js", "utf8");

test("bill placeholder stays empty instead of becoming a JJ name", () => {
  const start = source.indexOf("const selectedVrpValue = () => {");
  const end = source.indexOf("    if (!billForm.dataset.originalVrpOptions)", start);
  const context = vm.createContext({
    vrpSelect: { selectedIndex: 0, value: "Select Jeevika Jankar Name" },
    originalVrpOptions: []
  });
  vm.runInContext(source.slice(start, end) + "\nthis.selectedVrpValue = selectedVrpValue;", context);
  assert.equal(context.selectedVrpValue(), "");
  context.vrpSelect = { selectedIndex: 1, value: "165" };
  assert.equal(context.selectedVrpValue(), "165");
});

test("concurrent bill fetches share a request and failures can retry", async () => {
  const start = source.indexOf("const loadBillRowsForSelection = async");
  const end = source.indexOf("    const renderJeevikaBillRows", start);
  let requests = 0;
  let resolve;
  let fail = false;
  const context = vm.createContext({
    billRowsCache: new Map(), pendingBillRows: new Map(), billRows: [],
    billRowsUrl: "/bill_rows", achievementSummary: {}, targetSummary: {}, URL,
    window: { location: { origin: "https://example.test" } },
    normalizedMonth: (month) => month.trim().toLowerCase(),
    billRowsKey: (id, month) => `${id}|${month.trim().toLowerCase()}`,
    fetchJson: () => {
      requests++;
      if (fail) return Promise.reject(new Error("Failed"));
      return new Promise((done) => { resolve = done; });
    }
  });
  vm.runInContext(source.slice(start, end) + "\nthis.loadRows = loadBillRowsForSelection;", context);
  const first = context.loadRows("165", "September");
  const second = context.loadRows("165", "September");
  assert.equal(requests, 1);
  resolve({ rows: [{ target_mapping_id: "42" }] });
  const [a, b] = await Promise.all([first, second]);
  assert.equal(a, b);
  assert.equal(await context.loadRows("165", "September"), a);
  assert.equal(requests, 1);
  fail = true;
  await assert.rejects(context.loadRows("165", "October"));
  fail = false;
  const retry = context.loadRows("165", "October");
  resolve({ rows: [] });
  await retry;
  assert.equal(requests, 3);
  assert.equal(context.pendingBillRows.size, 0);
});

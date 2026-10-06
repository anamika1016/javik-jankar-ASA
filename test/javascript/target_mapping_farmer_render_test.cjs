const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('    const renderTargetFarmers =');
const end = source.indexOf('    const loadTargetData =', start);
const helperStart = source.indexOf('const farmerIdentityMeta =');
const helperEnd = source.indexOf('\n\n', helperStart);

for (const mode of ['ics_wise', 'block_wise']) {
  test(`${mode}: returned farmers render with identity details and trigger count refresh`, () => {
    assert.ok(helperStart >= 0, 'farmer identity helper must exist');
    assert.ok(start >= 0 && end > start);
    let refreshes = 0;
    const list = { innerHTML: '', querySelectorAll: () => [] };
    const context = vm.createContext({ farmerPanel: {}, farmerList: list, farmerSearchEmpty: {},
      editTarget: {}, escapeHtml: (value) => String(value ?? ''), applyTargetFarmerSearch() {},
      updateTargetFarmerCount() { refreshes += 1; } });
    vm.runInContext(source.slice(helperStart, helperEnd) + '\n' + source.slice(start, end) + '\nthis.render = renderTargetFarmers;', context);
    context.render([{ id: '12', farmer_name: 'Test Farmer', village_name: 'Village One', father_name: 'Test Father', tracenet_no: 'TRACE12', selected: true }]);
    assert.match(list.innerHTML, /Test Farmer/);
    assert.match(list.innerHTML, /Village: Village One/);
    assert.match(list.innerHTML, /Father: Test Father/);
    assert.match(list.innerHTML, /Tracenet: TRACE12/);
    assert.match(list.innerHTML, /value="12".* checked/);
    assert.equal(refreshes, 1);
  });
}

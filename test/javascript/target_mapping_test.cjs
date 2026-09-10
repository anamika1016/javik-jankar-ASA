const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const extract = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

test('only activity selects are required and manual mode preserves their selections', () => {
  let manual = false;
  const select = { tagName: 'SELECT', options: [{ selected: true }], dispatchEvent() {}, setCustomValidity() {} };
  const checkbox = { tagName: 'INPUT', type: 'checkbox', setCustomValidity() {} };
  const search = { tagName: 'INPUT', type: 'search', setCustomValidity() {} };
  const field = { classList: { remove() {} }, querySelectorAll: () => [select, checkbox, search] };
  const context = vm.createContext({
    targetInput: { setCustomValidity() {} }, newFarmerTargetMode: () => manual,
    villageTargetMode: () => false, mainActivityField: field, subActivityField: null,
    mainActivitySelect: select, subActivitySelect: null, Event: class {}
  });
  vm.runInContext(extract('    const syncNewFarmerTargetMode =', '    const locationValueParts =') + '\nthis.sync = syncNewFarmerTargetMode;', context);
  context.sync();
  assert.equal(select.required, true);
  assert.equal(checkbox.required, false);
  assert.equal(search.required, false);
  manual = true;
  context.sync();
  assert.equal(select.disabled, false);
  assert.equal(select.options[0].selected, true);
  manual = false;
  context.sync();
  assert.equal(select.disabled, false);
  assert.equal(select.options[0].selected, true);
});

test('counts use cached results and ignore responses after villages are cleared', async () => {
  let villages = ['1'];
  let calls = 0;
  let resolve;
  const input = {};
  const context = vm.createContext({
    targetBlockWiseMode: () => true, shell: { dataset: { villageFarmersUrl: '/count' } },
    targetSelectedValues: () => villages, villageSelect: {}, registeredCountInput: input,
    fetchJson: () => { calls++; return new Promise((done) => { resolve = done; }); }
  });
  vm.runInContext('let targetCountRequestId = 0;\n' + extract('    const targetFarmerCountCache =', '    const renderTargetFarmers =') + '\nthis.load = loadTargetFarmerCount;', context);
  const first = context.load();
  resolve({ count: 199 });
  await first;
  assert.equal(input.value, '199');
  await context.load();
  assert.equal(calls, 1);
  villages = ['2'];
  const pending = context.load();
  villages = [];
  await context.load();
  resolve({ count: 99 });
  await pending;
  assert.equal(input.value, '0');
});

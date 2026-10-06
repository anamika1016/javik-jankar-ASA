const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('    const loadTargetData =');
const end = source.indexOf('\n    farmerSelectAll?.addEventListener', start);
function setup() {
  const calls = [], rendered = [];
  const context = vm.createContext({ URL, window: { location: { origin: 'https://example.test' } },
    shell: { dataset: { mappingsUrl: '/mappings', villageFarmersUrl: '/farmers' } },
    vrpSelect: null, fcoSelect: null, blockSelect: { value: '42||Block' },
    villageSelect: {}, targetEntryModeSelect: { value: 'block_wise' },
    monthSelect: null, mainActivitySelect: null, subActivitySelect: null, targetTypeSelect: null,
    editTarget: {}, targetLoadRequestId: 0, selectedTargetIcsValue: () => '42||Block',
    targetSelectedValues: (select) => select ? ['8562||Village'] : [],
    targetBlockWiseMode: () => true, loadTargetFarmerCount() {},
    fetchJson: async (url, params) => { calls.push({ url, params }); return { farmers: [{ id: 'f1' }] }; },
    fetch: () => { throw new Error('Location reload must not interrupt farmer loading'); },
    renderTargetFarmers: (farmers) => rendered.push(farmers),
    clearTargetFarmers: () => { throw new Error('Selection should remain intact'); }, console });
  vm.runInContext(source.slice(start, end) + '\nthis.load = loadTargetData;', context);
  return { context, calls, rendered };
}
test('Block Wise loads selected village farmers without reloading location options', async () => {
  const { context, calls, rendered } = setup();
  await context.load();
  assert.equal(calls[0].url, '/farmers');
  assert.equal(calls[0].params.data_type, 'detail');
  assert.equal(calls[0].params.village_ids, '["8562||Village"]');
  assert.equal(rendered[0][0].id, 'f1');
});
test('Block Wise ignores a farmer response after a newer selection request', async () => {
  const { context, rendered } = setup();
  let resolve;
  context.fetchJson = () => new Promise((done) => { resolve = done; });
  const pending = context.load();
  context.targetLoadRequestId += 1;
  resolve({ farmers: [{ id: 'old' }] });
  await pending;
  assert.equal(rendered.length, 0);
});

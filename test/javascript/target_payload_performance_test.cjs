const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('const unpackTrainingTargetMappings =');
const end = source.indexOf('// Delegation keeps Delete', start);
const context = {};
vm.runInNewContext(`${source.slice(start, end)}\nthis.unpack = unpackTrainingTargetMappings;`, context);

test('compact target farmer payload expands to the legacy mapping shape', () => {
  const payload = {
    farmers: [
      { id: '1', farmer_name: 'Shared Farmer' },
      { id: '2', farmer_name: 'Second Farmer' }
    ],
    mappings: [
      { target_mapping_id: '10', farmer_indexes: [0, 1] },
      { target_mapping_id: '11', farmer_indexes: [0] }
    ]
  };

  assert.deepEqual(JSON.parse(JSON.stringify(context.unpack(payload))), [
    { target_mapping_id: '10', farmers: payload.farmers },
    { target_mapping_id: '11', farmers: [payload.farmers[0]] }
  ]);
});

test('legacy array payload remains unchanged', () => {
  const mappings = [{ target_mapping_id: '10', farmers: [{ id: '1' }] }];
  assert.equal(context.unpack(mappings), mappings);
});

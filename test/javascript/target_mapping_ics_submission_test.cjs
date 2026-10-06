const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const begin = source.indexOf('    const selectedTargetIcsValue =');
const end = source.indexOf('    const syncTargetEntryMode =', begin);

test('ICS and block selections populate the submitted hidden ICS field', () => {
  assert.ok(begin >= 0 && end > begin, 'ICS synchronization must remain in the target handler');
  let blockWise = false;
  const hidden = { value: '' };
  const ics = { value: 'I1||ICS One', dataset: { selectedValue: 'I0||Saved ICS' } };
  const block = { value: 'B1||Block One' };
  const context = vm.createContext({ icsHidden: hidden, icsSelect: ics, blockSelect: block, targetBlockWiseMode: () => blockWise });
  vm.runInContext(source.slice(begin, end) + '\nthis.sync = syncTargetIcsHidden;', context);
  context.sync();
  assert.equal(hidden.value, 'I1||ICS One');
  ics.value = '';
  context.sync();
  assert.equal(hidden.value, 'I0||Saved ICS');
  blockWise = true;
  context.sync();
  assert.equal(hidden.value, 'B1||Block One');
  block.value = '';
  context.sync();
  assert.equal(hidden.value, '');
});

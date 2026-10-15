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

test('saved Other Target ICS stays selectable when its mapping is no longer active', () => {
  const start = source.indexOf('    const fillSeedSelect =');
  const end = source.indexOf('    const setOnlySeedOption =', start);
  assert.ok(start >= 0 && end > start);
  const context = vm.createContext({
    document: { createElement: () => ({}) },
    normalizeOption: (value) => String(value || '').trim().toLowerCase(),
    optionValue: (option) => typeof option === 'object' ? option.value : option,
    optionLabel: (option) => typeof option === 'object' ? option.label : option,
    makeOption: (value, label) => ({ value, label }),
    selectOption: (option, optionData, selected) => {
      option.selected = optionData.value === selected || optionData.label === selected;
    }
  });
  vm.runInContext(source.slice(start, end) + '\nthis.fill = fillSeedSelect;', context);
  const select = {
    dataset: { selectedValue: 'Saved September ICS' },
    value: '',
    options: [],
    appendChild(option) { this.options.push(option); }
  };
  context.fill(select, [], 'Select ICS');
  assert.equal(select.options[1].value, 'Saved September ICS');
  assert.equal(select.options[1].selected, true);
});

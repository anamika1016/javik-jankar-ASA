const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('  const locationLevels =');
const end = source.indexOf('  document.querySelectorAll("[data-location-form]")', start);
const context = vm.createContext({
  uniquePresent: (values) => [...new Set(values.filter(Boolean))],
  normalizeOption: (value) => String(value || '').trim().toLowerCase(),
  document: { createElement: () => ({}) },
  Event: class { constructor(type) { this.type = type; } }
});
vm.runInContext(source.slice(start, end) + '\nthis.locationHelpers = { replaceLocationOptions, locationRowMatchesParents, optionMatchesLocationRow };', context);
const { replaceLocationOptions, locationRowMatchesParents, optionMatchesLocationRow } = context.locationHelpers;
const parent = (value) => ({ selectedOptions: [{ value, textContent: value }] });

test('directory-only Panchayats and villages populate empty master dropdowns', () => {
  for (const [level, key, label] of [['gram-panchayat', 'gram_panchayat', 'Pandhurna'], ['village', 'village', 'Ajangaon']]) {
    const select = { dataset: {}, selectedOptions: [], children: [],
      closest: () => ({ querySelector: () => parent('selected') }),
      appendChild(option) { this.children.push(option); },
      dispatchEvent(event) { this.event = event.type; }
    };
    replaceLocationOptions(select, [{ value: '', label: 'Select' }], [{ id: '42', [key]: label }], level);
    assert.equal(select.children[1].value, label);
    assert.equal(select.event, 'chip:refresh');
  }
});

test('parent matching accepts imported codes and excludes another block', () => {
  const selects = { state: parent('23'), district: parent('455'), block: parent('Pandhurna'), 'gram-panchayat': parent('Pandhurna') };
  const row = { state_code: '23', district_code: '455', cd_block_name: 'Pandhurna', gram_panchayat: '03658', gp_code: 'Pandhurna' };
  assert.equal(locationRowMatchesParents(row, selects, 'village'), true);
  assert.equal(locationRowMatchesParents({ ...row, cd_block_name: 'Sausar' }, selects, 'village'), false);
});

test('indexed location options preserve legacy matching, order and saved selection', () => {
  const options = [{ value: '', label: 'Select' }];
  const rows = [];
  for (let i = 0; i < 200; i++) {
    options.push({ value: String(i), label: `Village ${i}` });
    rows.push({ id: String(i % 70), village: `Village ${i % 120}`, village_code: String(i % 90) });
  }
  rows.push({ id: 'missing', village: 'ग्राम' }, { id: 'other', village: 'GRAM' }, { village: 'gram' });
  const expected = options.filter(option => option.value !== '' && rows.some(row => optionMatchesLocationRow(option, row, 'village')));
  rows.forEach(row => {
    if (row.village && !expected.some(option => optionMatchesLocationRow(option, row, 'village'))) {
      expected.push({ value: row.village, label: row.village });
    }
  });
  expected.sort((left, right) => left.label.localeCompare(right.label, undefined, { sensitivity: 'base' }));
  const select = { dataset: { selectedValues: '["Village 1"]' }, selectedOptions: [], children: [],
    closest: () => ({ querySelector: () => parent('selected') }),
    appendChild(option) { this.children.push(option); }, dispatchEvent() {}
  };
  replaceLocationOptions(select, options, rows, 'village');
  assert.deepEqual(select.children.slice(1).map(option => ({ value: option.value, label: option.textContent })), expected);
  assert.equal(select.children.find(option => option.value === '1').selected, true);
});

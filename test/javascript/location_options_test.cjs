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
vm.runInContext(source.slice(start, end) + '\nthis.locationHelpers = { replaceLocationOptions, locationRowMatchesParents };', context);
const { replaceLocationOptions, locationRowMatchesParents } = context.locationHelpers;
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

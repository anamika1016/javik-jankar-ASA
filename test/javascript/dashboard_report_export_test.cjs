const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('dashboard export retains reporting scope and exports searched rows across pages', () => {
  let input;
  const search = { value: '', dataset: {}, addEventListener: (_event, callback) => { input = callback; } };
  const link = { href: 'http://localhost/dashboard/demonstration-method.xlsx?month=September&fcoc=Sausar' };
  const report = { querySelector: () => search, querySelectorAll: () => [link] };
  const document = { querySelectorAll: () => [report], addEventListener: () => {} };
  vm.runInNewContext(fs.readFileSync('app/javascript/dashboard_reports.js', 'utf8'), { document, window: { location: { origin: 'http://localhost' } }, URL });
  search.value = ' JJ A ';
  input();
  let url = new URL(link.href);
  assert.equal(url.searchParams.get('q'), 'JJ A');
  assert.equal(url.searchParams.get('month'), 'September');
  assert.equal(url.searchParams.get('fcoc'), 'Sausar');
  search.value = '';
  input();
  assert.equal(new URL(link.href).searchParams.has('q'), false);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('  const paginateTable =');
const end = source.indexOf('  const closeColumnFilters =', start);

test('pagination preserves full-list search and filters and avoids unchanged DOM writes', () => {
  let writes = 0;
  const rows = Array.from({ length: 1000 }, (_, index) => {
    let hidden = false;
    return {
      dataset: {}, textContent: `JJ ${index}`, children: [{ textContent: index % 2 ? 'Odd' : 'Even' }],
      get hidden() { return hidden; },
      set hidden(value) { writes += 1; hidden = value; }
    };
  });
  const search = { value: '' };
  const table = { id: 'bills', dataset: { pageSize: '15' }, querySelectorAll: () => rows };
  const context = { document: { querySelector: (selector) => selector.includes('data-table-search') ? search : null } };
  vm.runInNewContext(`${source.slice(start, end)}\nthis.paginate = paginateTable;`, context);
  context.paginate(table, 1);
  assert.equal(rows.filter((row) => !row.hidden).length, 15);
  assert.equal(writes, 985);
  context.paginate(table, 1);
  assert.equal(writes, 985);
  context.paginate(table, 2);
  assert.deepEqual(rows.flatMap((row, index) => row.hidden ? [] : [index]), Array.from({ length: 15 }, (_, i) => i + 15));
  search.value = 'JJ 999';
  context.paginate(table, 1);
  assert.deepEqual(rows.flatMap((row, index) => row.hidden ? [] : [index]), [999]);
  search.value = '';
  table.dataset.columnFilters = JSON.stringify({ 0: { operator: 'equals', value: 'Even' } });
  context.paginate(table, 1);
  assert.deepEqual(rows.flatMap((row, index) => row.hidden ? [] : [index]), Array.from({ length: 15 }, (_, i) => i * 2));
});

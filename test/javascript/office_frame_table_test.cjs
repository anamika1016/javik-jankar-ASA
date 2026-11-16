const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('  const initializePaginatedTables =');
const end = source.indexOf('  // Simple client-side row filter', start);

test('Office frame initializes table controls without rebinding page forms or unrelated frames', () => {
  const listeners = {}, calls = [];
  const row = { children: [{}, {}], textContent: 'Office', dataset: {} };
  const table = { dataset: {}, querySelectorAll: () => [row] };
  const frame = { id: 'office_list_content', querySelectorAll: (selector) => selector === '[data-paginated-table]' ? [table] : [] };
  const document = { querySelectorAll: () => [], addEventListener: (name, handler) => listeners[name] = handler,
    removeEventListener: (name, handler) => { if (listeners[name] === handler) delete listeners[name]; }, getElementById: () => table };
  const context = { document, window: {}, ensureTableSearch: () => calls.push('search'), ensureTablePagination: () => calls.push('pager'),
    sortTableRowsAlphabetically: () => calls.push('sort'), setupColumnFilters: () => calls.push('filters'),
    paginateTable: (_table, page) => calls.push(`page:${page}`) };
  vm.createContext(context);
  vm.runInContext(source.slice(start, end), context);
  assert.deepEqual(calls, []);
  listeners['turbo:frame-load']({ target: { id: 'jj_api_user_picker' } });
  assert.deepEqual(calls, []);
  listeners['turbo:frame-load']({ target: frame });
  assert.deepEqual(calls, ['search', 'pager', 'sort', 'filters', 'page:1']);
});

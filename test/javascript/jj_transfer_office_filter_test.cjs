const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('    control.addEventListener("click", (event) => {');
const end = source.indexOf('\n    // No open-on-focus', start);

test('picker cancels label activation and stays open for multi-selection', () => {
  const classes = new Set();
  let click;
  const control = {
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      toggle: (name) => classes.has(name) ? classes.delete(name) : classes.add(name)
    },
    addEventListener: (_name, handler) => { click = handler; }
  };
  vm.runInNewContext(source.slice(start, end), {
    control, select: { disabled: false, dataset: {} },
    document: { querySelectorAll: () => [] }
  });
  let prevented = false;
  let stopped = false;
  const event = {
    target: { closest: () => null },
    preventDefault: () => { prevented = true; },
    stopPropagation: () => { stopped = true; }
  };
  click(event);
  assert.equal(prevented, true);
  assert.equal(stopped, true);
  assert.equal(classes.has('open'), true);
  // A click within the dropdown must leave it open and preserve input behavior.
  click({ target: { closest: () => ({}) }, preventDefault: () => assert.fail('input default cancelled') });
  assert.equal(classes.has('open'), true);
  click(event);
  assert.equal(classes.has('open'), false);
});

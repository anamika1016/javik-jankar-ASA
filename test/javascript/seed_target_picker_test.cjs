const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const extract = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

// Two targets can be saved for the same Jeevika Jankar, month, ICS, village and
// activity, differing only in quantity. Every select matches both, so the form
// used to take the first and the second was unreachable. These tests pin that
// both are now offered, that picking one is honoured, and that a form with a
// single target is untouched.

const makeElement = (tag) => {
  const element = {
    tag,
    children: [],
    attrs: {},
    hidden: false,
    value: '',
    textContent: '',
    listeners: {},
    parentElement: null,
    get options() { return this.children.filter((child) => child.tag === 'option'); },
    set innerHTML(_value) { this.children = []; },
    get innerHTML() { return ''; },
    setAttribute(name, value) { this.attrs[name] = value; },
    append(...nodes) { nodes.forEach((node) => { node.parentElement = this; this.children.push(node); }); },
    insertBefore(node) { node.parentElement = this; this.children.push(node); },
    addEventListener(name, fn) { this.listeners[name] = fn; },
    closest(selector) {
      const name = selector.replace(/[[\]]/g, '');
      let node = this;
      while (node) {
        if (node.attrs && Object.prototype.hasOwnProperty.call(node.attrs, name)) return node;
        node = node.parentElement;
      }
      return null;
    }
  };
  return element;
};

const buildContext = (rows) => {
  const host = makeElement('label');
  const container = makeElement('div');
  container.append(host);
  const subjectSelect = makeElement('select');
  subjectSelect.value = 'Farmer Internal Inspection';
  subjectSelect.closest = () => host;

  const context = vm.createContext({
    rowsForSelection: () => rows,
    normalizeOption: (value) => String(value == null ? '' : value).trim().toLowerCase(),
    subjectSelect,
    refreshTarget: () => {},
    document: { createElement: makeElement }
  });
  vm.runInContext(
    extract('    const matchingSeedMappings =', '    const selectedSeedMappingIsManual =') +
    '\nthis.refreshPicker = refreshSeedTargetPicker;' +
    '\nthis.selected = selectedSeedMapping;' +
    '\nthis.picker = () => seedTargetPick;',
    context
  );
  return { context, container };
};

const row = (id, quantity) => ({
  target_mapping_id: id,
  target: quantity,
  training_subject: 'Farmer Internal Inspection'
});

test('a single matching target shows no picker and resolves as before', () => {
  const { context } = buildContext([row('11', '56')]);

  context.refreshPicker();

  assert.equal(context.picker(), null, 'no picker should be created for one target');
  assert.equal(context.selected().target_mapping_id, '11');
});

test('two targets on the same combination are both offered', () => {
  const { context } = buildContext([row('11', '56'), row('12', '79')]);

  context.refreshPicker();
  const picker = context.picker();

  assert.ok(picker, 'a picker must appear once two targets match');
  assert.deepEqual(picker.options.map((option) => option.value), ['11', '12']);
  assert.deepEqual(picker.options.map((option) => option.textContent), ['Target 56', 'Target 79']);
  assert.equal(picker.closest('data-seed-target-pick-field').hidden, false);
});

test('the chosen target is the one the form uses', () => {
  const { context } = buildContext([row('11', '56'), row('12', '79')]);
  context.refreshPicker();

  assert.equal(context.selected().target_mapping_id, '11', 'defaults to the first, as before');

  context.picker().value = '12';
  assert.equal(context.selected().target_mapping_id, '12',
    'the second target was unreachable before this picker existed');
  assert.equal(context.selected().target, '79');
});

test('targets with the same quantity are told apart by id', () => {
  const { context } = buildContext([row('11', '56'), row('12', '56')]);

  context.refreshPicker();

  assert.deepEqual(context.picker().options.map((option) => option.textContent),
    ['Target 56 (#11)', 'Target 56 (#12)']);
});

test('dropping back to one match hides the picker again', () => {
  const rows = [row('11', '56'), row('12', '79')];
  const host = makeElement('label');
  makeElement('div').append(host);
  const subjectSelect = makeElement('select');
  subjectSelect.value = 'Farmer Internal Inspection';
  subjectSelect.closest = () => host;
  let current = rows;
  const context = vm.createContext({
    rowsForSelection: () => current,
    normalizeOption: (value) => String(value == null ? '' : value).trim().toLowerCase(),
    subjectSelect,
    refreshTarget: () => {},
    document: { createElement: makeElement }
  });
  vm.runInContext(
    extract('    const matchingSeedMappings =', '    const selectedSeedMappingIsManual =') +
    '\nthis.refreshPicker = refreshSeedTargetPicker;' +
    '\nthis.selected = selectedSeedMapping;' +
    '\nthis.picker = () => seedTargetPick;',
    context
  );

  context.refreshPicker();
  assert.equal(context.picker().closest('data-seed-target-pick-field').hidden, false);

  current = [row('11', '56')];
  context.refreshPicker();

  assert.equal(context.picker().closest('data-seed-target-pick-field').hidden, true);
  assert.equal(context.selected().target_mapping_id, '11');
});

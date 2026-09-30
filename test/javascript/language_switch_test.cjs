const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const extract = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

// The switcher block from the language codes down to the end of applyGoogleLanguage.
const languageSource = extract('    const googleLanguageCodes =', '    const preserveSpacing =');

// A combo that behaves like Google's: it ignores a value that is not one of its
// options, which is why the empty placeholder never reverted the page.
const makeCombo = () => ({
  options: ['', 'en', 'hi', 'mr', 'or', 'gu'],
  value: '',
  changes: [],
  dispatchEvent(event) { this.changes.push({ value: this.value, type: event.type }); }
});

const buildContext = ({ combo = makeCombo(), translated = false } = {}) => {
  const cookies = [];
  const timers = [];
  const context = {
    document: {
      cookie: '',
      documentElement: { className: translated ? 'translated-ltr' : '' },
      querySelector: (selector) => (selector === '.goog-te-combo' ? combo : null),
      createElement: () => ({ style: {} }),
      head: { appendChild() {} }
    },
    window: {
      location: { hostname: 'jj.asaindia.org' },
      setTimeout: (fn) => { timers.push(fn); return timers.length; },
      google: { translate: { TranslateElement: function () {} } }
    },
    Event: function (type) { this.type = type; },
    combo,
    cookies,
    timers
  };
  // Capture every cookie write.
  Object.defineProperty(context.document, 'cookie', {
    get: () => cookies.join('; '),
    set: (value) => { cookies.push(value); }
  });
  vm.createContext(context);
  vm.runInContext(`${languageSource}\nthis.applyGoogleLanguage = applyGoogleLanguage;`, context);
  return context;
};

const flush = (context) => {
  // Resolve the loadGoogleTranslate promise chain.
  return new Promise((resolve) => setImmediate(() => {
    context.timers.splice(0).forEach((fn) => fn());
    setImmediate(resolve);
  }));
};

test('switching to a language selects that language in Google\'s combo', async () => {
  const context = buildContext();
  context.applyGoogleLanguage('or');
  await flush(context);

  assert.equal(context.combo.value, 'or');
  assert.ok(context.cookies.some((c) => c.startsWith('googtrans=/en/or')), 'sets the translate cookie');
});

test('switching back to English reverts instead of leaving the page translated', async () => {
  const context = buildContext({ translated: true });
  context.applyGoogleLanguage('en');
  await flush(context);

  // The old code set "" here, which Google ignores, so the page stayed in Odia.
  assert.equal(context.combo.value, 'en', 'must select the page language to show the original');
  assert.ok(context.combo.changes.some((c) => c.value === 'en' && c.type === 'change'),
    'a change event has to fire for Google to react');
});

test('English clears the translate cookie so a reload stays English', async () => {
  const context = buildContext({ translated: true });
  context.applyGoogleLanguage('en');
  await flush(context);

  const cleared = context.cookies.filter((c) => c.startsWith('googtrans=;'));
  assert.ok(cleared.length >= 2, 'cookie must be expired on the plain path and the host domain');
  cleared.forEach((c) => assert.match(c, /expires=Thu, 01 Jan 1970/));
  assert.ok(!context.cookies.some((c) => c.startsWith('googtrans=/en/en')),
    'English must not write a translate cookie');
});

test('a switch retries while Google has not attached its select yet', async () => {
  let combo = null;
  const cookies = [];
  const timers = [];
  const context = {
    document: {
      documentElement: { className: '' },
      querySelector: (selector) => (selector === '.goog-te-combo' ? combo : null),
      createElement: () => ({ style: {} }),
      head: { appendChild() {} }
    },
    window: {
      location: { hostname: 'jj.asaindia.org' },
      setTimeout: (fn) => { timers.push(fn); return timers.length; },
      google: { translate: { TranslateElement: function () {} } }
    },
    Event: function (type) { this.type = type; },
    timers
  };
  Object.defineProperty(context.document, 'cookie', {
    get: () => cookies.join('; '),
    set: (value) => { cookies.push(value); }
  });
  vm.createContext(context);
  vm.runInContext(`${languageSource}\nthis.applyGoogleLanguage = applyGoogleLanguage;`, context);

  context.applyGoogleLanguage('hi');
  await new Promise((resolve) => setImmediate(resolve));
  timers.splice(0).forEach((fn) => fn());
  assert.equal(timers.length, 1, 'keeps retrying while the select is missing');

  // Google attaches the select on a later attempt.
  combo = makeCombo();
  timers.splice(0).forEach((fn) => fn());
  assert.equal(combo.value, 'hi', 'applies the language once the select exists');
});

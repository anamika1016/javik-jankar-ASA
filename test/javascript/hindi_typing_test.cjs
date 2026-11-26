const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/layout.js', 'utf8');
const start = source.indexOf('const HINDI_TYPING_INPUTS');
const block = source.slice(start, source.indexOf('const bootLayoutPage', start));

const load = (fetchImpl) => {
  const context = { fetch: fetchImpl, AbortController, setTimeout, clearTimeout, encodeURIComponent, Map, window: {} };
  vm.createContext(context);
  vm.runInContext(`${block}; this.api = { transliterateToHindi, hindiSuggestions, HINDI_TYPING_INPUTS };`, context);
  return context.api;
};

test('fallback transliteration builds Hindi words', () => {
  const { transliterateToHindi } = load(async () => { throw new Error('offline'); });
  assert.equal(transliterateToHindi('TamaaTar'), 'टमाटर');
  assert.equal(transliterateToHindi('kharif'), 'खरिफ़');
  assert.equal(transliterateToHindi('gehoon'), 'गेहून');
  assert.equal(transliterateToHindi('makka'), 'मक्का');
  assert.equal(transliterateToHindi('kela'), 'केला');
  assert.equal(transliterateToHindi('aaloo'), 'आलू');
});

test('Google suggestions come first, the fallback is offered too', async () => {
  const { hindiSuggestions } = load(async () => ({ json: async () => ['SUCCESS', [['tamatar', ['टमाटर', 'टामटर']]]] }));
  assert.deepEqual(Array.from(await hindiSuggestions('tamatar')), ['टमाटर', 'टामटर', 'तमतर']);
});

test('without Google the fallback alone is suggested', async () => {
  const { hindiSuggestions } = load(async () => { throw new Error('offline'); });
  assert.deepEqual(Array.from(await hindiSuggestions('makka')), ['मक्का']);
});

test('only the crop and seed master name fields get Hindi typing', () => {
  const { HINDI_TYPING_INPUTS } = load(async () => ({}));
  assert.match(HINDI_TYPING_INPUTS, /crop_season_name/);
  assert.match(HINDI_TYPING_INPUTS, /crop_type_name/);
  assert.match(HINDI_TYPING_INPUTS, /module_record\[crop_name\]/);
  assert.match(HINDI_TYPING_INPUTS, /seed_crop_name/);
  assert.match(HINDI_TYPING_INPUTS, /seed_variety_name/);
  assert.doesNotMatch(HINDI_TYPING_INPUTS, /module_record\[seed_crop\]"/);
});

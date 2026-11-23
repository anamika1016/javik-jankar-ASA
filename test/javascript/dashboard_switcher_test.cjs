const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/javascript/dashboard_switcher.js', 'utf8');

test('idle warming visits alternate modes sequentially and keeps links same-origin', async () => {
  const navigation = {};
  const listeners = {};
  const calls = [];
  const makeLink = (url, active = false) => ({ href: url, getAttribute: () => active ? 'page' : null });
  let run;
  vm.runInNewContext(source, {
    document: { readyState: 'loading', querySelector: () => navigation, visibilityState: 'visible', addEventListener: (name, fn) => listeners[name] = fn,
      querySelectorAll: () => [makeLink('/dashboard?entry_mode=both', true), makeLink('/dashboard?entry_mode=ics_wise'), makeLink('/dashboard?entry_mode=block_wise'), makeLink('https://outside.test/dashboard')] },
    navigator: {}, AbortController, URL,
    window: { location: { href: 'https://example.test/dashboard', origin: 'https://example.test' }, requestIdleCallback: fn => { run = fn; } },
    fetch: async (url, options) => { calls.push({ url, options }); return {}; }
  });
  listeners['turbo:load']();
  assert.equal(calls.length, 0, 'Warming must not delay the initial render');
  await run();
  assert.deepEqual(calls.map(call => new URL(call.url).searchParams.get('entry_mode')), ['ics_wise', 'block_wise', 'both']);
  assert.ok(calls.every(call => call.options.credentials === 'same-origin'));
  listeners['turbo:before-visit']();
  assert.ok(calls.every(call => call.options.signal.aborted));
});

test('warming respects data saver and cancels queued work on navigation', async () => {
  const navigation = {};
  const listeners = {};
  let run;
  let requests = 0;
  const navigator = { connection: { saveData: true } };
  vm.runInNewContext(source, {
    document: { readyState: 'loading', querySelector: () => navigation, visibilityState: 'visible', addEventListener: (name, fn) => listeners[name] = fn,
      querySelectorAll: () => [{ href: '/dashboard?entry_mode=both', getAttribute: () => null }] },
    navigator, AbortController, URL,
    window: { location: { href: 'https://example.test/dashboard', origin: 'https://example.test' }, requestIdleCallback: fn => { run = fn; } },
    fetch: async () => { requests++; }
  });
  listeners['turbo:load']();
  assert.equal(run, undefined);
  navigator.connection.saveData = false;
  listeners['turbo:load']();
  listeners['turbo:before-visit']();
  await run();
  assert.equal(requests, 0);
});

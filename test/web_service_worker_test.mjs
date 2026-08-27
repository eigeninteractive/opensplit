import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

function worker() {
  const listeners = new Map();
  const stored = new Map();
  const deleted = [];
  let installed = [];
  const scope = 'https://example.test/app/';
  const cache = {
    addAll: async (requests) => {
      installed = requests;
      for (const request of requests) stored.set(request.url, request.url);
    },
    match: async (url) => stored.get(url),
  };
  const self = {
    registration: { scope },
    location: { origin: 'https://example.test' },
    clients: { claim: async () => {} },
    addEventListener: (name, listener) => listeners.set(name, listener),
    skipWaiting: () => assert.fail('must not replace an active editor'),
  };
  const source = readFileSync(new URL('../web/sw.js', import.meta.url), 'utf8')
    .replace('__OPEN_SPLIT_BUILD_ID__', 'release-one')
    .replace('__OPEN_SPLIT_RESOURCES__', JSON.stringify([
      'index.html', 'main.dart.js', 'sqlite3.wasm', '/icons/Icon-192.png',
    ]));
  vm.runInNewContext(source, {
    self, URL, Request, console,
    importScripts: () => {},
    fetch: () => assert.fail('network unavailable'),
    caches: {
      open: async () => cache,
      keys: async () => ['another-app-cache', 'opensplit-shell-old', 'opensplit-shell-release-one'],
      delete: async (key) => { deleted.push(key); },
    },
  });
  return {
    installed: () => installed,
    deleted,
    async lifecycle(name) {
      let work;
      listeners.get(name)({ waitUntil: (promise) => { work = promise; } });
      await work;
    },
    request(path, { navigation = false, range = false } = {}) {
      let response;
      listeners.get('fetch')({
        request: {
          url: new URL(path, scope).href,
          method: 'GET', mode: navigation ? 'navigate' : 'cors',
          headers: new Headers(range ? { range: 'bytes=0-100' } : {}),
        },
        respondWith: (promise) => { response = promise; },
      });
      return response;
    },
  };
}

test('install precaches all release assets with HTTP revalidation', async () => {
  const app = worker();
  await app.lifecycle('install');
  assert.equal(app.installed().length, 4);
  assert.ok(app.installed().every((request) => request.cache === 'reload'));
});

test('offline deep links and code use one complete release', async () => {
  const app = worker();
  await app.lifecycle('install');
  assert.equal(await app.request('/app/g/group-id', { navigation: true }),
    'https://example.test/app/index.html');
  assert.equal(await app.request('sqlite3.wasm'),
    'https://example.test/app/sqlite3.wasm');
});

test('the worker does not intercept legal pages, APIs, or range requests', () => {
  const app = worker();
  assert.equal(app.request('/terms/', { navigation: true }), undefined);
  assert.equal(app.request('/api/entries'), undefined);
  assert.equal(app.request('sqlite3.wasm', { range: true }), undefined);
});

test('activation removes only older OpenSplit caches', async () => {
  const app = worker();
  await app.lifecycle('activate');
  assert.deepEqual(app.deleted, ['opensplit-shell-old']);
});

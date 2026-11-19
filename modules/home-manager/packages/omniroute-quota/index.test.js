import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, writeFile, chmod, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAdapter, createServer, pages, readKey, upstreamJSON } from './index.js';

const flush = () => new Promise(resolve => setImmediate(resolve));
const initialTime = Date.parse('2026-11-18T12:00:00Z');
function fixture(options = {}) {
  const calls = [];
  let clock = initialTime;
  const get = async path => {
    calls.push(path);
    if (path.startsWith('/api/combos?')) return { combos: ['a', 'b'].map(name => ({ name, models: [{ model: 'gpt-5', providerId: 'codex' }, { model: 'gpt-5-mini', providerId: 'codex' }] })), total: 2 };
    if (path.startsWith('/api/providers?')) return { connections: [{ id: 'c1', provider: 'codex', isActive: true, email: 'private@example.test', accessToken: 'secret-token' }, { id: 'off', provider: 'codex', isActive: false }], total: 2 };
    if (path === '/api/usage/provider-limits') {
      if (options.metadataFail) throw new Error('secret error');
      return { caches: options.missing ? {} : { c1: { quotas: [{ key: 'session', total: 100, used: 25 }], fetchedAt: new Date(clock - (options.stale ? 600_000 : 0)).toISOString() } } };
    }
    if (options.refreshFail) throw new Error('secret refresh error');
    return { quotas: [{ key: 'session', total: 100, used: 10 }], fetchedAt: new Date(clock).toISOString() };
  };
  return { adapter: createAdapter({ allowedCombos: new Set(['a', 'b']), get, now: () => clock }), calls, advance: ms => { clock += ms; } };
}

test('lazy metadata, cached requests, no credential identity leakage', async () => {
  const { adapter, calls } = fixture();
  assert.equal(adapter.snapshot('no'), undefined);
  assert.equal(calls.length, 0);
  assert.match(adapter.snapshot('a').entries[0].value, /pending/);
  await adapter.settled();
  const body = adapter.snapshot('a');
  assert.deepEqual(Object.keys(body), ['version', 'entries']);
  assert.equal(body.version, 'quota-v1');
  assert.equal(body.entries[0].percentRemaining, 75);
  for (let i = 0; i < 100; i++) adapter.snapshot('a');
  assert.equal(calls.length, 3);
  assert.doesNotMatch(JSON.stringify(body), /private|secret|c1|off/);
});

test('stale refresh deduplicates across combos and excludes inactive accounts', async () => {
  const { adapter, calls } = fixture({ stale: true });
  adapter.snapshot('a');
  await adapter.settled();
  assert.match(adapter.snapshot('a').entries[0].label, /stale/);
  adapter.snapshot('b');
  await flush();
  assert.equal(calls.filter(path => path === '/api/usage/c1').length, 1);
  assert.ok(!calls.includes('/api/usage/off'));
  assert.equal(adapter.snapshot('b').entries[0].percentRemaining, 90);
});

test('missing data unavailable; refresh failures have at least 60s cooldown', async () => {
  const { adapter, calls, advance } = fixture({ missing: true, refreshFail: true });
  adapter.snapshot('a');
  await adapter.settled();
  assert.equal(adapter.snapshot('a').entries[0].kind, 'value');
  await flush();
  advance(59_999);
  adapter.snapshot('b');
  await flush();
  assert.equal(calls.filter(path => path === '/api/usage/c1').length, 1);
  advance(1);
  adapter.snapshot('a');
  await adapter.settled();
  adapter.snapshot('a');
  await flush();
  assert.equal(calls.filter(path => path === '/api/usage/c1').length, 2);
});

test('metadata failures fail closed without provider errors', async () => {
  const { adapter } = fixture({ metadataFail: true });
  adapter.snapshot('a');
  await adapter.settled();
  const body = adapter.snapshot('a');
  assert.equal(body.entries[0].kind, 'value');
  assert.doesNotMatch(JSON.stringify(body), /secret error/);
});

test('bounded pagination observes total and rejects repeated or incomplete pages', async () => {
  const paths = [];
  const result = await pages(async path => {
    paths.push(path);
    return { connections: [{ id: path.endsWith('=0') ? 'a' : 'b' }], total: 2 };
  }, '/api/providers', 'connections', x => x);
  assert.equal(result.length, 2);
  assert.match(paths[1], /offset=1$/);
  for (const data of [{ connections: [], total: 1 }, { connections: [{ id: 'a' }], total: 2 }, { connections: [], total: 513 }]) {
    await assert.rejects(pages(async () => data, '/api/providers', 'connections', x => x));
  }
});

function request(port, path, headers = {}, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port, path, method, headers }, response => {
      let body = '';
      response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve({ code: response.statusCode, headers: response.headers, body: JSON.parse(body) }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('HTTP exact schema, host/origin/path/method bounds, inbound authorization ignored', async t => {
  const { adapter } = fixture();
  adapter.snapshot('a');
  await adapter.settled();
  // Port zero is test-only; update expected Host through a wrapper.
  const server = createServer(adapter, 20129);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const port = server.address().port;
  const host = { host: '127.0.0.1:20129' };
  const good = await request(port, '/combos/a', { ...host, authorization: 'Bearer INFERENCE-SECRET' });
  assert.equal(good.code, 200);
  assert.deepEqual(Object.keys(good.body), ['version', 'entries']);
  assert.doesNotMatch(JSON.stringify(good), /INFERENCE-SECRET|access-control-allow-origin|private@example/);
  assert.equal((await request(port, '/combos/a', { ...host, origin: 'https://evil.test' })).code, 403);
  assert.equal((await request(port, '/combos/a', { host: 'evil.test' })).code, 403);
  assert.equal((await request(port, '/combos/a', host, 'POST')).code, 405);
  for (const path of ['/api/providers', '/combos/no', '/combos/a?x=y', '/combos/a/next']) assert.equal((await request(port, path, host)).code, 404);
  assert.equal((await request(port, '/combos/%zz', host)).code, 400);
});

test('HTTP normalized upstream combo fixtures produce Codex and AGY percentages', async t => {
  const adapter = createAdapter({
    allowedCombos: new Set(['normalized']), now: () => initialTime,
    get: async path => {
      if (path.startsWith('/api/combos?')) return { total: 2, combos: [
        { name: 'normalized', models: [{ id: 'ref-1', kind: 'combo-ref', comboName: 'nested', weight: 0, label: 'Nested target' }] },
        { name: 'nested', models: [
          { id: 'model-1', kind: 'model', model: 'codex/gpt-5', providerId: 'codex', weight: 0, connectionId: null },
          { id: 'model-2', kind: 'model', model: 'antigravity/claude-sonnet', providerId: 'antigravity', weight: 100, label: 'Claude', connectionId: 'agy-1', allowedConnectionIds: ['agy-1'] },
        ] },
      ] };
      if (path.startsWith('/api/providers?')) return { total: 2, connections: [
        { id: 'codex-1', provider: 'codex', isActive: true },
        { id: 'agy-1', provider: 'antigravity', isActive: true },
      ] };
      if (path === '/api/usage/provider-limits') return { caches: {
        'codex-1': { fetchedAt: new Date(initialTime).toISOString(), quotas: [{ key: 'session', total: 100, used: 20 }, { key: 'weekly', total: 100, used: 40 }] },
        'agy-1': { fetchedAt: new Date(initialTime).toISOString(), quotas: [{ key: 'claude_gpt_session', remainingPercentage: 35 }, { key: 'claude_gpt_weekly', remainingPercentage: 45 }] },
      } };
      throw new Error('Unexpected refresh');
    },
  });
  adapter.snapshot('normalized');
  await adapter.settled();
  const server = createServer(adapter);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await request(server.address().port, '/combos/normalized', { host: '127.0.0.1:20129' });
  assert.equal(response.code, 200);
  assert.deepEqual(Object.keys(response.body), ['version', 'entries']);
  assert.deepEqual(response.body.entries.map(row => row.percentRemaining), [80, 60, 35, 45]);
  assert.ok(response.body.entries.every(row => row.kind === 'percent' && row.resultType === 'quota'));
});

test('credential file requires regular owner-only non-symlink file', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'omniroute-quota-test-'));
  const path = join(dir, 'key');
  await writeFile(path, 'FAKE-TEST-KEY\n', { mode: 0o600 });
  assert.equal(await readKey(path), 'FAKE-TEST-KEY');
  await chmod(path, 0o640);
  await assert.rejects(readKey(path));
  await chmod(path, 0o600);
  const link = join(dir, 'link');
  await symlink(path, link);
  await assert.rejects(readKey(link));
  await assert.rejects(readKey(dir));
});

test('refresh concurrency stays at two and preserves separate account rows', async () => {
  let active = 0;
  let maximum = 0;
  const releases = [];
  const adapter = createAdapter({
    allowedCombos: new Set(['a']), now: () => initialTime,
    get: async path => {
      if (path.startsWith('/api/combos?')) return { combos: [{ name: 'a', models: [{ model: 'gpt-5', providerId: 'codex' }] }], total: 1 };
      if (path.startsWith('/api/providers?')) return { connections: [1, 2, 3].map(i => ({ id: `c${i}`, provider: 'codex', isActive: true })), total: 3 };
      if (path === '/api/usage/provider-limits') return { caches: {} };
      active++;
      maximum = Math.max(maximum, active);
      await new Promise(resolve => releases.push(resolve));
      active--;
      return { quotas: [] };
    },
  });
  adapter.snapshot('a');
  await adapter.settled();
  const body = adapter.snapshot('a');
  assert.equal(body.entries.length, 6);
  assert.equal(new Set(body.entries.map(row => row.name.split(' ').slice(0, 2).join(' '))).size, 3);
  await flush();
  assert.equal(active, 2);
  releases.shift()();
  await flush();
  assert.equal(active, 2);
  while (releases.length) releases.shift()();
  await flush();
  assert.equal(maximum, 2);
  assert.equal(active, 0);
});

test('upstream client refuses nonfixed paths before network access', async () => {
  for (const path of ['http://evil.test', '/api/keys', '/api/usage/a?url=evil', '/api/providers?limit=999']) await assert.rejects(upstreamJSON(path, 'FAKE-TEST-KEY'));
});

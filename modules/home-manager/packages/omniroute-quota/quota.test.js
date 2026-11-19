import test from 'node:test';
import assert from 'node:assert/strict';
import { envelope, status, family, quotaRows, resolveTargets, selectAccounts } from './quota.js';

const now = Date.parse('2026-11-18T12:00:00Z');
const data = quotas => ({ quotas, fetchedAt: '2026-11-18T12:00:00Z' });
const rows = (pool, quotas) => quotaRows({}, pool, data(quotas), 1, now);

test('Codex maps only managed session/weekly and never invents missing allowance', () => {
  const result = rows('codex', [{ key: 'session', total: 100, used: 30 }, { key: 'code_review', total: 100, used: 0 }]);
  assert.equal(result[0].percentRemaining, 70);
  assert.equal(result[1].kind, 'value');
  assert.equal(family('codex', 'gpt-5.4'), 'codex');
  for (const model of ['gpt-5-spark', 'gpt-code_review', 'gpt-reserve', 'other']) assert.equal(family('codex', model), undefined);
});

test('AGY exact family windows, fractions, estimates, unlimited and resets', () => {
  assert.equal(family('antigravity', 'gemini-4-pro'), 'argon');
  assert.equal(family('agy', 'x-argon'), 'argon');
  assert.equal(family('agy', 'cloud-sonnet'), 'claude_gpt');
  assert.equal(family('agy', 'gemini-3-pro'), 'gemini');
  assert.equal(rows('argon', [{ key: 'gemini_weekly', remainingPercentage: 90 }])[0].kind, 'value');
  assert.equal(rows('argon', [{ key: 'argon_weekly', remainingPercentage: 25 }])[0].percentRemaining, 25);
  assert.equal(rows('gemini', [{ key: 'gemini_session', remaining: 3, total: 4 }])[0].percentRemaining, 75);
  for (const extra of [{ fractionReported: false }, { quotaSource: 'localUsageHistory' }, { remainingPercentage: NaN }, { remainingPercentage: 101 }]) {
    assert.equal(rows('gemini', [{ key: 'gemini_session', ...extra }])[0].kind, 'value');
  }
  const unlimited = rows('claude_gpt', [{ key: 'claude_gpt_weekly', unlimited: true, resetTime: '2026-11-19T00:00:00Z' }])[1];
  assert.equal(unlimited.value, 'Unlimited (provider reported)');
  assert.equal(unlimited.resetTimeIso, '2026-11-19T00:00:00.000Z');
  assert.equal(rows('gemini', [{ key: 'gemini_session', resetAt: 'nonsense' }])[0].resetTimeIso, undefined);
});

test('stale and unknown age stay explicit; schema and text bounds', () => {
  assert.match(quotaRows({}, 'codex', { ...data([]), fetchedAt: '2026-11-17T12:00:00Z' }, 1, now)[0].label, /stale/);
  assert.match(quotaRows({}, 'codex', undefined, 1, now)[0].value, /age unknown/);
  const row = status('a\u001b\u202eb'.repeat(100), 'c'.repeat(300));
  assert.equal(row.name.length, 80);
  assert.equal(row.value.length, 160);
  assert.ok(!/[\p{Cc}\p{Cf}]/u.test(row.name));
  const result = envelope(Array.from({ length: 102 }, () => row));
  assert.deepEqual(Object.keys(result), ['version', 'entries']);
  assert.equal(result.entries.length, 100);
  assert.match(result.entries[99].value, /Truncated/);
  assert.equal(envelope([]).entries.length, 1);
});

const normalizedModel = (providerId, model, extra = {}) => ({ id: `step-${model}`, kind: 'model', model: `${providerId}/${model}`, providerId, weight: 0, label: 'Quota target', connectionId: null, ...extra });

test('normalized Codex and AGY models, nested metadata, null and explicit pins', () => {
  const combos = [
    { name: 'root', allowedProviders: ['codex', 'antigravity'], models: [{ id: 'ref', kind: 'combo-ref', comboName: 'child', weight: 100, label: 'Nested' }] },
    { name: 'child', models: [normalizedModel('codex', 'gpt-5'), normalizedModel('antigravity', 'claude-sonnet'), normalizedModel('antigravity', 'gemini-4-pro')] },
  ];
  const targets = resolveTargets('root', combos);
  assert.deepEqual(targets.map(target => family(target.providerId, target.model)), ['codex', 'claude_gpt', 'argon']);
  assert.equal(targets[0].ids, undefined);
  const connections = [{ id: 'c1', provider: 'codex', isActive: true }, { id: 'c2', provider: 'codex', isActive: true }];
  assert.equal(selectAccounts([targets[0]], connections).selected.length, 2);
  const pinned = extra => resolveTargets('a', [{ name: 'a', models: [normalizedModel('codex', 'gpt-5', extra)] }]);
  assert.deepEqual(pinned({ connectionId: 'c1', allowedConnectionIds: ['c1', 'c2'] })[0].ids, ['c1']);
  assert.deepEqual(pinned({ connectionId: 'c1', allowedConnectionIds: ['c2'] })[0].ids, []);
  assert.deepEqual(pinned({ connectionId: null, allowedConnectionIds: ['c2'] })[0].ids, ['c2']);
});

test('malformed normalized metadata and mismatched qualified models fail closed', () => {
  const malformed = [{ id: 1 }, { label: null }, { kind: 'other' }, { weight: NaN }, { weight: Infinity }, { weight: -1 }, { weight: 101 }, { weight: '0' }, { model: 'antigravity/gpt-5' }, { model: 'codex/gpt-5/extra' }, { model: 'codex/*' }, { model: 'gpt-*' }, { connectionId: 1 }];
  for (const extra of malformed) assert.throws(() => resolveTargets('a', [{ name: 'a', models: [normalizedModel('codex', 'gpt-5', extra)] }]));
  for (const extra of [{ id: 1 }, { label: false }, { weight: -1 }, { weight: 101 }, { weight: NaN }]) {
    assert.throws(() => resolveTargets('a', [{ name: 'a', models: [{ id: 'ref', kind: 'combo-ref', comboName: 'b', weight: 0, ...extra }] }, { name: 'b', models: [] }]));
  }
});

const target = { model: 'gpt-5', providerId: 'codex' };
const accounts = [1, 2].map(i => ({ id: `c${i}`, provider: 'codex', isActive: true }));
test('nested resolution intersects pinning and providers; keeps accounts and deduplicates pools', () => {
  const combos = [{ name: 'a', allowedProviders: ['codex'], models: [{ kind: 'combo-ref', comboName: 'b' }, target] }, { name: 'b', models: [{ ...target, connectionId: 'c1', allowedConnectionIds: ['c2'] }] }];
  const result = selectAccounts(resolveTargets('a', combos), accounts);
  assert.equal(result.selected.length, 2);
  assert.equal(selectAccounts([target, target].map(t => ({ ...t })), accounts).selected.length, 2);
  assert.equal(resolveTargets('a', [{ name: 'a', allowedProviders: [], models: [target] }]).length, 0);
  assert.equal(selectAccounts([{ ...target, ids: ['c2'] }], accounts).selected[0].account.id, 'c2');
});

test('ambiguous strings, filters, cycles, unsupported nested pins fail closed', () => {
  for (const models of [['codex/gpt-5'], [{ ...target, tags: ['fast'] }], [{ kind: 'combo-ref', comboName: 'a' }], [{ kind: 'combo-ref', comboName: 'b', connectionId: 'c1' }]]) {
    assert.throws(() => resolveTargets('a', [{ name: 'a', models }]));
  }
  assert.throws(() => resolveTargets('a', [{ name: 'a', models: [target], connectionFilter: {} }]));
  const deep = Array.from({ length: 11 }, (_, i) => ({ name: `${i}`, models: i === 10 ? [target] : [{ kind: 'combo-ref', comboName: `${i + 1}` }] }));
  assert.throws(() => resolveTargets('0', deep));
});

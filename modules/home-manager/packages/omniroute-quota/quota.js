// Keep all presentation data independent of credentials and provider identities.
export const STALE_MS = 5 * 60_000;
const clean = (value, max) => String(value).replace(/[\p{Cc}\p{Cf}\p{Cs}]/gu, '').slice(0, max);
export const timestamp = value => {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT/.test(value)) return undefined;
  const time = Date.parse(value);
  return Number.isFinite(time) ? new Date(time).toISOString() : undefined;
};
export const status = (name, value) => ({ name: clean(name, 80), label: 'Shared account quota', kind: 'value', resultType: 'status', value: clean(value, 160) });
export function envelope(entries) {
  const rows = entries.length ? entries : [status('Quota', 'Unavailable')];
  return { version: 'quota-v1', entries: rows.length > 100 ? [...rows.slice(0, 99), status('Quota', 'Truncated: additional quota rows omitted')] : rows };
}

const list = value => Array.isArray(value) && value.every(x => typeof x === 'string');
const intersect = (a, b) => a === undefined ? b : b === undefined ? a : a.filter(x => b.includes(x));
const supported = (object, keys) => Object.keys(object).every(key => keys.includes(key));

export function resolveTargets(name, combos) {
  const targets = [];
  let visited = 0;
  const visit = (current, path, providers, ids) => {
    if (++visited > 512 || targets.length > 512) throw new Error('Combo expansion limit');
    if (path.length >= 10 || path.includes(current)) throw new Error('Nested combo cycle or depth limit');
    const matches = combos.filter(combo => combo.name === current);
    if (matches.length !== 1) throw new Error('Combo missing or ambiguous');
    const combo = matches[0];
    if (!Array.isArray(combo.models) || (combo.allowedProviders !== undefined && !list(combo.allowedProviders))) throw new Error('Unsupported combo');
    // Routing filters must not silently widen the set of eligible accounts.
    const routingKeys = Object.keys(combo).filter(key => /filter|tag|connection/i.test(key));
    if (routingKeys.length) throw new Error('Unsupported combo routing filter');
    providers = intersect(providers, combo.allowedProviders);
    for (const target of combo.models) {
      if (!target || typeof target !== 'object' || Array.isArray(target)) throw new Error('Ambiguous target');
      const metadataKeys = ['id', 'kind', 'weight', 'label'];
      if (('id' in target && typeof target.id !== 'string') || ('label' in target && typeof target.label !== 'string') || ('weight' in target && (!Number.isFinite(target.weight) || target.weight < 0 || target.weight > 100))) throw new Error('Invalid target metadata');
      if (target.kind === 'combo-ref') {
        if (!supported(target, [...metadataKeys, 'comboName']) || typeof target.comboName !== 'string') throw new Error('Unsupported nested target');
        visit(target.comboName, [...path, current], providers, ids);
        continue;
      }
      if (('kind' in target && target.kind !== 'model') || !supported(target, [...metadataKeys, 'model', 'providerId', 'connectionId', 'allowedConnectionIds']) || typeof target.model !== 'string' || typeof target.providerId !== 'string') throw new Error('Unsupported target');
      if (target.allowedConnectionIds !== undefined && !list(target.allowedConnectionIds)) throw new Error('Unsupported account filter');
      if (target.connectionId != null && typeof target.connectionId !== 'string') throw new Error('Unsupported account pin');
      let model = target.model;
      if (!target.providerId || /[/*]/.test(target.providerId) || model.includes('*')) throw new Error('Unsupported model identifier');
      if (model.includes('/')) {
        const prefix = `${target.providerId}/`;
        if (!model.startsWith(prefix)) throw new Error('Mismatched model provider');
        model = model.slice(prefix.length);
      }
      if (!model || model.includes('/')) throw new Error('Unsupported model identifier');
      const accountIds = intersect(intersect(ids, target.allowedConnectionIds), target.connectionId == null ? undefined : [target.connectionId]);
      if (providers !== undefined && !providers.includes(target.providerId)) continue;
      targets.push({ model, providerId: target.providerId, ids: accountIds });
    }
  };
  visit(name, [], undefined, undefined);
  return targets;
}

export function family(provider, model) {
  if (['codex', 'openai-codex'].includes(provider)) {
    return /^(?:gpt-)/i.test(model) && !/spark|code[_-]?review|reserve/i.test(model) ? 'codex' : undefined;
  }
  if (!['antigravity', 'agy'].includes(provider)) return undefined;
  if (/^gemini-4|argon/i.test(model)) return 'argon';
  if (/^(claude-|cloud-)/i.test(model)) return 'claude_gpt';
  if (/^gemini-/i.test(model)) return 'gemini';
  return undefined;
}

function windows(data) {
  if (Array.isArray(data?.quotas)) return data.quotas;
  if (data?.quotas && typeof data.quotas === 'object') return Object.entries(data.quotas).map(([key, value]) => ({ ...value, key }));
  return [];
}

function remaining(quota) {
  if (quota.quotaSource === 'localUsageHistory' || quota.fractionReported === false) return undefined;
  if (Number.isFinite(quota.remainingPercentage)) return quota.remainingPercentage >= 0 && quota.remainingPercentage <= 100 ? quota.remainingPercentage : undefined;
  const { total, used, remaining: left } = quota;
  if (!Number.isFinite(total) || total <= 0) return undefined;
  const available = Number.isFinite(left) ? left : Number.isFinite(used) ? total - used : NaN;
  return available >= 0 && available <= total ? available / total * 100 : undefined;
}

export function quotaRows(connection, pool, data, ordinal, now) {
  const observedAtIso = timestamp(data?.fetchedAt);
  const age = observedAtIso ? now - Date.parse(observedAtIso) : Infinity;
  const stale = age > STALE_MS || age < 0;
  const freshness = !observedAtIso ? 'age unknown' : stale ? `stale ${Math.max(0, Math.floor(age / 60_000))}m` : `age ${Math.max(0, Math.floor(age / 60_000))}m`;
  const keys = pool === 'codex' ? [['session'], ['weekly']] : pool === 'argon' ? [['gemini_4_argon_weekly', 'argon_weekly']] : [[`${pool}_session`], [`${pool}_weekly`]];
  const quotas = windows(data);
  return keys.map(aliases => {
    const name = `Account ${ordinal} ${pool} ${aliases[0].replace(`${pool}_`, '')}`;
    const matches = quotas.filter(quota => aliases.includes(quota.key ?? quota.id ?? quota.name));
    const row = status(name, `Unavailable (${freshness})`);
    row.label = clean(`Shared account quota · ${freshness}`, 80);
    if (observedAtIso) row.observedAtIso = observedAtIso;
    if (matches.length !== 1) return row;
    const quota = matches[0];
    const resetTimeIso = timestamp(quota.resetTime ?? quota.resetAt ?? quota.resetTimeIso);
    if (resetTimeIso) row.resetTimeIso = resetTimeIso;
    if (quota.quotaSource === 'localUsageHistory' || quota.fractionReported === false) return row;
    if (quota.unlimited === true) return { ...row, value: 'Unlimited (provider reported)' };
    // Codex session/weekly use provider-normalized percentages, not token totals.
    if (pool === 'codex' && quota.total !== 100) return row;
    const percent = remaining(quota);
    if (percent === undefined) return row;
    const { value, ...base } = row;
    return { ...base, kind: 'percent', resultType: 'quota', percentRemaining: percent };
  });
}

export function selectAccounts(targets, connections) {
  const selected = new Map();
  const unsupported = [];
  for (const target of targets) {
    const pool = family(target.providerId, target.model);
    if (!pool) { unsupported.push(status('Unsupported model', 'Unavailable: unsupported quota mapping')); continue; }
    const accounts = connections.filter(connection => connection.isActive === true && connection.provider === target.providerId && (target.ids === undefined || target.ids.includes(connection.id)));
    if (!accounts.length) unsupported.push(status(pool, 'Unavailable: no eligible active account'));
    for (const account of accounts) selected.set(`${account.id}\0${pool}`, { account, pool });
  }
  return { selected: [...selected.values()], unsupported };
}

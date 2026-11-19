import http from 'node:http';
import { constants } from 'node:fs';
import { open, readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { envelope, status, resolveTargets, selectAccounts, quotaRows, STALE_MS, timestamp } from './quota.js';

const MAX_BODY = 2 * 1024 * 1024;
const TTL = 60_000;
const MAX_ACCOUNTS = 512;

export async function readKey(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0 || stat.size > 4096) throw new Error('Invalid credential file');
    const key = (await file.readFile('utf8')).trim();
    if (!key || /[^\x21-\x7e]/.test(key)) throw new Error('Invalid credential file');
    return key;
  } finally {
    await file.close();
  }
}

// Only these fixed paths can cross the credential boundary. No incoming request
// header, URL, or response from OmniRoute is forwarded to the client.
export async function upstreamJSON(path, key) {
  if (!/^\/api\/(?:combos|providers)(?:\?limit=100&offset=\d+)?$/.test(path) && path !== '/api/usage/provider-limits' && !/^\/api\/usage\/[A-Za-z0-9%_.~-]+$/.test(path)) throw new Error('Invalid upstream path');
  return new Promise((resolve, reject) => {
    const request = http.get({ hostname: '127.0.0.1', port: 20128, path, headers: { authorization: `Bearer ${key}`, accept: 'application/json' } }, response => {
      let size = 0;
      const chunks = [];
      if (response.statusCode !== 200) { response.resume(); request.destroy(new Error('Upstream unavailable')); return; }
      response.on('data', chunk => {
        size += chunk.length;
        if (size > MAX_BODY) request.destroy(new Error('Upstream response exceeds limit'));
        else chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch { reject(new Error('Invalid upstream JSON')); }
      });
    });
    // Absolute deadline, not an inactivity timeout that a slow peer can extend.
    const timer = setTimeout(() => request.destroy(new Error('Upstream timeout')), 5000);
    request.on('error', reject);
    request.on('close', () => clearTimeout(timer));
  });
}

export async function pages(get, path, field, project) {
  const rows = [];
  const seen = new Set();
  let total;
  for (let page = 0; page < 10; page++) {
    const data = await get(`${path}?limit=100&offset=${rows.length}`);
    if (!Array.isArray(data[field]) || !Number.isSafeInteger(data.total) || data.total < 0 || data.total > MAX_ACCOUNTS) throw new Error('Invalid or excessive metadata');
    if (total !== undefined && total !== data.total) throw new Error('Metadata changed during pagination');
    total = data.total;
    for (const raw of data[field]) {
      const row = project(raw);
      const identity = field === 'connections' ? row.id : row.name;
      if (seen.has(identity)) throw new Error('Repeated metadata page');
      seen.add(identity);
      rows.push(row);
    }
    if (rows.length === total) return rows;
    if (rows.length > total || !data[field].length) throw new Error('Incomplete metadata');
  }
  throw new Error('Metadata pagination limit');
}

function safeConnection(raw) {
  if (!raw || typeof raw.id !== 'string' || !raw.id || raw.id.length > 256 || /[\p{Cc}\p{Cf}/\\]/u.test(raw.id) || ['.', '..', 'provider-limits'].includes(raw.id) || typeof raw.provider !== 'string') throw new Error('Invalid account metadata');
  return { id: raw.id, provider: raw.provider, isActive: raw.isActive === true };
}
function safeCombo(raw) {
  if (!raw || typeof raw.name !== 'string' || !Array.isArray(raw.models)) throw new Error('Invalid combo metadata');
  // Preserve routing structure for fail-closed resolution; never expose it.
  return raw;
}
function safeUsage(raw, fetchedAt) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('Invalid usage cache');
  // Never retain provider payload identity/token fields or arbitrary row strings.
  const source = Array.isArray(raw.quotas) ? raw.quotas : raw.quotas && typeof raw.quotas === 'object' ? Object.entries(raw.quotas).map(([key, value]) => ({ ...value, key })) : [];
  if (source.length > 512) throw new Error('Excessive quota windows');
  const fields = ['key', 'id', 'name', 'total', 'used', 'remaining', 'remainingPercentage', 'fractionReported', 'quotaSource', 'unlimited', 'resetTime', 'resetAt', 'resetTimeIso'];
  const quotas = source.map(row => Object.fromEntries(fields.filter(field => ['string', 'number', 'boolean'].includes(typeof row?.[field])).map(field => [field, row[field]])));
  return { quotas, fetchedAt: timestamp(fetchedAt) };
}

export function createAdapter({ allowedCombos, get, now = Date.now }) {
  let metadata;
  let metadataExpires = 0;
  let metadataPending;
  let cache = new Map();
  const jobs = new Map();
  const queue = [];
  let running = 0;

  function updateMetadata() {
    if (metadataPending || now() < metadataExpires) return;
    metadataExpires = now() + TTL;
    metadataPending = (async () => {
      try {
        const combos = await pages(get, '/api/combos', 'combos', safeCombo);
        const connections = await pages(get, '/api/providers', 'connections', safeConnection);
        const usage = await get('/api/usage/provider-limits');
        if (!usage?.caches || typeof usage.caches !== 'object' || Array.isArray(usage.caches)) throw new Error('Invalid usage metadata');
        const next = new Map();
        for (const connection of connections) {
          const raw = usage.caches[connection.id];
          if (raw) next.set(connection.id, safeUsage(raw, raw.fetchedAt));
          const previous = cache.get(connection.id);
          if (previous && (!next.has(connection.id) || Date.parse(previous.fetchedAt) > Date.parse(next.get(connection.id).fetchedAt ?? ''))) next.set(connection.id, previous);
        }
        cache = next;
        metadata = { combos, connections };
        for (const [id, job] of jobs) if (!job.pending && !connections.some(connection => connection.id === id)) jobs.delete(id);
      } catch {
        metadata = undefined; // Fail closed, including when previously valid metadata expires.
      } finally {
        metadataExpires = now() + TTL;
        metadataPending = undefined;
      }
    })();
  }

  function pump() {
    while (running < 2 && queue.length) {
      const id = queue.shift();
      running++;
      const job = jobs.get(id);
      Promise.resolve().then(() => get(`/api/usage/${encodeURIComponent(id)}`)).then(raw => {
        // Preserve provider observation time; never stamp an old payload as fresh.
        cache.set(id, safeUsage(raw, raw.fetchedAt));
        job.next = now() + STALE_MS;
      }).catch(() => { job.next = now() + TTL; }).finally(() => {
        job.pending = false;
        running--;
        pump();
      });
    }
  }

  function refresh(id) {
    const job = jobs.get(id);
    if (job?.pending || (job && now() < job.next) || queue.length >= MAX_ACCOUNTS) return;
    jobs.set(id, { pending: true, next: Infinity });
    queue.push(id);
    pump();
  }

  return {
    snapshot(name) {
      if (!allowedCombos.has(name)) return undefined;
      const expired = now() >= metadataExpires;
      updateMetadata();
      if (expired || metadataPending || !metadata) return envelope([status('Quota', 'Unavailable: metadata refresh pending or failed')]);
      try {
        const targets = resolveTargets(name, metadata.combos);
        const { selected, unsupported } = selectAccounts(targets, metadata.connections);
        const ordinals = new Map([...metadata.connections].sort((a, b) => a.id.localeCompare(b.id)).map((connection, index) => [connection.id, index + 1]));
        const rows = [...unsupported];
        for (const { account, pool } of selected) {
          const data = cache.get(account.id);
          const observed = timestamp(data?.fetchedAt);
          const age = observed ? now() - Date.parse(observed) : Infinity;
          if (age > STALE_MS || age < 0) refresh(account.id);
          rows.push(...quotaRows(account, pool, data, ordinals.get(account.id), now()));
        }
        return envelope(rows);
      } catch {
        return envelope([status('Quota', 'Unavailable: unsupported or ambiguous combo routing')]);
      }
    },
    async settled() {
      // Test seam; production requests never await metadata or refresh work.
      await metadataPending;
    },
  };
}

export function createServer(adapter, port = 20129) {
  const server = http.createServer({ maxHeaderSize: 8192, requestTimeout: 5000, headersTimeout: 5000 }, (request, response) => {
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const finish = (code, body) => { response.writeHead(code); response.end(JSON.stringify(body)); };
    if (request.headers.origin !== undefined || request.headers.host !== `127.0.0.1:${port}`) return finish(403, envelope([status('Quota', 'Forbidden')]));
    if (request.method !== 'GET') return finish(405, envelope([status('Quota', 'GET only')]));
    if (typeof request.url !== 'string' || request.url.length > 1024 || !/^\/combos\/[^/?#]+$/.test(request.url)) return finish(404, envelope([status('Quota', 'Not found')]));
    let name;
    try { name = decodeURIComponent(request.url.slice('/combos/'.length)); } catch { return finish(400, envelope([status('Quota', 'Invalid path')])); }
    if (!name || /[\p{Cc}\p{Cf}/\\]/u.test(name)) return finish(400, envelope([status('Quota', 'Invalid path')]));
    const body = adapter.snapshot(name);
    finish(body ? 200 : 404, body ?? envelope([status('Quota', 'Not found')]));
  });
  server.maxConnections = 32;
  server.maxRequestsPerSocket = 100;
  server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  return server;
}

async function main() {
  const key = await readKey(process.env.OMNIROUTE_QUOTA_KEY_FILE);
  const names = JSON.parse(await readFile(process.env.OMNIROUTE_QUOTA_COMBOS_FILE, 'utf8'));
  if (!Array.isArray(names) || names.length < 1 || names.length > 100 || !names.every(name => typeof name === 'string' && name.length > 0 && name.length <= 200 && !/[\p{Cc}\p{Cf}/\\]/u.test(name))) throw new Error('Invalid combo allowlist');
  const adapter = createAdapter({ allowedCombos: new Set(names), get: path => upstreamJSON(path, key) });
  const server = createServer(adapter);
  server.on('error', () => { console.error('Quota adapter could not listen'); process.exitCode = 1; });
  server.listen(20129, '127.0.0.1');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => { console.error('Quota adapter startup failed; check private credential and allowlist files'); process.exitCode = 1; });
}

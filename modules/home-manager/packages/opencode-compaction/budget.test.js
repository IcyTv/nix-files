// @ts-check
import assert from "node:assert/strict";
import test from "node:test";
import { Budget, HARD_LIMIT, SOFT_LIMIT, inputTokens, observation } from "./budget.js";

/** @param {number} input @param {object} [extra] */
export function assistant(input, extra = {}) {
  return {
    type: /** @type {const} */ ("assistant"), id: "msg_assistant", agent: "build",
    model: { providerID: "openai", id: "gpt-6.1-sol" }, content: [],
    time: { created: 20, completed: 21 }, finish: "stop",
    tokens: { input, output: 900_000, reasoning: 80_000, cache: { read: 0, write: 0 } },
    ...extra,
  };
}

/** @param {"running" | "completed" | "failed"} status */
export function checkpoint(status) {
  const common = { type: "compaction", id: "msg_checkpoint", reason: "manual", time: { created: 30 }, status };
  if (status === "failed") return { ...common, error: { type: "unknown", message: "test failure" } };
  return { ...common, summary: "checkpoint", tokens: { input: 700_000, output: 1000, reasoning: 0, cache: { read: 0, write: 0 } } };
}

function harness() {
  /** @type {Map<string, import('./budget.js').Message[]>} */
  const histories = new Map();
  /** @type {Map<string, import('./budget.js').State>} */
  const storage = new Map();
  /** @type {string[]} */
  const queued = [];
  let fail = false;
  const api = {
    /** @param {string} id */
    context: async (id) => histories.get(id) ?? [],
    /** @param {string} id */
    compact: async (id) => { queued.push(id); if (fail) throw new Error("admission failed"); return { id: `msg_queued_${queued.length}` }; },
    /** @param {string} key */
    load: async (key) => structuredClone(storage.get(key)),
    /** @param {string} key @param {import('./budget.js').State} state */
    save: async (key, state) => { storage.set(key, structuredClone(state)); },
  };
  return { budget: new Budget(api), api, histories, storage, queued, fail: () => { fail = true; } };
}

test("V2 stored input adds cache reads/writes once, never output or reasoning", () => {
  assert.equal(inputTokens(assistant(20_000).tokens), 20_000);
  assert.equal(inputTokens({ input: 20_000, output: 900_000, reasoning: 50_000, cache: { read: 210_000, write: 10_000 } }), SOFT_LIMIT);
  assert.equal(inputTokens(undefined), undefined);
  assert.equal(inputTokens({ input: NaN, output: 0, reasoning: 0, cache: { read: 0, write: 0 } }), undefined);
});

test("cross-instance observers cannot overwrite concurrent controls for sessions at the same location", async () => {
  const h = harness();
  // A separate module evaluation represents an overlapping plugin reload.
  const { Budget: ReloadedBudget } = await import("./budget.js?concurrent-instance");
  const other = new ReloadedBudget(h.api);
  const readContext = h.api.context;
  let unblock;
  let started;
  const blocked = new Promise((resolve) => { unblock = resolve; });
  const entered = new Promise((resolve) => { started = resolve; });
  let first = true;
  h.api.context = async (id) => {
    if (id === "a" && first) {
      first = false;
      started();
      await blocked;
    }
    return readContext(id);
  };
  h.histories.set("a", [assistant(100_000)]);
  const staleObserver = h.budget.observe("a");
  await entered;
  const hardOff = other.command("a", "hard off");
  // A different session must remain independently usable while a is blocked.
  await other.command("b", "soft off");
  unblock();
  await Promise.all([staleObserver, hardOff]);
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  assert.deepEqual({
    a: { hard: h.storage.get("session/a")?.hard, soft: h.storage.get("session/a")?.soft },
    b: { hard: h.storage.get("session/b")?.hard, soft: h.storage.get("session/b")?.soft },
    queued: h.queued,
  }, { a: { hard: false, soft: true }, b: { hard: true, soft: false }, queued: [] });
});

test("unchanged inspections do not write durable settings", async () => {
  const h = harness();
  let writes = 0;
  const save = h.api.save;
  h.api.save = async (key, state) => { writes++; await save(key, state); };
  await h.budget.command("a", "hard off");
  writes = 0;
  await h.budget.command("a", "status");
  await h.budget.observe("a");
  await h.budget.cancelled("a", "msg_unrelated");
  assert.equal(writes, 0);
});

test("soft boundary is inclusive and advisory is emitted once, not a compaction", async () => {
  const h = harness();
  h.histories.set("a", [assistant(SOFT_LIMIT - 1)]);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.histories.set("a", [assistant(SOFT_LIMIT)]);
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /next safe milestone.*unless the user asked otherwise/);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  assert.deepEqual(h.queued, []);
});

test("hard boundary is inclusive, independent of soft, and serialized against duplicate calls", async () => {
  const h = harness();
  await h.budget.command("a", "soft off");
  h.histories.set("a", [assistant(HARD_LIMIT - 1)]);
  await h.budget.observe("a");
  assert.equal(h.queued.length, 0);
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await Promise.all([h.budget.observe("a"), h.budget.observe("a"), h.budget.voluntary("a")]);
  assert.deepEqual(h.queued, ["a"]);
});

test("latest completed request is used, never cumulative history, streaming, failed or summary usage", () => {
  const messages = [
    assistant(700_000, { id: "msg_old", time: { created: 1, completed: 2 } }),
    assistant(100_000),
    assistant(900_000, { time: { created: 40 } }),
    assistant(900_000, { time: { created: 50, completed: 51 }, error: { type: "unknown", message: "failed" } }),
  ];
  assert.equal(observation(messages).input, 100_000);
  assert.equal(observation([assistant(700_000), checkpoint("completed")]).input, undefined);
});

test("provider switches do not reuse OpenAI usage or trigger on another provider", async () => {
  const h = harness();
  h.histories.set("a", [assistant(HARD_LIMIT, { model: { providerID: "google-agy", id: "gemini" } })]);
  await h.budget.observe("a");
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a", { provider: "google-agy", advisory: true });
  h.histories.set("a", [assistant(HARD_LIMIT), {
    type: "model-switched", id: "msg_switch", time: { created: 30 }, model: { providerID: "openai", id: "gpt-6.1-sol" },
  }]);
  await h.budget.observe("a");
  assert.equal(h.queued.length, 0);
  h.histories.get("a")?.push(assistant(HARD_LIMIT, { time: { created: 40, completed: 41 } }));
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
});

test("settings and one-shot advisory survive reload and remain isolated from sessions/forks", async () => {
  const h = harness();
  await h.budget.command("a", "hard 600000");
  await h.budget.command("a", "hard off");
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a", { advisory: true });
  const reloaded = new Budget(h.api);
  assert.equal(await reloaded.observe("a", { advisory: true }), undefined);
  assert.match(await reloaded.command("a", "status"), /hard: off at 600000/);
  h.histories.set("fork", h.histories.get("a") ?? []);
  await reloaded.observe("fork");
  assert.deepEqual(h.queued, ["fork"]);
  assert.match(await reloaded.command("b", "status"), /Soft: on at 240000; hard: on at 500000/);
});

test("independent toggles and configurable limit do not change native configuration", async () => {
  const h = harness();
  await h.budget.command("a", "hard off");
  h.histories.set("a", [assistant(600_000)]);
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /advisory/);
  assert.equal(h.queued.length, 0);
  await h.budget.command("a", "hard 650000");
  await h.budget.command("a", "hard on");
  await h.budget.observe("a");
  assert.equal(h.queued.length, 0);
  h.histories.set("a", [assistant(650_000)]);
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
  assert.equal(h.storage.get("session/a")?.soft, true);
});

test("controls reject invalid thresholds and extra arguments without changing settings", async () => {
  const h = harness();
  for (const text of ["hard 0", "hard -1", "hard 1.5", "hard Infinity", "hard 9007199254740992", "soft off extra", "reset extra", "status extra"]) {
    assert.match(await h.budget.command("a", text), /No settings changed/);
  }
  assert.match(await h.budget.command("a", ""), /hard: on at 500000/);
});

test("pending admission survives reload and off/reset do not duplicate admitted compaction", async () => {
  const h = harness();
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  const reloaded = new Budget(h.api);
  await reloaded.command("a", "hard off");
  await reloaded.command("a", "reset");
  await reloaded.observe("a");
  assert.match(await reloaded.voluntary("a"), /already pending/);
  assert.deepEqual(h.queued, ["a"]);
});

test("admission failure is latched across requests/reload, user can rearm explicitly", async () => {
  const h = harness();
  h.fail();
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  await new Budget(h.api).observe("a");
  await h.budget.voluntary("a");
  assert.deepEqual(h.queued, ["a"]);
  await h.budget.command("a", "hard on");
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a", "a"]);
});

test("cancelled admitted control does not retry until the user rearms it", async () => {
  const h = harness();
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  await h.budget.cancelled("a", "msg_unrelated");
  assert.equal(h.storage.get("session/a")?.pending, true);
  await h.budget.cancelled("a", "msg_queued_1");
  await new Budget(h.api).observe("a");
  assert.equal(h.queued.length, 1);
  await h.budget.command("a", "reset");
  await h.budget.observe("a");
  assert.equal(h.queued.length, 2);
});

test("native/running compaction blocks duplicate; failure stops retry storms until reset", async () => {
  const h = harness();
  h.histories.set("a", [assistant(HARD_LIMIT), checkpoint("running")]);
  await h.budget.observe("a");
  assert.equal(h.queued.length, 0);
  h.histories.set("a", [assistant(HARD_LIMIT), checkpoint("failed")]);
  await h.budget.observe("a");
  await h.budget.observe("a");
  assert.equal(h.queued.length, 0);
  await h.budget.command("a", "reset");
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
});

test("successful native checkpoint clears a stale failure, then fresh low usage rearms automation", async () => {
  const h = harness();
  h.histories.set("a", [assistant(HARD_LIMIT), checkpoint("failed")]);
  await h.budget.observe("a");
  h.histories.set("a", [checkpoint("completed"), assistant(100_000, { time: { created: 40, completed: 41 } })]);
  await h.budget.observe("a");
  assert.equal(h.storage.get("session/a")?.failed, false);
  h.histories.get("a")?.push(assistant(HARD_LIMIT, { time: { created: 50, completed: 51 } }));
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
});

test("success discards old usage, resets advisory, and requires low input before another automatic compaction", async () => {
  const h = harness();
  h.histories.set("a", [assistant(SOFT_LIMIT)]);
  await h.budget.observe("a", { advisory: true });
  h.histories.set("a", [assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  h.histories.set("a", [checkpoint("completed"), assistant(HARD_LIMIT)]);
  await h.budget.observe("a");
  h.histories.get("a")?.push(assistant(HARD_LIMIT, { time: { created: 40, completed: 41 } }));
  await h.budget.observe("a");
  assert.equal(h.queued.length, 1);
  h.histories.set("a", [checkpoint("completed"), assistant(SOFT_LIMIT, { time: { created: 50, completed: 51 } })]);
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /advisory/);
  h.histories.get("a")?.push(assistant(HARD_LIMIT, { time: { created: 60, completed: 61 } }));
  await h.budget.observe("a");
  assert.equal(h.queued.length, 2);
});

test("voluntary compaction ignores automatic toggles but cannot alter controls or target another session", async () => {
  const h = harness();
  await h.budget.command("a", "soft off");
  await h.budget.command("a", "hard off");
  await h.budget.command("a", "hard 750000");
  assert.match(await h.budget.voluntary("a"), /queued.*not finished/);
  assert.match(await h.budget.voluntary("a"), /already pending/);
  assert.deepEqual(h.queued, ["a"]);
  assert.match(await h.budget.command("a", "status"), /Soft: off at 240000; hard: off at 750000/);
  assert.match(await h.budget.command("b", "status"), /hard: on at 500000/);
});

// @ts-check
import assert from "node:assert/strict";
import test from "node:test";
import { Budget, HARD_LIMIT, SOFT_LIMIT, OMNI_SOFT_LIMIT, defaults, inputTokens, observation, policy } from "./budget.js";

const openai = { providerID: "openai", id: "gpt-6.1-sol" };
const omni = { providerID: "omniroute", id: "orchestrator" };

/** @param {number} input @param {object} [extra] */
function omniAssistant(input, extra = {}) {
  return assistant(input, { model: omni, ...extra });
}

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

/** @param {import('./budget.js').Model} [initialModel] */
function harness(initialModel = openai) {
  /** @type {Map<string, import('./budget.js').Message[]>} */
  const histories = new Map();
  /** @type {Map<string, import('./budget.js').Model | undefined>} */
  const models = new Map();
  /** @type {Map<string, import('./budget.js').State | Omit<import('./budget.js').State, 'overrides'>>} */
  const storage = new Map();
  /** @type {string[]} */
  const queued = [];
  let fail = false;
  const api = {
    /** @param {string} id */
    context: async (id) => histories.get(id) ?? [],
    /** @param {string} id */
    model: async (id) => models.has(id) ? models.get(id) : initialModel,
    /** @param {string} id */
    compact: async (id) => { queued.push(id); if (fail) throw new Error("admission failed"); return { id: `msg_queued_${queued.length}` }; },
    /** @param {string} key */
    load: async (key) => structuredClone(storage.get(key)),
    /** @param {string} key @param {import('./budget.js').State} state */
    save: async (key, state) => { storage.set(key, structuredClone(state)); },
  };
  return { budget: new Budget(api), api, histories, models, storage, queued, fail: () => { fail = true; } };
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
  await h.budget.observe("a", { model: { providerID: "google-agy", id: "gemini" }, advisory: true });
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

test("exact managed core IDs alone enable OmniRoute budgets, all OmniRoute models get the tool", () => {
  for (const id of ["orchestrator", "exploration", "research", "mechanical", "implementation", "verification",
    "architecture", "review", "implementation-deep", "architecture-deep", "review-deep"]) {
    assert.equal(policy({ ...omni, id }).budget, true, id);
    assert.equal(policy({ ...omni, id }).hard, false, id);
  }
  for (const id of ["role-implementation", "role-orchestrator", "cloudflare-free", "unknown", "copilot", "orchestrator-extra"]) {
    const route = policy({ ...omni, id });
    assert.equal(route.tool, true, id);
    assert.equal(route.budget, false, id);
    assert.equal(route.softLimit, undefined, id);
  }
  assert.equal(policy({ providerID: "google-agy", id: "gemini" }).tool, false);
});

test("OmniRoute 500K input advisory includes cache once and never queues automatic fallback by default", async () => {
  const h = harness();
  h.models.set("a", omni);
  h.histories.set("a", [omniAssistant(OMNI_SOFT_LIMIT - 1)]);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.histories.set("a", [omniAssistant(200_000, {
    tokens: { input: 200_000, output: 900_000, reasoning: 80_000, cache: { read: 290_000, write: 10_000 } },
  })]);
  assert.match(await h.budget.observe("a", { model: omni, advisory: true }) ?? "", /OmniRoute core.*500,000 input tokens/);
  assert.equal(await new Budget(h.api).observe("a", { advisory: true }), undefined);
  h.histories.set("a", [omniAssistant(839_232)]);
  await h.budget.observe("a");
  await h.budget.observe("a", { model: omni, advisory: true });
  assert.deepEqual(h.queued, []);
  assert.match(await h.budget.command("a", "status"), /Soft: on at 500000; hard: off at 500000/);
});

test("old stored OpenAI defaults stay hard-off on OmniRoute without migration writes", async () => {
  const h = harness(omni);
  const { overrides: _overrides, ...legacy } = defaults();
  h.storage.set("session/a", legacy);
  h.histories.set("a", [omniAssistant(800_000)]);
  await h.budget.observe("a");
  assert.match(await h.budget.command("a", "status"), /OmniRoute core.*hard: off at 500000/);
  assert.deepEqual(h.queued, []);
  assert.deepEqual(h.storage.get("session/a"), legacy);
  h.models.set("a", openai);
  assert.match(await h.budget.command("a", "status"), /hard: on at 500000/);
});

test("new stored implicit OpenAI defaults follow OmniRoute policy, explicit defaults survive reload", async () => {
  const h = harness(omni);
  h.storage.set("session/a", defaults());
  h.histories.set("a", [omniAssistant(800_000)]);
  await h.budget.observe("a");
  assert.match(await new Budget(h.api).command("a", "status"), /hard: off at 500000/);
  assert.deepEqual(h.queued, []);
  h.models.set("a", openai);
  await h.budget.command("a", "soft on");
  await h.budget.command("a", "hard on");
  await h.budget.command("a", "hard 500000");
  h.models.set("a", omni);
  assert.match(await new Budget(h.api).command("a", "status"), /Soft: on at 500000; hard: on at 500000/);
  await new Budget(h.api).observe("a");
  assert.deepEqual(h.queued, ["a"]);
});

test("legacy nondefault controls survive provider switches without implicit OmniRoute opt-in", async () => {
  const h = harness(omni);
  const { overrides: _overrides, ...legacy } = defaults();
  h.storage.set("session/a", { ...legacy, soft: false, hardLimit: 700_000 });
  h.histories.set("a", [omniAssistant(800_000)]);
  assert.match(await h.budget.command("a", "status"), /Soft: off at 500000; hard: off at 700000/);
  await h.budget.observe("a");
  assert.deepEqual(h.queued, []);
  h.models.set("a", openai);
  assert.match(await h.budget.command("a", "status"), /Soft: off at 240000; hard: on at 700000/);
  h.storage.set("session/b", { ...legacy, hard: false });
  h.models.set("b", openai);
  assert.match(await h.budget.command("b", "status"), /hard: off at 500000/);
});

test("explicit session controls survive switches and reset restores the active route defaults", async () => {
  const h = harness();
  h.models.set("a", openai);
  await h.budget.command("a", "soft off");
  await h.budget.command("a", "hard on");
  await h.budget.command("a", "hard 700000");
  h.models.set("a", omni);
  assert.match(await h.budget.command("a", "status"), /Soft: off at 500000; hard: on at 700000/);
  await h.budget.command("a", "hard off");
  h.models.set("a", openai);
  assert.match(await h.budget.command("a", "status"), /Soft: off at 240000; hard: off at 700000/);
  h.models.set("a", omni);
  assert.match(await h.budget.command("a", "reset"), /Soft: on at 500000; hard: off at 500000/);
  assert.match(await h.budget.command("b", "status"), /Soft: on at 240000; hard: on at 500000/);
  h.models.set("a", openai);
  assert.match(await h.budget.command("a", "status"), /Soft: on at 240000; hard: on at 500000/);
  await h.budget.command("a", "hard off");
  assert.match(await h.budget.command("a", "reset"), /hard: on at 500000/);
});

test("OmniRoute explicit hard control is opt-in and retains the fixed-prompt retry gate", async () => {
  const h = harness(omni);
  h.histories.set("a", [omniAssistant(800_000)]);
  await h.budget.command("a", "hard 600000");
  await h.budget.observe("a");
  assert.deepEqual(h.queued, []);
  await h.budget.command("a", "hard on");
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
  h.histories.set("a", [checkpoint("completed"), omniAssistant(800_000, { time: { created: 40, completed: 41 } })]);
  await h.budget.observe("a");
  assert.match(await h.budget.voluntary("a"), /already attempted/);
  assert.deepEqual(h.queued, ["a"]);
});

test("unknown and small OmniRoute models allow voluntary compaction but never budget controls", async () => {
  for (const id of ["role-implementation", "cloudflare-free", "unknown"]) {
    const h = harness();
    h.models.set("a", { ...omni, id });
    h.histories.set("a", [assistant(900_000, { model: { ...omni, id } })]);
    await h.budget.command("a", "hard on");
    await h.budget.command("a", "hard 1");
    assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
    assert.match(await h.budget.command("a", "status"), /no managed budget.*Soft: on at n\/a.*inactive: no managed budget/);
    assert.deepEqual(h.queued, []);
    assert.match(await h.budget.voluntary("a"), /queued.*not finished/);
    assert.deepEqual(h.queued, ["a"]);
  }
});

test("current provider and exact model must match measured usage in both hooks and step observations", async () => {
  const h = harness();
  h.histories.set("a", [assistant(800_000)]);
  assert.equal(await h.budget.observe("a", { model: omni, advisory: true }), undefined);
  h.models.set("a", omni);
  await h.budget.observe("a");
  h.histories.set("a", [omniAssistant(800_000)]);
  h.models.set("a", openai);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.models.set("a", { ...omni, id: "implementation" });
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.histories.set("a", [assistant(800_000)]);
  assert.equal(await h.budget.observe("a", { model: { ...openai, id: "different-model" }, advisory: true }), undefined);
  h.histories.set("a", [omniAssistant(800_000), {
    type: "model-switched", id: "msg_omni_switch", time: { created: 30 }, model: omni,
  }]);
  h.models.set("a", omni);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.histories.get("a")?.push(omniAssistant(800_000, { time: { created: 40, completed: 41 } }));
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /OmniRoute core/);
  assert.deepEqual(h.queued, []);
});

test("OmniRoute advisory dedup survives provider switches and fresh high fixed prompts do not requeue", async () => {
  const h = harness(omni);
  h.histories.set("a", [omniAssistant(800_000)]);
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /advisory/);
  assert.match(await h.budget.voluntary("a"), /queued/);
  h.histories.set("a", [checkpoint("completed"), omniAssistant(800_000, { time: { created: 40, completed: 41 } })]);
  await h.budget.observe("a");
  assert.match(await h.budget.voluntary("a"), /already attempted/);
  assert.match(await h.budget.observe("a", { advisory: true }) ?? "", /advisory/);
  h.models.set("a", openai);
  h.histories.set("a", [assistant(300_000)]);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  h.models.set("a", omni);
  h.histories.set("a", [omniAssistant(800_000)]);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  assert.deepEqual(h.queued, ["a"]);
});

test("unproven current selection never borrows policy from historical usage", async () => {
  const h = harness();
  h.models.set("a", undefined);
  h.histories.set("a", [assistant(800_000)]);
  assert.equal(await h.budget.observe("a", { advisory: true }), undefined);
  assert.deepEqual(h.queued, []);
  const status = await h.budget.command("a", "status");
  assert.match(status, /Current policy unproven/);
  assert.doesNotMatch(status, /OpenAI|hard: on/);
  // A request hook has the authoritative resolved route, even without a pin.
  assert.equal(await h.budget.observe("a", { model: omni, advisory: true }), undefined);
  h.histories.set("a", [omniAssistant(800_000)]);
  assert.match(await h.budget.observe("a", { model: omni, advisory: true }) ?? "", /OmniRoute core/);
  assert.deepEqual(h.queued, []);
});

test("event selection is read after awaited history so an interleaved switch cannot trigger stale policy", async () => {
  const h = harness();
  let enter;
  let release;
  const entered = new Promise((resolve) => { enter = resolve; });
  const blocked = new Promise((resolve) => { release = resolve; });
  h.histories.set("a", [assistant(800_000)]);
  h.api.context = async (id) => {
    enter();
    await blocked;
    return h.histories.get(id) ?? [];
  };
  const inspection = h.budget.observe("a", { advisory: true });
  await entered;
  h.models.set("a", omni);
  release();
  assert.equal(await inspection, undefined);
  assert.deepEqual(h.queued, []);
  h.models.set("a", openai);
  await h.budget.observe("a");
  assert.deepEqual(h.queued, ["a"]);
});

test("unmanaged OmniRoute voluntary cycles rearm only after success and fresh low usage, never enable budgets", async () => {
  for (const id of ["cloudflare-free", "role-implementation", "unknown"]) {
    for (const pinned of [true, false]) {
      const model = { ...omni, id };
      const h = harness(model);
      h.models.set("a", pinned ? model : undefined);
      h.histories.set("a", [assistant(900_000, { model })]);
      await h.budget.command("a", "hard on");
      assert.equal(await h.budget.observe("a", { model, advisory: true }), undefined);
      assert.deepEqual(h.queued, []);
      assert.match(await h.budget.voluntary("a"), /queued/);
      const first = checkpoint("completed");
      h.histories.set("a", [first]);
      assert.match(await h.budget.voluntary("a"), /already attempted/);
      h.histories.get("a")?.push(assistant(800_000, { model, time: { created: 40, completed: 41 } }));
      assert.equal(await h.budget.observe("a", { model, advisory: true }), undefined);
      assert.match(await h.budget.voluntary("a"), /already attempted/);
      assert.deepEqual(h.queued, ["a"]);
      h.histories.get("a")?.push(assistant(100_000, { model, time: { created: 50, completed: 51 } }));
      assert.match(await h.budget.voluntary("a"), /queued/);
      h.histories.set("a", [first, {
        ...checkpoint("completed"), id: "msg_second_checkpoint", time: { created: 60 },
      }, assistant(100_000, { model, time: { created: 70, completed: 71 } })]);
      assert.equal(await h.budget.observe("a", { model, advisory: true }), undefined);
      assert.deepEqual(h.queued, ["a", "a"]);
      assert.equal(h.storage.get("session/a")?.pending, false);
      assert.equal(h.storage.get("session/a")?.attempted, false);
      h.histories.get("a")?.push(assistant(900_000, { model, time: { created: 80, completed: 81 } }));
      assert.equal(await h.budget.observe("a", { model, advisory: true }), undefined);
      await h.budget.observe("a");
      assert.deepEqual(h.queued, ["a", "a"]);
    }
  }
});

test("fresh low unmanaged OmniRoute usage cannot clear failure or cancellation latches", async () => {
  for (const reason of ["failed", "cancelled"]) {
    const model = { ...omni, id: "cloudflare-free" };
    const h = harness(model);
    h.models.set("a", undefined);
    h.histories.set("a", [assistant(900_000, { model })]);
    assert.match(await h.budget.voluntary("a"), /queued/);
    if (reason === "failed") h.histories.set("a", [checkpoint("failed")]);
    else await h.budget.cancelled("a", "msg_queued_1");
    h.histories.get("a")?.push(assistant(100_000, { model, time: { created: 40, completed: 41 } }));
    await h.budget.observe("a", { model, advisory: true });
    assert.match(await new Budget(h.api).voluntary("a"), /already attempted/);
    assert.deepEqual(h.queued, ["a"]);
    await h.budget.command("a", "reset");
    assert.match(await h.budget.voluntary("a"), /queued/);
    assert.deepEqual(h.queued, ["a", "a"]);
  }
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

// @ts-check

export const SOFT_LIMIT = 240_000;
export const HARD_LIMIT = 500_000;
export const OMNI_SOFT_LIMIT = 500_000;

const coreModels = new Set([
  "orchestrator", "exploration", "research", "mechanical", "implementation", "verification",
  "architecture", "review", "implementation-deep", "architecture-deep", "review-deep",
]);

/** @typedef {import('@opencode/client').ModelRef} Model */
/**
 * One route policy serves tool visibility, completed-step checks and request hooks.
 * Legacy role-prefixed combos and unknown OmniRoute models are voluntary-only.
 * @param {Model | undefined} model
 */
export function policy(model) {
  const openai = model?.providerID === "openai";
  const omni = model?.providerID === "omniroute";
  const core = omni && coreModels.has(model.id);
  return {
    tool: openai || omni,
    budget: openai || core,
    softLimit: openai ? SOFT_LIMIT : core ? OMNI_SOFT_LIMIT : undefined,
    hard: openai,
    hardLimit: HARD_LIMIT,
    label: openai ? `OpenAI (${model.id})` : core ? `OmniRoute core (${model.id})` :
      model ? `${model.providerID}/${model.id} (no managed budget policy)` : "Current policy unproven (no authoritative model selection)",
  };
}

/** @typedef {ReturnType<typeof policy>} Policy */
/** @typedef {{soft?: boolean, hard?: boolean, hardLimit?: number}} Overrides */

// Plugin storage is shared by plugin ID, not by location. Keep the matching
// session lock shared across location instances and overlapping module reloads.
const lockKey = Symbol.for("local.context-budget.session-locks");
/** @type {Map<string, Promise<unknown>>} */
const locks = Reflect.get(globalThis, lockKey) ?? new Map();
Reflect.set(globalThis, lockKey, locks);

/** @typedef {import('@opencode/client').SessionMessageInfo} Message */
/** @typedef {import('@opencode/client').TokenUsageInfo} Tokens */
/**
 * @typedef {object} State
 * @property {boolean} soft Legacy snapshot; effective controls use overrides and route defaults.
 * @property {boolean} hard Legacy snapshot; never used as a route-independent default.
 * @property {number} hardLimit Legacy snapshot retained for stored-session compatibility.
 * @property {Overrides} overrides Explicit user choices, including values equal to defaults.
 * @property {boolean} notified
 * @property {boolean} attempted
 * @property {boolean} pending
 * @property {boolean} failed
 * @property {string} checkpoint
 * @property {string} pendingID
 */
/**
 * @typedef {object} API
 * @property {(id: string) => Promise<readonly Message[]>} context
 * @property {(id: string) => Promise<Model | undefined>} [model]
 * @property {(id: string) => Promise<{id: string}>} compact
 * @property {(key: string) => Promise<unknown>} load
 * @property {(key: string, state: State) => Promise<void>} save
 */

/** @returns {State} */
export function defaults() {
  return {
    soft: true, hard: true, hardLimit: HARD_LIMIT, overrides: {},
    notified: false, attempted: false, pending: false, failed: false, checkpoint: "", pendingID: "",
  };
}

/** @param {unknown} raw @returns {State} */
function restore(raw) {
  const state = defaults();
  if (!raw || typeof raw !== "object") return state;
  for (const key of ["soft", "hard", "notified", "attempted", "pending", "failed"]) {
    const value = Reflect.get(raw, key);
    if (typeof value === "boolean") Reflect.set(state, key, value);
  }
  const limit = Reflect.get(raw, "hardLimit");
  if (Number.isSafeInteger(limit) && limit > 0) state.hardLimit = limit;
  const checkpoint = Reflect.get(raw, "checkpoint");
  if (typeof checkpoint === "string") state.checkpoint = checkpoint;
  const pendingID = Reflect.get(raw, "pendingID");
  if (typeof pendingID === "string") state.pendingID = pendingID;
  const overrides = Reflect.get(raw, "overrides");
  if (overrides && typeof overrides === "object") {
    for (const key of ["soft", "hard"]) {
      const value = Reflect.get(overrides, key);
      if (typeof value === "boolean") Reflect.set(state.overrides, key, value);
    }
    const limit = Reflect.get(overrides, "hardLimit");
    if (Number.isSafeInteger(limit) && limit > 0) state.overrides.hardLimit = limit;
  } else {
    // Old OpenAI defaults have no provenance. Preserve distinguishable user
    // choices, but never reinterpret an old default hard=true as an Omni opt-in.
    if (!state.soft) state.overrides.soft = false;
    if (!state.hard) state.overrides.hard = false;
    if (state.hardLimit !== HARD_LIMIT) state.overrides.hardLimit = state.hardLimit;
  }
  return state;
}

/** @param {State} state @param {Policy} route */
function controls(state, route) {
  return {
    soft: state.overrides.soft ?? true,
    hard: state.overrides.hard ?? route.hard,
    hardLimit: state.overrides.hardLimit ?? route.hardLimit,
  };
}

/** @param {Model | undefined} left @param {Model | undefined} right */
function sameModel(left, right) {
  return left !== undefined && right !== undefined && left.providerID === right.providerID && left.id === right.id;
}

/**
 * V2 SessionUsage.tokens stores *non-cached* input separately from cache reads/writes.
 * Do not use AI.Usage.inputTokens (already inclusive), output, or session totals here.
 * @param {Tokens | undefined} tokens
 */
export function inputTokens(tokens) {
  if (!tokens) return undefined;
  const parts = [tokens.input, tokens.cache.read, tokens.cache.write];
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return undefined;
  return parts.reduce((sum, n) => sum + n, 0);
}

/** @param {readonly Message[]} messages @param {Model} [active] */
export function observation(messages, active) {
  // Context can retain pre-checkpoint assistant messages beside the new summary.
  // Compare creation times, not array position, and never count the summary request.
  const checkpoint = messages.filter((m) => m.type === "compaction")
    .reduce((last, m) => !last || m.time.created >= last.time.created ? m : last,
      /** @type {Message | undefined} */ (undefined));
  const switched = messages.filter((m) => m.type === "model-switched")
    .reduce((last, m) => !last || m.time.created >= last.time.created ? m : last,
      /** @type {Message | undefined} */ (undefined));
  const cutoff = messages.filter((m) => m.type === "model-switched" ||
    (m.type === "compaction" && m.status === "completed"))
    .reduce((time, m) => Math.max(time, m.time.created), -1);
  const assistant = messages.filter((m) => m.type === "assistant" &&
    m.time.completed !== undefined && !m.error && m.tokens)
    .reduce((last, m) => !last || m.time.created >= last.time.created ? m : last,
      /** @type {Message | undefined} */ (undefined));
  const measured = assistant?.type === "assistant" ? assistant.model : undefined;
  const model = active ?? (switched?.type === "model-switched" &&
    switched.time.created >= (assistant?.time.created ?? -1) ? switched.model : measured);
  // History can prove fresh low usage for the voluntary retry gate, but cannot
  // resolve the current agent/default selection or authorize automatic policy.
  const route = policy(active);
  const input = assistant?.type === "assistant" && assistant.time.created > cutoff &&
    sameModel(measured, model) && policy(model).tool ? inputTokens(assistant.tokens) : undefined;
  return { checkpoint, input, model, policy: route };
}

export class Budget {
  /** @param {API} api */
  constructor(api) {
    this.api = api;
  }

  /** @template T @param {string} id @param {(state: State) => Promise<T>} action */
  run(id, action) {
    const key = `session/${id}`;
    const result = (locks.get(id) ?? Promise.resolve()).catch(() => {}).then(async () => {
      const state = restore(await this.api.load(key));
      const before = JSON.stringify(state);
      const value = await action(state);
      if (JSON.stringify(state) !== before) await this.api.save(key, state);
      return value;
    });
    locks.set(id, result);
    const release = () => { if (locks.get(id) === result) locks.delete(id); };
    void result.then(release, release);
    return result;
  }

  /** @param {string} id @param {Model} [active] */
  async current(id, active) {
    const messages = await this.api.context(id);
    // Session pins can change while context is loading. Read selection last;
    // without a pin only the request hook's resolved model proves policy.
    const model = active ?? await this.api.model?.(id);
    return observation(messages, model);
  }

  /** @param {State} state @param {ReturnType<typeof observation>} current */
  sync(state, current) {
    const checkpoint = current.checkpoint;
    if (checkpoint?.type === "compaction") {
      const marker = `${checkpoint.id}/${checkpoint.status}`;
      if (state.checkpoint !== marker) {
        state.checkpoint = marker;
        state.pending = checkpoint.status === "running";
        if (!state.pending) state.pendingID = "";
        if (checkpoint.status === "completed") {
          state.notified = false;
          state.failed = false;
        }
        if (checkpoint.status === "failed") state.failed = true;
      }
    }
    // A completed compaction alone does not rearm attempts. Fresh low-input
    // usage must prove it helped. All tool routes may rearm; this safety threshold
    // does not authorize advisory or automatic budgets on unmanaged routes.
    if (!state.pending && !state.failed && policy(current.model).tool && current.input !== undefined &&
      current.input < controls(state, current.policy).hardLimit) {
      state.attempted = false;
    }
    return current.input;
  }

  /** @param {string} id @param {State} state */
  async enqueue(id, state) {
    if (state.pending || state.failed || state.attempted) return false;
    state.pending = true;
    state.attempted = true;
    // Persist before admission: a crash or ambiguous error must not retry on reload.
    await this.api.save(`session/${id}`, state);
    try {
      const admitted = await this.api.compact(id);
      state.pendingID = admitted.id;
    } catch (error) {
      state.pending = false;
      state.failed = true;
      await this.api.save(`session/${id}`, state);
      console.warn("[context-budget] Compaction admission failed; use /context-budget reset to rearm.", error);
    }
    return true;
  }

  /** @param {string} id @param {string} inboxID */
  cancelled(id, inboxID) {
    return this.run(id, async (state) => {
      if (state.pending && state.pendingID === inboxID) {
        state.pending = false;
        state.pendingID = "";
        state.failed = true;
      }
    });
  }

  /** @param {string} id @param {{model?: Model, advisory?: boolean}} [options] */
  observe(id, options = {}) {
    return this.run(id, async (state) => {
      const current = await this.current(id, options.model);
      const input = this.sync(state, current);
      const route = current.policy;
      const settings = controls(state, route);
      if (!route.budget || input === undefined || state.pending) return;
      if (settings.hard && input >= settings.hardLimit) await this.enqueue(id, state);
      if (options.advisory && settings.soft && !state.notified && route.softLimit !== undefined &&
        input >= route.softLimit && !state.pending) {
        state.notified = true;
        return `${route.label} context advisory: latest completed request used ${input.toLocaleString("en-US")} input tokens, including cache, not output. ` +
          `This is a lagging signal, not the size of this request. Recommend compaction at the next safe milestone, unless the user asked otherwise. ` +
          `Preserve a handoff first; use context_compact when ready. The user alone controls /context-budget limits.`;
      }
    });
  }

  /** @param {string} id */
  voluntary(id) {
    return this.run(id, async (state) => {
      this.sync(state, await this.current(id));
      if (state.pending) return "Compaction already pending; no duplicate queued.";
      if (state.failed || state.attempted) return "Compaction already attempted for this high-input interval. Ask the user to /context-budget reset before retrying.";
      await this.enqueue(id, state);
      return state.failed ? "Compaction admission failed. Ask the user to /context-budget reset; do not retry automatically." :
        "Compaction queued for this session's next safe step boundary. It has not finished. Limits unchanged.";
    });
  }

  /** @param {string} id @param {string} text */
  command(id, text) {
    return this.run(id, async (state) => {
      const current = await this.current(id);
      const input = this.sync(state, current);
      const route = current.policy;
      const args = text.trim().split(/\s+/);
      const [name, value] = args;
      let acknowledgement = "Status";
      if (text.trim() === "reset") {
        // Keep any admitted control pending; reset must not create a second one.
        Object.assign(state, defaults(), {
          hard: route.hard, hardLimit: route.hardLimit,
          pending: state.pending, pendingID: state.pendingID, checkpoint: state.checkpoint, attempted: state.pending,
        });
        acknowledgement = "Defaults restored; failure latch cleared";
      } else if (args.length === 2 && (name === "soft" || name === "hard") && (value === "on" || value === "off")) {
        state[name] = value === "on";
        state.overrides[name] = state[name];
        if (name === "hard" && value === "on" && !state.pending) {
          state.failed = false;
          state.attempted = false;
        }
        acknowledgement = `${name} ${value}`;
      } else if (args.length === 2 && name === "hard" && /^\d+$/.test(value) && Number.isSafeInteger(Number(value)) && Number(value) > 0) {
        state.hardLimit = Number(value);
        state.overrides.hardLimit = state.hardLimit;
        if (!state.pending) { state.failed = false; state.attempted = false; }
        acknowledgement = `Hard limit set to ${state.hardLimit}`;
      } else if (text.trim() !== "" && text.trim() !== "status") {
        return "Usage: /context-budget status | hard <positive integer tokens> | soft on/off | hard on/off | reset. No settings changed.";
      }
      const settings = controls(state, route);
      return `${acknowledgement}. ${route.label}. Soft: ${settings.soft ? "on" : "off"} at ${route.softLimit ?? "n/a"}; ` +
        `hard: ${settings.hard ? "on" : "off"} at ${settings.hardLimit}${route.budget ? "" : " (inactive: no managed budget)"}. ` +
        `Latest complete request input: ${input ?? "unknown"} ` +
        `(includes cache; lagging, excludes output). Pending: ${state.pending}; retry blocked: ${state.failed || state.attempted}. ` +
        "Settings saved for this session only. Native automatic compaction is unchanged. Pending controls are not cancelled by off/reset.";
    });
  }
}

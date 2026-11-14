// @ts-check

export const SOFT_LIMIT = 240_000;
export const HARD_LIMIT = 500_000;

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
 * @property {boolean} soft
 * @property {boolean} hard
 * @property {number} hardLimit
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
 * @property {(id: string) => Promise<{id: string}>} compact
 * @property {(key: string) => Promise<unknown>} load
 * @property {(key: string, state: State) => Promise<void>} save
 */

/** @returns {State} */
export function defaults() {
  return {
    soft: true, hard: true, hardLimit: HARD_LIMIT,
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
  return state;
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

/** @param {readonly Message[]} messages */
export function observation(messages) {
  // Context can retain pre-checkpoint assistant messages beside the new summary.
  // Compare creation times, not array position, and never count the summary request.
  const checkpoint = messages.filter((m) => m.type === "compaction")
    .reduce((last, m) => !last || m.time.created >= last.time.created ? m : last,
      /** @type {Message | undefined} */ (undefined));
  const cutoff = messages.filter((m) => m.type === "model-switched" ||
    (m.type === "compaction" && m.status === "completed"))
    .reduce((time, m) => Math.max(time, m.time.created), -1);
  const assistant = messages.filter((m) => m.type === "assistant" &&
    m.time.completed !== undefined && !m.error && m.tokens)
    .reduce((last, m) => !last || m.time.created >= last.time.created ? m : last,
      /** @type {Message | undefined} */ (undefined));
  const input = assistant?.type === "assistant" && assistant.time.created > cutoff &&
    assistant.model.providerID === "openai" ? inputTokens(assistant.tokens) : undefined;
  return { checkpoint, input };
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

  /** @param {State} state @param {readonly Message[]} messages */
  sync(state, messages) {
    const current = observation(messages);
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
    // A completed compaction alone does not rearm automation. A fresh low-input
    // primary request must prove it helped, avoiding repeated fixed-prompt compactions.
    if (!state.pending && !state.failed && current.input !== undefined && current.input < state.hardLimit) {
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

  /** @param {string} id @param {{provider?: string, advisory?: boolean}} [options] */
  observe(id, options = {}) {
    return this.run(id, async (state) => {
      const input = this.sync(state, await this.api.context(id));
      if (options.provider !== undefined && options.provider !== "openai") return;
      if (input === undefined || state.pending) return;
      if (state.hard && input >= state.hardLimit) await this.enqueue(id, state);
      if (options.advisory && state.soft && !state.notified && input >= SOFT_LIMIT && !state.pending) {
        state.notified = true;
        return `OpenAI context advisory: latest completed request used ${input.toLocaleString("en-US")} input tokens, including cache, not output. ` +
          `This is a lagging signal, not the size of this request. Recommend compaction at the next safe milestone, unless the user asked otherwise. ` +
          `Preserve a handoff first; use context_compact when ready. The user alone controls /context-budget limits.`;
      }
    });
  }

  /** @param {string} id */
  voluntary(id) {
    return this.run(id, async (state) => {
      this.sync(state, await this.api.context(id));
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
      const input = this.sync(state, await this.api.context(id));
      const args = text.trim().split(/\s+/);
      const [name, value] = args;
      let acknowledgement = "Status";
      if (text.trim() === "reset") {
        // Keep any admitted control pending; reset must not create a second one.
        Object.assign(state, defaults(), {
          pending: state.pending, pendingID: state.pendingID, checkpoint: state.checkpoint, attempted: state.pending,
        });
        acknowledgement = "Defaults restored; failure latch cleared";
      } else if (args.length === 2 && (name === "soft" || name === "hard") && (value === "on" || value === "off")) {
        state[name] = value === "on";
        if (name === "hard" && value === "on" && !state.pending) {
          state.failed = false;
          state.attempted = false;
        }
        acknowledgement = `${name} ${value}`;
      } else if (args.length === 2 && name === "hard" && /^\d+$/.test(value) && Number.isSafeInteger(Number(value)) && Number(value) > 0) {
        state.hardLimit = Number(value);
        if (!state.pending) { state.failed = false; state.attempted = false; }
        acknowledgement = `Hard limit set to ${state.hardLimit}`;
      } else if (text.trim() !== "" && text.trim() !== "status") {
        return "Usage: /context-budget status | hard <positive integer tokens> | soft on/off | hard on/off | reset. No settings changed.";
      }
      return `${acknowledgement}. OpenAI only. Soft: ${state.soft ? "on" : "off"} at ${SOFT_LIMIT}; ` +
        `hard: ${state.hard ? "on" : "off"} at ${state.hardLimit}. Latest complete request input: ${input ?? "unknown"} ` +
        `(includes cache; lagging, excludes output). Pending: ${state.pending}; retry blocked: ${state.failed || state.attempted}. ` +
        "Settings saved for this session only. Native automatic compaction is unchanged. Pending controls are not cancelled by off/reset.";
    });
  }
}

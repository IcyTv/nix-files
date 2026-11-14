import assert from "node:assert/strict";
import test from "node:test";
import { Schema } from "effect";
import { SessionMessage } from "@opencode/schema/session-message";
import { TokenUsage } from "@opencode/schema/token-usage";
import plugin from "./index.js";
import { inputTokens } from "./budget.js";

const usage = { input: 20_000, output: 90_000, reasoning: 10_000, cache: { read: 210_000, write: 10_000 } };
const assistant = {
  type: "assistant", id: "msg_contract", agent: "build",
  model: { providerID: "openai", id: "gpt-6.1-sol" }, content: [],
  time: { created: 20, completed: 21 }, finish: "stop", tokens: usage,
};

test("accounting fixtures conform to real V2 encoded schemas, not a legacy SDK", () => {
  assert.ok(Schema.is(Schema.toEncoded(TokenUsage.Info))(usage));
  assert.ok(Schema.is(Schema.toEncoded(SessionMessage.Info))(assistant));
  for (const status of ["running", "completed", "failed"]) {
    const compaction = {
      type: "compaction", id: "msg_compaction", reason: "manual", time: { created: 30 }, status,
      ...(status === "failed" ? { error: { type: "unknown", message: "test failure" } } : { summary: "checkpoint" }),
    };
    assert.ok(Schema.is(Schema.toEncoded(SessionMessage.Info))(compaction), status);
  }
  assert.equal(inputTokens(usage), 240_000);
});

test("actual V2 plugin registers strict executor-only tool and no-wake command acknowledgement", async () => {
  const tools = [];
  const commands = [];
  const hooks = new Map();
  const storage = new Map();
  const compacted = [];
  const notices = [];
  const cleanup = await plugin.setup({
    location: { directory: "/project-a", project: { id: "project_a", directory: "/project-a", canonical: "/project-a" } },
    tool: { transform: async (edit) => edit({ add: (tool) => tools.push(tool) }) },
    command: { transform: async (edit) => edit({ add: (command) => commands.push(command) }) },
    storage: {
      get: async (key) => storage.get(key),
      set: async (key, value) => { storage.set(key, structuredClone(value)); },
    },
    session: {
      context: async () => [assistant],
      compact: async ({ sessionID }) => { compacted.push(sessionID); return { id: "msg_control" }; },
      synthetic: async (notice) => { notices.push(notice); },
      hook: async (name, hook) => { hooks.set(name, hook); },
      prompt: () => { throw new Error("Commands must not create an LLM turn"); },
      generate: () => { throw new Error("Commands must not generate an LLM turn"); },
    },
    event: { subscribe: async function* () {} },
  });
  assert.equal(plugin.id, "local.context-budget");
  assert.equal(commands[0].name, "context-budget");
  await commands[0].execute({ sessionID: "ses_a", prompt: { text: "hard off" }, delivery: "queue" });
  assert.equal(notices[0].resume, false);
  assert.equal(notices[0].delivery, "queue");
  assert.match(notices[0].description, /hard: off at 500000/);
  assert.equal(tools[0].name, "context_compact");
  assert.deepEqual(tools[0].input.properties, {});
  assert.equal(tools[0].input.additionalProperties, false);
  const before = structuredClone(storage.get("session/ses_a"));
  await tools[0].execute({ sessionID: "ses_victim", hardLimit: 1 }, { sessionID: "ses_a" });
  assert.deepEqual(compacted, ["ses_a"]);
  assert.equal(storage.get("session/ses_a").hard, before.hard);
  assert.equal(storage.get("session/ses_a").hardLimit, before.hardLimit);
  assert.equal(storage.has("session/ses_victim"), false);
  const event = {
    sessionID: "ses_b", model: { providerID: "google-agy", id: "gemini" },
    tools: { context_compact: {} }, system: [],
  };
  await hooks.get("context")(event);
  assert.equal("context_compact" in event.tools, false);
  assert.deepEqual(event.system, []);
  await cleanup?.();
});

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

// Delivery resolves only after the consumer finishes processing the event. No
// timers or scheduling guesses are needed to reproduce the stale-snapshot race.
function eventFeed() {
  const queue = [];
  let wake = () => {};
  return {
    emit(event) {
      const done = deferred();
      queue.push({ event, done });
      wake();
      return done.promise;
    },
    async *subscribe({ signal }) {
      const abort = () => wake();
      signal.addEventListener("abort", abort, { once: true });
      try {
        while (!signal.aborted) {
          if (!queue.length) await new Promise((resolve) => { wake = resolve; });
          if (signal.aborted) break;
          const next = queue.shift();
          if (!next) continue;
          yield next.event;
          next.done.resolve();
        }
      } finally {
        signal.removeEventListener("abort", abort);
      }
    },
  };
}

async function locationInstance(directory, shared, context = shared.context, workspaceID) {
  const feed = eventFeed();
  const commands = [];
  const cleanup = await plugin.setup({
    location: { directory, workspaceID, project: { id: "project_test", directory, canonical: directory } },
    tool: { transform: async (edit) => edit({ add() {} }) },
    command: { transform: async (edit) => edit({ add: (command) => commands.push(command) }) },
    storage: {
      get: async (key) => structuredClone(shared.storage.get(key)),
      set: async (key, value) => { shared.writes.push(directory); shared.storage.set(key, structuredClone(value)); },
    },
    session: {
      get: async ({ sessionID }) => ({ location: { directory: shared.owners.get(sessionID) } }),
      context,
      compact: async ({ sessionID }) => { shared.compacted.push({ directory, sessionID }); return { id: "msg_control" }; },
      synthetic: async () => {},
      hook: async () => {},
    },
    event: feed,
  });
  return {
    emit: feed.emit,
    command: (sessionID, text) => commands[0].execute({ sessionID, prompt: { text }, delivery: "queue" }),
    cleanup,
  };
}

function globalEvent(type, location) {
  return {
    id: "evt_global", created: 22, type, location,
    durable: { aggregateID: "ses_owner", seq: 1, version: 1 },
    data: {
      sessionID: "ses_owner", assistantMessageID: "msg_contract", inboxID: "msg_control",
      finish: "stop", cost: 0, tokens: usage, reason: "manual", text: "checkpoint",
    },
  };
}

test("global foreign-location observer cannot restore hard on or compact after the owner's hard off", async () => {
  let high = false;
  const shared = {
    storage: new Map(), writes: [], compacted: [], owners: new Map([["ses_owner", "/project-a"]]),
    context: async () => [{ ...assistant, tokens: { ...usage, input: high ? 600_000 : 0, cache: { read: 0, write: 0 } } }],
  };
  const entered = deferred();
  const release = deferred();
  const owner = await locationInstance("/project-a", shared);
  const foreign = await locationInstance("/project-b", shared, async () => {
    entered.resolve();
    await release.promise;
    return shared.context();
  });
  try {
    // Missing event.location cannot prove the full directory/workspace owner.
    const delivery = foreign.emit(globalEvent("session.step.ended"));
    await Promise.race([entered.promise, delivery]);
    await owner.command("ses_owner", "hard off");
    release.resolve();
    await delivery;
    high = true;
    await foreign.emit(globalEvent("session.step.ended", { directory: "/project-a" }));
    assert.deepEqual({
      hard: shared.storage.get("session/ses_owner").hard,
      compacted: shared.compacted,
    }, { hard: false, compacted: [] });
  } finally {
    release.resolve();
    await owner.cleanup?.();
    await foreign.cleanup?.();
  }
});

test("every global subscription type rejects foreign, stale, and unowned workspace locations", async () => {
  let contexts = 0;
  const shared = {
    storage: new Map(), writes: [], compacted: [], owners: new Map([["ses_owner", "/project-a"]]),
    context: async () => { contexts++; return [{ ...assistant, tokens: { ...usage, input: 600_000 } }]; },
  };
  const foreign = await locationInstance("/project-b", shared);
  const workspace = await locationInstance("/project-a", shared, shared.context, "workspace_a");
  const sameDirectory = await locationInstance("/project-a", shared);
  try {
    for (const type of ["session.step.ended", "session.compaction.started", "session.compaction.ended", "session.compaction.failed", "session.inbox.cancelled"]) {
      await foreign.emit(globalEvent(type, { directory: "/project-a" }));
      await foreign.emit(globalEvent(type));
      // An event stamped with this old location must not act after a session move.
      await foreign.emit(globalEvent(type, { directory: "/project-b" }));
      await workspace.emit(globalEvent(type, { directory: "/project-a", workspaceID: "workspace_b" }));
      await workspace.emit(globalEvent(type));
      // PublicRef from session.get cannot tell the root instance that this event
      // belongs to a workspace at the same directory, so it must also reject it.
      await sameDirectory.emit(globalEvent(type));
      await sameDirectory.emit(globalEvent(type, { directory: "/project-a", workspaceID: "workspace_b" }));
    }
    assert.deepEqual({ contexts, writes: shared.writes, compacted: shared.compacted }, { contexts: 0, writes: [], compacted: [] });
  } finally {
    await foreign.cleanup?.();
    await workspace.cleanup?.();
    await sameDirectory.cleanup?.();
  }
});

test("owned full-location step events still enqueue compaction once", async () => {
  for (const workspaceID of [undefined, "workspace_a"]) {
    const shared = {
      storage: new Map(), writes: [], compacted: [], owners: new Map([["ses_owner", "/project-a"]]),
      context: async () => [{ ...assistant, tokens: { ...usage, input: 600_000 } }],
    };
    const owner = await locationInstance("/project-a", shared, shared.context, workspaceID);
    try {
      const event = globalEvent("session.step.ended", { directory: "/project-a", workspaceID });
      await owner.emit(event);
      await owner.emit(event);
      assert.deepEqual(shared.compacted, [{ directory: "/project-a", sessionID: "ses_owner" }]);
    } finally {
      await owner.cleanup?.();
    }
  }
});

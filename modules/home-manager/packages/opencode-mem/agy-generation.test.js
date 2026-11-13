import assert from "node:assert/strict";
import { test } from "node:test";
import { generateMemoryText } from "./agy-generation.js";

const input = {
  model: { providerID: "google-agy", id: "gemini-3.8-flash", variant: "low" },
  prompt: "Return a JSON summary of synthetic data.",
};

function fixture() {
  const calls = [];
  const ctx = {
    generate: {
      async text(value) {
        calls.push(["stateless", value]);
        return { text: "stateless" };
      },
    },
    session: {
      async create(value, options) {
        calls.push(["create", value, options]);
        return { id: "temporary-session" };
      },
      async generate(value, options) {
        calls.push(["generate", value, options]);
        return { text: '{"summary":"synthetic"}' };
      },
      async remove(value, options) {
        calls.push(["remove", value, options]);
      },
    },
  };
  return { ctx, calls };
}

test("AGY uses the selected model and variant in a tool-denied temporary session", async () => {
  const { ctx, calls } = fixture();
  assert.deepEqual(await generateMemoryText(ctx, input), { text: '{"summary":"synthetic"}' });
  assert.deepEqual(calls.map(([name]) => name), ["create", "generate", "remove"]);
  assert.deepEqual(calls[0][1].model, input.model);
  assert.deepEqual(calls[0][1].permissions, [{ action: "*", resource: "*", effect: "deny" }]);
  assert.deepEqual(calls[1][1], { sessionID: "temporary-session", prompt: input.prompt });
  assert.equal(calls[0][2].signal, calls[1][2].signal);
  assert.deepEqual(calls[2][1], { sessionID: "temporary-session" });
});

test("other providers keep the original sessionless request", async () => {
  const { ctx, calls } = fixture();
  const value = { ...input, model: { providerID: "openai", id: "some-model" } };
  assert.deepEqual(await generateMemoryText(ctx, value), { text: "stateless" });
  assert.deepEqual(calls, [["stateless", value]]);
});

test("an unspecified model keeps upstream default-model resolution", async () => {
  const { ctx, calls } = fixture();
  const value = { prompt: input.prompt };
  await generateMemoryText(ctx, value);
  assert.deepEqual(calls, [["stateless", value]]);
});

test("generation failure still removes the session and preserves the error", async () => {
  const { ctx, calls } = fixture();
  const failure = new Error("provider rejected request");
  ctx.session.generate = async () => { throw failure; };
  await assert.rejects(generateMemoryText(ctx, input), (error) => error === failure);
  assert.equal(calls.at(-1)[0], "remove");
});

test("session creation failure does not attempt to remove an unknown session", async () => {
  const { ctx, calls } = fixture();
  ctx.session.create = async () => { throw new Error("create failed"); };
  await assert.rejects(generateMemoryText(ctx, input), /create failed/);
  assert.deepEqual(calls, []);
});

test("timeout aborts generation but cleanup gets no aborted signal", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { ctx, calls } = fixture();
  ctx.session.generate = async (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener("abort", () => reject(signal.reason), { once: true });
  });
  const pending = generateMemoryText(ctx, input, 10000);
  await Promise.resolve();
  t.mock.timers.tick(10000);
  await assert.rejects(pending, /timed out after 10000ms/);
  assert.deepEqual(calls.at(-1).slice(0, 2), ["remove", { sessionID: "temporary-session" }]);
  assert.equal(calls.at(-1)[2].signal.aborted, false);
  assert.notEqual(calls.at(-1)[2].signal, calls[0][2].signal);
});

test("cleanup has its own deadline", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { ctx } = fixture();
  ctx.session.remove = async (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener("abort", () => reject(signal.reason), { once: true });
  });
  const pending = generateMemoryText(ctx, input);
  await new Promise(setImmediate);
  t.mock.timers.tick(10000);
  await assert.rejects(pending, /cleanup timed out after 10000ms/);
});

test("cleanup failure is not reported as successful generation", async () => {
  const { ctx } = fixture();
  ctx.session.remove = async () => { throw new Error("cleanup failed"); };
  await assert.rejects(generateMemoryText(ctx, input), /cleanup failed/);
});

test("generation and cleanup failures are both retained", async () => {
  const { ctx } = fixture();
  const failure = new Error("generation failed");
  const cleanupFailure = new Error("cleanup failed");
  ctx.session.generate = async () => { throw failure; };
  ctx.session.remove = async () => { throw cleanupFailure; };
  await assert.rejects(generateMemoryText(ctx, input), (error) => {
    assert.ok(error instanceof AggregateError);
    assert.deepEqual(error.errors, [failure, cleanupFailure]);
    return true;
  });
});

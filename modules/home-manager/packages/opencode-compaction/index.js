// @ts-check
import { Plugin } from "@opencode/plugin";
import { Budget } from "./budget.js";

export default Plugin.define({
  id: "local.context-budget",
  async setup(ctx) {
    const budget = new Budget({
      context: (sessionID) => ctx.session.context({ sessionID }),
      compact: (sessionID) => ctx.session.compact({ sessionID }),
      load: (key) => ctx.storage.get(key),
      save: (key, value) => ctx.storage.set(key, { ...value }),
    });

    await ctx.command.transform((editor) => {
      editor.add({
        name: "context-budget",
        description: "Session-only OpenAI context budget: status, hard <tokens>, soft/hard on/off, reset",
        async execute({ sessionID, prompt, delivery }) {
          const text = await budget.command(sessionID, prompt.text);
          // V2 commands return void, not display text. Queue an explicit no-wake
          // acknowledgement instead of secretly calling session.prompt/generate.
          await ctx.session.synthetic({ sessionID, text, description: text, delivery, resume: false });
        },
      });
    });

    await ctx.tool.transform((editor) => {
      editor.add({
        name: "context_compact",
        description: "Voluntarily queue compaction for your own session at the next safe step boundary. Preserve a handoff first. Does not change user limits; do not retry a pending or failed request.",
        input: { type: "object", properties: {}, additionalProperties: false },
        async execute(_input, context) {
          return { content: await budget.voluntary(context.sessionID) };
        },
      });
    });

    await ctx.session.hook("context", async (event) => {
      if (event.model.providerID !== "openai") delete event.tools.context_compact;
      try {
        const text = await budget.observe(event.sessionID, { provider: event.model.providerID, advisory: true });
        if (text) event.system.push({ type: "text", text });
      } catch (error) {
        // An optional budget plugin must not break otherwise valid model requests.
        console.warn("[context-budget] Could not inspect session usage.", error);
      }
    });

    const controller = new AbortController();
    const events = ctx.event.subscribe({
      types: ["session.step.ended", "session.compaction.started", "session.compaction.ended", "session.compaction.failed", "session.inbox.cancelled"],
      signal: controller.signal,
    });
    const loop = (async () => {
      for await (const event of events) {
        try {
          // V2 subscriptions can receive global events. The optional envelope
          // carries the full Location.Ref; session.get returns only PublicRef.
          const location = event.location;
          // PublicRef cannot distinguish a non-workspace session from a workspace
          // at the same directory. Never infer full ownership from directory alone.
          if (!location || location.directory !== ctx.location.directory ||
            location.workspaceID !== ctx.location.workspaceID) continue;
          const owner = await ctx.session.get({ sessionID: event.data.sessionID });
          if (owner.location.directory !== ctx.location.directory) continue;
          if (event.type === "session.inbox.cancelled") {
            await budget.cancelled(event.data.sessionID, event.data.inboxID);
          } else {
            await budget.observe(event.data.sessionID);
          }
        } catch (error) {
          console.warn("[context-budget] Could not inspect session usage.", error);
        }
      }
    })().catch((error) => {
      if (!controller.signal.aborted) console.warn("[context-budget] Event subscription stopped.", error);
    });
    return async () => { controller.abort(); await loop; };
  },
});

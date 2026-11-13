// OpenCode #62096: sessionless generation skips provider HTTP hooks.
// Keep this adapter limited to AGY until the host supports those hooks.
export async function generateMemoryText(ctx, input, timeoutMs = 90000) {
  if (input.model?.providerID !== "google-agy") {
    return ctx.generate.text(input);
  }

  const duration = Number(timeoutMs);
  const timeout = Number.isFinite(duration)
    ? Math.min(600000, Math.max(10000, duration))
    : 90000;
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort(new Error(`opencode-mem: AGY generation timed out after ${timeout}ms`));
  }, timeout);

  let session;
  let generationError;
  try {
    session = await ctx.session.create({
      title: "opencode-mem internal generation",
      model: input.model,
      permissions: [{ action: "*", resource: "*", effect: "deny" }],
    }, { signal: controller.signal });

    return await ctx.session.generate({
      sessionID: session.id,
      prompt: input.prompt,
    }, { signal: controller.signal });
  } catch (error) {
    generationError = error;
    throw error;
  } finally {
    clearTimeout(timer);
    if (session) {
      // Cleanup must not reuse an aborted generation signal.
      const cleanup = new AbortController();
      const cleanupTimer = setTimeout(() => {
        cleanup.abort(new Error("opencode-mem: AGY session cleanup timed out after 10000ms"));
      }, 10000);
      try {
        await ctx.session.remove({ sessionID: session.id }, { signal: cleanup.signal });
      } catch (cleanupError) {
        if (generationError) {
          throw new AggregateError([generationError, cleanupError],
            "opencode-mem: AGY generation and session cleanup failed");
        }
        throw cleanupError;
      } finally {
        clearTimeout(cleanupTimer);
      }
    }
  }
}

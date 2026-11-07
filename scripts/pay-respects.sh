# Read credentials at runtime, never during Nix evaluation or shell startup.
if [[ -r "$PAY_RESPECTS_KEY_FILE" ]]; then
  _PR_AI_API_KEY=$(<"$PAY_RESPECTS_KEY_FILE")
  if [[ -n "$_PR_AI_API_KEY" ]]; then
    export _PR_AI_API_KEY
    export _PR_AI_URL="https://api.openai.com/v1/chat/completions"
    export _PR_AI_MODEL="${_PR_AI_MODEL:-gpt-4o-mini}"
  else
    export _PR_AI_DISABLE=1
  fi
else
  # Shell integration is also generated at build time, without runtime secrets.
  export _PR_AI_DISABLE=1
fi

exec "$PAY_RESPECTS_BIN" "$@"

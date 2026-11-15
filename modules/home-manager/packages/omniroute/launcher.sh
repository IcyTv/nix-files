#!@shell@
set -eu
umask 077

: "${DATA_DIR:?Set DATA_DIR to a private persistent directory outside the Nix store}"
export OMNIROUTE_NIX_PACKAGE=1
export OMNIROUTE_NO_UPDATE_NOTIFIER=1
export NEXT_TELEMETRY_DISABLED=1
export PATH="@blockedNpm@:@coreutils@/bin:$PATH"

# Next changes cwd to its entrypoint directory and writes runtime cache files.
# Keep files in the store, but give this Nix output a private, writable directory
# tree. Preserve symlinks when Node resolves the main script and its imports.
app='@app@'
runtime="$DATA_DIR/runtime/$(basename "$app")"
mkdir -p "$DATA_DIR/runtime"
chmod 700 "$DATA_DIR"
if [ ! -d "$runtime" ]; then
  staging="$runtime.staging.$$"
  cp -rs --no-preserve=mode "$app/share/omniroute" "$staging"
  mv -T "$staging" "$runtime"
fi
export NODE_OPTIONS="${NODE_OPTIONS:-} --preserve-symlinks --preserve-symlinks-main"
cd "$runtime"
# Upstream bootstrap generates and persists server.env, then selects server-ws
# (trusted socket-peer stamping) rather than the bare Next server.
exec @node@ dev/run-standalone.mjs "$@"

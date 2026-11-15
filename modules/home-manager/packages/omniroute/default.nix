{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
  autoPatchelfHook,
  pkg-config,
  openssl,
  zlib,
  libsecret,
  glib,
  libx11,
  ncurses,
  musl,
  coreutils,
  python3,
  zstd,
}: let
  revision = "094a1aa1c0b2c54a4c4e3065948b3d4e9c1d0165";
  swcPython = python3.withPackages (p: [p.pyelftools]);
in
  buildNpmPackage {
    pname = "omniroute";
    version = "3.8.53";
    src = fetchFromGitHub {
      owner = "cheaper-inference";
      repo = "OmniRoute";
      rev = revision;
      hash = "sha256-6bKbLP9+VMlYo6TYxWsjtMLWv7A1qtOXAqY0uCowzg4=";
    };

    nodejs = nodejs_24;
    npmDepsHash = "sha256-/Z2Xm3us0Ag5cEb2O/vpcfAXNIKh6zGuCZ8CqdUsmA8=";
    npmFlags = ["--ignore-scripts" "--legacy-peer-deps"];
    npmInstallFlags = ["--include=optional" "--no-audit" "--no-fund"];
    dontNpmBuild = true;
    dontNpmInstall = true;
    patches = [./immutable.patch];

    nativeBuildInputs = [autoPatchelfHook pkg-config zstd];
    # xsel needs X11; bundled Codex terminals need libtinfo. Keep every bundled
    # artifact rather than hiding missing dependencies or deleting alternates.
    buildInputs = [stdenv.cc.cc.lib openssl zlib libsecret glib libx11 ncurses];
    # Repair native tools before Next loads SWC/esbuild. Relative sibling-library
    # RPATHs must survive copying the standalone tree out of the build directory.
    autoPatchelfFlags = ["--preserve-origin" "--relativize-rpath"];
    # Do not run autoPatchelf a second time over libvips (see below).
    dontAutoPatchelf = true;

    env = {
      NEXT_TELEMETRY_DISABLED = "1";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      OMNIROUTE_USE_TURBOPACK = "0";
      CIRCLE_NODE_TOTAL = "2";
      OMNIROUTE_BUILDING = "1";
      OMNIROUTE_BUILD_SHA = revision;
      OMNIROUTE_SW_BUILD_ID = revision;
      SOURCE_VERSION = revision;
    };

    buildPhase = ''
      runHook preBuild
      export DATA_DIR="$TMPDIR/omniroute-build-data"
      mkdir -p "$DATA_DIR"
      # SWC validates every cache ancestor, even in temporary mode. Nix's
      # user-namespace sandbox root has unmapped uid 65534, which it rejects.
      # Materialize the pinned raw addons with upstream's full SHA-512 check
      # before ELF repair. No runtime cache or disabled integrity checks.
      ${swcPython}/bin/python3 ${./unpack-swc.py} \
        node_modules/@swc/core-linux-x64-gnu/swc.linux-x64-gnu.node \
        node_modules/@next/swc-linux-x64-gnu/next-swc.linux-x64-gnu.node
      # Like opencode-mem: patchelf can corrupt libvips-cpp's DT_INIT. Restore
      # the untouched bundled library after repairing the remaining native files.
      vips=node_modules/@img/sharp-libvips-linux-x64/lib
      mkdir -p "$TMPDIR/vips-original"
      cp "$vips"/libvips-cpp.so.* "$TMPDIR/vips-original/"
      # npm also installs musl alternatives. Supply their actual libc without
      # adding musl headers to the glibc SQLite compilation environment.
      addAutoPatchelfSearchPath ${musl}/lib
      autoPatchelf node_modules
      cp "$TMPDIR/vips-original/"* "$vips/"
      # Invoke only the pinned SQLite compiler, never prebuild-install/npx.
      (cd node_modules/better-sqlite3; node "$npm_config_node_gyp" rebuild)
      node -e "require('better-sqlite3')(':memory:').close(); if (typeof require('wreq-js').createTransport !== 'function') process.exit(1)"
      node -e "require('@swc/core').transformSync('const value: number = 1', {jsc: {parser: {syntax: 'typescript'}}}); console.log('Verified SWC addon loaded')"
      # Full dashboard build. Avoid prepublish: it installs nested dependencies.
      # Explicit postbuild is needed because npm lifecycle scripts are disabled.
      node scripts/build/build-next-isolated.mjs
      node scripts/build/colocate-standalone.mjs
      test -f .build/next/standalone/server-ws.mjs
      test -f .build/next/standalone/dev/run-standalone.mjs
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/omniroute" "$out/bin" "$out/libexec/omniroute"
      cp -r .build/next/standalone/. "$out/share/omniroute/"
      # Bootstrap requires the complete JS wrapper before Next starts, even if
      # standalone tracing only captured the native addon (upstream Docker pattern).
      cp -rT node_modules/better-sqlite3 "$out/share/omniroute/node_modules/better-sqlite3"
      cat > "$out/libexec/omniroute/npm" <<'EOF'
      #!${stdenv.shell}
      echo 'Runtime npm/npx operations are disabled; use Nix.' >&2
      exit 1
      EOF
      chmod +x "$out/libexec/omniroute/npm"
      ln -s npm "$out/libexec/omniroute/npx"
      substitute ${./launcher.sh} "$out/bin/omniroute" \
        --subst-var-by shell ${stdenv.shell} \
        --subst-var-by coreutils ${coreutils} \
        --subst-var-by blockedNpm "$out/libexec/omniroute" \
        --subst-var-by app "$out" \
        --subst-var-by node ${nodejs_24}/bin/node
      chmod +x "$out/bin/omniroute"
      install -Dm644 ${./README.md} "$out/share/doc/omniroute/README.md"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      cd "$out/share/omniroute"
      node --check server-ws.mjs
      node --check dev/run-standalone.mjs
      node -e "require('better-sqlite3')(':memory:').close(); if (typeof require('wreq-js').createTransport !== 'function') process.exit(1); require('sharp')"
      runHook postInstallCheck
    '';

    meta = {
      description = "Pinned local OmniRoute inference gateway with dashboard and OAuth";
      homepage = "https://github.com/cheaper-inference/OmniRoute";
      license = lib.licenses.mit;
      mainProgram = "omniroute";
      platforms = ["x86_64-linux"];
    };
  }

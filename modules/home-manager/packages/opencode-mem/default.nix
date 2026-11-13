{
  lib,
  stdenv,
  buildNpmPackage,
  nodejs_24,
  autoPatchelfHook,
}:
buildNpmPackage {
  pname = "opencode-mem";
  version = "2.42.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./agy-generation.js
      ./agy-generation.test.js
      ./agy-generation.patch
    ];
  };

  nodejs = nodejs_24;
  npmDepsHash = "sha256-oytfgxuBjVD4YQVwyu22Do7ODbIWzxGcQ+8GoLwdZzY=";
  npmFlags = ["--ignore-scripts"];
  dontNpmBuild = true;
  dontNpmInstall = true;

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  buildPhase = ''
    runHook preBuild
    patch -d node_modules/opencode-mem -p1 < agy-generation.patch
    cp agy-generation.js node_modules/opencode-mem/dist/v2/
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test agy-generation.test.js
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/node_modules"
    cp -r node_modules/opencode-mem/. "$out/"
    for dependency in node_modules/*; do
      if [ "$dependency" != node_modules/opencode-mem ]; then
        cp -r "$dependency" "$out/node_modules/"
      fi
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cd "$out"
    node --input-type=module -e '
      await import("@tursodatabase/database");
      await import("onnxruntime-node");
      await import("./dist/v2/legacy-client.js");
      console.log("Memory adapter and native dependencies loaded");
    '
    runHook postInstallCheck
  '';

  meta = {
    description = "OpenCode memory with session-backed AGY background generation";
    homepage = "https://github.com/tickernelz/opencode-mem";
    license = lib.licenses.mit;
    platforms = ["x86_64-linux"];
  };
}

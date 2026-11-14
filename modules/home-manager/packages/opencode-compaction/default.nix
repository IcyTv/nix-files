{
  lib,
  stdenvNoCC,
  nodejs_24,
}:
stdenvNoCC.mkDerivation {
  pname = "opencode-compaction";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./package.json ./index.js ./budget.js ./budget.test.js ./README.md];
  };

  nativeBuildInputs = [nodejs_24];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --check index.js
    node --test budget.test.js
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp package.json index.js budget.js README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Session-scoped OpenAI context advisories and safe-boundary compaction for OpenCode V2";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}

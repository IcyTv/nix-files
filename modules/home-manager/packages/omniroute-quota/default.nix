{
  lib,
  stdenvNoCC,
  nodejs_24,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "omniroute-quota";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./index.js
      ./quota.js
      ./index.test.js
      ./quota.test.js
      ./README.md
    ];
  };

  nativeBuildInputs = [nodejs_24 makeWrapper];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --check index.js
    node --check quota.js
    node --check index.test.js
    node --check quota.test.js
    node --test *.test.js
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/omniroute-quota" "$out/bin"
    cp package.json index.js quota.js "$out/share/omniroute-quota/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/omniroute-quota" \
      --add-flags "$out/share/omniroute-quota/index.js"
    install -Dm644 README.md "$out/share/doc/omniroute-quota/README.md"
    runHook postInstall
  '';

  meta = {
    description = "Private loopback subscription quota adapter for OmniRoute";
    mainProgram = "omniroute-quota";
    platforms = lib.platforms.linux;
  };
}

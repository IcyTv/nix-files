{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  bun,
  autoPatchelfHook,
}: let
  pluginSource = fetchurl {
    url = "https://registry.npmjs.org/opencode-latex/-/opencode-latex-0.2.0.tgz";
    hash = "sha512-OVKCZWv4HCG8wyDgUn2gzJXDwEsIpahAvsAiH2ngLgCoCbgquBYznbmsPbS2k8Kp++0W4DJ7uuTiAAyWk3Pa2Q==";
  };
  mathSource = fetchurl {
    url = "https://registry.npmjs.org/opentui-math/-/opentui-math-0.1.0.tgz";
    hash = "sha512-SfGKOogZHXY1YGCSiV9+fFDveiGnm6zrb3ts0LVeb57V6Hzc1vz1xl806L1UVYqC/iKjaDWM8sSrWopduTXapw==";
  };
in
  buildNpmPackage {
    pname = "opencode-latex";
    version = "0.2.0";
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [./package.json ./package-lock.json];
    };

    npmDepsHash = "sha256-cYDP5xBKceN3Ssf7VeG4dGypzn1NUluVev/kFAo8NU0=";
    npmFlags = ["--ignore-scripts"];

    nativeBuildInputs = [bun autoPatchelfHook];
    buildInputs = [stdenv.cc.cc.lib];

    buildPhase = ''
      runHook preBuild

      mkdir -p plugin vendor/opentui-math
      tar -xzf ${pluginSource} --strip-components=1 -C plugin
      tar -xzf ${mathSource} --strip-components=1 -C vendor/opentui-math
      ln -s ../vendor/opentui-math node_modules/opentui-math

      # Use the host's Yoga export, not a second OpenTUI native runtime.
      substituteInPlace \
        plugin/src/opentui-math.ts \
        vendor/opentui-math/dist/chunk-q1mfcwy1.js \
        vendor/opentui-math/dist/chunk-nf3q6tfq.js \
        --replace-fail 'import { MeasureMode } from "@opentui/core/yoga"' \
          'import { Yoga } from "@opentui/core"; const { MeasureMode } = Yoga'

      # Bundle the renderer so its nested imports also use OpenCode's shared
      # runtime. Keep MathJax's dynamic assets and resvg's native addon on disk.
      bun build plugin/src/index.ts --target=bun \
        --external=@opencode/plugin --outfile=server.js
      bun build plugin/src/tui.ts --target=bun \
        --external=@opencode/plugin/tui --external=@opentui/core \
        --external=mathjax --external=@resvg/resvg-js --outfile=tui.js

      unlink node_modules/opentui-math
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp package.json server.js tui.js $out/
      cp -r node_modules $out/
      install -Dm644 plugin/LICENSE $out/share/licenses/opencode-latex/LICENSE
      install -Dm644 vendor/opentui-math/LICENSE $out/share/licenses/opentui-math/LICENSE
      runHook postInstall
    '';

    # Exercise MathJax, its bundled fonts, and the patched native resvg addon
    # without network access, rather than merely checking that imports succeed.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      cd $out
      bun --eval '
        const { default: MathJax } = await import("mathjax");
        const { Resvg } = await import("@resvg/resvg-js");
        const math = await MathJax.init({
          loader: { load: ["input/tex", "output/svg"] },
          svg: { fontCache: "local" },
        });
        const node = await math.tex2svgPromise(String.raw`\frac{-b \pm \sqrt{b^2-4ac}}{2a}`, { display: true });
        const svg = math.startup.adaptor.serializeXML(math.startup.adaptor.tags(node, "svg")[0]);
        const png = new Resvg(svg, { font: { loadSystemFonts: false } }).render().asPng();
        if (png.length < 100 || png[0] !== 137 || png[1] !== 80) throw new Error("MathJax PNG rendering failed");
        console.log(`MathJax rendered equation: ''${png.length} PNG bytes`);
      '
      runHook postInstallCheck
    '';

    meta = {
      description = "MathJax graphics plugin using OpenCode's shared OpenTUI runtime";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }

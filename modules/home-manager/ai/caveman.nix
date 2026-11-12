{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  inherit (inputs) caveman;

  cavemanPlugin = pkgs.runCommand "opencode-caveman-plugin" {} ''
    mkdir -p "$out"

    cp -r ${caveman}/src/plugins/opencode/. "$out/"
    cp ${caveman}/src/hooks/caveman-config.js \
      "$out/caveman-config.cjs"
  '';

  installMarkdownFiles = destination: source:
    lib.mapAttrs' (
      name: _:
        lib.nameValuePair
        "${destination}/${name}"
        {
          source = source + "/${name}";
        }
    ) (
      lib.filterAttrs (
        name: type:
          type == "regular" && lib.hasSuffix ".md" name
      ) (builtins.readDir source)
    );
in {
  config = lib.mkIf config.my.hm.ai.enable {
    home.file =
      {
        ".config/opencode/plugins/caveman".source = cavemanPlugin;

        ".config/caveman/config.json".text = builtins.toJSON {
          defaultMode = "caveman";
        };
      }
      // installMarkdownFiles
      ".config/opencode/commands"
      "${caveman}/src/plugins/opencode/commands"
      // installMarkdownFiles
      ".config/opencode/agents"
      "${caveman}/agents";

    programs.opencode.settings = {
      plugins = [
        "./plugins/caveman"
      ];

      instructions = [
        "${caveman}/src/rules/caveman-activate.md"
      ];
    };
  };
}

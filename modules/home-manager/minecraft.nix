{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.minecraft.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.minecraft.enable {
    home.packages = [
      pkgs.packwiz
    ];

    nixcraft = {
      enable = true;
      client = {
        shared = {
          enableExternalAssets = true;

          useDiscreteGPU = true;

          files."screenshots".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Pictures/Minecraft";

          account = {
            offline = false;
            uuid = "60c31ad8-cee7-4198-b475-cf4985c354de";
          };
        };

        instances.vanilla-plus = {
          desktopEntry = {
            enable = true;
            name = "Vanilla Plus";
          };

          mrpack = {
            enable = true;
            file = pkgs.stdenv.mkDerivation {
              pname = "Vanilla Plus";
              version = "0.0.1";
              src = ./Vanilla-Plus-0.0.1.mrpack;
              dontUnpack = true;
              installPhase = "cp $src $out";
            };
            fabricLoaderVersion = "0.19.5";
          };

          java.maxMemory = 160000;

          files = {
            "mods/fabric-api.jar".source = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/bNnaTiuM/fabric-api-0.161.0%2B26.3.jar";
              hash = "sha256-hvFheKPOzIh6haTP6aedkvpzQdjzm1lRpNatgAq2V6Y=";
            };
            "mods/mod-menu.jar".source = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/mOgUt4GM/versions/kyy7dbrZ/modmenu-21.0.0.jar";
              hash = "sha256-g3gSxsmNZhQdt7XcrmaPJ/t41Vfo9MDImRKYX8JqXm8=";
            };
            # "mods/sodium.jar".source = pkgs.fetchurl {
            #   url = "https://cdn.modrinth.com/data/AANobbMI/versions/bAZQdGpg/sodium-fabric-0.9.2%2Bmc26.3.jar";
            #   hash = lib.fakeHash;
            # };
          };
        };
      };
    };
  };
}

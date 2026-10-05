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

        instances = {
          vanilla-plus = {
            desktopEntry = {
              enable = true;
              name = "Vanilla Plus";
            };

            binEntry = {
              enable = true;
              name = "mc-vanilla-plus";
            };

            mrpack = {
              enable = true;
              file = pkgs.stdenv.mkDerivation {
                pname = "Vanilla Plus";
                version = "1.0.2";
                src = ./Vanilla-Plus-1.0.2.mrpack;
                dontUnpack = true;
                installPhase = "cp $src $out";
              };
            };

            java.maxMemory = 160000;
            java.extraArguments = ["-XX:+UseZGC"];
          };
          slimed = {
            desktopEntry = {
              enable = true;
              name = "Slimed";
            };

            binEntry = {
              enable = true;
              name = "mc-slimed";
            };

            mrpack = {
              enable = true;
              file = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/8yKzGJOG/versions/ylSYr50H/Slimes%20Adventure%20-%201.13.4.mrpack";
                sha256 = "sha256-tIsqKpXo2xpRSnYjYbWu9ZbHoTLnx23g6Z6hEcafikg=";
              };
            };

            java.maxMemory = 160000;
          };
        };
      };
    };
  };
}

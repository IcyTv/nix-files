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

          binEntry = {
            enable = true;
            name = "mc-vanilla-plus";
          };

          mrpack = {
            enable = true;
            file = pkgs.stdenv.mkDerivation {
              pname = "Vanilla Plus";
              version = "0.0.1";
              src = ./Vanilla-Plus-1.0.2.mrpack;
              dontUnpack = true;
              installPhase = "cp $src $out";
            };
          };

          java.maxMemory = 160000;
        };
      };
    };
  };
}

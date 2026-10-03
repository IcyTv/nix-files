{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.minecraft.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.minecraft.enable {
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
            name = "Unmodded Minecraft";
          };

          fabricLoader = {
            enable = true;
            version = "0.19.5";
          };

          java.maxMemory = 160000;
        };
      };
    };
  };
}

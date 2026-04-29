{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.games.enable = lib.mkEnableOption "Gaming support (Steam, Gamemode)";

  config = lib.mkIf config.my.nixos.games.enable {
    programs.steam.enable = true;
    programs.gamemode.enable = true;
    hardware.steam-hardware.enable = true;

    boot.kernelModules = ["uinput" "hid-playstation" "hid-sony"];
  };
}

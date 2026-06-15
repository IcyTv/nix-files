{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.games.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.games.enable {
    home.packages = [
      pkgs.steamtinkerlaunch
    ];

    programs.lutris = {
      enable = true;
      protonPackages = [
        pkgs.proton-ge-bin
      ];
      extraPackages = [
        pkgs.winetricks
        pkgs.gamemode
      ];
    };
  };
}

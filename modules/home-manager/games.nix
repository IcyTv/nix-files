{pkgs, ...}: {
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
}

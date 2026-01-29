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

  home.packages = [
    pkgs.python313Packages.ds4drv
  ];
}

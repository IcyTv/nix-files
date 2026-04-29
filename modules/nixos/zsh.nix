{ config, lib, pkgs, ... }: {
  options.my.nixos.zsh.enable = lib.mkEnableOption "Zsh shell";

  config = lib.mkIf config.my.nixos.zsh.enable {
    programs.zsh.enable = true;

    environment.pathsToLink = ["/share/zsh"];
    environment.shells = [pkgs.zsh pkgs.bash pkgs.nushell];
  };
}
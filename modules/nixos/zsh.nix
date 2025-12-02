{pkgs, ...}: {
  programs.zsh.enable = true;

  environment.pathsToLink = ["/share/zsh"];
  environment.shells = [pkgs.zsh pkgs.bash];
}

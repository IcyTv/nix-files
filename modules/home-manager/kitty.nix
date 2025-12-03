{
  lib,
  pkgs,
  ...
}: {
  programs.kitty = {
    enable = true;
    settings = {
      force_ltr = "no";
      scrollback_lines = 1000000;
      scrollback_pager = "bat --color=always";
      scrollback_pager_history_size = 0;
      shell = "zsh";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}

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
      shell = "nu";
      confirm_os_window_close = 0;
      allow_remote_control = "socket";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}

{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.ghostty.enable = lib.mkEnableOption "Ghostty terminal";

  config = lib.mkIf config.my.hm.ghostty.enable {
    programs.ghostty = {
      enable = true;
      systemd.enable = true;
      # settings = {
      #   force_ltr = "no";
      #   scrollback_lines = 1000000;
      #   scrollback_pager = "bat --color=always";
      #   scrollback_pager_history_size = 0;
      #   shell = "nu";
      #   confirm_os_window_close = 0;
      #   allow_remote_control = "socket";
      #   listen_on = ''unix:$XDG_RUNTIME_DIR/kitty-socket-{kitty_pid}'';
      # };
      settings = {
        scrollback-limit = 1000000;
      };
      enableBashIntegration = true;
      enableZshIntegration = true;
      installBatSyntax = true;
    };
  };
}

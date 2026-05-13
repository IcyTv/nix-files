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
        confirm-close-surface = false;
        clipboard-read = "allow";

        # --- Entry Point ---
        # "keybind" = [
        #   # Entry Point
        #   "ctrl+space=activate_key_table:vim"
        #
        #   # Navigation
        #   "vim/j=scroll_page_lines:1"
        #   "vim/k=scroll_page_lines:-1"
        #   "vim/ctrl+d=scroll_page_down"
        #   "vim/ctrl+u=scroll_page_up"
        #   "vim/shift+j=scroll_page_down"
        #   "vim/shift+k=scroll_page_up"
        #
        #   # Jumps
        #   "vim/g>g=scroll_to_top"
        #   "vim/shift+g=scroll_to_bottom"
        #
        #   # Search
        #   "vim/slash=start_search"
        #   "vim/n=navigate_search:next"
        #   "vim/shift+n=navigate_search:prev"
        #
        #   # Clipboard & Splits
        #   "vim/y=copy_to_clipboard"
        #   "vim/ctrl+h=goto_split:left"
        #   "vim/ctrl+j=goto_split:bottom"
        #   "vim/ctrl+k=goto_split:top"
        #   "vim/ctrl+l=goto_split:right"
        #
        #   # Exit Mode
        #   "vim/escape=deactivate_key_table"
        #   "vim/i=deactivate_key_table"
        #   "vim/a=deactivate_key_table"
        #
        #   # Safety
        #   "vim/catch_all=ignore"
        # ];
      };
      enableBashIntegration = true;
      enableZshIntegration = true;
      installBatSyntax = true;
    };
  };
}

{ lib, pkgs, ... }:
{
  # This is how you set the option, after the module is imported
  catppuccin.kitty = {
    enable = true;
    flavor = "mocha";
  };

  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
      package = pkgs.nerd-fonts.jetbrains-mono;
    };
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

{
  pkgs,
  lib,
  config,
  ...
}: {
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    plugins.lualine.enable = true;

    plugins.treesitter.enable = true;
    plugins.lz-n.enable = true;
  };
}

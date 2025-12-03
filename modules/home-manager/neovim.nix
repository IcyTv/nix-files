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
    plugins.which-key.enable = true;
    plugins.noice.enable = true;
    plugins.mini.enable = true;

    plugins.lsp = {
      enable = true;
      servers = {
        nixd = {
          enable = true;
          settings = {
            formatting.command = ["alejandra"];
            nixpkgs.expr = "import <nixpkgs> { }";
          };
        };
      };
    };

    plugins.conform-nvim = {
      enable = true;
      settings = {
        format_on_save = {
          lsp_fallback = true;
          timeout_ms = 500;
        };
        formatters_by_fmt = {
          nix = ["alejandra"];
        };
      };
    };

    plugins.direnv.enable = true;

    extraPackages = [
      pkgs.alejandra
      pkgs.nixfmt-rfc-style
    ];
  };
}

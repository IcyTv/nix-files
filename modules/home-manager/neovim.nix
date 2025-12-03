{
  pkgs,
  lib,
  config,
  ...
}: let
  nKey = key: action: desc: {
    mode = "n";
    key = key;
    action = action;
    options.desc = desc;
  };
in {
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;

    globals.mapleader = " ";
    opts = {
      number = true;
      relativenumber = true;
      tabstop = 4;
      wrap = false;
      termguicolors = true;
    };

    plugins.lualine.enable = true;
    plugins.bufferline.enable = true;
    plugins.treesitter = {
      enable = true;
      settings.highlight.enable = true;
    };
    plugins.lz-n.enable = true;
    plugins.which-key.enable = true;
    plugins.noice.enable = true;
    plugins.dashboard.enable = true;
    plugins.web-devicons.enable = true;
    plugins.mini.enable = true;
    plugins.guess-indent.enable = true;

    plugins.neo-tree.enable = true;
    plugins.telescope.enable = true;
    plugins.flash.enable = true;
    plugins.gitsigns.enable = true;
    plugins.luasnip.enable = true;

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

    plugins.cmp = {
      enable = true;
      autoEnableSources = true;
      settings.sources = [
        {name = "nvim_lsp";}
        {name = "async_path";}
        {name = "luasnip";}
        {name = "buffer";}
      ];
    };

    plugins.direnv.enable = true;

    extraPackages = [
      pkgs.alejandra
      pkgs.nixfmt-rfc-style
    ];

    keymaps = [
      (nKey "<C-h>" "<cmd>wincmd h" "Go window left")
      (nKey "<C-l>" "<cmd>wincmd l" "Go window left")
      (nKey "<C-j>" "<cmd>wincmd j" "Go window left")
      (nKey "<C-k>" "<cmd>wincmd k" "Go window left")
      (nKey "<C-Up>" "<cmd>resize +5" "Increase window height")
      (nKey "<C-Down>" "<cmd>resize -5" "Decrease window height")
      (nKey "<C-Left>" "<cmd>vertical resize -5" "Decrease window width")
      (nKey "<C-Right>" "<cmd>vertical resize +5" "Decrease window width")
      (nKey "[b" "<cmd>next" "Go to next Buffer")
      (nKey "]b" "<cmd>previous" "Go to previous Buffer")
      (nKey "<leader>bb" "<cmd>Telescope buffers" "Switch to other Buffer")
      (nKey "<leader>bd" "<cmd>bdelete" "Delete Buffer")
      (nKey "<leader>e" "<cmd>Neotree toggle<CR>" "Toggle Explorer")
      (nKey "<leader>ff" "<cmd>Telescope find_files<CR>" "Find Files")
      (nKey "<leader>fg" "<cmd>Telescope live_grep<CR>" "Live Grep")
    ];
  };
}

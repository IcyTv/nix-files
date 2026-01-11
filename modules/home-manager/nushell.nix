{pkgs, ...}: {
  programs.nushell = {
    enable = true;
    plugins = with pkgs.nushellPlugins; [
      skim
      query
      gstat
      highlight
    ];
    settings = {
      show_banner = false;
      completions = {
        case_sensitive = false;
        quick = true;
        partial = true;
        algorithm = "fuzzy";
        external = {
          enable = true;
          max_results = 100;
        };
      };
    };

    shellAliases = {
      nix-shell = "nix-shell --command nu";
    };
  };

  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };
}

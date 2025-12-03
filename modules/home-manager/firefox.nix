{pkgs, ...}: {
  programs.firefox = {
    enable = true;
    profiles = {
      default = {
        id = 0;
        name = "default";
        isDefault = true;
        search = {
          order = ["Google"];
          engines = {
            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAlias = ["nix" "nixpkgs"];
            };
            "NixOS Wiki" = {
              urls = [{template = "https://nixos.wiki/index.php?search={searchTerms}";}];
              iconUpdateURL = "https://nixos.wiki/favicon.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["nixos" "nixwiki"];
            };
            "Rust Crates" = {
              urls = [{template = "https://crates.io/search?q={searchTerms}";}];
              iconUpdateURL = "https://crates.io/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["crates"];
            };
            "Rust Docs" = {
              urls = [{template = "https://docs.rs/releases/search?query={searchTerms}";}];
              iconUpdateURL = "https://docs.rs/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["docs"];
            };
            "Bing".metaData.hidden = true;
            "Google".metaData.alias = "@g";
          };
        };
      };
    };
  };
}

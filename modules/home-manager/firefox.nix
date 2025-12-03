{pkgs, ...}: let
  firefoxID = "{ec8030f7-c20a-464f-9b0e-13a3a9e97384}";
  makeSettings = packages:
    builtins.listToAttrs (map (pkg: {
        name = pkg.addonId;
        value = {
          installation_mode = "force_installed";
          install_url = "file://${pkg}/share/mozilla/extensions/${firefoxID}/${pkg.addonId}.xpi";
          private_browsing = true;
          default_area = "menupanel";
        };
      })
      packages);
in {
  stylix.targets.firefox.profileNames = ["default"];
  programs.firefox = {
    enable = true;

    policies = {
      ExtensionSettings = makeSettings (with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        privacy-possum
        adnauseam
      ]);

      "3rdparty".Extensions = {
        "uBlock0@raymondhill.net" = {
          adminSettings = {
            selectedFilterLists = [
              "user-filters"
              "ublock-filters"
              "ublock-badware"
              "ublock-privacy"
              "ublock-quick-fixes"
              "ublock-unbreak"
              "easylist"
              "easyprivacy"
              "urlhaus-1"
              "plowe-0"

              "ublock-annoyances"
              "adguard-annoyance"
              "fanboy-cookiemonster"
              "fanboy-annoyance"
            ];
          };
        };
      };
    };

    profiles = {
      default = {
        id = 0;
        name = "default";
        isDefault = true;
        search = {
          order = ["google"];
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
              icon = "https://nixos.wiki/favicon.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["nixos" "nixwiki"];
            };
            "Rust Crates" = {
              urls = [{template = "https://crates.io/search?q={searchTerms}";}];
              icon = "https://crates.io/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["crates"];
            };
            "Rust Docs" = {
              urls = [{template = "https://docs.rs/releases/search?query={searchTerms}";}];
              icon = "https://docs.rs/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = ["docs"];
            };
            bing.metaData.hidden = true;
            google.metaData.alias = "@g";
          };
        };
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          vimium
          bitwarden
          return-youtube-dislikes
          sponsorblock
          tabliss
          tab-stash
          auto-tab-discard
          istilldontcareaboutcookies
          behind-the-overlay-revival
        ];
      };

      yes = {
        id = 2;
        name = "Yes";
        isDefault = false;
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          privacy-possum
          istilldontcareaboutcookies
          behind-the-overlay-revival
        ];
      };
    };
  };
}

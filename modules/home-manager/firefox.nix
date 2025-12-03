{pkgs, ...}: let
  firefoxID = "{ec8030f7-c20a-464f-9b0e-13a3a9e97384}";
  makeSettings = packages:
    builtins.listToAttrs (map (pkg: {
        name = pkg.addonId;
        value = {
          installation_mode = "force_installed";
          install_url = "file://${pkg}/share/mozilla/extensions/${firefoxID}/${pkg.addonId}.xpi";
          private_browsing = true;
          default_area = "navbar";
        };
      })
      packages);
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-true = {
    Value = true;
    Status = "locked";
  };
in {
  stylix.targets.firefox.profileNames = ["default"];
  programs.firefox = {
    enable = true;
    languagePacks = ["en-US"];

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      DisablePocket = true;
      DisableFirefoxAccounts = true;
      DisableFirefoxScreenshots = true;
      DisableProfileImport = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      DisplayBookmarksToolbar = "always";
      DisplayMenuBar = "default-off";
      SearchBar = "unified";
      GenerativeAI = {
        Enabled = false;
      };

      Preferences = {
        "browser.contentblocking.category" = {
          Value = "strict";
          Status = "locked";
        };
        "extensions.pocket.enabled" = lock-false;
        "extensions.screenshots.disabled" = lock-true;
        "extensions.autoDisableScopes" = 0;
        "browser.topsites.contile.enabled" = lock-false;
        "browser.formfill.enable" = lock-false;
        "browser.search.suggest.enabled" = {Value = "true";};
        "browser.search.suggest.enabled.private" = {Value = "true";};
        "browser.urlbar.suggest.searches" = {Value = "true";};
        "browser.urlbar.showSearchSuggestionsFirst" = lock-false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = lock-false;
        "browser.newtabpage.activity-stream.feeds.snippets" = lock-false;
        "browser.newtabpage.activity-stream.section.highlights.includePocket" = lock-false;
        "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = {Value = "true";};
        "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = lock-false;
        "browser.newtabpage.activity-stream.section.highlights.includeVisited" = {Value = "true";};
        "browser.newtabpage.activity-stream.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;
      };

      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        UrlbarInterventions = false;
        SkipOnboarding = true;
        MoreFromMozilla = false;
        FirefoxLabs = false;
        Locked = true;
      };

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
        extensions = {
          force = true;
          packages = with pkgs.nur.repos.rycee.firefox-addons; [
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
      };

      yes = {
        id = 2;
        name = "Yes";
        isDefault = false;
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          istilldontcareaboutcookies
          behind-the-overlay-revival
        ];
      };
    };
  };
}

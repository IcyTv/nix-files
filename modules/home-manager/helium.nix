{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  heliumDataDir = "${config.xdg.configHome}/net.imput.helium";
  heliumPkg = inputs.helium-flake.packages.${pkgs.stdenv.hostPlatform.system}.default;

  defaultExtensions = {
    video-speed-controller = "nffaoalbilbmmfgbnbgppjihopabppdk";
    behind-the-overlay = "ljipkdpcjbmhkdjjmbbaggebcednbbme";
  };

  globalPolicies = {
    "MetricsReportingEnabled" = false;
    "PasswordManagerEnabled" = false;
    "AutofillAddressEnabled" = false;
    "AutofillCreditCardEnabled" = false;
    "BookmarksBarEnabled" = true;
  };

  profiles = {
    "Default" = {
      displayName = null;
      bookmarksFile =
        if config.icy.personalSecrets
        then builtins.fromJSON (builtins.readFile ../../secrets/bookmarks-default.json)
        else [];
      extensions =
        defaultExtensions
        // {
          bitwarden = "nngceckbapebfimnlniiiahkandclblb";
          vimium = "dbepggeogbaibhgnhhndojpepiihcmeb";
          sponsor-block-for-youtube = "mnjggcdmjocbbbhaepdhchncahnbgone";
          unhook-remove-youtube-rec = "khncfooichmfjbepaaaebmommgaepoid";
          youtube-dislike-counter = "ggmlbjnojmdpejjekdlfkplepdigcond";
        };
    };

    "Yes" = {
      displayName = "Yes";
      bookmarksFile =
        if config.icy.personalSecrets
        then builtins.fromJSON (builtins.readFile ../../secrets/bookmarks-yes.json)
        else [];
      extensions = defaultExtensions // {};
    };
  };

  mkChromiumBookmarks = raw: let
    convertNode = prefix: idx: item: let
      id = "${prefix}${toString idx}";
    in
      if item ? bookmarks
      then {
        inherit id;
        inherit (item) name;
        type = "folder";
        date_added = "13350000000000000";
        date_modified = "13350000000000000";
        children = lib.imap1 (i: child: convertNode "${id}_" i child) item.bookmarks;
      }
      else {
        inherit id;
        inherit (item) name url;
        type = "url";
        date_added = "13350000000000000";
      };
    toolbarEntry = lib.findFirst (x: x.toolbar or false) {bookmarks = [];} raw;
    otherEntries = builtins.filter (x: !(x.toolbar or false)) raw;
  in
    builtins.toJSON {
      version = 1;
      roots = {
        bookmark_bar = {
          id = "1";
          name = "Bookmarks bar";
          type = "folder";
          date_added = "13350000000000000";
          date_modified = "13350000000000000";
          children = lib.imap1 (i: item: convertNode "10" i item) toolbarEntry.bookmarks;
        };
        other = {
          id = "2";
          name = "Other bookmarks";
          type = "folder";
          date_added = "13350000000000000";
          date_modified = "13350000000000000";
          children = lib.imap1 (i: item: convertNode "20" i item) otherEntries;
        };
        synced = {
          id = "3";
          name = "Mobile bookmarks";
          type = "folder";
          date_added = "13350000000000000";
          date_modified = "13350000000000000";
          children = [];
        };
      };
    };

  # Fixed: mapAttrs' (with prime) + fixed typo "net.imput.helium"
  perProfileExtensionFiles = lib.foldl' (
    acc: dirName: let
      exts = profiles.${dirName}.extensions;
      files =
        lib.mapAttrs' (
          _name: id:
            lib.nameValuePair "net.imput.helium/${dirName}/External Extensions/${id}.json" {
              text = builtins.toJSON {
                external_update_url = "https://clients2.google.com/service/update2/crx";
              };
            }
        )
        exts;
    in
      acc // files
  ) {} (builtins.attrNames profiles);

  profileDesktopEntries =
    lib.mapAttrsToList (
      dirName: cfg:
        pkgs.makeDesktopItem {
          name = "helium-${lib.toLower dirName}";
          desktopName =
            if cfg.displayName != null
            then "Helium (${cfg.displayName})"
            else "Helium";
          exec = "${heliumPkg}/bin/helium --profile-directory=${lib.escapeShellArg dirName} %U";
          icon = "helium";
          categories = ["Network" "WebBrowser"];
          mimeTypes = ["text/html" "x-scheme-handler/http" "x-scheme-handler/https"];
        }
    )
    profiles;

  generatedBookmarkFiles =
    lib.mapAttrs (
      dirName: cfg:
        pkgs.writeText "helium-bookmarks-${lib.toLower dirName}.json"
        (mkChromiumBookmarks cfg.bookmarksFile)
    )
    profiles;

  profileCachePatch = builtins.toJSON (lib.mapAttrs (dirName: cfg: {
      name =
        if cfg.displayName != null
        then cfg.displayName
        else dirName;
      is_using_default_name = cfg.displayName == null;
    })
    profiles);

  syncHeliumScript = pkgs.writeShellScript "sync-helium-profiles" ''
    set -euo pipefail
    LOCAL_STATE="${heliumDataDir}/Local State"
    LOCK_FILE="${heliumDataDir}/SingletonLock"
    mkdir -p "${heliumDataDir}"

    # Chromium creates a SingletonLock symlink while running.
    # Recheck every two seconds until the lock and this user's Helium processes are gone.
    while [ -e "$LOCK_FILE" ] || [ -L "$LOCK_FILE" ] || ${pkgs.procps}/bin/pgrep -u "$(id -u)" -x helium >/dev/null 2>&1; do
      sleep 2
    done

    if [ ! -f "$LOCAL_STATE" ]; then
      echo '{}' > "$LOCAL_STATE"
    fi

    TMP_FILE=$(mktemp)
    ${pkgs.jq}/bin/jq --argjson patch '${profileCachePatch}' '
      .profile.info_cache = ((.profile.info_cache // {}) * $patch)
    ' "$LOCAL_STATE" > "$TMP_FILE" && mv "$TMP_FILE" "$LOCAL_STATE"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (dirName: bmStorePath: ''
        mkdir -p "${heliumDataDir}/${dirName}"
        cp -f "${bmStorePath}" "${heliumDataDir}/${dirName}/Bookmarks"
        chmod 600 "${heliumDataDir}/${dirName}/Bookmarks"
      '')
      generatedBookmarkFiles)}
  '';
in {
  imports = [inputs.helium-flake.homeModules.default];

  options.my.hm.helium.enable = lib.mkEnableOption "Helium configuration";

  config = lib.mkIf config.my.hm.helium.enable {
    warnings = lib.optional config.my.hm.firefox.enable "Helium and Firefox are both enabled, which can cause conflicts when selecting a default browser";

    assertions = [
      {
        assertion = let
          displayNames = map (cfg: cfg.displayName) (lib.attrValues profiles);
        in
          lib.length displayNames == lib.length (lib.unique displayNames);
        message = "Duplicate profile display names found in Helium configuration";
      }
    ];

    home.packages =
      [
        heliumPkg
        pkgs.xdg-utils
      ]
      ++ profileDesktopEntries;

    xdg.configFile =
      {
        "net.imput.helium/policies/managed/helium.json".text = builtins.toJSON globalPolicies;
        "chromium/policies/managed/helium.json".text = builtins.toJSON globalPolicies;
      }
      // perProfileExtensionFiles;

    systemd.user.services.helium-profile-sync = {
      Unit = {
        Description = "Sync declarative Helium profiles and bookmarks";
      };
      Service = {
        # Complete startup once the worker is launched, even while it waits for Helium.
        Type = "exec";
        ExecStart = "${syncHeliumScript}";
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };

    home.activation.configureHeliumProfiles = lib.hm.dag.entryAfter ["reloadSystemd"] ''
      ${pkgs.systemd}/bin/systemctl --user restart --no-block helium-profile-sync.service
    '';
  };
}

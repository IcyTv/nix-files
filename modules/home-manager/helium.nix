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
    chrome-lock = "dfncaoemjmmnbcfldoochfgkhenhegjl";
    video-speed-controller = "nffaoalbilbmmfgbnbgppjihopabppdk";
    behind-the-overlay = "ljipkdpcjbmhkdjjmbbaggebcednbbme";
  };

  sharedSettings =
    lib.recursiveUpdate {
      browser = {
        custom_chrome_frame = false;
        show_home_button = false;
        theme.color_scheme2 = 2;
      };
      helium.browser = {
        centered_location_bar = false;
        layout = 0;
        minimal_location_bar = false;
        zen_mode = false;
        zen_mode_top_chrome_pinned = true;
      };
      intl = {
        accept_languages = "en-US,en,de";
        selected_languages = "en-US,en,de";
      };
      spellcheck = {
        dictionaries = ["en-US" "de"];
        dictionary = "";
      };
      translate_blocked_languages = ["en" "de"];
      session.restore_on_startup = 1;
      toolbar.pinned_actions = ["kActionShowChromeLabs" "kActionDevTools"];
      vertical_tabs = {
        collapsed_state = false;
        uncollapsed_width = 200;
      };
      webkit.webprefs = {
        default_fixed_font_size = 13;
        default_font_size = 16;
        fonts = {
          sansserif.Zyyy = "Sans";
          serif.Zyyy = "Serif";
          standard.Zyyy = "Sans";
        };
      };
      bookmark_bar.show_on_all_tabs = true;
    } (lib.optionalAttrs (config.stylix.enable or false) {
      browser.theme.color_scheme2 =
        if config.stylix.polarity == "dark"
        then 2
        else if config.stylix.polarity == "light"
        then 1
        else 0;
      webkit.webprefs.fonts = {
        sansserif.Zyyy = config.stylix.fonts.sansSerif.name;
        standard.Zyyy = config.stylix.fonts.sansSerif.name;
        serif.Zyyy = config.stylix.fonts.serif.name;
        fixed.Zyyy = config.stylix.fonts.monospace.name;
      };
    });

  profiles = {
    "Default" = {
      displayName = null;
      settings = {};
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
      settings = {};
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

  profileLaunchers =
    lib.mapAttrs (
      dirName: cfg: let
        extensionIds = lib.unique (lib.attrValues cfg.extensions);
      in
        pkgs.writeShellScript "helium-${lib.toLower dirName}" ''
          declared_ids=(${lib.escapeShellArgs extensionIds})
          registered_ids=()
          missing_urls=()
          preferences_files=(
            ${lib.escapeShellArg "${heliumDataDir}/${dirName}/Preferences"}
            ${lib.escapeShellArg "${heliumDataDir}/${dirName}/Secure Preferences"}
          )
          valid_preferences=true

          for preferences in "''${preferences_files[@]}"; do
            if [ ! -e "$preferences" ]; then
              continue
            fi

            if ! registrations=$(${pkgs.jq}/bin/jq -r -s --argjson declared ${lib.escapeShellArg (builtins.toJSON extensionIds)} '
              if length == 1 and (.[0] | type == "object") then .[0]
              else error("Preferences must contain exactly one JSON object") end
              | (if has("extensions") then .extensions else {} end)
              | if type == "object" then .
                else error("extensions must be an object") end
              | (if has("settings") then .settings else {} end)
              | if type == "object" then .
                else error("extensions.settings must be an object") end
              | keys[]
              | select(. as $id | $declared | index($id))
            ' "$preferences"); then
              printf 'Invalid Helium preferences; skipping extension prompts: %s\n' "$preferences" >&2
              valid_preferences=false
              break
            fi

            while IFS= read -r registered_id; do
              registered_ids+=("$registered_id")
            done <<< "$registrations"
          done

          if "$valid_preferences"; then
            chromium_version=""
            for id in "''${declared_ids[@]}"; do
              registered=false
              for registered_id in "''${registered_ids[@]}"; do
                if [[ "$id" == "$registered_id" ]]; then
                  registered=true
                  break
                fi
              done
              if ! "$registered"; then
                if [[ -z "$chromium_version" ]]; then
                  chromium_version_pattern='[(]Chromium ([0-9]+[.][0-9]+[.][0-9]+[.][0-9]+)[)]'
                  if version_output=$(${lib.escapeShellArg "${heliumPkg}/bin/helium"} --version) &&
                    [[ "$version_output" =~ $chromium_version_pattern ]]; then
                    chromium_version="''${BASH_REMATCH[1]}"
                  else
                    printf 'Could not determine Helium Chromium version; skipping extension prompts\n' >&2
                    break
                  fi
                fi
                missing_urls+=("https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&prodversion=$chromium_version&x=id%3D$id%26uc")
              fi
            done
          fi

          exec ${lib.escapeShellArg "${heliumPkg}/bin/helium"} \
            ${lib.escapeShellArg "--profile-directory=${dirName}"} \
            --extension-mime-request-handling=always-prompt-for-install \
            "$@" "''${missing_urls[@]}"
        ''
    )
    profiles;

  profileDesktopEntries =
    lib.mapAttrsToList (
      dirName: cfg:
        pkgs.makeDesktopItem {
          name = "helium-${lib.toLower dirName}";
          desktopName =
            if cfg.displayName != null
            then "Helium (${cfg.displayName})"
            else "Helium";
          exec = "${profileLaunchers.${dirName}} %U";
          icon = "helium";
          comment = "Access the Internet";
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

  generatedSettingsFiles =
    lib.mapAttrs (
      dirName: cfg:
        pkgs.writeText "helium-settings-${lib.toLower dirName}.json"
        (builtins.toJSON (lib.recursiveUpdate sharedSettings cfg.settings))
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

    merge_preferences() {
      local preferences="$1" patch="$2" input missing=false temporary
      input="$preferences"
      if [ ! -e "$preferences" ]; then
        input=/dev/null
        missing=true
      fi

      # Validate before creating a temporary file; never reset invalid preferences.
      if ! ${pkgs.jq}/bin/jq -e -s --argjson missing "$missing" '
        (length == 0 and $missing) or
        (length == 1 and (.[0] | type == "object"))
      ' "$input" >/dev/null; then
        echo "Refusing to merge invalid Helium Preferences: $preferences" >&2
        return 1
      fi

      temporary=$(mktemp "$preferences.tmp.XXXXXX") || return 1
      if ! chmod 600 "$temporary"; then
        echo "Could not secure Helium Preferences temporary file: $temporary" >&2
        return 1
      fi
      if ! ${pkgs.jq}/bin/jq -e -s --argjson missing "$missing" --slurpfile patch "$patch" '
        (if length == 0 and $missing then {}
         elif length == 1 and (.[0] | type == "object") then .[0]
         else error("Preferences must contain exactly one JSON object") end)
        * (if ($patch | length) == 1 and ($patch[0] | type == "object")
           then $patch[0]
           else error("Settings patch must contain exactly one JSON object") end)
      ' "$input" > "$temporary"; then
        echo "Helium Preferences merge failed; temporary file retained: $temporary" >&2
        return 1
      fi
      if ! mv -- "$temporary" "$preferences"; then
        echo "Helium Preferences replacement failed; temporary file retained: $temporary" >&2
        return 1
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (dirName: settingsStorePath: ''
        mkdir -p ${lib.escapeShellArg "${heliumDataDir}/${dirName}"}
        merge_preferences ${lib.escapeShellArg "${heliumDataDir}/${dirName}/Preferences"} ${lib.escapeShellArg (toString settingsStorePath)} || exit 1
      '')
      generatedSettingsFiles)}

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

  options.my.hm.helium.pkg = lib.mkOption {
    type = lib.types.package;
    default = heliumPkg;
    defaultText = lib.literalExpression "pkgs.helium";
    description = "The derivation to use for helium";
  };

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

    # Bitwarden desktop's own browser-integration setup now also tries to
    # rewrite this manifest itself on every startup (to repoint `path` at its
    # current nix-store desktop_proxy, which changes on every update) -- it
    # still doesn't auto-detect Helium's profile directory to create the file
    # from scratch, but it does try to overwrite one that's already there.
    # A plain home.file symlinks into the Nix store (read-only), so that
    # self-rewrite throws EROFS and aborts the app's whole native-messaging
    # setup for the run -- which greys out biometric unlock in every browser,
    # not just Helium (see app.log: "Error while setting up native
    # messaging"). `install` instead of a symlink keeps this a regular,
    # writable file that both home-manager and Bitwarden can update.
    home.activation.configureHeliumNativeMessaging = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run mkdir -p "${heliumDataDir}/NativeMessagingHosts"
      run install -m644 ${pkgs.writeText "com.8bit.bitwarden.json" (builtins.toJSON {
        name = "com.8bit.bitwarden";
        description = "Bitwarden desktop integration";
        path = "${pkgs.bitwarden-desktop}/libexec/desktop_proxy";
        type = "stdio";
        # Same Chrome Web Store id used in profiles.Default.extensions.bitwarden above.
        allowed_origins = ["chrome-extension://nngceckbapebfimnlniiiahkandclblb/"];
      })} "${heliumDataDir}/NativeMessagingHosts/com.8bit.bitwarden.json"
    '';

    systemd.user.services.helium-profile-sync = {
      Unit = {
        Description = "Sync declarative Helium profiles, settings and bookmarks";
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

{
  config,
  lib,
  pkgs,
  inputs,
  osConfig,
  ...
}: let
  m = builtins.fromJSON (builtins.readFile ./install.json);
in {
  imports =
    [
      ../../modules/home-manager/default.nix
      (builtins.fromJSON (builtins.readFile ./home-options.json))
    ]
    ++ lib.optional (!osConfig.stylix.enable) inputs.stylix.homeModules.stylix;
  icy = {
    inherit (m) personalSecrets;

    internal.core.enable = true;
    user.name = m.username;
    git = {
      name = m.gitName;
      email = m.gitEmail;
      signing = m.signing;
    };
  };
  home.stateVersion = lib.mkForce m.stateVersion;
  # Bridges the Bitwarden browser extension to fprintd/polkit for biometric
  # unlock. Enable "Settings -> Security -> Unlock with biometrics" and
  # "Allow browser integration" inside the app once, for Firefox; Helium's
  # native-messaging manifest is wired declaratively in helium.nix instead,
  # since its non-standard profile directory isn't one Bitwarden auto-detects.
  home.packages = [pkgs.bitwarden-desktop];
  programs.gpg.enable = true;
  # Repository access and the separately chosen signing policy remain usable
  # even when the optional personal Git/GitHub feature profile is disabled.
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings.user = {
      name = m.gitName;
      email = m.gitEmail;
    };
    signing = {
      format = "openpgp";
      signByDefault = m.signing;
    };
  };
  programs.pay-respects.enable = lib.mkIf (!m.personalSecrets) (lib.mkForce false);
  # Lid close triggers suspend-then-hibernate (see configuration.nix); lock
  # the screen first via the same gate-invalidating command the manual lock
  # keybind uses, so a lid-close lock behaves identically to a manual one.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = config.my.hm.niri.lockCommandDaemonized;
      lock = config.my.hm.niri.lockCommandDaemonized;
    };
  };
  services.gpg-agent = {
    enable = true;
    pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  };

  my.hm.helium.enable = true;

  my.hm.niri.defaultBrowser = "${config.my.hm.helium.pkg}/bin/helium --profile-directory=Default";

  # Same three external monitors as eagle (matched by resolution/refresh,
  # connector names differ per-GPU), plus the laptop panel, parked at the
  # bottom-middle of the external row for now.
  programs.niri.settings.outputs = {
    "DP-10" = {
      enable = true;
      mode = {
        width = 1920;
        height = 1080;
        refresh = 60.0;
      };
      position = {
        x = 0;
        y = 0;
      };
    };
    "DP-9" = {
      enable = true;
      focus-at-startup = true;
      mode = {
        width = 2560;
        height = 1440;
        refresh = 239.97;
      };
      position = {
        x = 1920;
        y = 0;
      };
    };
    "DP-8" = {
      enable = true;
      mode = {
        width = 1920;
        height = 1080;
        refresh = 60.0;
      };
      position = {
        x = 4480;
        y = 0;
      };
    };
    "eDP-1" = {
      enable = true;
      mode = {
        width = 1920;
        height = 1200;
        refresh = 60.001;
      };
      position = {
        x = 2432;
        y = 1440;
      };
    };
  };
}

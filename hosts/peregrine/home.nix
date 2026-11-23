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
    internal.core.enable = true;
    user.name = m.username;
    personalSecrets = m.personalSecrets;
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
}

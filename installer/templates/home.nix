{
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
      key = "433D8E22007D3A9762D54780ED06A3B7C8B9C6B0!";
      signByDefault = m.signing;
    };
  };
  programs.pay-respects.enable = lib.mkIf (!m.personalSecrets) (lib.mkForce false);
  services.gpg-agent = {
    enable = true;
    pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  };
}

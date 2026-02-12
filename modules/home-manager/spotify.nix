{
  pkgs,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in {
  programs.spicetify = {
    enable = true;
    spotifyPackage = pkgs.spotify;

    enabledExtensions = with spicePkgs.extensions; [
      shuffle
      bookmark
      trashbin
      hidePodcasts
    ];
    enabledCustomApps = with spicePkgs.apps; [
      marketplace
      newReleases
    ];
  };

  xdg.configFile."autostart/spotify.desktop".source = "${pkgs.spotify}/share/applications/spotify.desktop";
}

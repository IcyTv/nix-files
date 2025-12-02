{
  pkgs,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in {
  programs.spicetify = {
    enable = true;

    enabledExtensions = with spicePkgs.extensions; [
      shuffle
      bookmark
      trashbin
    ];

    theme = spicePkgs.themes.catppuccin;
    colorScheme = "mocha";
  };
}

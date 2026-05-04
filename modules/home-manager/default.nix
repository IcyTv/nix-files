{inputs, ...}: {
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    inputs.spicetify-nix.homeManagerModules.default
    inputs.agenix.homeManagerModules.default
    inputs.nixcord.homeModules.nixcord
    inputs.subniri.homeModules.subniri

    ./waybar.nix
    ./ai.nix
    ./anyrun.nix
    ./audio.nix
    ./bluetooth.nix
    ./core.nix
    ./discord.nix
    ./firefox.nix
    ./games.nix
    ./git.nix
    ./kitty.nix
    ./niri.nix
    ./nix.nix
    ./nushell.nix
    ./obs.nix
    ./spotify.nix
    ./ssh.nix
    ./starship.nix
    ./stylix.nix
    ./subniri.nix
    ./swww.nix
    ./tools.nix
    ./qt6.nix
    ./unifiedremote.nix
    ./yazi.nix
    ./zsh.nix
  ];
}

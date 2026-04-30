{inputs, ...}: {
  imports = [
    inputs.nix-index-database.homeModules.nix-index
    inputs.spicetify-nix.homeManagerModules.default
    inputs.agenix.homeManagerModules.default
    inputs.nixcord.homeModules.nixcord
    inputs.subniri.homeModules.subniri

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
    ./nushell.nix
    ./nix.nix
    ./obs.nix
    ./spotify.nix
    ./ssh.nix
    ./stylix.nix
    ./tools.nix
    ./swww.nix
    # ./waybar.nix
    ./subniri.nix
    ./unifiedremote.nix
    ./yazi.nix
    ./zsh.nix
  ];
}

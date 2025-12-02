{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: {
    # use "nixos", or your hostname as the name of the configuration
    # it's a better practice than "default" shown in the video
    nixosConfigurations.eagle = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = [
        (
          {pkgs, ...}: {
            nixpkgs.overlays = [inputs.niri.overlays.niri];
          }
        )
        inputs.niri.nixosModules.niri
        inputs.nix-index-database.nixosModules.nix-index
        ./hosts/eagle/configuration.nix
        inputs.home-manager.nixosModules.default
      ];
    };
  };
}

{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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

    hardware.url = "github:nixos/nixos-hardware";

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim = {
      url = "github:IcyTv/nvim.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixvim.follows = "nixvim";
    };

    stylix = {
      url = "github:nix-community/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nur,
    ...
  } @ inputs: let
    systems = nixpkgs.lib.systems.flakeExposed;
    forAllSystems = function:
      nixpkgs.lib.genAttrs systems (system:
        function (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [nur.overlays.default];
        }));
    sharedModules = [
        (
          {pkgs, ...}: {
            nixpkgs.overlays = [
              inputs.niri.overlays.niri
              inputs.nur.overlays.default
            ];
          }
        )
        inputs.stylix.nixosModules.stylix
        inputs.niri.nixosModules.niri
        inputs.nix-index-database.nixosModules.nix-index
        inputs.home-manager.nixosModules.default
        inputs.nur.modules.nixos.default
        inputs.agenix.nixosModules.default
      ];
  in {
    legacyPackages = forAllSystems (pkgs: pkgs);

    # use "nixos", or your hostname as the name of the configuration
    # it's a better practice than "default" shown in the video
    nixosConfigurations.eagle = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = sharedModules ++ [
        ./hosts/eagle/configuration.nix
      ];
    };
    nixosConfigurations.sparrow = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};
      modules = sharedModules ++ [
        ./hosts/sparrow/configuration.nix
      ];
    };
  };
}

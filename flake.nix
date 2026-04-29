{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nirinit = {
      url = "github:amaanq/nirinit";
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

    nix-filter.url = "github:numtide/nix-filter";

    nixcord.url = "github:FlameFlag/nixcord";

    subniri = {
      url = "github:IcyTv/subniri";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nur,
    nix-filter,
    subniri,
    disko,
    ...
  } @ inputs: let
    systems = nixpkgs.lib.systems.flakeExposed;
    forAllSystems = function:
      nixpkgs.lib.genAttrs systems (system:
        function (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [nur.overlays.default subniri.overlays.default];
        }));
    sharedModules = [
      (
        {pkgs, ...}: {
          nixpkgs.overlays = [
            inputs.niri.overlays.niri
            inputs.nur.overlays.default
            inputs.subniri.overlays.default
          ];
        }
      )
      inputs.stylix.nixosModules.stylix
      inputs.niri.nixosModules.niri
      inputs.nix-index-database.nixosModules.nix-index
      inputs.home-manager.nixosModules.default
      inputs.nur.modules.nixos.default
      inputs.agenix.nixosModules.default
      inputs.nirinit.nixosModules.default
      inputs.disko.nixosModules.disko
    ];
    filtered-src = nix-filter.lib {
      root = ./.;
      include = [
        ./flake.nix
        ./flake.lock
        ./rebuild.sh
        ./modules
        ./scripts
        ./secrets
        ./hosts
      ];
      exclude = [./wallpapers];
    };
  in {
    legacyPackages = forAllSystems (pkgs: pkgs);

    packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;

    nixosConfigurations = {
      eagle = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          self = filtered-src;
        };
        modules =
          sharedModules
          ++ [
            ./hosts/eagle/configuration.nix
          ];
      };
      sparrow = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          self = filtered-src;
        };
        modules =
          sharedModules
          ++ [
            ./hosts/sparrow/configuration.nix
          ];
      };
      iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          self = filtered-src;
        };

        modules = sharedModules ++ [./hosts/iso/configuration.nix];
      };
    };
  };
}

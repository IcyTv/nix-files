{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    llm-agents.url = "github:numtide/llm-agents.nix";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim = {
      url = "github:IcyTv/nvim.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixvim.follows = "nixvim";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
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

    agents-nix = {
      url = "github:sudosubin/agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caveman = {
      url = "github:JuliusBrussee/caveman/v4.1.0";
      flake = false;
    };

    nix-filter.url = "github:numtide/nix-filter";

    nixcord.url = "github:FlameFlag/nixcord";

    subniri = {
      url = "github:IcyTv/subniri";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cargo2nix.url = "github:AstroForge-Incorporated/cargo2nix/9ccc2c70a23a0905af3a6e218a83e337f1eaa3dd";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    solaar = {
      url = "github:Svenum/Solaar-Flake/0.1.7";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nur,
    nix-filter,
    subniri,
    agents-nix,
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
            inputs.nix-minecraft.overlay
            inputs.nur.overlays.default
            inputs.subniri.overlays.default
            agents-nix.overlays.default
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
      inputs.solaar.nixosModules.default
      inputs.subniri.nixosModules.subniri
    ];
    filtered-src = nix-filter.lib {
      root = ./.;
      include = [
        ./flake.nix
        ./flake.lock
        ./rebuild.sh
        ./modules
        ./scripts
        ./installer
        ./.gitattributes
        ./.gitignore
        ./secrets
        ./hosts
      ];
      exclude = ["wallpapers"];
    };
    hosts = builtins.attrNames (nixpkgs.lib.filterAttrs (name: type: type == "directory" && name != "iso") (builtins.readDir ./hosts));
  in {
    legacyPackages = forAllSystems (pkgs: pkgs);

    packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
    packages.x86_64-linux.installer = nixpkgs.legacyPackages.x86_64-linux.callPackage ./installer {
      source = nixpkgs.lib.cleanSourceWith {
        src = filtered-src;
        # Never bake unlocked git-crypt bookmark plaintext into the ISO snapshot.
        filter = path: _: !(builtins.elem (baseNameOf path) ["bookmarks-default.json" "bookmarks-yes.json"]);
      };
    };

    installerApi = 1;
    checks.x86_64-linux.installer = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
      pkgs.runCommand "installer-safety-tests" {nativeBuildInputs = [pkgs.python3 pkgs.psmisc];} ''
        export PYTHONDONTWRITEBYTECODE=1
        python3 -m unittest discover -s ${./installer}/tests -p 'test_*.py' -v
        touch "$out"
      '';
    installerStateVersion = nixpkgs.lib.versions.majorMinor nixpkgs.lib.version;
    installerSchema.x86_64-linux = let
      schemaSystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          self = filtered-src;
        };
        modules = sharedModules ++ [./modules/nixos/default.nix];
      };
      schemaHome = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = schemaSystem.pkgs;
        extraSpecialArgs = {inherit inputs;};
        modules =
          schemaSystem.config.home-manager.sharedModules
          ++ [
            inputs.stylix.homeModules.stylix
            ./modules/home-manager/default.nix
            {
              home.username = "schema";
              home.homeDirectory = "/home/schema";
              home.stateVersion = "25.11";
              my.hm.default.enable = true;
              icy.personalSecrets = false;
            }
          ];
      };
    in
      import ./installer/schema.nix {
        lib = nixpkgs.lib;
        systemOptions = schemaSystem.options.my;
        homeOptions = schemaHome.options.my;
        homeDefaults = schemaHome.config;
      };

    nixosConfigurations =
      (nixpkgs.lib.genAttrs hosts (host:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            self = filtered-src;
          };
          modules =
            sharedModules
            ++ [
              ./hosts/${host}/configuration.nix
            ];
        }))
      // {
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

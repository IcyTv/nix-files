{
  pkgs,
  config,
  lib,
  ...
}: let
  prismData = "${config.xdg.dataHome}/PrismLauncher";

  vanillaPlus = pkgs.fetchPackwizModpack {
    pname = "vanilla-plus-client";
    version = "1.0.2";
    src = ./vanilla-plus-modpack;
    side = "client";
    packHash = "sha256-u9nzh5QgbC6CBpHc7/Gxxf15FE62vAO098pBOxHXIdY=";
  };

  slimed = pkgs.fetchModrinthModpack {
    pname = "slimes-adventure-client";
    version = "1.13.4";
    url = "https://cdn.modrinth.com/data/8yKzGJOG/versions/ylSYr50H/Slimes%20Adventure%20-%201.13.4.mrpack";
    side = "client";
    packHash = "sha256-PiUwGOLJD6+ObgRNocaESUaADU6Pz1pT7zejJjnqmNQ=";
  };

  divineJourney = pkgs.fetchurl {
    url = "https://github.com/Divine-Journey-2/Divine-Journey-2/releases/download/2.23.4/Divine_Journey_2.23.4.zip";
    hash = "sha256-rrUvFFQT+b1GotEEVpb9duUYJ13S5OkX7Jzwk1UQviw=";
  };

  mkLauncher = name: instance:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.prismlauncher];
      text = ''
        exec prismlauncher --launch ${lib.escapeShellArg instance} "$@"
      '';
    };

  vanillaPlusLauncher = mkLauncher "mc-vanilla-plus" "vanilla-plus";
  slimedLauncher = mkLauncher "mc-slimed" "slimed";
  divineJourneyLauncher = pkgs.writeShellApplication {
    name = "mc-dj";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.prismlauncher
    ];
    text = ''
      instance_root=${lib.escapeShellArg prismData}/instances
      for cfg in "$instance_root"/*/instance.cfg; do
        if [[ -f "$cfg" ]] && grep -qi '^name=Divine Journey' "$cfg"; then
          instance="$(basename "$(dirname "$cfg")")"
          exec prismlauncher --launch "$instance" "$@"
        fi
      done

      exec prismlauncher --import ${divineJourney}
    '';
  };

  instanceConfig = name: extraJvmArgs:
    pkgs.writeText "${name}-instance.cfg" ''
      [General]
      AutomaticJava=true
      ConfigVersion=1.3
      InstanceType=OneSix
      JvmArgs=${extraJvmArgs}
      MaxMemAlloc=10240
      MinMemAlloc=1024
      OverrideJavaArgs=true
      OverrideMemory=true
      OverridePerformance=true
      UseDiscreteGpu=true
      name=${name}
    '';

  fabricPack = name: minecraft: loader:
    pkgs.writeText "${name}-mmc-pack.json" (builtins.toJSON {
      formatVersion = 1;
      components = [
        {
          uid = "net.minecraft";
          version = minecraft;
          important = true;
        }
        {
          uid = "net.fabricmc.fabric-loader";
          version = loader;
        }
      ];
    });
in {
  options.my.hm.minecraft.enable = lib.mkEnableOption "Minecraft clients";

  config = lib.mkIf config.my.hm.minecraft.enable {
    programs.prismlauncher.enable = true;

    home.packages = [
      pkgs.packwiz
      vanillaPlusLauncher
      slimedLauncher
      divineJourneyLauncher
    ];

    xdg.desktopEntries = {
      minecraft-vanilla-plus = {
        name = "Vanilla Plus";
        exec = "${vanillaPlusLauncher}/bin/mc-vanilla-plus";
        terminal = false;
        categories = ["Game"];
      };
      minecraft-slimed = {
        name = "Slimed";
        exec = "${slimedLauncher}/bin/mc-slimed";
        terminal = false;
        categories = ["Game"];
      };
      minecraft-divine-journey = {
        name = "Divine Journey 2";
        exec = "${divineJourneyLauncher}/bin/mc-dj";
        terminal = false;
        categories = ["Game"];
      };
    };

    home.activation.minecraftInstances = lib.hm.dag.entryAfter ["writeBoundary"] ''
      initialize_instance() {
        local id="$1"
        local pack="$2"
        local instance_config="$3"
        local version_config="$4"
        local old_instance="$HOME/.local/share/nixcraft/client/instances/$id"
        local instance="${prismData}/instances/$id"
        local minecraft="$instance/minecraft"

        if [[ -d "$old_instance" && ! -e "$minecraft" ]]; then
          run mkdir -p "$instance"
          run mv "$old_instance" "$minecraft"
        else
          run mkdir -p "$minecraft"
        fi

        if [[ -d "$minecraft/.nixcraft" && ! -e "$instance/nixcraft-metadata" ]]; then
          run mv "$minecraft/.nixcraft" "$instance/nixcraft-metadata"
        fi

        run install -m 0644 "$version_config" "$instance/mmc-pack.json"
        if [[ ! -e "$instance/instance.cfg" ]]; then
          run install -m 0644 "$instance_config" "$instance/instance.cfg"
        fi

        for directory in mods resourcepacks; do
          if [[ ! -d "$pack/$directory" ]]; then
            continue
          fi

          if [[ -e "$minecraft/$directory" && ! -L "$minecraft/$directory" && ! -e "$minecraft/$directory.nixcraft" ]]; then
            run mv "$minecraft/$directory" "$minecraft/$directory.nixcraft"
          fi
          run ln -sfn "$pack/$directory" "$minecraft/$directory"
        done

        for initial_path in config options.txt servers.dat; do
          if [[ -e "$pack/$initial_path" && ! -e "$minecraft/$initial_path" ]]; then
            run cp -a "$pack/$initial_path" "$minecraft/$initial_path"
            run chmod -R u+w "$minecraft/$initial_path"
          fi
        done

        run mkdir -p "$HOME/Pictures/Minecraft"
        run ln -sfn "$HOME/Pictures/Minecraft" "$minecraft/screenshots"
      }

      initialize_instance \
        vanilla-plus \
        ${vanillaPlus} \
        ${instanceConfig "Vanilla Plus" "-XX:+UseZGC"} \
        ${fabricPack "vanilla-plus" "26.2" "0.19.5"}

      initialize_instance \
        slimed \
        ${slimed} \
        ${instanceConfig "Slimed" ""} \
        ${fabricPack "slimed" "1.21.1" "0.19.5"}
    '';
  };
}

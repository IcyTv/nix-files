#!/usr/bin/env bash
set -e

export GUM_SPIN_SPINNER="dot"

clear
gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Welcome to the NixOS TUI Installer"

# 1. Ask for hostname
HOSTNAME=$(gum input --placeholder "Enter new hostname (e.g. falcon)..." --prompt "Hostname: ")
if [ -z "$HOSTNAME" ]; then
    echo "Hostname cannot be empty!"
    exit 1
fi

# 2. Ask for disk
echo "Available disks:"
lsblk -d -n -o NAME,SIZE,MODEL | awk '{print "/dev/"$1 " - " $2 " - " $3}'
DISK=$(gum input --placeholder "Enter disk path (e.g. /dev/nvme0n1)..." --prompt "Target Disk: ")
if [ -z "$DISK" ]; then
    echo "Disk cannot be empty!"
    exit 1
fi

# 3. Ask for system features
SYSTEM_FEATURES=$(gum choose --no-limit --header "Select SYSTEM features to enable:" \
    "ananicy" \
    "bluetooth" \
    "console-font" \
    "games" \
    "greetd" \
    "keymap" \
    "limine" \
    "niri" \
    "openrgb" \
    "plymouth" \
    "printing" \
    "rebuild" \
    "stylix" \
    "sudo-rs" \
    "tools" \
    "zsh")

# 4. Ask for home-manager features
HM_FEATURES=$(gum choose --no-limit --header "Select HOME-MANAGER features to enable:" \
    "ai" \
    "anyrun" \
    "audio" \
    "bluetooth" \
    "discord" \
    "firefox" \
    "games" \
    "git" \
    "kitty" \
    "niri" \
    "nix" \
    "nushell" \
    "obs" \
    "spotify" \
    "ssh" \
    "stylix" \
    "subniri" \
    "swww" \
    "tools" \
    "unifiedremote" \
    "waybar" \
    "yazi" \
    "zsh")

echo "Starting installation for host: $HOSTNAME on disk: $DISK"

gum confirm "This will ERASE ALL DATA on $DISK. Are you sure?" || exit 0

mkdir -p /mnt
DOTFILES_DIR="/mnt/home/michael/.dotfiles/nix"

# Clone dotfiles to target location
gum spin --title "Cloning dotfiles to $DOTFILES_DIR..." -- \
    git clone https://github.com/IcyTv/nix-files.git "$DOTFILES_DIR"

# Partition disk using disko
gum spin --title "Partitioning disk $DISK using disko..." -- \
    nix run github:nix-community/disko -- --mode disko "$DOTFILES_DIR/modules/nixos/disko.nix" --argstr device "$DISK"

# Create host directories
mkdir -p "$DOTFILES_DIR/hosts/$HOSTNAME"

# Generate configuration.nix
cat > "$DOTFILES_DIR/hosts/$HOSTNAME/configuration.nix" <<EOF
{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
    inputs.home-manager.nixosModules.default
  ];

  networking.hostName = "$HOSTNAME";

  my.nixos.core.enable = true;
EOF

for feature in $SYSTEM_FEATURES; do
    echo "  my.nixos.$feature.enable = true;" >> "$DOTFILES_DIR/hosts/$HOSTNAME/configuration.nix"
done

cat >> "$DOTFILES_DIR/hosts/$HOSTNAME/configuration.nix" <<EOF

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "bak";

    users = {
      "michael" = import ./home.nix;
    };
  };

  # Make sure the kernel supports the hardware
  boot.kernelPackages = pkgs.linuxPackages;

  system.stateVersion = "25.11";
}
EOF

# Generate home.nix
cat > "$DOTFILES_DIR/hosts/$HOSTNAME/home.nix" <<EOF
{ config, pkgs, lib, inputs, ... }: {
  imports = [
    ../../modules/home-manager/default.nix
    inputs.nix-index-database.homeModules.nix-index
    inputs.spicetify-nix.homeManagerModules.default
    inputs.agenix.homeManagerModules.default
    inputs.nixcord.homeModules.nixcord
    inputs.subniri.homeModules.subniri
  ];

  my.hm.core.enable = true;
EOF

for feature in $HM_FEATURES; do
    echo "  my.hm.$feature.enable = true;" >> "$DOTFILES_DIR/hosts/$HOSTNAME/home.nix"
done

cat >> "$DOTFILES_DIR/hosts/$HOSTNAME/home.nix" <<EOF
}
EOF

# Generate hardware-configuration.nix
gum spin --title "Generating hardware-configuration.nix..." -- \
    nixos-generate-config --root /mnt --dir /tmp/nixos-config
cp /tmp/nixos-config/hardware-configuration.nix "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix"

# We must remove the fileSystems declarations from the generated config since disko handles it
sed -i '/fileSystems."\/" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/boot" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/nix" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/home" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/swap" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/swapDevices =/d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true

# Ensure the disko module is imported
sed -i "s|imports = \[|imports = [\n    ../../modules/nixos/disko.nix|g" "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix"

# Tell the new host to enable the disko module and set the correct target disk
cat >> "$DOTFILES_DIR/hosts/$HOSTNAME/configuration.nix" <<EOF

  my.nixos.disko.enable = true;
  my.nixos.disko.device = "$DISK";
EOF

# Add the new host to flake.nix dynamically
# We match 'nixosConfigurations = {' and append our host inside
gum spin --title "Updating flake.nix..." -- \
    sed -i "/nixosConfigurations = {/a \\
      $HOSTNAME = nixpkgs.lib.nixosSystem { \\
        specialArgs = { \\
          inherit inputs; \\
          self = filtered-src; \\
        }; \\
        modules = \\
          sharedModules \\
          ++ [ \\
            ./hosts/$HOSTNAME/configuration.nix \\
          ]; \\
      };" "$DOTFILES_DIR/flake.nix"

# Stage all files
pushd "$DOTFILES_DIR" > /dev/null
git add .
popd > /dev/null

gum spin --title "Installing NixOS..." -- \
    nixos-install --root /mnt --flake "$DOTFILES_DIR#$HOSTNAME" --no-root-passwd

gum style --foreground 212 "Installation Complete! You can now reboot."
#!/usr/bin/env bash
set -e

export GUM_SPIN_SPINNER="dot"

DRY_RUN=0
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=1
fi

clear
gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Welcome to the NixOS TUI Installer"

if [ $DRY_RUN -eq 1 ]; then
    gum style --foreground 214 "DRY RUN MODE ENABLED. No changes will be applied to the system."
fi

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

# 5. Ask for git-crypt key
GIT_CRYPT_KEY=""
if gum confirm "Do you have a git-crypt symmetric key to unlock secrets?"; then
    DETECTED_KEYS=()
    
    # 1. Check local home directory
    if [ -f "$HOME/.keys/git-crypt" ]; then
        DETECTED_KEYS+=("$HOME/.keys/git-crypt")
    fi
    
    # 2. Try to find and mount Ventoy to check for keys
    VENTOY_DEV=$(blkid -L Ventoy || true)
    if [ -n "$VENTOY_DEV" ]; then
        mkdir -p /tmp/ventoy
        mount -o ro "$VENTOY_DEV" /tmp/ventoy 2>/dev/null || true
        # Look for files containing 'git-crypt' in the name in the root of Ventoy
        for k in /tmp/ventoy/*git-crypt*; do
            if [ -f "$k" ]; then
                DETECTED_KEYS+=("$k")
            fi
        done
    fi

    if [ ${#DETECTED_KEYS[@]} -gt 0 ]; then
        echo "Auto-detected potential git-crypt keys:"
        OPTIONS=("Enter path manually")
        for k in "${DETECTED_KEYS[@]}"; do
            OPTIONS+=("$k")
        done
        CHOSEN_KEY=$(gum choose --header "Select a key or choose to enter manually:" "${OPTIONS[@]}")
        if [ "$CHOSEN_KEY" != "Enter path manually" ]; then
            GIT_CRYPT_KEY="$CHOSEN_KEY"
        fi
    fi

    if [ -z "$GIT_CRYPT_KEY" ]; then
        GIT_CRYPT_KEY=$(gum input --placeholder "Enter path to key file (e.g. /mnt/usb/key)..." --prompt "Key path: ")
    fi

    if [ -n "$GIT_CRYPT_KEY" ] && [ ! -f "$GIT_CRYPT_KEY" ] && [ $DRY_RUN -eq 0 ]; then
        gum style --foreground 196 "Warning: Key file not found at $GIT_CRYPT_KEY. Secrets will not be unlocked."
        GIT_CRYPT_KEY=""
    fi
fi

echo "Starting installation for host: $HOSTNAME on disk: $DISK"

gum confirm "This will ERASE ALL DATA on $DISK. Are you sure?" || exit 0

mkdir -p /mnt
DOTFILES_DIR="/mnt/home/michael/.dotfiles/nix"

if [ $DRY_RUN -eq 1 ]; then
    DOTFILES_DIR="/tmp/nixos-dry-run-dotfiles"
    mkdir -p "$DOTFILES_DIR"
    echo "Dry run: using $DOTFILES_DIR instead of /mnt/..."
fi

# Clone dotfiles to target location
if [ $DRY_RUN -eq 0 ]; then
    gum spin --title "Cloning dotfiles to $DOTFILES_DIR..." -- \
        git clone https://github.com/IcyTv/nix-files.git "$DOTFILES_DIR"
else
    gum spin --title "[DRY RUN] Cloning dotfiles to $DOTFILES_DIR..." -- \
        cp -r /home/michael/.dotfiles/nix/. "$DOTFILES_DIR"
fi

# Unlock secrets
if [ -n "$GIT_CRYPT_KEY" ]; then
    if [ $DRY_RUN -eq 0 ]; then
        gum spin --title "Unlocking git-crypt secrets..." -- \
            bash -c "cd $DOTFILES_DIR && git-crypt unlock $GIT_CRYPT_KEY"
    else
        echo "[DRY RUN] Would unlock git-crypt secrets using key $GIT_CRYPT_KEY."
    fi
fi

# Partition disk using disko
if [ $DRY_RUN -eq 0 ]; then
    gum spin --title "Partitioning disk $DISK using disko..." -- \
        nix run github:nix-community/disko -- --mode disko "$DOTFILES_DIR/modules/nixos/disko.nix" --argstr device "$DISK"
else
    echo "[DRY RUN] Would partition $DISK using disko."
fi

# Create host directories
mkdir -p "$DOTFILES_DIR/hosts/$HOSTNAME"

# Generate configuration.nix
cat > "$DOTFILES_DIR/hosts/$HOSTNAME/configuration.nix" <<EOF
{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
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

  my.nixos.disko.enable = true;
  my.nixos.disko.device = "$DISK";

  system.stateVersion = "25.11";
}
EOF

# Generate home.nix
cat > "$DOTFILES_DIR/hosts/$HOSTNAME/home.nix" <<EOF
{ config, pkgs, lib, inputs, ... }: {
  imports = [
    ../../modules/home-manager/default.nix
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
if [ $DRY_RUN -eq 0 ]; then
    gum spin --title "Generating hardware-configuration.nix..." -- \
        nixos-generate-config --root /mnt --dir /tmp/nixos-config
    cp /tmp/nixos-config/hardware-configuration.nix "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix"
else
    echo "[DRY RUN] Would generate hardware-configuration.nix."
    echo "{ config, lib, pkgs, modulesPath, ... }: {}" > "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix"
fi

# We must remove the fileSystems declarations from the generated config since disko handles it
sed -i '/fileSystems."\/" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/boot" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/nix" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/home" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/fileSystems."\/swap" =/,+12d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true
sed -i '/swapDevices =/d' "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix" || true

# Ensure the disko module is imported
sed -i "s|imports = \[|imports = [\n    ../../modules/nixos/disko.nix|g" "$DOTFILES_DIR/hosts/$HOSTNAME/hardware-configuration.nix"

# Flake is dynamically updated now, so we don't need to manually inject it!
echo "Flake reads directories dynamically! The new host will automatically be included."

# Stage all files
pushd "$DOTFILES_DIR" > /dev/null
git add .
popd > /dev/null

if [ $DRY_RUN -eq 0 ]; then
    gum spin --title "Installing NixOS..." -- \
        nixos-install --root /mnt --flake "$DOTFILES_DIR#$HOSTNAME" --no-root-passwd
    gum style --foreground 212 "Installation Complete! You can now reboot."
else
    echo "[DRY RUN] Would run: nixos-install --root /mnt --flake \"$DOTFILES_DIR#$HOSTNAME\" --no-root-passwd"
    gum style --foreground 214 "Dry run complete. Check $DOTFILES_DIR/hosts/$HOSTNAME to see the generated files."
fi

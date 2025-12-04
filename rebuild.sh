#!/usr/bin/env bash

set -euo pipefail

shopt -s extglob

HOST=$(hostname)

pushd ~/.dotfiles/nix

cleanup() {
	rm -f result
}
trap cleanup EXIT

alejandra . &>/dev/null || echo "Alejandra skipped or failed"

echo " Building system configuration..."

git add .
nixos-rebuild build --flake ".#$HOST" || exit 1

NEW_SYSTEM=$(readlink -f result)
CURRENT_SYSTEM=$(readlink -f /run/current-system)

if [ "$NEW_SYSTEM" == "$CURRENT_SYSTEM" ]; then
	echo " No changes detected. System is up to date."
	exit 0
fi

CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | grep -o -E '[0-9]+' | head -1)
NEXT_GEN=$((CURRENT_GEN + 1))

COMMIT_PREFIX="chore"
DIFF_OUTPUT=""
RAW_DIFF=""

if command -v nvd &> /dev/null; then
	echo "󰍉 Analyzing changes..."
	RAW_DIFF=$(nvd diff "$CURRENT_SYSTEM" "$NEW_SYSTEM")

	CLEAN_DIFF="${RAW_DIFF//+($'\e'[)+([0-9;])m/}"

	if [[ "$CLEAN_DIFF" == *"Added packages"* ]]; then
		COMMIT_PREFIX="feat"
	elif [[ "$CLEAN_DIFF" == *"Removed packages"* ]]; then
		COMMIT_PREFIX="refactor"
	fi

	DIFF_OUTPUT="$CLEAN_DIFF"
else
	echo " 'nvd' missing. Cannot analyze package changes"
fi

COMMIT_TITLE="$COMMIT_PREFIX(system): generation $NEXT_GEN"
COMMIT_MESSAGE="$COMMIT_TITLE

$DIFF_OUTPUT"

echo -e "\n Proposed Commit:"
echo "-------------------------------------------"
echo -e "\033[1;33m$COMMIT_TITLE\033[0m"
if [ -n "$RAW_DIFF" ]; then
	echo -e "\n$RAW_DIFF"
fi
echo "-------------------------------------------"

read -p "Do you want to switch to this configuration? (y/N)" -n1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo " Aborting"
	exit 1
fi

echo " Switching to new configuration..."
nixos-rebuild switch --sudo --flake ".#$HOST"

echo " Committing changes to git..."
git commit -am "$COMMIT_MESSAGE"

echo " Success! Switched to Generation $NEXT_GEN."

popd

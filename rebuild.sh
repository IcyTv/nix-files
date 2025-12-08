#!/usr/bin/env bash

set -euo pipefail
shopt -s extglob

TARGET_DIR="${FLAKE_PATH:-$PWD}"
if [[ ! -f "$TARGET_DIR/flake.nix" ]]; then
	echo " Error: no flake.nix found in $TARGET_DIR. Try setting 'FLAKE_PATH'"
	exit 1
fi

HOST="${HOSTNAME:-$(hostname)}"

pushd "$TARGET_DIR" >/dev/null

TEMP_COMMIT_CREATED=0

cleanup() {
	if [ "$TEMP_COMMIT_CREATED" -eq 1 ]; then
		echo -e "\n Script aborted or failed. Rolling back git changes..."
		git reset --soft HEAD~1
	fi

	rm -f result
}
trap cleanup EXIT

if command -v alejandra &>/dev/null; then
	alejandra . &>/dev/null || true
fi

echo " Building system configuration..."

git add .

if git diff --staged --quiet; then
	echo " No changes detected. Proceeding with existing commit"
else
	git commit -m "chore: rebuilding system (temp)" >/dev/null
	TEMP_COMMIT_CREATED=1
fi

if ! nixos-rebuild build --flake ".#$HOST"; then
	echo " Build failed!"
	exit 1
fi

NEW_SYSTEM=$(readlink -f result)
CURRENT_SYSTEM=$(readlink -f /run/current-system)

CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | grep -o -E '[0-9]+' | head -1)
NEXT_GEN=$((CURRENT_GEN + 1))

COMMIT_PREFIX="chore"
DIFF_OUTPUT=""
RAW_DIFF=""

if command -v nvd &>/dev/null; then
	echo "󰍉 Analyzing changes..."
	RAW_DIFF=$(nvd diff "$CURRENT_SYSTEM" "$NEW_SYSTEM") || true

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
if [ "$RAW_DIFF" != "" ]; then
	echo -e "\n$RAW_DIFF"
fi
echo "-------------------------------------------"

PROMPT_OPTS="y/N"
HAS_NVIM=0

if command -v nvim &>/dev/null; then
	PROMPT_OPTS="y/N/c"
	HAS_NVIM=1
fi

read -p "Do you want to switch to this configuration? ($PROMPT_OPTS) " -n1 -r
echo

if [[ $REPLY =~ ^[Cc]$ ]]; then
	if [ "$HAS_NVIM" -eq 1 ]; then
		echo "Opening commit message in neovim..."

		TMP_MSG=$(mktemp --suffix=.gitcommit)
		echo "$COMMIT_MESSAGE" >"$TMP_MSG"

		nvim "$TMP_MSG"

		COMMIT_MESSAGE=$(cat "$TMP_MSG")
		rm -f "$TMP_MSG"

		echo "Commit message updated..."
	else
		echo "neovim not found, cannot customize"
		exit 1
	fi
elif [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo " Aborting"
	exit 1
fi

echo " Switching to new configuration..."
if ! nixos-rebuild switch --sudo --flake ".#$HOST"; then
	echo " Switch failed!"
	exit 1
fi

echo " Committing changes to git..."
if [ "$TEMP_COMMIT_CREATED" -eq 1 ]; then
	git commit --amend -m "$COMMIT_MESSAGE" >/dev/null
else
	echo " No new changes to commit."
fi

TEMP_COMMIT_CREATED=0
echo " Success! Switched to Generation $NEXT_GEN."

popd >/dev/null

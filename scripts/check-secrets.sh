#!/usr/bin/env bash
set -euo pipefail

# Include ignored files: plaintext must stay outside the flake, not just Git.
while IFS= read -r -d '' file; do
  [[ -e "$file" || -L "$file" ]] || continue
  if [[ -L "$file" || ! -f "$file" ]]; then
    printf 'Refusing rebuild: secret is not a regular file: %s\n' "$file" >&2
    exit 1
  fi
  case "$file" in
    secrets/*.age)
      IFS= read -r header < "$file" || true
      if [[ "$header" != "age-encryption.org/v1" ]]; then
        printf 'Refusing rebuild: expected age ciphertext: %s\n' "$file" >&2
        exit 1
      fi
      ;;
    secrets/bookmarks-default.json|secrets/bookmarks-yes.json)
      attribute=$(git check-attr filter -- "$file")
      if [[ "$attribute" != "$file: filter: git-crypt" ]] ||
        ! git config --get filter.git-crypt.clean >/dev/null; then
        printf 'Refusing rebuild: git-crypt is not configured for %s\n' "$file" >&2
        exit 1
      fi
      ;;
    secrets/README.md) ;;
    *)
      printf 'Refusing rebuild: move plaintext/unrecognized secret outside the flake: %s\n' "$file" >&2
      exit 1
      ;;
  esac
done < <(git ls-files --cached --others -z -- secrets/)

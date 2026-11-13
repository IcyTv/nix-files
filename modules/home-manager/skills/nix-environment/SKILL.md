---
name: nix-environment
description: Work in NixOS development environments, resolve missing tools or libraries, and handle flake changes. Load before Nix environment changes or when an expected command or dependency is missing.
---

# Nix environment

Expect NixOS and a development environment usually defined by `flake.nix`.

- If an expected tool is missing, ask the user to restart their development
  shell. Prefer this over silently constructing another environment.
- If the user declines, run the required command through `nix develop`.
- For a tool not declared by the project, verify its package name using the
  NixOS MCP tools, then use `nix-shell -p <package>` when appropriate.
- Use NixOS MCP tools for current package, module-option, and flake-input facts.
- Use `nix-locate` for missing libraries or executables when appropriate. Ask
  the user if research cannot resolve the dependency.
- After changing `flake.nix`, prompt the user to restart their shell. Fall back
  to `nix develop` only if the user declines.
- Do not update lock files or dependencies as a side effect of validation. Use
  `--no-write-lock-file` for flake commands unless an update is in scope.

Delegates report environment blockers to the main agent instead of starting
another user approval flow.

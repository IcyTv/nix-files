# OpenCode LaTeX plugin

Packages `opencode-latex` 0.2.0 and `opentui-math` 0.1.0 for Numtide's
OpenCode 2.0.29. MathJax 4.1.3, its fonts, and resvg 2.6.2 are locked and
installed in the Nix output; this plugin needs no runtime npm downloads.

The upstream packages' `@opentui/core/yoga` imports can load a second OpenTUI
runtime, failing with a duplicate `OPENTUI_FORCE_UNICODE` registration. This
package replaces those imports with the host's `Yoga` export and bundles the
renderer, leaving `@opencode/plugin` and `@opentui/core` external. No second
OpenTUI package is installed. MathJax and resvg stay external to the JS bundle
so their local fonts, dynamic modules, and native addon remain available.

The Nix install check renders an equation to PNG inside the build sandbox.
For a real TUI integration test, run:

```sh
python3 modules/home-manager/packages/opencode-latex/test-tui.py /nix/store/…-opencode-latex-0.2.0
```

The test uses a private server, fresh XDG directories, and a pseudo-terminal;
it needs no credentials or model requests. It loads the packaged plugin and
tests its renderer with a quadratic formula and an aligned matrix, saving PNGs
and logs in a new temporary directory. `--output-dir` selects the parent of
that directory; `--opencode` selects the executable.

Graphical output requires a compatible terminal (e.g. Ghostty or Kitty).
The plugin's default `auto` mode falls back to terminal cells where necessary.
Use `/latex-render-mode` to change the mode.

When updating upstream sources, update the tarball URLs/hashes, verify the
three Yoga substitutions still apply, regenerate `package-lock.json` if runtime
dependencies change, and update `npmDepsHash`. Repeat the TUI integration test
when updating OpenCode as well.

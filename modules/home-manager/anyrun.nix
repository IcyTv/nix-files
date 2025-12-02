{pkgs, ...}: {
  programs.anyrun = {
    enable = true;
    config = {
      closeOnClick = true;
      maxEntries = 12;
      ignoreExclusiveZones = false;
      showResultsImmediately = true;
      hidePluginInfo = true;

      x = {fraction = 0.5;};
      y = {fraction = 0.3;};
      width = {fraction = 0.5;};

      plugins = [
        "${pkgs.anyrun}/lib/libapplications.so"
        "${pkgs.anyrun}/lib/libsymbols.so"
        "${pkgs.anyrun}/lib/libniri_focus.so"
        "${pkgs.anyrun}/lib/libnix_run.so"
        "${pkgs.anyrun}/lib/libshell.so"
        "${pkgs.anyrun}/lib/librink.so"
        "${pkgs.anyrun}/lib/libtranslate.so"
        "${pkgs.anyrun}/lib/libwebsearch.so"
      ];
    };

    extraConfigFiles."applications.ron".text = ''
      Config(
        desktop_actions: true,
        max_entries: 5,
        hide_description: true,
        terminal: Some(Terminal(
          command: "kitty",
          args: "-e {}",
        ))
      )
    '';
    extraConfigFiles."niri-focus.ron".text = ''
      Config(
        max_entries: 2,
      )
    '';
    extraConfigFiles."nix-run.ron".text = ''
      Config(
        prefix: ":nr ",
        allow_unfree: true,
        channel: "nixpkgs-stable",
        max_entries: 3,
      )
    '';

    extraCss =
      /*
      css
      */
      ''
        @define-color base #1e1e2e;
        @define-color text #cdd6f4;
        @define-color primary-color #b4befe;
        @define-color secondary-color #313244;
        @define-color border-color #9399b2;
        @define-color selected-bg-color @primary-color;
        @define-color selected-fg-color @secondary-color;

        * {
          all: unset;
          font-family: JetBrainsMono Nerd Font;
        }

        window {
          background: transparent;
        }

        box.main {
          border-radius: 16px;
          background-color: alpha(@base, 0.9);
          border: 0.5px solid alpha(@border-color, 0.25);
          border-radius: 16px;
        }

        text {
          font-size: 1.25rem;
          background: transparent;
          box-shadow: none;
          border: none;
          border-radius: 16px;
          padding: 16px 24px;
          min-height: 40px;
          caret-color: @primary-color;
        }

        list#main {
          background-color: transparent;
        }

        #plugin {
          background-color: transparent;
          padding-bottom: 4px;
        }

        .match {
          font-size: 1.1rem;
          padding: 2px 4px;
        }

        .match:selected,
        .match:hover {
          background-color: @selected-bg-color;
          color: @selected-fg-color;
        }

        .match:selected label.info,
        .match:hover label.info {
          color: @selected-fg-color;
        }

        .match:selected label.match.description,
        .match:hover label.match.description {
          color: alpha(@selected-fg-color, 0.9);
        }

        .match label.info {
          color: transparent;
          color: @text;
        }

        label.match.description {
          font-size: 1rem;
          color: @text;
        }

        label.plugin.info {
          font-size: 16px;
        }
      '';
  };
}

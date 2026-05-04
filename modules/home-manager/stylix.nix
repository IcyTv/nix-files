{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.stylix.enable = lib.mkEnableOption "Stylix home-manager theming";

  config = lib.mkIf config.my.hm.stylix.enable {
    stylix = {
      enable = true;
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
      polarity = "dark";

      cursor.package = pkgs.whitesur-cursors;
      cursor.name = "WhiteSur-cursors";
      cursor.size = 16;

      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.jetbrains-mono;
          name = "JetBrainsMono Nerd Font";
        };
      };

      iconTheme = {
        enable = true;
        package = pkgs.qlementine-icons;

        dark = "Qlementine";
        light = "Qlementine";
      };
    };
  };
}

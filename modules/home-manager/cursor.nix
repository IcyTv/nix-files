{ pkgs, ... }:
{
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.whitesur-cursors;
    size = 16;
    name = "WhiteSur-cursors";
  };
}

{...}: {
  services.swww.enable = true;

  home.file."Pictures/wallpapers" = {
    source = ./wallpapers;
    recursive = false;
  };
}

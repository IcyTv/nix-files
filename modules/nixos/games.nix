{...}: {
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.steam-hardware.enable = true;

  boot.kernelModules = ["uinput" "hid-playstation" "hid-sony"];
}

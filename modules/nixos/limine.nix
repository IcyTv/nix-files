{pkgs, ...}: {
  boot.loader.limine = {
    enable = true;
    maxGenerations = 5;
    enrollConfig = true;
    panicOnChecksumMismatch = true;
    extraEntries = ''
      # Windows
      / Windows
        protocol: efi_chainload
        image_path: guid(94832d6a-d3d8-4755-ab82-4bd8fbe9ae65):/EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };

  environment.systemPackages = [
    pkgs.sbctl
  ];
}

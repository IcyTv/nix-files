{pkgs, ...}: {
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
    ];
  };

  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [hplipWithPlugin];
  };
}

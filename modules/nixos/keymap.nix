{...}: {
  services.xserver.xkb = {
    layout = "us";
    variant = "altgr-intl";
    options = "caps:escape_shifted_capslock";
  };

  console.useXkbConfig = true;
}

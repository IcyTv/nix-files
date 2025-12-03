{...}: {
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = true;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_priority=3"
    "rd.systemd.show_status=auto"
  ];
  boot.loader.timeout = 0;
  boot.plymouth.enable = true;
}

{...}: {
  programs.walker = {
    enable = true;
    runAsService = true;

    config.theme = "catppuccin-mocha";
  };
}

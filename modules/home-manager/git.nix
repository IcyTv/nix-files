{pkgs, ...}: {
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      init = {
        defaultBranch = "main";
      };

      push = {
        autoSetupRemote = true;
      };

      user = {
        name = "Michael Finger";
        email = "michael.finger@icytv.de";
      };

      url = {
        "https://github.com/" = {
          insteadOf = [
            "gh:"
            "github:"
          ];
        };
      };
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "ssh";
  };

  home.packages = [
    pkgs.git-crypt
  ];
}

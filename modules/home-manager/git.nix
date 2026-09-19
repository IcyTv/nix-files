{
  pkgs,
  config,
  lib,
  ...
}: {
  options.my.hm.git.enable = lib.mkEnableOption "Git and GitHub CLI configuration";

  config = lib.mkIf config.my.hm.git.enable {
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

      signing = {
        format = "openpgp";
        key = "433D8E22007D3A9762D54780ED06A3B7C8B9C6B0!";
        signByDefault = true;
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
  };
}

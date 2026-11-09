{
  pkgs,
  config,
  lib,
  ...
}: let
in {
  options.my.hm.git.enable = lib.mkEnableOption "Git and GitHub CLI configuration";

  options.my.hm.git.excludes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Paths to globally exclude from git";
  };

  config = lib.mkIf config.my.hm.git.enable {
    programs.git = {
      enable = true;
      lfs.enable = true;
      settings = {
        core = let
          excludesfile = pkgs.writeText "gitignore" (lib.concatStringsSep "\n" config.my.hm.git.excludes);
        in {
          excludesfile = "${excludesfile}";
        };

        init = {
          defaultBranch = "main";
        };

        push = {
          autoSetupRemote = true;
        };

        user = {
          name = config.icy.git.name;
          email = config.icy.git.email;
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
        signByDefault = config.icy.git.signing;
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

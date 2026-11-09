{lib, ...}: {
  options.icy = {
    user.name = lib.mkOption {
      type = lib.types.str;
      default = "michael";
    };
    personalSecrets = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    git = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Michael Finger";
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "michael.finger@icytv.de";
      };
      signing = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };
}

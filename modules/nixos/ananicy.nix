{
  config,
  lib,
  pkgs,
  ...
}: {
  options.my.nixos.ananicy.enable = lib.mkEnableOption "Ananicy auto nice daemon";

  config = lib.mkIf config.my.nixos.ananicy.enable {
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
      settings = {
        apply_cgroup = false;
        cgroup_load = false;
        check_freq = 5;
        log_applied_rule = true;
      };

      extraTypes = [
        {
          type = "BuildTool";
          nice = 16;
          sched = "idle";
          ioclass = "idle";
          latency_nice = 11;
        }
      ];

      extraRules = let
        buildTools = [
          "ar"
          "cargo"
          "cc"
          "cc1"
          "cc1plus"
          "clang"
          "clang++"
          "cmake"
          "g++"
          "gcc"
          "ld"
          "ld.lld"
          "lld"
          "make"
          "mold"
          "ninja"
          "ranlib"
          "rustc"
        ];
      in
        map (name: {
          inherit name;
          type = "BuildTool";
        })
        buildTools;
    };
  };
}

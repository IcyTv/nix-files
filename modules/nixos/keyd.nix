{pkgs, ...}: {
  services.keyd = {
    enable = true;
    keyboards.defalt = {
      ids = ["*"];
      settings = {
        main = {
          capslock = "overload(wm, esc)";
        };
        shift = {
          capslock = "capslock";
        };
        "wm:M" = {
          d = "layer(wmshift)";
        };
        "wmshift:M=S" = {
        };
      };
    };
  };
}

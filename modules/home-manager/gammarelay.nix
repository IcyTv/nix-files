{
  pkgs,
  config,
  lib,
  ...
}: let
  wl-gammarelay = pkgs.buildGoModule {
    pname = "wl-gammarelay";
    version = "0.1.3";

    src = pkgs.fetchFromGitHub {
      owner = "jeremija";
      repo = "wl-gammarelay";
      rev = "v0.1.3";
      hash = "sha256-XD9BKaNfxH02Fi7szs23HSfLsTbcUlxw30lZTTDOv+E=";
    };

    vendorHash = "sha256-yJ6AuL0cmU+rMQNv3lmHQQSVipUZAUFxsLvthIsoS+s=";

    buildInputs = with pkgs; [
      wlr-protocols
      wayland
    ];

    nativeBuildInputs = with pkgs; [
      wayland-scanner
      pkg-config
    ];

    preBuild = ''
      pushd protocol

      make all

      popd
    '';
    meta = with lib; {
      description = "A client and daemon for changing color temperature and brightness under Wayland via keybindings.";
      homepage = "https://github.com/jeremija/wl-gammarelay";
      license = licenses.gpl3;
    };
  };
in {
  options.my.hm.gammarelay.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.gammarelay.enable {
    home.packages = [wl-gammarelay];
  };
}

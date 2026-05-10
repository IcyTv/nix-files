{
  pkgs,
  config,
  lib,
  ...
}: let
  version = "0.1.3";
  wl-gammarelay = pkgs.buildGoModule {
    pname = "wl-gammarelay";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "jeremija";
      repo = "wl-gammarelay";
      rev = "v${version}";
      hash = "sha256-XD9BKaNfxH02Fi7szs23HSfLsTbcUlxw30lZTTDOv+E=";
    };

    vendorHash = "sha256-yJ6AuL0cmU+rMQNv3lmHQQSVipUZAUFxsLvthIsoS+s=";

    buildInputs = with pkgs; [
      wayland
    ];

    nativeBuildInputs = with pkgs; [
      wayland-scanner
      pkg-config
    ];

    buildPhase = ''
      runHook preBuild

      make protocol build \
        VERSION=${version} \
        COMMIT_HASH=nixpkgs \
        GOFLAGS="-mod=vendor -trimpath"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin

      make install \
        PREFIX=$out \
        VERSION=${version} \
        COMMIT_HASH=nixpkgs

      runHook postInstall
    '';

    doCheck = false;

    meta = with lib; {
      description = "A client and daemon for changing color temperature and brightness under Wayland via keybindings.";
      homepage = "https://github.com/jeremija/wl-gammarelay";
      license = licenses.gpl3;
    };
  };
in {
  options.my.hm.gammarelay.enable = lib.mkEnableOption "Gaming tools (Lutris, Proton)";

  config = lib.mkIf config.my.hm.gammarelay.enable {
    systemd.user.services.wl-gammarelay = {
      Unit = {
        Description = "Gammarelay for controling brightness and temerature via dbus";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "${wl-gammarelay}/bin/wl-gammarelay";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        # This is the magic line that "enables" it by default
        # when you log into your Wayland session.
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home-manager/default.nix
  ];

  icy.internal.core.enable = true;
  my.hm.default.enable = true;
  my.hm.chromium.enable = true;
  my.hm.daw.enable = true;
  my.hm.minecraft.enable = true;

  programs.git.signing.key = "433D8E22007D3A9762D54780ED06A3B7C8B9C6B0!";

  programs.chromium = {
    commandLineArgs = [
      "--ozone-platform=wayland"
      "--disable-features=Vulkan"
      "--enable-features=VaapiOnNvidiaGPUs,AcceleratedVideoDecodeLinuxGL"
    ];

    package = pkgs.chromium.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
      buildCommand =
        old.buildCommand
        + ''
          wrapProgram "$out/bin/chromium" \
            --set VK_DRIVER_FILES /etc/vulkan/icd.d/nvidia_icd.json \
            --set LIBVA_DRIVER_NAME nvidia
        '';
    });
  };

  programs.firefox = {
    package = pkgs.firefox.overrideAttrs (old: {
      # NVIDIA VA-API requires disabling the media-decoder sandbox on this host.
      makeWrapperArgs =
        (old.makeWrapperArgs or [])
        ++ [
          "--set"
          "LIBVA_DRIVER_NAME"
          "nvidia"
          "--set"
          "MOZ_DISABLE_RDD_SANDBOX"
          "1"
        ];
    });

    profiles = lib.genAttrs ["default" "yes"] (_: {
      settings."media.hardware-video-decoding.force-enabled" = true;
    });
  };

  programs.niri = {
    settings.outputs = {
      "DP-3" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 0;
          y = 0;
        };
      };
      "DP-2" = {
        enable = true;
        focus-at-startup = true;
        mode = {
          width = 2560;
          height = 1440;
          refresh = 239.97;
        };
        position = {
          x = 1920;
          y = 0;
        };
      };
      "HDMI-A-1" = {
        enable = true;
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 4480;
          y = 0;
        };
      };
    };
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "DP-3,1920x1080@60,0x0,1"
      "DP-2,2560x1440@239.97,1920x0,1"
      "HDMI-A-1,1920x1080@60,4480x0,1"
    ];
    workspace = [
      "9, monitor:HDMI-A-1"
    ];
  };
}

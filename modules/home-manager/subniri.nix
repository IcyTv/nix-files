{
  config,
  lib,
  ...
}: {
  options.my.hm.subniri.enable = lib.mkEnableOption "Subniri integration";

  config = lib.mkIf config.my.hm.subniri.enable {
    services.subniri = {
      enable = true;
      settings = {
        nightlight = {
          enable = true;
          dawn = "07:00";
          dusk = "22:30";
          night = {
            temperature = 1800;
            brightness = 0.7;
          };
        };

        spotify = {
          enable = true;
        };

        homeassistant = {
          enable = true;
          url = "https://assistant.icytv.de";
          trackedDevices = ["scene.livingroom_bright" "scene.livingrom_evening" "input_boolean.nighlights_active" "script.1714814456677" "light.bedroom_lamp" "light.living_room_lamp" "scene.livingrom_middle" "scene.livingroom_off"];
        };

        systemMenu.rows = [
          [
            {
              widget = "wifi";
              width = 1;
              height = 1;
            }
            {
              widget = "bluetooth";
              width = 1;
              height = 1;
            }
            {
              widget = "speaker";
              width = 1;
              height = 1;
            }
            {
              widget = "microphone";
              width = 1;
              height = 1;
            }
            {
              widget = "script.1714814456677";
              width = 2;
              height = 1;
            }
          ]
          [
            {
              widget = "nightlight";
              width = 4;
              height = 2;
            }
            {
              widget = "light.bedroom_lamp";
              width = 2;
              height = 1;
            }
          ]
          [
            {gap = 4;}
            {
              widget = "light.living_room_lamp";
              width = 2;
              height = 1;
            }
          ]
          [
            {
              widget = "scene.livingroom_bright";
              width = 3;
              height = 1;
            }
            {
              widget = "scene.livingrom_middle";
              width = 3;
              height = 1;
            }
          ]
          [
            {
              widget = "scene.livingrom_evening";
              width = 3;
              height = 1;
            }
            {
              widget = "scene.livingroom_off";
              width = 3;
              height = 1;
            }
          ]
          [
            {
              widget = "input_boolean.nighlights_active";
              width = 3;
              height = 1;
            }
          ]
        ];
      };
    };
  };
}

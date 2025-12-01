{ config, pkgs, ... }:

{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri --theme 'prompt=blue;user=green;user_default=green;password=white;password_default=white;password_hidden=white;borders=blue;text=white;text_secondary=brightblack'";
      };
    };
  };

  environment.systemPackages = [
    pkgs.tuigreet
  ];
}

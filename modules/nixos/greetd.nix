{
  config,
  pkgs,
  ...
}: {
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --remember --remember-user-session --asterisks --time --user-menu --theme 'prompt=blue;user=green;user_default=green;password=white;password_default=white;password_hidden=white;borders=blue;text=white;text_secondary=brightblack'";
        user = "greeter";
      };
    };
  };

  security.pam.services.greetd.enableGnomeKeyring = false;

  environment.systemPackages = [
    pkgs.tuigreet
  ];
}

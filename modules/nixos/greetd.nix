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
        command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri --remember --remember-session --remember-user-session --asterisks --time --greeting 'IcyTvs System' --user-menu --theme 'prompt=blue;user=green;user_default=green;password=white;password_default=white;password_hidden=white;borders=blue;text=white;text_secondary=brightblack'";
        user = "greeter";
      };
    };
  };

  environment.systemPackages = [
    pkgs.tuigreet
  ];
}

{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.icy.internal.core.enable && config.icy.personalSecrets && config.programs.pay-respects.enable) {
    age.secrets.pay-respects-api-key = {
      file = ../../secrets/pay-respects-api-key.age;
      mode = "600";
    };

    programs.pay-respects.package = pkgs.writeShellApplication {
      name = "pay-respects";
      runtimeInputs = [pkgs.pay-respects];
      runtimeEnv = {
        PAY_RESPECTS_BIN = lib.getExe pkgs.pay-respects;
      };
      # agenix paths contain a shell expression, expanded here at runtime.
      text =
        ''
          XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
          PAY_RESPECTS_KEY_FILE="${config.age.secrets.pay-respects-api-key.path}"
        ''
        + builtins.readFile ../../scripts/pay-respects.sh;
    };
  };
}

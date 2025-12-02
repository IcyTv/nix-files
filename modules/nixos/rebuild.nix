{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "rebuild";
      runtimeInputs = [pkgs.git pkgs.nvd pkgs.alejandra];
      text = builtins.readFile ../../rebuild.sh;
    })
  ];
}

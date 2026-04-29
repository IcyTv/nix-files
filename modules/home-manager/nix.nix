{ pkgs, config, lib, ... }: {
  options.my.hm.nix.enable = lib.mkEnableOption "Nix related tools (alejandra, nvd)";

  config = lib.mkIf config.my.hm.nix.enable {
    home.packages = [
      pkgs.alejandra
      pkgs.nvd
    ];
  };
}
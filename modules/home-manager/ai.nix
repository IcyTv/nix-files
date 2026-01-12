{inputs, ...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.opencode;

    settings = {
      autoshare = false;
      plugin = [
        "opencode-gemini-auth@latest"
      ];
    };
  };

  programs.mcp = {
    enable = true;
    servers = {
      mcp-nixos = {
        command = "nix";
        args = [
          "run"
          "github:utensils/mcp-nixos"
          "--"
        ];
      };
    };
  };
}

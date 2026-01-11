{...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

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

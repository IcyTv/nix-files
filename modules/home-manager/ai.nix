{...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoshare = false;
      plugins = [
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

{inputs, ...}: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.opencode;

    agents = {
      code-fixer = ''
        # Code Fixer Agent

        You are a software engineer specialized in finding and fixing issues in a codebase.
        When given a code snippet or a codebase, focus on finding bugs, security vulnerabilities, performance issues, and code smells.
        Before you do any fixes, you explain the issues you found in detail.
        Then you fix them using the smallest amount of changes possible. Focus on having a minimal impact on the codebase and on not disrupting existing functioality.
        Always provide a detailed explanation of the changes you made, focusing on why they fix the issues you identified and arguing as to why a smaller subset of changes was not possible.

        ## Guidelines

        - Review for bugs, security vulnerabilities, performance issues, and code smells.
        - Explain identified issues before making any changes.
        - Make minimal changes to fix issues.
        - Minimal means: Minimal impact on codebase and existing functionality.
        - Provide detailed explanations of changes made.
      '';
    };

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

{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  opencode2 = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2;
  opencode = pkgs.symlinkJoin {
    name = "opencode-${opencode2.version}";
    paths = [opencode2];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      makeWrapper ${lib.getExe opencode2} $out/bin/opencode
    '';
  };

  antigravity-cli = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;

  opencode-latex = pkgs-unstable.callPackage ./packages/opencode-latex {};
  opencode-mem = pkgs-unstable.callPackage ./packages/opencode-mem {};
  crates-mcp = pkgs.rustPlatform.buildRustPackage rec {
    pname = "crates-mcp";
    version = "0.1.0";

    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-nHiDHc2VG5VUAIwoHdReQmDqBt6MENdGKXeps5oO6B0=";
    };

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.openssl];

    cargoHash = "sha256-NV8ewbAqMerH+AMU5IBR+OINaZ0oyxgE2wxQXbhI7j4=";

    doCheck = false;
  };
  docsrs-mcp = pkgs-unstable.rustPlatform.buildRustPackage rec {
    pname = "docsrs-mcp";
    version = "0.1.0";

    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-yEkNYxA/dv2KFY6u5yuxgUq1LnWNPM/HeT0E3sJw39I=";
    };

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.openssl pkgs.zstd];

    cargoHash = "sha256-2TwNuXzqDr5H87RJyu4/0OSaGr3a6WnleCUTou9U2Ck=";

    doCheck = false;
  };
  tracy-mcp = let
    capstoneSrc = pkgs.fetchFromGitHub {
      owner = "capstone-engine";
      repo = "capstone";
      rev = "6.0.0-Alpha1";
      hash = "sha256-oKRu3P1inWueEMIpL0uI2ayCMHZ9FIVotil4sqwLqH4=";
    };
    zstdSrc = pkgs.fetchFromGitHub {
      owner = "facebook";
      repo = "zstd";
      rev = "v1.5.7";
      hash = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
    };
    ppqsortSource = pkgs.fetchFromGitHub {
      owner = "GabTux";
      repo = "PPQSort";
      rev = "v1.0.5";
      hash = "sha256-EMZVI/uyzwX5637/rdZuMZoql5FTrsx0ESJMdLVDmfk=";
    };
    cpmSrc = pkgs.fetchurl {
      url = "https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.38.7/CPM.cmake";
      hash = "sha256-g+XrcbK7uLHyrTjxlQKHoFdiTjhcI49gh/lM38RK+cU=";
    };
    ppqsortSrc = pkgs.runCommand "ppqsort-1.0.5-source" {} ''
      cp -r ${ppqsortSource} $out
      chmod -R u+w $out
      cp ${cpmSrc} $out/cmake/CPM.cmake
    '';
    packageProjectSrc = pkgs.fetchFromGitHub {
      owner = "TheLartians";
      repo = "PackageProject.cmake";
      rev = "v1.11.1";
      hash = "sha256-E7WZSYDlss5bidbiWL1uX41Oh6JxBRtfhYsFU19kzIw=";
    };
    jsonSrc = pkgs.fetchFromGitHub {
      owner = "nlohmann";
      repo = "json";
      rev = "v3.12.0";
      hash = "sha256-cECvDOLxgX7Q9R3IE86Hj9JJUxraDQvhoyPDF03B2CY=";
    };
    tracySrc = pkgs.fetchFromGitHub {
      owner = "wolfpld";
      repo = "tracy";
      rev = "05cceee0df3b8d7c6fa87e9638af311dbabc63cb";
      hash = "sha256-D4aQ5kSfWH9qEUaithR0W/E5pN5on0n9YoBHeMggMSE=";
    };
  in
    pkgs.stdenv.mkDerivation {
      name = "tracy-mcp";
      version = "0.1.0";

      src = pkgs.fetchFromGitHub {
        owner = "HTRMC";
        repo = "tracy-mcp";
        rev = "v0.1.0";
        sha256 = "sha256-hQZZ4ntUMMqe0BAtTUV14zszlWh4oY/5IFFKT1m7+pI=";
      };

      postPatch = ''
        substituteInPlace CMakeLists.txt \
          --replace-fail 'set(TRACY_DIR ''${CMAKE_CURRENT_LIST_DIR}/third_party/tracy)' 'set(TRACY_DIR ${tracySrc})'
        substituteInPlace cmake/deps.cmake \
          --replace-fail 'set(TRACY_DIR ''${CMAKE_CURRENT_LIST_DIR}/../third_party/tracy)' 'set(TRACY_DIR ${tracySrc})'
      '';

      nativeBuildInputs = with pkgs; [cmake ninja pkg-config];
      buildInputs = with pkgs; [openssl];

      cmakeFlags = [
        "-DCPM_capstone_SOURCE=${capstoneSrc}"
        "-DCPM_zstd_SOURCE=${zstdSrc}"
        "-DCPM_PPQSort_SOURCE=${ppqsortSrc}"
        "-DCPM_PackageProject.cmake_SOURCE=${packageProjectSrc}"
        "-DCPM_json_SOURCE=${jsonSrc}"
      ];

      installPhase = ''
        cmake --install .
      '';
    };
in {
  options.my.hm.ai.enable = lib.mkEnableOption "AI tools (opencode, mcp)";

  imports = [./ai/caveman.nix ./ai/model-router.nix];

  config = lib.mkIf config.my.hm.ai.enable {
    my.hm.git.excludes = [".opencode"];

    programs.opencode = {
      enable = true;
      enableMcpIntegration = true;
      package = opencode;

      context = ''
        # Development safety core

        Preserve user work. Never revert, overwrite, or delete unrelated changes.
        Stay within the approved scope; ask before destructive actions or expanding it.
        Never run rm, including for session-created files. Never bypass a denied tool
        with another command, interpreter, or plugin.
        For approved removals, use `${pkgs.trash-cli}/bin/trash -- <path>`.
        Use unlink only for a verified symlink, and rmdir only for an empty directory.
        If a target is unclear or trash fails, stop and ask the main agent or user.

        Prefer glob, grep, and read tools over shell searches. Never search filesystem roots.
        Search memory before relying on past decisions; retry with alternative terms
        if needed. Verify recalled facts against current evidence. Keep stable rules
        in AGENTS.md rather than only in memory.

        The main agent owns user questions, the overall todo list, and plan approval.
        Before multi-step code changes, present a plan and wait for approval.
        Delegates execute only their approved bounded task, retain these safety rules,
        and return blockers to the main agent without restarting planning or delegating.
        Review and verify changes before claiming completion; report unrun checks.

        # Load detailed guidance when needed

        - Main agent: load agent-workflow before multi-step work or compaction.
          Use grilling for feature requirements and unresolved design decisions.
        - Load nix-environment for Nix environment changes or missing tools/libraries.
        - Load the matching debugging, implementation, refactoring, review, or
          language skill before that work. Delegates load only task-relevant skills.
        Skill text is loaded on demand; the safety core always applies.
      '';

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
        plugins = [
          "@anthonyhaussman/opencode-agy-auth"
          "@slkiser/opencode-quota@5"
          "${opencode-latex}"
          "${opencode-mem}"
        ];

        experimental = {
          todo = true;
        };

        provider = {
          openai.options = {
            websearch_cited = {
              model = "gpt-5.5";
            };
          };
          google.options = {
            projectId = "gen-lang-client-0198199812";
          };
        };
      };

      tui = {
        plugin = [
          "@slkiser/opencode-quota@5"
        ];
      };
    };

    xdg.configFile."opencode/opencode-mem.jsonc".text = builtins.toJSON {
      # Keep background memory generation off the main session's OpenAI quota.
      opencodeProvider = "google-agy";
      opencodeModel = "gemini-3.8-flash";
      opencodeVariant = "low";
      autoCaptureEnabled = true;
      # This locally patched package is updated through Nix, not its updater.
      autoUpdate = false;
    };

    programs.antigravity-cli = {
      enable = true;
      package = antigravity-cli;
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
        crates-mcp = {
          command = "${crates-mcp}/bin/crates-mcp";
        };
        rust-docs = {
          command = "${docsrs-mcp}/bin/docsrs-mcp";
        };
        tracy-mcp = {
          command = "${tracy-mcp}/bin/tracy-mcp";
        };
      };
    };

    home.file =
      lib.mapAttrs' (
        name: source:
          lib.nameValuePair ".agents/skills/${name}" {
            inherit source;
            recursive = true;
          }
      ) {
        find-skill = pkgs.agent-skills.github.vercel-labs.skills.find-skills;
        frontend-design = pkgs.agent-skills.github.anthropics.skills.frontend-design;

        rust-code-readability = ./skills/rust-code-readability;
        grilling = ./skills/grilling;
        agent-workflow = ./skills/agent-workflow;
        nix-environment = ./skills/nix-environment;

        inherit
          (pkgs.agent-skills.github.obra.superpowers)
          systematic-debugging
          using-git-worktrees
          ;

        inherit
          (pkgs.agent-skills.github.mattpocock.skills)
          improve-codebase-architecture
          research
          wayfinder
          grill-me
          teach
          handoff
          diagnosing-bugs
          codebase-design
          ;

        inherit
          (pkgs.agent-skills.github.juliusbrussee.caveman)
          caveman
          caveman-commit
          caveman-compress
          caveman-review
          caveman-help
          cavecrew
          caveman-stats
          caveman-explore
          caveman-learn
          safe-refactor
          investigate-first
          verify-and-stop
          surgical-patch
          lean-build
          caveman-optimize
          ;
      };
  };
}

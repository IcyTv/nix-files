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
    buildInputs = [pkgs.openssl];

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

  config = lib.mkIf config.my.hm.ai.enable {
    programs.opencode = {
      enable = true;
      enableMcpIntegration = true;
      package = pkgs-unstable.opencode;

      context = ''
        # General Development Rules

        ## Removal of files and directories

        CRITICAL: Never, ever run `rm -rf` to delete files or directories. This command is extremely dangerous and can lead to irreversible data loss. Instead, use safer alternatives like `${pkgs.trash-cli}/bin/trash` to move files to the trash.

        ```
        usage: ${pkgs.trash-cli}/bin/trash [OPTION]... FILE...

        Put files in trash

        positional arguments:
          files

        options:
          -h, --help            show this help message and exit
          --print-completion {bash,zsh,tcsh}
                                print shell completion script
          -d, --directory       ignored (for GNU rm compatibility)
          -f, --force           silently ignore nonexistent files
          -i, --interactive     prompt before every removal
          -r, -R, --recursive   ignored (for GNU rm compatibility)
          --trash-dir TRASHDIR  use TRASHDIR as trash folder
          -v, --verbose         explain what is being done
          --version             show program's version number and exit

        all trash-cli commands:
          trash-put             trash files and directories.
          trash-list            list trashed files.
          trash-restore         restore a trashed file.

        To remove a file whose name starts with a '-', for example '-foo',
        use one of these commands:

            trash -- -foo

            trash ./-foo
        ```

        Other options include:
        - If the target is a symlink, use `unlink` to remove it.
        - Checking the target thoroughly before running `rm` (no `-f` and no `-r`), deleting files individually.
        - Using `rmdir` to delete empty directories.

        It is only ever acceptible to delete files or directories, if *you* created them in this session.
        It is generally unacceptible to delete any non-generated code files.

        If you're unsure about whether a file or directory can be deleted, ask for clarification before proceeding. It's better to be safe than sorry.
        If the `trash` cli fails to execute, ask for clarification before proceeding.

        ## Searching for files or file contents

        Prefer the use of builtin tools (like glob or grep) to find files.
        Disfavor the use of command-lines or shells to find files or file contents.

        NEVER use tools like glob or grep on filesystem root(s).

        ## Longer/Multistep implementations

        When doing long or multistep implementations, break them down into smaller, more manageable tasks before starting.
        Try to figure out the roadblocks, and how to resolve them ahead of time, using websearches, code searches or by asking the user.
        Before doing any code changes, use the todos tool to write a step-by-step plan. Try to include as much detail as necessary, including the solutions to possible roadblocks you've found.
        Present that plan to the user for review and approval before proceeding with any code changes.

        ### Compaction

        Longer-term implementations will likely exceed any context window you have. That is, when you will need to compact the previous context to make room for new context.
        You will be prompted for compaction automatically, and you won't have to do that yourself.
        When you do this, you should try to compact the context in a way that preserves as much relevant information as possible, while removing irrelevant or redundant information, like old or finished tasks.
        If you need to mention finished tasks in the compaction, try to keep it as short as possible.
        If you need more space, for example to explain roadblocks you've overcome, for a finished task, write them to /tmp/opencode/<UNIQUE_TASK_NAME>.md and in the compacted context, write:
          "Did <Task description>. For more details see /tmp/opencode/<UNIQUE_TASK_NAME>.md"

        You should also try to preserve the structure of the context, so that it is still easy to read and understand.
        During compaction, make sure you are aware, what the current state of the project is, what the blockers are and what is already done and relay that as concicely as possible.

        ### Roadblocks

        If you encounter roadblocks during your efforts, there is a multistep process you should follow (in that order):

        1. Try to find a solution by doing a websearch. Oftentimes roadblocks you encounter will have been solved by someone else before.
           You will at least be able to find some terminology and ideas for further research.
        2. Read local code. If you are unable to find a promising solution using websearches, the next step is to look at the locally installed code and dependencies.
           Use the glob and grep tools to find code relevant to the blocker. Try to trace any codepaths that are relevant.
           Use the GNU `binutils` tools to explore binary files only if needed.
        3. Ask the user for guidance. Explain the blocker you've encountered in detail.
           Then explain to them, what research you've done, what has panned out and what hasn't.
           Link them to relevant issues (GitHub issues preferred, other git-provider issues work as well, forums are acceptible, but not preferred).

        ## Commands

        You will generally be acting on NixOS, inside an isolated environment, generally defined at @flake.nix.
        If any tools you expect to see, based on the flake, are missing either:
        - Prompt the user to restart your shell (preferred)
        - Run commands using `nix develop`.

        If you need tools not specified in the flake, you should ask the user for permission to install them, and then install them using `nix-shell -p <package>`.
        Use the nixos mcp (if available) to check the naming of packages.

        If you can't find certain tools, libraries or packages you need, you can either use `nix-locate` to find them, or ask the user for guidance.

        If you update the @flake.nix yourself, always prompt the user for a shell restart. Only fall back on `nix develop` if the user declines.
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
        plugin = [
          "opencode-gemini-auth@latest"
          "opencode-websearch-cited@1.2.0"
          "opencode-dynamic-context-pruning@latest"
        ];

        provider = {
          openai.options = {
            websearch_cited = {
              model = "gpt-5.2";
            };
          };
        };
      };
    };

    programs.antigravity-cli = {
      enable = true;
      package = pkgs-unstable.antigravity-cli;
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
  };
}

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
  serena = inputs.serena.packages.${pkgs.stdenv.hostPlatform.system}.serena;
  serenaConfigMerge = pkgs.writeText "serena-config-merge.py" ''
    import copy
    import io
    import os
    from pathlib import Path
    import stat
    import sys
    import tempfile
    from collections.abc import Mapping, MutableMapping

    from filelock import FileLock
    from ruamel.yaml import YAML
    from ruamel.yaml.comments import CommentedMap


    def mapping(parent, key):
        if key not in parent:
            parent[key] = CommentedMap()
        value = parent[key]
        if not isinstance(value, MutableMapping):
            raise ValueError(f"{key} must be a YAML mapping")
        return value


    def merge_defaults(target, defaults):
        for key, value in defaults.items():
            if key not in target:
                target[key] = copy.deepcopy(value)
            elif isinstance(value, Mapping):
                merge_defaults(mapping(target, key), value)


    def target_stat(path):
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"Refusing symlink or nonregular config: {path}")
        return info


    def fingerprint(info):
        if info is None:
            return None
        return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
                info.st_mtime_ns, info.st_ctime_ns)


    def merge_config(path):
        previous = target_stat(path)
        original = b""
        if previous is not None:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, "rb") as source:
                opened = os.fstat(source.fileno())
                if not stat.S_ISREG(opened.st_mode) or fingerprint(opened) != fingerprint(previous):
                    raise ValueError(f"Config changed while opening: {path}")
                original = source.read()

        yaml = YAML(typ="rt")
        yaml.preserve_quotes = True
        document = yaml.load(original.decode("utf-8"))
        empty_comments = ""
        if document is None:
            if yaml.compose(original.decode("utf-8")) is not None:
                raise ValueError("Serena config must be a YAML mapping or empty")
            empty_comments = "".join(
                line + "\n" for line in original.decode("utf-8").splitlines()
                if not line.strip() or line.lstrip().startswith("#")
            )
            document = CommentedMap()
        if not isinstance(document, MutableMapping):
            raise ValueError("Serena config must be a YAML mapping or empty")

        if "projects" not in document:
            document["projects"] = []
        settings = mapping(document, "ls_specific_settings")
        rust = mapping(settings, "rust")
        options = mapping(rust, "initializationOptions")
        cargo = mapping(options, "cargo")
        # Serena shallowly replaces cargo; retain its pinned base defaults.
        merge_defaults(cargo, {
            "autoreload": True,
            "buildScripts": {
                "enable": True,
                "invocationLocation": "workspace",
                "invocationStrategy": "per_workspace",
                "overrideCommand": None,
                "useRustcWrapper": True,
            },
            "cfgs": [],
            "extraArgs": [],
            "extraEnv": {},
            "features": [],
            "noDefaultFeatures": False,
            "sysroot": "discover",
            "sysrootSrc": None,
            "target": None,
            "unsetTest": ["core"],
        })
        args = cargo["extraArgs"]
        if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
            raise ValueError("cargo.extraArgs must be a list of strings")
        if "--locked" not in args:
            args.append("--locked")
        options["checkOnSave"] = False

        output = io.StringIO()
        yaml.dump(document, output)
        rendered = (empty_comments + output.getvalue()).encode("utf-8")
        if previous is not None and rendered == original:
            return

        temporary = None
        try:
            fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
            with os.fdopen(fd, "wb") as destination:
                os.fchmod(destination.fileno(), stat.S_IMODE(previous.st_mode) if previous else 0o600)
                destination.write(rendered)
                destination.flush()
                os.fsync(destination.fileno())
            if fingerprint(target_stat(path)) != fingerprint(previous):
                raise ValueError(f"Config changed before replacement: {path}")
            os.replace(temporary, path)
        except BaseException:
            if temporary is not None:
                # Leave the session-created file for approved cleanup, never unlink it.
                sys.stderr.write(f"Serena config merge failed; temporary file retained: {temporary}\n")
            raise


    def main():
        path = Path(sys.argv[1])
        path.parent.mkdir(parents=True, exist_ok=True)
        with FileLock(str(path) + ".lock"):
            merge_config(path)


    if __name__ == "__main__":
        main()
  '';

  opencode-latex = pkgs-unstable.callPackage ./packages/opencode-latex {};
  opencode-mem = pkgs-unstable.callPackage ./packages/opencode-mem {};
  opencode-compaction = pkgs-unstable.callPackage ./packages/opencode-compaction {};
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

  imports = [./ai/caveman.nix ./ai/omniroute.nix ./ai/opencode-agents.nix];

  config = lib.mkIf config.my.hm.ai.enable {
    my.hm.git.excludes = [".opencode" ".serena/"];

    home.packages = with pkgs; [
      claude-code
    ];

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

        Prefer native grep (ripgrep-backed where available) and glob for broad text
        and file discovery. Use read for configuration, prose, and unsupported files.
        When Serena supports the project language, use its targeted symbolic tools
        for symbols, references, and symbol-level edits, not broad repository discovery.
        Read Serena's initial instructions and confirm the active project before
        using project tools. Scope Serena queries with relative_path to a known file
        or narrow directory. Serena never overrides role boundaries, edit approval
        requirements, or tool denials.

        Prefer native tools over shell searches; bounded rg shell searches are allowed
        when needed and permitted by the role. Never search filesystem roots or bypass
        a denied tool. Use the project's explicitly approved build/check route for
        compiler diagnostics. Empty LSP diagnostics do not prove compilation or a
        successful build; report the actual checks run and any unrun checks.
        Search memory before relying on past decisions; retry with alternative terms
        if needed. Verify recalled facts against current evidence. Keep stable rules
        in AGENTS.md rather than only in memory.
        All roles may read and write task-relevant memories using the memory tool or
        Serena, including read-only roles and verifiers. Prefer the memory tool over
        Serena memories. Prefer memory for working notes, findings, and handoffs
        instead of temporary files. Keep code, requested
        deliverables, and durable project rules in their proper files. Never store
        secrets in memory. This memory permission does not expand other role or task
        limits.

        The main agent owns user questions, the overall todo list, and plan approval.
        Before multi-step code changes, present a plan and wait for approval.
        Delegates execute only their approved bounded task, retain these safety rules,
        and return blockers to the main agent without restarting planning or delegating.
        Review and verify changes before claiming completion; report unrun checks.

        # Delegate by role

        Use explorer for code location and researcher for documentation or API facts.
        Use mechanical-editor for approved, precisely specified edits without shell.
        Use implementer for bounded implementation and architect for design decisions.
        Use verifier for approved, task-scoped test/lint/build commands, and reviewer
        for an independent correctness/security review. Before producer dispatch,
        main defines the implementation plan with concrete paths, steps, and
        acceptance conditions; never ask a producer to invent the overall plan.
        Every dispatch needs a compact contract: ROLE; approved SCOPE/PLAN;
        INPUTS/paths; DELIVERABLE; ALLOWED work; FORBIDDEN work; STOP condition;
        exact COMMANDS for a verifier, including any before/after status or diff
        commands. Main supplies missing details. Producers may make local coding
        choices within the plan; unresolved design returns to main. Specialists
        do not restart overall planning or delegate further.

        Keep production, review, and verification in separate child sessions. Do not
        resume a producer session as its reviewer or verifier. Implementer and
        mechanical-editor may do focused development sanity, not deep self-review
        or an independent acceptance pass; they return files, checks, and risks,
        then stop. Reviewers return independent semantic findings only: no
        implementation, patches, fixes, or check execution. Verifiers execute exactly
        main-supplied COMMANDS only and report evidence: no choosing/expanding checks,
        broad investigation/debugging, semantic review, or fixes. Main routes failures
        and findings to a producer for bounded fixes, then requests targeted rechecks.
        Explorer and researcher return evidence only; architect returns design only.
        Broad shell permissions do not expand role responsibilities. Verifiers make
        no deliberate source changes; check scripts may write files, so shell access
        is not a no-source-write sandbox.

        Launch named roles through the subagent tool's agent argument, without a
        model override. Native agents keep their configured model and permissions;
        model advice is advisory, not a reason to override a named role's model.
        Fast/medium/heavy are native role aliases, not a delegation plugin.
        Use balanced named roles by default. Choose implementer-deep, architect-deep,
        or reviewer-deep only with a stated task-specific reason: normal effort is
        insufficient or the task's complexity requires deeper effort. Never make
        deep roles the default or escalate automatically after an error. Escalation
        cannot bypass denials, approvals, or role boundaries. Resume the same session
        and role for genuine budget stops; do not substitute a deep role or override
        its model to evade a stop.
        No role instruction overrides global safety or approvals.
        Named role boundaries govern generic tier instructions to implement, review,
        or verify; do not perform another role's work to satisfy those instructions.
        Main owns completion and handoffs. Main must arrange separate verifier
        and reviewer checks before claiming completion. A passing test result
        never replaces independent review. Read-only roles use read/glob/grep;
        main supplies Git diffs and context. There are no plugin Git tools,
        read budgets, or automatic verification gates in this configuration.

        Every child must return a compact handoff regardless of verbosity:
        progress/files changed, verbatim denial messages and recovery instructions,
        checks run/unrun, and session ID if known (never invent one). Never label
        blockers completed. Main reads actual tool errors and budget notes.

        Follow returned recovery instructions. For a genuine budget stop, resume the
        SAME sessionID in the same role with bounded continuation, not a duplicate
        producer. Failed checks require a bounded fix and a targeted recheck;
        never blindly retry or switch providers merely to obtain a pass.
        A safety denial is an authority blocker: stop/report it and obtain proper
        authorization/configuration fixes, never switch tools/providers to bypass it.

        Core OmniRoute role combos provide explicit subscription-model fallback;
        cloudflare-free is manual-only and never a fallback. Combos do not change
        role permissions or replace independent review and verification.
        Authentication/configuration failures remain blockers. Quota displays and
        catalog labels are not proof of account billing or available capacity.

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
          "${opencode-compaction}"
        ];

        experimental = {
          todo = true;
        };

        providers = {
          openai.settings = {
            websearch_cited = {
              model = "gpt-5.5";
            };
          };
          google.settings = {
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

    xdg.configFile."opencode/cli.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/v2/cli.json";
      session.grouping = "none";
    };

    xdg.configFile."opencode/opencode-mem.jsonc".text = builtins.toJSON {
      # Keep background memory generation off the main session's OpenAI quota.
      opencodeProvider = "openai";
      opencodeModel = "gpt-6-luna";
      opencodeVariant = "low";
      autoCaptureEnabled = true;
      # This locally patched package is updated through Nix, not its updater.
      autoUpdate = false;
    };

    programs.antigravity-cli = {
      enable = true;
      package = antigravity-cli;
    };

    home.activation.serenaConfigMerge = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        ${pkgs.python3.withPackages (ps: [ps.ruamel-yaml ps.filelock])}/bin/python \
          ${serenaConfigMerge} ${lib.escapeShellArg "${config.home.homeDirectory}/.serena/serena_config.yml"}
      fi
    '';

    # Share the memory budget across Serena instances and their child language servers.
    systemd.user.slices.serena = {
      Unit.Description = "Shared memory budget for Serena MCP servers";
      Slice = {
        MemoryAccounting = true;
        MemoryMax = "8G";
        MemorySwapMax = 0;
      };
    };

    programs.mcp = {
      enable = true;
      servers = {
        serena = {
          env.CARGO_BUILD_JOBS = "2";
          command = "${pkgs.systemd}/bin/systemd-run";
          args = [
            "--user"
            "--scope"
            "--quiet"
            "--collect"
            "--slice=serena.slice"
            "--expand-environment=no"
            "--"
            "${serena}/bin/serena"
            "start-mcp-server"
            "--context"
            "ide"
            "--project-from-cwd"
            "--open-web-dashboard"
            "false"
          ];
        };
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

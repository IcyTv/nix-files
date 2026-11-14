{
  config,
  lib,
  ...
}: let
  agyTiers = {
    fast = {
      model = "google-agy/gemini-3.8-flash";
      readOnly = true;
      costRatio = 1;
      steps = 30;
    };
    medium = {
      model = "google-agy/claude-sonnet-5-5";
      costRatio = 5;
      steps = 50;
    };
    heavy = {
      model = "google-agy/claude-opus-5-5";
      costRatio = 20;
      steps = 120;
    };
  };
  # Match common direct, absolute-path, and command-wrapper spellings.
  # These checks are guardrails, not a shell sandbox or an exhaustive parser.
  commandPatterns = command: ["${command} *" "*/${command} *" "* ${command} *"];
  approvalCommands = [
    "sudo"
    "doas"
    "su"
    "git reset"
    "git restore"
    "git checkout"
    "git clean"
    "git push"
    "git branch -D"
    "git stash drop"
    "git stash clear"
    # Git accepts global flags before its subcommand, such as -C <directory>.
    "git * reset"
    "git * restore"
    "git * checkout"
    "git * clean"
    "git * push"
    "git * branch -D"
    "git * stash drop"
    "git * stash clear"
  ];
  approvalPatterns = lib.concatMap commandPatterns approvalCommands;
  gitTools = map (operation: "router_git_${operation}") ["status" "diff" "log" "show" "blame" "ls_files"];
  inspectionTools = ["glob" "grep" "skill"] ++ gitTools;
  denyShell = [
    {
      action = "shell";
      resource = "*";
      effect = "deny";
    }
  ];
  boundedTask = ''
    Execute only main's approved bounded task. Preserve unrelated work and all
    global safety rules. Do not restart overall planning, ask the user questions,
    or delegate. Return evidence, blockers, and unrun checks to main; stop at the
    stated acceptance condition. Never bypass a denied tool through another tool.
    This named role's scope governs generic tier instructions about implementation,
    review, or verification. Do not perform another role's work to satisfy those
    instructions. Global safety, approvals, and genuine router gates still apply;
    main owns completion and any router_verify calls for returned handles.
  '';
  reviewTask =
    boundedTask
    + ''
      Independently check correctness, security, regressions, and missing tests in
      the assigned changes and their relevant context. Do not rubber-stamp based
      on passing tests or another agent's summary. Findings only: do not implement,
      produce patches, fix findings, edit, run checks, or run shell.
      Report only actionable findings, one per line: path:line: severity: problem
      and suggested fix. If none, say no findings and state any review limits.
    '';
  verifierTask =
    boundedTask
    + ''
      Run only main-approved test, lint, or build commands scoped to this task.
      Report execution evidence only, not a semantic review or acceptance judgment.
      Do not independently analyze correctness or fix failures; main routes failures
      to an implementer and requests a narrow recheck of the affected scope.
      Inspect commands and relevant scripts before requesting approval. Request
      approval for the exact command, not a blanket runner prefix. Never install
      packages, run arbitrary interpreters/shell/eval, fix or format source, widen
      checks, write Git state, activate an environment, or deploy. Return failures
      to main without fixing them. Test/build scripts can modify files: this is not
      a sandbox. Make no deliberate source changes. Inspect Git status and diff
      before and after checks; report any resulting changes, commands, exit codes,
      and relevant output. Do not revert generated changes. Report unrun checks.
    '';
  # These prefixes only permit an approval request, never unattended execution.
  # The caller must approve the task scope and inspect the invoked project script.
  runnerPrefixes = [
    "npm test *"
    "npm run test *"
    "npm run lint *"
    "npm run build *"
    "pnpm test *"
    "pnpm run test *"
    "pnpm run lint *"
    "pnpm run build *"
    "cargo test *"
    "cargo check *"
    "cargo clippy *"
    "cargo build *"
    "go test *"
    "go build *"
    "pytest *"
    "ruff check *"
    "eslint *"
    "tsc --noEmit *"
    "alejandra --check *"
    "nix eval --offline --no-write-lock-file *"
    "nix build --offline --no-write-lock-file *"
  ];
  # Shell matching does not treat the space before '*' as optional.
  runnerCommands =
    lib.concatMap (pattern: [
      (lib.removeSuffix " *" pattern)
      pattern
    ])
    runnerPrefixes;
  runnerDeniedFlags = ["* --fix*" "* --write*" "* --outputFile*" "* --eval*" "* --command*" "* -c *"];
  nativeReadPermissions =
    [
      {
        action = "*";
        resource = "*";
        effect = "deny";
      }
    ]
    ++ map (action: {
      inherit action;
      resource = "*";
      effect = "allow";
    }) (["read"] ++ inspectionTools)
    ++ [
      {
        action = "external_directory";
        resource = "*";
        effect = "ask";
      }
      {
        action = "read";
        resource = "*.env";
        effect = "ask";
      }
      {
        action = "read";
        resource = "*.env.*";
        effect = "ask";
      }
      {
        action = "read";
        resource = "*.env.example";
        effect = "allow";
      }
    ];
  runnerPermissions =
    map (resource: {
      action = "shell";
      inherit resource;
      effect = "ask";
    })
    runnerCommands
    ++ map (resource: {
      action = "shell";
      inherit resource;
      effect = "deny";
    })
    runnerDeniedFlags;
in {
  config = lib.mkIf config.my.hm.ai.enable {
    programs.opencode.settings = {
      plugins = ["opencode-model-router@2.9.1"];

      # The router's read-only fast tier denies tools by default. Grant only
      # lazy skill loading; keep shell, edits, Code Mode, and delegation denied.
      agents.fast.permissions = [
        # Host config rules are appended after the router's read-only policy.
        # Do not let shared shell approval rules widen fast to shell access.
        {
          action = "shell";
          resource = "*";
          effect = "deny";
        }
        {
          action = "skill";
          resource = "*";
          effect = "allow";
        }
      ];

      # Global approval rules load after plugin transforms. Reassert each role's
      # shell boundary last so a global Git/sudo ask cannot widen that role.
      agents.explorer.permissions = denyShell;
      agents.researcher.permissions = denyShell;
      agents.reviewer-backup.permissions = denyShell;
      agents.architect.permissions = denyShell;
      agents.verifier.permissions = denyShell ++ runnerPermissions;

      # V2 uses system and provider/model#variant, not legacy prompt/variant.
      # Keep these IDs out of router agents/subagentTiers so tier pinning cannot
      # replace their fixed models. Native config loads after router transforms.
      agents.mechanical-editor = {
        model = "openai/gpt-6-luna#high";
        mode = "subagent";
        description = "Precisely specified, approved mechanical edits; no shell";
        system =
          boundedTask
          + ''
            Apply only the precisely specified edits in the approved paths. Do not
            infer a broader refactor or run shell. If the edit needs design choices
            or execution, return the blocker to main. Check only that the requested
            edits landed; do not conduct deep self-review or an independent acceptance
            pass. Return changed files, checks, and risks, then stop. Main arranges
            separate reviewer and verifier child sessions.
          '';
        steps = 30;
        permissions =
          nativeReadPermissions
          ++ [
            {
              action = "edit";
              resource = "*";
              effect = "ask";
            }
          ];
      };
      agents.verifier-backup = {
        model = "openai/gpt-6-luna#high";
        mode = "subagent";
        description = "Scoped approved check runner after confirmed shared Google quota exhaustion";
        system = verifierTask;
        steps = 30;
        permissions = nativeReadPermissions ++ runnerPermissions;
      };
      agents.reviewer = {
        model = "google-agy/gemini-4-argon#high";
        mode = "subagent";
        description = "Independent correctness/security review; no shell or edits";
        system = reviewTask;
        steps = 40;
        permissions = nativeReadPermissions;
      };

      # Policy denies survive agent-level permission overrides and approvals.
      policies = map (pattern: {
        action = "tool.use";
        resource = "shell:${pattern}";
        effect = "deny";
      }) (commandPatterns "rm");

      permissions =
        map (pattern: {
          action = "shell";
          resource = pattern;
          effect = "ask";
        })
        approvalPatterns;
    };

    # Upstream currently hardcodes ~/.config rather than XDG_CONFIG_HOME.
    home.file.".config/opencode/opencode-model-router.overrides.jsonc".text = builtins.toJSON {
      activePreset = "hybrid-agy-openai";
      activeMode = "normal";
      delegateInstructions = "keep";
      rules = [
        "Use subagent(agent=<role>) without a model override: explorer for code location; researcher for docs; mechanical-editor for precise edits; implementer for implementation; architect for design; verifier for approved scoped checks; reviewer for independent correctness/security review."
        "Main owns scope, questions, plan approval, completion and handoffs. Specialists execute only their named role, without replanning or delegation. Role scope takes precedence over generic tier instructions to implement/review/verify, never over safety, approvals or genuine router gates. Main uses router_verify only for returned unverified handles."
        "Canonical fast/medium/heavy remain available. Tier/model cost guidance is advisory for native roles; do not re-pin fixed native agents or backups to a tier model. Native edits need separate verifier and reviewer checks; native dispatch alone does not supply the router gate."
        "Producers (implementer/mechanical-editor) may perform focused development sanity only, not deep self-review or independent acceptance. Return files/checks/risks, then stop. Launch reviewer and verifier as separate child sessions, not continuations of the producer. Reviewers return findings only, never implementation/patches/fixes. Verifiers run approved checks and report evidence only, never semantic review/fixes. Main routes failures/findings to an implementer and narrowly rechecks affected scope."
        "Role fallback is agent-managed only: on confirmed Google quota exhaustion, Flash AND Argon share the exhausted pool for this task. Announce switches to verifier-backup and reviewer-backup; do not repeatedly probe either Google model. No explorer/researcher backup. Auth/config failures are blockers; test failures/review findings are NOT fallback triggers. Never claim automatic runtime failover."
        "Explicit role backups take precedence over generic provider fallback advice after confirmed Google exhaustion. Existing provider/preset fallback settings continue to govern ordinary tier dispatches."
      ];
      agents = {
        explorer = {
          tier = "fast";
          description = "Locate code and explain relevant paths; no shell or edits";
          prompt =
            boundedTask
            + ''
              Find only the code needed for the assigned question. Return concise
              path:line evidence and useful symbols; do not edit or run shell.
            '';
          readOnly = true;
          allowTools = ["skill"];
        };
        researcher = {
          tier = "fast";
          description = "Research documentation and API facts; no shell or edits";
          prompt =
            boundedTask
            + ''
              Use current authoritative documentation and read-only sources for the
              assigned facts. Cite URLs or path:line evidence and distinguish facts
              from uncertainty. Do not edit or run shell.
            '';
          readOnly = true;
          allowTools = ["skill" "webfetch" "websearch" "mcp-nixos_nix" "mcp-nixos_nix_versions"];
        };
        implementer = {
          tier = "medium";
          description = "Bounded implementation with existing safety approvals";
          prompt =
            boundedTask
            + ''
              Make the smallest coherent implementation matching repository patterns.
              Never suppress type errors. Focused development sanity checks are
              allowed, never a full suite unless approved. Do not conduct deep
              self-review or an independent acceptance pass. Stop after two consecutive
              failures on the same issue. Return files, checks, decisions, and risks,
              then stop; main arranges separate reviewer and verifier child sessions.
            '';
          readOnly = false;
          # Plugin policies drop inherited asks. Restate existing implementation
          # approvals explicitly; global hard-deny policies still apply.
          permission = {
            "*" = "allow";
            shell = {"*" = "allow";} // lib.genAttrs approvalPatterns (_: "ask");
            execute = "deny";
            subagent = "deny";
            delegate = "deny";
            question = "deny";
          };
        };
        verifier = {
          tier = "fast";
          description = "Run only approved task-scoped tests/lint/build; no deliberate source changes";
          prompt = verifierTask;
          steps = 30;
          # Explicit policies are independent of the fast tier's read-only flag.
          # A readOnly=true agent cannot request shell, even with allowTools.
          readOnly = false;
          allowTools = inspectionTools;
          permission = {
            read = "allow";
            external_directory = "ask";
            shell = {
              ask = runnerCommands;
              deny = runnerDeniedFlags;
            };
          };
        };
        reviewer-backup = {
          tier = "medium";
          description = "Independent review after confirmed shared Google quota exhaustion; no shell or edits";
          prompt = reviewTask;
          steps = 40;
          readOnly = true;
          allowTools = ["skill"];
        };
        architect = {
          tier = "heavy";
          description = "Design decisions and tradeoffs; no shell or edits";
          prompt =
            boundedTask
            + ''
              Analyze the assigned design decision using repository evidence. Return
              a concise recommendation, alternatives, risks, and unresolved choices.
              Do not implement, run shell, or expand the approved task.
            '';
          readOnly = true;
          allowTools = ["skill"];
        };
      };
      presets = {
        hybrid-agy-openai = {
          inherit (agyTiers) fast;
          medium = {
            model = "openai/gpt-6.1-sol";
            variant = "xhigh";
            costRatio = 5;
            steps = 50;
          };
          heavy = {
            model = "openai/gpt-6-astra";
            variant = "max";
            costRatio = 20;
            steps = 120;
          };
        };
        google-agy = agyTiers;
      };
      # Chains contain preset names, not provider IDs. Do not fall through to
      # upstream providers or the OpenCode catalog (which also has paid models).
      # This controls routing instructions, not provider access permissions.
      fallback.presets = {
        hybrid-agy-openai = {
          openai = ["google-agy"];
          google-agy = [];
        };
        google-agy.google-agy = [];
      };
    };
  };
}

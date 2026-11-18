{
  config,
  lib,
  ...
}: let
  rule = action: resource: effect: {inherit action resource effect;};
  # Best-effort scanner guardrails, not a shell sandbox.
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
    "git * reset"
    "git * restore"
    "git * checkout"
    "git * clean"
    "git * push"
    "git * branch -D"
    "git * stash drop"
    "git * stash clear"
  ];
  shellAsks = map (pattern: rule "shell" pattern "ask") (lib.concatMap commandPatterns approvalCommands);
  environmentAsks = [
    (rule "external_directory" "*" "allow")
    (rule "read" "*.env" "ask")
    (rule "read" "*.env.*" "ask")
    (rule "read" "*.env.example" "allow")
  ];
  inspection = ["read" "glob" "grep" "skill" "serena_initial_instructions" "serena_serena_repl"];
  allow = actions: map (action: rule action "*" "allow") actions;
  readPermissions = [(rule "*" "*" "deny")] ++ allow (inspection ++ ["context_compact"]) ++ environmentAsks;
  # Fixed role permissions apply to every model in the combo, never to a model tier.
  editPermissions = readPermissions ++ allow ["edit"];
  executionPermissions =
    editPermissions
    ++ allow [
      "shell"
      "webfetch"
      "websearch"
      "mcp-nixos_*"
      "mcp_nixos_*"
      "crates-mcp_*"
      "crates_mcp_*"
      "rust-docs_*"
      "rust_docs_*"
    ]
    ++ shellAsks;
  boundedTask = ''
    Execute only main's approved bounded task. Preserve unrelated work and all
    global safety rules. Do not restart planning, ask the user questions, or
    delegate. Never bypass a denied tool through another tool. Named role scope
    governs generic model advice, never safety or approvals. Return progress,
    files changed, checks run/unrun, risks, and session ID if known; never invent
    one. Preserve denial messages and recovery instructions verbatim. Stop at
    the stated acceptance condition. Main owns completion and separate checks.
    Read-only roles have no shell or Git tools; main supplies diffs and context.
    Before using Serena, read initial_instructions and confirm the active project
    path matches the assigned directory. Use Serena only within your existing role
    and approved task scope. Never bypass denied tools through Serena or Python.
  '';
  producerTask =
    boundedTask
    + ''
      Make the smallest coherent implementation matching repository patterns.
      Make local choices within main's plan only; return missing details or design
      decisions to main. Never suppress type errors. Focused development sanity
      checks are allowed, not a full suite unless approved. Do not conduct deep
      self-review or an independent acceptance pass. Stop after two consecutive
      failures on the same issue. Return files, checks, decisions, and risks,
      then stop; main arranges separate reviewer and verifier child sessions.
    '';
  reviewTask =
    boundedTask
    + ''
      Independently check correctness, security, regressions, and missing tests.
      Do not rubber-stamp passing tests or another agent's summary. Findings only:
      do not implement, patch, fix, edit, run checks, or run shell. Report actionable
      findings as path:line: severity: problem and suggested fix. If none, say no
      findings and state review limits. Request missing diff context from main.
    '';
  verifierTask =
    boundedTask
    + ''
      Execute exactly main-supplied COMMANDS in the supplied directory and scope.
      Do not choose, rewrite, or expand checks. If commands or inputs are missing,
      return the blocker. Evidence only: no semantic review, acceptance judgment,
      broad debugging, or fixes. Never install packages, format source, write Git
      state, activate, or deploy. Make no deliberate source changes. Scripts can
      write files; shell access is not a no-source-write sandbox. Main supplies
      before/after status or diff commands. Report commands, exit codes, output,
      resulting changes, and unrun checks. Do not revert generated changes.
    '';
  agent = combo: description: system: steps: permissions: {
    model = "omniroute/${combo}";
    mode = "subagent";
    inherit description system steps permissions;
  };
  orchestrator = {
    model = "omniroute/orchestrator";
    mode = "primary";
    description = "Main agent for questions, approval, delegation, and approved work";
    system = ''
      You are the main agent, not a bounded-task subagent. Own user questions,
      the overall plan and todo list, approval, delegation, and final handoffs.
      Preserve unrelated work and all global safety rules. Obtain approval before
      multi-step code changes, destructive actions, or scope expansion. You may
      inspect, edit, and run checks within approved work using normal primary tools.
      Dispatch named roles with bounded contracts and no model override. Keep
      production, independent review, and verification in separate child sessions;
      arrange separate reviewer and verifier checks before claiming completion.
      Report blockers and unrun checks. Never bypass denials or role boundaries.
    '';
    # Keep inherited primary tools; no subagent-style broad deny. Repeat explicit
    # safeguards for defense in depth even if permission merge behavior changes.
    permissions = allow ["subagent" "execute" "question" "todowrite" "context_compact"] ++ shellAsks ++ environmentAsks;
  };
  explorer =
    agent "exploration" "Locate code; no shell or edits"
    (boundedTask + "Find only assigned code. Return concise path:line evidence and useful symbols.")
    30
    readPermissions;
  researcher =
    agent "research" "Authoritative documentation and API facts; no shell or edits"
    (boundedTask + "Use current primary sources. Cite URLs or path:line evidence; distinguish uncertainty.")
    30 (readPermissions
      ++ allow [
        "webfetch"
        "websearch"
        "opencode_list_mcp_resources"
        "opencode_read_mcp_resource"
        "mcp-nixos_*"
        "mcp_nixos_*"
        "crates-mcp_*"
        "crates_mcp_*"
        "rust-docs_*"
        "rust_docs_*"
      ]);
  implementer = agent "implementation" "Approved bounded implementation" producerTask 50 executionPermissions;
  architect =
    agent "architecture" "Design decisions and tradeoffs; no shell or edits"
    (boundedTask + "Return design only: recommendation, alternatives, risks, and unresolved choices. Do not implement.")
    60
    readPermissions;
  reviewer = agent "review" "Independent correctness/security review; no shell or edits" reviewTask 40 readPermissions;
  verifier =
    agent "verification" "Run exactly approved scoped checks; no deliberate source changes"
    verifierTask
    30 (readPermissions ++ allow ["shell"] ++ shellAsks);
in {
  config = lib.mkIf config.my.hm.ai.enable {
    programs.opencode.settings = {
      default_agent = "orchestrator";
      model = "omniroute/orchestrator";
      agents = {
        inherit orchestrator explorer researcher implementer architect reviewer verifier;
        implementer-deep =
          implementer
          // {
            model = "omniroute/implementation-deep";
            description = "Approved bounded implementation requiring deeper effort";
          };
        architect-deep =
          architect
          // {
            model = "omniroute/architecture-deep";
            description = "Complex design decisions and tradeoffs; no shell or edits";
          };
        reviewer-deep =
          reviewer
          // {
            model = "omniroute/review-deep";
            description = "Complex independent correctness/security review; no shell or edits";
          };
        mechanical-editor =
          agent "mechanical" "Precisely specified approved edits; no shell"
          (boundedTask
            + ''
              Apply only precisely specified edits in approved paths. Do not infer a
              broader refactor or run shell. Return design/execution needs to main.
              Check only that requested edits landed; no deep self-review or acceptance
              pass. Main arranges separate reviewer and verifier child sessions.
            '')
          30
          editPermissions;
        # Compatibility names, not a claim about shared provider quota pools.
        reviewer-backup = reviewer;
        verifier-backup = verifier;
        fast = explorer;
        medium = implementer;
        heavy = architect;
        build.model = "omniroute/implementation";
        execution = {
          model = "omniroute/implementation";
          mode = "primary";
          description = "Main execution agent using the implementation combo";
        };
      };
      policies = map (pattern: rule "tool.use" "shell:${pattern}" "deny") (commandPatterns "rm");
      permissions = shellAsks ++ environmentAsks;
    };
  };
}

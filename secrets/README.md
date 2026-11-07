# Secrets

## Credentials: age / agenix

Keep the private identity outside this flake at `~/.keys/age-master.key`
(`0600`, with `~/.keys` set to `0700`). Back it up securely. Home Manager
decrypts the committed `.age` files during activation, not during builds.
The identity must already be present on a newly installed machine.

To add a credential, first put its plaintext in a private file outside the
repository. From the flake root, encrypt it without putting the value in shell
history or command-line arguments:

```sh
nix-shell -p age --run 'age -r age1uk3pt523xsgzkumlf23psgsf4k5w457g4k9vqgznk0hhx9v0dass3l8wnc -o secrets/example.age ~/.keys/example'
```

Add the recipient to `secrets.nix` and declare the file using Home Manager's
`age.secrets`. Applications must read `config.age.secrets.<name>.path` at
runtime. Never use `builtins.readFile` on credentials or put their values in
Nix strings, session variables, or generated configuration.

The pay-respects wrapper reads its runtime secret into `_PR_AI_API_KEY` for
that process only and explicitly uses OpenAI's endpoint. It defaults to
`gpt-4o-mini`; `_PR_AI_MODEL` can override the model. `_PR_AI_DISABLE` still
disables AI. Missing/empty credentials disable AI rather than selecting a
built-in provider. Commands and error output may be sent to OpenAI.

The original plaintext API-key file was preserved privately at
`~/.keys/pay-respects-api-key`; it is not needed after encryption unless you
want a backup or need to re-encrypt it.

## Bookmarks: git-crypt

Only `bookmarks-default.json` and `bookmarks-yes.json` use git-crypt. Unlock
an existing clone with your separately backed-up git-crypt key:

```sh
git-crypt unlock ~/.keys/git-crypt
git-crypt status
```

Git automatically encrypts these two files when staging them. No separate
encrypt command is needed. For new credentials, use age instead: git-crypt
protects Git blobs, but unlocked files copied into the Nix store are plaintext.
`git-crypt status` labels `.age` files "not encrypted" because git-crypt does
not manage them; their contents are already encrypted by age.
Firefox bookmarks intentionally remain readable in generated configuration.

Plaintext files under `secrets/` are ignored, and `scripts/check-secrets.sh`
rejects unexpected files (including ignored ones) before rebuild stages
anything. This is a focused guard, not a repository-wide secret scanner.

## Existing store copies

Moving the identity outside the flake prevents new source snapshots from
including it. It does not remove copies already in the Nix store or change
Git history. Existing store cleanup and credential rotation are separate,
manual decisions.

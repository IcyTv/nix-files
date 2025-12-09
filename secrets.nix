let
  masterKey = "age1uk3pt523xsgzkumlf23psgsf4k5w457g4k9vqgznk0hhx9v0dass3l8wnc";
in {
  "secrets/id_ed25519.age".publicKeys = [masterKey];
  "secrets/github-token.age".publicKeys = [masterKey];
}

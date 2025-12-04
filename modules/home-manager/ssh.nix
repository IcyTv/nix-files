{lib, ...}: {
  programs.sshAgent = true;

  age.identityPaths = ["${home.homeDirectory}/.dotfiles/nix/secrets/master.key"];

  age.secrets.mainKey = {
    file = ../../secrets/id_ed25519.age;
    path = "${home.homeDirectory}/.ssh/id_ed25519";
    mode = "600";
  };
}

{pkgs, ...}: {
  console = {
    packages = [pkgs.terminus_font];
    font = "ter-v16n";
  };
}

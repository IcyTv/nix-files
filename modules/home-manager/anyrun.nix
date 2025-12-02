{pkgs, ...}: {
  programs.anyrun = {
    enable = true;
    config = {
      closeOnClick = true;
      maxEntries = 12;
      ignoreExclusiveZones = false;
      showResultsImmediately = true;

      plugins = [
        "${pkgs.anyrun}/lib/libapplications.so"
        "${pkgs.anyrun}/lib/libsymbols.so"
        "${pkgs.anyrun}/lib/libniri_focus.so"
        "${pkgs.anyrun}/lib/libnix_run.so"
        "${pkgs.anyrun}/lib/libshell.so"
        "${pkgs.anyrun}/lib/librink.so"
        "${pkgs.anyrun}/lib/libtranslate.so"
        "${pkgs.anyrun}/lib/libwebsearch.so"
      ];
    };
  };
}

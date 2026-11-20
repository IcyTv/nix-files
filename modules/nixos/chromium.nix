{
  config,
  lib,
  ...
}: {
  options.my.nixos.chromium.enable =
    lib.mkEnableOption "shared Chromium browser policies"
    // {default = true;};

  config = lib.mkIf config.my.nixos.chromium.enable {
    # These policies are shared by Chromium, Helium, and other supported browsers.
    programs.chromium = {
      enable = true;
      extraOpts = {
        MetricsReportingEnabled = false;
        PasswordManagerEnabled = false;
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;
        BookmarksBarEnabled = true;
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderName = "Startpage";
        DefaultSearchProviderKeyword = "startpage.com";
        DefaultSearchProviderSearchURL = "https://www.startpage.com/sp/search?query={searchTerms}";
        SearchSuggestEnabled = false;
      };
    };
  };
}

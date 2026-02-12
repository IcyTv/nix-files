{pkgs, ...}: {
  # programs.vesktop = {
  #   enable = true;
  #   settings = {
  #     discordBranch = "stable";
  #     tray = true;
  #     minimizeToTray = false;
  #     appBadge = true;
  #     arRPC = true;
  #     hardwareAcceleration = true;
  #     disableMinSize = true;
  #   };
  #   vencord.settings = {
  #     checkUpdates = false;
  #     autoUpdate = false;
  #     autoUpdateNotification = false;
  #     notifyAboutUpdates = false;
  #     customTitleBar = false;
  #     tray = true;
  #     plugins = {
  #       AnonymiseFileNames.enabled = true;
  #       BetterFolders.enabled = true;
  #       MessageLogger.enabled = true;
  #       FakeNitro.enabled = true;
  #       BetterSessions.enabled = true;
  #       BetterSettings.enabled = true;
  #       CallTimer.enabled = true;
  #       ClearURLs.enabled = true;
  #       CustomRPC.enabled = true;
  #       CustomIdle.enabled = true;
  #       DisableCallIdle.enabled = true;
  #       FavoriteEmojiFirst.enabled = true;
  #       FixImagesQuality.enabled = true;
  #       FixYoutubeEmbeds.enabled = true;
  #       GameActivityToggle.enabled = true;
  #       ImageZoom.enabled = true;
  #       LastFMRichPresence.enabled = true;
  #       ReadAllNotificationsButton.enabled = true;
  #       YoutubeAdblock.enabled = true;
  #       VolumeBooster.enabled = true;
  #       Unindent.enabled = true;
  #     };
  #   };
  # };

  programs.nixcord = {
    enable = true;

    discord.vencord.enable = false;
    discord.equicord.enable = true;

    config = {
      frameless = true;
      autoUpdate = false;
      autoUpdateNotification = false;
      notifyAboutUpdates = false;

      disableMinSize = true;

      plugins = {
        anonymiseFileNames.enable = true;
        betterFolders.enable = true;
        messageLogger.enable = true;
        fakeNitro.enable = true;
        betterSessions.enable = true;
        betterSettings.enable = true;
        callTimer.enable = true;
        ClearURLs.enable = true;
        CustomRPC.enable = true;
        customIdle.enable = true;
        disableCallIdle.enable = true;
        favoriteEmojiFirst.enable = true;
        fixImagesQuality.enable = true;
        fixYoutubeEmbeds.enable = true;
        gameActivityToggle.enable = true;
        imageZoom.enable = true;
        readAllNotificationsButton.enable = true;
        youtubeAdblock.enable = true;
        volumeBooster.enable = true;
        unindent.enable = true;
      };
    };
  };

  xdg.configFile."autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
}

{pkgs, ...}: {
  programs.vesktop = {
    enable = true;
    vencord.settings = {
      appBadge = true;
      arRPC = true;
      checkUpdates = false;
      autoUpdate = false;
      autoUpdateNotification = false;
      notifyAboutUpdates = false;
      customTitleBar = false;
      tray = true;
      hardwareAcceleration = true;
      discordBranch = "stable";
      vesktop.settings = {
        autoUpdate = false;
        autoUpdateNotification = false;
        notifyAboutUpdates = false;
        disableMinSize = true;
        plugins = {
          AnonymiseFileNames.enabled = true;
          BetterFolders.enabled = true;
          MessageLogger.enabled = true;
          FakeNitro.enabled = true;
          BetterSessions.enabled = true;
          BetterSettings.enabled = true;
          CallTimer.enabled = true;
          ClearURLs.enabled = true;
          CustomRPC.enabled = true;
          CustomIdle.enabled = true;
          DisableCallIdle.enabled = true;
          FavoriteEmojiFirst.enabled = true;
          FixImagesQuality.enabled = true;
          FixYoutubeEmbeds.enabled = true;
          GameActivityToggle.enabled = true;
          ImageZoom.enabled = true;
          LastFMRichPresence.enabled = true;
          ReadAllNotificationsButton.enabled = true;
          YoutubeAdblock.enabled = true;
          VolumeBooster.enabled = true;
          Unindent.enabled = true;
        };
      };
    };
  };

  xdg.configFile."autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
}

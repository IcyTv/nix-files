{pkgs, ...}: {
  programs.nixcord = {
    enable = true;

    discord = {
      enable = true;
      autoscroll.enable = true;
      branch = "stable";

      vencord.enable = false;
      equicord.enable = true;
    };

    config = {
      frameless = true;
      autoUpdate = false;
      autoUpdateNotification = false;
      notifyAboutUpdates = false;

      disableMinSize = true;

      plugins = {
        anonymiseFileNames.enable = true;
        betterFolders.enable = true;
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
        followVoiceUser.enable = true;
        forceOwnerCrown.enable = true;
        gameActivityToggle.enable = true;
        ghosted.enable = true;
        homeTyping.enable = true;
        imageZoom.enable = true;
        implicitRelationships.enable = true;
        mediaPlaybackSpeed.enable = true;
        memberCount.enable = true;
        mentionAvatars.enable = true;
        messageLoggerEnhanced.enable = true;
        noF1.enable = true;
        noNitroUpsell.enable = true;
        petpet.enable = true;
        readAllNotificationsButton.enable = true;
        youtubeAdblock.enable = true;
        volumeBooster.enable = true;
        unindent.enable = true;
      };
    };
  };

  xdg.configFile."autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
}

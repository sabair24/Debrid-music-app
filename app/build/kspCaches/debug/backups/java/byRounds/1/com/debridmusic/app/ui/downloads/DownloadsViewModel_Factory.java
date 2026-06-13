package com.debridmusic.app.ui.downloads;

import com.debridmusic.app.download.OfflineDownloadManager;
import com.debridmusic.app.player.PlayerController;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
@QualifierMetadata
@DaggerGenerated
@Generated(
    value = "dagger.internal.codegen.ComponentProcessor",
    comments = "https://dagger.dev"
)
@SuppressWarnings({
    "unchecked",
    "rawtypes",
    "KotlinInternal",
    "KotlinInternalInJava",
    "cast"
})
public final class DownloadsViewModel_Factory implements Factory<DownloadsViewModel> {
  private final Provider<OfflineDownloadManager> downloadManagerProvider;

  private final Provider<PlayerController> playerControllerProvider;

  public DownloadsViewModel_Factory(Provider<OfflineDownloadManager> downloadManagerProvider,
      Provider<PlayerController> playerControllerProvider) {
    this.downloadManagerProvider = downloadManagerProvider;
    this.playerControllerProvider = playerControllerProvider;
  }

  @Override
  public DownloadsViewModel get() {
    return newInstance(downloadManagerProvider.get(), playerControllerProvider.get());
  }

  public static DownloadsViewModel_Factory create(
      Provider<OfflineDownloadManager> downloadManagerProvider,
      Provider<PlayerController> playerControllerProvider) {
    return new DownloadsViewModel_Factory(downloadManagerProvider, playerControllerProvider);
  }

  public static DownloadsViewModel newInstance(OfflineDownloadManager downloadManager,
      PlayerController playerController) {
    return new DownloadsViewModel(downloadManager, playerController);
  }
}

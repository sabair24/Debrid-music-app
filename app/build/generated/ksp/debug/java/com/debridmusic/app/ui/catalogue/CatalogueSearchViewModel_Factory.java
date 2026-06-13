package com.debridmusic.app.ui.catalogue;

import com.debridmusic.app.download.OfflineDownloadManager;
import com.debridmusic.app.player.PlayerController;
import com.debridmusic.app.torbox.TorBoxRepository;
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
public final class CatalogueSearchViewModel_Factory implements Factory<CatalogueSearchViewModel> {
  private final Provider<TorBoxRepository> torBoxRepositoryProvider;

  private final Provider<PlayerController> playerControllerProvider;

  private final Provider<OfflineDownloadManager> offlineDownloadManagerProvider;

  public CatalogueSearchViewModel_Factory(Provider<TorBoxRepository> torBoxRepositoryProvider,
      Provider<PlayerController> playerControllerProvider,
      Provider<OfflineDownloadManager> offlineDownloadManagerProvider) {
    this.torBoxRepositoryProvider = torBoxRepositoryProvider;
    this.playerControllerProvider = playerControllerProvider;
    this.offlineDownloadManagerProvider = offlineDownloadManagerProvider;
  }

  @Override
  public CatalogueSearchViewModel get() {
    return newInstance(torBoxRepositoryProvider.get(), playerControllerProvider.get(), offlineDownloadManagerProvider.get());
  }

  public static CatalogueSearchViewModel_Factory create(
      Provider<TorBoxRepository> torBoxRepositoryProvider,
      Provider<PlayerController> playerControllerProvider,
      Provider<OfflineDownloadManager> offlineDownloadManagerProvider) {
    return new CatalogueSearchViewModel_Factory(torBoxRepositoryProvider, playerControllerProvider, offlineDownloadManagerProvider);
  }

  public static CatalogueSearchViewModel newInstance(TorBoxRepository torBoxRepository,
      PlayerController playerController, OfflineDownloadManager offlineDownloadManager) {
    return new CatalogueSearchViewModel(torBoxRepository, playerController, offlineDownloadManager);
  }
}

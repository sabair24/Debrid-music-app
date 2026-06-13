package com.debridmusic.app.ui.settings;

import com.debridmusic.app.data.local.SettingsStore;
import com.debridmusic.app.metadata.MetadataEnricher;
import com.debridmusic.app.player.EqController;
import com.debridmusic.app.player.ScrobbleManager;
import com.debridmusic.app.soulseek.SoulseekRepository;
import com.debridmusic.app.torbox.TorBoxAuthInterceptor;
import com.debridmusic.app.torbox.TorBoxRepository;
import com.debridmusic.app.update.UpdateRepository;
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
public final class SettingsViewModel_Factory implements Factory<SettingsViewModel> {
  private final Provider<SettingsStore> settingsStoreProvider;

  private final Provider<MetadataEnricher> metadataEnricherProvider;

  private final Provider<TorBoxRepository> torBoxRepositoryProvider;

  private final Provider<TorBoxAuthInterceptor> torBoxAuthInterceptorProvider;

  private final Provider<SoulseekRepository> soulseekRepositoryProvider;

  private final Provider<UpdateRepository> updateRepositoryProvider;

  private final Provider<EqController> eqControllerProvider;

  private final Provider<ScrobbleManager> scrobbleManagerProvider;

  public SettingsViewModel_Factory(Provider<SettingsStore> settingsStoreProvider,
      Provider<MetadataEnricher> metadataEnricherProvider,
      Provider<TorBoxRepository> torBoxRepositoryProvider,
      Provider<TorBoxAuthInterceptor> torBoxAuthInterceptorProvider,
      Provider<SoulseekRepository> soulseekRepositoryProvider,
      Provider<UpdateRepository> updateRepositoryProvider,
      Provider<EqController> eqControllerProvider,
      Provider<ScrobbleManager> scrobbleManagerProvider) {
    this.settingsStoreProvider = settingsStoreProvider;
    this.metadataEnricherProvider = metadataEnricherProvider;
    this.torBoxRepositoryProvider = torBoxRepositoryProvider;
    this.torBoxAuthInterceptorProvider = torBoxAuthInterceptorProvider;
    this.soulseekRepositoryProvider = soulseekRepositoryProvider;
    this.updateRepositoryProvider = updateRepositoryProvider;
    this.eqControllerProvider = eqControllerProvider;
    this.scrobbleManagerProvider = scrobbleManagerProvider;
  }

  @Override
  public SettingsViewModel get() {
    return newInstance(settingsStoreProvider.get(), metadataEnricherProvider.get(), torBoxRepositoryProvider.get(), torBoxAuthInterceptorProvider.get(), soulseekRepositoryProvider.get(), updateRepositoryProvider.get(), eqControllerProvider.get(), scrobbleManagerProvider.get());
  }

  public static SettingsViewModel_Factory create(Provider<SettingsStore> settingsStoreProvider,
      Provider<MetadataEnricher> metadataEnricherProvider,
      Provider<TorBoxRepository> torBoxRepositoryProvider,
      Provider<TorBoxAuthInterceptor> torBoxAuthInterceptorProvider,
      Provider<SoulseekRepository> soulseekRepositoryProvider,
      Provider<UpdateRepository> updateRepositoryProvider,
      Provider<EqController> eqControllerProvider,
      Provider<ScrobbleManager> scrobbleManagerProvider) {
    return new SettingsViewModel_Factory(settingsStoreProvider, metadataEnricherProvider, torBoxRepositoryProvider, torBoxAuthInterceptorProvider, soulseekRepositoryProvider, updateRepositoryProvider, eqControllerProvider, scrobbleManagerProvider);
  }

  public static SettingsViewModel newInstance(SettingsStore settingsStore,
      MetadataEnricher metadataEnricher, TorBoxRepository torBoxRepository,
      TorBoxAuthInterceptor torBoxAuthInterceptor, SoulseekRepository soulseekRepository,
      UpdateRepository updateRepository, EqController eqController,
      ScrobbleManager scrobbleManager) {
    return new SettingsViewModel(settingsStore, metadataEnricher, torBoxRepository, torBoxAuthInterceptor, soulseekRepository, updateRepository, eqController, scrobbleManager);
  }
}

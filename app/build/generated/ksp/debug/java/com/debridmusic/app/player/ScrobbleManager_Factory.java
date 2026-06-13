package com.debridmusic.app.player;

import com.debridmusic.app.data.local.SettingsStore;
import com.debridmusic.app.data.remote.api.LastFmScrobbleApi;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
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
public final class ScrobbleManager_Factory implements Factory<ScrobbleManager> {
  private final Provider<SettingsStore> settingsStoreProvider;

  private final Provider<LastFmScrobbleApi> scrobbleApiProvider;

  public ScrobbleManager_Factory(Provider<SettingsStore> settingsStoreProvider,
      Provider<LastFmScrobbleApi> scrobbleApiProvider) {
    this.settingsStoreProvider = settingsStoreProvider;
    this.scrobbleApiProvider = scrobbleApiProvider;
  }

  @Override
  public ScrobbleManager get() {
    return newInstance(settingsStoreProvider.get(), scrobbleApiProvider.get());
  }

  public static ScrobbleManager_Factory create(Provider<SettingsStore> settingsStoreProvider,
      Provider<LastFmScrobbleApi> scrobbleApiProvider) {
    return new ScrobbleManager_Factory(settingsStoreProvider, scrobbleApiProvider);
  }

  public static ScrobbleManager newInstance(SettingsStore settingsStore,
      LastFmScrobbleApi scrobbleApi) {
    return new ScrobbleManager(settingsStore, scrobbleApi);
  }
}

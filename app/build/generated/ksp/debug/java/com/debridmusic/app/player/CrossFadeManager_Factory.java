package com.debridmusic.app.player;

import com.debridmusic.app.data.local.SettingsStore;
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
public final class CrossFadeManager_Factory implements Factory<CrossFadeManager> {
  private final Provider<SettingsStore> settingsStoreProvider;

  public CrossFadeManager_Factory(Provider<SettingsStore> settingsStoreProvider) {
    this.settingsStoreProvider = settingsStoreProvider;
  }

  @Override
  public CrossFadeManager get() {
    return newInstance(settingsStoreProvider.get());
  }

  public static CrossFadeManager_Factory create(Provider<SettingsStore> settingsStoreProvider) {
    return new CrossFadeManager_Factory(settingsStoreProvider);
  }

  public static CrossFadeManager newInstance(SettingsStore settingsStore) {
    return new CrossFadeManager(settingsStore);
  }
}

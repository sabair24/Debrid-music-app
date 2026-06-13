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
public final class EqController_Factory implements Factory<EqController> {
  private final Provider<SettingsStore> settingsStoreProvider;

  public EqController_Factory(Provider<SettingsStore> settingsStoreProvider) {
    this.settingsStoreProvider = settingsStoreProvider;
  }

  @Override
  public EqController get() {
    return newInstance(settingsStoreProvider.get());
  }

  public static EqController_Factory create(Provider<SettingsStore> settingsStoreProvider) {
    return new EqController_Factory(settingsStoreProvider);
  }

  public static EqController newInstance(SettingsStore settingsStore) {
    return new EqController(settingsStore);
  }
}

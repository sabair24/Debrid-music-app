package com.debridmusic.app.soulseek;

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
public final class SoulseekRepository_Factory implements Factory<SoulseekRepository> {
  private final Provider<SoulseekClient> clientProvider;

  private final Provider<SettingsStore> settingsStoreProvider;

  public SoulseekRepository_Factory(Provider<SoulseekClient> clientProvider,
      Provider<SettingsStore> settingsStoreProvider) {
    this.clientProvider = clientProvider;
    this.settingsStoreProvider = settingsStoreProvider;
  }

  @Override
  public SoulseekRepository get() {
    return newInstance(clientProvider.get(), settingsStoreProvider.get());
  }

  public static SoulseekRepository_Factory create(Provider<SoulseekClient> clientProvider,
      Provider<SettingsStore> settingsStoreProvider) {
    return new SoulseekRepository_Factory(clientProvider, settingsStoreProvider);
  }

  public static SoulseekRepository newInstance(SoulseekClient client, SettingsStore settingsStore) {
    return new SoulseekRepository(client, settingsStore);
  }
}

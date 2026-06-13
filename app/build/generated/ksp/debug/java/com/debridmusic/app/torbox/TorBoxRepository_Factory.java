package com.debridmusic.app.torbox;

import com.debridmusic.app.data.local.SettingsStore;
import com.debridmusic.app.data.remote.api.BitSearchApi;
import com.debridmusic.app.data.remote.api.TorBoxApi;
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
public final class TorBoxRepository_Factory implements Factory<TorBoxRepository> {
  private final Provider<TorBoxApi> apiProvider;

  private final Provider<BitSearchApi> bitSearchApiProvider;

  private final Provider<SettingsStore> settingsStoreProvider;

  private final Provider<TorBoxAuthInterceptor> authInterceptorProvider;

  public TorBoxRepository_Factory(Provider<TorBoxApi> apiProvider,
      Provider<BitSearchApi> bitSearchApiProvider, Provider<SettingsStore> settingsStoreProvider,
      Provider<TorBoxAuthInterceptor> authInterceptorProvider) {
    this.apiProvider = apiProvider;
    this.bitSearchApiProvider = bitSearchApiProvider;
    this.settingsStoreProvider = settingsStoreProvider;
    this.authInterceptorProvider = authInterceptorProvider;
  }

  @Override
  public TorBoxRepository get() {
    return newInstance(apiProvider.get(), bitSearchApiProvider.get(), settingsStoreProvider.get(), authInterceptorProvider.get());
  }

  public static TorBoxRepository_Factory create(Provider<TorBoxApi> apiProvider,
      Provider<BitSearchApi> bitSearchApiProvider, Provider<SettingsStore> settingsStoreProvider,
      Provider<TorBoxAuthInterceptor> authInterceptorProvider) {
    return new TorBoxRepository_Factory(apiProvider, bitSearchApiProvider, settingsStoreProvider, authInterceptorProvider);
  }

  public static TorBoxRepository newInstance(TorBoxApi api, BitSearchApi bitSearchApi,
      SettingsStore settingsStore, TorBoxAuthInterceptor authInterceptor) {
    return new TorBoxRepository(api, bitSearchApi, settingsStore, authInterceptor);
  }
}

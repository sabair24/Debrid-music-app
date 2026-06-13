package com.debridmusic.app.di;

import com.debridmusic.app.data.remote.api.BitSearchApi;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import retrofit2.Retrofit;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("javax.inject.Named")
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
public final class NetworkModule_ProvideBitSearchApiFactory implements Factory<BitSearchApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideBitSearchApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public BitSearchApi get() {
    return provideBitSearchApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideBitSearchApiFactory create(
      Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideBitSearchApiFactory(retrofitProvider);
  }

  public static BitSearchApi provideBitSearchApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideBitSearchApi(retrofit));
  }
}

package com.debridmusic.app.di;

import com.debridmusic.app.data.remote.api.LastFmScrobbleApi;
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
public final class NetworkModule_ProvideLastFmScrobbleApiFactory implements Factory<LastFmScrobbleApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideLastFmScrobbleApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public LastFmScrobbleApi get() {
    return provideLastFmScrobbleApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideLastFmScrobbleApiFactory create(
      Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideLastFmScrobbleApiFactory(retrofitProvider);
  }

  public static LastFmScrobbleApi provideLastFmScrobbleApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideLastFmScrobbleApi(retrofit));
  }
}

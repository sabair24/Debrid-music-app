package com.debridmusic.app.di;

import com.debridmusic.app.data.remote.api.LastFmApi;
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
public final class NetworkModule_ProvideLastFmApiFactory implements Factory<LastFmApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideLastFmApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public LastFmApi get() {
    return provideLastFmApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideLastFmApiFactory create(Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideLastFmApiFactory(retrofitProvider);
  }

  public static LastFmApi provideLastFmApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideLastFmApi(retrofit));
  }
}

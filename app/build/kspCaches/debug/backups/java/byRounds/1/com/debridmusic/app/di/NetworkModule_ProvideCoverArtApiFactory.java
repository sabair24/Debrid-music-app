package com.debridmusic.app.di;

import com.debridmusic.app.data.remote.api.CoverArtArchiveApi;
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
public final class NetworkModule_ProvideCoverArtApiFactory implements Factory<CoverArtArchiveApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideCoverArtApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public CoverArtArchiveApi get() {
    return provideCoverArtApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideCoverArtApiFactory create(
      Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideCoverArtApiFactory(retrofitProvider);
  }

  public static CoverArtArchiveApi provideCoverArtApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideCoverArtApi(retrofit));
  }
}

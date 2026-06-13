package com.debridmusic.app.di;

import com.debridmusic.app.torbox.TorBoxAuthInterceptor;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import okhttp3.OkHttpClient;
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
public final class NetworkModule_ProvideTorBoxRetrofitFactory implements Factory<Retrofit> {
  private final Provider<OkHttpClient> okHttpClientProvider;

  private final Provider<TorBoxAuthInterceptor> authInterceptorProvider;

  public NetworkModule_ProvideTorBoxRetrofitFactory(Provider<OkHttpClient> okHttpClientProvider,
      Provider<TorBoxAuthInterceptor> authInterceptorProvider) {
    this.okHttpClientProvider = okHttpClientProvider;
    this.authInterceptorProvider = authInterceptorProvider;
  }

  @Override
  public Retrofit get() {
    return provideTorBoxRetrofit(okHttpClientProvider.get(), authInterceptorProvider.get());
  }

  public static NetworkModule_ProvideTorBoxRetrofitFactory create(
      Provider<OkHttpClient> okHttpClientProvider,
      Provider<TorBoxAuthInterceptor> authInterceptorProvider) {
    return new NetworkModule_ProvideTorBoxRetrofitFactory(okHttpClientProvider, authInterceptorProvider);
  }

  public static Retrofit provideTorBoxRetrofit(OkHttpClient okHttpClient,
      TorBoxAuthInterceptor authInterceptor) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideTorBoxRetrofit(okHttpClient, authInterceptor));
  }
}

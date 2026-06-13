package com.debridmusic.app.di;

import com.debridmusic.app.update.GitHubApi;
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
public final class NetworkModule_ProvideGitHubApiFactory implements Factory<GitHubApi> {
  private final Provider<Retrofit> retrofitProvider;

  public NetworkModule_ProvideGitHubApiFactory(Provider<Retrofit> retrofitProvider) {
    this.retrofitProvider = retrofitProvider;
  }

  @Override
  public GitHubApi get() {
    return provideGitHubApi(retrofitProvider.get());
  }

  public static NetworkModule_ProvideGitHubApiFactory create(Provider<Retrofit> retrofitProvider) {
    return new NetworkModule_ProvideGitHubApiFactory(retrofitProvider);
  }

  public static GitHubApi provideGitHubApi(Retrofit retrofit) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideGitHubApi(retrofit));
  }
}

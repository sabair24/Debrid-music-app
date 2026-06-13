package com.debridmusic.app.update;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import okhttp3.OkHttpClient;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class UpdateRepository_Factory implements Factory<UpdateRepository> {
  private final Provider<Context> contextProvider;

  private final Provider<GitHubApi> gitHubApiProvider;

  private final Provider<OkHttpClient> okHttpClientProvider;

  public UpdateRepository_Factory(Provider<Context> contextProvider,
      Provider<GitHubApi> gitHubApiProvider, Provider<OkHttpClient> okHttpClientProvider) {
    this.contextProvider = contextProvider;
    this.gitHubApiProvider = gitHubApiProvider;
    this.okHttpClientProvider = okHttpClientProvider;
  }

  @Override
  public UpdateRepository get() {
    return newInstance(contextProvider.get(), gitHubApiProvider.get(), okHttpClientProvider.get());
  }

  public static UpdateRepository_Factory create(Provider<Context> contextProvider,
      Provider<GitHubApi> gitHubApiProvider, Provider<OkHttpClient> okHttpClientProvider) {
    return new UpdateRepository_Factory(contextProvider, gitHubApiProvider, okHttpClientProvider);
  }

  public static UpdateRepository newInstance(Context context, GitHubApi gitHubApi,
      OkHttpClient okHttpClient) {
    return new UpdateRepository(context, gitHubApi, okHttpClient);
  }
}

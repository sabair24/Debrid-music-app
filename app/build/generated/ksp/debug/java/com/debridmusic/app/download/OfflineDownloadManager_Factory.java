package com.debridmusic.app.download;

import android.content.Context;
import com.debridmusic.app.data.local.dao.DownloadDao;
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
public final class OfflineDownloadManager_Factory implements Factory<OfflineDownloadManager> {
  private final Provider<Context> contextProvider;

  private final Provider<DownloadDao> downloadDaoProvider;

  private final Provider<OkHttpClient> okHttpClientProvider;

  public OfflineDownloadManager_Factory(Provider<Context> contextProvider,
      Provider<DownloadDao> downloadDaoProvider, Provider<OkHttpClient> okHttpClientProvider) {
    this.contextProvider = contextProvider;
    this.downloadDaoProvider = downloadDaoProvider;
    this.okHttpClientProvider = okHttpClientProvider;
  }

  @Override
  public OfflineDownloadManager get() {
    return newInstance(contextProvider.get(), downloadDaoProvider.get(), okHttpClientProvider.get());
  }

  public static OfflineDownloadManager_Factory create(Provider<Context> contextProvider,
      Provider<DownloadDao> downloadDaoProvider, Provider<OkHttpClient> okHttpClientProvider) {
    return new OfflineDownloadManager_Factory(contextProvider, downloadDaoProvider, okHttpClientProvider);
  }

  public static OfflineDownloadManager newInstance(Context context, DownloadDao downloadDao,
      OkHttpClient okHttpClient) {
    return new OfflineDownloadManager(context, downloadDao, okHttpClient);
  }
}

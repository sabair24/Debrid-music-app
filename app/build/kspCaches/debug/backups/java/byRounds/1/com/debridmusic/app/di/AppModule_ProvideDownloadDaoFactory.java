package com.debridmusic.app.di;

import com.debridmusic.app.data.local.AppDatabase;
import com.debridmusic.app.data.local.dao.DownloadDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
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
public final class AppModule_ProvideDownloadDaoFactory implements Factory<DownloadDao> {
  private final Provider<AppDatabase> dbProvider;

  public AppModule_ProvideDownloadDaoFactory(Provider<AppDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public DownloadDao get() {
    return provideDownloadDao(dbProvider.get());
  }

  public static AppModule_ProvideDownloadDaoFactory create(Provider<AppDatabase> dbProvider) {
    return new AppModule_ProvideDownloadDaoFactory(dbProvider);
  }

  public static DownloadDao provideDownloadDao(AppDatabase db) {
    return Preconditions.checkNotNullFromProvides(AppModule.INSTANCE.provideDownloadDao(db));
  }
}

package com.debridmusic.app.di;

import com.debridmusic.app.data.local.AppDatabase;
import com.debridmusic.app.data.local.dao.PlaylistDao;
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
public final class AppModule_ProvidePlaylistDaoFactory implements Factory<PlaylistDao> {
  private final Provider<AppDatabase> dbProvider;

  public AppModule_ProvidePlaylistDaoFactory(Provider<AppDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public PlaylistDao get() {
    return providePlaylistDao(dbProvider.get());
  }

  public static AppModule_ProvidePlaylistDaoFactory create(Provider<AppDatabase> dbProvider) {
    return new AppModule_ProvidePlaylistDaoFactory(dbProvider);
  }

  public static PlaylistDao providePlaylistDao(AppDatabase db) {
    return Preconditions.checkNotNullFromProvides(AppModule.INSTANCE.providePlaylistDao(db));
  }
}

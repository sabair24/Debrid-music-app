package com.debridmusic.app.di;

import com.debridmusic.app.data.local.AppDatabase;
import com.debridmusic.app.data.local.dao.AlbumDao;
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
public final class AppModule_ProvideAlbumDaoFactory implements Factory<AlbumDao> {
  private final Provider<AppDatabase> dbProvider;

  public AppModule_ProvideAlbumDaoFactory(Provider<AppDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public AlbumDao get() {
    return provideAlbumDao(dbProvider.get());
  }

  public static AppModule_ProvideAlbumDaoFactory create(Provider<AppDatabase> dbProvider) {
    return new AppModule_ProvideAlbumDaoFactory(dbProvider);
  }

  public static AlbumDao provideAlbumDao(AppDatabase db) {
    return Preconditions.checkNotNullFromProvides(AppModule.INSTANCE.provideAlbumDao(db));
  }
}

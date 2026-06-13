package com.debridmusic.app.di;

import com.debridmusic.app.data.local.AppDatabase;
import com.debridmusic.app.data.local.dao.ArtistDao;
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
public final class AppModule_ProvideArtistDaoFactory implements Factory<ArtistDao> {
  private final Provider<AppDatabase> dbProvider;

  public AppModule_ProvideArtistDaoFactory(Provider<AppDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public ArtistDao get() {
    return provideArtistDao(dbProvider.get());
  }

  public static AppModule_ProvideArtistDaoFactory create(Provider<AppDatabase> dbProvider) {
    return new AppModule_ProvideArtistDaoFactory(dbProvider);
  }

  public static ArtistDao provideArtistDao(AppDatabase db) {
    return Preconditions.checkNotNullFromProvides(AppModule.INSTANCE.provideArtistDao(db));
  }
}

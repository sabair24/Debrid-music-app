package com.debridmusic.app.scanner;

import android.content.Context;
import com.debridmusic.app.data.local.dao.AlbumDao;
import com.debridmusic.app.data.local.dao.ArtistDao;
import com.debridmusic.app.data.local.dao.TrackDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class MediaScanner_Factory implements Factory<MediaScanner> {
  private final Provider<Context> contextProvider;

  private final Provider<TrackDao> trackDaoProvider;

  private final Provider<AlbumDao> albumDaoProvider;

  private final Provider<ArtistDao> artistDaoProvider;

  public MediaScanner_Factory(Provider<Context> contextProvider,
      Provider<TrackDao> trackDaoProvider, Provider<AlbumDao> albumDaoProvider,
      Provider<ArtistDao> artistDaoProvider) {
    this.contextProvider = contextProvider;
    this.trackDaoProvider = trackDaoProvider;
    this.albumDaoProvider = albumDaoProvider;
    this.artistDaoProvider = artistDaoProvider;
  }

  @Override
  public MediaScanner get() {
    return newInstance(contextProvider.get(), trackDaoProvider.get(), albumDaoProvider.get(), artistDaoProvider.get());
  }

  public static MediaScanner_Factory create(Provider<Context> contextProvider,
      Provider<TrackDao> trackDaoProvider, Provider<AlbumDao> albumDaoProvider,
      Provider<ArtistDao> artistDaoProvider) {
    return new MediaScanner_Factory(contextProvider, trackDaoProvider, albumDaoProvider, artistDaoProvider);
  }

  public static MediaScanner newInstance(Context context, TrackDao trackDao, AlbumDao albumDao,
      ArtistDao artistDao) {
    return new MediaScanner(context, trackDao, albumDao, artistDao);
  }
}

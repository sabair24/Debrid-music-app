package com.debridmusic.app.data.repository;

import com.debridmusic.app.data.local.dao.AlbumDao;
import com.debridmusic.app.data.local.dao.ArtistDao;
import com.debridmusic.app.data.local.dao.DownloadDao;
import com.debridmusic.app.data.local.dao.PlaylistDao;
import com.debridmusic.app.data.local.dao.TrackDao;
import com.debridmusic.app.scanner.MediaScanner;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
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
public final class MusicRepository_Factory implements Factory<MusicRepository> {
  private final Provider<TrackDao> trackDaoProvider;

  private final Provider<AlbumDao> albumDaoProvider;

  private final Provider<ArtistDao> artistDaoProvider;

  private final Provider<PlaylistDao> playlistDaoProvider;

  private final Provider<DownloadDao> downloadDaoProvider;

  private final Provider<MediaScanner> mediaScannerProvider;

  public MusicRepository_Factory(Provider<TrackDao> trackDaoProvider,
      Provider<AlbumDao> albumDaoProvider, Provider<ArtistDao> artistDaoProvider,
      Provider<PlaylistDao> playlistDaoProvider, Provider<DownloadDao> downloadDaoProvider,
      Provider<MediaScanner> mediaScannerProvider) {
    this.trackDaoProvider = trackDaoProvider;
    this.albumDaoProvider = albumDaoProvider;
    this.artistDaoProvider = artistDaoProvider;
    this.playlistDaoProvider = playlistDaoProvider;
    this.downloadDaoProvider = downloadDaoProvider;
    this.mediaScannerProvider = mediaScannerProvider;
  }

  @Override
  public MusicRepository get() {
    return newInstance(trackDaoProvider.get(), albumDaoProvider.get(), artistDaoProvider.get(), playlistDaoProvider.get(), downloadDaoProvider.get(), mediaScannerProvider.get());
  }

  public static MusicRepository_Factory create(Provider<TrackDao> trackDaoProvider,
      Provider<AlbumDao> albumDaoProvider, Provider<ArtistDao> artistDaoProvider,
      Provider<PlaylistDao> playlistDaoProvider, Provider<DownloadDao> downloadDaoProvider,
      Provider<MediaScanner> mediaScannerProvider) {
    return new MusicRepository_Factory(trackDaoProvider, albumDaoProvider, artistDaoProvider, playlistDaoProvider, downloadDaoProvider, mediaScannerProvider);
  }

  public static MusicRepository newInstance(TrackDao trackDao, AlbumDao albumDao,
      ArtistDao artistDao, PlaylistDao playlistDao, DownloadDao downloadDao,
      MediaScanner mediaScanner) {
    return new MusicRepository(trackDao, albumDao, artistDao, playlistDao, downloadDao, mediaScanner);
  }
}

package com.debridmusic.app.metadata;

import com.debridmusic.app.data.local.SettingsStore;
import com.debridmusic.app.data.local.dao.AlbumDao;
import com.debridmusic.app.data.local.dao.ArtistDao;
import com.debridmusic.app.data.local.dao.TrackDao;
import com.debridmusic.app.data.remote.api.CoverArtArchiveApi;
import com.debridmusic.app.data.remote.api.LastFmApi;
import com.debridmusic.app.data.remote.api.MusicBrainzApi;
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
public final class MetadataEnricher_Factory implements Factory<MetadataEnricher> {
  private final Provider<AlbumDao> albumDaoProvider;

  private final Provider<ArtistDao> artistDaoProvider;

  private final Provider<TrackDao> trackDaoProvider;

  private final Provider<MusicBrainzApi> musicBrainzApiProvider;

  private final Provider<CoverArtArchiveApi> coverArtApiProvider;

  private final Provider<LastFmApi> lastFmApiProvider;

  private final Provider<SettingsStore> settingsStoreProvider;

  public MetadataEnricher_Factory(Provider<AlbumDao> albumDaoProvider,
      Provider<ArtistDao> artistDaoProvider, Provider<TrackDao> trackDaoProvider,
      Provider<MusicBrainzApi> musicBrainzApiProvider,
      Provider<CoverArtArchiveApi> coverArtApiProvider, Provider<LastFmApi> lastFmApiProvider,
      Provider<SettingsStore> settingsStoreProvider) {
    this.albumDaoProvider = albumDaoProvider;
    this.artistDaoProvider = artistDaoProvider;
    this.trackDaoProvider = trackDaoProvider;
    this.musicBrainzApiProvider = musicBrainzApiProvider;
    this.coverArtApiProvider = coverArtApiProvider;
    this.lastFmApiProvider = lastFmApiProvider;
    this.settingsStoreProvider = settingsStoreProvider;
  }

  @Override
  public MetadataEnricher get() {
    return newInstance(albumDaoProvider.get(), artistDaoProvider.get(), trackDaoProvider.get(), musicBrainzApiProvider.get(), coverArtApiProvider.get(), lastFmApiProvider.get(), settingsStoreProvider.get());
  }

  public static MetadataEnricher_Factory create(Provider<AlbumDao> albumDaoProvider,
      Provider<ArtistDao> artistDaoProvider, Provider<TrackDao> trackDaoProvider,
      Provider<MusicBrainzApi> musicBrainzApiProvider,
      Provider<CoverArtArchiveApi> coverArtApiProvider, Provider<LastFmApi> lastFmApiProvider,
      Provider<SettingsStore> settingsStoreProvider) {
    return new MetadataEnricher_Factory(albumDaoProvider, artistDaoProvider, trackDaoProvider, musicBrainzApiProvider, coverArtApiProvider, lastFmApiProvider, settingsStoreProvider);
  }

  public static MetadataEnricher newInstance(AlbumDao albumDao, ArtistDao artistDao,
      TrackDao trackDao, MusicBrainzApi musicBrainzApi, CoverArtArchiveApi coverArtApi,
      LastFmApi lastFmApi, SettingsStore settingsStore) {
    return new MetadataEnricher(albumDao, artistDao, trackDao, musicBrainzApi, coverArtApi, lastFmApi, settingsStore);
  }
}

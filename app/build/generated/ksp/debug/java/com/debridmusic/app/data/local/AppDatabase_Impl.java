package com.debridmusic.app.data.local;

import androidx.annotation.NonNull;
import androidx.room.DatabaseConfiguration;
import androidx.room.InvalidationTracker;
import androidx.room.RoomDatabase;
import androidx.room.RoomOpenHelper;
import androidx.room.migration.AutoMigrationSpec;
import androidx.room.migration.Migration;
import androidx.room.util.DBUtil;
import androidx.room.util.TableInfo;
import androidx.sqlite.db.SupportSQLiteDatabase;
import androidx.sqlite.db.SupportSQLiteOpenHelper;
import com.debridmusic.app.data.local.dao.AlbumDao;
import com.debridmusic.app.data.local.dao.AlbumDao_Impl;
import com.debridmusic.app.data.local.dao.ArtistDao;
import com.debridmusic.app.data.local.dao.ArtistDao_Impl;
import com.debridmusic.app.data.local.dao.DownloadDao;
import com.debridmusic.app.data.local.dao.DownloadDao_Impl;
import com.debridmusic.app.data.local.dao.PlaylistDao;
import com.debridmusic.app.data.local.dao.PlaylistDao_Impl;
import com.debridmusic.app.data.local.dao.TrackDao;
import com.debridmusic.app.data.local.dao.TrackDao_Impl;
import java.lang.Class;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.annotation.processing.Generated;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class AppDatabase_Impl extends AppDatabase {
  private volatile TrackDao _trackDao;

  private volatile AlbumDao _albumDao;

  private volatile ArtistDao _artistDao;

  private volatile PlaylistDao _playlistDao;

  private volatile DownloadDao _downloadDao;

  @Override
  @NonNull
  protected SupportSQLiteOpenHelper createOpenHelper(@NonNull final DatabaseConfiguration config) {
    final SupportSQLiteOpenHelper.Callback _openCallback = new RoomOpenHelper(config, new RoomOpenHelper.Delegate(2) {
      @Override
      public void createAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `tracks` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `title` TEXT NOT NULL, `artistName` TEXT NOT NULL, `albumTitle` TEXT NOT NULL, `albumId` INTEGER, `artistId` INTEGER, `uri` TEXT NOT NULL, `durationMs` INTEGER NOT NULL, `trackNumber` INTEGER NOT NULL, `discNumber` INTEGER NOT NULL, `year` INTEGER, `artworkUri` TEXT, `genre` TEXT, `bitrate` INTEGER, `sampleRate` INTEGER, `isLossless` INTEGER NOT NULL, `fileSize` INTEGER NOT NULL, `dateAdded` INTEGER NOT NULL, FOREIGN KEY(`albumId`) REFERENCES `albums`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL , FOREIGN KEY(`artistId`) REFERENCES `artists`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_tracks_albumId` ON `tracks` (`albumId`)");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_tracks_artistId` ON `tracks` (`artistId`)");
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_tracks_uri` ON `tracks` (`uri`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `albums` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `title` TEXT NOT NULL, `artistId` INTEGER NOT NULL, `artistName` TEXT NOT NULL, `year` INTEGER, `artworkUri` TEXT, `genre` TEXT, `musicBrainzId` TEXT, FOREIGN KEY(`artistId`) REFERENCES `artists`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_albums_artistId` ON `albums` (`artistId`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `artists` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `biography` TEXT, `imageUri` TEXT, `musicBrainzId` TEXT)");
        db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS `index_artists_name` ON `artists` (`name`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `playlists` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `name` TEXT NOT NULL, `createdAt` INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `playlist_track_cross_ref` (`playlistId` INTEGER NOT NULL, `trackId` INTEGER NOT NULL, `sortOrder` INTEGER NOT NULL, PRIMARY KEY(`playlistId`, `trackId`), FOREIGN KEY(`playlistId`) REFERENCES `playlists`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_playlist_track_cross_ref_trackId` ON `playlist_track_cross_ref` (`trackId`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `downloads` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `title` TEXT NOT NULL, `artist` TEXT NOT NULL, `album` TEXT NOT NULL, `sourceUrl` TEXT NOT NULL, `localPath` TEXT NOT NULL, `sizeBytes` INTEGER NOT NULL, `downloadedBytes` INTEGER NOT NULL, `status` TEXT NOT NULL, `dateAdded` INTEGER NOT NULL)");
        db.execSQL("CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)");
        db.execSQL("INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, '1766826ea6af55625b6d3e8d09439f13')");
      }

      @Override
      public void dropAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("DROP TABLE IF EXISTS `tracks`");
        db.execSQL("DROP TABLE IF EXISTS `albums`");
        db.execSQL("DROP TABLE IF EXISTS `artists`");
        db.execSQL("DROP TABLE IF EXISTS `playlists`");
        db.execSQL("DROP TABLE IF EXISTS `playlist_track_cross_ref`");
        db.execSQL("DROP TABLE IF EXISTS `downloads`");
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onDestructiveMigration(db);
          }
        }
      }

      @Override
      public void onCreate(@NonNull final SupportSQLiteDatabase db) {
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onCreate(db);
          }
        }
      }

      @Override
      public void onOpen(@NonNull final SupportSQLiteDatabase db) {
        mDatabase = db;
        db.execSQL("PRAGMA foreign_keys = ON");
        internalInitInvalidationTracker(db);
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onOpen(db);
          }
        }
      }

      @Override
      public void onPreMigrate(@NonNull final SupportSQLiteDatabase db) {
        DBUtil.dropFtsSyncTriggers(db);
      }

      @Override
      public void onPostMigrate(@NonNull final SupportSQLiteDatabase db) {
      }

      @Override
      @NonNull
      public RoomOpenHelper.ValidationResult onValidateSchema(
          @NonNull final SupportSQLiteDatabase db) {
        final HashMap<String, TableInfo.Column> _columnsTracks = new HashMap<String, TableInfo.Column>(18);
        _columnsTracks.put("id", new TableInfo.Column("id", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("title", new TableInfo.Column("title", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("artistName", new TableInfo.Column("artistName", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("albumTitle", new TableInfo.Column("albumTitle", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("albumId", new TableInfo.Column("albumId", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("artistId", new TableInfo.Column("artistId", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("uri", new TableInfo.Column("uri", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("durationMs", new TableInfo.Column("durationMs", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("trackNumber", new TableInfo.Column("trackNumber", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("discNumber", new TableInfo.Column("discNumber", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("year", new TableInfo.Column("year", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("artworkUri", new TableInfo.Column("artworkUri", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("genre", new TableInfo.Column("genre", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("bitrate", new TableInfo.Column("bitrate", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("sampleRate", new TableInfo.Column("sampleRate", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("isLossless", new TableInfo.Column("isLossless", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("fileSize", new TableInfo.Column("fileSize", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsTracks.put("dateAdded", new TableInfo.Column("dateAdded", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysTracks = new HashSet<TableInfo.ForeignKey>(2);
        _foreignKeysTracks.add(new TableInfo.ForeignKey("albums", "SET NULL", "NO ACTION", Arrays.asList("albumId"), Arrays.asList("id")));
        _foreignKeysTracks.add(new TableInfo.ForeignKey("artists", "SET NULL", "NO ACTION", Arrays.asList("artistId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesTracks = new HashSet<TableInfo.Index>(3);
        _indicesTracks.add(new TableInfo.Index("index_tracks_albumId", false, Arrays.asList("albumId"), Arrays.asList("ASC")));
        _indicesTracks.add(new TableInfo.Index("index_tracks_artistId", false, Arrays.asList("artistId"), Arrays.asList("ASC")));
        _indicesTracks.add(new TableInfo.Index("index_tracks_uri", true, Arrays.asList("uri"), Arrays.asList("ASC")));
        final TableInfo _infoTracks = new TableInfo("tracks", _columnsTracks, _foreignKeysTracks, _indicesTracks);
        final TableInfo _existingTracks = TableInfo.read(db, "tracks");
        if (!_infoTracks.equals(_existingTracks)) {
          return new RoomOpenHelper.ValidationResult(false, "tracks(com.debridmusic.app.data.local.entity.TrackEntity).\n"
                  + " Expected:\n" + _infoTracks + "\n"
                  + " Found:\n" + _existingTracks);
        }
        final HashMap<String, TableInfo.Column> _columnsAlbums = new HashMap<String, TableInfo.Column>(8);
        _columnsAlbums.put("id", new TableInfo.Column("id", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("title", new TableInfo.Column("title", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("artistId", new TableInfo.Column("artistId", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("artistName", new TableInfo.Column("artistName", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("year", new TableInfo.Column("year", "INTEGER", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("artworkUri", new TableInfo.Column("artworkUri", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("genre", new TableInfo.Column("genre", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsAlbums.put("musicBrainzId", new TableInfo.Column("musicBrainzId", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysAlbums = new HashSet<TableInfo.ForeignKey>(1);
        _foreignKeysAlbums.add(new TableInfo.ForeignKey("artists", "CASCADE", "NO ACTION", Arrays.asList("artistId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesAlbums = new HashSet<TableInfo.Index>(1);
        _indicesAlbums.add(new TableInfo.Index("index_albums_artistId", false, Arrays.asList("artistId"), Arrays.asList("ASC")));
        final TableInfo _infoAlbums = new TableInfo("albums", _columnsAlbums, _foreignKeysAlbums, _indicesAlbums);
        final TableInfo _existingAlbums = TableInfo.read(db, "albums");
        if (!_infoAlbums.equals(_existingAlbums)) {
          return new RoomOpenHelper.ValidationResult(false, "albums(com.debridmusic.app.data.local.entity.AlbumEntity).\n"
                  + " Expected:\n" + _infoAlbums + "\n"
                  + " Found:\n" + _existingAlbums);
        }
        final HashMap<String, TableInfo.Column> _columnsArtists = new HashMap<String, TableInfo.Column>(5);
        _columnsArtists.put("id", new TableInfo.Column("id", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsArtists.put("name", new TableInfo.Column("name", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsArtists.put("biography", new TableInfo.Column("biography", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsArtists.put("imageUri", new TableInfo.Column("imageUri", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsArtists.put("musicBrainzId", new TableInfo.Column("musicBrainzId", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysArtists = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesArtists = new HashSet<TableInfo.Index>(1);
        _indicesArtists.add(new TableInfo.Index("index_artists_name", true, Arrays.asList("name"), Arrays.asList("ASC")));
        final TableInfo _infoArtists = new TableInfo("artists", _columnsArtists, _foreignKeysArtists, _indicesArtists);
        final TableInfo _existingArtists = TableInfo.read(db, "artists");
        if (!_infoArtists.equals(_existingArtists)) {
          return new RoomOpenHelper.ValidationResult(false, "artists(com.debridmusic.app.data.local.entity.ArtistEntity).\n"
                  + " Expected:\n" + _infoArtists + "\n"
                  + " Found:\n" + _existingArtists);
        }
        final HashMap<String, TableInfo.Column> _columnsPlaylists = new HashMap<String, TableInfo.Column>(3);
        _columnsPlaylists.put("id", new TableInfo.Column("id", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPlaylists.put("name", new TableInfo.Column("name", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPlaylists.put("createdAt", new TableInfo.Column("createdAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysPlaylists = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesPlaylists = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoPlaylists = new TableInfo("playlists", _columnsPlaylists, _foreignKeysPlaylists, _indicesPlaylists);
        final TableInfo _existingPlaylists = TableInfo.read(db, "playlists");
        if (!_infoPlaylists.equals(_existingPlaylists)) {
          return new RoomOpenHelper.ValidationResult(false, "playlists(com.debridmusic.app.data.local.entity.PlaylistEntity).\n"
                  + " Expected:\n" + _infoPlaylists + "\n"
                  + " Found:\n" + _existingPlaylists);
        }
        final HashMap<String, TableInfo.Column> _columnsPlaylistTrackCrossRef = new HashMap<String, TableInfo.Column>(3);
        _columnsPlaylistTrackCrossRef.put("playlistId", new TableInfo.Column("playlistId", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPlaylistTrackCrossRef.put("trackId", new TableInfo.Column("trackId", "INTEGER", true, 2, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPlaylistTrackCrossRef.put("sortOrder", new TableInfo.Column("sortOrder", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysPlaylistTrackCrossRef = new HashSet<TableInfo.ForeignKey>(1);
        _foreignKeysPlaylistTrackCrossRef.add(new TableInfo.ForeignKey("playlists", "CASCADE", "NO ACTION", Arrays.asList("playlistId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesPlaylistTrackCrossRef = new HashSet<TableInfo.Index>(1);
        _indicesPlaylistTrackCrossRef.add(new TableInfo.Index("index_playlist_track_cross_ref_trackId", false, Arrays.asList("trackId"), Arrays.asList("ASC")));
        final TableInfo _infoPlaylistTrackCrossRef = new TableInfo("playlist_track_cross_ref", _columnsPlaylistTrackCrossRef, _foreignKeysPlaylistTrackCrossRef, _indicesPlaylistTrackCrossRef);
        final TableInfo _existingPlaylistTrackCrossRef = TableInfo.read(db, "playlist_track_cross_ref");
        if (!_infoPlaylistTrackCrossRef.equals(_existingPlaylistTrackCrossRef)) {
          return new RoomOpenHelper.ValidationResult(false, "playlist_track_cross_ref(com.debridmusic.app.data.local.entity.PlaylistTrackCrossRef).\n"
                  + " Expected:\n" + _infoPlaylistTrackCrossRef + "\n"
                  + " Found:\n" + _existingPlaylistTrackCrossRef);
        }
        final HashMap<String, TableInfo.Column> _columnsDownloads = new HashMap<String, TableInfo.Column>(10);
        _columnsDownloads.put("id", new TableInfo.Column("id", "INTEGER", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("title", new TableInfo.Column("title", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("artist", new TableInfo.Column("artist", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("album", new TableInfo.Column("album", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("sourceUrl", new TableInfo.Column("sourceUrl", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("localPath", new TableInfo.Column("localPath", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("sizeBytes", new TableInfo.Column("sizeBytes", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("downloadedBytes", new TableInfo.Column("downloadedBytes", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("status", new TableInfo.Column("status", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsDownloads.put("dateAdded", new TableInfo.Column("dateAdded", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysDownloads = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesDownloads = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoDownloads = new TableInfo("downloads", _columnsDownloads, _foreignKeysDownloads, _indicesDownloads);
        final TableInfo _existingDownloads = TableInfo.read(db, "downloads");
        if (!_infoDownloads.equals(_existingDownloads)) {
          return new RoomOpenHelper.ValidationResult(false, "downloads(com.debridmusic.app.data.local.entity.DownloadEntity).\n"
                  + " Expected:\n" + _infoDownloads + "\n"
                  + " Found:\n" + _existingDownloads);
        }
        return new RoomOpenHelper.ValidationResult(true, null);
      }
    }, "1766826ea6af55625b6d3e8d09439f13", "f13cb6e25cc87d9ddbf0eedf76b50fa2");
    final SupportSQLiteOpenHelper.Configuration _sqliteConfig = SupportSQLiteOpenHelper.Configuration.builder(config.context).name(config.name).callback(_openCallback).build();
    final SupportSQLiteOpenHelper _helper = config.sqliteOpenHelperFactory.create(_sqliteConfig);
    return _helper;
  }

  @Override
  @NonNull
  protected InvalidationTracker createInvalidationTracker() {
    final HashMap<String, String> _shadowTablesMap = new HashMap<String, String>(0);
    final HashMap<String, Set<String>> _viewTables = new HashMap<String, Set<String>>(0);
    return new InvalidationTracker(this, _shadowTablesMap, _viewTables, "tracks","albums","artists","playlists","playlist_track_cross_ref","downloads");
  }

  @Override
  public void clearAllTables() {
    super.assertNotMainThread();
    final SupportSQLiteDatabase _db = super.getOpenHelper().getWritableDatabase();
    final boolean _supportsDeferForeignKeys = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP;
    try {
      if (!_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA foreign_keys = FALSE");
      }
      super.beginTransaction();
      if (_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA defer_foreign_keys = TRUE");
      }
      _db.execSQL("DELETE FROM `tracks`");
      _db.execSQL("DELETE FROM `albums`");
      _db.execSQL("DELETE FROM `artists`");
      _db.execSQL("DELETE FROM `playlists`");
      _db.execSQL("DELETE FROM `playlist_track_cross_ref`");
      _db.execSQL("DELETE FROM `downloads`");
      super.setTransactionSuccessful();
    } finally {
      super.endTransaction();
      if (!_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA foreign_keys = TRUE");
      }
      _db.query("PRAGMA wal_checkpoint(FULL)").close();
      if (!_db.inTransaction()) {
        _db.execSQL("VACUUM");
      }
    }
  }

  @Override
  @NonNull
  protected Map<Class<?>, List<Class<?>>> getRequiredTypeConverters() {
    final HashMap<Class<?>, List<Class<?>>> _typeConvertersMap = new HashMap<Class<?>, List<Class<?>>>();
    _typeConvertersMap.put(TrackDao.class, TrackDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(AlbumDao.class, AlbumDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(ArtistDao.class, ArtistDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(PlaylistDao.class, PlaylistDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(DownloadDao.class, DownloadDao_Impl.getRequiredConverters());
    return _typeConvertersMap;
  }

  @Override
  @NonNull
  public Set<Class<? extends AutoMigrationSpec>> getRequiredAutoMigrationSpecs() {
    final HashSet<Class<? extends AutoMigrationSpec>> _autoMigrationSpecsSet = new HashSet<Class<? extends AutoMigrationSpec>>();
    return _autoMigrationSpecsSet;
  }

  @Override
  @NonNull
  public List<Migration> getAutoMigrations(
      @NonNull final Map<Class<? extends AutoMigrationSpec>, AutoMigrationSpec> autoMigrationSpecs) {
    final List<Migration> _autoMigrations = new ArrayList<Migration>();
    return _autoMigrations;
  }

  @Override
  public TrackDao trackDao() {
    if (_trackDao != null) {
      return _trackDao;
    } else {
      synchronized(this) {
        if(_trackDao == null) {
          _trackDao = new TrackDao_Impl(this);
        }
        return _trackDao;
      }
    }
  }

  @Override
  public AlbumDao albumDao() {
    if (_albumDao != null) {
      return _albumDao;
    } else {
      synchronized(this) {
        if(_albumDao == null) {
          _albumDao = new AlbumDao_Impl(this);
        }
        return _albumDao;
      }
    }
  }

  @Override
  public ArtistDao artistDao() {
    if (_artistDao != null) {
      return _artistDao;
    } else {
      synchronized(this) {
        if(_artistDao == null) {
          _artistDao = new ArtistDao_Impl(this);
        }
        return _artistDao;
      }
    }
  }

  @Override
  public PlaylistDao playlistDao() {
    if (_playlistDao != null) {
      return _playlistDao;
    } else {
      synchronized(this) {
        if(_playlistDao == null) {
          _playlistDao = new PlaylistDao_Impl(this);
        }
        return _playlistDao;
      }
    }
  }

  @Override
  public DownloadDao downloadDao() {
    if (_downloadDao != null) {
      return _downloadDao;
    } else {
      synchronized(this) {
        if(_downloadDao == null) {
          _downloadDao = new DownloadDao_Impl(this);
        }
        return _downloadDao;
      }
    }
  }
}

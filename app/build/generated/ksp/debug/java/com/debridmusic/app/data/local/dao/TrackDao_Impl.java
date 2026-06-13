package com.debridmusic.app.data.local.dao;

import android.database.Cursor;
import android.os.CancellationSignal;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityDeletionOrUpdateAdapter;
import androidx.room.EntityInsertionAdapter;
import androidx.room.EntityUpsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.SharedSQLiteStatement;
import androidx.room.util.CursorUtil;
import androidx.room.util.DBUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import com.debridmusic.app.data.local.entity.TrackEntity;
import java.lang.Class;
import java.lang.Exception;
import java.lang.Integer;
import java.lang.Long;
import java.lang.Object;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import javax.annotation.processing.Generated;
import kotlin.Unit;
import kotlin.coroutines.Continuation;
import kotlinx.coroutines.flow.Flow;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class TrackDao_Impl implements TrackDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<TrackEntity> __insertionAdapterOfTrackEntity;

  private final EntityDeletionOrUpdateAdapter<TrackEntity> __updateAdapterOfTrackEntity;

  private final SharedSQLiteStatement __preparedStmtOfDeleteById;

  private final SharedSQLiteStatement __preparedStmtOfDeleteByUri;

  private final EntityUpsertionAdapter<TrackEntity> __upsertionAdapterOfTrackEntity;

  public TrackDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfTrackEntity = new EntityInsertionAdapter<TrackEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR IGNORE INTO `tracks` (`id`,`title`,`artistName`,`albumTitle`,`albumId`,`artistId`,`uri`,`durationMs`,`trackNumber`,`discNumber`,`year`,`artworkUri`,`genre`,`bitrate`,`sampleRate`,`isLossless`,`fileSize`,`dateAdded`) VALUES (nullif(?, 0),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final TrackEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindString(3, entity.getArtistName());
        statement.bindString(4, entity.getAlbumTitle());
        if (entity.getAlbumId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getAlbumId());
        }
        if (entity.getArtistId() == null) {
          statement.bindNull(6);
        } else {
          statement.bindLong(6, entity.getArtistId());
        }
        statement.bindString(7, entity.getUri());
        statement.bindLong(8, entity.getDurationMs());
        statement.bindLong(9, entity.getTrackNumber());
        statement.bindLong(10, entity.getDiscNumber());
        if (entity.getYear() == null) {
          statement.bindNull(11);
        } else {
          statement.bindLong(11, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(12);
        } else {
          statement.bindString(12, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, entity.getGenre());
        }
        if (entity.getBitrate() == null) {
          statement.bindNull(14);
        } else {
          statement.bindLong(14, entity.getBitrate());
        }
        if (entity.getSampleRate() == null) {
          statement.bindNull(15);
        } else {
          statement.bindLong(15, entity.getSampleRate());
        }
        final int _tmp = entity.isLossless() ? 1 : 0;
        statement.bindLong(16, _tmp);
        statement.bindLong(17, entity.getFileSize());
        statement.bindLong(18, entity.getDateAdded());
      }
    };
    this.__updateAdapterOfTrackEntity = new EntityDeletionOrUpdateAdapter<TrackEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE OR ABORT `tracks` SET `id` = ?,`title` = ?,`artistName` = ?,`albumTitle` = ?,`albumId` = ?,`artistId` = ?,`uri` = ?,`durationMs` = ?,`trackNumber` = ?,`discNumber` = ?,`year` = ?,`artworkUri` = ?,`genre` = ?,`bitrate` = ?,`sampleRate` = ?,`isLossless` = ?,`fileSize` = ?,`dateAdded` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final TrackEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindString(3, entity.getArtistName());
        statement.bindString(4, entity.getAlbumTitle());
        if (entity.getAlbumId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getAlbumId());
        }
        if (entity.getArtistId() == null) {
          statement.bindNull(6);
        } else {
          statement.bindLong(6, entity.getArtistId());
        }
        statement.bindString(7, entity.getUri());
        statement.bindLong(8, entity.getDurationMs());
        statement.bindLong(9, entity.getTrackNumber());
        statement.bindLong(10, entity.getDiscNumber());
        if (entity.getYear() == null) {
          statement.bindNull(11);
        } else {
          statement.bindLong(11, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(12);
        } else {
          statement.bindString(12, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, entity.getGenre());
        }
        if (entity.getBitrate() == null) {
          statement.bindNull(14);
        } else {
          statement.bindLong(14, entity.getBitrate());
        }
        if (entity.getSampleRate() == null) {
          statement.bindNull(15);
        } else {
          statement.bindLong(15, entity.getSampleRate());
        }
        final int _tmp = entity.isLossless() ? 1 : 0;
        statement.bindLong(16, _tmp);
        statement.bindLong(17, entity.getFileSize());
        statement.bindLong(18, entity.getDateAdded());
        statement.bindLong(19, entity.getId());
      }
    };
    this.__preparedStmtOfDeleteById = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "DELETE FROM tracks WHERE id = ?";
        return _query;
      }
    };
    this.__preparedStmtOfDeleteByUri = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "DELETE FROM tracks WHERE uri = ?";
        return _query;
      }
    };
    this.__upsertionAdapterOfTrackEntity = new EntityUpsertionAdapter<TrackEntity>(new EntityInsertionAdapter<TrackEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT INTO `tracks` (`id`,`title`,`artistName`,`albumTitle`,`albumId`,`artistId`,`uri`,`durationMs`,`trackNumber`,`discNumber`,`year`,`artworkUri`,`genre`,`bitrate`,`sampleRate`,`isLossless`,`fileSize`,`dateAdded`) VALUES (nullif(?, 0),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final TrackEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindString(3, entity.getArtistName());
        statement.bindString(4, entity.getAlbumTitle());
        if (entity.getAlbumId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getAlbumId());
        }
        if (entity.getArtistId() == null) {
          statement.bindNull(6);
        } else {
          statement.bindLong(6, entity.getArtistId());
        }
        statement.bindString(7, entity.getUri());
        statement.bindLong(8, entity.getDurationMs());
        statement.bindLong(9, entity.getTrackNumber());
        statement.bindLong(10, entity.getDiscNumber());
        if (entity.getYear() == null) {
          statement.bindNull(11);
        } else {
          statement.bindLong(11, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(12);
        } else {
          statement.bindString(12, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, entity.getGenre());
        }
        if (entity.getBitrate() == null) {
          statement.bindNull(14);
        } else {
          statement.bindLong(14, entity.getBitrate());
        }
        if (entity.getSampleRate() == null) {
          statement.bindNull(15);
        } else {
          statement.bindLong(15, entity.getSampleRate());
        }
        final int _tmp = entity.isLossless() ? 1 : 0;
        statement.bindLong(16, _tmp);
        statement.bindLong(17, entity.getFileSize());
        statement.bindLong(18, entity.getDateAdded());
      }
    }, new EntityDeletionOrUpdateAdapter<TrackEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE `tracks` SET `id` = ?,`title` = ?,`artistName` = ?,`albumTitle` = ?,`albumId` = ?,`artistId` = ?,`uri` = ?,`durationMs` = ?,`trackNumber` = ?,`discNumber` = ?,`year` = ?,`artworkUri` = ?,`genre` = ?,`bitrate` = ?,`sampleRate` = ?,`isLossless` = ?,`fileSize` = ?,`dateAdded` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final TrackEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindString(3, entity.getArtistName());
        statement.bindString(4, entity.getAlbumTitle());
        if (entity.getAlbumId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getAlbumId());
        }
        if (entity.getArtistId() == null) {
          statement.bindNull(6);
        } else {
          statement.bindLong(6, entity.getArtistId());
        }
        statement.bindString(7, entity.getUri());
        statement.bindLong(8, entity.getDurationMs());
        statement.bindLong(9, entity.getTrackNumber());
        statement.bindLong(10, entity.getDiscNumber());
        if (entity.getYear() == null) {
          statement.bindNull(11);
        } else {
          statement.bindLong(11, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(12);
        } else {
          statement.bindString(12, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(13);
        } else {
          statement.bindString(13, entity.getGenre());
        }
        if (entity.getBitrate() == null) {
          statement.bindNull(14);
        } else {
          statement.bindLong(14, entity.getBitrate());
        }
        if (entity.getSampleRate() == null) {
          statement.bindNull(15);
        } else {
          statement.bindLong(15, entity.getSampleRate());
        }
        final int _tmp = entity.isLossless() ? 1 : 0;
        statement.bindLong(16, _tmp);
        statement.bindLong(17, entity.getFileSize());
        statement.bindLong(18, entity.getDateAdded());
        statement.bindLong(19, entity.getId());
      }
    });
  }

  @Override
  public Object insert(final TrackEntity track, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __insertionAdapterOfTrackEntity.insertAndReturnId(track);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object update(final TrackEntity track, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __updateAdapterOfTrackEntity.handle(track);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object deleteById(final long id, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfDeleteById.acquire();
        int _argIndex = 1;
        _stmt.bindLong(_argIndex, id);
        try {
          __db.beginTransaction();
          try {
            _stmt.executeUpdateDelete();
            __db.setTransactionSuccessful();
            return Unit.INSTANCE;
          } finally {
            __db.endTransaction();
          }
        } finally {
          __preparedStmtOfDeleteById.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Object deleteByUri(final String uri, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfDeleteByUri.acquire();
        int _argIndex = 1;
        _stmt.bindString(_argIndex, uri);
        try {
          __db.beginTransaction();
          try {
            _stmt.executeUpdateDelete();
            __db.setTransactionSuccessful();
            return Unit.INSTANCE;
          } finally {
            __db.endTransaction();
          }
        } finally {
          __preparedStmtOfDeleteByUri.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Object upsert(final TrackEntity track, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __upsertionAdapterOfTrackEntity.upsertAndReturnId(track);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<TrackEntity>> observeAll() {
    final String _sql = "SELECT * FROM tracks ORDER BY artistName ASC, albumTitle ASC, discNumber ASC, trackNumber ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"tracks"}, new Callable<List<TrackEntity>>() {
      @Override
      @NonNull
      public List<TrackEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final List<TrackEntity> _result = new ArrayList<TrackEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final TrackEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _item = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Flow<List<TrackEntity>> observeByAlbum(final long albumId) {
    final String _sql = "SELECT * FROM tracks WHERE albumId = ? ORDER BY discNumber ASC, trackNumber ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, albumId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"tracks"}, new Callable<List<TrackEntity>>() {
      @Override
      @NonNull
      public List<TrackEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final List<TrackEntity> _result = new ArrayList<TrackEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final TrackEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _item = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Flow<List<TrackEntity>> observeByArtist(final long artistId) {
    final String _sql = "SELECT * FROM tracks WHERE artistId = ? ORDER BY albumTitle ASC, discNumber ASC, trackNumber ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, artistId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"tracks"}, new Callable<List<TrackEntity>>() {
      @Override
      @NonNull
      public List<TrackEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final List<TrackEntity> _result = new ArrayList<TrackEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final TrackEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _item = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Object getById(final long id, final Continuation<? super TrackEntity> $completion) {
    final String _sql = "SELECT * FROM tracks WHERE id = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, id);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<TrackEntity>() {
      @Override
      @Nullable
      public TrackEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final TrackEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _result = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @Override
  public Object getByUri(final String uri, final Continuation<? super TrackEntity> $completion) {
    final String _sql = "SELECT * FROM tracks WHERE uri = ? LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, uri);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<TrackEntity>() {
      @Override
      @Nullable
      public TrackEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final TrackEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _result = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @Override
  public Object search(final String query,
      final Continuation<? super List<TrackEntity>> $completion) {
    final String _sql = "\n"
            + "        SELECT * FROM tracks\n"
            + "        WHERE title LIKE '%' || ? || '%'\n"
            + "           OR artistName LIKE '%' || ? || '%'\n"
            + "           OR albumTitle LIKE '%' || ? || '%'\n"
            + "        ORDER BY title ASC\n"
            + "        LIMIT 50\n"
            + "    ";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 3);
    int _argIndex = 1;
    _statement.bindString(_argIndex, query);
    _argIndex = 2;
    _statement.bindString(_argIndex, query);
    _argIndex = 3;
    _statement.bindString(_argIndex, query);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<List<TrackEntity>>() {
      @Override
      @NonNull
      public List<TrackEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final List<TrackEntity> _result = new ArrayList<TrackEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final TrackEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _item = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @Override
  public Flow<Integer> countAll() {
    final String _sql = "SELECT COUNT(*) FROM tracks";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"tracks"}, new Callable<Integer>() {
      @Override
      @NonNull
      public Integer call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final Integer _result;
          if (_cursor.moveToFirst()) {
            final int _tmp;
            _tmp = _cursor.getInt(0);
            _result = _tmp;
          } else {
            _result = 0;
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Flow<List<TrackEntity>> observeRecentlyAdded(final int limit) {
    final String _sql = "SELECT * FROM tracks ORDER BY dateAdded DESC LIMIT ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, limit);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"tracks"}, new Callable<List<TrackEntity>>() {
      @Override
      @NonNull
      public List<TrackEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfAlbumTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "albumTitle");
          final int _cursorIndexOfAlbumId = CursorUtil.getColumnIndexOrThrow(_cursor, "albumId");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfUri = CursorUtil.getColumnIndexOrThrow(_cursor, "uri");
          final int _cursorIndexOfDurationMs = CursorUtil.getColumnIndexOrThrow(_cursor, "durationMs");
          final int _cursorIndexOfTrackNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "trackNumber");
          final int _cursorIndexOfDiscNumber = CursorUtil.getColumnIndexOrThrow(_cursor, "discNumber");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfBitrate = CursorUtil.getColumnIndexOrThrow(_cursor, "bitrate");
          final int _cursorIndexOfSampleRate = CursorUtil.getColumnIndexOrThrow(_cursor, "sampleRate");
          final int _cursorIndexOfIsLossless = CursorUtil.getColumnIndexOrThrow(_cursor, "isLossless");
          final int _cursorIndexOfFileSize = CursorUtil.getColumnIndexOrThrow(_cursor, "fileSize");
          final int _cursorIndexOfDateAdded = CursorUtil.getColumnIndexOrThrow(_cursor, "dateAdded");
          final List<TrackEntity> _result = new ArrayList<TrackEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final TrackEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
            final String _tmpAlbumTitle;
            _tmpAlbumTitle = _cursor.getString(_cursorIndexOfAlbumTitle);
            final Long _tmpAlbumId;
            if (_cursor.isNull(_cursorIndexOfAlbumId)) {
              _tmpAlbumId = null;
            } else {
              _tmpAlbumId = _cursor.getLong(_cursorIndexOfAlbumId);
            }
            final Long _tmpArtistId;
            if (_cursor.isNull(_cursorIndexOfArtistId)) {
              _tmpArtistId = null;
            } else {
              _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            }
            final String _tmpUri;
            _tmpUri = _cursor.getString(_cursorIndexOfUri);
            final long _tmpDurationMs;
            _tmpDurationMs = _cursor.getLong(_cursorIndexOfDurationMs);
            final int _tmpTrackNumber;
            _tmpTrackNumber = _cursor.getInt(_cursorIndexOfTrackNumber);
            final int _tmpDiscNumber;
            _tmpDiscNumber = _cursor.getInt(_cursorIndexOfDiscNumber);
            final Integer _tmpYear;
            if (_cursor.isNull(_cursorIndexOfYear)) {
              _tmpYear = null;
            } else {
              _tmpYear = _cursor.getInt(_cursorIndexOfYear);
            }
            final String _tmpArtworkUri;
            if (_cursor.isNull(_cursorIndexOfArtworkUri)) {
              _tmpArtworkUri = null;
            } else {
              _tmpArtworkUri = _cursor.getString(_cursorIndexOfArtworkUri);
            }
            final String _tmpGenre;
            if (_cursor.isNull(_cursorIndexOfGenre)) {
              _tmpGenre = null;
            } else {
              _tmpGenre = _cursor.getString(_cursorIndexOfGenre);
            }
            final Integer _tmpBitrate;
            if (_cursor.isNull(_cursorIndexOfBitrate)) {
              _tmpBitrate = null;
            } else {
              _tmpBitrate = _cursor.getInt(_cursorIndexOfBitrate);
            }
            final Integer _tmpSampleRate;
            if (_cursor.isNull(_cursorIndexOfSampleRate)) {
              _tmpSampleRate = null;
            } else {
              _tmpSampleRate = _cursor.getInt(_cursorIndexOfSampleRate);
            }
            final boolean _tmpIsLossless;
            final int _tmp;
            _tmp = _cursor.getInt(_cursorIndexOfIsLossless);
            _tmpIsLossless = _tmp != 0;
            final long _tmpFileSize;
            _tmpFileSize = _cursor.getLong(_cursorIndexOfFileSize);
            final long _tmpDateAdded;
            _tmpDateAdded = _cursor.getLong(_cursorIndexOfDateAdded);
            _item = new TrackEntity(_tmpId,_tmpTitle,_tmpArtistName,_tmpAlbumTitle,_tmpAlbumId,_tmpArtistId,_tmpUri,_tmpDurationMs,_tmpTrackNumber,_tmpDiscNumber,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpBitrate,_tmpSampleRate,_tmpIsLossless,_tmpFileSize,_tmpDateAdded);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}

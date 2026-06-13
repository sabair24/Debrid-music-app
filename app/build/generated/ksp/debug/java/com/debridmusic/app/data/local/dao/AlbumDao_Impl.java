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
import com.debridmusic.app.data.local.entity.AlbumEntity;
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
public final class AlbumDao_Impl implements AlbumDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<AlbumEntity> __insertionAdapterOfAlbumEntity;

  private final EntityDeletionOrUpdateAdapter<AlbumEntity> __updateAdapterOfAlbumEntity;

  private final SharedSQLiteStatement __preparedStmtOfDeleteById;

  private final EntityUpsertionAdapter<AlbumEntity> __upsertionAdapterOfAlbumEntity;

  public AlbumDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfAlbumEntity = new EntityInsertionAdapter<AlbumEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR IGNORE INTO `albums` (`id`,`title`,`artistId`,`artistName`,`year`,`artworkUri`,`genre`,`musicBrainzId`) VALUES (nullif(?, 0),?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final AlbumEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindLong(3, entity.getArtistId());
        statement.bindString(4, entity.getArtistName());
        if (entity.getYear() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getGenre());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(8);
        } else {
          statement.bindString(8, entity.getMusicBrainzId());
        }
      }
    };
    this.__updateAdapterOfAlbumEntity = new EntityDeletionOrUpdateAdapter<AlbumEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE OR ABORT `albums` SET `id` = ?,`title` = ?,`artistId` = ?,`artistName` = ?,`year` = ?,`artworkUri` = ?,`genre` = ?,`musicBrainzId` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final AlbumEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindLong(3, entity.getArtistId());
        statement.bindString(4, entity.getArtistName());
        if (entity.getYear() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getGenre());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(8);
        } else {
          statement.bindString(8, entity.getMusicBrainzId());
        }
        statement.bindLong(9, entity.getId());
      }
    };
    this.__preparedStmtOfDeleteById = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "DELETE FROM albums WHERE id = ?";
        return _query;
      }
    };
    this.__upsertionAdapterOfAlbumEntity = new EntityUpsertionAdapter<AlbumEntity>(new EntityInsertionAdapter<AlbumEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT INTO `albums` (`id`,`title`,`artistId`,`artistName`,`year`,`artworkUri`,`genre`,`musicBrainzId`) VALUES (nullif(?, 0),?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final AlbumEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindLong(3, entity.getArtistId());
        statement.bindString(4, entity.getArtistName());
        if (entity.getYear() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getGenre());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(8);
        } else {
          statement.bindString(8, entity.getMusicBrainzId());
        }
      }
    }, new EntityDeletionOrUpdateAdapter<AlbumEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE `albums` SET `id` = ?,`title` = ?,`artistId` = ?,`artistName` = ?,`year` = ?,`artworkUri` = ?,`genre` = ?,`musicBrainzId` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final AlbumEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getTitle());
        statement.bindLong(3, entity.getArtistId());
        statement.bindString(4, entity.getArtistName());
        if (entity.getYear() == null) {
          statement.bindNull(5);
        } else {
          statement.bindLong(5, entity.getYear());
        }
        if (entity.getArtworkUri() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getArtworkUri());
        }
        if (entity.getGenre() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getGenre());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(8);
        } else {
          statement.bindString(8, entity.getMusicBrainzId());
        }
        statement.bindLong(9, entity.getId());
      }
    });
  }

  @Override
  public Object insert(final AlbumEntity album, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __insertionAdapterOfAlbumEntity.insertAndReturnId(album);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object update(final AlbumEntity album, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __updateAdapterOfAlbumEntity.handle(album);
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
  public Object upsert(final AlbumEntity album, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __upsertionAdapterOfAlbumEntity.upsertAndReturnId(album);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<AlbumEntity>> observeAll() {
    final String _sql = "SELECT * FROM albums ORDER BY title ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"albums"}, new Callable<List<AlbumEntity>>() {
      @Override
      @NonNull
      public List<AlbumEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final List<AlbumEntity> _result = new ArrayList<AlbumEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final AlbumEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final long _tmpArtistId;
            _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
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
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _item = new AlbumEntity(_tmpId,_tmpTitle,_tmpArtistId,_tmpArtistName,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpMusicBrainzId);
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
  public Flow<List<AlbumEntity>> observeByArtist(final long artistId) {
    final String _sql = "SELECT * FROM albums WHERE artistId = ? ORDER BY year ASC, title ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, artistId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"albums"}, new Callable<List<AlbumEntity>>() {
      @Override
      @NonNull
      public List<AlbumEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final List<AlbumEntity> _result = new ArrayList<AlbumEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final AlbumEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final long _tmpArtistId;
            _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
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
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _item = new AlbumEntity(_tmpId,_tmpTitle,_tmpArtistId,_tmpArtistName,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpMusicBrainzId);
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
  public Object getById(final long id, final Continuation<? super AlbumEntity> $completion) {
    final String _sql = "SELECT * FROM albums WHERE id = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, id);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<AlbumEntity>() {
      @Override
      @Nullable
      public AlbumEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final AlbumEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final long _tmpArtistId;
            _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
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
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _result = new AlbumEntity(_tmpId,_tmpTitle,_tmpArtistId,_tmpArtistName,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpMusicBrainzId);
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
  public Object getByTitleAndArtist(final String title, final long artistId,
      final Continuation<? super AlbumEntity> $completion) {
    final String _sql = "SELECT * FROM albums WHERE title = ? AND artistId = ? LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 2);
    int _argIndex = 1;
    _statement.bindString(_argIndex, title);
    _argIndex = 2;
    _statement.bindLong(_argIndex, artistId);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<AlbumEntity>() {
      @Override
      @Nullable
      public AlbumEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final AlbumEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final long _tmpArtistId;
            _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
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
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _result = new AlbumEntity(_tmpId,_tmpTitle,_tmpArtistId,_tmpArtistName,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpMusicBrainzId);
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
  public Flow<List<AlbumWithCount>> observeAlbumsWithTrackCount() {
    final String _sql = "\n"
            + "        SELECT al.*, COUNT(t.id) as trackCount\n"
            + "        FROM albums al\n"
            + "        LEFT JOIN tracks t ON t.albumId = al.id\n"
            + "        GROUP BY al.id\n"
            + "        ORDER BY al.title ASC\n"
            + "    ";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"albums",
        "tracks"}, new Callable<List<AlbumWithCount>>() {
      @Override
      @NonNull
      public List<AlbumWithCount> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfTitle = CursorUtil.getColumnIndexOrThrow(_cursor, "title");
          final int _cursorIndexOfArtistId = CursorUtil.getColumnIndexOrThrow(_cursor, "artistId");
          final int _cursorIndexOfArtistName = CursorUtil.getColumnIndexOrThrow(_cursor, "artistName");
          final int _cursorIndexOfYear = CursorUtil.getColumnIndexOrThrow(_cursor, "year");
          final int _cursorIndexOfArtworkUri = CursorUtil.getColumnIndexOrThrow(_cursor, "artworkUri");
          final int _cursorIndexOfGenre = CursorUtil.getColumnIndexOrThrow(_cursor, "genre");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final int _cursorIndexOfTrackCount = CursorUtil.getColumnIndexOrThrow(_cursor, "trackCount");
          final List<AlbumWithCount> _result = new ArrayList<AlbumWithCount>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final AlbumWithCount _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpTitle;
            _tmpTitle = _cursor.getString(_cursorIndexOfTitle);
            final long _tmpArtistId;
            _tmpArtistId = _cursor.getLong(_cursorIndexOfArtistId);
            final String _tmpArtistName;
            _tmpArtistName = _cursor.getString(_cursorIndexOfArtistName);
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
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            final int _tmpTrackCount;
            _tmpTrackCount = _cursor.getInt(_cursorIndexOfTrackCount);
            _item = new AlbumWithCount(_tmpId,_tmpTitle,_tmpArtistId,_tmpArtistName,_tmpYear,_tmpArtworkUri,_tmpGenre,_tmpMusicBrainzId,_tmpTrackCount);
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

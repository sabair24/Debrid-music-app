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
import com.debridmusic.app.data.local.entity.ArtistEntity;
import java.lang.Class;
import java.lang.Exception;
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
public final class ArtistDao_Impl implements ArtistDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<ArtistEntity> __insertionAdapterOfArtistEntity;

  private final EntityDeletionOrUpdateAdapter<ArtistEntity> __updateAdapterOfArtistEntity;

  private final SharedSQLiteStatement __preparedStmtOfDeleteById;

  private final EntityUpsertionAdapter<ArtistEntity> __upsertionAdapterOfArtistEntity;

  public ArtistDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfArtistEntity = new EntityInsertionAdapter<ArtistEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR IGNORE INTO `artists` (`id`,`name`,`biography`,`imageUri`,`musicBrainzId`) VALUES (nullif(?, 0),?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ArtistEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getName());
        if (entity.getBiography() == null) {
          statement.bindNull(3);
        } else {
          statement.bindString(3, entity.getBiography());
        }
        if (entity.getImageUri() == null) {
          statement.bindNull(4);
        } else {
          statement.bindString(4, entity.getImageUri());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getMusicBrainzId());
        }
      }
    };
    this.__updateAdapterOfArtistEntity = new EntityDeletionOrUpdateAdapter<ArtistEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE OR ABORT `artists` SET `id` = ?,`name` = ?,`biography` = ?,`imageUri` = ?,`musicBrainzId` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ArtistEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getName());
        if (entity.getBiography() == null) {
          statement.bindNull(3);
        } else {
          statement.bindString(3, entity.getBiography());
        }
        if (entity.getImageUri() == null) {
          statement.bindNull(4);
        } else {
          statement.bindString(4, entity.getImageUri());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getMusicBrainzId());
        }
        statement.bindLong(6, entity.getId());
      }
    };
    this.__preparedStmtOfDeleteById = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "DELETE FROM artists WHERE id = ?";
        return _query;
      }
    };
    this.__upsertionAdapterOfArtistEntity = new EntityUpsertionAdapter<ArtistEntity>(new EntityInsertionAdapter<ArtistEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT INTO `artists` (`id`,`name`,`biography`,`imageUri`,`musicBrainzId`) VALUES (nullif(?, 0),?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ArtistEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getName());
        if (entity.getBiography() == null) {
          statement.bindNull(3);
        } else {
          statement.bindString(3, entity.getBiography());
        }
        if (entity.getImageUri() == null) {
          statement.bindNull(4);
        } else {
          statement.bindString(4, entity.getImageUri());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getMusicBrainzId());
        }
      }
    }, new EntityDeletionOrUpdateAdapter<ArtistEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "UPDATE `artists` SET `id` = ?,`name` = ?,`biography` = ?,`imageUri` = ?,`musicBrainzId` = ? WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ArtistEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindString(2, entity.getName());
        if (entity.getBiography() == null) {
          statement.bindNull(3);
        } else {
          statement.bindString(3, entity.getBiography());
        }
        if (entity.getImageUri() == null) {
          statement.bindNull(4);
        } else {
          statement.bindString(4, entity.getImageUri());
        }
        if (entity.getMusicBrainzId() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getMusicBrainzId());
        }
        statement.bindLong(6, entity.getId());
      }
    });
  }

  @Override
  public Object insert(final ArtistEntity artist, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __insertionAdapterOfArtistEntity.insertAndReturnId(artist);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object update(final ArtistEntity artist, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __updateAdapterOfArtistEntity.handle(artist);
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
  public Object upsert(final ArtistEntity artist, final Continuation<? super Long> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Long>() {
      @Override
      @NonNull
      public Long call() throws Exception {
        __db.beginTransaction();
        try {
          final Long _result = __upsertionAdapterOfArtistEntity.upsertAndReturnId(artist);
          __db.setTransactionSuccessful();
          return _result;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<ArtistEntity>> observeAll() {
    final String _sql = "SELECT * FROM artists ORDER BY name ASC";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"artists"}, new Callable<List<ArtistEntity>>() {
      @Override
      @NonNull
      public List<ArtistEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfBiography = CursorUtil.getColumnIndexOrThrow(_cursor, "biography");
          final int _cursorIndexOfImageUri = CursorUtil.getColumnIndexOrThrow(_cursor, "imageUri");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final List<ArtistEntity> _result = new ArrayList<ArtistEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final ArtistEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpBiography;
            if (_cursor.isNull(_cursorIndexOfBiography)) {
              _tmpBiography = null;
            } else {
              _tmpBiography = _cursor.getString(_cursorIndexOfBiography);
            }
            final String _tmpImageUri;
            if (_cursor.isNull(_cursorIndexOfImageUri)) {
              _tmpImageUri = null;
            } else {
              _tmpImageUri = _cursor.getString(_cursorIndexOfImageUri);
            }
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _item = new ArtistEntity(_tmpId,_tmpName,_tmpBiography,_tmpImageUri,_tmpMusicBrainzId);
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
  public Object getById(final long id, final Continuation<? super ArtistEntity> $completion) {
    final String _sql = "SELECT * FROM artists WHERE id = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindLong(_argIndex, id);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<ArtistEntity>() {
      @Override
      @Nullable
      public ArtistEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfBiography = CursorUtil.getColumnIndexOrThrow(_cursor, "biography");
          final int _cursorIndexOfImageUri = CursorUtil.getColumnIndexOrThrow(_cursor, "imageUri");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final ArtistEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpBiography;
            if (_cursor.isNull(_cursorIndexOfBiography)) {
              _tmpBiography = null;
            } else {
              _tmpBiography = _cursor.getString(_cursorIndexOfBiography);
            }
            final String _tmpImageUri;
            if (_cursor.isNull(_cursorIndexOfImageUri)) {
              _tmpImageUri = null;
            } else {
              _tmpImageUri = _cursor.getString(_cursorIndexOfImageUri);
            }
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _result = new ArtistEntity(_tmpId,_tmpName,_tmpBiography,_tmpImageUri,_tmpMusicBrainzId);
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
  public Object getByName(final String name, final Continuation<? super ArtistEntity> $completion) {
    final String _sql = "SELECT * FROM artists WHERE name = ? LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, name);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<ArtistEntity>() {
      @Override
      @Nullable
      public ArtistEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfBiography = CursorUtil.getColumnIndexOrThrow(_cursor, "biography");
          final int _cursorIndexOfImageUri = CursorUtil.getColumnIndexOrThrow(_cursor, "imageUri");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final ArtistEntity _result;
          if (_cursor.moveToFirst()) {
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpBiography;
            if (_cursor.isNull(_cursorIndexOfBiography)) {
              _tmpBiography = null;
            } else {
              _tmpBiography = _cursor.getString(_cursorIndexOfBiography);
            }
            final String _tmpImageUri;
            if (_cursor.isNull(_cursorIndexOfImageUri)) {
              _tmpImageUri = null;
            } else {
              _tmpImageUri = _cursor.getString(_cursorIndexOfImageUri);
            }
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _result = new ArtistEntity(_tmpId,_tmpName,_tmpBiography,_tmpImageUri,_tmpMusicBrainzId);
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
  public Flow<List<ArtistEntity>> observeArtistsWithTracks() {
    final String _sql = "\n"
            + "        SELECT a.* FROM artists a\n"
            + "        WHERE a.id IN (SELECT DISTINCT artistId FROM tracks WHERE artistId IS NOT NULL)\n"
            + "        ORDER BY a.name ASC\n"
            + "    ";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"artists",
        "tracks"}, new Callable<List<ArtistEntity>>() {
      @Override
      @NonNull
      public List<ArtistEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfBiography = CursorUtil.getColumnIndexOrThrow(_cursor, "biography");
          final int _cursorIndexOfImageUri = CursorUtil.getColumnIndexOrThrow(_cursor, "imageUri");
          final int _cursorIndexOfMusicBrainzId = CursorUtil.getColumnIndexOrThrow(_cursor, "musicBrainzId");
          final List<ArtistEntity> _result = new ArrayList<ArtistEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final ArtistEntity _item;
            final long _tmpId;
            _tmpId = _cursor.getLong(_cursorIndexOfId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpBiography;
            if (_cursor.isNull(_cursorIndexOfBiography)) {
              _tmpBiography = null;
            } else {
              _tmpBiography = _cursor.getString(_cursorIndexOfBiography);
            }
            final String _tmpImageUri;
            if (_cursor.isNull(_cursorIndexOfImageUri)) {
              _tmpImageUri = null;
            } else {
              _tmpImageUri = _cursor.getString(_cursorIndexOfImageUri);
            }
            final String _tmpMusicBrainzId;
            if (_cursor.isNull(_cursorIndexOfMusicBrainzId)) {
              _tmpMusicBrainzId = null;
            } else {
              _tmpMusicBrainzId = _cursor.getString(_cursorIndexOfMusicBrainzId);
            }
            _item = new ArtistEntity(_tmpId,_tmpName,_tmpBiography,_tmpImageUri,_tmpMusicBrainzId);
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

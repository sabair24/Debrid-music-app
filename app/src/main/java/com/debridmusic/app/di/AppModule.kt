package com.debridmusic.app.di

import android.content.Context
import androidx.room.Room
import com.debridmusic.app.data.local.AppDatabase
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides @Singleton
    fun provideDatabase(@ApplicationContext ctx: Context): AppDatabase =
        Room.databaseBuilder(ctx, AppDatabase::class.java, "debrid_music.db")
            .fallbackToDestructiveMigration()
            .build()

    @Provides fun provideTrackDao(db: AppDatabase): TrackDao = db.trackDao()
    @Provides fun provideAlbumDao(db: AppDatabase): AlbumDao = db.albumDao()
    @Provides fun provideArtistDao(db: AppDatabase): ArtistDao = db.artistDao()

    @Provides @Singleton
    fun provideOkHttpClient(): OkHttpClient =
        OkHttpClient.Builder()
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

    @Provides @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://api.torbox.app/v1/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

}

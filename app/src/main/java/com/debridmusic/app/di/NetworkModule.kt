package com.debridmusic.app.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.debridmusic.app.data.remote.api.CoverArtArchiveApi
import com.debridmusic.app.data.remote.api.LastFmApi
import com.debridmusic.app.data.remote.api.MusicBrainzApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import javax.inject.Named
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides @Singleton
    fun provideDataStore(@ApplicationContext ctx: Context): DataStore<Preferences> = ctx.dataStore

    @Provides @Singleton @Named("musicbrainz")
    fun provideMusicBrainzRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://musicbrainz.org/ws/2/")
            .client(
                okHttpClient.newBuilder()
                    .addInterceptor { chain ->
                        val req = chain.request().newBuilder()
                            .header("User-Agent", "DebridMusic/1.0 (android)")
                            .build()
                        chain.proceed(req)
                    }
                    .build()
            )
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton @Named("coverart")
    fun provideCoverArtRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://coverartarchive.org/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton @Named("lastfm")
    fun provideLastFmRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://ws.audioscrobbler.com/2.0/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideMusicBrainzApi(@Named("musicbrainz") retrofit: Retrofit): MusicBrainzApi =
        retrofit.create(MusicBrainzApi::class.java)

    @Provides @Singleton
    fun provideCoverArtApi(@Named("coverart") retrofit: Retrofit): CoverArtArchiveApi =
        retrofit.create(CoverArtArchiveApi::class.java)

    @Provides @Singleton
    fun provideLastFmApi(@Named("lastfm") retrofit: Retrofit): LastFmApi =
        retrofit.create(LastFmApi::class.java)
}

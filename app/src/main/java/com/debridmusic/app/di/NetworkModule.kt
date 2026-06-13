package com.debridmusic.app.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.debridmusic.app.data.remote.api.BitSearchApi
import com.debridmusic.app.data.remote.api.CoverArtArchiveApi
import com.debridmusic.app.data.remote.api.DeezerApi
import com.debridmusic.app.data.remote.api.TheAudioDbApi
import com.debridmusic.app.data.remote.api.LastFmApi
import com.debridmusic.app.data.remote.api.LastFmScrobbleApi
import com.debridmusic.app.data.remote.api.MusicBrainzApi
import com.debridmusic.app.data.remote.api.TorBoxApi
import com.debridmusic.app.torbox.TorBoxAuthInterceptor
import com.debridmusic.app.update.GitHubApi
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

    @Provides @Singleton
    fun provideLastFmScrobbleApi(@Named("lastfm") retrofit: Retrofit): LastFmScrobbleApi =
        retrofit.create(LastFmScrobbleApi::class.java)

    @Provides @Singleton @Named("torbox")
    fun provideTorBoxRetrofit(
        okHttpClient: OkHttpClient,
        authInterceptor: TorBoxAuthInterceptor,
    ): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://api.torbox.app/v1/")
            .client(
                okHttpClient.newBuilder()
                    .addInterceptor(authInterceptor)
                    .build()
            )
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideTorBoxApi(@Named("torbox") retrofit: Retrofit): TorBoxApi =
        retrofit.create(TorBoxApi::class.java)

    @Provides @Singleton @Named("bitsearch")
    fun provideBitSearchRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://bitsearch.eu/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideBitSearchApi(@Named("bitsearch") retrofit: Retrofit): BitSearchApi =
        retrofit.create(BitSearchApi::class.java)

    @Provides @Singleton @Named("github")
    fun provideGitHubRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://api.github.com/")
            .client(
                okHttpClient.newBuilder()
                    .addInterceptor { chain ->
                        // GitHub's API rejects requests without a User-Agent (HTTP 403).
                        val req = chain.request().newBuilder()
                            .header("User-Agent", "DebridMusic-Android")
                            .header("Accept", "application/vnd.github+json")
                            .build()
                        chain.proceed(req)
                    }
                    .build()
            )
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideGitHubApi(@Named("github") retrofit: Retrofit): GitHubApi =
        retrofit.create(GitHubApi::class.java)

    // ── Metadata enrichment (keyless) ───────────────────────────────────────────
    @Provides @Singleton @Named("deezer")
    fun provideDeezerRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            .baseUrl("https://api.deezer.com/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideDeezerApi(@Named("deezer") retrofit: Retrofit): DeezerApi =
        retrofit.create(DeezerApi::class.java)

    @Provides @Singleton @Named("theaudiodb")
    fun provideTheAudioDbRetrofit(okHttpClient: OkHttpClient): Retrofit =
        Retrofit.Builder()
            // "123" is TheAudioDB's free public test key.
            .baseUrl("https://www.theaudiodb.com/api/v1/json/123/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

    @Provides @Singleton
    fun provideTheAudioDbApi(@Named("theaudiodb") retrofit: Retrofit): TheAudioDbApi =
        retrofit.create(TheAudioDbApi::class.java)
}

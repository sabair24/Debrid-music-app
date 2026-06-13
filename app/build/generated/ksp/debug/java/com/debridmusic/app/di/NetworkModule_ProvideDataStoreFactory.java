package com.debridmusic.app.di;

import android.content.Context;
import androidx.datastore.core.DataStore;
import androidx.datastore.preferences.core.Preferences;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
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
public final class NetworkModule_ProvideDataStoreFactory implements Factory<DataStore<Preferences>> {
  private final Provider<Context> ctxProvider;

  public NetworkModule_ProvideDataStoreFactory(Provider<Context> ctxProvider) {
    this.ctxProvider = ctxProvider;
  }

  @Override
  public DataStore<Preferences> get() {
    return provideDataStore(ctxProvider.get());
  }

  public static NetworkModule_ProvideDataStoreFactory create(Provider<Context> ctxProvider) {
    return new NetworkModule_ProvideDataStoreFactory(ctxProvider);
  }

  public static DataStore<Preferences> provideDataStore(Context ctx) {
    return Preconditions.checkNotNullFromProvides(NetworkModule.INSTANCE.provideDataStore(ctx));
  }
}

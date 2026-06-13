package com.debridmusic.app.data.local;

import androidx.datastore.core.DataStore;
import androidx.datastore.preferences.core.Preferences;
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
public final class SettingsStore_Factory implements Factory<SettingsStore> {
  private final Provider<DataStore<Preferences>> dataStoreProvider;

  public SettingsStore_Factory(Provider<DataStore<Preferences>> dataStoreProvider) {
    this.dataStoreProvider = dataStoreProvider;
  }

  @Override
  public SettingsStore get() {
    return newInstance(dataStoreProvider.get());
  }

  public static SettingsStore_Factory create(Provider<DataStore<Preferences>> dataStoreProvider) {
    return new SettingsStore_Factory(dataStoreProvider);
  }

  public static SettingsStore newInstance(DataStore<Preferences> dataStore) {
    return new SettingsStore(dataStore);
  }
}

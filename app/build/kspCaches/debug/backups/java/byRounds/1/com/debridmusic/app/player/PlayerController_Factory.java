package com.debridmusic.app.player;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
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
public final class PlayerController_Factory implements Factory<PlayerController> {
  private final Provider<Context> contextProvider;

  private final Provider<CrossFadeManager> crossFadeManagerProvider;

  private final Provider<ScrobbleManager> scrobbleManagerProvider;

  public PlayerController_Factory(Provider<Context> contextProvider,
      Provider<CrossFadeManager> crossFadeManagerProvider,
      Provider<ScrobbleManager> scrobbleManagerProvider) {
    this.contextProvider = contextProvider;
    this.crossFadeManagerProvider = crossFadeManagerProvider;
    this.scrobbleManagerProvider = scrobbleManagerProvider;
  }

  @Override
  public PlayerController get() {
    return newInstance(contextProvider.get(), crossFadeManagerProvider.get(), scrobbleManagerProvider.get());
  }

  public static PlayerController_Factory create(Provider<Context> contextProvider,
      Provider<CrossFadeManager> crossFadeManagerProvider,
      Provider<ScrobbleManager> scrobbleManagerProvider) {
    return new PlayerController_Factory(contextProvider, crossFadeManagerProvider, scrobbleManagerProvider);
  }

  public static PlayerController newInstance(Context context, CrossFadeManager crossFadeManager,
      ScrobbleManager scrobbleManager) {
    return new PlayerController(context, crossFadeManager, scrobbleManager);
  }
}

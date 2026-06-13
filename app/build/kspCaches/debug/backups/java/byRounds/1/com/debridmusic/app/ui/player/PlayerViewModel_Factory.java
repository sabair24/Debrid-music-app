package com.debridmusic.app.ui.player;

import com.debridmusic.app.player.PlayerController;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
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
public final class PlayerViewModel_Factory implements Factory<PlayerViewModel> {
  private final Provider<PlayerController> playerControllerProvider;

  public PlayerViewModel_Factory(Provider<PlayerController> playerControllerProvider) {
    this.playerControllerProvider = playerControllerProvider;
  }

  @Override
  public PlayerViewModel get() {
    return newInstance(playerControllerProvider.get());
  }

  public static PlayerViewModel_Factory create(
      Provider<PlayerController> playerControllerProvider) {
    return new PlayerViewModel_Factory(playerControllerProvider);
  }

  public static PlayerViewModel newInstance(PlayerController playerController) {
    return new PlayerViewModel(playerController);
  }
}

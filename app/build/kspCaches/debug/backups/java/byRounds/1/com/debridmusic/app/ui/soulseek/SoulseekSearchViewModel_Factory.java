package com.debridmusic.app.ui.soulseek;

import com.debridmusic.app.player.PlayerController;
import com.debridmusic.app.soulseek.SoulseekRepository;
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
public final class SoulseekSearchViewModel_Factory implements Factory<SoulseekSearchViewModel> {
  private final Provider<SoulseekRepository> repositoryProvider;

  private final Provider<PlayerController> playerControllerProvider;

  public SoulseekSearchViewModel_Factory(Provider<SoulseekRepository> repositoryProvider,
      Provider<PlayerController> playerControllerProvider) {
    this.repositoryProvider = repositoryProvider;
    this.playerControllerProvider = playerControllerProvider;
  }

  @Override
  public SoulseekSearchViewModel get() {
    return newInstance(repositoryProvider.get(), playerControllerProvider.get());
  }

  public static SoulseekSearchViewModel_Factory create(
      Provider<SoulseekRepository> repositoryProvider,
      Provider<PlayerController> playerControllerProvider) {
    return new SoulseekSearchViewModel_Factory(repositoryProvider, playerControllerProvider);
  }

  public static SoulseekSearchViewModel newInstance(SoulseekRepository repository,
      PlayerController playerController) {
    return new SoulseekSearchViewModel(repository, playerController);
  }
}

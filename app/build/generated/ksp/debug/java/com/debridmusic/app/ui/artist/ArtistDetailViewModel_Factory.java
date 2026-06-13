package com.debridmusic.app.ui.artist;

import androidx.lifecycle.SavedStateHandle;
import com.debridmusic.app.data.repository.MusicRepository;
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
public final class ArtistDetailViewModel_Factory implements Factory<ArtistDetailViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<MusicRepository> repositoryProvider;

  private final Provider<PlayerController> playerControllerProvider;

  public ArtistDetailViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<MusicRepository> repositoryProvider,
      Provider<PlayerController> playerControllerProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repositoryProvider = repositoryProvider;
    this.playerControllerProvider = playerControllerProvider;
  }

  @Override
  public ArtistDetailViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repositoryProvider.get(), playerControllerProvider.get());
  }

  public static ArtistDetailViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<MusicRepository> repositoryProvider,
      Provider<PlayerController> playerControllerProvider) {
    return new ArtistDetailViewModel_Factory(savedStateHandleProvider, repositoryProvider, playerControllerProvider);
  }

  public static ArtistDetailViewModel newInstance(SavedStateHandle savedStateHandle,
      MusicRepository repository, PlayerController playerController) {
    return new ArtistDetailViewModel(savedStateHandle, repository, playerController);
  }
}

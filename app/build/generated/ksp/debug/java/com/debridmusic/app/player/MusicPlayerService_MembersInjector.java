package com.debridmusic.app.player;

import dagger.MembersInjector;
import dagger.internal.DaggerGenerated;
import dagger.internal.InjectedFieldSignature;
import dagger.internal.QualifierMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class MusicPlayerService_MembersInjector implements MembersInjector<MusicPlayerService> {
  private final Provider<EqController> eqControllerProvider;

  public MusicPlayerService_MembersInjector(Provider<EqController> eqControllerProvider) {
    this.eqControllerProvider = eqControllerProvider;
  }

  public static MembersInjector<MusicPlayerService> create(
      Provider<EqController> eqControllerProvider) {
    return new MusicPlayerService_MembersInjector(eqControllerProvider);
  }

  @Override
  public void injectMembers(MusicPlayerService instance) {
    injectEqController(instance, eqControllerProvider.get());
  }

  @InjectedFieldSignature("com.debridmusic.app.player.MusicPlayerService.eqController")
  public static void injectEqController(MusicPlayerService instance, EqController eqController) {
    instance.eqController = eqController;
  }
}

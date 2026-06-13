package com.debridmusic.app.soulseek;

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
public final class SoulseekClient_Factory implements Factory<SoulseekClient> {
  private final Provider<Context> contextProvider;

  public SoulseekClient_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public SoulseekClient get() {
    return newInstance(contextProvider.get());
  }

  public static SoulseekClient_Factory create(Provider<Context> contextProvider) {
    return new SoulseekClient_Factory(contextProvider);
  }

  public static SoulseekClient newInstance(Context context) {
    return new SoulseekClient(context);
  }
}

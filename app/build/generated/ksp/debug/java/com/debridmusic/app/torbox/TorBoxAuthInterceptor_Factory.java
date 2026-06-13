package com.debridmusic.app.torbox;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;

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
public final class TorBoxAuthInterceptor_Factory implements Factory<TorBoxAuthInterceptor> {
  @Override
  public TorBoxAuthInterceptor get() {
    return newInstance();
  }

  public static TorBoxAuthInterceptor_Factory create() {
    return InstanceHolder.INSTANCE;
  }

  public static TorBoxAuthInterceptor newInstance() {
    return new TorBoxAuthInterceptor();
  }

  private static final class InstanceHolder {
    private static final TorBoxAuthInterceptor_Factory INSTANCE = new TorBoxAuthInterceptor_Factory();
  }
}

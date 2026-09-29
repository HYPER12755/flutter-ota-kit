# flutter_ota_kit loads libapp.so and hooks engine internals reflectively.
# Keep the private field/target members R8 would otherwise rename or strip.
-keepclassmembers class io.flutter.embedding.engine.FlutterInjector {
    private ** flutterJniFactory;
}
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.engine.FlutterJNI$Factory { *; }

# Plugin's own classes are resolved by name from native/manifest wiring.
-keep class com.flutter_patcher.flutter_patcher.** { *; }

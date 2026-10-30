# Ignore optional ML Kit Text Recognition language model packages
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# Keep Flutter TTS and audio plugins
-keep class com.tundralabs.fluttertts.** { *; }

# General Flutter & native plugin proguard rules
-dontwarn io.flutter.plugin.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.** { *; }

# Flutter engine deferred components & Play Core split install
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Flutter engine & plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent R8 from obfuscating SharedPreferences and Kotlin coroutine signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class * extends kotlin.coroutines.jvm.internal.ContinuationImpl { *; }

# flutter_uvc_camera & libuvc JNI bindings
-keep class com.jiangdg.uvc.** { *; }
-keep class com.jiangdg.usb.** { *; }
-keep class com.jiangdg.uvc.UVCCamera { native <methods>; long mNativePtr; }
-keep class com.jiangdg.uvc.IStatusCallback { *; }
-keep interface com.jiangdg.uvc.IButtonCallback { *; }

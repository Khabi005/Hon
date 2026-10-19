# LuaJ bundles an optional JSR-223 bridge that Hon never instantiates on Android.
# Android does not ship javax.script, so R8 may ignore that optional reference.
-dontwarn javax.script.ScriptEngineFactory

# LuaJ VM and libraries are loaded reflectively via LibFunction.bind and Class.forName.
# R8 cannot infer these reflective references. Removing classes (like Bit32Lib$Bit32LibV)
# crashes sources in release. Keep all LuaJ classes and constructors intact.
-keep class org.luaj.vm2.** { *; }
-keepclassmembers class org.luaj.vm2.** { *; }
-dontwarn org.luaj.vm2.**

# Source scripts call whitelisted public DOM and HTTP capabilities.
-keep class org.jsoup.** { *; }
-keepclassmembers class org.jsoup.** { public *; }
-keepnames class okhttp3.**
-keepclassmembers class okhttp3.** { public *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# WorkManager Workers instantiated reflectively by Android WorkManager
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class com.hon.reader.hon.HonDownloadWorker { *; }

# Readium Toolkit components
-keep class org.readium.r2.** { *; }
-dontwarn org.readium.r2.**

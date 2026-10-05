# Flutter 基础混淆保留规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# JNI & 本地原生方法保留
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter 插件机制保留
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }

# 忽略第三方库无害警告
-dontwarn io.flutter.**
-dontwarn javax.annotation.**

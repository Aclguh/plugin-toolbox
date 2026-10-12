import 'plugin_native_bridge.dart';

/// LuaHostDelegate 的 AI 能力域方法集：宿主统一 AI 网关的
/// 可用性查询、一次性对话与流式对话转发。
mixin PluginHostAiDelegate {
  PluginNativeBridge get nativeBridge;

  Future<bool> isAiAvailable() => nativeBridge.isAiAvailable();

  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) =>
      nativeBridge.aiChat(
          messages: messages, model: model, temperature: temperature);

  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) =>
      nativeBridge.aiStreamChat(
          messages: messages, model: model, temperature: temperature);
}

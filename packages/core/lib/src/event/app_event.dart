import 'package:equatable/equatable.dart';

abstract class AppEvent extends Equatable {
  final DateTime timestamp;
  AppEvent() : timestamp = DateTime.now();

  @override
  List<Object?> get props => [timestamp];
}

class PluginInstalledEvent extends AppEvent {
  final String pluginId;
  PluginInstalledEvent(this.pluginId);
  @override
  List<Object?> get props => [pluginId, ...super.props];
}

class PluginUninstalledEvent extends AppEvent {
  final String pluginId;
  PluginUninstalledEvent(this.pluginId);
  @override
  List<Object?> get props => [pluginId, ...super.props];
}

/// 卸载请求事件：注册中心发出，由安装器监听并执行沙箱目录清理
class PluginUninstallRequestedEvent extends AppEvent {
  final String pluginId;
  PluginUninstallRequestedEvent(this.pluginId);
  @override
  List<Object?> get props => [pluginId, ...super.props];
}

class PluginStateChangedEvent extends AppEvent {
  final String pluginId;
  final bool isEnabled;
  PluginStateChangedEvent(this.pluginId, this.isEnabled);
  @override
  List<Object?> get props => [pluginId, isEnabled, ...super.props];
}

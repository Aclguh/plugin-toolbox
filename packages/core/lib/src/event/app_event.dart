import 'package:equatable/equatable.dart';

/// 系统及插件生命周期事件基类。
///
/// 保留 [timestamp] 记录事件发生时刻以供日志与观测诊断，但不将 [timestamp] 纳入 [props]，
/// 确保相同业务载荷的事件实例符合 Equatable 值对象等价语义。
abstract class AppEvent extends Equatable {
  final DateTime timestamp;
  AppEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [];
}

/// 插件已安装完成事件
class PluginInstalledEvent extends AppEvent {
  final String pluginId;
  PluginInstalledEvent(this.pluginId, {super.timestamp});
  @override
  List<Object?> get props => [pluginId];
}

/// 插件已彻底卸载事件
class PluginUninstalledEvent extends AppEvent {
  final String pluginId;
  PluginUninstalledEvent(this.pluginId, {super.timestamp});
  @override
  List<Object?> get props => [pluginId];
}

/// 卸载请求事件：注册中心发出，由安装器监听并执行沙箱目录清理
class PluginUninstallRequestedEvent extends AppEvent {
  final String pluginId;
  PluginUninstallRequestedEvent(this.pluginId, {super.timestamp});
  @override
  List<Object?> get props => [pluginId];
}

/// 插件启用/禁用状态变更事件
class PluginStateChangedEvent extends AppEvent {
  final String pluginId;
  final bool isEnabled;
  PluginStateChangedEvent(this.pluginId, this.isEnabled, {super.timestamp});
  @override
  List<Object?> get props => [pluginId, isEnabled];
}

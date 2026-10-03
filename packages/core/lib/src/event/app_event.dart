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

class PluginStateChangedEvent extends AppEvent {
  final String pluginId;
  final bool isEnabled;
  PluginStateChangedEvent(this.pluginId, this.isEnabled);
  @override
  List<Object?> get props => [pluginId, isEnabled, ...super.props];
}

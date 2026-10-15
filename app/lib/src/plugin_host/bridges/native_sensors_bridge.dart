import 'bridge_base.dart';

/// 设备运动与环境传感器原生能力领域扩展
mixin NativeSensorsBridge on NativeBridgeBase {
  final Map<String, Map<String, dynamic>> _sensorCache = {};

  Future<bool> startSensor(String type) =>
      invoke<bool>('startSensor', false, {'type': type});

  Future<bool> stopSensor(String type) =>
      invoke<bool>('stopSensor', false, {'type': type});

  Future<Map<String, dynamic>?> getSensorData(String type) async {
    final res = await invokeMap('getSensorData', {'type': type});
    if (res != null) {
      _sensorCache[type] = res;
      return res;
    }
    return _sensorCache[type];
  }
}

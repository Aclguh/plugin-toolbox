import 'dart:io';

import 'bridges/bridge_base.dart';
import 'bridges/native_device_bridge.dart';
import 'bridges/native_hardware_bridge.dart';
import 'bridges/native_media_bridge.dart';
import 'bridges/native_notification_bridge.dart';
import 'bridges/native_sensors_bridge.dart';

export 'bridges/bridge_base.dart';
export 'bridges/native_device_bridge.dart';
export 'bridges/native_hardware_bridge.dart';
export 'bridges/native_media_bridge.dart';
export 'bridges/native_notification_bridge.dart';
export 'bridges/native_sensors_bridge.dart';

/// 动态插件与宿主 Android 原生及系统能力调度的专用桥接层。
///
/// 采用清晰的模块领域组合设计，由各专属领域能力扩展汇聚而成：
/// - [NativeDeviceBridge]：手电筒、屏幕显示、电池与系统分享
/// - [NativeMediaBridge]：音频录放、TTS、拍照录像、相册选取与图像视觉
/// - [NativeNotificationBridge]：本地系统通知推送与计划任务
/// - [NativeSensorsBridge]：运动与环境物理传感器
/// - [NativeHardwareBridge]：蓝牙低功耗 (BLE)、近场通信 (NFC)、生物认证与定位
class PluginNativeBridge extends NativeBridgeBase
    with
        NativeDeviceBridge,
        NativeMediaBridge,
        NativeNotificationBridge,
        NativeSensorsBridge,
        NativeHardwareBridge {
  PluginNativeBridge({
    required super.pluginRootDir,
    super.storageQuotaMb = 50,
    super.nativeChannel,
    super.logger,
  });

  /// 剔除路径分隔符与连续点号，净化文件选择器传入的文件名
  static String sanitizePickedFileName(String name) =>
      NativeBridgeBase.sanitizePickedFileName(name);

  /// 重名时自动追加序号后缀，避免静默覆盖已有文件
  static String uniqueSandboxFileName(Directory dir, String fileName) =>
      NativeBridgeBase.uniqueSandboxFileName(dir, fileName);

  /// 核对沙箱在追加 [additionalBytes] 后是否仍处于存储配额内
  bool hasQuotaFor(int additionalBytes) => hasSandboxQuotaFor(additionalBytes);

  /// 集中释放设备与硬件占用的活跃状态
  void dispose() {
    disposeDeviceBridge();
    stopSensor('all');
    stopAudio();
    stopBluetoothScan();
  }
}

/// 插件声明与请求的系统/宿主权限
enum PluginPermission {
  clipboard('剪贴板', '允许读取与写入系统剪贴板'),
  storage('本地存储', '允许在独立沙箱中存储持久化数据'),
  network('网络访问', '允许发起 HTTP/HTTPS 网络请求'),
  camera('相机', '允许调用系统相机'),
  photoLibrary('相册', '允许读取设备相册图片'),
  torch('手电筒', '允许控制设备闪光灯与手电筒'),
  sensor('传感器', '允许读取设备运动与方向传感器数据'),
  notification('本地通知', '允许发送本地系统通知'),
  biometrics('生物认证', '允许调用系统指纹或面容识别进行身份核验'),
  microphone('麦克风录音', '允许使用设备麦克风录音与实时声音分贝感知'),
  screen('屏幕控制', '允许控制屏幕常亮与屏幕亮度调节'),
  location('地理位置', '允许获取设备定位坐标与海拔信息'),
  bluetooth('蓝牙低功耗', '允许扫描、连接与读写 BLE 外设设备'),
  nfc('近场通信', '允许读取与写入 NFC 标签数据'),
  ai('AI 模型网关', '允许调用宿主配置的统一大语言模型服务'),
  database('结构化存储', '允许在独立沙箱中创建与读写 SQLite 数据库'),
  ipc('跨插件互通', '允许与其他已安装插件通信与管道调用');

  const PluginPermission(this.label, this.description);

  final String label;
  final String description;

  static PluginPermission? fromString(String value) {
    switch (value.toLowerCase()) {
      case 'clipboard':
        return PluginPermission.clipboard;
      case 'storage':
        return PluginPermission.storage;
      case 'network':
        return PluginPermission.network;
      case 'camera':
        return PluginPermission.camera;
      case 'photo_library':
      case 'photolibrary':
        return PluginPermission.photoLibrary;
      case 'torch':
        return PluginPermission.torch;
      case 'sensor':
        return PluginPermission.sensor;
      case 'notification':
        return PluginPermission.notification;
      case 'biometrics':
        return PluginPermission.biometrics;
      case 'microphone':
        return PluginPermission.microphone;
      case 'screen':
        return PluginPermission.screen;
      case 'location':
        return PluginPermission.location;
      case 'bluetooth':
        return PluginPermission.bluetooth;
      case 'nfc':
        return PluginPermission.nfc;
      case 'ai':
        return PluginPermission.ai;
      case 'database':
      case 'db':
        return PluginPermission.database;
      case 'ipc':
        return PluginPermission.ipc;
      default:
        return null;
    }
  }
}

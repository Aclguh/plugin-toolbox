/// 插件声明与请求的系统/宿主权限
enum PluginPermission {
  clipboard('剪贴板', '允许读取与写入系统剪贴板'),
  storage('本地存储', '允许在独立沙箱中存储持久化数据'),
  network('网络访问', '允许发起 HTTP/HTTPS 网络请求'),
  camera('相机', '允许调用系统相机'),
  photoLibrary('相册', '允许读取设备相册图片'),
  torch('手电筒', '允许控制设备闪光灯与手电筒'),
  sensor('传感器', '允许读取设备运动与方向传感器数据'),
  notification('本地通知', '允许发送本地系统通知');

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
      default:
        return null;
    }
  }
}

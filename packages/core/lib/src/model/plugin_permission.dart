/// 插件声明与请求的系统/宿主权限
enum PluginPermission {
  clipboard('剪贴板', '允许读取与写入系统剪贴板'),
  storage('本地存储', '允许在独立沙箱中存储持久化数据'),
  network('网络访问', '允许发起 HTTP/HTTPS 网络请求'),
  camera('相机', '允许调用系统相机'),
  photoLibrary('相册', '允许读取设备相册图片');

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
      default:
        return null;
    }
  }
}

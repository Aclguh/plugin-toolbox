import 'bridge_base.dart';

/// 系统本地通知调度领域扩展
mixin NativeNotificationBridge on NativeBridgeBase {
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) {
    return invoke<int>('showNotification', -1, {
      'title': title,
      'body': body,
      'payload': payload,
    });
  }

  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) {
    return invoke<int>('scheduleNotification', -1, {
      'title': title,
      'body': body,
      'delaySeconds': delaySeconds,
      'payload': payload,
    });
  }

  Future<bool> cancelNotification(int id) {
    return invoke<bool>('cancelNotification', false, {'id': id});
  }

  Future<bool> cancelAllNotifications() {
    return invoke<bool>('cancelAllNotifications', false);
  }
}

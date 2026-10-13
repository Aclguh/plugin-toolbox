import 'package:flutter/material.dart';

/// 插件宿主统一对话框与交互服务
class PluginDialogService {
  static void showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> showAlert(
      BuildContext context, String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  static Future<bool> showConfirm(
      BuildContext context, String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  static Future<String?> showPrompt(
    BuildContext context, {
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    final controller = TextEditingController(text: defaultValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  static Future<Map<String, dynamic>?> showPickItem(
    BuildContext context, {
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return SimpleDialogOption(
            onPressed: () =>
                Navigator.of(ctx).pop({'index': idx, 'text': item}),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(item),
            ),
          );
        }).toList(),
      ),
    );
  }

  static Future<Map<String, dynamic>?> showBottomSheet(
    BuildContext context, {
    required String title,
    required List<String> items,
  }) async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return ListTile(
                title: Text(item, textAlign: TextAlign.center),
                onTap: () =>
                    Navigator.of(ctx).pop({'index': idx, 'text': item}),
              );
            }),
          ],
        ),
      ),
    );
  }

  static Future<String?> pickDate(
    BuildContext context, {
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async {
    DateTime parseDate(String? s, DateTime fallback) {
      if (s == null || s.isEmpty) return fallback;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return fallback;
      }
    }

    final now = DateTime.now();
    final first = parseDate(firstDate, DateTime(1900, 1, 1));
    final last = parseDate(lastDate, DateTime(2100, 12, 31));
    var init = parseDate(initialDate, now);
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return null;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<String?> pickTime(
    BuildContext context, {
    String? initialTime,
  }) async {
    TimeOfDay parseTime(String? s) {
      if (s != null && s.contains(':')) {
        final parts = s.split(':');
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
        }
      }
      return TimeOfDay.now();
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: parseTime(initialTime),
    );
    if (picked == null) return null;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

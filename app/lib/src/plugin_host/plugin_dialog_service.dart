import 'package:flutter/material.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

/// 插件宿主统一对话框与交互服务
class PluginDialogService {
  static void showToast(BuildContext context, String message) {
    AppSnack.info(context, message);
  }

  static Future<void> showAlert(
      BuildContext context, String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: Icons.info_outline_rounded,
        title: title,
        content: Text(
          message,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
        ),
        actions: [
          FilledButton.tonal(
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
      builder: (ctx) => AppDialog(
        icon: Icons.help_outline_rounded,
        title: title,
        content: Text(
          message,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
        ),
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
    return await showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(
        title: title,
        hint: hint,
        defaultValue: defaultValue,
      ),
    );
  }

  static Future<Map<String, dynamic>?> showPickItem(
    BuildContext context, {
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.sm,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          children: items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final selected = idx == initialIndex;
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(item),
              trailing: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(ctx).pop({'index': idx, 'text': item}),
            );
          }).toList(),
        );
      },
    );
  }

  static Future<Map<String, dynamic>?> showBottomSheet(
    BuildContext context, {
    required String title,
    required List<String> items,
  }) async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              ...items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return ListTile(
                  title: Text(item, textAlign: TextAlign.center),
                  onTap: () =>
                      Navigator.of(ctx).pop({'index': idx, 'text': item}),
                );
              }),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
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

class _PromptDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String? defaultValue;

  const _PromptDialog({
    required this.title,
    this.hint,
    this.defaultValue,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.edit_note_rounded,
      title: widget.title,
      scrollable: false,
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

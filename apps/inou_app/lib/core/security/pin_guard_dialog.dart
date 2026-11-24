import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_store.dart';

/// Prompts the user for the configured Parent PIN before performing sensitive
/// operations (clearing data, deleting questions, changing security/AI keys).
/// Returns `true` immediately when no PIN is configured.
Future<bool> ensureParentPinAuthorized(
  BuildContext context,
  AppState state,
  AppStoreNotifier notifier, {
  String reason = '需要验证家长密码以继续操作',
}) async {
  if (!state.pinConfigured) return true;
  final ctrl = TextEditingController();
  var errorText = '';
  var busy = false;

  final verified = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = ctx.inou;
        Future<void> submit() async {
          if (busy) return;
          setState(() {
            busy = true;
            errorText = '';
          });
          final res = await notifier.verifyParentPin(ctrl.text);
          if (!ctx.mounted) return;
          if (res.ok) {
            Navigator.of(ctx).pop(true);
            return;
          }
          setState(() {
            busy = false;
            errorText = res.message;
          });
        }

        return AlertDialog(
          title: const Text('家长密码验证'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reason,
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: '输入家长数字密码',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('确认'),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return verified == true;
}

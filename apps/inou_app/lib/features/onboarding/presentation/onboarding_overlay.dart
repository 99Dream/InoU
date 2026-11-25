import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/state/app_store.dart';

/// Three-step responsive onboarding wizard (Profile -> Privacy -> Optional AI)
/// with full-screen mobile density and centered floating studio card on tablet.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  int _step = 0;
  late TextEditingController _nameController;
  StudyStage _stage = StudyStage.middle;
  String _grade = '九年级';
  final Set<String> _subjects = {'math', 'phy', 'eng'};
  bool _consentAccepted = true;

  AiEndpointConfig _endpoint = AiEndpointPresets.defaults().first;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(appStoreProvider).activeProfile;
    _nameController = TextEditingController(
      text: p.name == '新同学' ? '' : p.name,
    );
    _stage = p.stage;
    _grade = p.grade;
    _subjects
      ..clear()
      ..addAll(p.subjects);
    _syncEndpoint(_endpoint);
  }

  void _syncEndpoint(AiEndpointConfig ep) {
    _endpoint = ep;
    _urlController.text = ep.baseUrl;
    _modelController.text = ep.tierModels[AiTier.balanced] ?? '';
    _testMessage = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  AiEndpointConfig _builtEndpoint() {
    final primaryModel = _modelController.text.trim();
    final url = _urlController.text.trim();
    return _endpoint.copyWith(
      baseUrl: url,
      preferSse: true,
      disableSocketReuse: !AiEndpointConfig.isOfficialProviderUrl(url),
      tierModels: primaryModel.isNotEmpty
          ? {
              AiTier.fast: primaryModel,
              AiTier.balanced: primaryModel,
              AiTier.strong: primaryModel,
            }
          : _endpoint.tierModels,
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testMessage = '正在测试连通性…';
    });
    final res = await ref
        .read(appStoreProvider.notifier)
        .testEndpointConnection(
          _builtEndpoint(),
          apiKey: _keyController.text.trim(),
        );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = res.result.ok;
      _testMessage = res.result.message;
    });
  }

  Future<void> _finish({bool skipKey = false}) async {
    final active = ref.read(appStoreProvider).activeProfile;
    final updatedProfile = StudentProfile(
      id: active.id,
      name: _nameController.text.trim().isEmpty
          ? '新同学'
          : _nameController.text.trim(),
      stage: _stage,
      grade: _grade,
      subjects: _subjects.toList(growable: false),
    );
    await ref
        .read(appStoreProvider.notifier)
        .completeOnboarding(
          consentAccepted: _consentAccepted,
          updatedProfile: updatedProfile,
          endpoint: _builtEndpoint(),
          apiKey: skipKey ? '' : _keyController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final compact = AdaptiveScope.of(context) == WindowClass.compact;

    final bodyCard = InouSurface(
      radius: compact ? 18 : 20,
      elevated: !compact,
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const NuoNuoMascotView(emotion: NuoNuoExpression.happy, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '欢迎使用 InoU',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      '纯本地存储 · 支持接入自有大模型',
                      style: TextStyle(fontSize: 12, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              InouBadge(label: '${_step + 1} / 3', tone: InouBadgeTone.accent),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_step + 1) / 3,
              minHeight: 3.5,
              backgroundColor: t.surfaceMuted,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: switch (_step) {
                0 => _buildProfileStep(t),
                1 => _buildPrivacyStep(t),
                _ => _buildAiStep(t),
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('上一步'),
                ),
              const Spacer(),
              if (_step < 2)
                FilledButton(
                  onPressed: (_step == 1 && !_consentAccepted)
                      ? null
                      : () => setState(() => _step++),
                  child: const Text('下一步'),
                )
              else ...[
                TextButton(
                  onPressed: () => _finish(skipKey: true),
                  child: const Text('稍后配置'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _finish, child: const Text('开始使用')),
              ],
            ],
          ),
        ],
      ),
    );

    if (compact) {
      return Material(
        color: t.canvas,
        child: SafeArea(
          child: Padding(padding: const EdgeInsets.all(14), child: bodyCard),
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 610),
          child: Padding(padding: const EdgeInsets.all(16), child: bodyCard),
        ),
      ),
    );
  }

  Widget _buildProfileStep(InouTokens t) {
    final grades = switch (_stage) {
      StudyStage.primary => const ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'],
      StudyStage.middle => const ['七年级', '八年级', '九年级'],
      StudyStage.high => const ['高一', '高二', '高三'],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '你的名字或昵称',
            hintText: '例如：林同学',
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<StudyStage>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StudyStage.primary, label: Text('小学')),
              ButtonSegment(value: StudyStage.middle, label: Text('初中')),
              ButtonSegment(value: StudyStage.high, label: Text('高中')),
            ],
            selected: {_stage},
            onSelectionChanged: (sel) {
              setState(() {
                _stage = sel.first;
                _grade = switch (_stage) {
                  StudyStage.primary => '五年级',
                  StudyStage.middle => '九年级',
                  StudyStage.high => '高一',
                };
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in grades)
              ChoiceChip(
                label: Text(g),
                selected: _grade == g,
                onSelected: (_) => setState(() => _grade = g),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '常学学科',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in SubjectCatalog.labels.entries)
              FilterChip(
                label: Text(entry.value),
                selected: _subjects.contains(entry.key),
                onSelected: (on) {
                  setState(() {
                    if (on) {
                      _subjects.add(entry.key);
                    } else if (_subjects.length > 1) {
                      _subjects.remove(entry.key);
                    }
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrivacyStep(InouTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本地优先与数据自主',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        InouSurface(
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _privacyPoint(t, '题库、错题本、原卷照片与手写笔迹仅保存在你的设备本机。'),
              const SizedBox(height: 10),
              _privacyPoint(t, '应用不含预置假数据，所有内容均由你拍照、导入或手工建立。'),
              const SizedBox(height: 10),
              _privacyPoint(t, '导出的 `.inou` 备份归档默认剥离 API Key 与家长密码。'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _consentAccepted,
          onChanged: (v) => setState(() => _consentAccepted = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            '我已知晓数据保存在本地并同意使用说明',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _privacyPoint(InouTokens t, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: 17, color: t.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, height: 1.45, color: t.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildAiStep(InouTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择 AI 接口服务（可选）',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final ep in AiEndpointPresets.defaults())
              ChoiceChip(
                label: Text(ep.name),
                selected: _endpoint.id == ep.id,
                onSelected: (_) => setState(() => _syncEndpoint(ep)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: '跳过也可稍后在设置中添加',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(labelText: 'Base URL'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _modelController,
          decoration: const InputDecoration(labelText: '主模型名称（同时用于识别、讲解与出题）'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _testing ? null : _runTest,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check, size: 16),
              label: const Text('测试连接'),
            ),
            if (_testMessage != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _testMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _testOk ? t.success : t.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

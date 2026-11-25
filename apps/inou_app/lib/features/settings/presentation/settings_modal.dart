import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/backup/inou_backup_service.dart';
import '../../../core/platform/platform_media_service.dart';
import '../../../core/security/pin_guard_dialog.dart';
import '../../../core/state/app_store.dart';
import 'diagnostics_log_dialog.dart';

/// Opens Settings & AI Engine Console adaptively:
/// generous bottom sheet on phone width, centered studio dialog on tablet.
Future<void> showSettingsModal(BuildContext context) {
  final compact = AdaptiveScope.of(context) == WindowClass.compact;
  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.93,
        child: SettingsConsole(isSheet: true),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SettingsConsole(isSheet: false),
    ),
  );
}

class SettingsConsole extends ConsumerStatefulWidget {
  const SettingsConsole({super.key, this.isSheet = false});

  final bool isSheet;

  @override
  ConsumerState<SettingsConsole> createState() => _SettingsConsoleState();
}

class _SettingsConsoleState extends ConsumerState<SettingsConsole> {
  int _tab = 0; // 0: AI 接口, 1: 学习偏好, 2: 安全与备份

  late String _editingEndpointId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _fastCtrl = TextEditingController();
  final TextEditingController _balCtrl = TextEditingController();
  final TextEditingController _strCtrl = TextEditingController();
  AiProtocol _protocol = AiProtocol.gemini;
  JsonModeStrategy _jsonMode = JsonModeStrategy.auto;
  BboxOrder _bboxOrder = BboxOrder.yxyx1000;
  bool _preferSse = true;
  bool _disableSocketReuse = false;
  bool _userTouchedSocketToggle = false;
  bool _sendImageDetail = true;
  bool _supportsThinking = false;
  bool _supportsStreamUsage = true;
  Map<String, String> _extraHeaders = const {};
  bool _obscureKey = true;
  bool _testing = false;
  ConnectionCheckReport? _lastReport;
  List<String> _discoveredModels = const [];
  int _chipTarget = 0; // 0: 全部三档, 1: Fast, 2: Balanced, 3: Strong

  final TextEditingController _pinCtrl = TextEditingController();
  String _pinFeedback = '';
  String? _exportedBackupBase64;
  int _exportedByteLen = 0;
  final TextEditingController _importBase64Ctrl = TextEditingController();
  BackupImportMode _importMode = BackupImportMode.merge;
  String _backupMessage = '';

  @override
  void initState() {
    super.initState();
    final state = ref.read(appStoreProvider);
    _loadEndpointIntoForm(state.activeEndpoint, state.endpointKeys);
  }

  void _loadEndpointIntoForm(AiEndpointConfig ep, Map<String, String> keys) {
    _editingEndpointId = ep.id;
    _nameCtrl.text = ep.name;
    _urlCtrl.text = ep.baseUrl;
    _keyCtrl.text = keys[ep.id] ?? '';
    _fastCtrl.text = ep.tierModels[AiTier.fast] ?? '';
    _balCtrl.text = ep.tierModels[AiTier.balanced] ?? '';
    _strCtrl.text = ep.tierModels[AiTier.strong] ?? '';
    _protocol = ep.protocol;
    _jsonMode = ep.jsonModeStrategy;
    _bboxOrder = ep.bboxOrder;
    _preferSse = ep.preferSse;
    _disableSocketReuse = ep.disableSocketReuse;
    _userTouchedSocketToggle = false;
    _sendImageDetail = ep.sendImageDetail;
    _supportsThinking = ep.supportsThinking;
    _supportsStreamUsage = ep.supportsStreamUsage;
    _extraHeaders = ep.extraHeaders;
    _discoveredModels = const [];
    _lastReport = null;
  }

  AiEndpointConfig _collectEndpoint() {
    return AiEndpointConfig(
      id: _editingEndpointId,
      name: _nameCtrl.text.trim().isEmpty ? '自定义端点' : _nameCtrl.text.trim(),
      protocol: _protocol,
      baseUrl: _urlCtrl.text.trim(),
      tierModels: {
        if (_fastCtrl.text.trim().isNotEmpty)
          AiTier.fast: _fastCtrl.text.trim(),
        if (_balCtrl.text.trim().isNotEmpty)
          AiTier.balanced: _balCtrl.text.trim(),
        if (_strCtrl.text.trim().isNotEmpty)
          AiTier.strong: _strCtrl.text.trim(),
      },
      jsonModeStrategy: _jsonMode,
      bboxOrder: _bboxOrder,
      sendImageDetail: _sendImageDetail,
      supportsThinking: _supportsThinking,
      supportsStreamUsage: _supportsStreamUsage,
      preferSse: _preferSse,
      disableSocketReuse: _disableSocketReuse,
      extraHeaders: _extraHeaders,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _fastCtrl.dispose();
    _balCtrl.dispose();
    _strCtrl.dispose();
    _pinCtrl.dispose();
    _importBase64Ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveEndpoint() async {
    final notifier = ref.read(appStoreProvider.notifier);
    final ep = _collectEndpoint();
    await notifier.upsertEndpoint(ep, makeActive: true);
    await notifier.saveEndpointApiKey(ep.id, _keyCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已保存并启用「${ep.name}」')));
  }

  Future<void> _testConnection({required bool verifyVision}) async {
    setState(() => _testing = true);
    final ep = _collectEndpoint();
    final report = await ref
        .read(appStoreProvider.notifier)
        .testEndpointConnection(
          ep,
          apiKey: _keyCtrl.text,
          verifyVision: verifyVision,
        );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _lastReport = report;
    });
  }

  Future<void> _fetchModels() async {
    setState(() => _testing = true);
    final ep = _collectEndpoint();
    final res = await const InouConnectionService().listModels(
      ep,
      apiKey: _keyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _discoveredModels = res.models;
    });
    if (!res.ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.errorMessage ?? '拉取模型失败')));
    }
  }

  Future<void> _exportInouFile({required bool shareSheet}) async {
    final notifier = ref.read(appStoreProvider.notifier);
    final media = ref.read(platformMediaServiceProvider);
    final bytes = notifier.exportBackupArchive();
    final now = DateTime.now();
    final filename =
        'inou_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.inou';
    bool ok = false;
    try {
      ok = shareSheet
          ? await media.shareFile(
              filename: filename,
              mimeType: 'application/octet-stream',
              bytes: bytes,
            )
          : await media.saveFile(
              filename: filename,
              mimeType: 'application/octet-stream',
              bytes: bytes,
            );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = e.message ?? '导出文件失败');
      return;
    }
    if (!mounted) return;
    setState(() {
      _exportedByteLen = bytes.length;
      _exportedBackupBase64 = base64Encode(bytes);
      _importBase64Ctrl.text = _exportedBackupBase64!;
      _backupMessage = ok
          ? '已导出 $filename（${bytes.length} B）'
          : '已生成 .inou 归档（${bytes.length} B），可在下方复制或校验';
    });
  }

  Future<void> _importInouFromFile() async {
    try {
      final picked = await ref.read(platformMediaServiceProvider).pickFile();
      if (picked == null || !mounted) return;
      final notifier = ref.read(appStoreProvider.notifier);
      final info = notifier.inspectBackupArchive(picked.bytes);
      if (!info.ok) {
        setState(() => _backupMessage = info.errorMessage ?? '备份校验失败');
        return;
      }
      await notifier.importBackupArchive(picked.bytes, mode: _importMode);
      if (!mounted) return;
      setState(() {
        _backupMessage =
            '已导入 ${picked.name}：${info.questionCount} 道题、${info.wrongItemCount} 道错题';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = e.message ?? '无法选择文件');
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = '导入失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final state = ref.watch(appStoreProvider);
    final notifier = ref.read(appStoreProvider.notifier);
    final compact =
        widget.isSheet || AdaptiveScope.of(context) == WindowClass.compact;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact ? double.infinity : 760,
        maxHeight: compact ? double.infinity : 680,
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 22,
              compact ? 2 : 16,
              compact ? 10 : 14,
              10,
            ),
            child: Row(
              children: [
                Text(
                  '设置与 AI 模型引擎',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: t.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 22),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('AI 接口')),
                  ButtonSegment(value: 1, label: Text('学习偏好')),
                  ButtonSegment(value: 2, label: Text('安全与备份')),
                ],
                selected: {_tab},
                onSelectionChanged: (sel) => setState(() => _tab = sel.first),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 18 : 22),
              child: switch (_tab) {
                0 => _buildAiTab(t, state, notifier, compact),
                1 => _buildStudyPrefsTab(t, state, notifier),
                _ => _buildSecurityAndBackupTab(t, state, notifier, compact),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiTab(
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
    bool compact,
  ) {
    final tierFields = [
      TextField(
        controller: _fastCtrl,
        decoration: const InputDecoration(labelText: 'Fast 模型（选填，留空同主模型）'),
      ),
      TextField(
        controller: _balCtrl,
        decoration: const InputDecoration(labelText: '主模型 / Balanced（视觉与默认兜底）'),
      ),
      TextField(
        controller: _strCtrl,
        decoration: const InputDecoration(labelText: 'Strong 推理（选填，留空同主模型）'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final ep in state.snapshot.endpoints)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${ep.name}${ep.id == state.activeEndpoint.id ? " · 当前" : ""}',
                    ),
                    selected: ep.id == _editingEndpointId,
                    onSelected: (_) => setState(
                      () => _loadEndpointIntoForm(ep, state.endpointKeys),
                    ),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 15),
                label: const Text('新增自定义'),
                onPressed: () {
                  final fresh = AiEndpointConfig(
                    id: 'ep_${DateTime.now().millisecondsSinceEpoch}',
                    name: '自定义 API 接口',
                    protocol: AiProtocol.openAiCompatible,
                    baseUrl: '',
                    tierModels: const {},
                  );
                  setState(
                    () => _loadEndpointIntoForm(fresh, state.endpointKeys),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        InouSurface(
          subtle: true,
          padding: EdgeInsets.all(compact ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: '配置名称'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<AiProtocol>(
                  initialValue: _protocol,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '接口协议'),
                  items: [
                    for (final p in AiProtocol.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(p.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _protocol = v);
                  },
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: '配置名称'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<AiProtocol>(
                        initialValue: _protocol,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '接口协议'),
                        items: [
                          for (final p in AiProtocol.values)
                            DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _protocol = v);
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key（仅存本机）',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'Base URL / 网关地址'),
                onChanged: (value) {
                  setState(() {
                    if (!_userTouchedSocketToggle) {
                      _disableSocketReuse =
                          !AiEndpointConfig.isOfficialProviderUrl(value);
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                tierFields[1],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: tierFields[0]),
                    const SizedBox(width: 8),
                    Expanded(child: tierFields[2]),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: tierFields[0]),
                    const SizedBox(width: 8),
                    Expanded(child: tierFields[1]),
                    const SizedBox(width: 8),
                    Expanded(child: tierFields[2]),
                  ],
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final primary = _balCtrl.text.trim().isNotEmpty
                        ? _balCtrl.text.trim()
                        : (_fastCtrl.text.trim().isNotEmpty
                              ? _fastCtrl.text.trim()
                              : _strCtrl.text.trim());
                    if (primary.isEmpty) return;
                    setState(() {
                      _fastCtrl.text = primary;
                      _balCtrl.text = primary;
                      _strCtrl.text = primary;
                    });
                  },
                  icon: const Icon(Icons.sync_rounded, size: 15),
                  label: const Text('三档均同步为主模型'),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<JsonModeStrategy>(
                      initialValue: _jsonMode,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '结构化输出'),
                      items: [
                        for (final m in JsonModeStrategy.values)
                          DropdownMenuItem(value: m, child: Text(m.code)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _jsonMode = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<BboxOrder>(
                      initialValue: _bboxOrder,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '视觉坐标'),
                      items: [
                        for (final b in BboxOrder.values)
                          DropdownMenuItem(value: b, child: Text(b.code)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _bboxOrder = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final urlText = _urlCtrl.text.trim();
                  final isOfficial =
                      AiEndpointConfig.isOfficialProviderUrl(urlText);
                  final statusText = urlText.isEmpty
                      ? '未填写网关地址：默认使用 SSE（text/event-stream）并关闭长连接复用'
                      : isOfficial
                      ? '检测到官方接口域名：优先使用 SSE，可按需启用连接复用'
                      : '检测到非官方中转/自建地址：默认优先 SSE 且禁用 Socket 长连接复用，避免断连';
                  return InouSurface(
                    subtle: true,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isOfficial
                                  ? Icons.verified_rounded
                                  : Icons.hub_rounded,
                              size: 16,
                              color: isOfficial ? t.success : t.accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          key: const ValueKey('settings_prefer_sse_switch'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            '优先使用 SSE 流式连接',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            '通过 Server-Sent Events 增量接收 AI 回复，提升响应体感并降低超时概率',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          value: _preferSse,
                          onChanged: (v) => setState(() => _preferSse = v),
                        ),
                        SwitchListTile(
                          key: const ValueKey('settings_disable_socket_switch'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            '禁用 Socket 长连接复用（非官方地址推荐）',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            '每次请求关闭 Keep-Alive（Connection: close），防止中转网关断流引发 connection abort',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          value: _disableSocketReuse,
                          onChanged: (v) => setState(() {
                            _userTouchedSocketToggle = true;
                            _disableSocketReuse = v;
                          }),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_discoveredModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        '点击模型填入：',
                        style: TextStyle(fontSize: 11.5, color: t.textMuted),
                      ),
                      const SizedBox(width: 6),
                      for (final opt in const [
                        (idx: 0, label: '全部三档'),
                        (idx: 1, label: 'Fast'),
                        (idx: 2, label: 'Balanced'),
                        (idx: 3, label: 'Strong'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              opt.label,
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _chipTarget == opt.idx,
                            onSelected: (_) =>
                                setState(() => _chipTarget = opt.idx),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in _discoveredModels.take(18))
                      ActionChip(
                        label: Text(m, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () => setState(() {
                          switch (_chipTarget) {
                            case 1:
                              _fastCtrl.text = m;
                            case 2:
                              _balCtrl.text = m;
                            case 3:
                              _strCtrl.text = m;
                            default:
                              _fastCtrl.text = m;
                              _balCtrl.text = m;
                              _strCtrl.text = m;
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saveEndpoint,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('保存并启用'),
                  ),
                  OutlinedButton(
                    onPressed: _testing
                        ? null
                        : () => _testConnection(verifyVision: false),
                    child: const Text('测试文本'),
                  ),
                  OutlinedButton(
                    onPressed: _testing
                        ? null
                        : () => _testConnection(verifyVision: true),
                    child: const Text('测试视觉'),
                  ),
                  OutlinedButton(
                    onPressed: _testing ? null : _fetchModels,
                    child: const Text('拉取模型'),
                  ),
                  if (state.snapshot.endpoints.length > 1 &&
                      state.snapshot.endpoints.any(
                        (e) => e.id == _editingEndpointId,
                      ))
                    TextButton(
                      onPressed: () async {
                        await notifier.deleteEndpoint(_editingEndpointId);
                        if (!mounted) return;
                        final next = ref.read(appStoreProvider);
                        setState(
                          () => _loadEndpointIntoForm(
                            next.activeEndpoint,
                            next.endpointKeys,
                          ),
                        );
                      },
                      child: Text('删除此配置', style: TextStyle(color: t.danger)),
                    ),
                ],
              ),
              if (_lastReport != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InouBadge(
                      label: _lastReport!.result.ok ? '可用' : '失败',
                      tone: _lastReport!.result.ok
                          ? InouBadgeTone.success
                          : InouBadgeTone.danger,
                    ),
                    if (!_lastReport!.result.ok)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => showDiagnosticsLogDialog(
                          context,
                          initialErrorsOnly: true,
                        ),
                        child: const Text('查看/导出日志'),
                      ),
                  ],
                ),
                if ((_lastReport!.result.message ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    _lastReport!.result.message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _lastReport!.result.ok ? t.success : t.danger,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudyPrefsTab(
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
  ) {
    final prefs = state.snapshot.preferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InouSectionHeader(title: '外观主题与伴学精灵'),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', label: Text('跟随系统')),
              ButtonSegment(value: 'light', label: Text('浅色')),
              ButtonSegment(value: 'dark', label: Text('深色')),
            ],
            selected: {prefs.darkModePreference},
            onSelectionChanged: (sel) => notifier.updatePreferences(
              prefs.copyWith(darkModePreference: sel.first),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.mascotAnimating,
          title: const Text('诺诺伴学微动效'),
          onChanged: (v) =>
              notifier.updatePreferences(prefs.copyWith(mascotAnimating: v)),
        ),
        const Divider(height: 22),
        const InouSectionHeader(title: '错题收集与毕业设置'),
        const SizedBox(height: 10),
        DropdownButtonFormField<WrongBookCollectMode>(
          initialValue: prefs.wrongBookCollectMode,
          decoration: const InputDecoration(labelText: '练习做错收集方式'),
          items: const [
            DropdownMenuItem(
              value: WrongBookCollectMode.ask,
              child: Text('交卷后勾选纳入（推荐）'),
            ),
            DropdownMenuItem(
              value: WrongBookCollectMode.auto,
              child: Text('做错自动收录'),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              notifier.updatePreferences(
                prefs.copyWith(wrongBookCollectMode: v),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '连续答对几次毕业：N = ${prefs.masteryStreak}',
                style: TextStyle(fontSize: 13.5, color: t.textPrimary),
              ),
            ),
            for (final n in const [2, 3, 4, 5])
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: ChoiceChip(
                  label: Text('$n'),
                  selected: prefs.masteryStreak == n,
                  onSelected: (_) => notifier.updatePreferences(
                    prefs.copyWith(masteryStreak: n),
                  ),
                ),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.partialClearsStreak,
          title: const Text('“部分正确”清零连对次数'),
          onChanged: (v) => notifier.updatePreferences(
            prefs.copyWith(partialClearsStreak: v),
          ),
        ),
        const Divider(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                notifier.reopenOnboarding();
              },
              icon: const Icon(Icons.explore_outlined, size: 16),
              label: const Text('重走新手引导'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await ensureParentPinAuthorized(
                  context,
                  state,
                  notifier,
                  reason: '清空数据需要验证家长密码',
                );
                if (!ok || !mounted) return;
                await notifier.clearActiveWorkspace();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('已清空当前档案学习数据')),
                );
              },
              icon: Icon(Icons.delete_outline, size: 16, color: t.danger),
              label: Text('清空当前档案', style: TextStyle(color: t.danger)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecurityAndBackupTab(
    InouTokens t,
    AppState state,
    AppStoreNotifier notifier,
    bool compact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InouSectionHeader(
          title: '家长密码锁',
          subtitle: '启用后，删除题目、删除试卷与清空数据需要验证密码',
        ),
        const SizedBox(height: 10),
        InouSurface(
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InouBadge(
                    label: state.pinConfigured ? '家长密码已启用' : '未启用',
                    tone: state.pinConfigured
                        ? InouBadgeTone.success
                        : InouBadgeTone.neutral,
                  ),
                  const Spacer(),
                  if (state.pinConfigured)
                    TextButton(
                      onPressed: () async {
                        final ok = await ensureParentPinAuthorized(
                          context,
                          state,
                          notifier,
                          reason: '关闭密码锁需先验证原密码',
                        );
                        if (!ok) return;
                        await notifier.clearParentPin();
                        if (!mounted) return;
                        setState(() => _pinFeedback = '已清除家长密码锁');
                      },
                      child: const Text('清除密码'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '输入至少 4 位数字'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _submitPin(state, notifier),
                        child: const Text('设置/更新'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final res = await notifier.verifyParentPin(
                          _pinCtrl.text,
                        );
                        if (!mounted) return;
                        setState(() => _pinFeedback = res.message);
                      },
                      child: const Text('校验'),
                    ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '输入至少 4 位数字',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _submitPin(state, notifier),
                      child: const Text('设置/更新'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () async {
                        final res = await notifier.verifyParentPin(
                          _pinCtrl.text,
                        );
                        if (!mounted) return;
                        setState(() => _pinFeedback = res.message);
                      },
                      child: const Text('校验'),
                    ),
                  ],
                ),
              if (_pinFeedback.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _pinFeedback,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const InouSectionHeader(
          title: '.inou 工作区备份与还原',
          subtitle: '导出全部题库、错题与笔迹（不包含 API Key）',
        ),
        const SizedBox(height: 10),
        InouSurface(
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _exportInouFile(shareSheet: false),
                    icon: const Icon(Icons.save_alt, size: 16),
                    label: const Text('保存 .inou 文件'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportInouFile(shareSheet: true),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('分享备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importInouFromFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('从文件导入'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BackupImportMode>(
                initialValue: _importMode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '导入策略'),
                items: [
                  for (final m in BackupImportMode.values)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _importMode = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _importBase64Ctrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '也可粘贴 .inou Base64 备份串校验或还原…',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      final bytes = notifier.exportBackupArchive();
                      final b64 = base64Encode(bytes);
                      setState(() {
                        _exportedBackupBase64 = b64;
                        _exportedByteLen = bytes.length;
                        _importBase64Ctrl.text = b64;
                        _backupMessage = '已生成 .inou 压缩归档（${bytes.length} B）';
                      });
                    },
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('生成 .inou 备份包'),
                  ),
                  if (_exportedBackupBase64 != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: _exportedBackupBase64!),
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('已复制 ($_exportedByteLen B)')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制'),
                    ),
                  OutlinedButton(
                    onPressed: () {
                      try {
                        final bytes = base64Decode(
                          _importBase64Ctrl.text.trim(),
                        );
                        final info = notifier.inspectBackupArchive(bytes);
                        setState(() {
                          _backupMessage = info.ok
                              ? 'SHA-256 校验通过：${info.profileCount} 档案，${info.questionCount} 题目，${info.wrongItemCount} 错题'
                              : (info.errorMessage ?? '校验失败');
                        });
                      } catch (e) {
                        setState(() => _backupMessage = '解码失败：$e');
                      }
                    },
                    child: const Text('仅校验完整性'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      try {
                        final bytes = base64Decode(
                          _importBase64Ctrl.text.trim(),
                        );
                        await notifier.importBackupArchive(
                          bytes,
                          mode: _importMode,
                        );
                        setState(
                          () => _backupMessage = '备份导入完成（${_importMode.label}）',
                        );
                      } catch (e) {
                        setState(() => _backupMessage = '导入失败：$e');
                      }
                    },
                    child: const Text('执行还原导入'),
                  ),
                ],
              ),
              if (_backupMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _backupMessage,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const InouSectionHeader(
          title: '诊断日志与导出',
          subtitle: '查看完整报错堆栈或导出 .txt 日志用于排查问题（自动脱敏密钥）',
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final logger = InouDiagnosticsLogger.instance;
            final latestErr = logger.latestError;
            return InouSurface(
              subtle: true,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InouBadge(
                        label: '共 ${logger.entries.length} 条日志',
                        tone: InouBadgeTone.neutral,
                      ),
                      InouBadge(
                        label: '错误 ${logger.errorCount} 条',
                        tone: logger.errorCount > 0
                            ? InouBadgeTone.danger
                            : InouBadgeTone.success,
                      ),
                    ],
                  ),
                  if (latestErr != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      '最近报错（${latestErr.tag}）：${latestErr.message}'
                      '${latestErr.detail != null ? "\n${latestErr.detail}" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: t.danger,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await showDiagnosticsLogDialog(context);
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.bug_report_outlined, size: 16),
                        label: const Text('查看完整日志'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => exportDiagnosticsLogFile(
                          context,
                          ref,
                          shareSheet: false,
                        ),
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: const Text('保存日志文件'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => exportDiagnosticsLogFile(
                          context,
                          ref,
                          shareSheet: true,
                        ),
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('分享日志'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            copyDiagnosticsLogsToClipboard(context, ref),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制全部'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _submitPin(AppState state, AppStoreNotifier notifier) async {
    if (state.pinConfigured) {
      final ok = await ensureParentPinAuthorized(
        context,
        state,
        notifier,
        reason: '修改密码需先验证原密码',
      );
      if (!ok) return;
    }
    try {
      await notifier.setParentPin(_pinCtrl.text);
      _pinCtrl.clear();
      if (!mounted) return;
      setState(() => _pinFeedback = '家长密码设置成功');
    } catch (e) {
      if (!mounted) return;
      setState(() => _pinFeedback = '$e');
    }
  }
}

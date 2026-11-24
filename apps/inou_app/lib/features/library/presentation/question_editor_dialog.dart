import 'package:flutter/services.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/state/app_store.dart';

/// Unified creator & editor dialog for creating a new [Question] or editing an
/// existing one (used in both Library and OCR Split Proofread).
Future<Question?> showQuestionEditorDialog(
  BuildContext context, {
  required AppState state,
  Question? existing,
  String defaultSubject = 'math',
  Future<void> Function(Question question)? onSaveAndNext,
}) {
  final compact = AdaptiveScope.of(context) == WindowClass.compact;
  if (compact) {
    return showModalBottomSheet<Question>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.88,
          child: _QuestionEditorSheet(
            appState: state,
            existing: existing,
            defaultSubject: defaultSubject,
            onSaveAndNext: onSaveAndNext,
            isSheet: true,
          ),
        ),
      ),
    );
  }
  return showDialog<Question>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: _QuestionEditorSheet(
        appState: state,
        existing: existing,
        defaultSubject: defaultSubject,
        onSaveAndNext: onSaveAndNext,
      ),
    ),
  );
}

class _QuestionEditorSheet extends StatefulWidget {
  const _QuestionEditorSheet({
    required this.appState,
    this.existing,
    this.defaultSubject = 'math',
    this.onSaveAndNext,
    this.isSheet = false,
  });

  final AppState appState;
  final Question? existing;
  final String defaultSubject;
  final Future<void> Function(Question question)? onSaveAndNext;
  final bool isSheet;

  @override
  State<_QuestionEditorSheet> createState() => _QuestionEditorSheetState();
}

class _QuestionEditorSheetState extends State<_QuestionEditorSheet> {
  static const _optionLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

  late QuestionKind _kind;
  late String _subject;
  late String? _selectedKpId;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _stemCtrl;
  late final TextEditingController _ansCtrl;
  late final TextEditingController _bankCtrl;
  late final TextEditingController _expCtrl;
  late final TextEditingController _tagsCtrl;
  final List<TextEditingController> _optionCtrls = [];
  final Set<String> _correctOptionIds = {};
  int _continuousSavedCount = 0;
  bool _savingNext = false;
  late bool _subjectLocked;
  bool _autoDetectedFromInput = false;
  bool _sequenceMode = false;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    _subjectLocked = q != null;
    _sequenceMode = q?.isSequence ?? false;
    _kind = q?.kind ?? QuestionKind.choice;
    if (_kind != QuestionKind.choice &&
        _kind != QuestionKind.fill &&
        _kind != QuestionKind.solve &&
        _kind != QuestionKind.response) {
      // Keep specialized interactive kinds safe while letting basic fields edit cleanly
    }
    _subject = q?.meta.subject ?? widget.defaultSubject;
    final kpLeaves = widget.appState.kpTree.leaves(subject: _subject);
    final existingKp = q?.meta.kpIds.firstOrNull;
    _selectedKpId =
        (existingKp != null && kpLeaves.any((k) => k.id == existingKp))
        ? existingKp
        : kpLeaves.firstOrNull?.id;

    _titleCtrl = TextEditingController(text: q?.header.title ?? '');
    _stemCtrl = TextEditingController(text: q?.plainText ?? '');
    if (!_subjectLocked) {
      _stemCtrl.addListener(_onStemTextChanged);
    }
    _expCtrl = TextEditingController(
      text: q != null ? ContentTextUtils.extractPlainText(q.explanation) : '',
    );
    _tagsCtrl = TextEditingController(text: q?.meta.tags.join(' ') ?? '');

    if (q != null && q.kind == QuestionKind.choice) {
      final rawOpts = (q.body['options'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .toList();
      for (final opt in rawOpts) {
        final content = opt['content'];
        final txt = content is List
            ? ContentTextUtils.extractPlainText(
                content
                    .whereType<Map<Object?, Object?>>()
                    .map(
                      (m) => ContentBlock.fromJson(
                        m.map((k, v) => MapEntry(k.toString(), v)),
                      ),
                    )
                    .toList(),
              )
            : '';
        _optionCtrls.add(TextEditingController(text: txt));
      }
      final ansSets = q.grading['answerSets'] as List<Object?>? ?? const [];
      if (ansSets.isNotEmpty && ansSets.first is Map) {
        final exp = (ansSets.first! as Map)['expected'];
        if (exp is Map && exp['selectedIds'] is List) {
          for (final id in exp['selectedIds'] as List) {
            _correctOptionIds.add(id.toString());
          }
        }
      }
    }
    if (_optionCtrls.isEmpty) {
      for (var i = 0; i < 4; i++) {
        _optionCtrls.add(TextEditingController());
      }
      _correctOptionIds.add('A');
    }

    _ansCtrl = TextEditingController(text: _extractInitialScalarAnswer(q));
    _bankCtrl = TextEditingController(text: _extractInitialBankText(q));
  }

  String _extractInitialBankText(Question? q) {
    if (q == null || !q.isSequence) return '';
    final bank = SequenceQuestionDetector.normalizeBankList(q.body['bank']);
    final parts = <String>[];
    for (final item in bank) {
      final content = item['content'];
      if (content is List) {
        final txt = ContentTextUtils.extractPlainText(
          content
              .whereType<Map<Object?, Object?>>()
              .map(
                (m) => ContentBlock.fromJson(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList(),
        );
        if (txt.isNotEmpty) parts.add(txt);
      }
    }
    return parts.any((p) => p.length > 14)
        ? parts.join('\n')
        : parts.join(' / ');
  }

  String _extractInitialScalarAnswer(Question? q) {
    if (q == null) return '';
    if (q.kind == QuestionKind.fill) {
      final sets = q.grading['answerSets'] as List<Object?>? ?? const [];
      if (sets.isNotEmpty && sets.first is Map) {
        final exp = (sets.first! as Map)['expected'];
        if (exp is Map && exp['entries'] is List) {
          final entries = exp['entries'] as List;
          if (entries.isNotEmpty && entries.first is Map) {
            final vals = (entries.first as Map)['acceptedValues'] as List?;
            if (vals != null && vals.isNotEmpty && vals.first is Map) {
              final first = vals.first as Map;
              if (first['type'] == 'items' && first['itemIds'] is List) {
                final ids = (first['itemIds'] as List)
                    .map((e) => e.toString())
                    .toList();
                final bank = SequenceQuestionDetector.normalizeBankList(
                  q.body['bank'],
                );
                final labels = <String>[];
                for (final id in ids) {
                  final idx = bank.indexWhere((b) => b['id']?.toString() == id);
                  if (idx >= 0) {
                    labels.add('${idx + 1}');
                  } else {
                    labels.add(id);
                  }
                }
                return labels.join(',');
              }
              return (first['value'] ?? first['text'] ?? '').toString();
            }
          }
        }
      }
    }
    final fin = q.grading['finalAnswer'];
    if (fin is Map && fin['acceptedValues'] is List) {
      final vals = fin['acceptedValues'] as List;
      if (vals.isNotEmpty && vals.first is Map) {
        final first = vals.first as Map;
        return (first['value'] ?? first['text'] ?? '').toString();
      }
    }
    return '';
  }

  void _onStemTextChanged() {
    if (_subjectLocked) return;
    final txt = _stemCtrl.text.trim();
    if (txt.length < 8) return;
    final det = SubjectDetector.detect(txt);
    if (det.isStrong && det.subject != _subject) {
      final leaves = widget.appState.kpTree.leaves(subject: det.subject);
      setState(() {
        _subject = det.subject;
        _selectedKpId = leaves.firstOrNull?.id;
        _autoDetectedFromInput = true;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _stemCtrl
      ..removeListener(_onStemTextChanged)
      ..dispose();
    _ansCtrl.dispose();
    _bankCtrl.dispose();
    _expCtrl.dispose();
    _tagsCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Question? _buildQuestionFromForm() {
    final stem = _stemCtrl.text.trim();
    if (stem.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写题干内容')));
      return null;
    }

    final old = widget.existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = old?.id ?? 'q_${const Uuid().v4().substring(0, 8)}';
    final autoTitle = stem.length <= 16 ? stem : '${stem.substring(0, 16)}…';
    final title = _titleCtrl.text.trim().isEmpty
        ? autoTitle
        : _titleCtrl.text.trim();
    final exp = _expCtrl.text.trim();
    final tags = _tagsCtrl.text
        .split(RegExp(r'[\s,，]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final kpIds = _selectedKpId != null ? [_selectedKpId!] : const <String>[];
    final meta = (old?.meta ?? QuestionMeta(subject: _subject, grade: 'g9'))
        .copyWith(
          subject: _subject,
          kpIds: kpIds,
          tags: tags,
          answerSource: AnswerSource.user,
          uncertainNote: null,
        );

    late final Question result;
    if (_kind == QuestionKind.choice) {
      final opts = <Map<String, Object?>>[];
      for (var i = 0; i < _optionCtrls.length; i++) {
        final letter = _optionLetters[i];
        opts.add({
          'id': letter,
          'content': [
            {
              'type': 'text',
              'text': _optionCtrls[i].text.trim().isEmpty
                  ? '选项 $letter'
                  : _optionCtrls[i].text.trim(),
            },
          ],
        });
      }
      final validLetters = opts.map((e) => e['id'].toString()).toSet();
      final selected = _correctOptionIds.where(validLetters.contains).toList();
      if (selected.isEmpty) selected.add(opts.first['id'].toString());

      result = Question(
        id: id,
        kind: QuestionKind.choice,
        docId: old?.docId,
        sourceType: old?.sourceType ?? 'manual',
        bbox: old?.bbox,
        historyVerdicts: old?.historyVerdicts ?? const [],
        header: QuestionHeader(title: title, score: old?.header.score ?? 3),
        prompt: [TextBlock(stem)],
        body: {'options': opts},
        rules: {
          'minSelections': 1,
          'maxSelections': selected.length > 1 ? selected.length : 1,
        },
        presentation: const QuestionPresentation(interaction: 'choice.select'),
        grading: {
          'mode': 'exact',
          'maxScore': old?.maxScore ?? 3,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {'selectedIds': selected},
            },
          ],
        },
        explanation: exp.isEmpty ? const [] : [TextBlock(exp)],
        meta: meta,
        createdAtMs: old?.createdAtMs ?? now,
        updatedAtMs: now,
      );
    } else if (_kind == QuestionKind.fill && _sequenceMode) {
      final ans = _ansCtrl.text.trim();
      final rawTokens = _bankCtrl.text
          .split(RegExp(r'\n+|/|｜|\|'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final items = rawTokens
          .map((t) => (label: null as String?, text: t))
          .toList();
      final bank = SequenceQuestionDetector.buildBankFromItems(items);
      final itemIds = SequenceQuestionDetector.matchAnswerToBankIds(ans, bank);
      result = Question(
        id: id,
        kind: QuestionKind.fill,
        docId: old?.docId,
        sourceType: old?.sourceType ?? 'manual',
        bbox: old?.bbox,
        historyVerdicts: old?.historyVerdicts ?? const [],
        header: QuestionHeader(title: title, score: old?.header.score ?? 4),
        prompt: [TextBlock(stem), const TextBlock(' '), const SlotBlock('s1')],
        body: {
          'slots': const [
            {'id': 's1', 'label': '排序结果', 'valueType': 'text'},
          ],
          'bank': bank,
        },
        presentation: const QuestionPresentation(interaction: 'fill.sequence'),
        grading: {
          'mode': 'exact',
          'maxScore': old?.maxScore ?? 4,
          'perSlotScore': {'s1': old?.maxScore ?? 4},
          'answerSets': itemIds.isNotEmpty
              ? [
                  {
                    'id': 'ans-1',
                    'expected': {
                      'entries': [
                        {
                          'slotId': 's1',
                          'acceptedValues': [
                            {'type': 'items', 'itemIds': itemIds},
                          ],
                        },
                      ],
                    },
                  },
                ]
              : const <Object?>[],
        },
        explanation: exp.isEmpty ? const [] : [TextBlock(exp)],
        meta: meta,
        createdAtMs: old?.createdAtMs ?? now,
        updatedAtMs: now,
      );
    } else if (_kind == QuestionKind.fill) {
      final ans = _ansCtrl.text.trim();
      final numV = double.tryParse(ans);
      result = Question(
        id: id,
        kind: QuestionKind.fill,
        docId: old?.docId,
        sourceType: old?.sourceType ?? 'manual',
        bbox: old?.bbox,
        historyVerdicts: old?.historyVerdicts ?? const [],
        header: QuestionHeader(title: title, score: old?.header.score ?? 4),
        prompt: [TextBlock(stem), const TextBlock(' '), const SlotBlock('s1')],
        body: const {
          'slots': [
            {'id': 's1', 'label': '答案', 'valueType': 'text'},
          ],
        },
        presentation: const QuestionPresentation(interaction: 'fill.input'),
        grading: {
          'mode': 'exact',
          'maxScore': old?.maxScore ?? 4,
          'perSlotScore': {'s1': old?.maxScore ?? 4},
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'slotId': 's1',
                    'acceptedValues': [
                      if (numV != null)
                        {'type': 'number', 'value': numV, 'tolerance': 1e-6}
                      else
                        {'type': 'text', 'text': ans},
                    ],
                  },
                ],
              },
            },
          ],
        },
        explanation: exp.isEmpty ? const [] : [TextBlock(exp)],
        meta: meta,
        createdAtMs: old?.createdAtMs ?? now,
        updatedAtMs: now,
      );
    } else if (_kind == QuestionKind.solve || _kind == QuestionKind.response) {
      final ans = _ansCtrl.text.trim();
      result = Question(
        id: id,
        kind: _kind,
        docId: old?.docId,
        sourceType: old?.sourceType ?? 'manual',
        bbox: old?.bbox,
        historyVerdicts: old?.historyVerdicts ?? const [],
        header: QuestionHeader(title: title, score: old?.header.score ?? 8),
        prompt: [TextBlock(stem)],
        body: _kind == QuestionKind.solve
            ? const {
                'steps': [
                  {'id': 'st1', 'label': '解答步骤', 'score': 8},
                ],
              }
            : const {
                'parts': [
                  {'id': 'p1', 'label': '作答内容'},
                ],
              },
        presentation: QuestionPresentation(
          interaction: _kind == QuestionKind.solve
              ? 'solve.steps'
              : 'response.text',
        ),
        grading: {
          'mode': 'stepwise_ai',
          'maxScore': old?.maxScore ?? 8,
          if (ans.isNotEmpty)
            'finalAnswer': {
              'acceptedValues': [
                if (double.tryParse(ans) != null)
                  {
                    'type': 'number',
                    'value': double.parse(ans),
                    'tolerance': 1e-6,
                  }
                else
                  {'type': 'text', 'text': ans},
              ],
            },
        },
        explanation: exp.isEmpty ? const [] : [TextBlock(exp)],
        meta: meta,
        createdAtMs: old?.createdAtMs ?? now,
        updatedAtMs: now,
      );
    } else {
      // Preserve specialized interactive bodies (match, classify, draw, spatial, write, group)
      result = old!.copyWith(
        header: QuestionHeader(
          title: title,
          description: old.header.description,
          score: old.header.score,
        ),
        prompt: [TextBlock(stem)],
        explanation: exp.isEmpty ? const [] : [TextBlock(exp)],
        meta: meta,
        updatedAtMs: now,
      );
    }

    return result;
  }

  void _saveAndClose() {
    final result = _buildQuestionFromForm();
    if (result == null) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _saveAndContinue() async {
    final onNext = widget.onSaveAndNext;
    if (onNext == null || _savingNext) return;
    final result = _buildQuestionFromForm();
    if (result == null) return;
    setState(() => _savingNext = true);
    try {
      await onNext(result);
      if (!mounted) return;
      _titleCtrl.clear();
      _stemCtrl.clear();
      _ansCtrl.clear();
      _bankCtrl.clear();
      _expCtrl.clear();
      _tagsCtrl.clear();
      for (final c in _optionCtrls) {
        c.clear();
      }
      _correctOptionIds
        ..clear()
        ..add('A');
      setState(() {
        _continuousSavedCount++;
        _subjectLocked = false;
        _autoDetectedFromInput = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('已保存第 $_continuousSavedCount 题，继续录入下一题'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingNext = false);
    }
  }

  void _applyParsedText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final grade = widget.appState.activeProfile.grade;
    final jsonParsed = StructuredQuestionTextParser.tryParseJsonOrJsonl(
      trimmed,
      subject: _subjectLocked ? _subject : SubjectCatalog.autoCode,
      grade: grade,
      lockSubject: _subjectLocked,
    );
    final q = (jsonParsed != null && jsonParsed.isNotEmpty)
        ? jsonParsed.first
        : StructuredQuestionTextParser.parseTextChunk(
            trimmed,
            id: 'q_paste',
            index: 0,
            subject: _subjectLocked ? _subject : SubjectCatalog.autoCode,
            grade: grade,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            lockSubject: _subjectLocked,
          );

    setState(() {
      if (!_subjectLocked &&
          q.meta.subject != 'other' &&
          q.meta.subject != _subject) {
        _subject = q.meta.subject;
        _selectedKpId = widget.appState.kpTree
            .leaves(subject: _subject)
            .firstOrNull
            ?.id;
        _autoDetectedFromInput = true;
      }
      if (q.kind == QuestionKind.choice ||
          q.kind == QuestionKind.fill ||
          q.kind == QuestionKind.solve ||
          q.kind == QuestionKind.response) {
        _kind = q.kind;
        _sequenceMode = q.isSequence;
      }
      if (q.header.title.isNotEmpty) {
        _titleCtrl.text = q.header.title;
      }
      _stemCtrl.text = q.plainText;
      _expCtrl.text = ContentTextUtils.extractPlainText(q.explanation);
      if (q.isSequence) {
        _bankCtrl.text = _extractInitialBankText(q);
        _ansCtrl.text = _extractInitialScalarAnswer(q);
      } else if (q.kind == QuestionKind.choice) {
        final rawOpts = (q.body['options'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList();
        if (rawOpts.isNotEmpty) {
          for (final c in _optionCtrls) {
            c.dispose();
          }
          _optionCtrls.clear();
          _correctOptionIds.clear();
          for (
            var i = 0;
            i < rawOpts.length && i < _optionLetters.length;
            i++
          ) {
            final content = rawOpts[i]['content'];
            final txt = content is List
                ? ContentTextUtils.extractPlainText(
                    content
                        .whereType<Map<Object?, Object?>>()
                        .map(
                          (m) => ContentBlock.fromJson(
                            m.map((k, v) => MapEntry(k.toString(), v)),
                          ),
                        )
                        .toList(),
                  )
                : '';
            _optionCtrls.add(TextEditingController(text: txt));
          }
          while (_optionCtrls.length < 2) {
            _optionCtrls.add(TextEditingController());
          }
          final sets = q.grading['answerSets'] as List<Object?>? ?? const [];
          if (sets.isNotEmpty && sets.first is Map) {
            final exp = (sets.first! as Map)['expected'];
            if (exp is Map && exp['selectedIds'] is List) {
              for (final id in exp['selectedIds'] as List) {
                _correctOptionIds.add(id.toString());
              }
            }
          }
          if (_correctOptionIds.isEmpty) _correctOptionIds.add('A');
        }
      } else {
        _ansCtrl.text = _extractInitialScalarAnswer(q);
      }
    });
  }

  Future<void> _smartPaste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text?.trim() ?? '';
    if (!mounted) return;
    if (clipText.isNotEmpty) {
      _applyParsedText(clipText);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('已从剪贴板智能拆分题干、选项与答案'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final pasteCtrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('智能粘贴拆题'),
        content: TextField(
          controller: pasteCtrl,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴题干、A/B/C/D 选项、答案：/ 解析：或 JSON',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(pasteCtrl.text),
            child: const Text('自动填充'),
          ),
        ],
      ),
    );
    pasteCtrl.dispose();
    if (!mounted || submitted == null || submitted.trim().isEmpty) return;
    _applyParsedText(submitted);
  }

  Future<void> _showSchemaSpec() async {
    final spec = QuestionSchemaCatalog.specFor(_kind);
    final jsonSkeleton = QuestionSchemaCatalog.formattedSkeletonJson(_kind);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = ctx.inou;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.schema_outlined, size: 18, color: t.accent),
              const SizedBox(width: 8),
              Text('${spec.label}结构规范'),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.description,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    spec.generationGuide,
                    style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  InouSurface(
                    subtle: true,
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      jsonSkeleton,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final kpLeaves = widget.appState.kpTree.leaves(subject: _subject);
    final isEditableBasic =
        _kind == QuestionKind.choice ||
        _kind == QuestionKind.fill ||
        _kind == QuestionKind.solve ||
        _kind == QuestionKind.response;

    final compact =
        widget.isSheet || AdaptiveScope.of(context) == WindowClass.compact;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.isSheet ? double.infinity : 560,
        maxHeight: widget.isSheet ? double.infinity : 680,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.existing == null ? '录入新题' : '编辑题目',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      if (_continuousSavedCount > 0) ...[
                        const SizedBox(width: 8),
                        InouBadge(
                          label: '已录 $_continuousSavedCount 题',
                          tone: InouBadgeTone.success,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '智能粘贴拆题',
                  onPressed: _smartPaste,
                  icon: const Icon(Icons.content_paste_go_rounded, size: 19),
                ),
                IconButton(
                  tooltip: '题型结构规范',
                  onPressed: _showSchemaSpec,
                  icon: const Icon(Icons.schema_outlined, size: 19),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEditableBasic)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final opt
                              in const <
                                ({String label, QuestionKind kind, bool seq})
                              >[
                                (
                                  label: '选择题',
                                  kind: QuestionKind.choice,
                                  seq: false,
                                ),
                                (
                                  label: '填空题',
                                  kind: QuestionKind.fill,
                                  seq: false,
                                ),
                                (
                                  label: '排序题',
                                  kind: QuestionKind.fill,
                                  seq: true,
                                ),
                                (
                                  label: '解答题',
                                  kind: QuestionKind.solve,
                                  seq: false,
                                ),
                                (
                                  label: '简答题',
                                  kind: QuestionKind.response,
                                  seq: false,
                                ),
                              ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(opt.label),
                                selected:
                                    _kind == opt.kind &&
                                    _sequenceMode == opt.seq,
                                onSelected: (_) => setState(() {
                                  _kind = opt.kind;
                                  _sequenceMode = opt.seq;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (compact) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _subject,
                      decoration: InputDecoration(
                        labelText: _autoDetectedFromInput && !_subjectLocked
                            ? '学科（已按题干自动识别）'
                            : '学科',
                      ),
                      items: [
                        for (final entry in SubjectCatalog.labels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        final leaves = widget.appState.kpTree.leaves(
                          subject: v,
                        );
                        setState(() {
                          _subject = v;
                          _subjectLocked = true;
                          _autoDetectedFromInput = false;
                          _selectedKpId = leaves.firstOrNull?.id;
                        });
                      },
                    ),
                    if (kpLeaves.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: kpLeaves.any((k) => k.id == _selectedKpId)
                            ? _selectedKpId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '知识点'),
                        items: [
                          for (final k in kpLeaves)
                            DropdownMenuItem(
                              value: k.id,
                              child: Text(
                                k.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selectedKpId = v),
                      ),
                    ],
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _subject,
                            decoration: InputDecoration(
                              labelText:
                                  _autoDetectedFromInput && !_subjectLocked
                                  ? '学科（已自动识别）'
                                  : '学科',
                            ),
                            items: [
                              for (final entry in SubjectCatalog.labels.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              final leaves = widget.appState.kpTree.leaves(
                                subject: v,
                              );
                              setState(() {
                                _subject = v;
                                _subjectLocked = true;
                                _autoDetectedFromInput = false;
                                _selectedKpId = leaves.firstOrNull?.id;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (kpLeaves.isNotEmpty)
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  kpLeaves.any((k) => k.id == _selectedKpId)
                                  ? _selectedKpId
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '知识点',
                              ),
                              items: [
                                for (final k in kpLeaves)
                                  DropdownMenuItem(
                                    value: k.id,
                                    child: Text(
                                      k.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedKpId = v),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题（选填，留空自动提取）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _stemCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '题干正文 *'),
                  ),
                  if (_kind == QuestionKind.choice) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '选项（勾选右侧设为正确答案）',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (_optionCtrls.length < _optionLetters.length)
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _optionCtrls.add(TextEditingController()),
                            ),
                            icon: const Icon(Icons.add, size: 15),
                            label: const Text('加选项'),
                          ),
                        if (_optionCtrls.length > 2)
                          TextButton(
                            onPressed: () => setState(() {
                              final removed = _optionCtrls.removeLast();
                              removed.dispose();
                            }),
                            child: const Text('删末项'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < _optionCtrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _optionCtrls[i],
                                decoration: InputDecoration(
                                  labelText: '选项 ${_optionLetters[i]}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              label: Text(_optionLetters[i]),
                              selected: _correctOptionIds.contains(
                                _optionLetters[i],
                              ),
                              onSelected: (on) {
                                setState(() {
                                  final id = _optionLetters[i];
                                  if (on) {
                                    _correctOptionIds.add(id);
                                  } else if (_correctOptionIds.length > 1) {
                                    _correctOptionIds.remove(id);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                  ] else if (_kind == QuestionKind.fill && _sequenceMode) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bankCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '待排序词块 / 句段（用 / 或换行分隔）*',
                        hintText: '如：How / are / you / ? 或每行一句 ① ...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ansCtrl,
                      decoration: const InputDecoration(
                        labelText: '标准排序（序号如 3,1,2 / ③①② 或完整句子）',
                      ),
                    ),
                  ] else if (isEditableBasic) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ansCtrl,
                      decoration: const InputDecoration(
                        labelText: '参考答案（支持数值或文本）',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _expCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '参考解析（选填）'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tagsCtrl,
                    decoration: const InputDecoration(labelText: '标签（空格分隔，选填）'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 20,
              10,
              compact ? 14 : 20,
              14,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  if (widget.onSaveAndNext != null && widget.existing == null)
                    OutlinedButton(
                      onPressed: _savingNext ? null : _saveAndContinue,
                      child: const Text('保存并录下一题'),
                    ),
                  FilledButton(
                    onPressed: _saveAndClose,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

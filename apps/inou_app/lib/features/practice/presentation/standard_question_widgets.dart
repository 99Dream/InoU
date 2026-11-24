import 'dart:convert';
import 'dart:math' as math;

import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:inou_ink/render.dart';
import 'package:inou_ui_kit/inou_ui_kit.dart';
import 'package:material_ui/material_ui.dart';

/// Interactive standard input widget dispatching across all 10 [QuestionKind]s
/// (`choice`, `fill`, `match`, `classify`, `response`, `group`, `solve`, `draw`,
/// `spatial`, `write`).
class StandardQuestionWidget extends StatelessWidget {
  const StandardQuestionWidget({
    super.key,
    required this.question,
    required this.response,
    required this.onChanged,
    this.readOnly = false,
  });

  final Question question;
  final StudentResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return switch (question.kind) {
      QuestionKind.choice => _ChoiceInputWidget(
        question: question,
        response: response is ChoiceResponse
            ? response! as ChoiceResponse
            : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.fill => _FillInputWidget(
        question: question,
        response: response is FillResponse ? response! as FillResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.match => _MatchInputWidget(
        question: question,
        response: response is MatchResponse ? response! as MatchResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.classify => _ClassifyInputWidget(
        question: question,
        response: response is ClassifyResponse
            ? response! as ClassifyResponse
            : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.response => _TextResponseWidget(
        question: question,
        response: response is TextResponse ? response! as TextResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.solve => _SolveInputWidget(
        question: question,
        response: response is SolveResponse ? response! as SolveResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.draw => _DrawInputWidget(
        question: question,
        response: response is DrawResponse ? response! as DrawResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.spatial => _SpatialInputWidget(
        question: question,
        response: response is SpatialResponse
            ? response! as SpatialResponse
            : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.write => _WriteInputWidget(
        question: question,
        response: response is WriteResponse ? response! as WriteResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
      QuestionKind.group => _GroupInputWidget(
        question: question,
        response: response is GroupResponse ? response! as GroupResponse : null,
        onChanged: onChanged,
        readOnly: readOnly,
      ),
    };
  }
}

List<ContentBlock> _parseBlocks(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map(
        (m) =>
            ContentBlock.fromJson(m.map((k, v) => MapEntry(k.toString(), v))),
      )
      .toList(growable: false);
}

// -----------------------------------------------------------------------------
// 1. Choice (single & multi)
// -----------------------------------------------------------------------------

class _ChoiceInputWidget extends StatelessWidget {
  const _ChoiceInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final ChoiceResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final options = (question.body['options'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final maxSel = (question.rules['maxSelections'] as num?)?.toInt() ?? 1;
    final selected = response?.selectedIds ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: question.prompt),
        const SizedBox(height: 14),
        for (final opt in options) ...[
          Builder(
            builder: (context) {
              final optId = opt['id']?.toString() ?? '';
              final isSelected = selected.contains(optId);
              final content = _parseBlocks(opt['content']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InouSurface(
                  onTap: readOnly
                      ? null
                      : () {
                          final next = List<String>.from(selected);
                          if (maxSel == 1) {
                            next
                              ..clear()
                              ..add(optId);
                          } else {
                            if (isSelected) {
                              next.remove(optId);
                            } else if (next.length < maxSel) {
                              next.add(optId);
                            }
                          }
                          onChanged(
                            ChoiceResponse(
                              questionId: question.id,
                              inputMode: InputMode.standard,
                              selectedIds: next,
                            ),
                          );
                        },
                  borderWidth: isSelected ? 2.0 : 0.9,
                  borderColor: isSelected ? t.accent : t.borderHairline,
                  backgroundColor: isSelected
                      ? t.accent.withValues(alpha: t.isDark ? 0.28 : 0.14)
                      : t.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isSelected ? t.accent : t.surfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            optId,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isSelected
                                  ? Colors.white
                                  : t.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: ContentBlockRenderer(blocks: content)),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 19,
                          color: t.accent,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. Fill (text/numeric + math keypad + fill.sequence bank)
// -----------------------------------------------------------------------------

class _FillInputWidget extends StatefulWidget {
  const _FillInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final FillResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_FillInputWidget> createState() => _FillInputWidgetState();
}

class _FillInputWidgetState extends State<_FillInputWidget> {
  final Map<String, TextEditingController> _controllers = {};
  String? _activeSlotId;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _FillInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _activeSlotId = null;
    }
    _syncControllers();
  }

  void _syncControllers() {
    final slots = (widget.question.body['slots'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    for (final s in slots) {
      final sid = s['id']?.toString() ?? 's1';
      _activeSlotId ??= sid;
      final val = widget.response?.textEntries[sid] ?? '';
      final ctrl = _controllers.putIfAbsent(
        sid,
        () => TextEditingController(text: val),
      );
      if (ctrl.text != val) {
        ctrl.text = val;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emitTextMap() {
    final entries = <String, String>{
      for (final e in _controllers.entries) e.key: e.value.text,
    };
    widget.onChanged(
      FillResponse(
        questionId: widget.question.id,
        inputMode: InputMode.standard,
        textEntries: entries,
        itemEntries: widget.response?.itemEntries ?? const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final slots = (widget.question.body['slots'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final bank = (widget.question.body['bank'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final isSequence =
        widget.question.presentation.interaction == 'fill.sequence' ||
        bank.isNotEmpty;

    if (isSequence && bank.isNotEmpty) {
      final slotId = slots.isNotEmpty
          ? (slots.first['id']?.toString() ?? 's1')
          : 's1';
      final chosenIds =
          widget.response?.itemEntries[slotId] ?? const <String>[];
      final bankById = {
        for (final b in bank)
          (b['id']?.toString() ?? ''): ContentTextUtils.extractPlainText(
            _parseBlocks(b['content']),
          ),
      };
      final chosenText = chosenIds.map((id) => bankById[id] ?? id).join(' ');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContentBlockRenderer(
            blocks: widget.question.prompt,
            slotValues: {slotId: chosenText},
            activeSlotId: slotId,
          ),
          const SizedBox(height: 14),
          InouSurface(
            backgroundColor: t.surfaceMuted,
            borderColor: chosenIds.isNotEmpty
                ? t.accent.withValues(alpha: 0.45)
                : t.borderHairline,
            borderWidth: chosenIds.isNotEmpty ? 1.2 : 0.9,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已选语序（点击词块或 × 移除）：',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                    if (!widget.readOnly && chosenIds.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          widget.onChanged(
                            FillResponse(
                              questionId: widget.question.id,
                              inputMode: InputMode.standard,
                              itemEntries: {slotId: const []},
                            ),
                          );
                        },
                        child: const Text('清空'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (chosenIds.isEmpty)
                  Text(
                    '请按顺序点击下方词块完成拼句',
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < chosenIds.length; i++)
                        Builder(
                          builder: (context) {
                            void removeThis() {
                              final next = List<String>.from(chosenIds)
                                ..removeAt(i);
                              widget.onChanged(
                                FillResponse(
                                  questionId: widget.question.id,
                                  inputMode: InputMode.standard,
                                  itemEntries: {slotId: next},
                                ),
                              );
                            }

                            return InputChip(
                              selected: true,
                              showCheckmark: false,
                              deleteIconColor: Colors.white,
                              label: Text(
                                '${i + 1}. ${bankById[chosenIds[i]] ?? chosenIds[i]}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              onPressed: widget.readOnly ? null : removeThis,
                              onDeleted: widget.readOnly ? null : removeThis,
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '候选词库（点击加入句子）：',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in bank)
                Builder(
                  builder: (context) {
                    final bid = b['id']?.toString() ?? '';
                    final used = chosenIds.contains(bid);
                    final tokenText = bankById[bid] ?? bid;
                    return ActionChip(
                      avatar: used
                          ? Icon(Icons.check_rounded, size: 15, color: t.accent)
                          : null,
                      label: Text(
                        tokenText,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: used ? FontWeight.w500 : FontWeight.w600,
                          color: used ? t.textSecondary : t.textPrimary,
                          decoration: used
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      backgroundColor: used ? t.surfaceMuted : t.surface,
                      side: BorderSide(
                        color: used
                            ? t.borderHairline
                            : t.textMuted.withValues(alpha: 0.45),
                        width: 1.0,
                      ),
                      onPressed: widget.readOnly || used
                          ? null
                          : () {
                              widget.onChanged(
                                FillResponse(
                                  questionId: widget.question.id,
                                  inputMode: InputMode.standard,
                                  itemEntries: {
                                    slotId: [...chosenIds, bid],
                                  },
                                ),
                              );
                            },
                    );
                  },
                ),
            ],
          ),
        ],
      );
    }

    final slotValues = <String, String>{
      for (final e in _controllers.entries) e.key: e.value.text,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(
          blocks: widget.question.prompt,
          slotValues: slotValues,
          activeSlotId: _activeSlotId,
          onSlotTap: (sid) => setState(() => _activeSlotId = sid),
        ),
        const SizedBox(height: 14),
        for (final s in slots)
          Builder(
            builder: (context) {
              final sid = s['id']?.toString() ?? 's1';
              final label = s['label']?.toString() ?? sid;
              final ctrl = _controllers[sid]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: ctrl,
                  readOnly: widget.readOnly,
                  onTap: () => setState(() => _activeSlotId = sid),
                  onChanged: (_) => _emitTextMap(),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: '输入数字、分数（如 1/2）或文本',
                  ),
                ),
              );
            },
          ),
        if (!widget.readOnly && _activeSlotId != null)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sym in const [
                '1/2',
                '√',
                'π',
                '±',
                '²',
                '/',
                '-',
                '.',
              ])
                ActionChip(
                  label: Text(sym),
                  onPressed: () {
                    final ctrl = _controllers[_activeSlotId!];
                    if (ctrl == null) return;
                    ctrl.text = '${ctrl.text}$sym';
                    _emitTextMap();
                    setState(() {});
                  },
                ),
            ],
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 3. Match (interactive two-column linking)
// -----------------------------------------------------------------------------

class _MatchInputWidget extends StatefulWidget {
  const _MatchInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final MatchResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_MatchInputWidget> createState() => _MatchInputWidgetState();
}

class _MatchInputWidgetState extends State<_MatchInputWidget> {
  String? _activeLeftId;

  @override
  void didUpdateWidget(covariant _MatchInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _activeLeftId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final left = (widget.question.body['left'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final right = (widget.question.body['right'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final pairs = Map<String, String>.from(widget.response?.pairs ?? const {});

    final rightTitles = {
      for (final r in right)
        (r['id']?.toString() ?? ''): ContentTextUtils.extractPlainText(
          _parseBlocks(r['content']),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 8),
        Text(
          '操作提示：先点左侧项目，再点右侧对应项配对；点击已配对标签可解除。',
          style: TextStyle(fontSize: 12, color: t.textSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final l in left)
                    Builder(
                      builder: (context) {
                        final lid = l['id']?.toString() ?? '';
                        final linkedR = pairs[lid];
                        final active = _activeLeftId == lid;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InouSurface(
                            onTap: widget.readOnly
                                ? null
                                : () => setState(
                                    () => _activeLeftId = active ? null : lid,
                                  ),
                            borderWidth: active || linkedR != null ? 1.8 : 0.9,
                            borderColor: active
                                ? t.accent
                                : (linkedR != null
                                      ? t.success
                                      : t.borderHairline),
                            backgroundColor: active
                                ? t.accent.withValues(
                                    alpha: t.isDark ? 0.28 : 0.14,
                                  )
                                : t.surface,
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ContentBlockRenderer(
                                    blocks: _parseBlocks(l['content']),
                                  ),
                                ),
                                if (linkedR != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 112,
                                      ),
                                      child: GestureDetector(
                                        onTap: widget.readOnly
                                            ? null
                                            : () {
                                                final next =
                                                    Map<String, String>.from(
                                                      pairs,
                                                    )..remove(lid);
                                                widget.onChanged(
                                                  MatchResponse(
                                                    questionId:
                                                        widget.question.id,
                                                    inputMode:
                                                        InputMode.standard,
                                                    pairs: next,
                                                  ),
                                                );
                                              },
                                        child: InouBadge(
                                          label: widget.readOnly
                                              ? '→ ${rightTitles[linkedR] ?? linkedR}'
                                              : '→ ${rightTitles[linkedR] ?? linkedR} ×',
                                          tone: InouBadgeTone.success,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final r in right)
                    Builder(
                      builder: (context) {
                        final rid = r['id']?.toString() ?? '';
                        final linkedToMe = pairs.values.contains(rid);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InouSurface(
                            onTap: widget.readOnly || _activeLeftId == null
                                ? null
                                : () {
                                    final next = Map<String, String>.from(pairs)
                                      ..[_activeLeftId!] = rid;
                                    widget.onChanged(
                                      MatchResponse(
                                        questionId: widget.question.id,
                                        inputMode: InputMode.standard,
                                        pairs: next,
                                      ),
                                    );
                                    setState(() => _activeLeftId = null);
                                  },
                            borderWidth: linkedToMe
                                ? 1.8
                                : (_activeLeftId != null ? 1.4 : 0.9),
                            borderColor: linkedToMe
                                ? t.success
                                : (_activeLeftId != null
                                      ? t.accent.withValues(alpha: 0.65)
                                      : t.borderHairline),
                            backgroundColor: linkedToMe
                                ? t.successSoft
                                : t.surface,
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ContentBlockRenderer(
                                    blocks: _parseBlocks(r['content']),
                                  ),
                                ),
                                if (linkedToMe) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: t.success,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 4. Classify (tap item -> tap category bin)
// -----------------------------------------------------------------------------

class _ClassifyInputWidget extends StatefulWidget {
  const _ClassifyInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final ClassifyResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_ClassifyInputWidget> createState() => _ClassifyInputWidgetState();
}

class _ClassifyInputWidgetState extends State<_ClassifyInputWidget> {
  String? _selectedItemId;

  @override
  void didUpdateWidget(covariant _ClassifyInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _selectedItemId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final items = (widget.question.body['items'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final categories =
        (widget.question.body['categories'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList();
    final placements = Map<String, String?>.from(
      widget.response?.placements ?? const {},
    );

    final itemTitles = {
      for (final item in items)
        (item['id']?.toString() ?? ''): ContentTextUtils.extractPlainText(
          _parseBlocks(item['content']),
        ),
    };

    Widget buildCategoryBucket(Map<Object?, Object?> cat) {
      final cid = cat['id']?.toString() ?? '';
      final cLabel = ContentTextUtils.extractPlainText(
        _parseBlocks(cat['content']),
      );
      final insideIds = placements.entries
          .where((e) => e.value == cid)
          .map((e) => e.key)
          .toList();
      final isWaitingDrop = _selectedItemId != null && !widget.readOnly;
      return InouSurface(
        onTap: widget.readOnly || _selectedItemId == null
            ? null
            : () {
                final next = Map<String, String?>.from(placements)
                  ..[_selectedItemId!] = cid;
                widget.onChanged(
                  ClassifyResponse(
                    questionId: widget.question.id,
                    inputMode: InputMode.standard,
                    placements: next,
                  ),
                );
                setState(() => _selectedItemId = null);
              },
        backgroundColor: t.surfaceMuted,
        borderWidth: isWaitingDrop ? 1.6 : 0.9,
        borderColor: isWaitingDrop ? t.accent : t.borderHairline,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (insideIds.isEmpty)
              Text(
                isWaitingDrop ? '点击此处放入已选条目' : '点击上方条目后放入此处',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isWaitingDrop ? FontWeight.w600 : FontWeight.w400,
                  color: isWaitingDrop ? t.accent : t.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final iid in insideIds)
                    Builder(
                      builder: (context) {
                        void removeItem() {
                          final next = Map<String, String?>.from(placements)
                            ..remove(iid);
                          widget.onChanged(
                            ClassifyResponse(
                              questionId: widget.question.id,
                              inputMode: InputMode.standard,
                              placements: next,
                            ),
                          );
                        }

                        return InputChip(
                          selected: true,
                          showCheckmark: false,
                          deleteIconColor: Colors.white,
                          label: Text(
                            itemTitles[iid] ?? iid,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: widget.readOnly ? null : removeItem,
                          onDeleted: widget.readOnly ? null : removeItem,
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 10),
        Text(
          '先点击待分类条目，再点下方目标分类桶（点击桶内词块可移除）：',
          style: TextStyle(fontSize: 12, color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              Builder(
                builder: (context) {
                  final iid = item['id']?.toString() ?? '';
                  final placed = placements[iid] != null;
                  final active = _selectedItemId == iid;
                  return ChoiceChip(
                    showCheckmark: false,
                    label: Text(itemTitles[iid] ?? iid),
                    selected: active,
                    avatar: placed
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: active ? Colors.white : t.success,
                          )
                        : null,
                    onSelected: widget.readOnly
                        ? null
                        : (_) => setState(
                            () => _selectedItemId = active ? null : iid,
                          ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stackVertical =
                (constraints.maxWidth < 460 && categories.length > 2) ||
                constraints.maxWidth < 320;
            if (stackVertical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var idx = 0; idx < categories.length; idx++) ...[
                    if (idx > 0) const SizedBox(height: 10),
                    buildCategoryBucket(categories[idx]),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var idx = 0; idx < categories.length; idx++) ...[
                  if (idx > 0) const SizedBox(width: 10),
                  Expanded(child: buildCategoryBucket(categories[idx])),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 5. Response (multi-part open text response)
// -----------------------------------------------------------------------------

class _TextResponseWidget extends StatefulWidget {
  const _TextResponseWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final TextResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_TextResponseWidget> createState() => _TextResponseWidgetState();
}

class _TextResponseWidgetState extends State<_TextResponseWidget> {
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TextResponseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
    }
    _sync();
  }

  void _sync() {
    final parts = (widget.question.body['parts'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    if (parts.isEmpty) {
      final c = _ctrls.putIfAbsent(
        'p1',
        () => TextEditingController(text: widget.response?.parts['p1'] ?? ''),
      );
      c.text = widget.response?.parts['p1'] ?? c.text;
    } else {
      for (final p in parts) {
        final pid = p['id']?.toString() ?? 'p1';
        _ctrls.putIfAbsent(
          pid,
          () => TextEditingController(text: widget.response?.parts[pid] ?? ''),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = (widget.question.body['parts'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final effectiveParts = parts.isEmpty
        ? [
            {'id': 'p1', 'label': '简答作答区'},
          ]
        : parts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 12),
        for (final p in effectiveParts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _ctrls[p['id']?.toString() ?? 'p1'],
              readOnly: widget.readOnly,
              maxLines: 3,
              onChanged: (_) {
                widget.onChanged(
                  TextResponse(
                    questionId: widget.question.id,
                    inputMode: InputMode.standard,
                    parts: {
                      for (final e in _ctrls.entries) e.key: e.value.text,
                    },
                  ),
                );
              },
              decoration: InputDecoration(
                labelText: p['label']?.toString() ?? '作答',
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 6. Solve (steps + final answer box)
// -----------------------------------------------------------------------------

class _SolveInputWidget extends StatefulWidget {
  const _SolveInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final SolveResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_SolveInputWidget> createState() => _SolveInputWidgetState();
}

class _SolveInputWidgetState extends State<_SolveInputWidget> {
  late final TextEditingController _stepsCtrl = TextEditingController(
    text: widget.response?.steps.join('\n') ?? '',
  );
  late final TextEditingController _finalCtrl = TextEditingController(
    text: widget.response?.finalAnswer ?? '',
  );

  @override
  void didUpdateWidget(covariant _SolveInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _stepsCtrl.text = widget.response?.steps.join('\n') ?? '';
      _finalCtrl.text = widget.response?.finalAnswer ?? '';
    }
  }

  @override
  void dispose() {
    _stepsCtrl.dispose();
    _finalCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final lines = _stepsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    widget.onChanged(
      SolveResponse(
        questionId: widget.question.id,
        inputMode: InputMode.standard,
        steps: lines,
        finalAnswer: _finalCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final finSlot =
        widget.question.body['finalAnswerSlot'] as Map<Object?, Object?>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 12),
        TextField(
          controller: _stepsCtrl,
          readOnly: widget.readOnly,
          maxLines: 4,
          onChanged: (_) => _emit(),
          decoration: const InputDecoration(
            labelText: '关键推导过程（每行一步，也可切换平板稿纸手写）',
            hintText: '例如：\n由判别式 Δ = (-4)² - 4k = 0\n解得 k = 4',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _finalCtrl,
          readOnly: widget.readOnly,
          onChanged: (_) => _emit(),
          decoration: InputDecoration(
            labelText: finSlot?['label']?.toString() ?? '最终结果（用于自动核验）',
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 7. Draw (embedded InouInkCanvas pad + PNG export into DrawResponse)
// -----------------------------------------------------------------------------

class _DrawInputWidget extends StatefulWidget {
  const _DrawInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final DrawResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_DrawInputWidget> createState() => _DrawInputWidgetState();
}

class _DrawInputWidgetState extends State<_DrawInputWidget> {
  late final InkController _ink = InkController(
    initialPage: const InkPageData(pageW: 420, pageH: 250),
    backgroundKind: PaperBackgroundKind.grid,
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.response?.note ?? '',
  );

  @override
  void initState() {
    super.initState();
    _ink.addListener(_onInkChanged);
  }

  @override
  void didUpdateWidget(covariant _DrawInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _ink.clearAll();
      _noteCtrl.text = widget.response?.note ?? '';
    }
  }

  @override
  void dispose() {
    _ink.removeListener(_onInkChanged);
    _ink.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _onInkChanged() async {
    if (_ink.activeLiveStroke != null) return;
    final png = await InkSnapshotExporter.exportRegionPng(
      _ink.page,
      pixelRatio: 1.5,
    );
    widget.onChanged(
      DrawResponse(
        questionId: widget.question.id,
        inputMode: InputMode.standard,
        inkRegionId: 'draw_${widget.question.id}',
        composedPngBase64: png == null ? null : base64Encode(png),
        note: _noteCtrl.text.trim().isNotEmpty
            ? _noteCtrl.text.trim()
            : '已绘制 ${_ink.page.strokes.length} 笔',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 10),
        Row(
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: Icon(
                Icons.edit_outlined,
                size: 16,
                color: _ink.activeTool == InkToolKind.pen
                    ? Colors.white
                    : t.textPrimary,
              ),
              label: const Text('画笔'),
              selected: _ink.activeTool == InkToolKind.pen,
              onSelected: (_) => setState(() => _ink.setTool(InkToolKind.pen)),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              showCheckmark: false,
              avatar: Icon(
                Icons.auto_fix_normal,
                size: 16,
                color: _ink.activeTool == InkToolKind.eraser
                    ? Colors.white
                    : t.textPrimary,
              ),
              label: const Text('橡皮'),
              selected: _ink.activeTool == InkToolKind.eraser,
              onSelected: (_) =>
                  setState(() => _ink.setTool(InkToolKind.eraser)),
            ),
            const Spacer(),
            IconButton(
              tooltip: '撤销',
              onPressed: _ink.canUndo ? _ink.undo : null,
              icon: const Icon(Icons.undo, size: 18),
            ),
            TextButton(onPressed: _ink.clearAll, child: const Text('清屏')),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            height: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.borderHairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InouInkCanvas(controller: _ink, readOnly: widget.readOnly),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          readOnly: widget.readOnly,
          onChanged: (_) => _onInkChanged(),
          decoration: const InputDecoration(
            labelText: '作图关键点说明（可选，例如过 (0,-2) 与 (1,0)）',
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 8. Spatial (coordinate targets + label placements)
// -----------------------------------------------------------------------------

class _SpatialInputWidget extends StatefulWidget {
  const _SpatialInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final SpatialResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_SpatialInputWidget> createState() => _SpatialInputWidgetState();
}

class _SpatialInputWidgetState extends State<_SpatialInputWidget> {
  String? _activeLabelId;

  @override
  void didUpdateWidget(covariant _SpatialInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      _activeLabelId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final targets =
        (widget.question.body['targets'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList();
    final labels =
        (widget.question.body['labels'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList();
    final placements = Map<String, String>.from(
      widget.response?.placements ?? const {},
    );
    final labelTextById = {
      for (final lb in labels)
        (lb['id']?.toString() ?? ''): ContentTextUtils.extractPlainText(
          _parseBlocks(lb['content']),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 10),
        if (labels.isNotEmpty) ...[
          Text(
            '先点击标签词，再点下方图谱标号区放入；再点已填标号可移除：',
            style: TextStyle(fontSize: 12, color: t.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final lb in labels)
                Builder(
                  builder: (context) {
                    final lid = lb['id']?.toString() ?? '';
                    final placed = placements.containsKey(lid);
                    final isActive = _activeLabelId == lid;
                    return ChoiceChip(
                      showCheckmark: false,
                      label: Text(labelTextById[lid] ?? lid),
                      selected: isActive,
                      avatar: placed
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: isActive ? Colors.white : t.success,
                            )
                          : null,
                      onSelected: widget.readOnly
                          ? null
                          : (_) => setState(
                              () => _activeLabelId = isActive ? null : lid,
                            ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: t.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.borderHairline),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final h = c.maxHeight;
                return GestureDetector(
                  onTapDown: widget.readOnly || labels.isNotEmpty
                      ? null
                      : (details) {
                          final nx = details.localPosition.dx / w;
                          final ny = details.localPosition.dy / h;
                          widget.onChanged(
                            SpatialResponse(
                              questionId: widget.question.id,
                              inputMode: InputMode.standard,
                              points: [
                                ...(widget.response?.points ?? const []),
                                (nx, ny),
                              ],
                              placements: placements,
                            ),
                          );
                        },
                  child: Stack(
                    children: [
                      // Schematic outline representing diagram canvas
                      Center(
                        child: Container(
                          width: w * 0.72,
                          height: h * 0.74,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: t.borderHairline,
                              width: 2,
                            ),
                            color: t.surface,
                          ),
                        ),
                      ),
                      for (final tgt in targets)
                        _buildTargetHotspot(
                          tgt,
                          w,
                          h,
                          t,
                          placements,
                          labelTextById,
                        ),
                      for (final pt
                          in widget.response?.points ??
                              const <(double, double)>[])
                        Positioned(
                          left: pt.$1 * w - 7,
                          top: pt.$2 * h - 7,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: t.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetHotspot(
    Map<Object?, Object?> tgt,
    double w,
    double h,
    InouTokens t,
    Map<String, String> placements,
    Map<String, String> labelTextById,
  ) {
    final tid = tgt['id']?.toString() ?? '';
    final marker = tgt['label']?.toString() ?? tid;
    final shape = tgt['shape'] as Map<Object?, Object?>? ?? const {};
    final isCircle = shape['type'] == 'circle';
    final left = isCircle
        ? (((shape['cx'] as num?)?.toDouble() ?? 0.5) -
                  ((shape['r'] as num?)?.toDouble() ?? 0.08)) *
              w
        : ((shape['x'] as num?)?.toDouble() ?? 0.1) * w;
    final top = isCircle
        ? (((shape['cy'] as num?)?.toDouble() ?? 0.5) -
                  ((shape['r'] as num?)?.toDouble() ?? 0.08)) *
              h
        : ((shape['y'] as num?)?.toDouble() ?? 0.1) * h;
    final boxW = math.max(
      64.0,
      isCircle
          ? ((shape['r'] as num?)?.toDouble() ?? 0.08) * 2 * w
          : ((shape['w'] as num?)?.toDouble() ?? 0.16) * w,
    );
    final boxH = math.max(
      34.0,
      isCircle
          ? ((shape['r'] as num?)?.toDouble() ?? 0.08) * 2 * h
          : ((shape['h'] as num?)?.toDouble() ?? 0.14) * h,
    );

    final assignedLabelId = placements.entries
        .where((e) => e.value == tid)
        .map((e) => e.key)
        .firstOrNull;

    final hasAssigned = assignedLabelId != null;
    final hasActiveSelection = _activeLabelId != null;
    return Positioned(
      left: left.clamp(0.0, math.max(0.0, w - boxW)),
      top: top.clamp(0.0, math.max(0.0, h - boxH)),
      width: boxW,
      height: boxH,
      child: GestureDetector(
        onTap: widget.readOnly || (!hasActiveSelection && !hasAssigned)
            ? null
            : () {
                final next = Map<String, String>.from(placements);
                if (hasActiveSelection) {
                  next
                    ..removeWhere((_, v) => v == tid)
                    ..[_activeLabelId!] = tid;
                } else {
                  next.removeWhere((_, v) => v == tid);
                }
                widget.onChanged(
                  SpatialResponse(
                    questionId: widget.question.id,
                    inputMode: InputMode.standard,
                    points: widget.response?.points ?? const [],
                    placements: next,
                  ),
                );
                if (hasActiveSelection) {
                  setState(() => _activeLabelId = null);
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: hasAssigned
                ? t.accent
                : (hasActiveSelection ? t.accentSoft : t.surface),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasAssigned || hasActiveSelection
                  ? t.accent
                  : t.borderHairline,
              width: hasAssigned || hasActiveSelection ? 1.8 : 1,
            ),
          ),
          child: Center(
            child: Text(
              hasAssigned
                  ? '$marker ${labelTextById[assignedLabelId] ?? assignedLabelId}'
                  : marker,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: hasAssigned ? Colors.white : t.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 9. Write (hanzi / English dictation cells)
// -----------------------------------------------------------------------------

class _WriteInputWidget extends StatefulWidget {
  const _WriteInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final WriteResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  State<_WriteInputWidget> createState() => _WriteInputWidgetState();
}

class _WriteInputWidgetState extends State<_WriteInputWidget> {
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _syncCells();
  }

  @override
  void didUpdateWidget(covariant _WriteInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
    }
    _syncCells();
  }

  void _syncCells() {
    final cells = (widget.question.body['cells'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>();
    for (final c in cells) {
      final cid = c['id']?.toString() ?? 'c1';
      final val = widget.response?.cells[cid] ?? '';
      final ctrl = _ctrls.putIfAbsent(
        cid,
        () => TextEditingController(text: val),
      );
      if (ctrl.text != val) {
        ctrl.text = val;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final cells = (widget.question.body['cells'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: widget.question.prompt),
        const SizedBox(height: 12),
        for (final c in cells)
          Builder(
            builder: (context) {
              final cid = c['id']?.toString() ?? 'c1';
              final blocks = _parseBlocks(c['prompt']);
              final ctrl = _ctrls.putIfAbsent(cid, TextEditingController.new);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InouSurface(
                  backgroundColor: t.surfaceMuted,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ContentBlockRenderer(blocks: blocks),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl,
                        readOnly: widget.readOnly,
                        onChanged: (_) {
                          widget.onChanged(
                            WriteResponse(
                              questionId: widget.question.id,
                              inputMode: InputMode.standard,
                              cells: {
                                for (final e in _ctrls.entries)
                                  e.key: e.value.text,
                              },
                            ),
                          );
                        },
                        decoration: const InputDecoration(
                          hintText: '书写/键入字词或默写句…',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 10. Group (passage + nested sub-questions)
// -----------------------------------------------------------------------------

class _GroupInputWidget extends StatelessWidget {
  const _GroupInputWidget({
    required this.question,
    required this.response,
    required this.onChanged,
    required this.readOnly,
  });

  final Question question;
  final GroupResponse? response;
  final ValueChanged<StudentResponse> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final subQuestions = question.toPublicView().subQuestions;
    final children = Map<String, StudentResponse>.from(
      response?.children ?? const {},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentBlockRenderer(blocks: question.prompt),
        const SizedBox(height: 14),
        for (var i = 0; i < subQuestions.length; i++) ...[
          InouSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InouBadge(label: '第 ${i + 1} 小题'),
                const SizedBox(height: 8),
                StandardQuestionWidget(
                  question: subQuestions[i],
                  response: children[subQuestions[i].id],
                  readOnly: readOnly,
                  onChanged: (subResp) {
                    final next = Map<String, StudentResponse>.from(children)
                      ..[subQuestions[i].id] = subResp;
                    onChanged(
                      GroupResponse(
                        questionId: question.id,
                        inputMode: InputMode.standard,
                        children: next,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

import 'package:meta/meta.dart';

import 'content_block.dart';
import 'enums.dart';
import 'question_models.dart';

/// Machine-readable issue produced by two-stage question validators and fed
/// into `P-03` JSON repair prompts when validating AI drafts.
@immutable
class ValidationIssue {
  const ValidationIssue({
    required this.path,
    required this.code,
    required this.message,
  });

  final String path;
  final String code;
  final String message;

  Map<String, Object?> toJson() => {
    'path': path,
    'code': code,
    'message': message,
  };

  @override
  String toString() => '[$code] $path: $message';
}

/// Validates schema version, block allowlists, LaTeX brace balance, and bounds.
class QuestionStructureValidator {
  const QuestionStructureValidator();

  static const int maxTextLength = 12000;
  static const int maxLatexLength = 2000;

  List<ValidationIssue> validate(Question q) {
    final issues = <ValidationIssue>[];
    if (q.schema != 1) {
      issues.add(
        ValidationIssue(
          path: 'schema',
          code: 'unsupported_schema',
          message: '仅支持 schema == 1，当前为 ${q.schema}',
        ),
      );
    }
    if (q.prompt.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'prompt',
          code: 'empty_prompt',
          message: '题干 prompt 不能为空',
        ),
      );
    }
    _validateBlocks(q.prompt, 'prompt', issues);
    _validateBlocks(q.header.description, 'header.description', issues);
    _validateBlocks(q.explanation, 'explanation', issues);
    return issues;
  }

  void _validateBlocks(
    List<ContentBlock> blocks,
    String basePath,
    List<ValidationIssue> issues,
  ) {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final path = '$basePath[$i]';
      switch (b) {
        case TextBlock(:final text):
          if (text.length > maxTextLength) {
            issues.add(
              ValidationIssue(
                path: '$path.text',
                code: 'text_too_long',
                message: '文本超过最大长度 $maxTextLength',
              ),
            );
          }
        case MathBlock(:final latex):
          if (latex.isEmpty) {
            issues.add(
              ValidationIssue(
                path: '$path.latex',
                code: 'empty_latex',
                message: 'MathBlock.latex 不能为空',
              ),
            );
          } else if (latex.length > maxLatexLength) {
            issues.add(
              ValidationIssue(
                path: '$path.latex',
                code: 'latex_too_long',
                message: 'LaTeX 公式长度超过限制',
              ),
            );
          } else if (!_hasBalancedBraces(latex)) {
            issues.add(
              ValidationIssue(
                path: '$path.latex',
                code: 'invalid_latex',
                message: 'KaTeX 公式存在未闭合的花括号：$latex',
              ),
            );
          }
        case TableBlock(:final header, :final rows):
          if (header != null) {
            for (var c = 0; c < header.length; c++) {
              _validateBlocks(header[c], '$path.header[$c]', issues);
            }
          }
          for (var r = 0; r < rows.length; r++) {
            for (var c = 0; c < rows[r].length; c++) {
              _validateBlocks(rows[r][c], '$path.rows[$r][$c]', issues);
            }
          }
        case PassageBlock(:final paragraphs):
          if (paragraphs.isEmpty) {
            issues.add(
              ValidationIssue(
                path: '$path.paragraphs',
                code: 'empty_passage',
                message: 'PassageBlock 至少包含 1 个段落',
              ),
            );
          }
          for (var p = 0; p < paragraphs.length; p++) {
            _validateBlocks(
              paragraphs[p].content,
              '$path.paragraphs[$p].content',
              issues,
            );
          }
        case RichTextBlock():
        case ImageBlock():
        case FigureBlock():
        case SlotBlock():
        case MediaPlaceholderBlock():
          break;
      }
    }
  }

  static bool _hasBalancedBraces(String latex) {
    var depth = 0;
    var escaped = false;
    for (var i = 0; i < latex.length; i++) {
      final ch = latex[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth < 0) return false;
      }
    }
    return depth == 0;
  }
}

/// Validates unique local IDs, non-dangling grading references, and kind constraints.
class QuestionSemanticValidator {
  const QuestionSemanticValidator();

  List<ValidationIssue> validate(Question q) {
    final issues = <ValidationIssue>[];
    switch (q.kind) {
      case QuestionKind.choice:
        _validateChoice(q, issues);
      case QuestionKind.fill:
        _validateFill(q, issues);
      case QuestionKind.match:
        _validateMatch(q, issues);
      case QuestionKind.classify:
        _validateClassify(q, issues);
      case QuestionKind.response:
        _validateResponse(q, issues);
      case QuestionKind.group:
        _validateGroup(q, issues);
      case QuestionKind.solve:
        _validateSolve(q, issues);
      case QuestionKind.draw:
        _validateDraw(q, issues);
      case QuestionKind.spatial:
        _validateSpatial(q, issues);
      case QuestionKind.write:
        _validateWrite(q, issues);
    }
    return issues;
  }

  Set<String> _collectUniqueIds(
    List<Object?> list,
    String basePath,
    List<ValidationIssue> issues,
  ) {
    final seen = <String>{};
    for (var i = 0; i < list.length; i++) {
      final map = list[i];
      if (map is! Map<String, Object?>) continue;
      final id = map['id'];
      if (id is! String || id.isEmpty) {
        issues.add(
          ValidationIssue(
            path: '$basePath[$i].id',
            code: 'missing_id',
            message: '缺少合法局部 id',
          ),
        );
      } else if (!seen.add(id)) {
        issues.add(
          ValidationIssue(
            path: '$basePath[$i].id',
            code: 'duplicate_id',
            message: '局部 id 重复: $id',
          ),
        );
      }
    }
    return seen;
  }

  void _validateChoice(Question q, List<ValidationIssue> issues) {
    final options = q.body['options'];
    if (options is! List<Object?> || options.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.options',
          code: 'empty_options',
          message: '选择题至少需要 2 个选项',
        ),
      );
      return;
    }
    final optionIds = _collectUniqueIds(options, 'body.options', issues);
    final minSel = (q.rules['minSelections'] as int?) ?? 1;
    final maxSel = (q.rules['maxSelections'] as int?) ?? 1;
    if (minSel < 1 || maxSel < minSel || maxSel > options.length) {
      issues.add(
        ValidationIssue(
          path: 'rules',
          code: 'invalid_selection_bounds',
          message:
              '选区范围非法：minSelections=$minSel, maxSelections=$maxSel, options=${options.length}',
        ),
      );
    }
    final answerSets = q.grading['answerSets'];
    if (answerSets is List<Object?>) {
      for (var i = 0; i < answerSets.length; i++) {
        final setMap = answerSets[i] as Map<String, Object?>?;
        final expected = setMap?['expected'] as Map<String, Object?>?;
        final selected = expected?['selectedIds'] as List<Object?>? ?? const [];
        for (var j = 0; j < selected.length; j++) {
          final ref = selected[j] as String?;
          if (ref == null || !optionIds.contains(ref)) {
            issues.add(
              ValidationIssue(
                path: 'grading.answerSets[$i].expected.selectedIds[$j]',
                code: 'dangling_option_ref',
                message: '答案引用了不存在的选项 ID: $ref',
              ),
            );
          }
        }
      }
    }
  }

  void _validateFill(Question q, List<ValidationIssue> issues) {
    final slots = q.body['slots'];
    if (slots is! List<Object?> || slots.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.slots',
          code: 'empty_slots',
          message: '填空题至少需要 1 个 slot',
        ),
      );
      return;
    }
    final slotIds = _collectUniqueIds(slots, 'body.slots', issues);
    final answerSets = q.grading['answerSets'];
    if (answerSets is List<Object?>) {
      for (var i = 0; i < answerSets.length; i++) {
        final setMap = answerSets[i] as Map<String, Object?>?;
        final expected = setMap?['expected'] as Map<String, Object?>?;
        final entries = expected?['entries'] as List<Object?>? ?? const [];
        for (var j = 0; j < entries.length; j++) {
          final entry = entries[j] as Map<String, Object?>?;
          final slotId = entry?['slotId'] as String?;
          if (slotId == null || !slotIds.contains(slotId)) {
            issues.add(
              ValidationIssue(
                path: 'grading.answerSets[$i].expected.entries[$j].slotId',
                code: 'dangling_slot_ref',
                message: '引用了不存在的 slotId: $slotId',
              ),
            );
          }
        }
      }
    }
  }

  void _validateMatch(Question q, List<ValidationIssue> issues) {
    final left = q.body['left'];
    final right = q.body['right'];
    if (left is! List<Object?> ||
        right is! List<Object?> ||
        left.isEmpty ||
        right.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body',
          code: 'empty_match_items',
          message: '连线题需要非空的 left 与 right 列表',
        ),
      );
      return;
    }
    final leftIds = _collectUniqueIds(left, 'body.left', issues);
    final rightIds = _collectUniqueIds(right, 'body.right', issues);
    final answerSets = q.grading['answerSets'];
    if (answerSets is List<Object?>) {
      for (var i = 0; i < answerSets.length; i++) {
        final expected =
            (answerSets[i] as Map<String, Object?>?)?['expected']
                as Map<String, Object?>?;
        final pairs = expected?['pairs'] as List<Object?>? ?? const [];
        for (var j = 0; j < pairs.length; j++) {
          final pair = pairs[j] as Map<String, Object?>?;
          final fromId = pair?['fromId'] as String?;
          final toId = pair?['toId'] as String?;
          if (fromId == null || !leftIds.contains(fromId)) {
            issues.add(
              ValidationIssue(
                path: 'grading.answerSets[$i].expected.pairs[$j].fromId',
                code: 'dangling_left_ref',
                message: 'fromId 不存在: $fromId',
              ),
            );
          }
          if (toId == null || !rightIds.contains(toId)) {
            issues.add(
              ValidationIssue(
                path: 'grading.answerSets[$i].expected.pairs[$j].toId',
                code: 'dangling_right_ref',
                message: 'toId 不存在: $toId',
              ),
            );
          }
        }
      }
    }
  }

  void _validateClassify(Question q, List<ValidationIssue> issues) {
    final items = q.body['items'];
    final cats = q.body['categories'];
    if (items is! List<Object?> ||
        cats is! List<Object?> ||
        items.isEmpty ||
        cats.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body',
          code: 'empty_classify_items',
          message: '分类题需要非空的 items 与 categories',
        ),
      );
      return;
    }
    final itemIds = _collectUniqueIds(items, 'body.items', issues);
    final catIds = _collectUniqueIds(cats, 'body.categories', issues);
    final answerSets = q.grading['answerSets'];
    if (answerSets is List<Object?>) {
      for (var i = 0; i < answerSets.length; i++) {
        final expected =
            (answerSets[i] as Map<String, Object?>?)?['expected']
                as Map<String, Object?>?;
        final placements =
            expected?['placements'] as List<Object?>? ?? const [];
        for (var j = 0; j < placements.length; j++) {
          final pl = placements[j] as Map<String, Object?>?;
          final itemId = pl?['itemId'] as String?;
          final catId = pl?['categoryId'] as String?;
          if (itemId == null || !itemIds.contains(itemId)) {
            issues.add(
              ValidationIssue(
                path: 'grading.answerSets[$i].expected.placements[$j].itemId',
                code: 'dangling_item_ref',
                message: 'itemId 不存在: $itemId',
              ),
            );
          }
          if (catId == null || !catIds.contains(catId)) {
            issues.add(
              ValidationIssue(
                path:
                    'grading.answerSets[$i].expected.placements[$j].categoryId',
                code: 'dangling_category_ref',
                message: 'categoryId 不存在: $catId',
              ),
            );
          }
        }
      }
    }
  }

  void _validateResponse(Question q, List<ValidationIssue> issues) {
    final parts = q.body['parts'];
    if (parts is! List<Object?> || parts.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.parts',
          code: 'empty_response_parts',
          message: '开放作答题至少需要 1 个作答 part',
        ),
      );
      return;
    }
    _collectUniqueIds(parts, 'body.parts', issues);
  }

  void _validateGroup(Question q, List<ValidationIssue> issues) {
    final sub = q.body['questions'];
    if (sub is! List<Object?> || sub.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.questions',
          code: 'empty_group',
          message: '组合题至少包含 1 道小题',
        ),
      );
      return;
    }
    const structValidator = QuestionStructureValidator();
    for (var i = 0; i < sub.length; i++) {
      final raw = sub[i];
      if (raw is! Map<String, Object?>) {
        issues.add(
          ValidationIssue(
            path: 'body.questions[$i]',
            code: 'invalid_sub_question',
            message: '小题结构非法',
          ),
        );
        continue;
      }
      final child = Question.fromJson(raw, fallbackId: '${q.id}_$i');
      if (child.kind == QuestionKind.group) {
        issues.add(
          ValidationIssue(
            path: 'body.questions[$i].kind',
            code: 'nested_group_forbidden',
            message: 'group 题严禁嵌套 group 小题',
          ),
        );
        continue;
      }
      issues.addAll(structValidator.validate(child));
      issues.addAll(validate(child));
    }
  }

  void _validateSolve(Question q, List<ValidationIssue> issues) {
    final steps = q.body['steps'];
    if (steps is List<Object?> && steps.isNotEmpty) {
      _collectUniqueIds(steps, 'body.steps', issues);
    }
  }

  void _validateDraw(Question q, List<ValidationIssue> issues) {
    if (q.body['canvas'] is! Map<String, Object?>) {
      issues.add(
        const ValidationIssue(
          path: 'body.canvas',
          code: 'missing_canvas',
          message: '作图题缺少 body.canvas 定义',
        ),
      );
    }
  }

  void _validateSpatial(Question q, List<ValidationIssue> issues) {
    final targets = q.body['targets'];
    if (targets is! List<Object?> || targets.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.targets',
          code: 'empty_targets',
          message: '看图标注题至少需要 1 个 target 热区',
        ),
      );
      return;
    }
    _collectUniqueIds(targets, 'body.targets', issues);
    for (var i = 0; i < targets.length; i++) {
      final t = targets[i] as Map<String, Object?>?;
      final shape = t?['shape'] as Map<String, Object?>?;
      if (shape == null) continue;
      for (final coordKey in const ['x', 'y', 'w', 'h', 'cx', 'cy', 'r']) {
        final v = shape[coordKey];
        if (v is num && (v < 0.0 || v > 1.0)) {
          issues.add(
            ValidationIssue(
              path: 'body.targets[$i].shape.$coordKey',
              code: 'out_of_normalized_range',
              message: '热区坐标必须在 0..1 之间，当前为 $v',
            ),
          );
        }
      }
    }
  }

  void _validateWrite(Question q, List<ValidationIssue> issues) {
    final cells = q.body['cells'];
    if (cells is! List<Object?> || cells.isEmpty) {
      issues.add(
        const ValidationIssue(
          path: 'body.cells',
          code: 'empty_cells',
          message: '书写题至少需要 1 个格单元',
        ),
      );
      return;
    }
    _collectUniqueIds(cells, 'body.cells', issues);
  }
}

/// Runs both structure and semantic validators together.
List<ValidationIssue> validateQuestionEnvelope(Question q) {
  return [
    ...const QuestionStructureValidator().validate(q),
    ...const QuestionSemanticValidator().validate(q),
  ];
}

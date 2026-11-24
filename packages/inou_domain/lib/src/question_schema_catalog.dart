import 'dart:convert';

import 'package:meta/meta.dart';

import 'content_block.dart';
import 'enums.dart';
import 'question_models.dart';
import 'sequence_question_detector.dart';
import 'subject_detector.dart';

/// Structured schema guide & canonical skeleton for each [QuestionKind],
/// aligned with the `res-hub` question bank protocol (`catalog.json`).
@immutable
class QuestionSchemaSpec {
  const QuestionSchemaSpec({
    required this.kind,
    required this.label,
    required this.description,
    required this.defaultInteraction,
    required this.defaultGradingMode,
    required this.generationGuide,
    required this.skeletonJson,
  });

  final QuestionKind kind;
  final String label;
  final String description;
  final String defaultInteraction;
  final String defaultGradingMode;
  final String generationGuide;
  final Map<String, Object?> skeletonJson;
}

/// Centralized catalog of `res-hub` question schemas, generation guides, and
/// empty structural templates for AI prompting and fast manual/batch entry.
abstract final class QuestionSchemaCatalog {
  static const List<QuestionSchemaSpec> specs = [
    QuestionSchemaSpec(
      kind: QuestionKind.choice,
      label: '选择题',
      description: '从候选项中单选或多选，也适用于判断正误与听读理解。',
      defaultInteraction: 'choice.select',
      defaultGradingMode: 'exact',
      generationGuide:
          '将候选项写入 body.options（每项含稳定 id 与 content ContentBlock 数组，禁止将正确性写入选项本身）；'
          '单选设 rules.minSelections=1, maxSelections=1，多选设 maxSelections>1；'
          '标准答案仅放入 grading.answerSets[0].expected.selectedIds 引用稳定选项 id。',
      skeletonJson: {
        'schema': 1,
        'kind': 'choice',
        'header': {'title': '', 'score': 3},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {
          'options': [
            {
              'id': 'A',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
            {
              'id': 'B',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
          ],
        },
        'rules': {'minSelections': 1, 'maxSelections': 1},
        'presentation': {
          'interaction': 'choice.select',
          'config': {'layout': 'list'},
        },
        'grading': {
          'mode': 'exact',
          'maxScore': 3,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'selectedIds': ['A'],
              },
            },
          ],
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.fill,
      label: '填空与排序题',
      description: '在 prompt 中通过 slotId 标记空位，支持文字/数值填空及选词排序。',
      defaultInteraction: 'fill.input',
      defaultGradingMode: 'exact',
      generationGuide:
          '普通填空在 body.slots 定义空位，prompt 用 {"type":"slot","slotId":"s1"}，答案放 expected.entries[].acceptedValues；'
          '【排序题 / 连词成句 / 句子排列（重要）】禁止用 response/solve！必须设 kind="fill"，'
          'presentation.interaction="fill.sequence"，将词块/句子拆分放入 body.bank=[{"id":"w1","content":[{"type":"text","text":"..."}]}]，'
          '正确顺序填入 grading.answerSets[0].expected.entries[0].acceptedValues=[{"type":"items","itemIds":["w2","w1"]}]。',
      skeletonJson: {
        'schema': 1,
        'kind': 'fill',
        'header': {'title': '', 'score': 4},
        'prompt': [
          {'type': 'text', 'text': ''},
          {'type': 'slot', 'slotId': 's1'},
        ],
        'body': {
          'slots': [
            {'id': 's1', 'label': '填空', 'valueType': 'text', 'required': true},
          ],
        },
        'presentation': {
          'interaction': 'fill.input',
          'config': <String, Object?>{},
        },
        'grading': {
          'mode': 'exact',
          'maxScore': 4,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'slotId': 's1',
                    'acceptedValues': [
                      {'type': 'text', 'text': ''},
                    ],
                  },
                ],
              },
            },
          ],
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.solve,
      label: '步骤解答题',
      description: '数理化分步推导与综合解答题，支持文字、公式或手写纸拍照批改。',
      defaultInteraction: 'solve.steps',
      defaultGradingMode: 'stepwise_ai',
      generationGuide:
          '在 body.steps 列出关键采分步骤（id, label, score），rules 设为 {"allowImageAnswer":true,"minSteps":1}；'
          'grading.mode="stepwise_ai" 并列出 scoringPoints 与 finalAnswer.acceptedValues。',
      skeletonJson: {
        'schema': 1,
        'kind': 'solve',
        'header': {'title': '', 'score': 8},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {
          'steps': [
            {'id': 'st1', 'label': '步骤推导', 'score': 8},
          ],
        },
        'rules': {'allowImageAnswer': true, 'minSteps': 1},
        'presentation': {'interaction': 'solve.steps'},
        'grading': {
          'mode': 'stepwise_ai',
          'maxScore': 8,
          'scoringPoints': [
            {'stepId': 'st1', 'point': '核心思路正确', 'score': 8},
          ],
          'finalAnswer': {
            'acceptedValues': [
              {'type': 'text', 'text': ''},
            ],
          },
          'tolerateAlternateMethods': true,
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.match,
      label: '连线题',
      description: '分别定义左右两侧候选条目并建立一对一/多配对关系。',
      defaultInteraction: 'match.connect',
      defaultGradingMode: 'exact',
      generationGuide:
          '分别构造 body.left 与 body.right（稳定 id + content 数组），rules 指定 maxLinksPerLeft/maxLinksPerRight/requireAllLeft；'
          'grading.answerSets[0].expected.pairs 使用 {fromId, toId} 引用两侧 id，禁止在公开字段泄露配对。',
      skeletonJson: {
        'schema': 1,
        'kind': 'match',
        'header': {'title': '', 'score': 4},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {
          'left': [
            {
              'id': 'L1',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
          ],
          'right': [
            {
              'id': 'R1',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
          ],
        },
        'rules': {
          'maxLinksPerLeft': 1,
          'maxLinksPerRight': 1,
          'requireAllLeft': true,
        },
        'presentation': {'interaction': 'match.connect'},
        'grading': {
          'mode': 'exact',
          'maxScore': 4,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'pairs': [
                  {'fromId': 'L1', 'toId': 'R1'},
                ],
              },
            },
          ],
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.classify,
      label: '分类归档题',
      description: '将多个待分类条目放入清晰区分的分类桶中。',
      defaultInteraction: 'classify.bins',
      defaultGradingMode: 'exact',
      generationGuide:
          '定义可区分的 body.categories 与 body.items，同一对象保持稳定 id；'
          'grading.answerSets[0].expected.assignments 用 {itemId, categoryId} 记录归类。',
      skeletonJson: {
        'schema': 1,
        'kind': 'classify',
        'header': {'title': '', 'score': 4},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {
          'categories': [
            {
              'id': 'C1',
              'content': [
                {'type': 'text', 'text': '分类一'},
              ],
            },
          ],
          'items': [
            {
              'id': 'I1',
              'content': [
                {'type': 'text', 'text': ''},
              ],
            },
          ],
        },
        'presentation': {'interaction': 'classify.bins'},
        'grading': {
          'mode': 'exact',
          'maxScore': 4,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'assignments': [
                  {'itemId': 'I1', 'categoryId': 'C1'},
                ],
              },
            },
          ],
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.response,
      label: '开放问答题',
      description: '自由文本、拍照或语音回答的开放题目，采用量规评价。',
      defaultInteraction: 'response.submit',
      defaultGradingMode: 'manual',
      generationGuide:
          '按任务拆分 body.parts（声明 acceptedFormats 如 ["text","image"] 与 required），'
          'grading.mode="manual" 或 "rubric_ai"，附上 maxScore 与 rubric 评分要点。',
      skeletonJson: {
        'schema': 1,
        'kind': 'response',
        'header': {'title': '', 'score': 5},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {
          'parts': [
            {
              'id': 'p1',
              'label': '作答内容',
              'acceptedFormats': ['text'],
              'required': true,
            },
          ],
        },
        'presentation': {'interaction': 'response.submit'},
        'grading': {
          'mode': 'manual',
          'maxScore': 5,
          'rubric': ['观点明确', '表达清晰'],
        },
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.group,
      label: '材料组合题',
      description: '共用一段阅读材料或情境，包含多道单层独立小题。',
      defaultInteraction: 'group.compose',
      defaultGradingMode: 'aggregate',
      generationGuide:
          '阅读/情境材料放父题 prompt，完整子题放 body.questions（子题可使用 choice/fill/match/classify/response/solve，禁止嵌套 group）；'
          '父题 presentation.interaction="group.compose"，rules={}，grading={"mode":"aggregate"} 且不写独立标准答案。',
      skeletonJson: {
        'schema': 1,
        'kind': 'group',
        'header': {'title': '', 'score': 6},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {'questions': <Object?>[]},
        'rules': <String, Object?>{},
        'presentation': {'interaction': 'group.compose'},
        'grading': {'mode': 'aggregate'},
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.draw,
      label: '作图证明题',
      description: '几何作图、电路图连接或带坐标标注的图画题。',
      defaultInteraction: 'draw.canvas',
      defaultGradingMode: 'stepwise_ai',
      generationGuide:
          '作图题在 body.requirements 描述绘图要素，rules 允许手写画布，grading 标注核心图元要点。',
      skeletonJson: {
        'schema': 1,
        'kind': 'draw',
        'header': {'title': '', 'score': 6},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {'requirements': <String>[]},
        'presentation': {'interaction': 'draw.canvas'},
        'grading': {'mode': 'stepwise_ai', 'maxScore': 6},
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.spatial,
      label: '图形定位题',
      description: '基于坐标系或区域标点的几何/生物/地理识图题。',
      defaultInteraction: 'spatial.pin',
      defaultGradingMode: 'exact',
      generationGuide:
          '在 body.base 与 body.regions 定义归一化框定区域（0..1000），grading 指定正确命中区 id。',
      skeletonJson: {
        'schema': 1,
        'kind': 'spatial',
        'header': {'title': '', 'score': 4},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {'regions': <Object?>[]},
        'presentation': {'interaction': 'spatial.pin'},
        'grading': {'mode': 'exact', 'maxScore': 4},
      },
    ),
    QuestionSchemaSpec(
      kind: QuestionKind.write,
      label: '作文 / 长文写作',
      description: '中英文作文、读后感或长文表达训练。',
      defaultInteraction: 'write.essay',
      defaultGradingMode: 'rubric_ai',
      generationGuide: '标明字数与体裁要求在 body，grading 提供维度权重与评价量规。',
      skeletonJson: {
        'schema': 1,
        'kind': 'write',
        'header': {'title': '', 'score': 15},
        'prompt': [
          {'type': 'text', 'text': ''},
        ],
        'body': {'minWords': 80},
        'presentation': {'interaction': 'write.essay'},
        'grading': {
          'mode': 'rubric_ai',
          'maxScore': 15,
          'rubric': ['紧扣主题', '结构完整', '语言流畅'],
        },
      },
    ),
  ];

  static QuestionSchemaSpec specFor(QuestionKind kind) {
    return specs.firstWhere((s) => s.kind == kind, orElse: () => specs.first);
  }

  /// Generates a concise, authoritative schema reference string for the given
  /// [kinds] to guide LLM extraction / JSON repair (`P-02` / `P-03`).
  static String promptGuideForKinds(Iterable<QuestionKind> kinds) {
    final targetKinds = kinds.isEmpty
        ? const [QuestionKind.choice, QuestionKind.fill, QuestionKind.solve]
        : kinds.toSet().toList();
    final buf = StringBuffer()
      ..writeln('【公共规范】header.title 为简短考点标题，prompt 为 ContentBlock[]；')
      ..writeln('答案与解析仅写入 grading 与 explanation，不得混入 prompt/options；');
    for (final k in targetKinds) {
      final spec = specFor(k);
      buf.writeln(
        '- kind="${k.code}" (${spec.label}): ${spec.generationGuide}',
      );
    }
    return buf.toString().trim();
  }

  static String formattedSkeletonJson(QuestionKind kind) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(specFor(kind).skeletonJson);
  }
}

/// Shared structured parser converting pasted text, Markdown blocks, JSON,
/// or JSONL lines into structured [Question] drafts (used both by Quick Paste
/// inside Question Editor and offline document ingestion).
abstract final class StructuredQuestionTextParser {
  static final RegExp _optionLine = RegExp(
    r'^(?:[\(（]?([A-Fa-f])[\)）\.\、\s:：]+)(.+)$',
  );
  static final RegExp _answerLine = RegExp(
    r'^(?:【?\s*(?:参考)?答案\s*】?[:：]?\s*)(.+)$',
    caseSensitive: false,
  );
  static final RegExp _expLine = RegExp(
    r'^(?:【?\s*(?:参考)?解析\s*】?[:：]?\s*)(.+)$',
    caseSensitive: false,
  );
  static final RegExp _titlePrefix = RegExp(r'^(?:#+\s*|【题型[：:]\s*[^】]+】\s*)');

  /// Attempts direct JSON / JSONL decoding first (`questions` array, single
  /// JSON object, or JSONL chunk stream). Returns `null` if input is not valid
  /// structured JSON/JSONL.
  static List<Question>? tryParseJsonOrJsonl(
    String rawText, {
    String subject = SubjectCatalog.autoCode,
    required String grade,
    bool lockSubject = false,
  }) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    Question coerceWithAutoSubject(
      Map<String, Object?> map,
      String fallbackId,
    ) {
      final rawMeta = map['meta'] is Map
          ? (map['meta']! as Map).map((k, v) => MapEntry(k.toString(), v))
          : const <String, Object?>{};
      final explicitJsonSub = SubjectCatalog.tryParseCode(
        rawMeta['subject']?.toString(),
      );
      var q = Question.coerceFromAiMap(
        map,
        fallbackId: fallbackId,
        defaultSubject:
            explicitJsonSub ??
            (subject == SubjectCatalog.autoCode ? 'other' : subject),
        defaultGrade: grade,
      );
      q = SequenceQuestionDetector.tryRescueAsSequence(q) ?? q;
      if (lockSubject) {
        final locked = SubjectCatalog.normalize(subject);
        return q.meta.subject == locked
            ? q
            : q.copyWith(meta: q.meta.copyWith(subject: locked));
      }
      if (explicitJsonSub != null) return q;
      final resolved = SubjectDetector.resolveSubjectForText(
        SubjectDetector.searchableTextOfQuestion(q),
        preferredSubject: subject,
        allowOverrideDefault: true,
      );
      return q.meta.subject == resolved
          ? q
          : q.copyWith(meta: q.meta.copyWith(subject: resolved));
    }

    // 1. Standard JSON object / array
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['questions'] is List
                  ? decoded['questions'] as List
                  : [decoded]);
        final out = <Question>[];
        for (var i = 0; i < list.length; i++) {
          if (list[i] is! Map) continue;
          final map = (list[i] as Map).map((k, v) => MapEntry(k.toString(), v));
          out.add(coerceWithAutoSubject(map, 'q_doc_${i + 1}'));
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        // Might be JSONL where each line starts with '{'
      }
    }

    // 2. JSONL (`教材正文_AI分块.jsonl` / line-delimited question objects)
    final lines = trimmed
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('{') && l.endsWith('}'))
        .toList();
    if (lines.length >= 2) {
      final out = <Question>[];
      for (var i = 0; i < lines.length; i++) {
        try {
          final obj = jsonDecode(lines[i]);
          if (obj is! Map) continue;
          final map = obj.map((k, v) => MapEntry(k.toString(), v));
          if (map.containsKey('question') && map['question'] is Map) {
            final qMap = (map['question'] as Map).map(
              (k, v) => MapEntry(k.toString(), v),
            );
            out.add(coerceWithAutoSubject(qMap, 'q_jsonl_${i + 1}'));
          } else {
            out.add(coerceWithAutoSubject(map, 'q_jsonl_${i + 1}'));
          }
        } catch (_) {
          continue;
        }
      }
      if (out.isNotEmpty) return out;
    }

    return null;
  }

  /// Parses one raw text chunk (`题干 + 可选 A/B/C/D 选项 + 可选 答案/解析`) into
  /// a structured [Question] (`choice`, `fill`, or `solve`), automatically
  /// inferring its subject from content unless [lockSubject] is `true`.
  static Question parseTextChunk(
    String rawChunk, {
    required String id,
    required int index,
    String subject = SubjectCatalog.autoCode,
    required String grade,
    required int timestampMs,
    String sourceType = 'text',
    bool lockSubject = false,
  }) {
    final lines = rawChunk
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final stemLines = <String>[];
    final options = <({String id, String text})>[];
    String answerRaw = '';
    final expLines = <String>[];
    var inExp = false;

    for (final line in lines) {
      final ansMatch = _answerLine.firstMatch(line);
      if (ansMatch != null) {
        answerRaw = ansMatch.group(1)?.trim() ?? '';
        inExp = false;
        continue;
      }
      final expMatch = _expLine.firstMatch(line);
      if (expMatch != null) {
        final tail = expMatch.group(1)?.trim() ?? '';
        if (tail.isNotEmpty) expLines.add(tail);
        inExp = true;
        continue;
      }
      if (inExp) {
        expLines.add(line);
        continue;
      }
      final optMatch = _optionLine.firstMatch(line);
      if (optMatch != null) {
        options.add((
          id: optMatch.group(1)!.toUpperCase(),
          text: optMatch.group(2)!.trim(),
        ));
        continue;
      }
      stemLines.add(line.replaceFirst(_titlePrefix, '').trim());
    }

    var stem = stemLines.join('\n').trim();
    if (stem.isEmpty) stem = rawChunk.trim();
    stem = stem.replaceFirst(RegExp(r'^\d+[\.、\)]\s*'), '').trim();
    final title = stem.length <= 16 ? stem : '${stem.substring(0, 16)}…';
    final explanation = expLines.isEmpty
        ? const <ContentBlock>[]
        : [TextBlock(expLines.join('\n'))];
    final combinedSearchText = [
      stem,
      for (final o in options) o.text,
      answerRaw,
      ...expLines,
    ].join('\n');
    final resolvedSubject = lockSubject
        ? SubjectCatalog.normalize(subject)
        : SubjectDetector.resolveSubjectForText(
            combinedSearchText,
            preferredSubject: subject,
            allowOverrideDefault: true,
          );

    if (options.length >= 2) {
      final hasOrderingCue = SequenceQuestionDetector.sequenceCueRegex.hasMatch(
        stem,
      );
      final permAnswerLetters = RegExp(r'[A-Fa-f]')
          .allMatches(answerRaw)
          .map((m) => m.group(0)!.toUpperCase())
          .where((id) => options.any((o) => o.id == id))
          .toList();
      final optsArePermutations = options.every(
        (o) => RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩\d\-\s→>、，]+$').hasMatch(o.text.trim()),
      );

      // A. ... B. ... C. ... ordering task with multi-letter permutation answer (e.g. "B C A")
      if (hasOrderingCue &&
          !optsArePermutations &&
          permAnswerLetters.length >= 2) {
        final bank = SequenceQuestionDetector.buildBankFromItems([
          for (final o in options) (label: o.id, text: '${o.id}. ${o.text}'),
        ]);
        final itemIds = SequenceQuestionDetector.matchAnswerToBankIds(
          answerRaw,
          bank,
        );
        return Question(
          id: id,
          kind: QuestionKind.fill,
          sourceType: sourceType,
          header: QuestionHeader(title: title, score: 4),
          prompt: [
            TextBlock(stem),
            const TextBlock(' '),
            const SlotBlock('s1'),
          ],
          body: {
            'slots': const [
              {'id': 's1', 'label': '排序结果', 'valueType': 'text'},
            ],
            'bank': bank,
          },
          presentation: const QuestionPresentation(
            interaction: 'fill.sequence',
          ),
          grading: {
            'mode': 'exact',
            'maxScore': 4,
            'perSlotScore': const {'s1': 4},
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
          explanation: explanation,
          meta: QuestionMeta(
            subject: resolvedSubject,
            grade: grade,
            answerSource: itemIds.isNotEmpty
                ? AnswerSource.user
                : AnswerSource.ai,
            aiConfidence: itemIds.isNotEmpty ? 1.0 : 0.78,
            uncertainNote: itemIds.isEmpty ? '已识别为排序题，请确认正确顺序。' : null,
          ),
          createdAtMs: timestampMs,
          updatedAtMs: timestampMs,
        );
      }

      final ansLetters = permAnswerLetters.toSet().toList();
      if (ansLetters.isEmpty) ansLetters.add(options.first.id);

      return Question(
        id: id,
        kind: QuestionKind.choice,
        sourceType: sourceType,
        header: QuestionHeader(title: title, score: 3),
        prompt: [TextBlock(stem)],
        body: {
          'options': [
            for (final o in options)
              {
                'id': o.id,
                'content': [
                  {'type': 'text', 'text': o.text},
                ],
              },
          ],
        },
        rules: {
          'minSelections': 1,
          'maxSelections': ansLetters.length > 1 ? ansLetters.length : 1,
        },
        presentation: const QuestionPresentation(interaction: 'choice.select'),
        grading: {
          'mode': 'exact',
          'maxScore': 3,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {'selectedIds': ansLetters},
            },
          ],
        },
        explanation: explanation,
        meta: QuestionMeta(
          subject: resolvedSubject,
          grade: grade,
          answerSource: answerRaw.isNotEmpty
              ? AnswerSource.user
              : AnswerSource.ai,
          aiConfidence: answerRaw.isNotEmpty ? 1.0 : 0.72,
          uncertainNote: answerRaw.isEmpty ? '尚未标注参考答案，请在校对或编辑时确认。' : null,
        ),
        createdAtMs: timestampMs,
        updatedAtMs: timestampMs,
      );
    }

    final seqExtracted = SequenceQuestionDetector.extractOrderableItems(stem);
    if (seqExtracted != null && seqExtracted.items.length >= 2) {
      final bank = SequenceQuestionDetector.buildBankFromItems(
        seqExtracted.items,
      );
      final itemIds = SequenceQuestionDetector.matchAnswerToBankIds(
        answerRaw,
        bank,
      );
      return Question(
        id: id,
        kind: QuestionKind.fill,
        sourceType: sourceType,
        header: QuestionHeader(title: title, score: 4),
        prompt: [
          TextBlock(seqExtracted.instruction),
          const TextBlock(' '),
          const SlotBlock('s1'),
        ],
        body: {
          'slots': const [
            {'id': 's1', 'label': '排序结果', 'valueType': 'text'},
          ],
          'bank': bank,
        },
        presentation: const QuestionPresentation(interaction: 'fill.sequence'),
        grading: {
          'mode': 'exact',
          'maxScore': 4,
          'perSlotScore': const {'s1': 4},
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
        explanation: explanation,
        meta: QuestionMeta(
          subject: resolvedSubject,
          grade: grade,
          answerSource: itemIds.isNotEmpty
              ? AnswerSource.user
              : AnswerSource.ai,
          aiConfidence: itemIds.isNotEmpty ? 1.0 : 0.78,
          uncertainNote: itemIds.isEmpty ? '已识别为排序题，请确认正确语序。' : null,
        ),
        createdAtMs: timestampMs,
        updatedAtMs: timestampMs,
      );
    }

    final hasBlank = RegExp(r'_{2,}|（\s*）|\(\s*\)').hasMatch(stem);
    if (hasBlank) {
      final parts = stem.split(RegExp(r'_{2,}|（\s*）|\(\s*\)'));
      final promptBlocks = <ContentBlock>[];
      final slots = <Map<String, Object?>>[];
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) promptBlocks.add(TextBlock(parts[i]));
        if (i < parts.length - 1) {
          final sid = 's${i + 1}';
          promptBlocks.add(SlotBlock(sid));
          slots.add({'id': sid, 'label': '第${i + 1}空', 'valueType': 'text'});
        }
      }
      final numAns = double.tryParse(answerRaw);
      final firstSlotId = slots.isNotEmpty
          ? slots.first['id'].toString()
          : 's1';
      return Question(
        id: id,
        kind: QuestionKind.fill,
        sourceType: sourceType,
        header: QuestionHeader(title: title, score: 4),
        prompt: promptBlocks,
        body: {'slots': slots},
        presentation: const QuestionPresentation(interaction: 'fill.input'),
        grading: {
          'mode': 'exact',
          'maxScore': 4,
          'perSlotScore': {firstSlotId: 4},
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'slotId': firstSlotId,
                    'acceptedValues': [
                      if (numAns != null)
                        {'type': 'number', 'value': numAns, 'tolerance': 1e-6}
                      else
                        {'type': 'text', 'text': answerRaw},
                    ],
                  },
                ],
              },
            },
          ],
        },
        explanation: explanation,
        meta: QuestionMeta(
          subject: resolvedSubject,
          grade: grade,
          answerSource: answerRaw.isNotEmpty
              ? AnswerSource.user
              : AnswerSource.ai,
          aiConfidence: answerRaw.isNotEmpty ? 1.0 : 0.72,
          uncertainNote: answerRaw.isEmpty ? '请核对填空标准答案。' : null,
        ),
        createdAtMs: timestampMs,
        updatedAtMs: timestampMs,
      );
    }

    final numFin = double.tryParse(answerRaw);
    return Question(
      id: id,
      kind: QuestionKind.solve,
      sourceType: sourceType,
      header: QuestionHeader(
        title: title.isEmpty ? '题目 $index' : title,
        score: 6,
      ),
      prompt: [TextBlock(stem)],
      body: const {
        'steps': [
          {'id': 'st1', 'label': '解答步骤', 'score': 6},
        ],
      },
      rules: const {'allowImageAnswer': true, 'minSteps': 1},
      presentation: const QuestionPresentation(
        interaction: 'solve.steps',
        config: {'preferMode': 'paper'},
      ),
      grading: {
        'mode': 'stepwise_ai',
        'maxScore': 6,
        'scoringPoints': const [
          {'stepId': 'st1', 'point': '核心思路正确', 'score': 6},
        ],
        if (answerRaw.isNotEmpty)
          'finalAnswer': {
            'acceptedValues': [
              if (numFin != null)
                {'type': 'number', 'value': numFin, 'tolerance': 1e-6}
              else
                {'type': 'text', 'text': answerRaw},
            ],
          },
        'tolerateAlternateMethods': true,
      },
      explanation: explanation,
      meta: QuestionMeta(
        subject: resolvedSubject,
        grade: grade,
        answerSource: answerRaw.isNotEmpty
            ? AnswerSource.user
            : AnswerSource.ai,
        aiConfidence: answerRaw.isNotEmpty ? 1.0 : 0.72,
        uncertainNote: answerRaw.isEmpty ? '文本导入草案，建议核对参考答案与题型。' : null,
      ),
      createdAtMs: timestampMs,
      updatedAtMs: timestampMs,
    );
  }
}

import 'package:meta/meta.dart';

import 'content_block.dart';
import 'content_plain_text.dart';
import 'enums.dart';

/// Header metadata shown at the top of a question.
@immutable
class QuestionHeader {
  const QuestionHeader({
    required this.title,
    this.description = const [],
    this.score = 1,
  });

  factory QuestionHeader.fromJson(Map<String, Object?> json) {
    final title = json['title'];
    if (title is! String) {
      throw const FormatException('QuestionHeader requires string "title".');
    }
    final rawDesc = json['description'] as List<Object?>? ?? const [];
    final score = json['score'];
    return QuestionHeader(
      title: title,
      description: rawDesc
          .map((e) => ContentBlock.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      score: score is num ? score.toDouble() : 1.0,
    );
  }

  final String title;
  final List<ContentBlock> description;
  final double score;

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description.map((b) => b.toJson()).toList(growable: false),
    'score': score,
  };
}

/// UI interaction binding separate from question structure (`kind`).
@immutable
class QuestionPresentation {
  const QuestionPresentation({
    required this.interaction,
    this.config = const <String, Object?>{},
  });

  factory QuestionPresentation.fromJson(Map<String, Object?> json) {
    final interaction = json['interaction'];
    if (interaction is! String || interaction.isEmpty) {
      throw const FormatException(
        'QuestionPresentation requires non-empty "interaction".',
      );
    }
    final cfg = json['config'];
    return QuestionPresentation(
      interaction: interaction,
      config: cfg is Map<String, Object?>
          ? Map<String, Object?>.unmodifiable(cfg)
          : const <String, Object?>{},
    );
  }

  final String interaction;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => {
    'interaction': interaction,
    'config': config,
  };
}

/// Normalized bounding box `[ymin, xmin, ymax, xmax]` in `0..1000` integers.
@immutable
class NormalizedBbox {
  const NormalizedBbox(this.ymin, this.xmin, this.ymax, this.xmax);

  factory NormalizedBbox.fromList(List<Object?> raw) {
    if (raw.length != 4) {
      throw const FormatException('NormalizedBbox requires 4 numbers.');
    }
    return NormalizedBbox(
      (raw[0]! as num).toInt(),
      (raw[1]! as num).toInt(),
      (raw[2]! as num).toInt(),
      (raw[3]! as num).toInt(),
    );
  }

  final int ymin;
  final int xmin;
  final int ymax;
  final int xmax;

  List<int> toJson() => [ymin, xmin, ymax, xmax];
}

/// Learning-oriented metadata attached to a [Question].
@immutable
class QuestionMeta {
  const QuestionMeta({
    required this.subject,
    required this.grade,
    this.difficulty = Difficulty.normal,
    this.kpIds = const [],
    this.tags = const [],
    this.sourceNo,
    this.answerSource = AnswerSource.paper,
    this.aiConfidence,
    this.originQuestionId,
    this.variationNote,
    this.uncertainNote,
  });

  factory QuestionMeta.fromJson(Map<String, Object?> json) {
    final subject = json['subject'] as String? ?? 'other';
    final grade = json['grade'] as String? ?? 'g7';
    final diffRaw = json['difficulty'] as String? ?? 'normal';
    final srcRaw = json['answerSource'] as String? ?? 'paper';
    final conf = json['aiConfidence'];
    return QuestionMeta(
      subject: subject,
      grade: grade,
      difficulty: Difficulty.fromCode(diffRaw),
      kpIds: (json['kpIds'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      tags: (json['tags'] as List<Object?>? ?? const []).cast<String>().toList(
        growable: false,
      ),
      sourceNo: json['sourceNo'] as String?,
      answerSource: AnswerSource.fromCode(srcRaw),
      aiConfidence: conf is num ? conf.toDouble() : null,
      originQuestionId: json['originQuestionId'] as String?,
      variationNote: json['variationNote'] as String?,
      uncertainNote: json['uncertainNote'] as String?,
    );
  }

  final String subject;
  final String grade;
  final Difficulty difficulty;
  final List<String> kpIds;
  final List<String> tags;
  final String? sourceNo;
  final AnswerSource answerSource;
  final double? aiConfidence;
  final String? originQuestionId;
  final String? variationNote;
  final String? uncertainNote;

  QuestionMeta copyWith({
    String? subject,
    String? grade,
    Difficulty? difficulty,
    List<String>? kpIds,
    List<String>? tags,
    String? sourceNo,
    AnswerSource? answerSource,
    double? aiConfidence,
    String? originQuestionId,
    String? variationNote,
    String? uncertainNote,
  }) {
    return QuestionMeta(
      subject: subject ?? this.subject,
      grade: grade ?? this.grade,
      difficulty: difficulty ?? this.difficulty,
      kpIds: kpIds ?? this.kpIds,
      tags: tags ?? this.tags,
      sourceNo: sourceNo ?? this.sourceNo,
      answerSource: answerSource ?? this.answerSource,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      originQuestionId: originQuestionId ?? this.originQuestionId,
      variationNote: variationNote ?? this.variationNote,
      uncertainNote: uncertainNote ?? this.uncertainNote,
    );
  }

  Map<String, Object?> toJson() => {
    'subject': subject,
    'grade': grade,
    'difficulty': difficulty.code,
    'kpIds': kpIds,
    'tags': tags,
    if (sourceNo != null) 'sourceNo': sourceNo,
    'answerSource': answerSource.code,
    if (aiConfidence != null) 'aiConfidence': aiConfidence,
    if (originQuestionId != null) 'originQuestionId': originQuestionId,
    if (variationNote != null) 'variationNote': variationNote,
    if (uncertainNote != null) 'uncertainNote': uncertainNote,
  };
}

/// Strictly answer-free view exposed to UI rendering and restricted L1/L2 agents.
@immutable
class QuestionPublicView {
  const QuestionPublicView({
    required this.id,
    required this.schema,
    required this.kind,
    required this.header,
    required this.prompt,
    required this.body,
    required this.rules,
    required this.presentation,
    required this.meta,
    this.docId,
    this.sourceType = 'manual',
    this.bbox,
  });

  final String id;
  final int schema;
  final QuestionKind kind;
  final QuestionHeader header;
  final List<ContentBlock> prompt;
  final Map<String, Object?> body;
  final Map<String, Object?> rules;
  final QuestionPresentation presentation;
  final QuestionMeta meta;
  final String? docId;
  final String sourceType;
  final NormalizedBbox? bbox;

  String get plainText =>
      ContentTextUtils.extractPlainText([...prompt, ...header.description]);

  bool get isSequence =>
      kind == QuestionKind.fill &&
      (presentation.interaction == 'fill.sequence' ||
          (body['bank'] is List && (body['bank']! as List).isNotEmpty));

  String get displayKindLabel => isSequence ? '排序题' : kind.label;

  List<Question> get subQuestions {
    if (kind != QuestionKind.group) return const [];
    final raw = body['questions'];
    if (raw is! List<Object?>) return const [];
    return raw
        .map(
          (e) => Question.fromJson(
            e! as Map<String, Object?>,
            fallbackId: '${id}_sub',
          ),
        )
        .toList(growable: false);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'schema': schema,
    'kind': kind.code,
    'header': header.toJson(),
    'prompt': prompt.map((b) => b.toJson()).toList(growable: false),
    'body': body,
    'rules': rules,
    'presentation': presentation.toJson(),
    'meta': meta.toJson(),
  };
}

/// Full question entity including private grading and explanation.
@immutable
class Question {
  const Question({
    required this.id,
    this.schema = 1,
    required this.kind,
    required this.header,
    required this.prompt,
    required this.body,
    this.rules = const <String, Object?>{},
    required this.presentation,
    required this.grading,
    this.explanation = const [],
    required this.meta,
    this.docId,
    this.sourceType = 'manual',
    this.bbox,
    this.historyVerdicts = const [],
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  factory Question.fromJson(Map<String, Object?> json, {String? fallbackId}) {
    final schema = json['schema'];
    if (schema is! int || schema != 1) {
      throw FormatException('Unsupported question schema: $schema');
    }
    final kindRaw = json['kind'];
    if (kindRaw is! String) {
      throw const FormatException('Question requires string "kind".');
    }
    final kind = QuestionKind.fromCode(kindRaw);
    final rawPrompt = json['prompt'];
    if (rawPrompt is! List<Object?>) {
      throw const FormatException('Question requires list "prompt".');
    }
    final rawExp = json['explanation'] as List<Object?>? ?? const [];
    final rawBbox = json['bbox'];
    final rawHist = json['historyVerdicts'] as List<Object?>? ?? const [];

    return Question(
      id: (json['id'] as String?) ?? fallbackId ?? 'q_unassigned',
      schema: schema,
      kind: kind,
      header: QuestionHeader.fromJson(json['header']! as Map<String, Object?>),
      prompt: rawPrompt
          .map((e) => ContentBlock.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      body: Map<String, Object?>.unmodifiable(
        (json['body'] as Map<String, Object?>?) ?? const <String, Object?>{},
      ),
      rules: Map<String, Object?>.unmodifiable(
        (json['rules'] as Map<String, Object?>?) ?? const <String, Object?>{},
      ),
      presentation: QuestionPresentation.fromJson(
        json['presentation']! as Map<String, Object?>,
      ),
      grading: Map<String, Object?>.unmodifiable(
        (json['grading'] as Map<String, Object?>?) ?? const <String, Object?>{},
      ),
      explanation: rawExp
          .map((e) => ContentBlock.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      meta: QuestionMeta.fromJson(
        (json['meta'] as Map<String, Object?>?) ?? const <String, Object?>{},
      ),
      docId: json['docId'] as String?,
      sourceType: (json['sourceType'] as String?) ?? 'manual',
      bbox: rawBbox is List<Object?> ? NormalizedBbox.fromList(rawBbox) : null,
      historyVerdicts: rawHist
          .map((e) => Verdict.fromCode(e! as String))
          .toList(growable: false),
      createdAtMs: (json['createdAtMs'] as int?) ?? 0,
      updatedAtMs: (json['updatedAtMs'] as int?) ?? 0,
    );
  }

  /// Resiliently normalizes looser JSON shapes emitted by Vision LLMs into a
  /// schema-1 [Question] envelope so minor key omissions or flat strings do not
  /// discard valid OCR results.
  factory Question.coerceFromAiMap(
    Map<String, Object?> raw, {
    String? fallbackId,
    String defaultSubject = 'math',
    String defaultGrade = 'g9',
    AnswerSource defaultAnswerSource = AnswerSource.ai,
  }) {
    Map<String, Object?> asMap(Object? v) => v is Map
        ? v.map((k, val) => MapEntry(k.toString(), val))
        : <String, Object?>{};

    List<ContentBlock> parseBlocks(Object? val) {
      if (val is String && val.trim().isNotEmpty) {
        return [TextBlock(val.trim())];
      }
      if (val is List) {
        final out = <ContentBlock>[];
        for (final item in val) {
          if (item is String && item.trim().isNotEmpty) {
            out.add(TextBlock(item.trim()));
          } else if (item is Map) {
            try {
              out.add(ContentBlock.fromJson(asMap(item)));
            } catch (_) {
              final text = (item['text'] ?? item['content'] ?? '').toString();
              if (text.trim().isNotEmpty) out.add(TextBlock(text.trim()));
            }
          }
        }
        return out;
      }
      return const [];
    }

    final rawKind = (raw['kind'] ?? raw['type'] ?? 'solve')
        .toString()
        .trim()
        .toLowerCase();
    final rawPresMap = asMap(raw['presentation']);
    final rawInteraction =
        (rawPresMap['interaction'] ?? raw['interaction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final rawBankCandidate =
        asMap(raw['body'])['bank'] ??
        raw['bank'] ??
        raw['words'] ??
        raw['tokens'] ??
        raw['segments'];
    final isExplicitSequenceKind =
        const {
          'fill.sequence',
          'fill_sequence',
          'sequence',
          'sort',
          'sorting',
          'order',
          'ordering',
          'reorder',
          'rearrange',
          'unscramble',
          '排序',
          '排序题',
          '连词成句',
          '排句成段',
          '句段排序',
        }.contains(rawKind) ||
        rawInteraction.contains('sequence') ||
        rawInteraction.contains('order') ||
        rawInteraction.contains('sort') ||
        (rawBankCandidate is List &&
            rawBankCandidate.length >= 2 &&
            rawKind != 'choice' &&
            rawKind != 'match' &&
            rawKind != 'classify');

    final kind = switch (rawKind) {
      'choice' ||
      'single_choice' ||
      'multiple_choice' ||
      'mcq' ||
      'true_false' ||
      'judge' ||
      '选择题' ||
      '判断题' ||
      '判断' => QuestionKind.choice,
      'fill' ||
      'blank' ||
      'fill_in_blank' ||
      'fill.input' ||
      'fill.pick' ||
      '填空' ||
      '填空题' => QuestionKind.fill,
      'match' ||
      'matching' ||
      'pair' ||
      'pairs' ||
      '连线' ||
      '连线题' => QuestionKind.match,
      'classify' || '分类' || '分类题' => QuestionKind.classify,
      'response' || 'short_answer' || 'essay' || '简答' || '简答题' =>
        isExplicitSequenceKind ? QuestionKind.fill : QuestionKind.response,
      'draw' || 'sketch' || '作图' || '作图题' => QuestionKind.draw,
      'spatial' || 'hotspot' => QuestionKind.spatial,
      'write' || 'handwrite' || '书写' || '书写题' => QuestionKind.write,
      'group' || 'reading' || '组合阅读题' => QuestionKind.group,
      _ => isExplicitSequenceKind ? QuestionKind.fill : QuestionKind.solve,
    };

    var promptBlocks = parseBlocks(
      raw['prompt'] ?? raw['stem'] ?? raw['question'] ?? raw['text'],
    );
    if (promptBlocks.isEmpty) {
      promptBlocks = const [TextBlock('（识别题干为空，请人工补充）')];
    }
    final stemPlain = ContentTextUtils.extractPlainText(promptBlocks);

    final rawHeader = asMap(raw['header']);
    final score =
        (rawHeader['score'] as num?)?.toDouble() ??
        (raw['score'] as num?)?.toDouble() ??
        switch (kind) {
          QuestionKind.choice => 3.0,
          QuestionKind.fill => 4.0,
          _ => 6.0,
        };
    final autoTitle = stemPlain.length <= 18
        ? stemPlain
        : '${stemPlain.substring(0, 18)}…';
    final header = QuestionHeader(
      title: (rawHeader['title'] as String?)?.trim().isNotEmpty == true
          ? (rawHeader['title']! as String).trim()
          : ((raw['title'] as String?)?.trim().isNotEmpty == true
                ? (raw['title']! as String).trim()
                : autoTitle),
      description: parseBlocks(rawHeader['description']),
      score: score,
    );

    final body = Map<String, Object?>.from(asMap(raw['body']));
    if (kind == QuestionKind.choice) {
      final rawOpts =
          (body['options'] ?? raw['options']) as List<Object?>? ?? const [];
      final normalizedOpts = <Map<String, Object?>>[];
      const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
      for (var i = 0; i < rawOpts.length; i++) {
        final opt = rawOpts[i];
        final fallbackOptId = i < letters.length ? letters[i] : '${i + 1}';
        if (opt is String) {
          normalizedOpts.add({
            'id': fallbackOptId,
            'content': [
              {'type': 'text', 'text': opt.trim()},
            ],
          });
        } else if (opt is Map) {
          final om = asMap(opt);
          final oid = (om['id'] ?? om['label'] ?? fallbackOptId)
              .toString()
              .trim();
          final contentList = parseBlocks(
            om['content'] ?? om['text'] ?? om['value'],
          );
          normalizedOpts.add({
            'id': oid.isEmpty ? fallbackOptId : oid,
            'content': contentList.isNotEmpty
                ? contentList.map((b) => b.toJson()).toList(growable: false)
                : [
                    {'type': 'text', 'text': oid},
                  ],
          });
        }
      }
      if (normalizedOpts.isNotEmpty) {
        body['options'] = normalizedOpts;
      }
    } else if (kind == QuestionKind.fill) {
      if (body['slots'] == null ||
          (body['slots'] is List && (body['slots']! as List).isEmpty)) {
        body['slots'] = [
          {
            'id': 's1',
            'label': isExplicitSequenceKind ? '排序结果' : '填空答案',
            'valueType': 'text',
          },
        ];
      }
      if (rawBankCandidate is List && rawBankCandidate.isNotEmpty) {
        final normBank = <Map<String, Object?>>[];
        for (var i = 0; i < rawBankCandidate.length; i++) {
          final item = rawBankCandidate[i];
          if (item is String && item.trim().isNotEmpty) {
            normBank.add({
              'id': 'w${i + 1}',
              'content': [
                {'type': 'text', 'text': item.trim()},
              ],
            });
          } else if (item is Map) {
            final bm = asMap(item);
            final bid = (bm['id'] ?? 'w${i + 1}').toString().trim();
            final blocks = parseBlocks(
              bm['content'] ?? bm['text'] ?? bm['value'] ?? bm['label'],
            );
            normBank.add({
              'id': bid.isEmpty ? 'w${i + 1}' : bid,
              if (bm['label'] != null) 'label': bm['label'],
              'content': blocks.isNotEmpty
                  ? blocks.map((b) => b.toJson()).toList(growable: false)
                  : [
                      {'type': 'text', 'text': bid},
                    ],
            });
          }
        }
        if (normBank.isNotEmpty) {
          body['bank'] = normBank;
        }
      }
      if (!promptBlocks.any((b) => b is SlotBlock)) {
        promptBlocks = [
          ...promptBlocks,
          const TextBlock(' '),
          const SlotBlock('s1'),
        ];
      }
    } else if (kind == QuestionKind.solve && body['steps'] == null) {
      body['steps'] = [
        {'id': 'st1', 'label': '解题过程', 'score': score},
      ];
    }

    final rawPres = rawPresMap;
    final defaultInteraction = switch (kind) {
      QuestionKind.choice => 'choice.select',
      QuestionKind.fill =>
        (isExplicitSequenceKind ||
                (body['bank'] is List && (body['bank']! as List).isNotEmpty))
            ? 'fill.sequence'
            : 'fill.input',
      QuestionKind.match => 'match.pair',
      QuestionKind.classify => 'classify.bucket',
      QuestionKind.response => 'response.text',
      QuestionKind.draw => 'draw.canvas',
      QuestionKind.spatial => 'spatial.hotspot',
      QuestionKind.write => 'write.cells',
      QuestionKind.group => 'group.bundle',
      QuestionKind.solve => 'solve.steps',
    };
    final presentation = QuestionPresentation(
      interaction: isExplicitSequenceKind
          ? 'fill.sequence'
          : ((rawPres['interaction'] as String?)?.trim().isNotEmpty == true
                ? (rawPres['interaction']! as String).trim()
                : defaultInteraction),
      config: asMap(rawPres['config']),
    );

    final grading = Map<String, Object?>.from(asMap(raw['grading']));
    grading['maxScore'] ??= score;
    final simpleAnswer =
        (raw['answer'] ?? grading['answer'] ?? raw['correctAnswer'])
            ?.toString()
            .trim();
    if (kind == QuestionKind.choice && grading['answerSets'] == null) {
      grading['mode'] ??= 'exact';
      final sel = simpleAnswer != null && simpleAnswer.isNotEmpty
          ? simpleAnswer
                .split(RegExp(r'[\s,;，]+'))
                .map((s) => s.trim().toUpperCase())
                .where((s) => s.isNotEmpty)
                .toList()
          : <String>[
              if ((body['options'] as List?)?.isNotEmpty == true)
                ((body['options']! as List).first as Map)['id'].toString(),
            ];
      grading['answerSets'] = [
        {
          'id': 'ans-1',
          'expected': {'selectedIds': sel},
        },
      ];
    } else if (kind == QuestionKind.fill && grading['answerSets'] == null) {
      grading['mode'] ??= 'exact';
      final rawItemIds =
          (raw['itemIds'] ?? raw['answerOrder'] ?? raw['order']) as List?;
      final ansVal = simpleAnswer ?? '';
      final numV = double.tryParse(ansVal);
      grading['perSlotScore'] ??= {'s1': score};
      grading['answerSets'] = [
        {
          'id': 'ans-1',
          'expected': {
            'entries': [
              {
                'slotId': 's1',
                'acceptedValues': [
                  if (rawItemIds != null && rawItemIds.isNotEmpty)
                    {
                      'type': 'items',
                      'itemIds': rawItemIds
                          .map((e) => e.toString())
                          .toList(growable: false),
                    }
                  else if (numV != null)
                    {'type': 'number', 'value': numV, 'tolerance': 1e-6}
                  else
                    {'type': 'text', 'text': ansVal},
                ],
              },
            ],
          },
        },
      ];
    } else if (kind == QuestionKind.solve && grading['finalAnswer'] == null) {
      grading['mode'] ??= 'stepwise_ai';
      if (simpleAnswer != null && simpleAnswer.isNotEmpty) {
        grading['finalAnswer'] = {
          'acceptedValues': [
            {'type': 'text', 'text': simpleAnswer},
          ],
        };
      }
    }

    final rules = Map<String, Object?>.from(asMap(raw['rules']));
    if (kind == QuestionKind.choice) {
      final ansList = grading['answerSets'] as List?;
      final selCount = ansList?.isNotEmpty == true
          ? ((asMap(asMap(ansList!.first)['expected'])['selectedIds'] as List?)
                    ?.length ??
                1)
          : 1;
      rules['minSelections'] ??= 1;
      rules['maxSelections'] ??= selCount > 1
          ? selCount
          : ((body['options'] as List?)?.length ?? 1);
    }

    final rawMeta = asMap(raw['meta']);
    final srcStr = rawMeta['answerSource'] as String?;
    final normalizedRawSubject = SubjectCatalog.tryParseCode(
      rawMeta['subject'] as String?,
    );
    final meta = QuestionMeta(
      subject: normalizedRawSubject ?? defaultSubject,
      grade: (rawMeta['grade'] as String?)?.trim().isNotEmpty == true
          ? (rawMeta['grade']! as String).trim()
          : defaultGrade,
      difficulty: Difficulty.fromCode(
        (rawMeta['difficulty'] as String?) ?? 'normal',
      ),
      kpIds: (rawMeta['kpIds'] as List<Object?>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      tags: (rawMeta['tags'] as List<Object?>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      sourceNo: rawMeta['sourceNo'] as String?,
      answerSource: srcStr != null
          ? AnswerSource.fromCode(srcStr)
          : defaultAnswerSource,
      aiConfidence: (rawMeta['aiConfidence'] as num?)?.toDouble(),
      uncertainNote: rawMeta['uncertainNote'] as String?,
    );

    final rawBbox = raw['bbox'];
    NormalizedBbox? parsedBbox;
    if (rawBbox is List && rawBbox.length == 4) {
      try {
        parsedBbox = NormalizedBbox.fromList(rawBbox.cast<Object?>());
      } catch (_) {
        parsedBbox = null;
      }
    }

    final expBlocks = parseBlocks(raw['explanation']);
    final now = DateTime.now().millisecondsSinceEpoch;
    return Question(
      id: (raw['id'] as String?)?.trim().isNotEmpty == true
          ? (raw['id']! as String).trim()
          : (fallbackId ?? 'q_ai_$now'),
      schema: 1,
      kind: kind,
      header: header,
      prompt: promptBlocks,
      body: Map<String, Object?>.unmodifiable(body),
      rules: Map<String, Object?>.unmodifiable(rules),
      presentation: presentation,
      grading: Map<String, Object?>.unmodifiable(grading),
      explanation: expBlocks,
      meta: meta,
      docId: raw['docId'] as String?,
      sourceType: (raw['sourceType'] as String?) ?? 'photo',
      bbox: parsedBbox,
      createdAtMs: (raw['createdAtMs'] as num?)?.toInt() ?? now,
      updatedAtMs: (raw['updatedAtMs'] as num?)?.toInt() ?? now,
    );
  }

  final String id;
  final int schema;
  final QuestionKind kind;
  final QuestionHeader header;
  final List<ContentBlock> prompt;
  final Map<String, Object?> body;
  final Map<String, Object?> rules;
  final QuestionPresentation presentation;
  final Map<String, Object?> grading;
  final List<ContentBlock> explanation;
  final QuestionMeta meta;
  final String? docId;
  final String sourceType;
  final NormalizedBbox? bbox;
  final List<Verdict> historyVerdicts;
  final int createdAtMs;
  final int updatedAtMs;

  /// Strips private [grading] and [explanation] to create a safe public view.
  QuestionPublicView toPublicView() {
    final sanitizedBody = kind == QuestionKind.group
        ? <String, Object?>{
            ...body,
            'questions': (body['questions'] as List<Object?>? ?? const [])
                .map((item) {
                  final sub = Question.fromJson(
                    item! as Map<String, Object?>,
                    fallbackId: '${id}_sub',
                  );
                  return sub.toPublicView().toJson();
                })
                .toList(growable: false),
          }
        : body;

    return QuestionPublicView(
      id: id,
      schema: schema,
      kind: kind,
      header: header,
      prompt: prompt,
      body: sanitizedBody,
      rules: rules,
      presentation: presentation,
      meta: meta,
      docId: docId,
      sourceType: sourceType,
      bbox: bbox,
    );
  }

  String get plainText => ContentTextUtils.extractPlainText(prompt);

  bool get isSequence =>
      kind == QuestionKind.fill &&
      (presentation.interaction == 'fill.sequence' ||
          (body['bank'] is List && (body['bank']! as List).isNotEmpty));

  String get displayKindLabel => isSequence ? '排序题' : kind.label;

  List<Question> get subQuestions {
    if (kind != QuestionKind.group) return const [];
    final raw = body['questions'];
    if (raw is! List<Object?>) return const [];
    return raw
        .map(
          (e) => Question.fromJson(
            e! as Map<String, Object?>,
            fallbackId: '${id}_sub',
          ),
        )
        .toList(growable: false);
  }

  String get textFingerprint =>
      ContentTextUtils.sha256Hex(ContentTextUtils.normalizeText(plainText));

  int get simHash => ContentTextUtils.simHash64(plainText);

  double get maxScore {
    final gMax = grading['maxScore'];
    if (gMax is num) return gMax.toDouble();
    return header.score;
  }

  /// Formats the structured [grading] payload into a concise, human-readable
  /// reference answer string across all supported [QuestionKind]s.
  String formatReferenceAnswer() {
    switch (kind) {
      case QuestionKind.choice:
        final sets = grading['answerSets'] as List<Object?>? ?? const [];
        if (sets.isNotEmpty && sets.first is Map) {
          final firstSet = _qAsMap(sets.first);
          final expected = _qAsMap(firstSet['expected']);
          final selectedIds =
              (expected['selectedIds'] as List<Object?>? ?? const [])
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
          if (selectedIds.isNotEmpty) {
            if (selectedIds.length == 1) {
              final optText = _findItemPlainText(
                body['options'],
                selectedIds.first,
              );
              if (optText.isNotEmpty && optText.length <= 28) {
                return '${selectedIds.first}（$optText）';
              }
            }
            return selectedIds.join('、');
          }
        }
        return _fallbackScalarFromGrading();

      case QuestionKind.fill:
        final sets = grading['answerSets'] as List<Object?>? ?? const [];
        if (sets.isNotEmpty && sets.first is Map) {
          final expected = _qAsMap(_qAsMap(sets.first)['expected']);
          final entries = expected['entries'] as List<Object?>? ?? const [];
          final parts = <String>[];
          for (var i = 0; i < entries.length; i++) {
            final entry = _qAsMap(entries[i]);
            final accepted = entry['acceptedValues'] as List<Object?>? ?? const [];
            if (accepted.isEmpty) continue;
            final firstAcc = _qAsMap(accepted.first);
            if (firstAcc['type'] == 'items' && firstAcc['itemIds'] is List) {
              final itemIds = (firstAcc['itemIds'] as List<Object?>)
                  .map((e) => e.toString())
                  .toList();
              final texts = itemIds
                  .map((id) {
                    final t = _findItemPlainText(body['bank'], id);
                    return t.isNotEmpty ? t : id;
                  })
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (texts.isNotEmpty) {
                final asciiWordCount = texts
                    .where((s) => RegExp(r'^[A-Za-z0-9.,!?\x27"-]+$').hasMatch(s))
                    .length;
                final joiner = asciiWordCount >= texts.length / 2 ? ' ' : ' → ';
                parts.add(texts.join(joiner));
              }
            } else {
              final val =
                  (firstAcc['value'] ?? firstAcc['text'] ?? '')
                      .toString()
                      .trim();
              if (val.isNotEmpty) parts.add(val);
            }
          }
          if (parts.length == 1) return parts.first;
          if (parts.length > 1) {
            return [
              for (var i = 0; i < parts.length; i++) '(${i + 1}) ${parts[i]}',
            ].join('；');
          }
        }
        return _fallbackScalarFromGrading();

      case QuestionKind.match:
        final sets = grading['answerSets'] as List<Object?>? ?? const [];
        if (sets.isNotEmpty && sets.first is Map) {
          final expected = _qAsMap(_qAsMap(sets.first)['expected']);
          final pairs = expected['pairs'] as List<Object?>? ?? const [];
          final out = <String>[];
          for (final rawPair in pairs) {
            final pm = _qAsMap(rawPair);
            final fromId = pm['fromId']?.toString() ?? '';
            final toId = pm['toId']?.toString() ?? '';
            if (fromId.isEmpty || toId.isEmpty) continue;
            final leftTxt = _findItemPlainText(body['left'], fromId);
            final rightTxt = _findItemPlainText(body['right'], toId);
            out.add(
              '${leftTxt.isNotEmpty ? leftTxt : fromId} → ${rightTxt.isNotEmpty ? rightTxt : toId}',
            );
          }
          if (out.isNotEmpty) return out.join('；');
        }
        return _fallbackScalarFromGrading();

      case QuestionKind.classify:
        final sets = grading['answerSets'] as List<Object?>? ?? const [];
        if (sets.isNotEmpty && sets.first is Map) {
          final expected = _qAsMap(_qAsMap(sets.first)['expected']);
          final placements =
              expected['placements'] as List<Object?>? ?? const [];
          final grouped = <String, List<String>>{};
          for (final rawPl in placements) {
            final pl = _qAsMap(rawPl);
            final itemId = pl['itemId']?.toString() ?? '';
            final catId = pl['categoryId']?.toString() ?? '';
            if (itemId.isEmpty || catId.isEmpty) continue;
            final itemTxt = _findItemPlainText(body['items'], itemId);
            final catTxt = _findItemPlainText(body['categories'], catId);
            grouped
                .putIfAbsent(catTxt.isNotEmpty ? catTxt : catId, () => [])
                .add(itemTxt.isNotEmpty ? itemTxt : itemId);
          }
          if (grouped.isNotEmpty) {
            return grouped.entries
                .map((e) => '${e.key}：${e.value.join('、')}')
                .join('；');
          }
        }
        return _fallbackScalarFromGrading();

      case QuestionKind.solve:
        final fin = _qAsMap(grading['finalAnswer']);
        final vals = fin['acceptedValues'] as List<Object?>? ?? const [];
        final formattedVals = vals
            .map((v) {
              final m = _qAsMap(v);
              return (m['value'] ?? m['text'] ?? '').toString().trim();
            })
            .where((s) => s.isNotEmpty)
            .toList();
        if (formattedVals.isNotEmpty) return formattedVals.join(' 或 ');
        final refAns = _fallbackScalarFromGrading();
        if (refAns.isNotEmpty) return refAns;
        final pts = grading['scoringPoints'] as List<Object?>? ?? const [];
        if (pts.isNotEmpty) {
          final lastPt = _qAsMap(pts.last)['point']?.toString().trim() ?? '';
          if (lastPt.isNotEmpty) return lastPt;
        }
        return '';

      case QuestionKind.response:
      case QuestionKind.draw:
      case QuestionKind.write:
      case QuestionKind.spatial:
        final refAns = _fallbackScalarFromGrading();
        if (refAns.isNotEmpty) return refAns;
        final keywords = (grading['keywords'] as List<Object?>? ?? const [])
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (keywords.isNotEmpty) return keywords.join('、');
        final rubric = grading['rubric']?.toString().trim() ?? '';
        if (rubric.isNotEmpty) return rubric;
        return '';

      case QuestionKind.group:
        final subs = subQuestions;
        if (subs.isEmpty) return _fallbackScalarFromGrading();
        final out = <String>[];
        for (var i = 0; i < subs.length; i++) {
          final subAns = subs[i].formatReferenceAnswer();
          if (subAns.isNotEmpty) {
            out.add('(${i + 1}) $subAns');
          }
        }
        return out.join('；');
    }
  }

  String _fallbackScalarFromGrading() {
    final raw =
        (grading['referenceAnswer'] ?? grading['answer'])?.toString().trim() ??
        '';
    return raw;
  }

  static Map<String, Object?> _qAsMap(Object? raw) {
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, Object?>{};
  }

  static String _findItemPlainText(Object? rawList, String targetId) {
    if (rawList is! List) return '';
    for (final raw in rawList) {
      final m = _qAsMap(raw);
      if (m['id']?.toString() != targetId) continue;
      final content = m['content'];
      if (content is List) {
        final blocks = <ContentBlock>[];
        for (final item in content) {
          if (item is Map) {
            try {
              blocks.add(ContentBlock.fromJson(_qAsMap(item)));
            } catch (_) {}
          }
        }
        final plain = ContentTextUtils.extractPlainText(blocks).trim();
        if (plain.isNotEmpty) return plain;
      }
      final fallback =
          (m['label'] ?? m['text'] ?? m['title'] ?? '').toString().trim();
      if (fallback.isNotEmpty) return fallback;
    }
    return '';
  }

  Question copyWith({
    String? id,
    QuestionKind? kind,
    QuestionHeader? header,
    List<ContentBlock>? prompt,
    Map<String, Object?>? body,
    Map<String, Object?>? rules,
    QuestionPresentation? presentation,
    Map<String, Object?>? grading,
    List<ContentBlock>? explanation,
    QuestionMeta? meta,
    String? docId,
    String? sourceType,
    NormalizedBbox? bbox,
    List<Verdict>? historyVerdicts,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return Question(
      id: id ?? this.id,
      schema: schema,
      kind: kind ?? this.kind,
      header: header ?? this.header,
      prompt: prompt ?? this.prompt,
      body: body ?? this.body,
      rules: rules ?? this.rules,
      presentation: presentation ?? this.presentation,
      grading: grading ?? this.grading,
      explanation: explanation ?? this.explanation,
      meta: meta ?? this.meta,
      docId: docId ?? this.docId,
      sourceType: sourceType ?? this.sourceType,
      bbox: bbox ?? this.bbox,
      historyVerdicts: historyVerdicts ?? this.historyVerdicts,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'schema': schema,
    'kind': kind.code,
    'header': header.toJson(),
    'prompt': prompt.map((b) => b.toJson()).toList(growable: false),
    'body': body,
    'rules': rules,
    'presentation': presentation.toJson(),
    'grading': grading,
    'explanation': explanation.map((b) => b.toJson()).toList(growable: false),
    'meta': meta.toJson(),
    if (docId != null) 'docId': docId,
    'sourceType': sourceType,
    if (bbox != null) 'bbox': bbox!.toJson(),
    if (historyVerdicts.isNotEmpty)
      'historyVerdicts': historyVerdicts
          .map((v) => v.code)
          .toList(growable: false),
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
  };
}

/// Polymorphic student response stored inside practice attempts.
@immutable
sealed class StudentResponse {
  const StudentResponse({
    required this.questionId,
    required this.inputMode,
    this.durationMs = 0,
    this.hintsUsed = 0,
  });

  factory StudentResponse.fromJson(Map<String, Object?> json) {
    final type = json['type'] as String? ?? '';
    final qId = json['questionId'] as String? ?? '';
    final mode = InputMode.fromCode(json['inputMode'] as String? ?? 'standard');
    final duration = (json['durationMs'] as int?) ?? 0;
    final hints = (json['hintsUsed'] as int?) ?? 0;

    return switch (type) {
      'choice' => ChoiceResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        selectedIds: (json['selectedIds'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(growable: false),
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'fill' => FillResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        textEntries: (json['textEntries'] as Map<String, Object?>? ?? const {})
            .map((k, v) => MapEntry(k, v.toString())),
        itemEntries: (json['itemEntries'] as Map<String, Object?>? ?? const {})
            .map(
              (k, v) => MapEntry(
                k,
                (v as List<Object?>).cast<String>().toList(growable: false),
              ),
            ),
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'match' => MatchResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        pairs: (json['pairs'] as Map<String, Object?>? ?? const {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'classify' => ClassifyResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        placements: (json['placements'] as Map<String, Object?>? ?? const {})
            .map((k, v) => MapEntry(k, v as String?)),
      ),
      'response' => TextResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        parts: (json['parts'] as Map<String, Object?>? ?? const {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'solve' => SolveResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        steps: (json['steps'] as List<Object?>? ?? const [])
            .cast<String>()
            .toList(growable: false),
        finalAnswer: json['finalAnswer'] as String?,
        imageAssetId: json['imageAssetId'] as String?,
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'draw' => DrawResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        inkRegionId: json['inkRegionId'] as String?,
        composedPngBase64: json['composedPngBase64'] as String?,
        note: json['note'] as String?,
      ),
      'spatial' => SpatialResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        points: (json['points'] as List<Object?>? ?? const [])
            .map((p) {
              final pair = p! as List<Object?>;
              return (
                (pair[0]! as num).toDouble(),
                (pair[1]! as num).toDouble(),
              );
            })
            .toList(growable: false),
        placements: (json['placements'] as Map<String, Object?>? ?? const {})
            .map((k, v) => MapEntry(k, v.toString())),
      ),
      'write' => WriteResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        cells: (json['cells'] as Map<String, Object?>? ?? const {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        inkRegionId: json['inkRegionId'] as String?,
      ),
      'group' => GroupResponse(
        questionId: qId,
        inputMode: mode,
        durationMs: duration,
        hintsUsed: hints,
        children: (json['children'] as Map<String, Object?>? ?? const {}).map(
          (k, v) =>
              MapEntry(k, StudentResponse.fromJson(v! as Map<String, Object?>)),
        ),
      ),
      _ => throw FormatException('Unknown StudentResponse type: $type'),
    };
  }

  final String questionId;
  final InputMode inputMode;
  final int durationMs;
  final int hintsUsed;

  String get type;

  Map<String, Object?> toJson();

  String toReadableSummary();
}

@immutable
class ChoiceResponse extends StudentResponse {
  const ChoiceResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.selectedIds = const [],
    this.inkRegionId,
  });

  final List<String> selectedIds;
  final String? inkRegionId;

  @override
  String get type => 'choice';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'selectedIds': selectedIds,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() =>
      selectedIds.isEmpty ? '未作答' : selectedIds.join('、');
}

@immutable
class FillResponse extends StudentResponse {
  const FillResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.textEntries = const {},
    this.itemEntries = const {},
    this.inkRegionId,
  });

  final Map<String, String> textEntries;
  final Map<String, List<String>> itemEntries;
  final String? inkRegionId;

  @override
  String get type => 'fill';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'textEntries': textEntries,
    'itemEntries': itemEntries,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() {
    if (textEntries.isNotEmpty) {
      return textEntries.values.where((v) => v.isNotEmpty).join(' ; ');
    }
    if (itemEntries.isNotEmpty) {
      return itemEntries.values.map((l) => l.join(' ')).join(' ; ');
    }
    return inkRegionId != null ? '手写填写' : '未作答';
  }
}

@immutable
class MatchResponse extends StudentResponse {
  const MatchResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.pairs = const {},
    this.inkRegionId,
  });

  final Map<String, String> pairs;
  final String? inkRegionId;

  @override
  String get type => 'match';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'pairs': pairs,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() => pairs.isEmpty
      ? '未连线'
      : pairs.entries.map((e) => '${e.key}→${e.value}').join(', ');
}

@immutable
class ClassifyResponse extends StudentResponse {
  const ClassifyResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.placements = const {},
  });

  final Map<String, String?> placements;

  @override
  String get type => 'classify';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'placements': placements,
  };

  @override
  String toReadableSummary() =>
      placements.isEmpty ? '未分类' : '已归类 ${placements.length} 项';
}

@immutable
class TextResponse extends StudentResponse {
  const TextResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.parts = const {},
    this.inkRegionId,
  });

  final Map<String, String> parts;
  final String? inkRegionId;

  @override
  String get type => 'response';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'parts': parts,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() {
    final text = parts.values.where((v) => v.trim().isNotEmpty).join('\n');
    return text.isNotEmpty ? text : (inkRegionId != null ? '手写作答' : '未作答');
  }
}

@immutable
class SolveResponse extends StudentResponse {
  const SolveResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.steps = const [],
    this.finalAnswer,
    this.imageAssetId,
    this.inkRegionId,
  });

  final List<String> steps;
  final String? finalAnswer;
  final String? imageAssetId;
  final String? inkRegionId;

  @override
  String get type => 'solve';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'steps': steps,
    if (finalAnswer != null) 'finalAnswer': finalAnswer,
    if (imageAssetId != null) 'imageAssetId': imageAssetId,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() {
    final joined = steps.where((s) => s.trim().isNotEmpty).join(' → ');
    if (joined.isNotEmpty) return joined;
    if (finalAnswer != null && finalAnswer!.isNotEmpty) return finalAnswer!;
    return inkRegionId != null ? '手写演算步骤' : '未作答';
  }
}

@immutable
class DrawResponse extends StudentResponse {
  const DrawResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.inkRegionId,
    this.composedPngBase64,
    this.note,
  });

  final String? inkRegionId;
  final String? composedPngBase64;
  final String? note;

  @override
  String get type => 'draw';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
    if (composedPngBase64 != null) 'composedPngBase64': composedPngBase64,
    if (note != null) 'note': note,
  };

  @override
  String toReadableSummary() => note?.isNotEmpty == true
      ? note!
      : (inkRegionId != null ? '手写作图已提交' : '未作图');
}

@immutable
class SpatialResponse extends StudentResponse {
  const SpatialResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.points = const [],
    this.placements = const {},
  });

  final List<(double x, double y)> points;
  final Map<String, String> placements;

  @override
  String get type => 'spatial';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'points': points.map((p) => [p.$1, p.$2]).toList(growable: false),
    'placements': placements,
  };

  @override
  String toReadableSummary() => placements.isNotEmpty
      ? placements.entries.map((e) => '${e.key}→${e.value}').join(', ')
      : (points.isNotEmpty ? '已标注 ${points.length} 处' : '未标注');
}

@immutable
class WriteResponse extends StudentResponse {
  const WriteResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.cells = const {},
    this.inkRegionId,
  });

  final Map<String, String> cells;
  final String? inkRegionId;

  @override
  String get type => 'write';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'cells': cells,
    if (inkRegionId != null) 'inkRegionId': inkRegionId,
  };

  @override
  String toReadableSummary() => cells.isNotEmpty
      ? cells.values.where((v) => v.isNotEmpty).join(' / ')
      : (inkRegionId != null ? '手写格已书写' : '未书写');
}

@immutable
class GroupResponse extends StudentResponse {
  const GroupResponse({
    required super.questionId,
    required super.inputMode,
    super.durationMs,
    super.hintsUsed,
    this.children = const {},
  });

  final Map<String, StudentResponse> children;

  @override
  String get type => 'group';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'durationMs': durationMs,
    'hintsUsed': hintsUsed,
    'children': children.map((k, v) => MapEntry(k, v.toJson())),
  };

  @override
  String toReadableSummary() => '已完成 ${children.length} 道小题';
}

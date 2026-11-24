import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'content_plain_text.dart';
import 'enums.dart';
import 'question_models.dart';

@immutable
class PartResult {
  const PartResult({
    required this.partId,
    required this.ok,
    required this.score,
    required this.maxScore,
    this.comment,
  });

  final String partId;
  final bool ok;
  final double score;
  final double maxScore;
  final String? comment;
}

@immutable
class GradeOutcome {
  const GradeOutcome({
    required this.verdict,
    required this.score,
    required this.maxScore,
    this.parts = const [],
    this.needsAi = false,
    this.notes = const [],
    this.errorTagSuggestions = const [],
  });

  final Verdict verdict;
  final double score;
  final double maxScore;
  final List<PartResult> parts;
  final bool needsAi;
  final List<String> notes;
  final List<ErrorTag> errorTagSuggestions;
}

@immutable
class GradingConfig {
  const GradingConfig({this.pointHitTolerance = 0.04});

  final double pointHitTolerance;
}

/// Deterministic local grading engine for objective question kinds, numeric /
/// normalized fill-in-the-blank equivalence, spatial hit-testing, and
/// group score aggregation.
class GradingEngine {
  const GradingEngine();

  GradeOutcome grade(
    Question q,
    StudentResponse response, {
    GradingConfig config = const GradingConfig(),
  }) {
    final maxScore = q.maxScore;
    return switch (q.kind) {
      QuestionKind.choice => _gradeChoice(q, response, maxScore),
      QuestionKind.fill => _gradeFill(q, response, maxScore),
      QuestionKind.match => _gradeMatch(q, response, maxScore),
      QuestionKind.classify => _gradeClassify(q, response, maxScore),
      QuestionKind.spatial => _gradeSpatial(q, response, maxScore, config),
      QuestionKind.write => _gradeWrite(q, response, maxScore),
      QuestionKind.solve => _gradeSolve(q, response, maxScore),
      QuestionKind.response || QuestionKind.draw => GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
        notes: const ['主观/作图题需交由 AI 视觉判分或人工自评'],
      ),
      QuestionKind.group => _gradeGroup(q, response, config),
    };
  }

  GradeOutcome _gradeChoice(Question q, StudentResponse r, double maxScore) {
    if (r is! ChoiceResponse || r.selectedIds.isEmpty) {
      if (r is ChoiceResponse && r.inkRegionId != null) {
        return GradeOutcome(
          verdict: Verdict.ungraded,
          score: 0,
          maxScore: maxScore,
          needsAi: true,
          notes: const ['检测到手写选项括号内容，等待识别'],
        );
      }
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }

    final answerSets = q.grading['answerSets'] as List<Object?>? ?? const [];
    final partialCfg = q.grading['partialScore'] as Map<String, Object?>?;
    final partialEnabled = (partialCfg?['enabled'] as bool?) ?? false;
    final subsetScore =
        (partialCfg?['subsetScore'] as num?)?.toDouble() ?? (maxScore / 2);
    final wrongCancelsAll = (partialCfg?['wrongCancelsAll'] as bool?) ?? true;
    final actualSet = r.selectedIds.toSet();

    for (final rawSet in answerSets) {
      final expectedMap =
          (rawSet! as Map<String, Object?>)['expected']
              as Map<String, Object?>?;
      final expectedIds =
          (expectedMap?['selectedIds'] as List<Object?>? ?? const [])
              .cast<String>()
              .toSet();
      if (actualSet.length == expectedIds.length &&
          actualSet.containsAll(expectedIds)) {
        return GradeOutcome(
          verdict: Verdict.correct,
          score: maxScore,
          maxScore: maxScore,
        );
      }
      if (partialEnabled &&
          actualSet.isNotEmpty &&
          actualSet.every(expectedIds.contains) &&
          actualSet.length < expectedIds.length) {
        return GradeOutcome(
          verdict: Verdict.partial,
          score: subsetScore,
          maxScore: maxScore,
          notes: const ['多选题漏选，按部分分给分'],
        );
      }
      if (!wrongCancelsAll && actualSet.any(expectedIds.contains)) {
        return GradeOutcome(
          verdict: Verdict.partial,
          score: subsetScore,
          maxScore: maxScore,
        );
      }
    }

    return GradeOutcome(
      verdict: Verdict.wrong,
      score: 0,
      maxScore: maxScore,
      errorTagSuggestions: const [ErrorTag.concept],
    );
  }

  GradeOutcome _gradeFill(Question q, StudentResponse r, double maxScore) {
    if (r is! FillResponse) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    if (r.textEntries.isEmpty &&
        r.itemEntries.isEmpty &&
        r.inkRegionId != null) {
      return GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
        notes: const ['手写填空需 AI OCR 后判分'],
      );
    }
    if (r.textEntries.isEmpty && r.itemEntries.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }

    final normCfg =
        q.grading['normalization'] as Map<String, Object?>? ?? const {};
    final trim = (normCfg['trim'] as bool?) ?? true;
    final caseSensitive = (normCfg['caseSensitive'] as bool?) ?? false;
    final fullWidth = (normCfg['fullWidth'] as bool?) ?? true;
    final ignorePunct = (normCfg['ignorePunct'] as bool?) ?? false;
    final perSlot = q.grading['perSlotScore'] as Map<String, Object?>?;
    final answerSets = q.grading['answerSets'] as List<Object?>? ?? const [];

    double bestScore = -1;
    List<PartResult> bestParts = const [];

    for (final rawSet in answerSets) {
      final expectedMap =
          (rawSet! as Map<String, Object?>)['expected']
              as Map<String, Object?>?;
      final entries = expectedMap?['entries'] as List<Object?>? ?? const [];
      if (entries.isEmpty) continue;

      final defaultSlotMax = maxScore / entries.length;
      var total = 0.0;
      final parts = <PartResult>[];

      for (final rawEntry in entries) {
        final entry = rawEntry! as Map<String, Object?>;
        final slotId = entry['slotId'] as String;
        final slotMax =
            (perSlot?[slotId] as num?)?.toDouble() ?? defaultSlotMax;
        final accepted = entry['acceptedValues'] as List<Object?>? ?? const [];
        final ok = _matchesAnyAcceptedValue(
          accepted: accepted,
          textValue: r.textEntries[slotId],
          itemList: r.itemEntries[slotId],
          trim: trim,
          caseSensitive: caseSensitive,
          fullWidth: fullWidth,
          ignorePunct: ignorePunct,
        );
        final earned = ok ? slotMax : 0.0;
        total += earned;
        parts.add(
          PartResult(partId: slotId, ok: ok, score: earned, maxScore: slotMax),
        );
      }

      if (total > bestScore) {
        bestScore = total;
        bestParts = parts;
      }
    }

    if (bestScore < 0) {
      return GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
      );
    }

    final verdict = bestScore >= maxScore - 1e-6
        ? Verdict.correct
        : (bestScore > 0 ? Verdict.partial : Verdict.wrong);

    return GradeOutcome(
      verdict: verdict,
      score: bestScore,
      maxScore: maxScore,
      parts: bestParts,
      errorTagSuggestions: verdict == Verdict.wrong
          ? const [ErrorTag.calc]
          : const [],
    );
  }

  bool _matchesAnyAcceptedValue({
    required List<Object?> accepted,
    required String? textValue,
    required List<String>? itemList,
    required bool trim,
    required bool caseSensitive,
    required bool fullWidth,
    required bool ignorePunct,
  }) {
    for (final rawAcc in accepted) {
      final acc = rawAcc! as Map<String, Object?>;
      final type = acc['type'] as String? ?? 'text';
      if (type == 'items') {
        final expectedItems = (acc['itemIds'] as List<Object?>? ?? const [])
            .cast<String>();
        final actualItems = itemList ?? const <String>[];
        if (expectedItems.length == actualItems.length) {
          var same = true;
          for (var i = 0; i < expectedItems.length; i++) {
            if (expectedItems[i] != actualItems[i]) {
              same = false;
              break;
            }
          }
          if (same) return true;
        }
      } else if (type == 'number') {
        if (textValue == null) continue;
        final parsed = _parseNumericOrFraction(textValue);
        final expectedVal = (acc['value'] as num?)?.toDouble();
        final tol = (acc['tolerance'] as num?)?.toDouble() ?? 1e-6;
        if (parsed != null &&
            expectedVal != null &&
            (parsed - expectedVal).abs() <= tol) {
          return true;
        }
      } else {
        if (textValue == null) continue;
        final expectedText =
            acc['text'] as String? ?? acc['expr'] as String? ?? '';
        final normActual = ContentTextUtils.normalizeText(
          textValue,
          trim: trim,
          caseSensitive: caseSensitive,
          fullWidthToHalf: fullWidth,
          ignorePunct: ignorePunct,
        );
        final normExp = ContentTextUtils.normalizeText(
          expectedText,
          trim: trim,
          caseSensitive: caseSensitive,
          fullWidthToHalf: fullWidth,
          ignorePunct: ignorePunct,
        );
        if (normActual == normExp) return true;
      }
    }
    return false;
  }

  /// Parses integers, decimals, percentages, and simple fractions like `1/2`
  /// or `-3/4` (including full-width digits) so mathematical equivalence
  /// (`0.5 == 1/2`) passes locally.
  static double? _parseNumericOrFraction(String raw) {
    final cleaned = ContentTextUtils.normalizeText(
      raw,
      trim: true,
      fullWidthToHalf: true,
      ignorePunct: false,
    ).replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    final direct = double.tryParse(cleaned);
    if (direct != null) return direct;
    if (cleaned.endsWith('%')) {
      final pct = double.tryParse(cleaned.substring(0, cleaned.length - 1));
      if (pct != null) return pct / 100.0;
    }
    final slashIdx = cleaned.indexOf('/');
    if (slashIdx > 0 && slashIdx == cleaned.lastIndexOf('/')) {
      final numPart = double.tryParse(cleaned.substring(0, slashIdx));
      final denPart = double.tryParse(cleaned.substring(slashIdx + 1));
      if (numPart != null && denPart != null && denPart.abs() > 1e-12) {
        return numPart / denPart;
      }
    }
    return null;
  }

  GradeOutcome _gradeMatch(Question q, StudentResponse r, double maxScore) {
    if (r is! MatchResponse || r.pairs.isEmpty) {
      if (r is MatchResponse && r.inkRegionId != null) {
        return GradeOutcome(
          verdict: Verdict.ungraded,
          score: 0,
          maxScore: maxScore,
          needsAi: true,
        );
      }
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }

    final answerSets = q.grading['answerSets'] as List<Object?>? ?? const [];
    final partialCfg = q.grading['partialScore'] as Map<String, Object?>?;
    final partialEnabled = (partialCfg?['enabled'] as bool?) ?? true;
    final perPairScore = (partialCfg?['perPairScore'] as num?)?.toDouble();

    for (final rawSet in answerSets) {
      final expectedMap =
          (rawSet! as Map<String, Object?>)['expected']
              as Map<String, Object?>?;
      final expectedPairs = expectedMap?['pairs'] as List<Object?>? ?? const [];
      if (expectedPairs.isEmpty) continue;

      final pairWeight = perPairScore ?? (maxScore / expectedPairs.length);
      var correctCount = 0;
      final parts = <PartResult>[];

      for (final rawPair in expectedPairs) {
        final pair = rawPair! as Map<String, Object?>;
        final fromId = pair['fromId'] as String;
        final toId = pair['toId'] as String;
        final ok = r.pairs[fromId] == toId;
        if (ok) correctCount++;
        parts.add(
          PartResult(
            partId: fromId,
            ok: ok,
            score: ok ? pairWeight : 0,
            maxScore: pairWeight,
          ),
        );
      }

      if (correctCount == expectedPairs.length &&
          r.pairs.length == expectedPairs.length) {
        return GradeOutcome(
          verdict: Verdict.correct,
          score: maxScore,
          maxScore: maxScore,
          parts: parts,
        );
      }
      if (correctCount > 0 && partialEnabled) {
        return GradeOutcome(
          verdict: Verdict.partial,
          score: (correctCount * pairWeight).clamp(0, maxScore),
          maxScore: maxScore,
          parts: parts,
        );
      }
    }

    return GradeOutcome(
      verdict: Verdict.wrong,
      score: 0,
      maxScore: maxScore,
      errorTagSuggestions: const [ErrorTag.concept],
    );
  }

  GradeOutcome _gradeClassify(Question q, StudentResponse r, double maxScore) {
    if (r is! ClassifyResponse || r.placements.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }

    final answerSets = q.grading['answerSets'] as List<Object?>? ?? const [];
    final partialCfg = q.grading['partialScore'] as Map<String, Object?>?;
    final partialEnabled = (partialCfg?['enabled'] as bool?) ?? true;
    final perItemScore = (partialCfg?['perItemScore'] as num?)?.toDouble();

    for (final rawSet in answerSets) {
      final expectedMap =
          (rawSet! as Map<String, Object?>)['expected']
              as Map<String, Object?>?;
      final expected = expectedMap?['placements'] as List<Object?>? ?? const [];
      if (expected.isEmpty) continue;

      final itemWeight = perItemScore ?? (maxScore / expected.length);
      var okCount = 0;
      final parts = <PartResult>[];

      for (final rawPl in expected) {
        final pl = rawPl! as Map<String, Object?>;
        final itemId = pl['itemId'] as String;
        final catId = pl['categoryId'] as String;
        final ok = r.placements[itemId] == catId;
        if (ok) okCount++;
        parts.add(
          PartResult(
            partId: itemId,
            ok: ok,
            score: ok ? itemWeight : 0,
            maxScore: itemWeight,
          ),
        );
      }

      if (okCount == expected.length) {
        return GradeOutcome(
          verdict: Verdict.correct,
          score: maxScore,
          maxScore: maxScore,
          parts: parts,
        );
      }
      if (okCount > 0 && partialEnabled) {
        return GradeOutcome(
          verdict: Verdict.partial,
          score: (okCount * itemWeight).clamp(0, maxScore),
          maxScore: maxScore,
          parts: parts,
        );
      }
    }

    return GradeOutcome(
      verdict: Verdict.wrong,
      score: 0,
      maxScore: maxScore,
      errorTagSuggestions: const [ErrorTag.concept],
    );
  }

  GradeOutcome _gradeSpatial(
    Question q,
    StudentResponse r,
    double maxScore,
    GradingConfig config,
  ) {
    if (r is! SpatialResponse) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    final expected = q.grading['expected'] as Map<String, Object?>? ?? const {};
    final expectedPlacements = expected['placements'] as List<Object?>?;
    if (expectedPlacements != null && expectedPlacements.isNotEmpty) {
      if (r.placements.isEmpty) {
        return GradeOutcome(
          verdict: Verdict.skipped,
          score: 0,
          maxScore: maxScore,
        );
      }
      final perTarget = maxScore / expectedPlacements.length;
      var okCount = 0;
      final parts = <PartResult>[];
      for (final rawPl in expectedPlacements) {
        final pl = rawPl! as Map<String, Object?>;
        final labelId = pl['labelId'] as String;
        final targetId = pl['targetId'] as String;
        final ok = r.placements[labelId] == targetId;
        if (ok) okCount++;
        parts.add(
          PartResult(
            partId: labelId,
            ok: ok,
            score: ok ? perTarget : 0,
            maxScore: perTarget,
          ),
        );
      }
      final verdict = okCount == expectedPlacements.length
          ? Verdict.correct
          : (okCount > 0 ? Verdict.partial : Verdict.wrong);
      return GradeOutcome(
        verdict: verdict,
        score: (okCount * perTarget).clamp(0, maxScore),
        maxScore: maxScore,
        parts: parts,
      );
    }

    // Point-hit mode
    final expectedTargetIds = (expected['point'] as List<Object?>? ?? const [])
        .cast<String>();
    if (r.points.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    final targets = q.body['targets'] as List<Object?>? ?? const [];
    var hitCount = 0;
    for (final tid in expectedTargetIds) {
      final target = targets.cast<Map<String, Object?>>().firstWhere(
        (t) => t['id'] == tid,
        orElse: () => const <String, Object?>{},
      );
      final shape = target['shape'] as Map<String, Object?>?;
      if (shape == null) continue;
      if (r.points.any(
        (pt) => _pointInShape(pt, shape, config.pointHitTolerance),
      )) {
        hitCount++;
      }
    }
    final perPt = expectedTargetIds.isEmpty
        ? maxScore
        : maxScore / expectedTargetIds.length;
    final verdict = hitCount == expectedTargetIds.length
        ? Verdict.correct
        : (hitCount > 0 ? Verdict.partial : Verdict.wrong);
    return GradeOutcome(
      verdict: verdict,
      score: (hitCount * perPt).clamp(0, maxScore),
      maxScore: maxScore,
    );
  }

  bool _pointInShape(
    (double x, double y) pt,
    Map<String, Object?> shape,
    double tol,
  ) {
    final type = shape['type'] as String? ?? 'rect';
    if (type == 'circle') {
      final cx = (shape['cx'] as num?)?.toDouble() ?? 0;
      final cy = (shape['cy'] as num?)?.toDouble() ?? 0;
      final r = ((shape['r'] as num?)?.toDouble() ?? 0) + tol;
      final dx = pt.$1 - cx;
      final dy = pt.$2 - cy;
      return dx * dx + dy * dy <= r * r;
    }
    final x = ((shape['x'] as num?)?.toDouble() ?? 0) - tol;
    final y = ((shape['y'] as num?)?.toDouble() ?? 0) - tol;
    final w = ((shape['w'] as num?)?.toDouble() ?? 0) + tol * 2;
    final h = ((shape['h'] as num?)?.toDouble() ?? 0) + tol * 2;
    return pt.$1 >= x && pt.$1 <= x + w && pt.$2 >= y && pt.$2 <= y + h;
  }

  GradeOutcome _gradeWrite(Question q, StudentResponse r, double maxScore) {
    if (r is! WriteResponse) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    if (r.cells.isEmpty && r.inkRegionId != null) {
      return GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
        notes: const ['手写格字迹将由视觉模型逐字识别比对'],
      );
    }
    if (r.cells.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    final answerSets = q.grading['answerSets'] as List<Object?>? ?? const [];
    if (answerSets.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
      );
    }
    final entries =
        ((answerSets.first! as Map<String, Object?>)['expected']
                as Map<String, Object?>?)?['entries']
            as List<Object?>? ??
        const [];
    if (entries.isEmpty) {
      return GradeOutcome(
        verdict: Verdict.ungraded,
        score: 0,
        maxScore: maxScore,
        needsAi: true,
      );
    }

    var total = 0.0;
    final parts = <PartResult>[];
    for (final rawEntry in entries) {
      final entry = rawEntry! as Map<String, Object?>;
      final cellId = entry['cellId'] as String;
      final cellMax =
          (entry['score'] as num?)?.toDouble() ?? (maxScore / entries.length);
      final accepted = entry['acceptedValues'] as List<Object?>? ?? const [];
      final ok = _matchesAnyAcceptedValue(
        accepted: accepted,
        textValue: r.cells[cellId],
        itemList: null,
        trim: true,
        caseSensitive: false,
        fullWidth: true,
        ignorePunct: false,
      );
      total += ok ? cellMax : 0;
      parts.add(
        PartResult(
          partId: cellId,
          ok: ok,
          score: ok ? cellMax : 0,
          maxScore: cellMax,
        ),
      );
    }
    final verdict = total >= maxScore - 1e-6
        ? Verdict.correct
        : (total > 0 ? Verdict.partial : Verdict.wrong);
    return GradeOutcome(
      verdict: verdict,
      score: total.clamp(0, maxScore),
      maxScore: maxScore,
      parts: parts,
      errorTagSuggestions: verdict == Verdict.wrong
          ? const [ErrorTag.writing]
          : const [],
    );
  }

  GradeOutcome _gradeSolve(Question q, StudentResponse r, double maxScore) {
    if (r is! SolveResponse) {
      return GradeOutcome(
        verdict: Verdict.skipped,
        score: 0,
        maxScore: maxScore,
      );
    }
    if (r.finalAnswer != null && r.finalAnswer!.trim().isNotEmpty) {
      final finalAns = q.grading['finalAnswer'] as Map<String, Object?>?;
      final accepted =
          finalAns?['acceptedValues'] as List<Object?>? ?? const [];
      final ok = _matchesAnyAcceptedValue(
        accepted: accepted,
        textValue: r.finalAnswer,
        itemList: null,
        trim: true,
        caseSensitive: false,
        fullWidth: true,
        ignorePunct: false,
      );
      if (ok && r.steps.isNotEmpty) {
        return GradeOutcome(
          verdict: Verdict.ungraded,
          score: maxScore * 0.5,
          maxScore: maxScore,
          needsAi: true,
          notes: const ['终答案精确命中，过程分待 AI 逐步核验'],
        );
      }
    }
    return GradeOutcome(
      verdict: Verdict.ungraded,
      score: 0,
      maxScore: maxScore,
      needsAi: true,
      notes: const ['解答步骤交由 AI 分步判分或自评'],
    );
  }

  GradeOutcome _gradeGroup(
    Question q,
    StudentResponse r,
    GradingConfig config,
  ) {
    final rawChildren = q.body['questions'] as List<Object?>? ?? const [];
    final respChildren = r is GroupResponse
        ? r.children
        : const <String, StudentResponse>{};

    var totalScore = 0.0;
    var totalMax = 0.0;
    var anyAi = false;
    final parts = <PartResult>[];

    for (var i = 0; i < rawChildren.length; i++) {
      final child = Question.fromJson(
        rawChildren[i]! as Map<String, Object?>,
        fallbackId: '${q.id}_$i',
      );
      final childResp =
          respChildren[child.id] ??
          ChoiceResponse(questionId: child.id, inputMode: r.inputMode);
      final subOutcome = grade(child, childResp, config: config);
      totalScore += subOutcome.score;
      totalMax += subOutcome.maxScore;
      anyAi = anyAi || subOutcome.needsAi;
      parts.add(
        PartResult(
          partId: child.id,
          ok: subOutcome.verdict == Verdict.correct,
          score: subOutcome.score,
          maxScore: subOutcome.maxScore,
        ),
      );
    }

    final verdict = anyAi
        ? Verdict.ungraded
        : (totalScore >= totalMax - 1e-6 && totalMax > 0
              ? Verdict.correct
              : (totalScore > 0 ? Verdict.partial : Verdict.wrong));

    return GradeOutcome(
      verdict: verdict,
      score: totalScore,
      maxScore: totalMax > 0 ? totalMax : q.maxScore,
      parts: parts,
      needsAi: anyAi,
    );
  }
}

enum JudgeMode { rubric, stepwise, visual, write }

@immutable
class JudgeInput {
  const JudgeInput({
    required this.question,
    required this.grading,
    required this.response,
    required this.mode,
    this.stage = StudyStage.middle,
    this.images = const [],
  });

  final QuestionPublicView question;
  final Map<String, Object?> grading;
  final StudentResponse response;
  final JudgeMode mode;
  final StudyStage stage;
  final List<Uint8List> images;
}

@immutable
class StepFeedback {
  const StepFeedback({
    this.stepId,
    required this.ok,
    required this.comment,
    this.deduct = 0,
  });

  factory StepFeedback.fromJson(Map<String, Object?> json) {
    return StepFeedback(
      stepId: json['stepId'] as String?,
      ok: (json['ok'] as bool?) ?? false,
      comment: (json['comment'] as String?) ?? '',
      deduct: (json['deduct'] as num?)?.toDouble() ?? 0,
    );
  }

  final String? stepId;
  final bool ok;
  final String comment;
  final double deduct;

  Map<String, Object?> toJson() => {
    if (stepId != null) 'stepId': stepId,
    'ok': ok,
    'comment': comment,
    'deduct': deduct,
  };
}

@immutable
class JudgeResult {
  const JudgeResult({
    required this.verdict,
    required this.score,
    required this.maxScore,
    required this.confidence,
    this.recognizedText,
    this.steps = const [],
    this.errorTagSuggestions = const [],
    this.summary,
  });

  factory JudgeResult.fromJson(Map<String, Object?> json) {
    final stepsRaw = json['steps'] as List<Object?>? ?? const [];
    final tagsRaw = json['errorTagSuggestions'] as List<Object?>? ?? const [];
    return JudgeResult(
      verdict: Verdict.fromCode(json['verdict'] as String? ?? 'ungraded'),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      recognizedText: json['recognizedText'] as String?,
      steps: stepsRaw
          .map((e) => StepFeedback.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      errorTagSuggestions: tagsRaw
          .map((e) => ErrorTag.fromCode(e! as String))
          .toList(growable: false),
      summary: json['summary'] as String?,
    );
  }

  final Verdict verdict;
  final double score;
  final double maxScore;
  final double confidence;
  final String? recognizedText;
  final List<StepFeedback> steps;
  final List<ErrorTag> errorTagSuggestions;
  final String? summary;

  Map<String, Object?> toJson() => {
    'verdict': verdict.code,
    'score': score,
    'maxScore': maxScore,
    'confidence': confidence,
    if (recognizedText != null) 'recognizedText': recognizedText,
    'steps': steps.map((s) => s.toJson()).toList(growable: false),
    'errorTagSuggestions': errorTagSuggestions
        .map((e) => e.code)
        .toList(growable: false),
    if (summary != null) 'summary': summary,
  };
}

/// Abstract subjective/handwriting judge interface (implemented in `inou_ai`).
abstract interface class SubjectiveJudge {
  Future<JudgeResult> judge(JudgeInput input);
}

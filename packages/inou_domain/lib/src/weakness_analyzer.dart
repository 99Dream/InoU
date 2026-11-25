import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'enums.dart';
import 'knowledge_node.dart';
import 'question_models.dart';
import 'study_entities.dart';

@immutable
class WeaknessConfig {
  const WeaknessConfig({
    this.windowDays = 90,
    this.halfLifeDays = 30.0,
    this.minWrongForReport = 5,
  });

  final int windowDays;
  final double halfLifeDays;
  final int minWrongForReport;
}

@immutable
class KpWeaknessStat {
  const KpWeaknessStat({
    required this.kpId,
    required this.name,
    required this.subject,
    required this.isLeaf,
    required this.weightedErrors,
    required this.weightedTotal,
    required this.unmasteredCount,
    required this.rawWrongCount,
    required this.errorRate,
    required this.weakScore,
  });

  final String kpId;
  final String name;
  final String subject;
  final bool isLeaf;
  final double weightedErrors;
  final double weightedTotal;
  final int unmasteredCount;
  final int rawWrongCount;
  final double errorRate;
  final double weakScore;

  int get masteryPercent => ((1.0 - errorRate).clamp(0.0, 1.0) * 100).round();
}

@immutable
class WeeklyTrendPoint {
  const WeeklyTrendPoint({
    required this.label,
    required this.accuracyPercent,
    required this.attemptCount,
  });

  final String label;
  final double accuracyPercent;
  final int attemptCount;
}

@immutable
class WeaknessSnapshot {
  const WeaknessSnapshot({
    required this.rankedWeakLeaves,
    required this.allNodeStats,
    required this.subjectMasteryPercent,
    required this.errorTagCounts,
    required this.weeklyTrend,
    required this.uncategorizedWrongCount,
    required this.totalWrongSamples,
    required this.isSampleInsufficient,
  });

  final List<KpWeaknessStat> rankedWeakLeaves;
  final Map<String, KpWeaknessStat> allNodeStats;
  final Map<String, double> subjectMasteryPercent;
  final Map<ErrorTag, int> errorTagCounts;
  final List<WeeklyTrendPoint> weeklyTrend;
  final int uncategorizedWrongCount;
  final int totalWrongSamples;
  final bool isSampleInsufficient;

  Map<String, double> toWeakRateMap() => {
    for (final s in rankedWeakLeaves) s.kpId: s.weakScore,
  };
}

/// Pure-Dart analytics calculator implementing dev doc §9.4.
class WeaknessAnalyzer {
  const WeaknessAnalyzer();

  WeaknessSnapshot analyze({
    required List<Question> questions,
    required List<AttemptRecord> attempts,
    required List<WrongItem> wrongItems,
    required List<KnowledgeNode> kpNodes,
    required int nowMs,
    String? subjectFilter,
    WeaknessConfig config = const WeaknessConfig(),
  }) {
    final qById = <String, Question>{for (final q in questions) q.id: q};
    final kpById = <String, KnowledgeNode>{for (final n in kpNodes) n.id: n};

    final eAcc = <String, double>{};
    final tAcc = <String, double>{};
    final rawWrongAcc = <String, int>{};
    final unmasteredAcc = <String, int>{};

    final subjectErrAcc = <String, double>{};
    final subjectTotAcc = <String, double>{};
    final errorTags = <ErrorTag, int>{};

    var uncategorizedWrong = 0;
    var totalWrongCount = 0;

    final windowMs = config.windowDays * Duration.millisecondsPerDay;

    // 1. Track unmastered counts & photo_marked baseline wrong points.
    final wrongByQ = <String, WrongItem>{};
    for (final w in wrongItems) {
      wrongByQ[w.questionId] = w;
      final q = qById[w.questionId];
      if (q == null) continue;
      if (subjectFilter != null && q.meta.subject != subjectFilter) continue;

      for (final tag in w.errorTags) {
        errorTags[tag] = (errorTags[tag] ?? 0) + 1;
      }

      if (w.mastery != MasteryState.mastered) {
        totalWrongCount++;
        if (q.meta.kpIds.isEmpty) {
          uncategorizedWrong++;
        } else {
          for (final kpId in q.meta.kpIds) {
            unmasteredAcc[kpId] = (unmasteredAcc[kpId] ?? 0) + 1;
          }
        }
      }

      if (w.addedVia == AddedVia.photoMarked ||
          w.addedVia == AddedVia.photoSearch) {
        final ageDays = math.max(
          0.0,
          (nowMs - w.addedAtMs) / Duration.millisecondsPerDay,
        );
        final weight = math.pow(0.5, ageDays / config.halfLifeDays).toDouble();
        subjectErrAcc[q.meta.subject] =
            (subjectErrAcc[q.meta.subject] ?? 0) + weight;
        subjectTotAcc[q.meta.subject] =
            (subjectTotAcc[q.meta.subject] ?? 0) + weight;
        for (final kpId in q.meta.kpIds) {
          eAcc[kpId] = (eAcc[kpId] ?? 0) + weight;
          tAcc[kpId] = (tAcc[kpId] ?? 0) + weight;
          rawWrongAcc[kpId] = (rawWrongAcc[kpId] ?? 0) + 1;
        }
      }
    }

    // 2. Accumulate time-decayed attempts within window.
    final weeklyBuckets = <int, (int correct, int total)>{};
    for (final a in attempts) {
      if (nowMs - a.createdAtMs > windowMs) continue;
      if (a.verdict != Verdict.correct &&
          a.verdict != Verdict.wrong &&
          a.verdict != Verdict.partial) {
        continue;
      }
      final q = qById[a.questionId];
      if (q == null) continue;
      if (subjectFilter != null && q.meta.subject != subjectFilter) continue;

      final ageDays = math.max(
        0.0,
        (nowMs - a.createdAtMs) / Duration.millisecondsPerDay,
      );
      final weight = math.pow(0.5, ageDays / config.halfLifeDays).toDouble();
      final errFraction = switch (a.verdict) {
        Verdict.wrong => 1.0,
        Verdict.partial => 0.5,
        _ => 0.0,
      };

      subjectErrAcc[q.meta.subject] =
          (subjectErrAcc[q.meta.subject] ?? 0) + weight * errFraction;
      subjectTotAcc[q.meta.subject] =
          (subjectTotAcc[q.meta.subject] ?? 0) + weight;

      for (final kpId in q.meta.kpIds) {
        eAcc[kpId] = (eAcc[kpId] ?? 0) + weight * errFraction;
        tAcc[kpId] = (tAcc[kpId] ?? 0) + weight;
        if (a.verdict == Verdict.wrong || a.verdict == Verdict.partial) {
          rawWrongAcc[kpId] = (rawWrongAcc[kpId] ?? 0) + 1;
        }
      }

      final weekIdx = (ageDays / 7.0).floor().clamp(0, 5);
      final prev = weeklyBuckets[weekIdx] ?? (0, 0);
      weeklyBuckets[weekIdx] = (
        prev.$1 + (a.verdict == Verdict.correct ? 1 : 0),
        prev.$2 + 1,
      );
    }

    // 3. Build leaf stats + roll up ancestors.
    final allNodeStats = <String, KpWeaknessStat>{};
    final childrenByParent = <String, List<KnowledgeNode>>{};
    for (final node in kpNodes) {
      childrenByParent.putIfAbsent(node.parentId, () => []).add(node);
    }

    KpWeaknessStat computeNodeStat(KnowledgeNode node) {
      if (allNodeStats.containsKey(node.id)) return allNodeStats[node.id]!;
      final kids = childrenByParent[node.id] ?? const <KnowledgeNode>[];
      double e = eAcc[node.id] ?? 0;
      double t = tAcc[node.id] ?? 0;
      int unm = unmasteredAcc[node.id] ?? 0;
      int rawW = rawWrongAcc[node.id] ?? 0;

      if (!node.isLeaf && kids.isNotEmpty) {
        for (final k in kids) {
          final cs = computeNodeStat(k);
          e += cs.weightedErrors;
          t += cs.weightedTotal;
          unm += cs.unmasteredCount;
          rawW += cs.rawWrongCount;
        }
      }

      final rate = (e + 1.0) / (t + 3.0);
      final weak = rate * (1.0 + math.log(1.0 + unm));
      final stat = KpWeaknessStat(
        kpId: node.id,
        name: node.name,
        subject: node.subject,
        isLeaf: node.isLeaf,
        weightedErrors: e,
        weightedTotal: t,
        unmasteredCount: unm,
        rawWrongCount: rawW,
        errorRate: rate,
        weakScore: weak,
      );
      allNodeStats[node.id] = stat;
      return stat;
    }

    for (final node in kpNodes) {
      if (subjectFilter == null || node.subject == subjectFilter) {
        computeNodeStat(node);
      }
    }

    // Include any question kpIds absent from kpNodes.
    for (final kpId in {...eAcc.keys, ...unmasteredAcc.keys}) {
      if (!allNodeStats.containsKey(kpId)) {
        final e = eAcc[kpId] ?? 0;
        final t = tAcc[kpId] ?? 0;
        final unm = unmasteredAcc[kpId] ?? 0;
        final rawW = rawWrongAcc[kpId] ?? 0;
        final rate = (e + 1.0) / (t + 3.0);
        final weak = rate * (1.0 + math.log(1.0 + unm));
        allNodeStats[kpId] = KpWeaknessStat(
          kpId: kpId,
          name: kpById[kpId]?.name ?? kpId,
          subject: kpById[kpId]?.subject ?? 'other',
          isLeaf: true,
          weightedErrors: e,
          weightedTotal: t,
          unmasteredCount: unm,
          rawWrongCount: rawW,
          errorRate: rate,
          weakScore: weak,
        );
      }
    }

    final rankedLeaves =
        allNodeStats.values
            .where(
              (s) =>
                  s.isLeaf &&
                  (s.weightedTotal >= 1.5 || s.unmasteredCount >= 1),
            )
            .toList()
          ..sort((a, b) => b.weakScore.compareTo(a.weakScore));

    // Subject radar scores — only include subjects with recorded attempts or wrongs.
    final subjectMastery = <String, double>{};
    for (final code in const ['math', 'phy', 'eng', 'chn', 'chem']) {
      final t = subjectTotAcc[code] ?? 0.0;
      if (t <= 0) continue;
      final e = subjectErrAcc[code] ?? 0.0;
      final rate = (e + 0.8) / (t + 3.2);
      subjectMastery[code] = ((1.0 - rate) * 100).clamp(25.0, 96.0);
    }

    // Weekly trend (oldest W1 -> newest W6)
    final trend = <WeeklyTrendPoint>[];
    for (var w = 5; w >= 0; w--) {
      final b = weeklyBuckets[w];
      final label = 'W${6 - w}';
      final acc = b == null || b.$2 == 0
          ? 0.0
          : ((b.$1 / b.$2) * 100).clamp(0.0, 100.0);
      trend.add(
        WeeklyTrendPoint(
          label: label,
          accuracyPercent: acc,
          attemptCount: b?.$2 ?? 0,
        ),
      );
    }

    return WeaknessSnapshot(
      rankedWeakLeaves: rankedLeaves,
      allNodeStats: allNodeStats,
      subjectMasteryPercent: subjectMastery,
      errorTagCounts: errorTags,
      weeklyTrend: trend,
      uncategorizedWrongCount: uncategorizedWrong,
      totalWrongSamples: totalWrongCount,
      isSampleInsufficient: totalWrongCount < config.minWrongForReport,
    );
  }

  /// Computes positive improvement percentages per kpId relative to a prior
  /// report snapshot (`prevWeakRate - currWeakRate`).
  Map<String, double> compareSnapshots({
    required Map<String, double> previousWeakRates,
    required Map<String, double> currentWeakRates,
  }) {
    final diffs = <String, double>{};
    for (final entry in currentWeakRates.entries) {
      final prev = previousWeakRates[entry.key];
      if (prev != null) {
        diffs[entry.key] = (prev - entry.value) * 100.0;
      }
    }
    return diffs;
  }
}

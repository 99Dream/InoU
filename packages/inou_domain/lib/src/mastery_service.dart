import 'package:meta/meta.dart';

import 'enums.dart';
import 'study_entities.dart';

@immutable
class MasteryConfig {
  const MasteryConfig({
    this.masteryStreak = 3,
    this.partialClearsStreak = false,
  });

  final int masteryStreak;
  final bool partialClearsStreak;
}

@immutable
class MasteryUpdateOutcome {
  const MasteryUpdateOutcome({
    required this.item,
    required this.suggestPromptAdd,
    required this.stateChanged,
  });

  final WrongItem? item;
  final bool suggestPromptAdd;
  final bool stateChanged;
}

/// Pure-Dart wrong-question mastery state machine aligned with dev doc §9.3:
/// `newWrong -> learning -> reviewing -> mastered` upon reaching
/// [MasteryConfig.masteryStreak] consecutive correct attempts.
class MasteryService {
  const MasteryService();

  MasteryUpdateOutcome recordAttempt({
    required WrongItem? existing,
    required String questionId,
    required Verdict verdict,
    required int nowMs,
    required WrongBookCollectMode collectMode,
    required String myAnswerSummary,
    MasteryConfig config = const MasteryConfig(),
    List<ErrorTag> suggestedTags = const [],
  }) {
    if (verdict == Verdict.skipped ||
        verdict == Verdict.ungraded ||
        verdict == Verdict.unreadable) {
      return MasteryUpdateOutcome(
        item: existing,
        suggestPromptAdd: false,
        stateChanged: false,
      );
    }

    if (verdict == Verdict.correct) {
      if (existing == null) {
        return const MasteryUpdateOutcome(
          item: null,
          suggestPromptAdd: false,
          stateChanged: false,
        );
      }
      final nextStreak = existing.correctStreak + 1;
      final isMastered = nextStreak >= config.masteryStreak;
      final nextState = isMastered
          ? MasteryState.mastered
          : (nextStreak >= 2 ? MasteryState.reviewing : MasteryState.learning);
      return MasteryUpdateOutcome(
        item: existing.copyWith(
          attemptCount: existing.attemptCount + 1,
          correctStreak: nextStreak,
          mastery: nextState,
          lastAttemptAtMs: nowMs,
          masteredAtMs: isMastered ? nowMs : existing.masteredAtMs,
        ),
        suggestPromptAdd: false,
        stateChanged: existing.mastery != nextState,
      );
    }

    // Verdict.wrong or Verdict.partial
    if (existing == null) {
      if (collectMode == WrongBookCollectMode.auto) {
        return MasteryUpdateOutcome(
          item: WrongItem(
            id: 'wb_$questionId',
            questionId: questionId,
            addedVia: AddedVia.practice,
            mastery: MasteryState.newWrong,
            correctStreak: 0,
            wrongCount: 1,
            attemptCount: 1,
            errorTags: suggestedTags,
            myWrongAnswer: myAnswerSummary,
            addedAtMs: nowMs,
            lastAttemptAtMs: nowMs,
          ),
          suggestPromptAdd: false,
          stateChanged: true,
        );
      }
      return const MasteryUpdateOutcome(
        item: null,
        suggestPromptAdd: true,
        stateChanged: false,
      );
    }

    final shouldResetStreak =
        verdict == Verdict.wrong || config.partialClearsStreak;
    final nextStreak = shouldResetStreak ? 0 : existing.correctStreak;
    return MasteryUpdateOutcome(
      item: existing.copyWith(
        wrongCount: existing.wrongCount + 1,
        attemptCount: existing.attemptCount + 1,
        correctStreak: nextStreak,
        mastery: MasteryState.learning,
        myWrongAnswer: myAnswerSummary.isNotEmpty
            ? myAnswerSummary
            : existing.myWrongAnswer,
        lastAttemptAtMs: nowMs,
      ),
      suggestPromptAdd: false,
      stateChanged: existing.mastery != MasteryState.learning,
    );
  }
}

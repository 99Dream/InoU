import 'package:meta/meta.dart';

import 'enums.dart';
import 'question_models.dart';

@immutable
class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.name,
    required this.stage,
    required this.grade,
    this.subjects = const ['math', 'phy', 'eng'],
  });

  factory StudentProfile.fromJson(Map<String, Object?> json) {
    return StudentProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      stage: StudyStage.fromCode(json['stage'] as String? ?? 'm'),
      grade: json['grade'] as String? ?? '九年级',
      subjects: (json['subjects'] as List<Object?>? ?? const ['math'])
          .cast<String>()
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final StudyStage stage;
  final String grade;
  final List<String> subjects;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'stage': stage.code,
    'grade': grade,
    'subjects': subjects,
  };
}

@immutable
class SourceDoc {
  const SourceDoc({
    required this.id,
    required this.title,
    required this.docType,
    required this.subject,
    required this.grade,
    this.folderId,
    this.pageCount = 1,
    this.localImagePath,
    this.createdAtMs = 0,
  });

  factory SourceDoc.fromJson(Map<String, Object?> json) {
    return SourceDoc(
      id: json['id'] as String,
      title: json['title'] as String,
      docType: json['docType'] as String? ?? 'paper',
      subject: json['subject'] as String? ?? 'math',
      grade: json['grade'] as String? ?? 'g9',
      folderId: json['folderId'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
      localImagePath: json['localImagePath'] as String?,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String docType; // paper | workbook | ai_practice | other
  final String subject;
  final String grade;
  final String? folderId;
  final int pageCount;
  final String? localImagePath;
  final int createdAtMs;

  SourceDoc copyWith({
    String? title,
    String? docType,
    String? subject,
    String? grade,
    String? folderId,
    int? pageCount,
    String? localImagePath,
  }) {
    return SourceDoc(
      id: id,
      title: title ?? this.title,
      docType: docType ?? this.docType,
      subject: subject ?? this.subject,
      grade: grade ?? this.grade,
      folderId: folderId ?? this.folderId,
      pageCount: pageCount ?? this.pageCount,
      localImagePath: localImagePath ?? this.localImagePath,
      createdAtMs: createdAtMs,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'docType': docType,
    'subject': subject,
    'grade': grade,
    if (folderId != null) 'folderId': folderId,
    'pageCount': pageCount,
    if (localImagePath != null) 'localImagePath': localImagePath,
    'createdAtMs': createdAtMs,
  };
}

@immutable
class CaptureDraftItem {
  const CaptureDraftItem({
    required this.id,
    required this.sortOrder,
    required this.question,
    required this.confidence,
    this.teacherMark = 'none',
    this.studentAnswerSnippet,
    this.flaggedWrong = false,
    this.errorTags = const [],
    this.duplicateOfTitle,
    this.skipDuplicate = false,
    this.confirmed = false,
  });

  final String id;
  final int sortOrder;
  final Question question;
  final double confidence;
  final String teacherMark; // correct | wrong | partial | none
  final String? studentAnswerSnippet;
  final bool flaggedWrong;
  final List<ErrorTag> errorTags;
  final String? duplicateOfTitle;
  final bool skipDuplicate;
  final bool confirmed;

  CaptureDraftItem copyWith({
    Question? question,
    double? confidence,
    String? teacherMark,
    String? studentAnswerSnippet,
    bool? flaggedWrong,
    List<ErrorTag>? errorTags,
    String? duplicateOfTitle,
    bool? skipDuplicate,
    bool? confirmed,
  }) {
    return CaptureDraftItem(
      id: id,
      sortOrder: sortOrder,
      question: question ?? this.question,
      confidence: confidence ?? this.confidence,
      teacherMark: teacherMark ?? this.teacherMark,
      studentAnswerSnippet: studentAnswerSnippet ?? this.studentAnswerSnippet,
      flaggedWrong: flaggedWrong ?? this.flaggedWrong,
      errorTags: errorTags ?? this.errorTags,
      duplicateOfTitle: duplicateOfTitle ?? this.duplicateOfTitle,
      skipDuplicate: skipDuplicate ?? this.skipDuplicate,
      confirmed: confirmed ?? this.confirmed,
    );
  }
}

@immutable
class WrongItem {
  const WrongItem({
    required this.id,
    required this.questionId,
    required this.addedVia,
    this.mastery = MasteryState.newWrong,
    this.correctStreak = 0,
    this.wrongCount = 1,
    this.attemptCount = 0,
    this.errorTags = const [],
    this.myWrongAnswer = '',
    this.teacherMark = 'wrong',
    this.note = '',
    this.addedAtMs = 0,
    this.lastAttemptAtMs,
    this.masteredAtMs,
  });

  factory WrongItem.fromJson(Map<String, Object?> json) {
    return WrongItem(
      id: json['id'] as String,
      questionId: json['questionId'] as String,
      addedVia: AddedVia.fromCode(json['addedVia'] as String? ?? 'practice'),
      mastery: MasteryState.fromCode(json['mastery'] as String? ?? 'new'),
      correctStreak: (json['correctStreak'] as int?) ?? 0,
      wrongCount: (json['wrongCount'] as int?) ?? 1,
      attemptCount: (json['attemptCount'] as int?) ?? 0,
      errorTags: (json['errorTags'] as List<Object?>? ?? const [])
          .map((e) => ErrorTag.fromCode(e! as String))
          .toList(growable: false),
      myWrongAnswer: (json['myWrongAnswer'] as String?) ?? '',
      teacherMark: (json['teacherMark'] as String?) ?? 'wrong',
      note: (json['note'] as String?) ?? '',
      addedAtMs: (json['addedAtMs'] as int?) ?? 0,
      lastAttemptAtMs: json['lastAttemptAtMs'] as int?,
      masteredAtMs: json['masteredAtMs'] as int?,
    );
  }

  final String id;
  final String questionId;
  final AddedVia addedVia;
  final MasteryState mastery;
  final int correctStreak;
  final int wrongCount;
  final int attemptCount;
  final List<ErrorTag> errorTags;
  final String myWrongAnswer;
  final String teacherMark;
  final String note;
  final int addedAtMs;
  final int? lastAttemptAtMs;
  final int? masteredAtMs;

  WrongItem copyWith({
    MasteryState? mastery,
    int? correctStreak,
    int? wrongCount,
    int? attemptCount,
    List<ErrorTag>? errorTags,
    String? myWrongAnswer,
    String? teacherMark,
    String? note,
    int? lastAttemptAtMs,
    int? masteredAtMs,
  }) {
    return WrongItem(
      id: id,
      questionId: questionId,
      addedVia: addedVia,
      mastery: mastery ?? this.mastery,
      correctStreak: correctStreak ?? this.correctStreak,
      wrongCount: wrongCount ?? this.wrongCount,
      attemptCount: attemptCount ?? this.attemptCount,
      errorTags: errorTags ?? this.errorTags,
      myWrongAnswer: myWrongAnswer ?? this.myWrongAnswer,
      teacherMark: teacherMark ?? this.teacherMark,
      note: note ?? this.note,
      addedAtMs: addedAtMs,
      lastAttemptAtMs: lastAttemptAtMs ?? this.lastAttemptAtMs,
      masteredAtMs: masteredAtMs ?? this.masteredAtMs,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'questionId': questionId,
    'addedVia': addedVia.code,
    'mastery': mastery.code,
    'correctStreak': correctStreak,
    'wrongCount': wrongCount,
    'attemptCount': attemptCount,
    'errorTags': errorTags.map((e) => e.code).toList(growable: false),
    'myWrongAnswer': myWrongAnswer,
    'teacherMark': teacherMark,
    'note': note,
    'addedAtMs': addedAtMs,
    if (lastAttemptAtMs != null) 'lastAttemptAtMs': lastAttemptAtMs,
    if (masteredAtMs != null) 'masteredAtMs': masteredAtMs,
  };
}

@immutable
class AttemptRecord {
  const AttemptRecord({
    required this.id,
    required this.sessionId,
    required this.questionId,
    required this.inputMode,
    required this.verdict,
    required this.score,
    required this.maxScore,
    this.judgedBy = JudgedBy.auto,
    this.recognizedText,
    this.feedbackSummary,
    this.hintsUsed = 0,
    this.durationMs = 0,
    this.basedOnAiAnswer = false,
    required this.createdAtMs,
    this.response,
  });

  factory AttemptRecord.fromJson(Map<String, Object?> json) {
    final respJson = json['response'];
    return AttemptRecord(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      questionId: json['questionId'] as String,
      inputMode: InputMode.fromCode(json['inputMode'] as String? ?? 'standard'),
      verdict: Verdict.fromCode(json['verdict'] as String? ?? 'ungraded'),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 1,
      judgedBy: JudgedBy.fromCode(json['judgedBy'] as String? ?? 'auto'),
      recognizedText: json['recognizedText'] as String?,
      feedbackSummary: json['feedbackSummary'] as String?,
      hintsUsed: (json['hintsUsed'] as int?) ?? 0,
      durationMs: (json['durationMs'] as int?) ?? 0,
      basedOnAiAnswer: (json['basedOnAiAnswer'] as bool?) ?? false,
      createdAtMs: (json['createdAtMs'] as int?) ?? 0,
      response: respJson is Map<String, Object?>
          ? StudentResponse.fromJson(respJson)
          : null,
    );
  }

  final String id;
  final String sessionId;
  final String questionId;
  final InputMode inputMode;
  final Verdict verdict;
  final double score;
  final double maxScore;
  final JudgedBy judgedBy;
  final String? recognizedText;
  final String? feedbackSummary;
  final int hintsUsed;
  final int durationMs;
  final bool basedOnAiAnswer;
  final int createdAtMs;
  final StudentResponse? response;

  AttemptRecord copyWith({
    Verdict? verdict,
    double? score,
    JudgedBy? judgedBy,
    String? recognizedText,
    String? feedbackSummary,
  }) {
    return AttemptRecord(
      id: id,
      sessionId: sessionId,
      questionId: questionId,
      inputMode: inputMode,
      verdict: verdict ?? this.verdict,
      score: score ?? this.score,
      maxScore: maxScore,
      judgedBy: judgedBy ?? this.judgedBy,
      recognizedText: recognizedText ?? this.recognizedText,
      feedbackSummary: feedbackSummary ?? this.feedbackSummary,
      hintsUsed: hintsUsed,
      durationMs: durationMs,
      basedOnAiAnswer: basedOnAiAnswer,
      createdAtMs: createdAtMs,
      response: response,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'questionId': questionId,
    'inputMode': inputMode.code,
    'verdict': verdict.code,
    'score': score,
    'maxScore': maxScore,
    'judgedBy': judgedBy.code,
    if (recognizedText != null) 'recognizedText': recognizedText,
    if (feedbackSummary != null) 'feedbackSummary': feedbackSummary,
    'hintsUsed': hintsUsed,
    'durationMs': durationMs,
    'basedOnAiAnswer': basedOnAiAnswer,
    'createdAtMs': createdAtMs,
    if (response != null) 'response': response!.toJson(),
  };
}

@immutable
class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.title,
    required this.kind,
    required this.inputMode,
    required this.feedbackTiming,
    required this.questionIds,
    this.docId,
    required this.startedAtMs,
    this.submittedAtMs,
    this.status = 'in_progress',
    this.totalScore = 0,
    this.maxScore = 0,
  });

  factory PracticeSession.fromJson(Map<String, Object?> json) {
    return PracticeSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '练习会话',
      kind: PracticeKind.fromCode(json['kind'] as String? ?? 'custom'),
      inputMode: InputMode.fromCode(json['inputMode'] as String? ?? 'standard'),
      feedbackTiming: FeedbackTiming.fromCode(
        json['feedbackTiming'] as String? ?? 'after_submit',
      ),
      questionIds: (json['questionIds'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      docId: json['docId'] as String?,
      startedAtMs: (json['startedAtMs'] as int?) ?? 0,
      submittedAtMs: json['submittedAtMs'] as int?,
      status: json['status'] as String? ?? 'in_progress',
      totalScore: (json['totalScore'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String title;
  final PracticeKind kind;
  final InputMode inputMode;
  final FeedbackTiming feedbackTiming;
  final List<String> questionIds;
  final String? docId;
  final int startedAtMs;
  final int? submittedAtMs;
  final String status; // in_progress | submitted | abandoned
  final double totalScore;
  final double maxScore;

  PracticeSession copyWith({
    InputMode? inputMode,
    int? submittedAtMs,
    String? status,
    double? totalScore,
    double? maxScore,
  }) {
    return PracticeSession(
      id: id,
      title: title,
      kind: kind,
      inputMode: inputMode ?? this.inputMode,
      feedbackTiming: feedbackTiming,
      questionIds: questionIds,
      docId: docId,
      startedAtMs: startedAtMs,
      submittedAtMs: submittedAtMs ?? this.submittedAtMs,
      status: status ?? this.status,
      totalScore: totalScore ?? this.totalScore,
      maxScore: maxScore ?? this.maxScore,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.code,
    'inputMode': inputMode.code,
    'feedbackTiming': feedbackTiming.code,
    'questionIds': questionIds,
    if (docId != null) 'docId': docId,
    'startedAtMs': startedAtMs,
    if (submittedAtMs != null) 'submittedAtMs': submittedAtMs,
    'status': status,
    'totalScore': totalScore,
    'maxScore': maxScore,
  };
}

@immutable
class WeaknessPointSummary {
  const WeaknessPointSummary({
    required this.kpId,
    required this.kpName,
    required this.severity,
    this.reasons = const [],
    this.advice = const [],
    this.suggestedCount = 5,
  });

  factory WeaknessPointSummary.fromJson(Map<String, Object?> json) {
    final sug = json['suggestedPractice'] as Map<String, Object?>?;
    return WeaknessPointSummary(
      kpId: json['kpId'] as String? ?? '',
      kpName: json['kpName'] as String? ?? '',
      severity: json['severity'] as String? ?? 'medium',
      reasons: (json['reasons'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      advice: (json['advice'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      suggestedCount:
          (sug?['count'] as int?) ?? (json['suggestedCount'] as int?) ?? 5,
    );
  }

  final String kpId;
  final String kpName;
  final String severity;
  final List<String> reasons;
  final List<String> advice;
  final int suggestedCount;

  Map<String, Object?> toJson() => {
    'kpId': kpId,
    'kpName': kpName,
    'severity': severity,
    'reasons': reasons,
    'advice': advice,
    'suggestedCount': suggestedCount,
  };
}

@immutable
class StudyPlanStep {
  const StudyPlanStep({required this.day, required this.task});

  factory StudyPlanStep.fromJson(Map<String, Object?> json) {
    return StudyPlanStep(
      day: json['day'] as String? ?? '',
      task: json['task'] as String? ?? '',
    );
  }

  final String day;
  final String task;

  Map<String, Object?> toJson() => {'day': day, 'task': task};
}

@immutable
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.createdAtMs,
    required this.markdown,
    required this.overallAdvice,
    this.weakPoints = const [],
    this.plan = const [],
    this.kpWeakRates = const {},
    this.toolTrace = const [],
  });

  factory ReportRecord.fromJson(Map<String, Object?> json) {
    return ReportRecord(
      id: json['id'] as String,
      createdAtMs: (json['createdAtMs'] as int?) ?? 0,
      markdown: json['markdown'] as String? ?? '',
      overallAdvice: json['overallAdvice'] as String? ?? '',
      weakPoints: (json['weakPoints'] as List<Object?>? ?? const [])
          .map((e) => WeaknessPointSummary.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      plan: (json['plan'] as List<Object?>? ?? const [])
          .map((e) => StudyPlanStep.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
      kpWeakRates: (json['kpWeakRates'] as Map<String, Object?>? ?? const {})
          .map((k, v) => MapEntry(k, (v! as num).toDouble())),
      toolTrace: (json['toolTrace'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
    );
  }

  final String id;
  final int createdAtMs;
  final String markdown;
  final String overallAdvice;
  final List<WeaknessPointSummary> weakPoints;
  final List<StudyPlanStep> plan;
  final Map<String, double> kpWeakRates;
  final List<String> toolTrace;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAtMs': createdAtMs,
    'markdown': markdown,
    'overallAdvice': overallAdvice,
    'weakPoints': weakPoints.map((w) => w.toJson()).toList(growable: false),
    'plan': plan.map((p) => p.toJson()).toList(growable: false),
    'kpWeakRates': kpWeakRates,
    'toolTrace': toolTrace,
  };
}

@immutable
class TutorMessageRecord {
  const TutorMessageRecord({
    required this.id,
    required this.role, // user | assistant | system
    required this.content,
    this.emotion = 'happy',
    this.toolTrace = const [],
    this.antiSpoilerBlocked = false,
    required this.createdAtMs,
  });

  factory TutorMessageRecord.fromJson(Map<String, Object?> json) {
    return TutorMessageRecord(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      emotion: json['emotion'] as String? ?? 'happy',
      toolTrace: (json['toolTrace'] as List<Object?>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      antiSpoilerBlocked: (json['antiSpoilerBlocked'] as bool?) ?? false,
      createdAtMs: (json['createdAtMs'] as int?) ?? 0,
    );
  }

  final String id;
  final String role;
  final String content;
  final String emotion;
  final List<String> toolTrace;
  final bool antiSpoilerBlocked;
  final int createdAtMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'emotion': emotion,
    'toolTrace': toolTrace,
    'antiSpoilerBlocked': antiSpoilerBlocked,
    'createdAtMs': createdAtMs,
  };
}

@immutable
class TutorThreadRecord {
  const TutorThreadRecord({
    required this.id,
    required this.scope, // question | global | temp | lasso
    this.questionId,
    this.hintLevel = 0,
    this.summary,
    this.messages = const [],
  });

  factory TutorThreadRecord.fromJson(Map<String, Object?> json) {
    return TutorThreadRecord(
      id: json['id'] as String,
      scope: json['scope'] as String? ?? 'global',
      questionId: json['questionId'] as String?,
      hintLevel: (json['hintLevel'] as int?) ?? 0,
      summary: json['summary'] as String?,
      messages: (json['messages'] as List<Object?>? ?? const [])
          .map((e) => TutorMessageRecord.fromJson(e! as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final String id;
  final String scope;
  final String? questionId;
  final int hintLevel;
  final String? summary;
  final List<TutorMessageRecord> messages;

  TutorThreadRecord copyWith({
    int? hintLevel,
    String? summary,
    List<TutorMessageRecord>? messages,
  }) {
    return TutorThreadRecord(
      id: id,
      scope: scope,
      questionId: questionId,
      hintLevel: hintLevel ?? this.hintLevel,
      summary: summary ?? this.summary,
      messages: messages ?? this.messages,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'scope': scope,
    if (questionId != null) 'questionId': questionId,
    'hintLevel': hintLevel,
    if (summary != null) 'summary': summary,
    'messages': messages.map((m) => m.toJson()).toList(growable: false),
  };
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.onboardingCompleted = false,
    this.consentAccepted = false,
    this.defaultInputMode,
    this.wrongBookCollectMode = WrongBookCollectMode.ask,
    this.masteryStreak = 3,
    this.partialClearsStreak = false,
    this.mascotVisible = true,
    this.mascotAnimating = true,
    this.parentPinEnabled = false,
    this.allowLocalLanEndpoints = false,
    this.darkModePreference = 'system',
  });

  factory AppPreferences.fromJson(Map<String, Object?> json) {
    final modeStr = json['defaultInputMode'] as String?;
    return AppPreferences(
      onboardingCompleted: (json['onboardingCompleted'] as bool?) ?? false,
      consentAccepted: (json['consentAccepted'] as bool?) ?? false,
      defaultInputMode: modeStr != null ? InputMode.fromCode(modeStr) : null,
      wrongBookCollectMode: WrongBookCollectMode.fromCode(
        json['wrongBookCollectMode'] as String? ?? 'ask',
      ),
      masteryStreak: (json['masteryStreak'] as int?) ?? 3,
      partialClearsStreak: (json['partialClearsStreak'] as bool?) ?? false,
      mascotVisible: (json['mascotVisible'] as bool?) ?? true,
      mascotAnimating: (json['mascotAnimating'] as bool?) ?? true,
      parentPinEnabled: (json['parentPinEnabled'] as bool?) ?? false,
      allowLocalLanEndpoints:
          (json['allowLocalLanEndpoints'] as bool?) ?? false,
      darkModePreference: (json['darkModePreference'] as String?) ?? 'system',
    );
  }

  final bool onboardingCompleted;
  final bool consentAccepted;
  final InputMode? defaultInputMode;
  final WrongBookCollectMode wrongBookCollectMode;
  final int masteryStreak;
  final bool partialClearsStreak;
  final bool mascotVisible;
  final bool mascotAnimating;
  final bool parentPinEnabled;
  final bool allowLocalLanEndpoints;
  final String darkModePreference; // system | light | dark

  AppPreferences copyWith({
    bool? onboardingCompleted,
    bool? consentAccepted,
    InputMode? defaultInputMode,
    bool clearDefaultInputMode = false,
    WrongBookCollectMode? wrongBookCollectMode,
    int? masteryStreak,
    bool? partialClearsStreak,
    bool? mascotVisible,
    bool? mascotAnimating,
    bool? parentPinEnabled,
    bool? allowLocalLanEndpoints,
    String? darkModePreference,
  }) {
    return AppPreferences(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      consentAccepted: consentAccepted ?? this.consentAccepted,
      defaultInputMode: clearDefaultInputMode
          ? null
          : (defaultInputMode ?? this.defaultInputMode),
      wrongBookCollectMode: wrongBookCollectMode ?? this.wrongBookCollectMode,
      masteryStreak: masteryStreak ?? this.masteryStreak,
      partialClearsStreak: partialClearsStreak ?? this.partialClearsStreak,
      mascotVisible: mascotVisible ?? this.mascotVisible,
      mascotAnimating: mascotAnimating ?? this.mascotAnimating,
      parentPinEnabled: parentPinEnabled ?? this.parentPinEnabled,
      allowLocalLanEndpoints:
          allowLocalLanEndpoints ?? this.allowLocalLanEndpoints,
      darkModePreference: darkModePreference ?? this.darkModePreference,
    );
  }

  Map<String, Object?> toJson() => {
    'onboardingCompleted': onboardingCompleted,
    'consentAccepted': consentAccepted,
    if (defaultInputMode != null) 'defaultInputMode': defaultInputMode!.code,
    'wrongBookCollectMode': wrongBookCollectMode.code,
    'masteryStreak': masteryStreak,
    'partialClearsStreak': partialClearsStreak,
    'mascotVisible': mascotVisible,
    'mascotAnimating': mascotAnimating,
    'parentPinEnabled': parentPinEnabled,
    'allowLocalLanEndpoints': allowLocalLanEndpoints,
    'darkModePreference': darkModePreference,
  };
}

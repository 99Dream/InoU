import 'package:flutter/foundation.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';

/// Complete study workspace belonging to one [StudentProfile].
@immutable
class ProfileWorkspaceData {
  const ProfileWorkspaceData({
    this.questions = const [],
    this.sourceDocs = const [],
    this.captureDrafts = const [],
    this.captureDocTitle = '',
    this.wrongItems = const [],
    this.attempts = const [],
    this.sessions = const [],
    this.reports = const [],
    this.tutorThreads = const [],
    this.inkPagesByQuestionId = const {},
    this.blackboardLessonsByQuestionId = const {},
    this.photoSearchHistory = const [],
  });

  factory ProfileWorkspaceData.fromJson(Map<String, Object?> json) {
    final rawInk =
        json['inkPagesByQuestionId'] as Map<String, Object?>? ?? const {};
    final rawBlackboard =
        json['blackboardLessonsByQuestionId'] as Map<String, Object?>? ??
        const {};
    return ProfileWorkspaceData(
      questions: (json['questions'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => Question.fromJson(_strMap(e)))
          .toList(growable: false),
      sourceDocs: (json['sourceDocs'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => SourceDoc.fromJson(_strMap(e)))
          .toList(growable: false),
      captureDrafts: (json['captureDrafts'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => _draftFromJson(_strMap(e)))
          .toList(growable: false),
      captureDocTitle: json['captureDocTitle'] as String? ?? '',
      wrongItems: (json['wrongItems'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => WrongItem.fromJson(_strMap(e)))
          .toList(growable: false),
      attempts: (json['attempts'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => AttemptRecord.fromJson(_strMap(e)))
          .toList(growable: false),
      sessions: (json['sessions'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => PracticeSession.fromJson(_strMap(e)))
          .toList(growable: false),
      reports: (json['reports'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => ReportRecord.fromJson(_strMap(e)))
          .toList(growable: false),
      tutorThreads: (json['tutorThreads'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((e) => TutorThreadRecord.fromJson(_strMap(e)))
          .toList(growable: false),
      inkPagesByQuestionId: rawInk.map(
        (k, v) => MapEntry(k, InkPageData.fromJson(_strMap(v! as Map))),
      ),
      blackboardLessonsByQuestionId: rawBlackboard.map(
        (k, v) =>
            MapEntry(k, BlackboardLessonRecord.fromJson(_strMap(v! as Map))),
      ),
      photoSearchHistory:
          (json['photoSearchHistory'] as List<Object?>? ?? const [])
              .whereType<Map<Object?, Object?>>()
              .map((e) => PhotoSearchSession.fromJson(_strMap(e)))
              .toList(growable: false),
    );
  }

  final List<Question> questions;
  final List<SourceDoc> sourceDocs;
  final List<CaptureDraftItem> captureDrafts;
  final String captureDocTitle;
  final List<WrongItem> wrongItems;
  final List<AttemptRecord> attempts;
  final List<PracticeSession> sessions;
  final List<ReportRecord> reports;
  final List<TutorThreadRecord> tutorThreads;
  final Map<String, InkPageData> inkPagesByQuestionId;
  final Map<String, BlackboardLessonRecord> blackboardLessonsByQuestionId;
  final List<PhotoSearchSession> photoSearchHistory;

  ProfileWorkspaceData copyWith({
    List<Question>? questions,
    List<SourceDoc>? sourceDocs,
    List<CaptureDraftItem>? captureDrafts,
    String? captureDocTitle,
    List<WrongItem>? wrongItems,
    List<AttemptRecord>? attempts,
    List<PracticeSession>? sessions,
    List<ReportRecord>? reports,
    List<TutorThreadRecord>? tutorThreads,
    Map<String, InkPageData>? inkPagesByQuestionId,
    Map<String, BlackboardLessonRecord>? blackboardLessonsByQuestionId,
    List<PhotoSearchSession>? photoSearchHistory,
  }) {
    return ProfileWorkspaceData(
      questions: questions ?? this.questions,
      sourceDocs: sourceDocs ?? this.sourceDocs,
      captureDrafts: captureDrafts ?? this.captureDrafts,
      captureDocTitle: captureDocTitle ?? this.captureDocTitle,
      wrongItems: wrongItems ?? this.wrongItems,
      attempts: attempts ?? this.attempts,
      sessions: sessions ?? this.sessions,
      reports: reports ?? this.reports,
      tutorThreads: tutorThreads ?? this.tutorThreads,
      inkPagesByQuestionId: inkPagesByQuestionId ?? this.inkPagesByQuestionId,
      blackboardLessonsByQuestionId:
          blackboardLessonsByQuestionId ?? this.blackboardLessonsByQuestionId,
      photoSearchHistory: photoSearchHistory ?? this.photoSearchHistory,
    );
  }

  Map<String, Object?> toJson() => {
    'questions': questions.map((e) => e.toJson()).toList(growable: false),
    'sourceDocs': sourceDocs.map((e) => e.toJson()).toList(growable: false),
    'captureDrafts': captureDrafts.map(_draftToJson).toList(growable: false),
    'captureDocTitle': captureDocTitle,
    'wrongItems': wrongItems.map((e) => e.toJson()).toList(growable: false),
    'attempts': attempts.map((e) => e.toJson()).toList(growable: false),
    'sessions': sessions.map((e) => e.toJson()).toList(growable: false),
    'reports': reports.map((e) => e.toJson()).toList(growable: false),
    'tutorThreads': tutorThreads.map((e) => e.toJson()).toList(growable: false),
    'inkPagesByQuestionId': inkPagesByQuestionId.map(
      (k, v) => MapEntry(k, v.toJson()),
    ),
    if (blackboardLessonsByQuestionId.isNotEmpty)
      'blackboardLessonsByQuestionId': blackboardLessonsByQuestionId.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
    if (photoSearchHistory.isNotEmpty)
      'photoSearchHistory': photoSearchHistory
          .map((e) => e.toJson())
          .toList(growable: false),
  };

  static Map<String, Object?> _strMap(Map<Object?, Object?> raw) =>
      raw.map((k, v) => MapEntry(k.toString(), v));

  static CaptureDraftItem _draftFromJson(Map<String, Object?> json) {
    return CaptureDraftItem(
      id: json['id'] as String? ?? 'draft',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 1,
      question: Question.fromJson(_strMap(json['question']! as Map)),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      teacherMark: json['teacherMark'] as String? ?? 'none',
      studentAnswerSnippet: json['studentAnswerSnippet'] as String?,
      flaggedWrong: (json['flaggedWrong'] as bool?) ?? false,
      errorTags: (json['errorTags'] as List<Object?>? ?? const [])
          .map((e) => ErrorTag.fromCode(e.toString()))
          .toList(growable: false),
      duplicateOfTitle: json['duplicateOfTitle'] as String?,
      skipDuplicate: (json['skipDuplicate'] as bool?) ?? false,
      confirmed: (json['confirmed'] as bool?) ?? false,
    );
  }

  static Map<String, Object?> _draftToJson(CaptureDraftItem d) => {
    'id': d.id,
    'sortOrder': d.sortOrder,
    'question': d.question.toJson(),
    'confidence': d.confidence,
    'teacherMark': d.teacherMark,
    if (d.studentAnswerSnippet != null)
      'studentAnswerSnippet': d.studentAnswerSnippet,
    'flaggedWrong': d.flaggedWrong,
    'errorTags': d.errorTags.map((e) => e.code).toList(growable: false),
    if (d.duplicateOfTitle != null) 'duplicateOfTitle': d.duplicateOfTitle,
    'skipDuplicate': d.skipDuplicate,
    'confirmed': d.confirmed,
  };
}

/// Complete non-secret application persistence snapshot across all student
/// profiles. Backed up directly by `.inou` ZIP archives.
@immutable
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.profiles,
    required this.activeProfileId,
    required this.workspaces,
    required this.endpoints,
    required this.activeEndpointId,
    required this.preferences,
    this.schemaVersion = 1,
  });

  factory WorkspaceSnapshot.clean() {
    const profile = StudentProfile(
      id: 'profile_default',
      name: '新同学',
      stage: StudyStage.middle,
      grade: '九年级',
      subjects: ['math', 'phy', 'eng'],
    );
    final endpoints = AiEndpointPresets.defaults();
    return WorkspaceSnapshot(
      profiles: [profile],
      activeProfileId: profile.id,
      workspaces: const {'profile_default': ProfileWorkspaceData()},
      endpoints: endpoints,
      activeEndpointId: endpoints.first.id,
      preferences: const AppPreferences(
        onboardingCompleted: false,
        consentAccepted: true,
      ),
    );
  }

  factory WorkspaceSnapshot.fromJson(Map<String, Object?> json) {
    final rawWorkspaces =
        json['workspaces'] as Map<String, Object?>? ?? const {};
    final parsedEndpoints = (json['endpoints'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (e) => AiEndpointConfig.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
    final effectiveEndpoints = parsedEndpoints.isEmpty
        ? AiEndpointPresets.defaults()
        : parsedEndpoints;

    final profiles = (json['profiles'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (e) => StudentProfile.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
    final effectiveProfiles = profiles.isEmpty
        ? const [
            StudentProfile(
              id: 'profile_default',
              name: '新同学',
              stage: StudyStage.middle,
              grade: '九年级',
              subjects: ['math', 'phy', 'eng'],
            ),
          ]
        : profiles;

    return WorkspaceSnapshot(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      profiles: effectiveProfiles,
      activeProfileId:
          json['activeProfileId'] as String? ?? effectiveProfiles.first.id,
      workspaces: rawWorkspaces.map(
        (k, v) => MapEntry(
          k,
          ProfileWorkspaceData.fromJson(
            (v! as Map).map((mk, mv) => MapEntry(mk.toString(), mv)),
          ),
        ),
      ),
      endpoints: effectiveEndpoints,
      activeEndpointId:
          json['activeEndpointId'] as String? ?? effectiveEndpoints.first.id,
      preferences: json['preferences'] is Map
          ? AppPreferences.fromJson(
              (json['preferences']! as Map).map(
                (k, v) => MapEntry(k.toString(), v),
              ),
            )
          : const AppPreferences(),
    );
  }

  final int schemaVersion;
  final List<StudentProfile> profiles;
  final String activeProfileId;
  final Map<String, ProfileWorkspaceData> workspaces;
  final List<AiEndpointConfig> endpoints;
  final String activeEndpointId;
  final AppPreferences preferences;

  StudentProfile get activeProfile => profiles.firstWhere(
    (p) => p.id == activeProfileId,
    orElse: () => profiles.first,
  );

  ProfileWorkspaceData get activeWorkspace =>
      workspaces[activeProfile.id] ?? const ProfileWorkspaceData();

  AiEndpointConfig get activeEndpoint => endpoints.firstWhere(
    (e) => e.id == activeEndpointId,
    orElse: () => endpoints.first,
  );

  WorkspaceSnapshot copyWith({
    List<StudentProfile>? profiles,
    String? activeProfileId,
    Map<String, ProfileWorkspaceData>? workspaces,
    List<AiEndpointConfig>? endpoints,
    String? activeEndpointId,
    AppPreferences? preferences,
  }) {
    return WorkspaceSnapshot(
      schemaVersion: schemaVersion,
      profiles: profiles ?? this.profiles,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      workspaces: workspaces ?? this.workspaces,
      endpoints: endpoints ?? this.endpoints,
      activeEndpointId: activeEndpointId ?? this.activeEndpointId,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'profiles': profiles.map((e) => e.toJson()).toList(growable: false),
    'activeProfileId': activeProfileId,
    'workspaces': workspaces.map((k, v) => MapEntry(k, v.toJson())),
    'endpoints': endpoints.map((e) => e.toJson()).toList(growable: false),
    'activeEndpointId': activeEndpointId,
    'preferences': preferences.toJson(),
  };
}

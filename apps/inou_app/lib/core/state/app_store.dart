import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:inou_ink/render.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../backup/inou_backup_service.dart';
import '../knowledge/kp_tree_repository.dart';
import '../security/secret_and_pin_service.dart';
import '../storage/workspace_storage.dart';
import 'workspace_models.dart';

/// Injectable persistence blob provider (overridable with [InMemoryBlobStorage] in tests).
final blobStorageProvider = Provider<KeyValueBlobStorage>((ref) {
  return createDefaultBlobStorage();
});

/// Optional scripted/mock [LLMClient] override for headless integration tests.
final overrideLlmClientProvider = Provider<LLMClient?>((ref) => null);

/// Pluggable ink region rasterizer (defaults to Skia PNG export; overridable in
/// FakeAsync widget tests).
final inkSnapshotExporterProvider =
    Provider<
      Future<Uint8List?> Function(
        InkPageData page, {
        Rect? cropRect,
        double pixelRatio,
      })
    >((ref) => InkSnapshotExporter.exportRegionPng);

/// Lifecycle state of an asynchronous background capture/ingestion job.
enum CaptureTaskStatus { running, completed, failed }

/// Interactive pen modes available on the AI classroom blackboard.
enum BlackboardPenMode { none, circleAsk, studentChalk, eraser }

/// Non-blocking background ingestion task kept across route/dialog changes so
/// users never lose long Vision/Document OCR runs when closing Capture UI.
@immutable
class CaptureBackgroundTask {
  const CaptureBackgroundTask({
    required this.id,
    required this.subject,
    required this.docTitle,
    required this.stageLabel,
    required this.status,
    required this.createdAtMs,
    this.lockSubject = false,
    this.autoFlagWrong = false,
    this.drafts = const [],
    this.examBytes,
    this.answerBytes,
    this.rawText,
    this.traces = const [],
    this.errorMessage,
  });

  final String id;
  final String subject;
  final String docTitle;
  final String stageLabel;
  final CaptureTaskStatus status;
  final int createdAtMs;
  final bool lockSubject;
  final bool autoFlagWrong;
  final List<CaptureDraftItem> drafts;
  final Uint8List? examBytes;
  final Uint8List? answerBytes;
  final String? rawText;
  final List<TutorToolTraceStep> traces;
  final String? errorMessage;

  CaptureBackgroundTask copyWith({
    String? subject,
    String? docTitle,
    String? stageLabel,
    CaptureTaskStatus? status,
    List<CaptureDraftItem>? drafts,
    List<TutorToolTraceStep>? traces,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CaptureBackgroundTask(
      id: id,
      subject: subject ?? this.subject,
      docTitle: docTitle ?? this.docTitle,
      stageLabel: stageLabel ?? this.stageLabel,
      status: status ?? this.status,
      createdAtMs: createdAtMs,
      lockSubject: lockSubject,
      autoFlagWrong: autoFlagWrong,
      drafts: drafts ?? this.drafts,
      examBytes: examBytes,
      answerBytes: answerBytes,
      rawText: rawText,
      traces: traces ?? this.traces,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Application state exposed by [appStoreProvider].
@immutable
class AppState {
  const AppState({
    required this.snapshot,
    required this.kpTree,
    this.endpointKeys = const {},
    this.connectionReports = const {},
    this.pinConfigured = false,
    this.hydrated = false,
    this.captureBusy = false,
    this.captureStageLabel = '',
    this.captureTraces = const [],
    this.captureExamImageBytes,
    this.captureAnswerImageBytes,
    this.captureErrorMessage,
    this.backgroundTasks = const [],
    this.activeBackgroundTaskId,
    this.coachBusy = false,
    this.activeSessionId,
    this.copilotOpen = false,
    this.copilotQuestionId,
    this.copilotHintLevel = HintLevel.l1Concept,
    this.copilotLassoBytes,
    this.copilotBusy = false,
    this.copilotLastEmotion = MascotEmotion.happy,
    this.copilotStreamingText,
    this.blackboardOpen = false,
    this.blackboardBusy = false,
    this.blackboardStepStreaming = false,
    this.blackboardFeedbackBusy = false,
    this.blackboardPenMode = BlackboardPenMode.none,
    this.blackboardLastTraces = const [],
    this.blackboardAntiSpoilerBlocked = false,
    this.streamingBlackboardLesson,
    this.lastSavedReportId,
    this.photoSearchBusy = false,
    this.photoSearchStageLabel = '',
    this.photoSearchErrorMessage,
    this.photoSearchImageBytes,
    this.activePhotoSearchSessionId,
    this.photoSearchSolvingItemIds = const {},
    this.aiRetryNotice,
    this.aiRetryExhausted = false,
  });

  final WorkspaceSnapshot snapshot;
  final KpTreeRepository kpTree;
  final Map<String, String> endpointKeys;
  final Map<String, ConnectionCheckReport> connectionReports;
  final bool pinConfigured;
  final bool hydrated;

  // Capture workflow transient UI state
  final bool captureBusy;
  final String captureStageLabel;
  final List<TutorToolTraceStep> captureTraces;
  final Uint8List? captureExamImageBytes;
  final Uint8List? captureAnswerImageBytes;
  final String? captureErrorMessage;
  final List<CaptureBackgroundTask> backgroundTasks;
  final String? activeBackgroundTaskId;

  // StudyCoach transient state
  final bool coachBusy;
  final String? lastSavedReportId;

  // Active Practice session
  final String? activeSessionId;

  // Global NuoNuo Copilot drawer state
  final bool copilotOpen;
  final String? copilotQuestionId;
  final HintLevel copilotHintLevel;
  final Uint8List? copilotLassoBytes;
  final bool copilotBusy;
  final MascotEmotion copilotLastEmotion;
  final String? copilotStreamingText;

  // Interactive AI Blackboard classroom state
  final bool blackboardOpen;
  final bool blackboardBusy;
  final bool blackboardStepStreaming;
  final bool blackboardFeedbackBusy;
  final BlackboardPenMode blackboardPenMode;
  final List<String> blackboardLastTraces;
  final bool blackboardAntiSpoilerBlocked;
  final BlackboardLessonRecord? streamingBlackboardLesson;

  // Photo-search transient UI state
  final bool photoSearchBusy;
  final String photoSearchStageLabel;
  final String? photoSearchErrorMessage;
  final Uint8List? photoSearchImageBytes;
  final String? activePhotoSearchSessionId;
  final Set<String> photoSearchSolvingItemIds;

  // Live AI auto-retry / exhaustion banner notice
  final String? aiRetryNotice;
  final bool aiRetryExhausted;

  String get activeBlackboardKey => copilotQuestionId ?? '__free__';

  PhotoSearchSession? get activePhotoSearchSession {
    final sid = activePhotoSearchSessionId;
    if (sid == null) return null;
    for (final s in activeWorkspace.photoSearchHistory) {
      if (s.id == sid) return s;
    }
    return null;
  }

  /// Resolves a question from either the Question Bank or any PhotoSearch session.
  Question? findQuestionById(String? questionId) {
    if (questionId == null || questionId.isEmpty) return null;
    for (final q in activeWorkspace.questions) {
      if (q.id == questionId) return q;
    }
    for (final session in activeWorkspace.photoSearchHistory) {
      for (final item in session.items) {
        if (item.question.id == questionId ||
            item.savedQuestionId == questionId) {
          return item.question;
        }
      }
    }
    return null;
  }

  BlackboardLessonRecord? get activeBlackboardLesson =>
      streamingBlackboardLesson ??
      activeWorkspace.blackboardLessonsByQuestionId[activeBlackboardKey];

  StudentProfile get activeProfile => snapshot.activeProfile;
  ProfileWorkspaceData get activeWorkspace => snapshot.activeWorkspace;
  AiEndpointConfig get activeEndpoint => snapshot.activeEndpoint;
  String get activeApiKey => endpointKeys[activeEndpoint.id] ?? '';
  bool get hasLiveAiKey => activeApiKey.trim().isNotEmpty;

  ThemeMode get themeMode => switch (snapshot.preferences.darkModePreference) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  TutorThreadRecord get activeCopilotThread {
    final qId = copilotQuestionId;
    final scope = qId != null ? 'question' : 'global';
    return activeWorkspace.tutorThreads.firstWhere(
      (t) => t.scope == scope && t.questionId == qId,
      orElse: () => TutorThreadRecord(
        id: qId != null ? 'thread_q_$qId' : 'thread_global',
        scope: scope,
        questionId: qId,
      ),
    );
  }

  PracticeSession? get activeSession {
    final sid = activeSessionId;
    if (sid == null) return null;
    for (final s in activeWorkspace.sessions) {
      if (s.id == sid) return s;
    }
    return null;
  }

  AppState copyWith({
    WorkspaceSnapshot? snapshot,
    KpTreeRepository? kpTree,
    Map<String, String>? endpointKeys,
    Map<String, ConnectionCheckReport>? connectionReports,
    bool? pinConfigured,
    bool? hydrated,
    bool? captureBusy,
    String? captureStageLabel,
    List<TutorToolTraceStep>? captureTraces,
    Uint8List? captureExamImageBytes,
    bool clearCaptureExamImage = false,
    Uint8List? captureAnswerImageBytes,
    bool clearCaptureAnswerImage = false,
    String? captureErrorMessage,
    bool clearCaptureError = false,
    List<CaptureBackgroundTask>? backgroundTasks,
    String? activeBackgroundTaskId,
    bool clearActiveBackgroundTask = false,
    bool? coachBusy,
    String? lastSavedReportId,
    String? activeSessionId,
    bool clearActiveSession = false,
    bool? copilotOpen,
    String? copilotQuestionId,
    bool clearCopilotQuestion = false,
    HintLevel? copilotHintLevel,
    Uint8List? copilotLassoBytes,
    bool clearCopilotLasso = false,
    bool? copilotBusy,
    MascotEmotion? copilotLastEmotion,
    String? copilotStreamingText,
    bool clearCopilotStreamingText = false,
    bool? blackboardOpen,
    bool? blackboardBusy,
    bool? blackboardStepStreaming,
    bool? blackboardFeedbackBusy,
    BlackboardPenMode? blackboardPenMode,
    List<String>? blackboardLastTraces,
    bool? blackboardAntiSpoilerBlocked,
    BlackboardLessonRecord? streamingBlackboardLesson,
    bool clearStreamingBlackboard = false,
    bool? photoSearchBusy,
    String? photoSearchStageLabel,
    String? photoSearchErrorMessage,
    bool clearPhotoSearchError = false,
    Uint8List? photoSearchImageBytes,
    bool clearPhotoSearchImage = false,
    String? activePhotoSearchSessionId,
    bool clearActivePhotoSearchSession = false,
    Set<String>? photoSearchSolvingItemIds,
    String? aiRetryNotice,
    bool clearAiRetryNotice = false,
    bool? aiRetryExhausted,
  }) {
    return AppState(
      snapshot: snapshot ?? this.snapshot,
      kpTree: kpTree ?? this.kpTree,
      endpointKeys: endpointKeys ?? this.endpointKeys,
      connectionReports: connectionReports ?? this.connectionReports,
      pinConfigured: pinConfigured ?? this.pinConfigured,
      hydrated: hydrated ?? this.hydrated,
      captureBusy: captureBusy ?? this.captureBusy,
      captureStageLabel: captureStageLabel ?? this.captureStageLabel,
      captureTraces: captureTraces ?? this.captureTraces,
      captureExamImageBytes: clearCaptureExamImage
          ? null
          : (captureExamImageBytes ?? this.captureExamImageBytes),
      captureAnswerImageBytes: clearCaptureAnswerImage
          ? null
          : (captureAnswerImageBytes ?? this.captureAnswerImageBytes),
      captureErrorMessage: clearCaptureError
          ? null
          : (captureErrorMessage ?? this.captureErrorMessage),
      backgroundTasks: backgroundTasks ?? this.backgroundTasks,
      activeBackgroundTaskId: clearActiveBackgroundTask
          ? null
          : (activeBackgroundTaskId ?? this.activeBackgroundTaskId),
      coachBusy: coachBusy ?? this.coachBusy,
      lastSavedReportId: lastSavedReportId ?? this.lastSavedReportId,
      activeSessionId: clearActiveSession
          ? null
          : (activeSessionId ?? this.activeSessionId),
      copilotOpen: copilotOpen ?? this.copilotOpen,
      copilotQuestionId: clearCopilotQuestion
          ? null
          : (copilotQuestionId ?? this.copilotQuestionId),
      copilotHintLevel: copilotHintLevel ?? this.copilotHintLevel,
      copilotLassoBytes: clearCopilotLasso
          ? null
          : (copilotLassoBytes ?? this.copilotLassoBytes),
      copilotBusy: copilotBusy ?? this.copilotBusy,
      copilotLastEmotion: copilotLastEmotion ?? this.copilotLastEmotion,
      copilotStreamingText: clearCopilotStreamingText
          ? null
          : (copilotStreamingText ?? this.copilotStreamingText),
      blackboardOpen: blackboardOpen ?? this.blackboardOpen,
      blackboardBusy: blackboardBusy ?? this.blackboardBusy,
      blackboardStepStreaming:
          blackboardStepStreaming ?? this.blackboardStepStreaming,
      blackboardFeedbackBusy:
          blackboardFeedbackBusy ?? this.blackboardFeedbackBusy,
      blackboardPenMode: blackboardPenMode ?? this.blackboardPenMode,
      blackboardLastTraces: blackboardLastTraces ?? this.blackboardLastTraces,
      blackboardAntiSpoilerBlocked:
          blackboardAntiSpoilerBlocked ?? this.blackboardAntiSpoilerBlocked,
      streamingBlackboardLesson: clearStreamingBlackboard
          ? null
          : (streamingBlackboardLesson ?? this.streamingBlackboardLesson),
      photoSearchBusy: photoSearchBusy ?? this.photoSearchBusy,
      photoSearchStageLabel:
          photoSearchStageLabel ?? this.photoSearchStageLabel,
      photoSearchErrorMessage: clearPhotoSearchError
          ? null
          : (photoSearchErrorMessage ?? this.photoSearchErrorMessage),
      photoSearchImageBytes: clearPhotoSearchImage
          ? null
          : (photoSearchImageBytes ?? this.photoSearchImageBytes),
      activePhotoSearchSessionId: clearActivePhotoSearchSession
          ? null
          : (activePhotoSearchSessionId ?? this.activePhotoSearchSessionId),
      photoSearchSolvingItemIds:
          photoSearchSolvingItemIds ?? this.photoSearchSolvingItemIds,
      aiRetryNotice: clearAiRetryNotice
          ? null
          : (aiRetryNotice ?? this.aiRetryNotice),
      aiRetryExhausted: aiRetryExhausted ?? this.aiRetryExhausted,
    );
  }
}

final appStoreProvider = NotifierProvider<AppStoreNotifier, AppState>(
  AppStoreNotifier.new,
);

/// Main reactive application orchestrator persisting workspaces locally and
/// coordinating `inou_domain`, `inou_ai`, and `inou_ink`.
class AppStoreNotifier extends Notifier<AppState> {
  static const String _workspaceBlobKey = 'inou_workspace_snapshot_v1';
  static const Uuid _uuid = Uuid();

  final GradingEngine _gradingEngine = const GradingEngine();
  final MasteryService _masteryService = const MasteryService();
  final WeaknessAnalyzer _weaknessAnalyzer = const WeaknessAnalyzer();
  final TutorAgentService _tutorService = const TutorAgentService();
  final StudyCoachAgentService _coachService = const StudyCoachAgentService();
  final IngestionPipeline _ingestionPipeline = const IngestionPipeline();
  final PhotoSearchService _photoSearchService = const PhotoSearchService();
  final InouConnectionService _connectionService =
      const InouConnectionService();
  final InouBackupService _backupService = const InouBackupService();

  late KeyValueBlobStorage _storage;
  final Map<String, CancelToken> _cancelTokens = {};
  StreamSubscription<AiRetryEvent>? _aiRetrySub;
  Timer? _aiRetryDismissTimer;
  int _blackboardGenSeq = 0;
  static const String _blackboardCancelKey = '__blackboard_plan__';
  static const String _blackboardPrefetchCancelKey = '__blackboard_prefetch__';
  static const String _photoSearchCancelKey = '__photo_search__';
  int? _prefetchingStepNumber;
  int? _awaitingStepNumber;
  ParsedBlackboardStep? _prefetchLatestPartial;
  String? _blackboardDraftText;
  bool _blackboardIsPostMortem = false;
  Uint8List? _blackboardInitialLasso;
  SecretKeyStore get _secretStore => SecretKeyStore(_storage);
  ParentPinService get _pinService => ParentPinService(_storage);

  void _cancelBlackboardStreams({String reason = 'superseded'}) {
    _blackboardGenSeq++;
    for (final k in const [_blackboardCancelKey, _blackboardPrefetchCancelKey]) {
      final token = _cancelTokens.remove(k);
      if (token != null && !token.isCancelled) {
        token.cancel(reason);
      }
    }
    _prefetchingStepNumber = null;
    _awaitingStepNumber = null;
    _prefetchLatestPartial = null;
  }

  @override
  AppState build() {
    _storage = ref.read(blobStorageProvider);
    unawaited(_aiRetrySub?.cancel());
    _aiRetrySub = AiRetryEventBus.instance.stream.listen(_onAiRetryEvent);
    ref.onDispose(() {
      _aiRetryDismissTimer?.cancel();
      _aiRetryDismissTimer = null;
      unawaited(_aiRetrySub?.cancel());
      _aiRetrySub = null;
      _cancelBlackboardStreams(reason: 'disposed');
      for (final token in _cancelTokens.values) {
        if (!token.isCancelled) token.cancel('disposed');
      }
      _cancelTokens.clear();
    });
    unawaited(hydrate());
    return AppState(
      snapshot: WorkspaceSnapshot.clean(),
      kpTree: KpTreeRepository(),
    );
  }

  void _onAiRetryEvent(AiRetryEvent ev) {
    if (!ref.mounted) return;
    _aiRetryDismissTimer?.cancel();
    _aiRetryDismissTimer = null;
    if (ev.recovered) {
      if (state.aiRetryNotice != null || state.aiRetryExhausted) {
        state = state.copyWith(
          clearAiRetryNotice: true,
          aiRetryExhausted: false,
        );
      }
      return;
    }
    state = state.copyWith(
      aiRetryNotice: ev.statusMessage,
      aiRetryExhausted: ev.exhausted,
    );
    if (ev.exhausted) {
      _aiRetryDismissTimer = Timer(const Duration(seconds: 6), () {
        if (!ref.mounted) return;
        state = state.copyWith(
          clearAiRetryNotice: true,
          aiRetryExhausted: false,
        );
      });
    }
  }

  void dismissAiRetryNotice() {
    _aiRetryDismissTimer?.cancel();
    _aiRetryDismissTimer = null;
    state = state.copyWith(
      clearAiRetryNotice: true,
      aiRetryExhausted: false,
    );
  }

  Future<void> hydrate() async {
    final kpRepo = await KpTreeRepository.loadFromAsset();
    if (!ref.mounted) return;
    final keys = await _secretStore.loadAllKeys();
    if (!ref.mounted) return;
    final pinConfigured = await _pinService.hasPinConfigured();
    if (!ref.mounted) return;
    WorkspaceSnapshot snapshot = state.snapshot;
    final rawSnapshot = await _storage.readString(_workspaceBlobKey);
    if (!ref.mounted) return;
    if (rawSnapshot != null && rawSnapshot.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSnapshot);
        if (decoded is Map) {
          snapshot = WorkspaceSnapshot.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (e, st) {
        InouDiagnosticsLogger.instance.warn(
          'app.store',
          'Corrupted workspace snapshot JSON ignored during hydrate',
          error: e,
          stackTrace: st,
        );
        // Keep clean initial snapshot if persisted JSON was corrupted.
      }
    }
    state = state.copyWith(
      snapshot: snapshot,
      kpTree: kpRepo,
      endpointKeys: keys,
      pinConfigured: pinConfigured,
      hydrated: true,
    );
  }

  Future<void> _commitSnapshot(WorkspaceSnapshot next) async {
    state = state.copyWith(snapshot: next);
    await _storage.writeString(_workspaceBlobKey, jsonEncode(next.toJson()));
  }

  Future<void> _updateActiveWorkspace(
    ProfileWorkspaceData Function(ProfileWorkspaceData current) transform,
  ) async {
    final pid = state.snapshot.activeProfile.id;
    final updatedWs = transform(state.snapshot.activeWorkspace);
    final nextMap = Map<String, ProfileWorkspaceData>.from(
      state.snapshot.workspaces,
    )..[pid] = updatedWs;
    await _commitSnapshot(state.snapshot.copyWith(workspaces: nextMap));
  }

  // ---------------------------------------------------------------------------
  // Profiles & Onboarding
  // ---------------------------------------------------------------------------

  Future<void> switchProfile(String profileId) async {
    if (!state.snapshot.profiles.any((p) => p.id == profileId)) return;
    _cancelBlackboardStreams(reason: 'profile_switched');
    cancelPhotoSearch();
    await _commitSnapshot(state.snapshot.copyWith(activeProfileId: profileId));
    state = state.copyWith(
      clearActiveSession: true,
      clearCopilotQuestion: true,
      clearCopilotLasso: true,
      blackboardOpen: false,
      blackboardBusy: false,
      blackboardStepStreaming: false,
      clearStreamingBlackboard: true,
      photoSearchBusy: false,
      photoSearchStageLabel: '',
      clearPhotoSearchError: true,
      clearPhotoSearchImage: true,
      clearActivePhotoSearchSession: true,
      photoSearchSolvingItemIds: const {},
    );
  }

  Future<void> addProfile({
    required String name,
    required StudyStage stage,
    required String grade,
    List<String> subjects = const ['math', 'phy', 'eng'],
  }) async {
    final id = 'profile_${_uuid.v4().substring(0, 8)}';
    final profile = StudentProfile(
      id: id,
      name: name.trim().isEmpty ? '新同学' : name.trim(),
      stage: stage,
      grade: grade,
      subjects: subjects,
    );
    final nextWorkspaces = Map<String, ProfileWorkspaceData>.from(
      state.snapshot.workspaces,
    )..[id] = const ProfileWorkspaceData();
    await _commitSnapshot(
      state.snapshot.copyWith(
        profiles: [...state.snapshot.profiles, profile],
        activeProfileId: id,
        workspaces: nextWorkspaces,
      ),
    );
  }

  Future<void> completeOnboarding({
    required bool consentAccepted,
    required StudentProfile? updatedProfile,
    AiEndpointConfig? endpoint,
    String? apiKey,
  }) async {
    var next = state.snapshot;
    if (updatedProfile != null) {
      final profiles = next.profiles
          .map((p) => p.id == updatedProfile.id ? updatedProfile : p)
          .toList(growable: false);
      next = next.copyWith(profiles: profiles);
    }
    if (endpoint != null) {
      next = _upsertEndpointInSnapshot(next, endpoint, makeActive: true);
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        await saveEndpointApiKey(endpoint.id, apiKey);
      }
    }
    next = next.copyWith(
      preferences: next.preferences.copyWith(
        onboardingCompleted: true,
        consentAccepted: consentAccepted,
      ),
    );
    await _commitSnapshot(next);
  }

  Future<void> clearActiveWorkspace() async {
    cancelPhotoSearch();
    await _updateActiveWorkspace((_) => const ProfileWorkspaceData());
    state = state.copyWith(
      clearActiveSession: true,
      clearCopilotQuestion: true,
      clearCopilotLasso: true,
      blackboardOpen: false,
      clearCaptureExamImage: true,
      clearCaptureAnswerImage: true,
      clearCaptureError: true,
      photoSearchBusy: false,
      photoSearchStageLabel: '',
      clearPhotoSearchError: true,
      clearPhotoSearchImage: true,
      clearActivePhotoSearchSession: true,
      photoSearchSolvingItemIds: const {},
    );
  }

  Future<void> reopenOnboarding() async {
    await updatePreferences(
      state.snapshot.preferences.copyWith(onboardingCompleted: false),
    );
  }

  // ---------------------------------------------------------------------------
  // AI Endpoints & BYOK Connection Testing
  // ---------------------------------------------------------------------------

  WorkspaceSnapshot _upsertEndpointInSnapshot(
    WorkspaceSnapshot snap,
    AiEndpointConfig endpoint, {
    bool makeActive = false,
  }) {
    final exists = snap.endpoints.any((e) => e.id == endpoint.id);
    final list = exists
        ? snap.endpoints
              .map((e) => e.id == endpoint.id ? endpoint : e)
              .toList(growable: false)
        : [...snap.endpoints, endpoint];
    return snap.copyWith(
      endpoints: list,
      activeEndpointId: makeActive ? endpoint.id : snap.activeEndpointId,
    );
  }

  Future<void> upsertEndpoint(
    AiEndpointConfig endpoint, {
    bool makeActive = true,
  }) async {
    final next = _upsertEndpointInSnapshot(
      state.snapshot,
      endpoint,
      makeActive: makeActive,
    );
    await _commitSnapshot(next);
  }

  Future<void> setActiveEndpoint(String endpointId) async {
    if (!state.snapshot.endpoints.any((e) => e.id == endpointId)) return;
    await _commitSnapshot(
      state.snapshot.copyWith(activeEndpointId: endpointId),
    );
  }

  Future<void> deleteEndpoint(String endpointId) async {
    if (state.snapshot.endpoints.length <= 1) return;
    final list = state.snapshot.endpoints
        .where((e) => e.id != endpointId)
        .toList(growable: false);
    final nextActive = state.snapshot.activeEndpointId == endpointId
        ? list.first.id
        : state.snapshot.activeEndpointId;
    await saveEndpointApiKey(endpointId, '');
    await _commitSnapshot(
      state.snapshot.copyWith(endpoints: list, activeEndpointId: nextActive),
    );
  }

  Future<void> saveEndpointApiKey(String endpointId, String apiKey) async {
    await _secretStore.saveKey(endpointId, apiKey);
    final nextKeys = Map<String, String>.from(state.endpointKeys);
    if (apiKey.trim().isEmpty) {
      nextKeys.remove(endpointId);
    } else {
      nextKeys[endpointId] = apiKey.trim();
    }
    state = state.copyWith(endpointKeys: nextKeys);
  }

  Future<ConnectionCheckReport> testEndpointConnection(
    AiEndpointConfig endpoint, {
    required String apiKey,
    bool verifyVision = false,
  }) async {
    final report = await _connectionService.testConnection(
      endpoint,
      apiKey: apiKey,
      verifyVision: verifyVision,
      overrideClient: ref.read(overrideLlmClientProvider),
    );
    final nextReports = Map<String, ConnectionCheckReport>.from(
      state.connectionReports,
    )..[endpoint.id] = report;
    state = state.copyWith(connectionReports: nextReports);
    return report;
  }

  // ---------------------------------------------------------------------------
  // Two-Stage Capture & Proofread
  // ---------------------------------------------------------------------------

  Future<IngestionBatchResult> importRawTextCapture(
    String rawText, {
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
  }) async {
    state = state.copyWith(
      captureBusy: true,
      captureStageLabel: '正在解析文本与识别学科…',
      captureTraces: const [],
      clearCaptureExamImage: true,
      clearCaptureAnswerImage: true,
      clearCaptureError: true,
    );
    final res = await _ingestionPipeline.importFromRawText(
      rawText: rawText,
      profile: state.activeProfile,
      subject: subject,
      lockSubject: lockSubject,
      existingQuestions: state.activeWorkspace.questions,
      endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
      apiKey: state.activeApiKey,
      overrideClient: ref.read(overrideLlmClientProvider),
      onProgress: (stage, note) {
        state = state.copyWith(captureStageLabel: '${stage.label} · $note');
      },
    );
    await _updateActiveWorkspace(
      (ws) => ws.copyWith(
        captureDrafts: res.drafts,
        captureDocTitle: res.suggestedDocTitle,
      ),
    );
    state = state.copyWith(
      captureBusy: false,
      captureStageLabel: '',
      captureTraces: res.traceSteps,
    );
    return res;
  }

  Future<IngestionBatchResult> ingestImageBytes({
    required Uint8List examBytes,
    Uint8List? answerBytes,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    String docTitle = '拍照试卷',
    bool autoFlagWrong = false,
  }) async {
    state = state.copyWith(
      captureBusy: true,
      captureStageLabel: CaptureStage.layoutAnalysis.label,
      captureTraces: const [],
      captureExamImageBytes: examBytes,
      captureAnswerImageBytes: answerBytes,
      clearCaptureAnswerImage: answerBytes == null,
      clearCaptureError: true,
    );
    final res = await _ingestionPipeline.ingestPage(
      profile: state.activeProfile,
      examImageBytes: examBytes,
      answerImageBytes: answerBytes,
      subject: subject,
      lockSubject: lockSubject,
      docTitleHint: docTitle,
      existingQuestions: state.activeWorkspace.questions,
      endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
      apiKey: state.activeApiKey,
      overrideClient: ref.read(overrideLlmClientProvider),
      onProgress: (stage, note) {
        state = state.copyWith(captureStageLabel: '${stage.label} · $note');
      },
    );
    if (res.ok && res.drafts.isNotEmpty) {
      final finalDrafts = autoFlagWrong
          ? res.drafts
                .map(
                  (d) => d.copyWith(
                    flaggedWrong: true,
                    teacherMark: d.teacherMark == 'none'
                        ? 'wrong'
                        : d.teacherMark,
                  ),
                )
                .toList(growable: false)
          : res.drafts;
      await _updateActiveWorkspace(
        (ws) => ws.copyWith(
          captureDrafts: finalDrafts,
          captureDocTitle: res.suggestedDocTitle,
        ),
      );
    }
    state = state.copyWith(
      captureBusy: false,
      captureStageLabel: '',
      captureTraces: res.traceSteps,
      captureErrorMessage: res.errorMessage,
      clearCaptureError: res.ok,
    );
    return res;
  }

  // ---------------------------------------------------------------------------
  // Non-Blocking Background Capture Task Queue
  // ---------------------------------------------------------------------------

  String enqueueBackgroundImageTask({
    required Uint8List examBytes,
    Uint8List? answerBytes,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    String docTitle = '拍照试卷',
    bool autoFlagWrong = false,
  }) {
    final taskId = 'task_${_uuid.v4().substring(0, 8)}';
    final task = CaptureBackgroundTask(
      id: taskId,
      subject: subject,
      docTitle: docTitle,
      stageLabel: CaptureStage.layoutAnalysis.label,
      status: CaptureTaskStatus.running,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      lockSubject: lockSubject,
      autoFlagWrong: autoFlagWrong,
      examBytes: examBytes,
      answerBytes: answerBytes,
    );
    state = state.copyWith(backgroundTasks: [task, ...state.backgroundTasks]);
    unawaited(_executeBackgroundImageTask(task));
    return taskId;
  }

  String enqueueBackgroundTextTask({
    required String rawText,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
    String docTitle = '文档导入解析',
  }) {
    final taskId = 'task_${_uuid.v4().substring(0, 8)}';
    final task = CaptureBackgroundTask(
      id: taskId,
      subject: subject,
      docTitle: docTitle,
      stageLabel: CaptureStage.questionStructuring.label,
      status: CaptureTaskStatus.running,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      lockSubject: lockSubject,
      rawText: rawText,
    );
    state = state.copyWith(backgroundTasks: [task, ...state.backgroundTasks]);
    unawaited(_executeBackgroundTextTask(task));
    return taskId;
  }

  void _updateBackgroundTask(
    String taskId,
    CaptureBackgroundTask Function(CaptureBackgroundTask current) transform,
  ) {
    if (!ref.mounted) return;
    final list = state.backgroundTasks
        .map((t) => t.id == taskId ? transform(t) : t)
        .toList(growable: false);
    state = state.copyWith(backgroundTasks: list);
  }

  Future<void> _executeBackgroundImageTask(CaptureBackgroundTask task) async {
    final token = CancelToken();
    _cancelTokens[task.id] = token;
    try {
      final res = await _ingestionPipeline.ingestPage(
        profile: state.activeProfile,
        examImageBytes: task.examBytes,
        answerImageBytes: task.answerBytes,
        subject: task.subject,
        lockSubject: task.lockSubject,
        docTitleHint: task.docTitle,
        existingQuestions: state.activeWorkspace.questions,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
        cancelToken: token,
        onProgress: (stage, note) {
          _updateBackgroundTask(
            task.id,
            (cur) => cur.copyWith(stageLabel: '${stage.label} · $note'),
          );
        },
      );
      if (!ref.mounted || token.isCancelled) return;
      if (res.ok && res.drafts.isNotEmpty) {
        final finalDrafts = task.autoFlagWrong
            ? res.drafts
                  .map(
                    (d) => d.copyWith(
                      flaggedWrong: true,
                      teacherMark: d.teacherMark == 'none'
                          ? 'wrong'
                          : d.teacherMark,
                    ),
                  )
                  .toList(growable: false)
            : res.drafts;
        _updateBackgroundTask(
          task.id,
          (cur) => cur.copyWith(
            subject: res.subject,
            docTitle: res.suggestedDocTitle,
            stageLabel:
                '${SubjectCatalog.labelOf(res.subject)} · 已识别 ${finalDrafts.length} 题',
            status: CaptureTaskStatus.completed,
            drafts: finalDrafts,
            traces: res.traceSteps,
            clearError: true,
          ),
        );
      } else {
        final msg = res.errorMessage ?? '未识别到有效题目，请重试';
        InouDiagnosticsLogger.instance.error(
          'app.store',
          '后台识题失败（${task.docTitle}）：$msg',
        );
        _updateBackgroundTask(
          task.id,
          (cur) => cur.copyWith(
            stageLabel: '识题失败',
            status: CaptureTaskStatus.failed,
            traces: res.traceSteps,
            errorMessage: msg,
          ),
        );
      }
    } catch (e, st) {
      if (!ref.mounted || token.isCancelled) return;
      InouDiagnosticsLogger.instance.error(
        'app.store',
        '后台识题异常（${task.docTitle}）',
        error: e,
        stackTrace: st,
      );
      _updateBackgroundTask(
        task.id,
        (cur) => cur.copyWith(
          stageLabel: '识题失败',
          status: CaptureTaskStatus.failed,
          errorMessage: AiUserErrorMessages.captureFailedFallback(),
        ),
      );
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  Future<void> _executeBackgroundTextTask(CaptureBackgroundTask task) async {
    final token = CancelToken();
    _cancelTokens[task.id] = token;
    try {
      final res = await _ingestionPipeline.importFromRawText(
        rawText: task.rawText ?? '',
        profile: state.activeProfile,
        subject: task.subject,
        lockSubject: task.lockSubject,
        existingQuestions: state.activeWorkspace.questions,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
        cancelToken: token,
        onProgress: (stage, note) {
          _updateBackgroundTask(
            task.id,
            (cur) => cur.copyWith(stageLabel: '${stage.label} · $note'),
          );
        },
      );
      if (!ref.mounted || token.isCancelled) return;
      if (res.drafts.isNotEmpty) {
        _updateBackgroundTask(
          task.id,
          (cur) => cur.copyWith(
            subject: res.subject,
            docTitle: res.suggestedDocTitle,
            stageLabel:
                '${SubjectCatalog.labelOf(res.subject)} · 已解析 ${res.drafts.length} 题',
            status: CaptureTaskStatus.completed,
            drafts: res.drafts,
            traces: res.traceSteps,
            clearError: true,
          ),
        );
      } else {
        InouDiagnosticsLogger.instance.warn(
          'app.store',
          '后台文本解析未提取到题目（${task.docTitle}）',
        );
        _updateBackgroundTask(
          task.id,
          (cur) => cur.copyWith(
            stageLabel: '解析失败',
            status: CaptureTaskStatus.failed,
            errorMessage: '未能从文本/文档中提取题目',
          ),
        );
      }
    } catch (e, st) {
      if (!ref.mounted || token.isCancelled) return;
      InouDiagnosticsLogger.instance.error(
        'app.store',
        '文档解析失败（${task.docTitle}）',
        error: e,
        stackTrace: st,
      );
      _updateBackgroundTask(
        task.id,
        (cur) => cur.copyWith(
          stageLabel: '解析失败',
          status: CaptureTaskStatus.failed,
          errorMessage: AiUserErrorMessages.captureFailedFallback(),
        ),
      );
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  Future<void> openBackgroundTaskForReview(String taskId) async {
    final task = state.backgroundTasks
        .where((t) => t.id == taskId && t.status == CaptureTaskStatus.completed)
        .firstOrNull;
    if (task == null) return;
    await _updateActiveWorkspace(
      (ws) => ws.copyWith(
        captureDrafts: task.drafts,
        captureDocTitle: task.docTitle,
      ),
    );
    state = state.copyWith(
      captureExamImageBytes: task.examBytes,
      clearCaptureExamImage: task.examBytes == null,
      captureAnswerImageBytes: task.answerBytes,
      clearCaptureAnswerImage: task.answerBytes == null,
      captureTraces: task.traces,
      activeBackgroundTaskId: task.id,
      clearCaptureError: true,
    );
  }

  void cancelBackgroundTask(String taskId) {
    final token = _cancelTokens.remove(taskId);
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancelled');
    }
    dismissBackgroundTask(taskId);
  }

  void retryBackgroundTask(String taskId) {
    final task = state.backgroundTasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    dismissBackgroundTask(taskId);
    if (task.examBytes != null) {
      enqueueBackgroundImageTask(
        examBytes: task.examBytes!,
        answerBytes: task.answerBytes,
        subject: task.subject,
        lockSubject: task.lockSubject,
        docTitle: task.docTitle,
        autoFlagWrong: task.autoFlagWrong,
      );
    } else if ((task.rawText ?? '').isNotEmpty) {
      enqueueBackgroundTextTask(
        rawText: task.rawText!,
        subject: task.subject,
        lockSubject: task.lockSubject,
        docTitle: task.docTitle,
      );
    }
  }

  void dismissBackgroundTask(String taskId) {
    final next = state.backgroundTasks
        .where((t) => t.id != taskId)
        .toList(growable: false);
    state = state.copyWith(
      backgroundTasks: next,
      clearActiveBackgroundTask: state.activeBackgroundTaskId == taskId,
    );
  }

  Future<void> updateCaptureDraft(CaptureDraftItem updated) async {
    await _updateActiveWorkspace((ws) {
      final list = ws.captureDrafts
          .map((d) => d.id == updated.id ? updated : d)
          .toList(growable: false);
      return ws.copyWith(captureDrafts: list);
    });
  }

  Future<void> deleteCaptureDraft(String draftId) async {
    await _updateActiveWorkspace((ws) {
      final list = ws.captureDrafts
          .where((d) => d.id != draftId)
          .toList(growable: false);
      return ws.copyWith(captureDrafts: list);
    });
  }

  Future<void> clearCaptureDrafts() async {
    await _updateActiveWorkspace(
      (ws) => ws.copyWith(captureDrafts: const [], captureDocTitle: ''),
    );
    state = state.copyWith(
      clearCaptureExamImage: true,
      clearCaptureAnswerImage: true,
      clearCaptureError: true,
      backgroundTasks: state.activeBackgroundTaskId == null
          ? state.backgroundTasks
          : state.backgroundTasks
                .where((t) => t.id != state.activeBackgroundTaskId)
                .toList(growable: false),
      clearActiveBackgroundTask: true,
    );
  }

  /// Commits all non-skipped confirmed drafts into Question Bank + SourceDoc
  /// + WrongBook (when flaggedWrong). Returns `(importedCount, wrongCount)`.
  Future<({int importedCount, int wrongCount, String? docId})>
  commitCaptureDrafts({String? customDocTitle}) async {
    final ws = state.activeWorkspace;
    final toCommit = ws.captureDrafts
        .where((d) => d.confirmed && !d.skipDuplicate)
        .toList();
    if (toCommit.isEmpty) {
      await clearCaptureDrafts();
      return (importedCount: 0, wrongCount: 0, docId: null);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final docId = 'doc_${_uuid.v4().substring(0, 8)}';
    final docTitle = (customDocTitle ?? '').trim().isNotEmpty
        ? customDocTitle!.trim()
        : (ws.captureDocTitle.isNotEmpty ? ws.captureDocTitle : '拍照校对入库卷');
    final firstSubject = toCommit.first.question.meta.subject;

    String? savedImagePath;
    if (state.captureExamImageBytes != null) {
      savedImagePath = 'captures/$docId.jpg';
      await _storage.writeBinary(savedImagePath, state.captureExamImageBytes!);
    }

    final newDoc = SourceDoc(
      id: docId,
      title: docTitle,
      docType: 'paper',
      subject: firstSubject,
      grade: toCommit.first.question.meta.grade,
      pageCount: 1,
      localImagePath: savedImagePath,
      createdAtMs: now,
    );

    final newQuestions = <Question>[];
    final newWrongs = List<WrongItem>.from(ws.wrongItems);
    var addedWrongCount = 0;

    for (final d in toCommit) {
      final q = d.question.copyWith(
        id: 'q_${_uuid.v4().substring(0, 8)}',
        docId: docId,
        createdAtMs: now,
        updatedAtMs: now,
      );
      newQuestions.add(q);

      if (d.flaggedWrong) {
        addedWrongCount++;
        newWrongs.insert(
          0,
          WrongItem(
            id: 'w_${_uuid.v4().substring(0, 8)}',
            questionId: q.id,
            addedVia: AddedVia.photoMarked,
            mastery: MasteryState.newWrong,
            correctStreak: 0,
            wrongCount: 1,
            attemptCount: 1,
            errorTags: d.errorTags.isNotEmpty
                ? d.errorTags
                : const [ErrorTag.calc],
            myWrongAnswer: d.studentAnswerSnippet ?? '卷面批改错题',
            teacherMark: d.teacherMark == 'none' ? 'wrong' : d.teacherMark,
            addedAtMs: now,
          ),
        );
      }
    }

    await _updateActiveWorkspace(
      (cur) => cur.copyWith(
        sourceDocs: [newDoc, ...cur.sourceDocs],
        questions: [...newQuestions, ...cur.questions],
        wrongItems: newWrongs,
        captureDrafts: const [],
        captureDocTitle: '',
      ),
    );
    state = state.copyWith(
      clearCaptureExamImage: true,
      clearCaptureAnswerImage: true,
      clearCaptureError: true,
      backgroundTasks: state.activeBackgroundTaskId == null
          ? state.backgroundTasks
          : state.backgroundTasks
                .where((t) => t.id != state.activeBackgroundTaskId)
                .toList(growable: false),
      clearActiveBackgroundTask: true,
    );
    return (
      importedCount: newQuestions.length,
      wrongCount: addedWrongCount,
      docId: docId,
    );
  }

  Future<Uint8List?> readDocImageBytes(String? relPath) {
    if (relPath == null || relPath.trim().isEmpty) return Future.value(null);
    return _storage.readBinary(relPath);
  }

  // ---------------------------------------------------------------------------
  // Photo Search & AI Independent Solve (Answer-Free Questions / Papers)
  // ---------------------------------------------------------------------------

  Future<PhotoSearchResult> runPhotoSearch({
    required Uint8List imageBytes,
    String subject = SubjectCatalog.autoCode,
    bool lockSubject = false,
  }) async {
    final prev = _cancelTokens.remove(_photoSearchCancelKey);
    if (prev != null && !prev.isCancelled) {
      prev.cancel('superseded');
    }
    final cancelToken = CancelToken();
    _cancelTokens[_photoSearchCancelKey] = cancelToken;

    final sessionId = 'pss_${_uuid.v4().substring(0, 8)}';
    final imagePath = 'photo_search/$sessionId.jpg';
    var sessionInserted = false;
    var pendingUpdateChain = Future<void>.value();

    Future<void> serializeUpdate(Future<void> Function() task) {
      pendingUpdateChain = pendingUpdateChain.then((_) => task());
      return pendingUpdateChain;
    }

    state = state.copyWith(
      photoSearchBusy: true,
      photoSearchImageBytes: imageBytes,
      photoSearchStageLabel: PhotoSearchStage.layoutAndOcr.label,
      photoSearchSolvingItemIds: const {},
      clearPhotoSearchError: true,
      clearActivePhotoSearchSession: true,
    );

    try {
      final res = await _photoSearchService.searchAndSolveImage(
        profile: state.activeProfile,
        imageBytes: imageBytes,
        subject: subject,
        lockSubject: lockSubject,
        existingQuestions: state.activeWorkspace.questions,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
        cancelToken: cancelToken,
        onProgress: (stage, note) {
          if (!ref.mounted || cancelToken.isCancelled) return;
          state = state.copyWith(photoSearchStageLabel: '${stage.label} · $note');
        },
        onItemsExtracted:
            (initialItems, {required suggestedTitle, required subject}) {
              if (!ref.mounted || cancelToken.isCancelled) return;
              final enrichedInitial = initialItems
                  .map(_attachMatchedKpIds)
                  .toList(growable: false);
              final solvingIds = enrichedInitial.map((it) => it.id).toSet();
              final previewSession = PhotoSearchSession(
                id: sessionId,
                title: suggestedTitle,
                subject: subject,
                localImagePath: imagePath,
                items: enrichedInitial,
                traces: const [],
                createdAtMs: DateTime.now().millisecondsSinceEpoch,
              );
              sessionInserted = true;
              state = state.copyWith(
                photoSearchBusy: false,
                photoSearchStageLabel: '',
                activePhotoSearchSessionId: sessionId,
                photoSearchSolvingItemIds: solvingIds,
                clearPhotoSearchError: true,
              );
              unawaited(
                serializeUpdate(() async {
                  if (!ref.mounted || cancelToken.isCancelled) return;
                  await _storage.writeBinary(imagePath, imageBytes);
                  if (!ref.mounted || cancelToken.isCancelled) return;
                  await _updateActiveWorkspace(
                    (ws) => ws.copyWith(
                      photoSearchHistory: [
                        previewSession,
                        ...ws.photoSearchHistory.where(
                          (s) => s.id != sessionId,
                        ),
                      ].take(30).toList(growable: false),
                    ),
                  );
                }),
              );
            },
        onItemSolved:
            (solvedItem, {required completedCount, required totalCount}) {
              if (!ref.mounted || cancelToken.isCancelled) return;
              final enriched = _attachMatchedKpIds(solvedItem);
              final nextSolving = Set<String>.from(
                state.photoSearchSolvingItemIds,
              )..remove(enriched.id);
              state = state.copyWith(photoSearchSolvingItemIds: nextSolving);
              unawaited(
                serializeUpdate(() async {
                  if (!ref.mounted || cancelToken.isCancelled) return;
                  await updatePhotoSearchItem(sessionId, enriched);
                }),
              );
            },
      );
      await pendingUpdateChain;
      if (!ref.mounted || cancelToken.isCancelled) {
        return res;
      }

      if (res.ok && res.items.isNotEmpty) {
        if (!sessionInserted) {
          await _storage.writeBinary(imagePath, imageBytes);
          if (!ref.mounted) return res;
        }

        final enrichedItems = res.items
            .map(_attachMatchedKpIds)
            .toList(growable: false);
        final session = PhotoSearchSession(
          id: sessionId,
          title: res.suggestedTitle,
          subject: res.subject,
          localImagePath: imagePath,
          items: enrichedItems,
          traces: res.traceSteps
              .map((t) => t.toDisplayLine())
              .toList(growable: false),
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _updateActiveWorkspace(
          (ws) => ws.copyWith(
            photoSearchHistory: [
              session,
              ...ws.photoSearchHistory.where((s) => s.id != sessionId),
            ].take(30).toList(growable: false),
          ),
        );
        if (!ref.mounted) return res;
        state = state.copyWith(
          photoSearchBusy: false,
          photoSearchStageLabel: '',
          activePhotoSearchSessionId: sessionId,
          photoSearchSolvingItemIds: const {},
          clearPhotoSearchError: true,
        );
        return PhotoSearchResult(
          items: enrichedItems,
          suggestedTitle: res.suggestedTitle,
          subject: res.subject,
          traceSteps: res.traceSteps,
        );
      }

      final errMsg = res.errorMessage ?? '未能从图片中识别到题目，请重试';
      InouDiagnosticsLogger.instance.warn(
        'app.photo_search',
        'Photo search finished without items: $errMsg',
      );
      state = state.copyWith(
        photoSearchBusy: false,
        photoSearchStageLabel: '',
        photoSearchSolvingItemIds: const {},
        photoSearchErrorMessage: errMsg,
      );
      return res;
    } catch (e, st) {
      if (!ref.mounted || cancelToken.isCancelled) {
        return const PhotoSearchResult(
          items: [],
          suggestedTitle: '拍照搜题',
          subject: 'other',
          traceSteps: [],
          errorMessage: '已取消拍照搜题',
        );
      }
      InouDiagnosticsLogger.instance.error(
        'app.photo_search',
        'Photo search exception',
        error: e,
        stackTrace: st,
      );
      final err = AiUserErrorMessages.photoSearchFailedFallback();
      state = state.copyWith(
        photoSearchBusy: false,
        photoSearchStageLabel: '',
        photoSearchSolvingItemIds: const {},
        photoSearchErrorMessage: err,
      );
      return PhotoSearchResult(
        items: const [],
        suggestedTitle: '拍照搜题',
        subject: subject,
        traceSteps: const [],
        errorMessage: err,
      );
    } finally {
      if (identical(_cancelTokens[_photoSearchCancelKey], cancelToken)) {
        _cancelTokens.remove(_photoSearchCancelKey);
      }
    }
  }

  void cancelPhotoSearch() {
    final token = _cancelTokens.remove(_photoSearchCancelKey);
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancelled');
    }
    if (state.photoSearchBusy || state.photoSearchSolvingItemIds.isNotEmpty) {
      state = state.copyWith(
        photoSearchBusy: false,
        photoSearchStageLabel: '',
        photoSearchSolvingItemIds: const {},
      );
    }
  }

  Future<void> selectPhotoSearchSession(String sessionId) async {
    final session = state.activeWorkspace.photoSearchHistory
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session == null) return;
    final bytes = await readDocImageBytes(session.localImagePath);
    if (!ref.mounted) return;
    state = state.copyWith(
      activePhotoSearchSessionId: session.id,
      photoSearchImageBytes: bytes,
      clearPhotoSearchImage: bytes == null,
      clearPhotoSearchError: true,
    );
  }

  void startNewPhotoSearch() {
    cancelPhotoSearch();
    state = state.copyWith(
      clearActivePhotoSearchSession: true,
      clearPhotoSearchImage: true,
      clearPhotoSearchError: true,
      photoSearchStageLabel: '',
    );
  }

  Future<void> deletePhotoSearchSession(String sessionId) async {
    await _updateActiveWorkspace(
      (ws) => ws.copyWith(
        photoSearchHistory: ws.photoSearchHistory
            .where((s) => s.id != sessionId)
            .toList(growable: false),
      ),
    );
    if (state.activePhotoSearchSessionId == sessionId) {
      state = state.copyWith(
        clearActivePhotoSearchSession: true,
        clearPhotoSearchImage: true,
      );
    }
  }

  Future<void> updatePhotoSearchItem(
    String sessionId,
    PhotoSearchItem updated,
  ) async {
    await _updateActiveWorkspace((ws) {
      final nextHistory = ws.photoSearchHistory
          .map((s) {
            if (s.id != sessionId) return s;
            return s.copyWith(
              items: s.items
                  .map((it) => it.id == updated.id ? updated : it)
                  .toList(growable: false),
            );
          })
          .toList(growable: false);

      var nextQuestions = ws.questions;
      if (updated.savedQuestionId != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        nextQuestions = ws.questions
            .map((q) {
              if (q.id != updated.savedQuestionId) return q;
              return updated.question.copyWith(
                id: q.id,
                docId: q.docId,
                sourceType: q.sourceType,
                historyVerdicts: q.historyVerdicts,
                createdAtMs: q.createdAtMs,
                updatedAtMs: now,
              );
            })
            .toList(growable: false);
      }

      return ws.copyWith(
        photoSearchHistory: nextHistory,
        questions: nextQuestions,
      );
    });
  }

  Future<bool> reSolvePhotoSearchItem(String sessionId, String itemId) async {
    final session = state.activeWorkspace.photoSearchHistory
        .where((s) => s.id == sessionId)
        .firstOrNull;
    final item = session?.items.where((it) => it.id == itemId).firstOrNull;
    if (session == null || item == null) return false;

    state = state.copyWith(
      photoSearchSolvingItemIds: {...state.photoSearchSolvingItemIds, itemId},
    );
    try {
      final imageBytes =
          (state.activePhotoSearchSessionId == sessionId
              ? state.photoSearchImageBytes
              : null) ??
          await readDocImageBytes(session.localImagePath);
      final solved = await _photoSearchService.solveSingleQuestion(
        profile: state.activeProfile,
        question: item.question,
        itemId: item.id,
        sortOrder: item.sortOrder,
        imageBytes: imageBytes,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
      );
      if (!ref.mounted) return solved.ok;

      final enriched = _attachMatchedKpIds(
        solved.item.copyWith(
          duplicateOfTitle: item.duplicateOfTitle,
          savedQuestionId: item.savedQuestionId,
          savedWrongItemId: item.savedWrongItemId,
        ),
      );
      await updatePhotoSearchItem(sessionId, enriched);
      return solved.ok;
    } finally {
      if (ref.mounted) {
        final nextIds = Set<String>.from(state.photoSearchSolvingItemIds)
          ..remove(itemId);
        state = state.copyWith(photoSearchSolvingItemIds: nextIds);
      }
    }
  }

  Future<Question?> savePhotoSearchItemToLibrary(
    String sessionId,
    String itemId,
  ) async {
    final res = await _savePhotoSearchItemsInternal(
      sessionId,
      [itemId],
      addToWrongBook: false,
    );
    return res.lastQuestion;
  }

  Future<({Question? question, WrongItem? wrongItem})>
  savePhotoSearchItemToWrongBook(
    String sessionId,
    String itemId, {
    List<ErrorTag> errorTags = const [ErrorTag.concept],
    String note = '',
  }) async {
    final res = await _savePhotoSearchItemsInternal(
      sessionId,
      [itemId],
      addToWrongBook: true,
      errorTags: errorTags,
      note: note,
    );
    return (question: res.lastQuestion, wrongItem: res.lastWrongItem);
  }

  Future<({int addedLibrary, int addedWrong})> saveAllPhotoSearchItems(
    String sessionId, {
    bool alsoAddToWrongBook = false,
  }) async {
    final session = state.activeWorkspace.photoSearchHistory
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session == null || session.items.isEmpty) {
      return (addedLibrary: 0, addedWrong: 0);
    }
    final res = await _savePhotoSearchItemsInternal(
      sessionId,
      session.items.map((e) => e.id).toList(growable: false),
      addToWrongBook: alsoAddToWrongBook,
    );
    return (addedLibrary: res.addedLibrary, addedWrong: res.addedWrong);
  }

  Future<
    ({
      int addedLibrary,
      int addedWrong,
      Question? lastQuestion,
      WrongItem? lastWrongItem,
    })
  >
  _savePhotoSearchItemsInternal(
    String sessionId,
    List<String> itemIds, {
    required bool addToWrongBook,
    List<ErrorTag> errorTags = const [ErrorTag.concept],
    String note = '',
  }) async {
    final ws = state.activeWorkspace;
    final session = ws.photoSearchHistory
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session == null || itemIds.isEmpty) {
      return (
        addedLibrary: 0,
        addedWrong: 0,
        lastQuestion: null,
        lastWrongItem: null,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final targetIdSet = itemIds.toSet();
    final nextDocs = List<SourceDoc>.from(ws.sourceDocs);
    final nextQuestions = List<Question>.from(ws.questions);
    final nextWrongs = List<WrongItem>.from(ws.wrongItems);

    var docId = session.sourceDocId;
    final hasDoc = docId != null && nextDocs.any((d) => d.id == docId);
    if (!hasDoc) {
      docId = 'doc_ps_${_uuid.v4().substring(0, 8)}';
      final firstGrade = session.items.isNotEmpty
          ? session.items.first.question.meta.grade
          : 'g9';
      nextDocs.insert(
        0,
        SourceDoc(
          id: docId,
          title: session.title,
          docType: 'photo_search',
          subject: session.subject,
          grade: firstGrade,
          pageCount: 1,
          localImagePath: session.localImagePath,
          createdAtMs: now,
        ),
      );
    }

    var addedLibrary = 0;
    var addedWrong = 0;
    Question? lastQuestion;
    WrongItem? lastWrongItem;

    final updatedItems = <PhotoSearchItem>[];
    for (final item in session.items) {
      if (!targetIdSet.contains(item.id)) {
        updatedItems.add(item);
        continue;
      }

      Question? savedQ;
      if (item.savedQuestionId != null) {
        savedQ = nextQuestions
            .where((q) => q.id == item.savedQuestionId)
            .firstOrNull;
      }
      if (savedQ == null) {
        savedQ = item.question.copyWith(
          id: 'q_${_uuid.v4().substring(0, 8)}',
          docId: docId,
          sourceType: 'photo_search',
          createdAtMs: now,
          updatedAtMs: now,
        );
        nextQuestions.insert(0, savedQ);
        addedLibrary++;
      }
      lastQuestion = savedQ;

      var savedWrongId = item.savedWrongItemId;
      if (addToWrongBook) {
        final existingWrong = nextWrongs
            .where((w) => w.questionId == savedQ!.id)
            .firstOrNull;
        if (existingWrong != null) {
          savedWrongId = existingWrong.id;
          lastWrongItem = existingWrong;
        } else {
          final w = WrongItem(
            id: 'w_${_uuid.v4().substring(0, 8)}',
            questionId: savedQ.id,
            addedVia: AddedVia.photoSearch,
            mastery: MasteryState.newWrong,
            correctStreak: 0,
            wrongCount: 1,
            attemptCount: 1,
            errorTags: errorTags.isNotEmpty
                ? errorTags
                : const [ErrorTag.concept],
            myWrongAnswer: '拍照搜题收录',
            teacherMark: 'wrong',
            note: note.trim().isNotEmpty
                ? note.trim()
                : (item.pitfallNote ?? ''),
            addedAtMs: now,
          );
          nextWrongs.insert(0, w);
          savedWrongId = w.id;
          lastWrongItem = w;
          addedWrong++;
        }
      }

      updatedItems.add(
        item.copyWith(
          savedQuestionId: savedQ.id,
          savedWrongItemId: savedWrongId,
        ),
      );
    }

    final updatedSession = session.copyWith(
      sourceDocId: docId,
      items: List.unmodifiable(updatedItems),
    );
    final nextHistory = ws.photoSearchHistory
        .map((s) => s.id == sessionId ? updatedSession : s)
        .toList(growable: false);

    await _updateActiveWorkspace(
      (cur) => cur.copyWith(
        sourceDocs: nextDocs,
        questions: nextQuestions,
        wrongItems: nextWrongs,
        photoSearchHistory: nextHistory,
      ),
    );

    return (
      addedLibrary: addedLibrary,
      addedWrong: addedWrong,
      lastQuestion: lastQuestion,
      lastWrongItem: lastWrongItem,
    );
  }

  PhotoSearchItem _attachMatchedKpIds(PhotoSearchItem item) {
    final q = item.question;
    final rawTerms = <String>[
      ...item.keyPoints,
      ...q.meta.tags,
    ];
    if (q.meta.kpIds.isNotEmpty || rawTerms.isEmpty) {
      return item;
    }
    final leaves = state.kpTree.leaves(subject: q.meta.subject);
    if (leaves.isEmpty) return item;
    final stageCode = state.activeProfile.stage.code;
    final prioritizedLeaves = <KnowledgeNode>[
      for (final node in leaves)
        if (node.stage == stageCode) node,
      for (final node in leaves)
        if (node.stage != stageCode) node,
    ];
    final matchedIds = <String>[];
    for (final rawTerm in rawTerms) {
      final needle = rawTerm.trim().toLowerCase();
      if (needle.isEmpty) continue;
      for (final node in prioritizedLeaves) {
        final nameLower = node.name.toLowerCase();
        if (nameLower.contains(needle) || needle.contains(nameLower)) {
          if (!matchedIds.contains(node.id)) {
            matchedIds.add(node.id);
          }
          if (matchedIds.length >= 3) break;
        }
      }
      if (matchedIds.length >= 3) break;
    }
    if (matchedIds.isEmpty) return item;
    return item.copyWith(
      question: q.copyWith(
        meta: q.meta.copyWith(kpIds: List.unmodifiable(matchedIds)),
      ),
    );
  }

  Future<void> deleteSourceDoc(
    String docId, {
    bool deleteQuestions = false,
  }) async {
    await _updateActiveWorkspace((ws) {
      final docs = ws.sourceDocs
          .where((d) => d.id != docId)
          .toList(growable: false);
      final removedQIds = deleteQuestions
          ? ws.questions.where((q) => q.docId == docId).map((q) => q.id).toSet()
          : const <String>{};
      final nextQuestions = deleteQuestions
          ? ws.questions
                .where((q) => !removedQIds.contains(q.id))
                .toList(growable: false)
          : ws.questions;
      final nextWrongs = deleteQuestions
          ? ws.wrongItems
                .where((w) => !removedQIds.contains(w.questionId))
                .toList(growable: false)
          : ws.wrongItems;
      return ws.copyWith(
        sourceDocs: docs,
        questions: nextQuestions,
        wrongItems: nextWrongs,
      );
    });
  }

  void exitActivePracticeSession() {
    state = state.copyWith(clearActiveSession: true);
  }

  void resumePracticeSession(String sessionId) {
    if (!state.activeWorkspace.sessions.any((s) => s.id == sessionId)) return;
    state = state.copyWith(activeSessionId: sessionId);
  }

  // ---------------------------------------------------------------------------
  // Question Library CRUD
  // ---------------------------------------------------------------------------

  Future<void> upsertQuestion(Question question) async {
    await _updateActiveWorkspace((ws) {
      final exists = ws.questions.any((q) => q.id == question.id);
      final list = exists
          ? ws.questions
                .map((q) => q.id == question.id ? question : q)
                .toList(growable: false)
          : [question, ...ws.questions];
      return ws.copyWith(questions: list);
    });
  }

  Future<void> deleteQuestion(String questionId) async {
    await _updateActiveWorkspace((ws) {
      return ws.copyWith(
        questions: ws.questions
            .where((q) => q.id != questionId)
            .toList(growable: false),
        wrongItems: ws.wrongItems
            .where((w) => w.questionId != questionId)
            .toList(growable: false),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Practice Session, Subjective Judging & Manual Verdict Override
  // ---------------------------------------------------------------------------

  Future<PracticeSession> startPracticeSession({
    required String title,
    required PracticeKind kind,
    required InputMode inputMode,
    required FeedbackTiming feedbackTiming,
    required List<String> questionIds,
    String? docId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'sess_${_uuid.v4().substring(0, 8)}';
    final ws = state.activeWorkspace;
    final maxScore = questionIds.fold<double>(0, (acc, qid) {
      final q = ws.questions.where((e) => e.id == qid).firstOrNull;
      return acc + (q?.maxScore ?? 0);
    });
    final session = PracticeSession(
      id: id,
      title: title,
      kind: kind,
      inputMode: inputMode,
      feedbackTiming: feedbackTiming,
      questionIds: questionIds,
      docId: docId,
      startedAtMs: now,
      status: 'in_progress',
      totalScore: 0,
      maxScore: maxScore,
    );
    await _updateActiveWorkspace(
      (cur) => cur.copyWith(sessions: [session, ...cur.sessions]),
    );
    state = state.copyWith(activeSessionId: id);
    return session;
  }

  Future<void> setPracticeSessionInputMode(
    String sessionId,
    InputMode inputMode,
  ) async {
    final ws = state.activeWorkspace;
    final existing = ws.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (existing == null || existing.inputMode == inputMode) return;
    await _updateActiveWorkspace(
      (cur) => cur.copyWith(
        sessions: cur.sessions
            .map(
              (s) => s.id == sessionId ? s.copyWith(inputMode: inputMode) : s,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> saveInkPage(String questionId, InkPageData page) async {
    await _updateActiveWorkspace((ws) {
      final nextInk = Map<String, InkPageData>.from(ws.inkPagesByQuestionId)
        ..[questionId] = page;
      return ws.copyWith(inkPagesByQuestionId: nextInk);
    });
  }

  Future<AttemptRecord> submitQuestionResponse({
    required String sessionId,
    required Question question,
    required StudentResponse response,
    List<Uint8List> attachedPngs = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ws = state.activeWorkspace;
    var verdict = Verdict.ungraded;
    var score = 0.0;
    final maxScore = question.maxScore;
    var judgedBy = JudgedBy.auto;
    String? recognizedText;
    String? feedbackSummary;
    var suggestedTags = <ErrorTag>[];

    final objective = _gradingEngine.grade(question, response);
    if (!objective.needsAi && objective.verdict != Verdict.ungraded) {
      verdict = objective.verdict;
      score = objective.score;
      feedbackSummary = objective.notes.join('；');
      suggestedTags = objective.errorTagSuggestions;
    } else {
      final judge = CloudSubjectiveJudge(
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
        strokeCountProvider: (qid) =>
            ws.inkPagesByQuestionId[qid]?.strokes.length ?? 0,
      );
      final mode = switch (question.kind) {
        QuestionKind.draw => JudgeMode.visual,
        QuestionKind.write => JudgeMode.write,
        QuestionKind.solve => JudgeMode.stepwise,
        _ => JudgeMode.rubric,
      };
      final res = await judge.judge(
        JudgeInput(
          question: question.toPublicView(),
          grading: question.grading,
          response: response,
          mode: mode,
          stage: state.activeProfile.stage,
          images: attachedPngs,
        ),
      );
      verdict = res.verdict;
      score = res.score;
      judgedBy = state.hasLiveAiKey ? JudgedBy.ai : JudgedBy.auto;
      recognizedText = res.recognizedText;
      feedbackSummary = res.summary;
      suggestedTags = res.errorTagSuggestions;
    }

    final attempt = AttemptRecord(
      id: 'att_${_uuid.v4().substring(0, 8)}',
      sessionId: sessionId,
      questionId: question.id,
      inputMode: response.inputMode,
      verdict: verdict,
      score: score,
      maxScore: maxScore,
      judgedBy: judgedBy,
      recognizedText: recognizedText,
      feedbackSummary: feedbackSummary,
      hintsUsed: response.hintsUsed,
      durationMs: response.durationMs,
      basedOnAiAnswer: question.meta.answerSource == AnswerSource.ai,
      createdAtMs: now,
      response: response,
    );

    await _applyAttemptToWorkspace(
      attempt: attempt,
      question: question,
      suggestedTags: suggestedTags,
    );
    return attempt;
  }

  Future<AttemptRecord?> overrideAttemptVerdict({
    required String attemptId,
    required Verdict newVerdict,
  }) async {
    final ws = state.activeWorkspace;
    final idx = ws.attempts.indexWhere((a) => a.id == attemptId);
    if (idx < 0) return null;
    final old = ws.attempts[idx];
    final nextScore = switch (newVerdict) {
      Verdict.correct => old.maxScore,
      Verdict.partial => double.parse((old.maxScore * 0.5).toStringAsFixed(1)),
      _ => 0.0,
    };
    final updated = AttemptRecord(
      id: old.id,
      sessionId: old.sessionId,
      questionId: old.questionId,
      inputMode: old.inputMode,
      verdict: newVerdict,
      score: nextScore,
      maxScore: old.maxScore,
      judgedBy: JudgedBy.user,
      recognizedText: old.recognizedText,
      feedbackSummary: '已由学生/家长手动改判为「${newVerdict.label}」',
      hintsUsed: old.hintsUsed,
      durationMs: old.durationMs,
      basedOnAiAnswer: old.basedOnAiAnswer,
      createdAtMs: old.createdAtMs,
      response: old.response,
    );

    final q = ws.questions.where((e) => e.id == updated.questionId).firstOrNull;
    if (q != null) {
      await _applyAttemptToWorkspace(
        attempt: updated,
        question: q,
        replaceExistingAttempt: true,
      );
    }
    return updated;
  }

  Future<void> _applyAttemptToWorkspace({
    required AttemptRecord attempt,
    required Question question,
    List<ErrorTag> suggestedTags = const [],
    bool replaceExistingAttempt = false,
  }) async {
    await _updateActiveWorkspace((ws) {
      final attempts = replaceExistingAttempt
          ? ws.attempts
                .map((a) => a.id == attempt.id ? attempt : a)
                .toList(growable: false)
          : [attempt, ...ws.attempts];

      // Update Question verdict history
      final updatedQuestions = ws.questions
          .map((q) {
            if (q.id != question.id) return q;
            final hist = replaceExistingAttempt && q.historyVerdicts.isNotEmpty
                ? [
                    ...q.historyVerdicts.sublist(
                      0,
                      q.historyVerdicts.length - 1,
                    ),
                    attempt.verdict,
                  ]
                : [...q.historyVerdicts, attempt.verdict];
            return q.copyWith(
              historyVerdicts: hist,
              updatedAtMs: attempt.createdAtMs,
            );
          })
          .toList(growable: false);

      // Update PracticeSession score total
      final sessionAttempts = attempts
          .where((a) => a.sessionId == attempt.sessionId)
          .toList();
      final totalScore = sessionAttempts.fold<double>(
        0,
        (acc, a) => acc + a.score,
      );
      final sessions = ws.sessions
          .map((s) {
            if (s.id != attempt.sessionId) return s;
            return s.copyWith(totalScore: totalScore);
          })
          .toList(growable: false);

      // Update WrongBook via MasteryService
      final existingWrong = ws.wrongItems
          .where((w) => w.questionId == question.id)
          .firstOrNull;
      final outcome = _masteryService.recordAttempt(
        existing: existingWrong,
        questionId: question.id,
        verdict: attempt.verdict,
        nowMs: attempt.createdAtMs,
        collectMode: state.snapshot.preferences.wrongBookCollectMode,
        myAnswerSummary:
            attempt.response?.toReadableSummary() ??
            (attempt.recognizedText ?? ''),
        config: MasteryConfig(
          masteryStreak: state.snapshot.preferences.masteryStreak,
          partialClearsStreak: state.snapshot.preferences.partialClearsStreak,
        ),
        suggestedTags: suggestedTags,
      );

      final nextWrongItems = List<WrongItem>.from(ws.wrongItems);
      if (outcome.item != null) {
        final wIdx = nextWrongItems.indexWhere(
          (w) => w.questionId == question.id,
        );
        if (wIdx >= 0) {
          nextWrongItems[wIdx] = outcome.item!;
        } else {
          nextWrongItems.insert(0, outcome.item!);
        }
      }

      return ws.copyWith(
        attempts: attempts,
        questions: updatedQuestions,
        sessions: sessions,
        wrongItems: nextWrongItems,
      );
    });
  }

  Future<void> finalizePracticeSession(String sessionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateActiveWorkspace((ws) {
      final sessions = ws.sessions
          .map((s) {
            if (s.id != sessionId) return s;
            return s.copyWith(status: 'submitted', submittedAtMs: now);
          })
          .toList(growable: false);
      return ws.copyWith(sessions: sessions);
    });
  }

  Future<int> collectQuestionsIntoWrongBook(List<String> questionIds) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    await _updateActiveWorkspace((ws) {
      final existingIds = ws.wrongItems.map((w) => w.questionId).toSet();
      final nextWrongs = List<WrongItem>.from(ws.wrongItems);
      for (final qid in questionIds) {
        if (existingIds.contains(qid)) {
          // Bump wrong count
          final idx = nextWrongs.indexWhere((w) => w.questionId == qid);
          if (idx >= 0) {
            final cur = nextWrongs[idx];
            nextWrongs[idx] = cur.copyWith(
              wrongCount: cur.wrongCount + 1,
              correctStreak: 0,
              mastery: MasteryState.learning,
            );
          }
          continue;
        }
        added++;
        nextWrongs.insert(
          0,
          WrongItem(
            id: 'w_${_uuid.v4().substring(0, 8)}',
            questionId: qid,
            addedVia: AddedVia.practice,
            mastery: MasteryState.newWrong,
            correctStreak: 0,
            wrongCount: 1,
            attemptCount: 1,
            errorTags: const [ErrorTag.calc],
            addedAtMs: now,
          ),
        );
      }
      return ws.copyWith(wrongItems: nextWrongs);
    });
    return added;
  }

  // ---------------------------------------------------------------------------
  // WrongBook Mastery Progression (`N = 3`)
  // ---------------------------------------------------------------------------

  Future<MasteryUpdateOutcome> simulateCorrectReview(String wrongItemId) async {
    final ws = state.activeWorkspace;
    final item = ws.wrongItems.firstWhere((w) => w.id == wrongItemId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final outcome = _masteryService.recordAttempt(
      existing: item,
      questionId: item.questionId,
      verdict: Verdict.correct,
      nowMs: now,
      collectMode: WrongBookCollectMode.auto,
      myAnswerSummary: '复练正确通过',
      config: MasteryConfig(
        masteryStreak: state.snapshot.preferences.masteryStreak,
        partialClearsStreak: state.snapshot.preferences.partialClearsStreak,
      ),
    );
    await _updateActiveWorkspace((cur) {
      final list = cur.wrongItems
          .map((w) => w.id == wrongItemId ? (outcome.item ?? w) : w)
          .toList(growable: false);
      final q = cur.questions.where((e) => e.id == item.questionId).firstOrNull;
      final attempt = AttemptRecord(
        id: 'att_rev_${_uuid.v4().substring(0, 8)}',
        sessionId: 'wrongbook_quick_review',
        questionId: item.questionId,
        inputMode: InputMode.standard,
        verdict: Verdict.correct,
        score: q?.maxScore ?? 1,
        maxScore: q?.maxScore ?? 1,
        createdAtMs: now,
      );
      return cur.copyWith(
        wrongItems: list,
        attempts: [attempt, ...cur.attempts],
      );
    });
    return outcome;
  }

  Future<void> updateWrongItemDetails(
    String wrongItemId, {
    List<ErrorTag>? errorTags,
    String? note,
  }) async {
    await _updateActiveWorkspace((ws) {
      final list = ws.wrongItems
          .map((w) {
            if (w.id != wrongItemId) return w;
            return w.copyWith(errorTags: errorTags, note: note);
          })
          .toList(growable: false);
      return ws.copyWith(wrongItems: list);
    });
  }

  Future<void> removeWrongItem(String wrongItemId) async {
    await _updateActiveWorkspace(
      (ws) => ws.copyWith(
        wrongItems: ws.wrongItems
            .where((w) => w.id != wrongItemId)
            .toList(growable: false),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Weakness Analytics & StudyCoach Report / Drill Generator
  // ---------------------------------------------------------------------------

  WeaknessSnapshot computeWeaknessSnapshot({String? subjectFilter}) {
    final ws = state.activeWorkspace;
    return _weaknessAnalyzer.analyze(
      questions: ws.questions,
      attempts: ws.attempts,
      wrongItems: ws.wrongItems,
      kpNodes: state.kpTree.nodes,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      subjectFilter: subjectFilter,
    );
  }

  Future<StudyCoachReportResult> generateStudyReport() async {
    state = state.copyWith(coachBusy: true);
    try {
      final snap = computeWeaknessSnapshot();
      final res = await _coachService.generateReport(
        profile: state.activeProfile,
        snapshot: snap,
        wrongItems: state.activeWorkspace.wrongItems,
        questions: state.activeWorkspace.questions,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
      );
      await _updateActiveWorkspace(
        (ws) => ws.copyWith(reports: [res.report, ...ws.reports]),
      );
      state = state.copyWith(
        coachBusy: false,
        lastSavedReportId: res.report.id,
      );
      return res;
    } finally {
      state = state.copyWith(coachBusy: false);
    }
  }

  Future<DrillGenerationResult> generateTargetedDrill({
    required String subject,
    List<String> targetKpIds = const [],
    List<String> targetKpNames = const [],
    Question? sourceWrongQuestion,
    int count = 3,
  }) async {
    state = state.copyWith(coachBusy: true);
    try {
      final res = await _coachService.generateDrill(
        profile: state.activeProfile,
        subject: subject,
        targetKpIds: targetKpIds,
        targetKpNames: targetKpNames,
        sourceWrongQuestion: sourceWrongQuestion,
        existingQuestions: state.activeWorkspace.questions,
        count: count,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
      );
      if (res.questions.isNotEmpty) {
        await _updateActiveWorkspace(
          (ws) => ws.copyWith(questions: [...res.questions, ...ws.questions]),
        );
      }
      state = state.copyWith(coachBusy: false);
      return res;
    } finally {
      state = state.copyWith(coachBusy: false);
    }
  }

  // ---------------------------------------------------------------------------
  // NuoNuo Copilot Tutor Drawer
  // ---------------------------------------------------------------------------

  void openCopilot({
    String? questionId,
    HintLevel? hintLevel,
    Uint8List? lassoBytes,
  }) {
    state = state.copyWith(
      copilotOpen: true,
      copilotQuestionId: questionId,
      clearCopilotQuestion: questionId == null,
      copilotHintLevel: hintLevel ?? state.copilotHintLevel,
      copilotLassoBytes: lassoBytes,
      clearCopilotLasso: lassoBytes == null,
    );
  }

  void closeCopilot() {
    state = state.copyWith(copilotOpen: false);
  }

  void setCopilotHintLevel(HintLevel level) {
    state = state.copyWith(copilotHintLevel: level);
  }

  void clearCopilotAttachment() {
    state = state.copyWith(clearCopilotLasso: true);
  }

  void attachCopilotImage(Uint8List bytes) {
    state = state.copyWith(copilotLassoBytes: bytes);
  }

  Future<void> clearCopilotThread() async {
    final thread = state.activeCopilotThread;
    await _saveCopilotThread(
      TutorThreadRecord(
        id: thread.id,
        scope: thread.scope,
        questionId: thread.questionId,
        hintLevel: thread.hintLevel,
      ),
    );
  }

  Future<TutorReplyResult> sendTutorMessage(
    String userText, {
    String? currentDraftText,
    bool isPostMortem = false,
    String? verdictLabel,
  }) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      return const TutorReplyResult(
        emotion: MascotEmotion.wink,
        content: '想问诺诺哪道题呢？随时输入问题吧～',
        toolTrace: [],
        antiSpoilerBlocked: false,
        usedOfflineFallback: true,
        hintLevel: HintLevel.none,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final thread = state.activeCopilotThread;
    final qId = state.copilotQuestionId;
    final boundQ = state.findQuestionById(qId);
    final relatedWrong = boundQ == null
        ? const <WrongItem>[]
        : state.activeWorkspace.wrongItems
              .where((w) => w.questionId == boundQ.id)
              .toList(growable: false);

    final userMsg = TutorMessageRecord(
      id: 'tmsg_u_${_uuid.v4().substring(0, 8)}',
      role: 'user',
      content: trimmed,
      createdAtMs: now,
    );

    final preMessages = [...thread.messages, userMsg];
    await _saveCopilotThread(
      thread.copyWith(
        messages: preMessages,
        hintLevel: state.copilotHintLevel.index,
      ),
    );
    state = state.copyWith(copilotBusy: true, clearCopilotStreamingText: true);

    try {
      final result = await _tutorService.sendMessage(
        TutorRequestContext(
          profile: state.activeProfile,
          userMessage: trimmed,
          sessionId: thread.id,
          boundQuestion: boundQ,
          currentDraftText: currentDraftText,
          isPostMortem: isPostMortem,
          verdictLabel: verdictLabel,
          hintLevel: state.copilotHintLevel,
          relatedWrongItems: relatedWrong,
          history: thread.messages,
          attachedImageBytes: state.copilotLassoBytes,
          endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
          apiKey: state.activeApiKey,
          overrideClient: ref.read(overrideLlmClientProvider),
        ),
        onPartialReply: (partial) {
          if (!ref.mounted) return;
          state = state.copyWith(copilotStreamingText: partial);
        },
      );

      final assistantMsg = TutorMessageRecord(
        id: 'tmsg_a_${_uuid.v4().substring(0, 8)}',
        role: 'assistant',
        content: result.content,
        emotion: result.emotion.code,
        toolTrace: result.toolTrace
            .map((e) => e.toDisplayLine())
            .toList(growable: false),
        antiSpoilerBlocked: result.antiSpoilerBlocked,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      final allMessages = [...preMessages, assistantMsg];
      await _saveCopilotThread(
        thread.copyWith(
          messages: allMessages,
          hintLevel: state.copilotHintLevel.index,
        ),
      );
      state = state.copyWith(
        copilotBusy: false,
        copilotLastEmotion: result.emotion,
        clearCopilotLasso: true,
        clearCopilotStreamingText: true,
      );
      if (allMessages.length > 14) {
        unawaited(
          _summarizeCopilotThreadInBackground(
            threadId: thread.id,
            messagesToSummarize: allMessages.sublist(0, allMessages.length - 8),
            previousSummary: thread.summary ?? '',
          ),
        );
      }
      return result;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          copilotBusy: false,
          clearCopilotStreamingText: true,
        );
      }
    }
  }

  Future<void> _summarizeCopilotThreadInBackground({
    required String threadId,
    required List<TutorMessageRecord> messagesToSummarize,
    required String previousSummary,
  }) async {
    try {
      final summary = await _tutorService.summarizeThread(
        messages: messagesToSummarize,
        previousSummary: previousSummary,
        endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
        apiKey: state.activeApiKey,
        overrideClient: ref.read(overrideLlmClientProvider),
      );
      if (!ref.mounted || summary.isEmpty || summary == previousSummary) {
        return;
      }
      final current = state.activeWorkspace.tutorThreads
          .where((t) => t.id == threadId)
          .firstOrNull;
      if (current == null) return;
      await _saveCopilotThread(current.copyWith(summary: summary));
    } catch (_) {
      // Background compression failure is non-critical and safe to ignore.
    }
  }

  Future<void> _saveCopilotThread(TutorThreadRecord updated) async {
    await _updateActiveWorkspace((ws) {
      final exists = ws.tutorThreads.any((t) => t.id == updated.id);
      final list = exists
          ? ws.tutorThreads
                .map((t) => t.id == updated.id ? updated : t)
                .toList(growable: false)
          : [updated, ...ws.tutorThreads];
      return ws.copyWith(tutorThreads: list);
    });
  }

  // ---------------------------------------------------------------------------
  // AI Blackboard Classroom (Step-by-Step Board + Diagrams + Circle-to-Ask)
  // ---------------------------------------------------------------------------

  Future<void> openBlackboard({
    String? questionId,
    HintLevel? hintLevel,
    Uint8List? lassoBytes,
    String? currentDraftText,
    bool isPostMortem = false,
    bool forceRegenerate = false,
  }) async {
    final nextQId = questionId ?? state.copilotQuestionId;
    final rawLevel =
        hintLevel ??
        (isPostMortem ? HintLevel.l3FullSolution : state.copilotHintLevel);
    final effectiveLevel = rawLevel == HintLevel.none
        ? HintLevel.l1Concept
        : rawLevel;
    final key = nextQId ?? '__free__';
    final existing = state.activeWorkspace.blackboardLessonsByQuestionId[key];

    state = state.copyWith(
      blackboardOpen: true,
      copilotOpen: false,
      copilotQuestionId: nextQId,
      clearCopilotQuestion: nextQId == null,
      copilotHintLevel: effectiveLevel,
      copilotLassoBytes: lassoBytes,
      clearCopilotLasso: lassoBytes == null,
      blackboardPenMode: BlackboardPenMode.none,
    );

    final needsGenerate =
        forceRegenerate ||
        existing == null ||
        existing.tracks.isEmpty ||
        existing.hintLevel != effectiveLevel.index;

    if (!needsGenerate) {
      final stepEmo = existing.activeTrack?.currentStep?.emotion;
      if (stepEmo != null) {
        state = state.copyWith(
          copilotLastEmotion: MascotEmotion.fromCode(stepEmo),
        );
      }
      final existingTrack = existing.activeTrack;
      final isRemote =
          state.hasLiveAiKey || ref.read(overrideLlmClientProvider) != null;
      if (isRemote &&
          existingTrack != null &&
          existingTrack.hasMoreSteps &&
          existingTrack.revealedCount >= existingTrack.steps.length &&
          _prefetchingStepNumber == null) {
        final nextStepNum = existingTrack.steps.length + 1;
        unawaited(
          _prefetchNextBlackboardStep(
            seq: _blackboardGenSeq,
            key: key,
            stepNumber: nextStepNum,
          ),
        );
      }
      return;
    }

    await _generateAndSaveBlackboardLesson(
      key: key,
      questionId: nextQId,
      hintLevel: effectiveLevel,
      lassoBytes: lassoBytes,
      currentDraftText: currentDraftText,
      isPostMortem: isPostMortem,
      preserveInk: existing?.studentInkData,
    );
  }

  Future<void> setBlackboardHintLevel(HintLevel level) async {
    final effective = level == HintLevel.none ? HintLevel.l1Concept : level;
    state = state.copyWith(copilotHintLevel: effective);
    final existing = state.activeBlackboardLesson;
    if (existing != null && existing.hintLevel == effective.index) return;
    await _generateAndSaveBlackboardLesson(
      key: state.activeBlackboardKey,
      questionId: state.copilotQuestionId,
      hintLevel: effective,
      currentDraftText: _blackboardDraftText,
      isPostMortem: _blackboardIsPostMortem,
      preserveInk: existing?.studentInkData,
    );
  }

  Future<void> regenerateBlackboardLesson() async {
    final existing = state.activeBlackboardLesson;
    await _generateAndSaveBlackboardLesson(
      key: state.activeBlackboardKey,
      questionId: state.copilotQuestionId,
      hintLevel: state.copilotHintLevel == HintLevel.none
          ? HintLevel.l1Concept
          : state.copilotHintLevel,
      currentDraftText: _blackboardDraftText,
      isPostMortem: _blackboardIsPostMortem,
      preserveInk: existing?.studentInkData,
    );
  }

  Future<void> _generateAndSaveBlackboardLesson({
    required String key,
    required String? questionId,
    required HintLevel hintLevel,
    Uint8List? lassoBytes,
    String? currentDraftText,
    bool isPostMortem = false,
    Map<String, Object?>? preserveInk,
  }) async {
    final boundQ = state.findQuestionById(questionId);
    final relatedWrong = boundQ == null
        ? const <WrongItem>[]
        : state.activeWorkspace.wrongItems
              .where((w) => w.questionId == boundQ.id)
              .toList(growable: false);

    _cancelBlackboardStreams(reason: 'superseded');
    final cancelToken = CancelToken();
    _cancelTokens[_blackboardCancelKey] = cancelToken;
    final seq = _blackboardGenSeq;

    _blackboardDraftText = currentDraftText;
    _blackboardIsPostMortem = isPostMortem;
    _blackboardInitialLasso = lassoBytes;

    final overrideClient = ref.read(overrideLlmClientProvider);
    final isRemote = state.hasLiveAiKey || overrideClient != null;

    // Offline / local deterministic lesson remains instantaneous & full-featured.
    if (!isRemote) {
      final planReq = BlackboardPlanRequest(
        profile: state.activeProfile,
        boundQuestion: boundQ,
        currentDraftText: currentDraftText,
        isPostMortem: isPostMortem,
        hintLevel: hintLevel,
        relatedWrongItems: relatedWrong,
        attachedImageBytes: lassoBytes,
        cancelToken: cancelToken,
      );
      state = state.copyWith(
        blackboardBusy: true,
        blackboardStepStreaming: false,
        blackboardFeedbackBusy: false,
        clearStreamingBlackboard: true,
        copilotLastEmotion: MascotEmotion.thinking,
      );
      try {
        final res = await _tutorService.generateBlackboardLesson(planReq);
        if (!ref.mounted || seq != _blackboardGenSeq) return;
        final lesson = preserveInk != null
            ? res.lesson.copyWith(studentInkData: preserveInk)
            : res.lesson;
        await _saveBlackboardLesson(key, lesson);
        if (!ref.mounted || seq != _blackboardGenSeq) return;
        final stepEmo = lesson.activeTrack?.currentStep?.emotion ?? 'happy';
        state = state.copyWith(
          blackboardBusy: false,
          blackboardStepStreaming: false,
          clearStreamingBlackboard: true,
          copilotLastEmotion: MascotEmotion.fromCode(stepEmo),
          blackboardLastTraces: res.toolTrace
              .map((t) => t.toDisplayLine())
              .toList(growable: false),
          blackboardAntiSpoilerBlocked: res.antiSpoilerBlocked,
          clearCopilotLasso: true,
        );
      } finally {
        if (identical(_cancelTokens[_blackboardCancelKey], cancelToken)) {
          _cancelTokens.remove(_blackboardCancelKey);
        }
        if (ref.mounted && seq == _blackboardGenSeq) {
          state = state.copyWith(
            blackboardBusy: false,
            blackboardStepStreaming: false,
            clearStreamingBlackboard: true,
          );
        }
      }
      return;
    }

    // Remote AI: stream ONLY Step 1 fast via P-17, unlock Forward button right
    // away when Step 1 finishes, then silently prefetch Step 2 in background.
    final lessonId = 'bb_${_uuid.v4().substring(0, 8)}';
    final effectiveHintIndex = (isPostMortem
            ? HintLevel.l3FullSolution
            : (hintLevel == HintLevel.none ? HintLevel.l1Concept : hintLevel))
        .index;

    state = state.copyWith(
      blackboardBusy: true,
      blackboardStepStreaming: true,
      blackboardFeedbackBusy: false,
      clearStreamingBlackboard: true,
      copilotLastEmotion: MascotEmotion.thinking,
    );

    BlackboardLessonRecord buildStep1Lesson({
      required BlackboardStep step,
      required bool hasMoreSteps,
      int? plannedTotalSteps,
      BlackboardDiagramSpec? diagram,
      String takeaway = '',
    }) {
      return BlackboardLessonRecord(
        id: lessonId,
        questionId: boundQ?.id ?? '__free__',
        questionTitle: boundQ?.header.title ?? '自由黑板讲堂',
        hintLevel: effectiveHintIndex,
        studentInkData: preserveInk,
        tracks: [
          BlackboardSolutionTrack(
            id: 'track_1',
            label: '解法一：分步精讲',
            diagram: diagram ?? const BlackboardDiagramSpec(),
            steps: [step],
            revealedCount: 1,
            takeaway: takeaway,
            hasMoreSteps: hasMoreSteps,
            plannedTotalSteps: plannedTotalSteps,
          ),
        ],
        activeTrackIndex: 0,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }

    var shouldPrefetchNext = false;
    try {
      final res = await _tutorService.generateBlackboardStep(
        BlackboardStepRequest(
          profile: state.activeProfile,
          stepNumber: 1,
          boundQuestion: boundQ,
          previousSteps: const [],
          currentDraftText: currentDraftText,
          isPostMortem: isPostMortem,
          hintLevel: hintLevel,
          attachedImageBytes: lassoBytes,
          endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
          apiKey: state.activeApiKey,
          overrideClient: overrideClient,
          cancelToken: cancelToken,
        ),
        onPartialStep: (partial) {
          if (!ref.mounted || seq != _blackboardGenSeq) return;
          final liveLesson = buildStep1Lesson(
            step: partial.step,
            hasMoreSteps: partial.hasMoreSteps,
            plannedTotalSteps: partial.plannedTotalSteps,
            diagram: partial.diagram,
            takeaway: partial.takeaway,
          );
          state = state.copyWith(
            blackboardBusy: false,
            blackboardStepStreaming: true,
            streamingBlackboardLesson: liveLesson,
            copilotLastEmotion: MascotEmotion.fromCode(partial.step.emotion),
          );
        },
      );
      if (!ref.mounted || seq != _blackboardGenSeq) return;

      final finalStep1Lesson = buildStep1Lesson(
        step: res.step,
        hasMoreSteps: res.hasMoreSteps,
        plannedTotalSteps: res.plannedTotalSteps,
        diagram: res.diagram,
        takeaway: res.takeaway,
      );
      await _saveBlackboardLesson(key, finalStep1Lesson);
      if (!ref.mounted || seq != _blackboardGenSeq) return;

      shouldPrefetchNext = res.hasMoreSteps && !res.usedOfflineFallback;
      state = state.copyWith(
        blackboardBusy: false,
        blackboardStepStreaming: false,
        clearStreamingBlackboard: true,
        copilotLastEmotion: MascotEmotion.fromCode(res.step.emotion),
        blackboardLastTraces: res.toolTrace
            .map((t) => t.toDisplayLine())
            .toList(growable: false),
        blackboardAntiSpoilerBlocked: res.antiSpoilerBlocked,
        clearCopilotLasso: true,
      );
    } finally {
      if (identical(_cancelTokens[_blackboardCancelKey], cancelToken)) {
        _cancelTokens.remove(_blackboardCancelKey);
      }
      if (ref.mounted && seq == _blackboardGenSeq) {
        state = state.copyWith(
          blackboardBusy: false,
          blackboardStepStreaming: false,
          clearStreamingBlackboard: true,
        );
      }
    }

    if (shouldPrefetchNext && ref.mounted && seq == _blackboardGenSeq) {
      unawaited(
        _prefetchNextBlackboardStep(
          seq: seq,
          key: key,
          stepNumber: 2,
        ),
      );
    }
  }

  Future<void> _prefetchNextBlackboardStep({
    required int seq,
    required String key,
    required int stepNumber,
  }) async {
    if (!ref.mounted || seq != _blackboardGenSeq) return;
    final overrideClient = ref.read(overrideLlmClientProvider);
    final isRemote = state.hasLiveAiKey || overrideClient != null;
    if (!isRemote) return;

    final startLesson =
        state.activeWorkspace.blackboardLessonsByQuestionId[key];
    final startTrack = startLesson?.tracks.firstOrNull;
    if (startLesson == null ||
        startTrack == null ||
        !startTrack.hasMoreSteps ||
        startTrack.steps.any((s) => s.stepNumber == stepNumber)) {
      return;
    }

    final prevToken = _cancelTokens.remove(_blackboardPrefetchCancelKey);
    if (prevToken != null && !prevToken.isCancelled) {
      prevToken.cancel('superseded_prefetch');
    }
    final cancelToken = CancelToken();
    _cancelTokens[_blackboardPrefetchCancelKey] = cancelToken;
    _prefetchingStepNumber = stepNumber;
    _prefetchLatestPartial = null;

    final boundQ = key == '__free__' ? null : state.findQuestionById(key);
    final hintLevel = HintLevel.values[startLesson.hintLevel.clamp(
      0,
      HintLevel.values.length - 1,
    )];

    var continuePrefetchNext = false;
    final feedbackSummary = _buildStudentFeedbackSummary(startTrack.steps);
    try {
      final res = await _tutorService.generateBlackboardStep(
        BlackboardStepRequest(
          profile: state.activeProfile,
          stepNumber: stepNumber,
          boundQuestion: boundQ,
          previousSteps: startTrack.steps,
          studentFeedbackSummary: feedbackSummary,
          currentDraftText: _blackboardDraftText,
          isPostMortem: _blackboardIsPostMortem,
          hintLevel: hintLevel,
          attachedImageBytes: _blackboardInitialLasso,
          endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
          apiKey: state.activeApiKey,
          overrideClient: overrideClient,
          cancelToken: cancelToken,
        ),
        onPartialStep: (partial) {
          if (!ref.mounted || seq != _blackboardGenSeq) return;
          _prefetchLatestPartial = partial;
          if (_awaitingStepNumber == stepNumber) {
            final latest =
                state.activeWorkspace.blackboardLessonsByQuestionId[key];
            final baseTrack = latest?.tracks.firstOrNull;
            if (latest == null || baseTrack == null) return;
            final mergedDiag = partial.addedDiagramElements.isEmpty
                ? baseTrack.diagram
                : baseTrack.diagram.addElements(partial.addedDiagramElements);
            final liveSteps = baseTrack.steps.any(
              (s) => s.stepNumber == stepNumber,
            )
                ? baseTrack.steps
                      .map((s) => s.stepNumber == stepNumber ? partial.step : s)
                      .toList(growable: false)
                : [...baseTrack.steps, partial.step];
            final liveTrack = baseTrack.copyWith(
              diagram: mergedDiag,
              steps: liveSteps,
              revealedCount: liveSteps.length,
              hasMoreSteps: partial.hasMoreSteps,
              plannedTotalSteps:
                  partial.plannedTotalSteps ?? baseTrack.plannedTotalSteps,
              takeaway: partial.takeaway.isNotEmpty
                  ? partial.takeaway
                  : baseTrack.takeaway,
            );
            state = state.copyWith(
              blackboardStepStreaming: true,
              streamingBlackboardLesson: _replaceTrackAt(latest, 0, liveTrack),
              copilotLastEmotion: MascotEmotion.fromCode(partial.step.emotion),
            );
          }
        },
      );

      if (!ref.mounted || seq != _blackboardGenSeq) return;
      final awaitingNow = _awaitingStepNumber == stepNumber;
      var savedNextRevealedCount = 0;

      await _updateActiveWorkspace((ws) {
        final latest = ws.blackboardLessonsByQuestionId[key];
        final baseTrack = latest?.tracks.firstOrNull;
        if (latest == null || baseTrack == null) return ws;
        final nextSteps = baseTrack.steps.any(
          (s) => s.stepNumber == res.step.stepNumber,
        )
            ? baseTrack.steps
                  .map(
                    (s) => s.stepNumber == res.step.stepNumber ? res.step : s,
                  )
                  .toList(growable: false)
            : [...baseTrack.steps, res.step];
        final nextDiag = res.addedDiagramElements.isEmpty
            ? baseTrack.diagram
            : baseTrack.diagram.addElements(res.addedDiagramElements);
        final nextRevealed = (awaitingNow && latest.activeTrackIndex == 0)
            ? nextSteps.length
            : baseTrack.revealedCount;
        savedNextRevealedCount = nextRevealed;
        final updatedTrack = baseTrack.copyWith(
          diagram: nextDiag,
          steps: nextSteps,
          revealedCount: nextRevealed,
          hasMoreSteps: res.hasMoreSteps,
          plannedTotalSteps:
              res.plannedTotalSteps ??
              (res.hasMoreSteps ? baseTrack.plannedTotalSteps : nextSteps.length),
          takeaway: res.takeaway.isNotEmpty ? res.takeaway : baseTrack.takeaway,
        );
        final updatedLesson = _replaceTrackAt(latest, 0, updatedTrack);
        final nextMap = Map<String, BlackboardLessonRecord>.from(
          ws.blackboardLessonsByQuestionId,
        )..[key] = updatedLesson;
        return ws.copyWith(blackboardLessonsByQuestionId: nextMap);
      });

      if (!ref.mounted || seq != _blackboardGenSeq) return;
      if (awaitingNow) {
        _awaitingStepNumber = null;
        continuePrefetchNext =
            res.hasMoreSteps &&
            !res.usedOfflineFallback &&
            savedNextRevealedCount >= stepNumber;
        state = state.copyWith(
          blackboardStepStreaming: false,
          clearStreamingBlackboard: true,
          copilotLastEmotion: MascotEmotion.fromCode(res.step.emotion),
          blackboardLastTraces: [
            ...state.blackboardLastTraces,
            ...res.toolTrace.map((t) => t.toDisplayLine()),
          ],
        );
      }
    } finally {
      if (identical(_cancelTokens[_blackboardPrefetchCancelKey], cancelToken)) {
        _cancelTokens.remove(_blackboardPrefetchCancelKey);
      }
      if (_prefetchingStepNumber == stepNumber) {
        _prefetchingStepNumber = null;
        _prefetchLatestPartial = null;
      }
      if (_awaitingStepNumber == stepNumber) {
        _awaitingStepNumber = null;
        if (ref.mounted && seq == _blackboardGenSeq) {
          state = state.copyWith(
            blackboardStepStreaming: false,
            clearStreamingBlackboard: true,
          );
        }
      }
    }

    if (continuePrefetchNext && ref.mounted && seq == _blackboardGenSeq) {
      unawaited(
        _prefetchNextBlackboardStep(
          seq: seq,
          key: key,
          stepNumber: stepNumber + 1,
        ),
      );
    }
  }

  void closeBlackboard({bool collapseToDrawer = false}) {
    _cancelBlackboardStreams(reason: 'closed');
    state = state.copyWith(
      blackboardOpen: false,
      blackboardBusy: false,
      blackboardStepStreaming: false,
      blackboardFeedbackBusy: false,
      clearStreamingBlackboard: true,
      copilotOpen: collapseToDrawer ? true : state.copilotOpen,
      blackboardPenMode: BlackboardPenMode.none,
    );
  }

  void setBlackboardPenMode(BlackboardPenMode mode) {
    state = state.copyWith(blackboardPenMode: mode);
  }

  Future<void> stepBlackboardForward() async {
    final lesson = state.activeBlackboardLesson;
    final track = lesson?.activeTrack;
    if (lesson == null ||
        track == null ||
        !track.canStepForward ||
        state.blackboardStepStreaming) {
      return;
    }

    if (track.revealedCount < track.steps.length) {
      final nextTrack = track.copyWith(revealedCount: track.revealedCount + 1);
      final updatedLesson = _replaceActiveTrack(lesson, nextTrack);
      await _saveBlackboardLesson(state.activeBlackboardKey, updatedLesson);
      if (!ref.mounted) return;
      final stepEmo = nextTrack.currentStep?.emotion;
      if (stepEmo != null) {
        state = state.copyWith(
          copilotLastEmotion: MascotEmotion.fromCode(stepEmo),
        );
      }
      if (lesson.activeTrackIndex == 0 &&
          nextTrack.revealedCount >= nextTrack.steps.length &&
          nextTrack.hasMoreSteps &&
          _prefetchingStepNumber == null) {
        unawaited(
          _prefetchNextBlackboardStep(
            seq: _blackboardGenSeq,
            key: state.activeBlackboardKey,
            stepNumber: nextTrack.steps.length + 1,
          ),
        );
      }
      return;
    }

    // Track is caught up to generated steps, and `hasMoreSteps` is true.
    final targetStepNum = track.steps.length + 1;
    final partial = _prefetchingStepNumber == targetStepNum
        ? _prefetchLatestPartial
        : null;
    _awaitingStepNumber = targetStepNum;

    BlackboardLessonRecord? liveLesson;
    if (partial != null) {
      final mergedDiag = partial.addedDiagramElements.isEmpty
          ? track.diagram
          : track.diagram.addElements(partial.addedDiagramElements);
      final liveTrack = track.copyWith(
        diagram: mergedDiag,
        steps: [...track.steps, partial.step],
        revealedCount: targetStepNum,
        hasMoreSteps: partial.hasMoreSteps,
        plannedTotalSteps: partial.plannedTotalSteps ?? track.plannedTotalSteps,
        takeaway: partial.takeaway.isNotEmpty ? partial.takeaway : track.takeaway,
      );
      liveLesson = _replaceActiveTrack(lesson, liveTrack);
    }

    state = state.copyWith(
      blackboardStepStreaming: true,
      streamingBlackboardLesson: liveLesson,
      copilotLastEmotion: partial != null
          ? MascotEmotion.fromCode(partial.step.emotion)
          : MascotEmotion.thinking,
    );

    if (_prefetchingStepNumber != targetStepNum) {
      unawaited(
        _prefetchNextBlackboardStep(
          seq: _blackboardGenSeq,
          key: state.activeBlackboardKey,
          stepNumber: targetStepNum,
        ),
      );
    }
  }

  Future<void> stepBlackboardBackward() async {
    final lesson = state.activeBlackboardLesson;
    final track = lesson?.activeTrack;
    if (lesson == null || track == null || !track.canStepBackward) return;
    final nextTrack = track.copyWith(revealedCount: track.revealedCount - 1);
    final updatedLesson = _replaceActiveTrack(lesson, nextTrack);
    await _saveBlackboardLesson(state.activeBlackboardKey, updatedLesson);
    if (!ref.mounted) return;
    final stepEmo = nextTrack.currentStep?.emotion;
    if (stepEmo != null) {
      state = state.copyWith(
        copilotLastEmotion: MascotEmotion.fromCode(stepEmo),
      );
    }
  }

  Future<void> answerBlackboardCheckpoint(
    String stepId,
    int? selectedOptionIndex, {
    bool skip = false,
    bool advanceOnSkip = true,
  }) async {
    final lesson = state.activeBlackboardLesson;
    final track = lesson?.activeTrack;
    if (lesson == null || track == null) return;

    var matched = false;
    var resolvedCorrect = false;
    final nextSteps = track.steps
        .map((step) {
          if (step.id != stepId || step.checkpoint == null) return step;
          matched = true;
          final cp = step.checkpoint!;
          resolvedCorrect = !skip && selectedOptionIndex == cp.correctIndex;
          final nextCp = cp.copyWith(
            answeredSelection: selectedOptionIndex,
            skipped: skip,
            feedbackVerdict: skip
                ? null
                : (resolvedCorrect ? 'correct' : 'wrong'),
          );
          return step.copyWith(checkpoint: nextCp);
        })
        .toList(growable: false);

    if (!matched) return;
    final hasRevealedNext = track.revealedCount < track.steps.length;
    final shouldAdvanceInline =
        skip &&
        advanceOnSkip &&
        track.currentStep?.id == stepId &&
        hasRevealedNext;
    final shouldTriggerOnDemandForward =
        skip &&
        advanceOnSkip &&
        track.currentStep?.id == stepId &&
        !hasRevealedNext &&
        track.hasMoreSteps;
    final nextTrack = track.copyWith(
      steps: nextSteps,
      revealedCount: shouldAdvanceInline
          ? track.revealedCount + 1
          : track.revealedCount,
    );
    await _saveBlackboardLesson(
      state.activeBlackboardKey,
      _replaceActiveTrack(lesson, nextTrack),
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      copilotLastEmotion: resolvedCorrect
          ? MascotEmotion.celebrate
          : MascotEmotion.encourage,
    );
    if (!skip && !resolvedCorrect) {
      await _invalidateUnrevealedPrefetchIfNeeded(state.activeBlackboardKey);
    } else if (shouldTriggerOnDemandForward) {
      await stepBlackboardForward();
    }
  }

  /// Evaluates open-ended student trial answers or confusion signals (`P-18`),
  /// stores both student input and teacher feedback inside the step, and
  /// invalidates any stale unrevealed prefetch so Step N+1 adapts immediately.
  Future<BlackboardFeedbackResult?> submitBlackboardStepFeedback({
    required String stepId,
    required String replyText,
    bool isConfused = false,
  }) async {
    final key = state.activeBlackboardKey;
    final lesson = state.activeBlackboardLesson;
    final track = lesson?.activeTrack;
    final targetStep = track?.steps.where((s) => s.id == stepId).firstOrNull;
    if (lesson == null || track == null || targetStep == null) return null;

    final boundQ = state.findQuestionById(state.copilotQuestionId);
    final trimmed = replyText.trim();
    state = state.copyWith(blackboardFeedbackBusy: true);
    try {
      final res = await _tutorService.evaluateBlackboardFeedback(
        BlackboardFeedbackRequest(
          profile: state.activeProfile,
          step: targetStep,
          studentReply: trimmed,
          boundQuestion: boundQ,
          hintLevel: state.copilotHintLevel,
          isConfused: isConfused,
          endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
          apiKey: state.activeApiKey,
          overrideClient: ref.read(overrideLlmClientProvider),
        ),
      );
      if (!ref.mounted) return res;

      final displayStudentNote = isConfused && trimmed.isEmpty
          ? '这一步有点懵，想听更细致一点的拆解'
          : trimmed;

      await _updateActiveWorkspace((ws) {
        final latest = ws.blackboardLessonsByQuestionId[key];
        final activeT = latest?.activeTrack;
        if (latest == null || activeT == null) return ws;
        final updatedSteps = activeT.steps
            .map((s) {
              if (s.id != stepId) return s;
              final cp = s.checkpoint;
              if (cp != null && cp.isOpenEnded) {
                return s.copyWith(
                  checkpoint: cp.copyWith(
                    studentReply: displayStudentNote,
                    teacherFeedback: res.feedback,
                    feedbackVerdict: res.verdict,
                  ),
                );
              }
              return s.copyWith(
                studentFeedbackTag: isConfused ? 'confused' : 'replied',
                studentFeedbackNote: displayStudentNote,
                teacherReaction: res.feedback,
              );
            })
            .toList(growable: false);
        final nextLesson = _replaceActiveTrack(
          latest,
          activeT.copyWith(steps: updatedSteps),
        );
        final nextMap = Map<String, BlackboardLessonRecord>.from(
          ws.blackboardLessonsByQuestionId,
        )..[key] = nextLesson;
        return ws.copyWith(blackboardLessonsByQuestionId: nextMap);
      });

      if (!ref.mounted) return res;
      state = state.copyWith(
        blackboardFeedbackBusy: false,
        copilotLastEmotion: res.emotion,
      );

      if (res.verdict == 'wrong' || res.verdict == 'confused' || isConfused) {
        await _invalidateUnrevealedPrefetchIfNeeded(key);
      }
      return res;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(blackboardFeedbackBusy: false);
      }
    }
  }

  Future<void> markBlackboardStepUnderstood(String stepId) async {
    final key = state.activeBlackboardKey;
    final lesson = state.activeBlackboardLesson;
    final track = lesson?.activeTrack;
    if (lesson == null || track == null) return;

    await _updateActiveWorkspace((ws) {
      final latest = ws.blackboardLessonsByQuestionId[key];
      final activeT = latest?.activeTrack;
      if (latest == null || activeT == null) return ws;
      final updatedSteps = activeT.steps
          .map(
            (s) => s.id == stepId
                ? s.copyWith(studentFeedbackTag: 'understood')
                : s,
          )
          .toList(growable: false);
      final nextMap = Map<String, BlackboardLessonRecord>.from(
        ws.blackboardLessonsByQuestionId,
      )..[key] = _replaceActiveTrack(latest, activeT.copyWith(steps: updatedSteps));
      return ws.copyWith(blackboardLessonsByQuestionId: nextMap);
    });

    if (!ref.mounted) return;
    state = state.copyWith(copilotLastEmotion: MascotEmotion.celebrate);

    final refreshedTrack = state.activeBlackboardLesson?.activeTrack;
    if (refreshedTrack != null &&
        refreshedTrack.currentStep?.id == stepId &&
        refreshedTrack.canStepForward &&
        !state.blackboardStepStreaming) {
      await stepBlackboardForward();
    }
  }

  String? _buildStudentFeedbackSummary(List<BlackboardStep> steps) {
    final lines = <String>[];
    for (final s in steps) {
      final cpSummary = s.checkpoint?.toFeedbackSummary();
      if (cpSummary != null) {
        lines.add('第${s.stepNumber}步 $cpSummary');
      }
      if (s.studentFeedbackTag != null && s.studentFeedbackTag!.isNotEmpty) {
        final note = s.studentFeedbackNote?.trim() ?? '';
        final tagDesc = switch (s.studentFeedbackTag) {
          'understood' => '表示「听懂了」',
          'confused' => '表示「没太懂」',
          _ => '发表了自己的看法',
        };
        lines.add(
          '第${s.stepNumber}步「${s.title}」：学生$tagDesc${note.isNotEmpty ? "（内容：$note）" : ""}',
        );
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  Future<void> _invalidateUnrevealedPrefetchIfNeeded(String key) async {
    final pf = _cancelTokens.remove(_blackboardPrefetchCancelKey);
    if (pf != null && !pf.isCancelled) {
      pf.cancel('feedback_replan');
    }
    _prefetchingStepNumber = null;
    _prefetchLatestPartial = null;

    int? nextStepNum;
    await _updateActiveWorkspace((ws) {
      final latest = ws.blackboardLessonsByQuestionId[key];
      final track = latest?.tracks.firstOrNull;
      if (latest == null || track == null || latest.activeTrackIndex != 0) {
        return ws;
      }
      if (track.steps.length > track.revealedCount) {
        final trimmedSteps = track.steps
            .take(track.revealedCount)
            .toList(growable: false);
        final trimmedTrack = track.copyWith(
          steps: trimmedSteps,
          hasMoreSteps: true,
        );
        nextStepNum = trimmedSteps.length + 1;
        final nextMap = Map<String, BlackboardLessonRecord>.from(
          ws.blackboardLessonsByQuestionId,
        )..[key] = _replaceTrackAt(latest, 0, trimmedTrack);
        return ws.copyWith(blackboardLessonsByQuestionId: nextMap);
      }
      if (track.hasMoreSteps) {
        nextStepNum = track.steps.length + 1;
      }
      return ws;
    });

    if (!ref.mounted || !state.blackboardOpen || nextStepNum == null) return;
    final isRemote =
        state.hasLiveAiKey || ref.read(overrideLlmClientProvider) != null;
    if (isRemote) {
      unawaited(
        _prefetchNextBlackboardStep(
          seq: _blackboardGenSeq,
          key: key,
          stepNumber: nextStepNum!,
        ),
      );
    }
  }

  Future<void> switchBlackboardTrack(int trackIndex) async {
    final lesson = state.activeBlackboardLesson;
    if (lesson == null ||
        trackIndex < 0 ||
        trackIndex >= lesson.tracks.length) {
      return;
    }
    final nextLesson = lesson.copyWith(
      activeTrackIndex: trackIndex,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveBlackboardLesson(state.activeBlackboardKey, nextLesson);
    if (!ref.mounted) return;
    final stepEmo = nextLesson.activeTrack?.currentStep?.emotion;
    if (stepEmo != null) {
      state = state.copyWith(
        copilotLastEmotion: MascotEmotion.fromCode(stepEmo),
      );
    }
  }

  Future<BlackboardAskResult> askBlackboardQuestion({
    required String questionText,
    String? targetStepId,
    Uint8List? compositePng,
    int studentStrokeCount = 0,
    bool requestAlternateMethod = false,
  }) async {
    final lesson = state.activeBlackboardLesson;
    final trimmed = questionText.trim();
    if (lesson == null || trimmed.isEmpty) {
      return const BlackboardAskResult(
        emotion: MascotEmotion.wink,
        spokenReply: '请先输入或圈选你想问的步骤内容哦～',
        usedOfflineFallback: true,
      );
    }

    final track = lesson.activeTrack;
    final targetStep = targetStepId != null
        ? track?.steps.where((s) => s.id == targetStepId).firstOrNull
        : track?.currentStep;
    final boundQ = state.findQuestionById(state.copilotQuestionId);

    state = state.copyWith(blackboardBusy: true);
    try {
      final res = await _tutorService.askOnBlackboard(
        BlackboardAskRequest(
          profile: state.activeProfile,
          userQuestion: trimmed,
          lesson: lesson,
          boundQuestion: boundQ,
          targetStep: targetStep,
          hintLevel: state.copilotHintLevel,
          compositeSnapshotPng: compositePng,
          studentStrokeCount: studentStrokeCount,
          requestAlternateMethod: requestAlternateMethod,
          endpoint: state.hasLiveAiKey ? state.activeEndpoint : null,
          apiKey: state.activeApiKey,
          overrideClient: ref.read(overrideLlmClientProvider),
        ),
      );
      if (!ref.mounted) return res;

      var nextLesson = state.activeBlackboardLesson ?? lesson;
      if (res.alternateTrack != null) {
        final pfToken = _cancelTokens.remove(_blackboardPrefetchCancelKey);
        if (pfToken != null && !pfToken.isCancelled) {
          pfToken.cancel('switched_track');
        }
        _prefetchingStepNumber = null;
        _awaitingStepNumber = null;
        _prefetchLatestPartial = null;
        final newTrack = res.alternateTrack!;
        final existingIdx = nextLesson.tracks.indexWhere(
          (t) => t.id == newTrack.id,
        );
        if (existingIdx >= 0) {
          final updatedTracks = nextLesson.tracks
              .map((t) => t.id == newTrack.id ? newTrack : t)
              .toList(growable: false);
          nextLesson = nextLesson.copyWith(
            tracks: updatedTracks,
            activeTrackIndex: existingIdx,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } else {
          final updatedTracks = [...nextLesson.tracks, newTrack];
          nextLesson = nextLesson.copyWith(
            tracks: updatedTracks,
            activeTrackIndex: updatedTracks.length - 1,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      } else if (res.sideNote != null && nextLesson.activeTrack != null) {
        final note = res.sideNote!;
        final activeTrack = nextLesson.activeTrack!;
        final attachStepId = activeTrack.steps.any(
          (s) => s.id == note.targetStepId,
        )
            ? note.targetStepId
            : (activeTrack.currentStep?.id ?? activeTrack.steps.first.id);
        final nextSteps = activeTrack.steps
            .map((s) {
              if (s.id != attachStepId) return s;
              return s.copyWith(sideNotes: [...s.sideNotes, note]);
            })
            .toList(growable: false);
        final nextDiagram = activeTrack.diagram.addElements(
          note.addedDiagramElements,
        );
        final nextTrack = activeTrack.copyWith(
          steps: nextSteps,
          diagram: nextDiagram,
        );
        nextLesson = _replaceActiveTrack(nextLesson, nextTrack);
      }

      await _saveBlackboardLesson(state.activeBlackboardKey, nextLesson);

      // Sync Q&A to TutorThreadRecord so drawer & blackboard share history
      final thread = state.activeCopilotThread;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _saveCopilotThread(
        thread.copyWith(
          hintLevel: state.copilotHintLevel.index,
          messages: [
            ...thread.messages,
            TutorMessageRecord(
              id: 'tmsg_bb_u_${_uuid.v4().substring(0, 8)}',
              role: 'user',
              content: '[黑板提问] $trimmed',
              createdAtMs: now,
            ),
            TutorMessageRecord(
              id: 'tmsg_bb_a_${_uuid.v4().substring(0, 8)}',
              role: 'assistant',
              content: res.spokenReply,
              emotion: res.emotion.code,
              toolTrace: res.toolTrace
                  .map((t) => t.toDisplayLine())
                  .toList(growable: false),
              antiSpoilerBlocked: res.antiSpoilerBlocked,
              createdAtMs: now + 1,
            ),
          ],
        ),
      );

      if (!ref.mounted) return res;
      state = state.copyWith(
        blackboardBusy: false,
        copilotLastEmotion: res.emotion,
        blackboardLastTraces: res.toolTrace
            .map((t) => t.toDisplayLine())
            .toList(growable: false),
        blackboardAntiSpoilerBlocked: res.antiSpoilerBlocked,
      );
      return res;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(blackboardBusy: false);
      }
    }
  }

  Future<void> saveBlackboardStudentInk(InkPageData page) async {
    final lesson = state.activeBlackboardLesson;
    if (lesson == null) return;
    final nextLesson = lesson.copyWith(
      studentInkData: page.toJson(),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveBlackboardLesson(state.activeBlackboardKey, nextLesson);
  }

  Future<bool> archiveBlackboardToWrongbook() async {
    final lesson = state.activeBlackboardLesson;
    if (lesson == null) return false;
    final noteText = lesson.toMarkdownNote();
    if (noteText.isEmpty) return false;

    final rawQId = lesson.questionId;
    if (rawQId == '__free__') return false;

    var qId = rawQId;
    final existingInBank = state.activeWorkspace.questions.any(
      (q) => q.id == rawQId,
    );
    String? sourceSessionId;
    String? sourceItemId;
    if (!existingInBank) {
      for (final session in state.activeWorkspace.photoSearchHistory) {
        for (final item in session.items) {
          if (item.question.id == rawQId || item.savedQuestionId == rawQId) {
            sourceSessionId = session.id;
            sourceItemId = item.id;
            if (item.savedQuestionId != null &&
                state.activeWorkspace.questions.any(
                  (q) => q.id == item.savedQuestionId,
                )) {
              qId = item.savedQuestionId!;
            } else {
              final savedQ = await savePhotoSearchItemToLibrary(
                session.id,
                item.id,
              );
              if (savedQ != null) {
                qId = savedQ.id;
              }
            }
            break;
          }
        }
        if (sourceItemId != null) break;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _updateActiveWorkspace((ws) {
      final nextWrongs = List<WrongItem>.from(ws.wrongItems);
      final wIdx = nextWrongs.indexWhere((w) => w.questionId == qId);
      String wrongId;
      if (wIdx >= 0) {
        final cur = nextWrongs[wIdx];
        wrongId = cur.id;
        final mergedNote = cur.note.trim().isEmpty
            ? noteText
            : (cur.note.contains('【黑板板书笔记')
                  ? '${cur.note.split('【黑板板书笔记').first.trim()}\n\n$noteText'
                        .trim()
                  : '${cur.note.trim()}\n\n$noteText');
        nextWrongs[wIdx] = cur.copyWith(note: mergedNote);
      } else {
        wrongId = 'w_${_uuid.v4().substring(0, 8)}';
        nextWrongs.insert(
          0,
          WrongItem(
            id: wrongId,
            questionId: qId,
            addedVia: sourceItemId != null
                ? AddedVia.photoSearch
                : AddedVia.manual,
            mastery: MasteryState.newWrong,
            note: noteText,
            addedAtMs: now,
          ),
        );
      }

      var nextHistory = ws.photoSearchHistory;
      if (sourceSessionId != null && sourceItemId != null) {
        nextHistory = ws.photoSearchHistory
            .map((s) {
              if (s.id != sourceSessionId) return s;
              return s.copyWith(
                items: s.items
                    .map(
                      (it) => it.id == sourceItemId
                          ? it.copyWith(
                              savedQuestionId: qId,
                              savedWrongItemId: wrongId,
                            )
                          : it,
                    )
                    .toList(growable: false),
              );
            })
            .toList(growable: false);
      }

      final nextLessons = Map<String, BlackboardLessonRecord>.from(
        ws.blackboardLessonsByQuestionId,
      );
      nextLessons[state.activeBlackboardKey] = lesson.copyWith(
        archivedToWrongbook: true,
        updatedAtMs: now,
      );

      return ws.copyWith(
        wrongItems: nextWrongs,
        photoSearchHistory: nextHistory,
        blackboardLessonsByQuestionId: nextLessons,
      );
    });
    return true;
  }

  BlackboardLessonRecord _replaceActiveTrack(
    BlackboardLessonRecord lesson,
    BlackboardSolutionTrack nextTrack,
  ) {
    final idx = lesson.activeTrackIndex.clamp(0, lesson.tracks.length - 1);
    return _replaceTrackAt(lesson, idx, nextTrack);
  }

  BlackboardLessonRecord _replaceTrackAt(
    BlackboardLessonRecord lesson,
    int trackIndex,
    BlackboardSolutionTrack nextTrack,
  ) {
    final idx = trackIndex.clamp(0, lesson.tracks.length - 1);
    final nextTracks = [
      for (var i = 0; i < lesson.tracks.length; i++)
        i == idx ? nextTrack : lesson.tracks[i],
    ];
    return lesson.copyWith(
      tracks: nextTracks,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _saveBlackboardLesson(
    String key,
    BlackboardLessonRecord lesson,
  ) async {
    await _updateActiveWorkspace((ws) {
      final nextMap = Map<String, BlackboardLessonRecord>.from(
        ws.blackboardLessonsByQuestionId,
      )..[key] = lesson;
      return ws.copyWith(blackboardLessonsByQuestionId: nextMap);
    });
  }

  // ---------------------------------------------------------------------------
  // Settings, Security PIN & `.inou` Backup
  // ---------------------------------------------------------------------------

  Future<void> updatePreferences(AppPreferences prefs) async {
    await _commitSnapshot(state.snapshot.copyWith(preferences: prefs));
  }

  Future<void> setParentPin(String pin) async {
    await _pinService.setPin(pin);
    await _commitSnapshot(
      state.snapshot.copyWith(
        preferences: state.snapshot.preferences.copyWith(
          parentPinEnabled: true,
        ),
      ),
    );
    state = state.copyWith(pinConfigured: true);
  }

  Future<PinCheckResult> verifyParentPin(String candidate) {
    return _pinService.verifyPin(candidate);
  }

  Future<void> clearParentPin() async {
    await _pinService.clearPin();
    await _commitSnapshot(
      state.snapshot.copyWith(
        preferences: state.snapshot.preferences.copyWith(
          parentPinEnabled: false,
        ),
      ),
    );
    state = state.copyWith(pinConfigured: false);
  }

  Uint8List exportBackupArchive() =>
      _backupService.exportArchive(state.snapshot);

  BackupInspectionResult inspectBackupArchive(Uint8List bytes) =>
      _backupService.inspectArchive(bytes);

  Future<void> importBackupArchive(
    Uint8List bytes, {
    required BackupImportMode mode,
  }) async {
    final next = _backupService.importArchive(
      bytes,
      mode: mode,
      current: state.snapshot,
    );
    await _commitSnapshot(next);
  }

  Future<void> resetToCleanWorkspace() async {
    _cancelBlackboardStreams(reason: 'reset');
    cancelPhotoSearch();
    final fresh = WorkspaceSnapshot.clean();
    await _commitSnapshot(fresh);
    state = state.copyWith(
      clearActiveSession: true,
      clearCopilotQuestion: true,
      clearCopilotLasso: true,
      blackboardOpen: false,
      blackboardBusy: false,
      blackboardStepStreaming: false,
      clearStreamingBlackboard: true,
      photoSearchBusy: false,
      photoSearchStageLabel: '',
      clearPhotoSearchError: true,
      clearPhotoSearchImage: true,
      clearActivePhotoSearchSession: true,
      photoSearchSolvingItemIds: const {},
    );
  }
}

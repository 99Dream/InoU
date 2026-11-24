import 'package:meta/meta.dart';

/// Chalk colors rendered on the dark classroom blackboard.
enum ChalkColor {
  white('white', '白粉笔', 0xFFFBF8F1),
  yellow('yellow', '暖杏粉笔', 0xFFFFCFA3),
  pink('pink', '珊瑚粉笔', 0xFFF6B4AE),
  blue('blue', '浅蓝粉笔', 0xFFBCE0F7),
  green('green', '嫩绿粉笔', 0xFFAEE2C2);

  const ChalkColor(this.code, this.label, this.argb);

  final String code;
  final String label;
  final int argb;

  static ChalkColor fromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    return ChalkColor.values.firstWhere(
      (c) => c.code == normalized,
      orElse: () => ChalkColor.white,
    );
  }
}

/// Decorative chalk emphasis marks around or beside a blackboard line.
enum ChalkAnnotationKind {
  none('none', '普通'),
  underline('underline', '重点下划线'),
  box('box', '核心方框'),
  warn('warn', '易错警示'),
  arrow('arrow', '推导箭头');

  const ChalkAnnotationKind(this.code, this.label);

  final String code;
  final String label;

  static ChalkAnnotationKind fromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    return ChalkAnnotationKind.values.firstWhere(
      (k) => k.code == normalized,
      orElse: () => ChalkAnnotationKind.none,
    );
  }
}

/// Single chalk line written inside a [BlackboardStep] or [BlackboardSideNote].
@immutable
class BlackboardLineItem {
  const BlackboardLineItem({
    required this.id,
    required this.text,
    this.latex,
    this.color = ChalkColor.white,
    this.annotation = ChalkAnnotationKind.none,
    this.tag,
  });

  factory BlackboardLineItem.fromJson(Map<String, Object?> json) {
    return BlackboardLineItem(
      id: (json['id'] as String?) ?? 'line',
      text: (json['text'] as String?) ?? '',
      latex: json['latex'] as String?,
      color: ChalkColor.fromCode(json['color'] as String?),
      annotation: ChalkAnnotationKind.fromCode(json['annotation'] as String?),
      tag: json['tag'] as String?,
    );
  }

  final String id;
  final String text;
  final String? latex;
  final ChalkColor color;
  final ChalkAnnotationKind annotation;
  final String? tag;

  BlackboardLineItem copyWith({
    String? id,
    String? text,
    String? latex,
    ChalkColor? color,
    ChalkAnnotationKind? annotation,
    String? tag,
  }) {
    return BlackboardLineItem(
      id: id ?? this.id,
      text: text ?? this.text,
      latex: latex ?? this.latex,
      color: color ?? this.color,
      annotation: annotation ?? this.annotation,
      tag: tag ?? this.tag,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (latex != null && latex!.isNotEmpty) 'latex': latex,
    'color': color.code,
    if (annotation != ChalkAnnotationKind.none) 'annotation': annotation.code,
    if (tag != null && tag!.isNotEmpty) 'tag': tag,
  };
}

/// Supported dynamic blackboard diagram genres.
enum BlackboardDiagramKind {
  none('none', '无示意图'),
  geometry('geometry', '几何图形'),
  functionPlot('function_plot', '函数图像'),
  physicsForce('physics_force', '物理受力/电路');

  const BlackboardDiagramKind(this.code, this.label);

  final String code;
  final String label;

  static BlackboardDiagramKind fromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    return BlackboardDiagramKind.values.firstWhere(
      (k) => k.code == normalized,
      orElse: () => BlackboardDiagramKind.none,
    );
  }
}

/// Normalized `0..100` coordinate vertex used by [BlackboardDiagramElement].
@immutable
class BlackboardDiagramPoint {
  const BlackboardDiagramPoint(this.x, this.y, {this.label});

  factory BlackboardDiagramPoint.fromJson(Object? raw) {
    if (raw is List && raw.length >= 2) {
      return BlackboardDiagramPoint(
        (raw[0] as num?)?.toDouble() ?? 0,
        (raw[1] as num?)?.toDouble() ?? 0,
        label: raw.length > 2 ? raw[2]?.toString() : null,
      );
    }
    if (raw is Map) {
      return BlackboardDiagramPoint(
        (raw['x'] as num?)?.toDouble() ?? 0,
        (raw['y'] as num?)?.toDouble() ?? 0,
        label: raw['label']?.toString(),
      );
    }
    return const BlackboardDiagramPoint(0, 0);
  }

  final double x;
  final double y;
  final String? label;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    if (label != null && label!.isNotEmpty) 'label': label,
  };
}

/// Structured vector graphic element rendered onto the blackboard diagram area.
///
/// Supported [type] values: `point`, `segment`, `polygon`, `circle`, `angle`,
/// `arrow`, `curve`, `axes`, `box`.
@immutable
class BlackboardDiagramElement {
  const BlackboardDiagramElement({
    required this.id,
    required this.type,
    this.points = const [],
    this.label,
    this.color = ChalkColor.white,
    this.dashed = false,
    this.appearAtStepIndex = 0,
    this.highlightOnStepIds = const [],
    this.radius,
  });

  factory BlackboardDiagramElement.fromJson(Map<String, Object?> json) {
    final rawPoints = json['points'] as List<Object?>? ?? const [];
    return BlackboardDiagramElement(
      id: (json['id'] as String?) ?? 'el',
      type: (json['type'] as String?) ?? 'segment',
      points: rawPoints
          .map(BlackboardDiagramPoint.fromJson)
          .toList(growable: false),
      label: json['label'] as String?,
      color: ChalkColor.fromCode(json['color'] as String?),
      dashed: (json['dashed'] as bool?) ?? false,
      appearAtStepIndex: (json['appearAtStepIndex'] as num?)?.toInt() ?? 0,
      highlightOnStepIds:
          (json['highlightOnStepIds'] as List<Object?>? ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
      radius: (json['radius'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String type;
  final List<BlackboardDiagramPoint> points;
  final String? label;
  final ChalkColor color;
  final bool dashed;
  final int appearAtStepIndex;
  final List<String> highlightOnStepIds;
  final double? radius;

  BlackboardDiagramElement copyWith({
    String? id,
    String? type,
    List<BlackboardDiagramPoint>? points,
    String? label,
    ChalkColor? color,
    bool? dashed,
    int? appearAtStepIndex,
    List<String>? highlightOnStepIds,
    double? radius,
  }) {
    return BlackboardDiagramElement(
      id: id ?? this.id,
      type: type ?? this.type,
      points: points ?? this.points,
      label: label ?? this.label,
      color: color ?? this.color,
      dashed: dashed ?? this.dashed,
      appearAtStepIndex: appearAtStepIndex ?? this.appearAtStepIndex,
      highlightOnStepIds: highlightOnStepIds ?? this.highlightOnStepIds,
      radius: radius ?? this.radius,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'points': points.map((p) => p.toJson()).toList(growable: false),
    if (label != null && label!.isNotEmpty) 'label': label,
    'color': color.code,
    if (dashed) 'dashed': dashed,
    'appearAtStepIndex': appearAtStepIndex,
    if (highlightOnStepIds.isNotEmpty) 'highlightOnStepIds': highlightOnStepIds,
    if (radius != null) 'radius': radius,
  };
}

/// Complete diagram blueprint paired with a [BlackboardSolutionTrack].
@immutable
class BlackboardDiagramSpec {
  const BlackboardDiagramSpec({
    this.kind = BlackboardDiagramKind.none,
    this.title = '',
    this.elements = const [],
  });

  factory BlackboardDiagramSpec.fromJson(Map<String, Object?> json) {
    final rawElements = json['elements'] as List<Object?>? ?? const [];
    return BlackboardDiagramSpec(
      kind: BlackboardDiagramKind.fromCode(json['kind'] as String?),
      title: (json['title'] as String?) ?? '',
      elements: rawElements
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => BlackboardDiagramElement.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList(growable: false),
    );
  }

  final BlackboardDiagramKind kind;
  final String title;
  final List<BlackboardDiagramElement> elements;

  bool get isEmpty =>
      kind == BlackboardDiagramKind.none && elements.isEmpty;

  bool get isNotEmpty => !isEmpty;

  BlackboardDiagramSpec addElements(List<BlackboardDiagramElement> extra) {
    if (extra.isEmpty) return this;
    final nextKind = kind == BlackboardDiagramKind.none
        ? BlackboardDiagramKind.geometry
        : kind;
    return BlackboardDiagramSpec(
      kind: nextKind,
      title: title,
      elements: [...elements, ...extra],
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.code,
    'title': title,
    'elements': elements.map((e) => e.toJson()).toList(growable: false),
  };
}

/// Lightweight interactive checkpoint or open-ended try-prompt embedded at a
/// key derivation step.
@immutable
class BlackboardCheckpoint {
  const BlackboardCheckpoint({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    this.encouragement = '太棒了，这一步卡点打通了！',
    this.answeredSelection,
    this.skipped = false,
    this.studentReply,
    this.teacherFeedback,
    this.feedbackVerdict,
    this.expectedHint,
  });

  factory BlackboardCheckpoint.fromJson(Map<String, Object?> json) {
    final opts = (json['options'] as List<Object?>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    final rawCorrect = (json['correctIndex'] as num?)?.toInt() ?? 0;
    final clampedCorrect = opts.isEmpty
        ? 0
        : rawCorrect.clamp(0, opts.length - 1);
    return BlackboardCheckpoint(
      prompt: (json['prompt'] as String?) ?? '请思考下一步的关键方向：',
      options: opts,
      correctIndex: clampedCorrect,
      encouragement:
          (json['encouragement'] as String?) ?? '太棒了，这一步卡点打通了！',
      answeredSelection: (json['answeredSelection'] as num?)?.toInt(),
      skipped: (json['skipped'] as bool?) ?? false,
      studentReply: json['studentReply'] as String?,
      teacherFeedback: json['teacherFeedback'] as String?,
      feedbackVerdict: json['feedbackVerdict'] as String?,
      expectedHint: json['expectedHint'] as String?,
    );
  }

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String encouragement;
  final int? answeredSelection;
  final bool skipped;
  final String? studentReply;
  final String? teacherFeedback;
  final String? feedbackVerdict;
  final String? expectedHint;

  bool get isOpenEnded => options.isEmpty;

  bool get isResolved =>
      skipped ||
      (options.isNotEmpty &&
          answeredSelection != null &&
          answeredSelection == correctIndex) ||
      feedbackVerdict == 'correct' ||
      feedbackVerdict == 'partial';

  String? toFeedbackSummary() {
    if (skipped) {
      return '小提问「$prompt」：学生选择跳过';
    }
    if (options.isNotEmpty &&
        answeredSelection != null &&
        answeredSelection! >= 0 &&
        answeredSelection! < options.length) {
      final chosen = options[answeredSelection!];
      final status = answeredSelection == correctIndex ? '答对了' : '答错了（需针对性澄清）';
      return '小提问「$prompt」：学生选择了「$chosen」（$status）';
    }
    final reply = studentReply?.trim() ?? '';
    if (reply.isNotEmpty || feedbackVerdict != null) {
      final verdictStr = switch (feedbackVerdict) {
        'correct' => '回答准确',
        'partial' => '接近正确',
        'wrong' => '思路有偏差（需耐心纠正）',
        'confused' => '表示没懂/有点懵（需换更通俗的例子解释）',
        _ => '已作答',
      };
      final fb = teacherFeedback?.trim();
      return '互动提问「$prompt」：学生输入「${reply.isEmpty ? "（点击没太懂）" : reply}」，评估=$verdictStr${fb != null && fb.isNotEmpty ? "，老师初步反馈：$fb" : ""}';
    }
    return null;
  }

  BlackboardCheckpoint copyWith({
    int? answeredSelection,
    bool clearSelection = false,
    bool? skipped,
    String? studentReply,
    String? teacherFeedback,
    String? feedbackVerdict,
    String? expectedHint,
    bool clearFeedback = false,
  }) {
    return BlackboardCheckpoint(
      prompt: prompt,
      options: options,
      correctIndex: correctIndex,
      encouragement: encouragement,
      answeredSelection: clearSelection
          ? null
          : (answeredSelection ?? this.answeredSelection),
      skipped: skipped ?? this.skipped,
      studentReply: clearFeedback ? null : (studentReply ?? this.studentReply),
      teacherFeedback: clearFeedback
          ? null
          : (teacherFeedback ?? this.teacherFeedback),
      feedbackVerdict: clearFeedback
          ? null
          : (feedbackVerdict ?? this.feedbackVerdict),
      expectedHint: expectedHint ?? this.expectedHint,
    );
  }

  Map<String, Object?> toJson() => {
    'prompt': prompt,
    'options': options,
    'correctIndex': correctIndex,
    'encouragement': encouragement,
    if (answeredSelection != null) 'answeredSelection': answeredSelection,
    if (skipped) 'skipped': skipped,
    if (studentReply != null && studentReply!.isNotEmpty)
      'studentReply': studentReply,
    if (teacherFeedback != null && teacherFeedback!.isNotEmpty)
      'teacherFeedback': teacherFeedback,
    if (feedbackVerdict != null && feedbackVerdict!.isNotEmpty)
      'feedbackVerdict': feedbackVerdict,
    if (expectedHint != null && expectedHint!.isNotEmpty)
      'expectedHint': expectedHint,
  };
}

/// In-place colored chalk annotation appended directly underneath the step
/// that the student circled or asked about.
@immutable
class BlackboardSideNote {
  const BlackboardSideNote({
    required this.id,
    required this.targetStepId,
    required this.studentQuestion,
    required this.spokenReply,
    this.emotion = 'thinking',
    this.chalkLines = const [],
    this.addedDiagramElements = const [],
    this.createdAtMs = 0,
  });

  factory BlackboardSideNote.fromJson(Map<String, Object?> json) {
    return BlackboardSideNote(
      id: (json['id'] as String?) ?? 'note',
      targetStepId: (json['targetStepId'] as String?) ?? '',
      studentQuestion: (json['studentQuestion'] as String?) ?? '',
      spokenReply: (json['spokenReply'] as String?) ?? '',
      emotion: (json['emotion'] as String?) ?? 'thinking',
      chalkLines: (json['chalkLines'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => BlackboardLineItem.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList(growable: false),
      addedDiagramElements:
          (json['addedDiagramElements'] as List<Object?>? ?? const [])
              .whereType<Map<Object?, Object?>>()
              .map(
                (m) => BlackboardDiagramElement.fromJson(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList(growable: false),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String targetStepId;
  final String studentQuestion;
  final String spokenReply;
  final String emotion;
  final List<BlackboardLineItem> chalkLines;
  final List<BlackboardDiagramElement> addedDiagramElements;
  final int createdAtMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'targetStepId': targetStepId,
    'studentQuestion': studentQuestion,
    'spokenReply': spokenReply,
    'emotion': emotion,
    'chalkLines': chalkLines.map((e) => e.toJson()).toList(growable: false),
    if (addedDiagramElements.isNotEmpty)
      'addedDiagramElements': addedDiagramElements
          .map((e) => e.toJson())
          .toList(growable: false),
    'createdAtMs': createdAtMs,
  };
}

/// Single step written sequentially by the AI teacher on the blackboard.
@immutable
class BlackboardStep {
  const BlackboardStep({
    required this.id,
    required this.stepNumber,
    required this.title,
    required this.spokenText,
    this.emotion = 'happy',
    this.lines = const [],
    this.checkpoint,
    this.sideNotes = const [],
    this.studentFeedbackTag,
    this.studentFeedbackNote,
    this.teacherReaction,
  });

  factory BlackboardStep.fromJson(Map<String, Object?> json) {
    final rawCp = json['checkpoint'];
    return BlackboardStep(
      id: (json['id'] as String?) ?? 'step',
      stepNumber: (json['stepNumber'] as num?)?.toInt() ?? 1,
      title: (json['title'] as String?) ?? '',
      spokenText: (json['spokenText'] as String?) ?? '',
      emotion: (json['emotion'] as String?) ?? 'happy',
      lines: (json['lines'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => BlackboardLineItem.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList(growable: false),
      checkpoint: rawCp is Map<Object?, Object?>
          ? BlackboardCheckpoint.fromJson(
              rawCp.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      sideNotes: (json['sideNotes'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => BlackboardSideNote.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList(growable: false),
      studentFeedbackTag: json['studentFeedbackTag'] as String?,
      studentFeedbackNote: json['studentFeedbackNote'] as String?,
      teacherReaction: json['teacherReaction'] as String?,
    );
  }

  final String id;
  final int stepNumber;
  final String title;
  final String spokenText;
  final String emotion;
  final List<BlackboardLineItem> lines;
  final BlackboardCheckpoint? checkpoint;
  final List<BlackboardSideNote> sideNotes;
  final String? studentFeedbackTag;
  final String? studentFeedbackNote;
  final String? teacherReaction;

  BlackboardStep copyWith({
    String? title,
    String? spokenText,
    String? emotion,
    List<BlackboardLineItem>? lines,
    BlackboardCheckpoint? checkpoint,
    List<BlackboardSideNote>? sideNotes,
    String? studentFeedbackTag,
    String? studentFeedbackNote,
    String? teacherReaction,
  }) {
    return BlackboardStep(
      id: id,
      stepNumber: stepNumber,
      title: title ?? this.title,
      spokenText: spokenText ?? this.spokenText,
      emotion: emotion ?? this.emotion,
      lines: lines ?? this.lines,
      checkpoint: checkpoint ?? this.checkpoint,
      sideNotes: sideNotes ?? this.sideNotes,
      studentFeedbackTag: studentFeedbackTag ?? this.studentFeedbackTag,
      studentFeedbackNote: studentFeedbackNote ?? this.studentFeedbackNote,
      teacherReaction: teacherReaction ?? this.teacherReaction,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'stepNumber': stepNumber,
    'title': title,
    'spokenText': spokenText,
    'emotion': emotion,
    'lines': lines.map((l) => l.toJson()).toList(growable: false),
    if (checkpoint != null) 'checkpoint': checkpoint!.toJson(),
    if (sideNotes.isNotEmpty)
      'sideNotes': sideNotes.map((n) => n.toJson()).toList(growable: false),
    if (studentFeedbackTag != null && studentFeedbackTag!.isNotEmpty)
      'studentFeedbackTag': studentFeedbackTag,
    if (studentFeedbackNote != null && studentFeedbackNote!.isNotEmpty)
      'studentFeedbackNote': studentFeedbackNote,
    if (teacherReaction != null && teacherReaction!.isNotEmpty)
      'teacherReaction': teacherReaction,
  };
}

/// Complete solution track (e.g. "解法一：常规推导" or "解法二：数形结合").
@immutable
class BlackboardSolutionTrack {
  const BlackboardSolutionTrack({
    required this.id,
    required this.label,
    this.diagram = const BlackboardDiagramSpec(),
    this.steps = const [],
    this.revealedCount = 1,
    this.takeaway = '',
    this.hasMoreSteps = false,
    this.plannedTotalSteps,
  });

  factory BlackboardSolutionTrack.fromJson(Map<String, Object?> json) {
    final rawDiag = json['diagram'];
    final rawSteps = (json['steps'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (m) => BlackboardStep.fromJson(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
    final rawRevealed = (json['revealedCount'] as num?)?.toInt() ?? 1;
    final clampedRevealed = rawSteps.isEmpty
        ? 0
        : rawRevealed.clamp(1, rawSteps.length);
    return BlackboardSolutionTrack(
      id: (json['id'] as String?) ?? 'track_1',
      label: (json['label'] as String?) ?? '解法一',
      diagram: rawDiag is Map<Object?, Object?>
          ? BlackboardDiagramSpec.fromJson(
              rawDiag.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const BlackboardDiagramSpec(),
      steps: rawSteps,
      revealedCount: clampedRevealed,
      takeaway: (json['takeaway'] as String?) ?? '',
      hasMoreSteps: (json['hasMoreSteps'] as bool?) ?? false,
      plannedTotalSteps: (json['plannedTotalSteps'] as num?)?.toInt(),
    );
  }

  final String id;
  final String label;
  final BlackboardDiagramSpec diagram;
  final List<BlackboardStep> steps;
  final int revealedCount;
  final String takeaway;
  final bool hasMoreSteps;
  final int? plannedTotalSteps;

  int get displayTotalSteps =>
      (plannedTotalSteps != null && plannedTotalSteps! > steps.length)
      ? plannedTotalSteps!
      : steps.length;

  List<BlackboardStep> get visibleSteps =>
      steps.take(revealedCount.clamp(0, steps.length)).toList(growable: false);

  BlackboardStep? get currentStep =>
      visibleSteps.isEmpty ? null : visibleSteps.last;

  bool get canStepForward => revealedCount < steps.length || hasMoreSteps;
  bool get canStepBackward => revealedCount > 1;

  BlackboardSolutionTrack copyWith({
    String? label,
    BlackboardDiagramSpec? diagram,
    List<BlackboardStep>? steps,
    int? revealedCount,
    String? takeaway,
    bool? hasMoreSteps,
    int? plannedTotalSteps,
    bool clearPlannedTotalSteps = false,
  }) {
    final nextSteps = steps ?? this.steps;
    final nextRevealed = nextSteps.isEmpty
        ? 0
        : (revealedCount ?? this.revealedCount).clamp(1, nextSteps.length);
    return BlackboardSolutionTrack(
      id: id,
      label: label ?? this.label,
      diagram: diagram ?? this.diagram,
      steps: nextSteps,
      revealedCount: nextRevealed,
      takeaway: takeaway ?? this.takeaway,
      hasMoreSteps: hasMoreSteps ?? this.hasMoreSteps,
      plannedTotalSteps: clearPlannedTotalSteps
          ? null
          : (plannedTotalSteps ?? this.plannedTotalSteps),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'diagram': diagram.toJson(),
    'steps': steps.map((s) => s.toJson()).toList(growable: false),
    'revealedCount': revealedCount,
    if (takeaway.isNotEmpty) 'takeaway': takeaway,
    if (hasMoreSteps) 'hasMoreSteps': hasMoreSteps,
    if (plannedTotalSteps != null) 'plannedTotalSteps': plannedTotalSteps,
  };
}

/// Persistent interactive blackboard lesson bound to a question (or free-ask).
@immutable
class BlackboardLessonRecord {
  const BlackboardLessonRecord({
    required this.id,
    required this.questionId,
    this.questionTitle = '',
    this.hintLevel = 1,
    this.tracks = const [],
    this.activeTrackIndex = 0,
    this.studentInkData,
    this.archivedToWrongbook = false,
    this.updatedAtMs = 0,
  });

  factory BlackboardLessonRecord.fromJson(Map<String, Object?> json) {
    final rawTracks = (json['tracks'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (m) => BlackboardSolutionTrack.fromJson(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(growable: false);
    final rawInk = json['studentInkData'];
    final rawIdx = (json['activeTrackIndex'] as num?)?.toInt() ?? 0;
    return BlackboardLessonRecord(
      id: (json['id'] as String?) ?? 'bb_lesson',
      questionId: (json['questionId'] as String?) ?? '__free__',
      questionTitle: (json['questionTitle'] as String?) ?? '',
      hintLevel: (json['hintLevel'] as num?)?.toInt() ?? 1,
      tracks: rawTracks,
      activeTrackIndex: rawTracks.isEmpty
          ? 0
          : rawIdx.clamp(0, rawTracks.length - 1),
      studentInkData: rawInk is Map<Object?, Object?>
          ? rawInk.map((k, v) => MapEntry(k.toString(), v))
          : null,
      archivedToWrongbook: (json['archivedToWrongbook'] as bool?) ?? false,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String questionId;
  final String questionTitle;
  final int hintLevel;
  final List<BlackboardSolutionTrack> tracks;
  final int activeTrackIndex;
  final Map<String, Object?>? studentInkData;
  final bool archivedToWrongbook;
  final int updatedAtMs;

  BlackboardSolutionTrack? get activeTrack => tracks.isEmpty
      ? null
      : tracks[activeTrackIndex.clamp(0, tracks.length - 1)];

  BlackboardLessonRecord copyWith({
    String? questionTitle,
    int? hintLevel,
    List<BlackboardSolutionTrack>? tracks,
    int? activeTrackIndex,
    Map<String, Object?>? studentInkData,
    bool clearStudentInk = false,
    bool? archivedToWrongbook,
    int? updatedAtMs,
  }) {
    final nextTracks = tracks ?? this.tracks;
    final nextIdx = nextTracks.isEmpty
        ? 0
        : (activeTrackIndex ?? this.activeTrackIndex).clamp(
            0,
            nextTracks.length - 1,
          );
    return BlackboardLessonRecord(
      id: id,
      questionId: questionId,
      questionTitle: questionTitle ?? this.questionTitle,
      hintLevel: hintLevel ?? this.hintLevel,
      tracks: nextTracks,
      activeTrackIndex: nextIdx,
      studentInkData: clearStudentInk
          ? null
          : (studentInkData ?? this.studentInkData),
      archivedToWrongbook: archivedToWrongbook ?? this.archivedToWrongbook,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  /// Formats the active blackboard track and any in-place side-notes into a
  /// concise structured note suitable for saving into [WrongItem.note].
  String toMarkdownNote() {
    final track = activeTrack;
    if (track == null) return '';
    final buf = StringBuffer();
    buf.writeln('【黑板板书笔记 · ${track.label}】');
    for (final step in track.visibleSteps) {
      buf.writeln('${step.stepNumber}. ${step.title}');
      for (final line in step.lines) {
        final tag = (line.tag != null && line.tag!.isNotEmpty)
            ? '[${line.tag}] '
            : '';
        final formula = (line.latex != null && line.latex!.isNotEmpty)
            ? ' \$${line.latex}\$'
            : '';
        buf.writeln('  - $tag${line.text}$formula');
      }
      for (final note in step.sideNotes) {
        buf.writeln('  ↳ 追问「${note.studentQuestion}」：${note.spokenReply}');
        for (final nl in note.chalkLines) {
          final nf = (nl.latex != null && nl.latex!.isNotEmpty)
              ? ' \$${nl.latex}\$'
              : '';
          buf.writeln('    · ${nl.text}$nf');
        }
      }
    }
    if (track.takeaway.isNotEmpty) {
      buf.writeln('核心避坑：${track.takeaway}');
    }
    return buf.toString().trim();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'questionId': questionId,
    'questionTitle': questionTitle,
    'hintLevel': hintLevel,
    'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
    'activeTrackIndex': activeTrackIndex,
    if (studentInkData != null) 'studentInkData': studentInkData,
    if (archivedToWrongbook) 'archivedToWrongbook': archivedToWrongbook,
    'updatedAtMs': updatedAtMs,
  };
}

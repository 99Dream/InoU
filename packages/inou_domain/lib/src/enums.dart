/// Question structural kinds supported by InoU protocol (schema v1).
enum QuestionKind {
  choice('choice', '选择题'),
  fill('fill', '填空题'),
  match('match', '连线题'),
  classify('classify', '分类题'),
  response('response', '简答题'),
  group('group', '组合阅读题'),
  solve('solve', '解答题'),
  draw('draw', '作图题'),
  spatial('spatial', '看图标注'),
  write('write', '书写题');

  const QuestionKind(this.code, this.label);

  final String code;
  final String label;

  static QuestionKind fromCode(String code) {
    return QuestionKind.values.firstWhere(
      (k) => k.code == code,
      orElse: () => throw FormatException('Unknown QuestionKind: $code'),
    );
  }
}

/// Origin & trust level of a question's reference answer.
enum AnswerSource {
  paper('paper', '卷面答案'),
  ai('ai', 'AI 生成 · 待核对'),
  aiVerified('ai_verified', 'AI 生成 · 已自检'),
  user('user', '人工已核对');

  const AnswerSource(this.code, this.label);

  final String code;
  final String label;

  static AnswerSource fromCode(String code) {
    return AnswerSource.values.firstWhere(
      (s) => s.code == code,
      orElse: () => throw FormatException('Unknown AnswerSource: $code'),
    );
  }
}

/// Question difficulty levels.
enum Difficulty {
  basic('basic', '基础'),
  normal('normal', '普通'),
  advanced('advanced', '拓展');

  const Difficulty(this.code, this.label);

  final String code;
  final String label;

  static Difficulty fromCode(String code) {
    return Difficulty.values.firstWhere(
      (d) => d.code == code,
      orElse: () => throw FormatException('Unknown Difficulty: $code'),
    );
  }
}

/// Student educational stages.
enum StudyStage {
  primary('p', '小学'),
  middle('m', '初中'),
  high('h', '高中');

  const StudyStage(this.code, this.label);

  final String code;
  final String label;

  static StudyStage fromCode(String code) {
    return StudyStage.values.firstWhere(
      (s) => s.code == code,
      orElse: () => StudyStage.middle,
    );
  }
}

/// Mastery progression states for wrong-book items.
enum MasteryState {
  newWrong('new', '新错'),
  learning('learning', '学习中'),
  reviewing('reviewing', '复习中'),
  mastered('mastered', '已掌握');

  const MasteryState(this.code, this.label);

  final String code;
  final String label;

  static MasteryState fromCode(String code) {
    return MasteryState.values.firstWhere(
      (m) => m.code == code,
      orElse: () => MasteryState.newWrong,
    );
  }
}

/// Attempt grading verdicts.
enum Verdict {
  correct('correct', '正确'),
  partial('partial', '部分对'),
  wrong('wrong', '错误'),
  skipped('skipped', '跳过'),
  unreadable('unreadable', '难以辨认'),
  ungraded('ungraded', '待批改');

  const Verdict(this.code, this.label);

  final String code;
  final String label;

  static Verdict fromCode(String code) {
    return Verdict.values.firstWhere(
      (v) => v.code == code,
      orElse: () => Verdict.ungraded,
    );
  }
}

/// Who issued the verdict for an attempt.
enum JudgedBy {
  auto('auto'),
  ai('ai'),
  self('self'),
  user('user');

  const JudgedBy(this.code);
  final String code;

  static JudgedBy fromCode(String code) {
    return JudgedBy.values.firstWhere(
      (j) => j.code == code,
      orElse: () => JudgedBy.auto,
    );
  }
}

/// Dual practice input modes.
enum InputMode {
  standard('standard', '常规数字化模式'),
  paper('paper', '手写纸质模式');

  const InputMode(this.code, this.label);

  final String code;
  final String label;

  static InputMode fromCode(String code) {
    return InputMode.values.firstWhere(
      (m) => m.code == code,
      orElse: () => InputMode.standard,
    );
  }
}

/// Standard error attribution tags.
enum ErrorTag {
  calc('calc', '计算错误'),
  careless('careless', '粗心'),
  concept('concept', '概念不清'),
  misread('misread', '审题偏差'),
  method('method', '方法不当'),
  writing('writing', '书写不规范'),
  other('other', '其他');

  const ErrorTag(this.code, this.label);

  final String code;
  final String label;

  static ErrorTag fromCode(String code) {
    return ErrorTag.values.firstWhere(
      (e) => e.code == code,
      orElse: () => ErrorTag.other,
    );
  }
}

enum PracticeKind {
  exam('exam'),
  custom('custom'),
  redo('redo'),
  single('single'),
  generated('generated');

  const PracticeKind(this.code);
  final String code;

  static PracticeKind fromCode(String code) {
    return PracticeKind.values.firstWhere(
      (p) => p.code == code,
      orElse: () => PracticeKind.custom,
    );
  }
}

enum FeedbackTiming {
  instant('instant'),
  afterSubmit('after_submit');

  const FeedbackTiming(this.code);
  final String code;

  static FeedbackTiming fromCode(String code) {
    return FeedbackTiming.values.firstWhere(
      (f) => f.code == code,
      orElse: () => FeedbackTiming.afterSubmit,
    );
  }
}

enum AddedVia {
  photoMarked('photo_marked'),
  photoSearch('photo_search'),
  practice('practice'),
  manual('manual');

  const AddedVia(this.code);
  final String code;

  static AddedVia fromCode(String code) {
    return AddedVia.values.firstWhere(
      (a) => a.code == code,
      orElse: () => AddedVia.manual,
    );
  }
}

enum WrongBookCollectMode {
  ask('ask', '询问加入'),
  auto('auto', '自动收录');

  const WrongBookCollectMode(this.code, this.label);

  final String code;
  final String label;

  static WrongBookCollectMode fromCode(String code) {
    return WrongBookCollectMode.values.firstWhere(
      (w) => w.code == code,
      orElse: () => WrongBookCollectMode.ask,
    );
  }
}

/// Common Chinese K12 subject metadata helper.
abstract final class SubjectCatalog {
  static const String autoCode = 'auto';

  static const Map<String, String> labels = <String, String>{
    'chn': '语文',
    'math': '数学',
    'eng': '英语',
    'phy': '物理',
    'chem': '化学',
    'bio': '生物',
    'hist': '历史',
    'geo': '地理',
    'pol': '道德与法治',
    'other': '其他',
  };

  static const Map<String, String> _aliases = <String, String>{
    'chn': 'chn',
    'chinese': 'chn',
    '语文': 'chn',
    'math': 'math',
    'mathematics': 'math',
    'maths': 'math',
    '数学': 'math',
    'eng': 'eng',
    'english': 'eng',
    '英语': 'eng',
    '英文': 'eng',
    '外语': 'eng',
    'phy': 'phy',
    'physics': 'phy',
    '物理': 'phy',
    'chem': 'chem',
    'chemistry': 'chem',
    '化学': 'chem',
    'bio': 'bio',
    'biology': 'bio',
    '生物': 'bio',
    'hist': 'hist',
    'history': 'hist',
    '历史': 'hist',
    'geo': 'geo',
    'geography': 'geo',
    '地理': 'geo',
    'pol': 'pol',
    'politics': 'pol',
    'morality': 'pol',
    '道德与法治': 'pol',
    '政治': 'pol',
    '道法': 'pol',
    '思政': 'pol',
    'other': 'other',
    '其他': 'other',
  };

  static String labelOf(String code) {
    if (code == autoCode) return '自动识别';
    return labels[code] ?? code;
  }

  /// Parses a canonical code, English alias, or Chinese subject label into a
  /// canonical subject code (`chn`..`other`). Returns `null` for `'auto'` or
  /// unrecognized strings.
  static String? tryParseCode(String? raw) {
    if (raw == null) return null;
    final key = raw.trim().toLowerCase();
    if (key.isEmpty || key == autoCode) return null;
    if (_aliases.containsKey(key)) return _aliases[key];
    for (final entry in _aliases.entries) {
      if (key.contains(entry.key) && entry.key.length >= 2) {
        return entry.value;
      }
    }
    return null;
  }

  static String normalize(String? raw, {String fallback = 'math'}) =>
      tryParseCode(raw) ?? fallback;
}

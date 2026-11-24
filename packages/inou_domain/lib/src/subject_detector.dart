import 'package:meta/meta.dart';

import 'content_block.dart';
import 'content_plain_text.dart';
import 'enums.dart';
import 'question_models.dart';

/// Output of content-based K12 subject detection.
@immutable
class SubjectDetectionResult {
  const SubjectDetectionResult({
    required this.subject,
    required this.confidence,
    this.matchedSignals = const [],
    this.scores = const {},
  });

  final String subject;
  final double confidence;
  final List<String> matchedSignals;
  final Map<String, int> scores;

  bool get isStrong => confidence >= 0.65;
}

/// Content-based classifier that infers the canonical K12 subject code
/// (`chn`, `math`, `eng`, `phy`, `chem`, `bio`, `hist`, `geo`, `pol`, `other`)
/// from question text, options, and explanations so mislabeled default subjects
/// (e.g., an English question captured under default "math") are routed to the
/// right subject automatically.
abstract final class SubjectDetector {
  static const Map<String, Map<String, int>> _keywordWeights = {
    'eng': {
      '完形填空': 6,
      '阅读理解': 5,
      '语法填空': 6,
      '短文改错': 6,
      '书面表达': 5,
      '英译汉': 6,
      '汉译英': 6,
      '首字母填空': 6,
      '选词填空': 4,
      '音标': 5,
      '划线部分发音': 6,
      '单项选择': 4,
      '一般过去时': 5,
      '一般现在时': 5,
      '现在进行时': 5,
      '现在完成时': 5,
      '被动语态': 5,
      '宾语从句': 5,
      '定语从句': 5,
      '状语从句': 5,
      '动词不定式': 5,
      '非谓语动词': 5,
      '时态': 4,
      '介词': 4,
      '冠词': 4,
      '连词': 3,
      '英语': 5,
      'according to the passage': 6,
      'choose the best': 6,
      'underlined word': 6,
      'which of the following is true': 5,
      'complete the sentence': 5,
      'excuse me': 4,
    },
    'math': {
      '勾股定理': 6,
      '一元一次方程': 6,
      '一元二次方程': 6,
      '二元一次方程': 6,
      '不等式': 5,
      '二次函数': 6,
      '一次函数': 6,
      '反比例函数': 6,
      '因式分解': 6,
      '直角三角形': 5,
      '等腰三角形': 5,
      '等边三角形': 5,
      '全等三角形': 6,
      '相似三角形': 6,
      '平行四边形': 5,
      '平面直角坐标系': 6,
      '坐标系': 4,
      '斜率': 5,
      '对称轴': 4,
      '抛物线': 5,
      '平方根': 5,
      '立方根': 5,
      '实数根': 6,
      '有理数': 5,
      '无理数': 5,
      '质数': 5,
      '合数': 5,
      '公约数': 5,
      '公倍数': 5,
      '韦达定理': 6,
      '正弦': 5,
      '余弦': 5,
      '正切': 5,
      '圆心角': 5,
      '圆周角': 5,
      '切线': 4,
      '方差': 4,
      '中位数': 4,
      '众数': 4,
      '导数': 5,
      '积分': 5,
      '向量': 4,
      '数列': 5,
      '概率': 4,
      '方程': 4,
      '三角形': 4,
      '函数': 4,
      '斜边': 4,
      '直角边': 4,
      '求值': 4,
      '化简': 4,
      '几何': 4,
      '代数': 4,
      '数学': 5,
    },
    'phy': {
      '牛顿第一定律': 6,
      '牛顿第二定律': 6,
      '受力分析': 6,
      '摩擦力': 5,
      '浮力': 5,
      '阿基米德': 5,
      '压强': 5,
      '大气压': 5,
      '加速度': 5,
      '匀变速': 6,
      '匀速直线': 5,
      '动能定理': 6,
      '机械能': 5,
      '势能': 5,
      '比热容': 6,
      '欧姆定律': 6,
      '电磁感应': 6,
      '安培': 5,
      '电路图': 6,
      '串联': 5,
      '并联': 5,
      '电阻': 5,
      '电流': 4,
      '电压': 4,
      '电功率': 5,
      '千瓦时': 5,
      '凸透镜': 6,
      '凹透镜': 6,
      '滑轮组': 6,
      '杠杆平衡': 6,
      '折射率': 5,
      '磁场': 4,
      '磁感线': 5,
      '重力': 4,
      '物理': 5,
    },
    'chem': {
      '化学方程式': 6,
      '化学式': 5,
      '化合价': 6,
      '离子方程式': 6,
      '物质的量': 6,
      '摩尔质量': 6,
      '氧化还原': 6,
      '复分解反应': 6,
      '置换反应': 6,
      '中和反应': 6,
      '催化剂': 5,
      '饱和溶液': 5,
      '溶质质量分数': 6,
      '溶解度': 5,
      '高锰酸钾': 6,
      '稀盐酸': 6,
      '氢氧化钠': 6,
      '碳酸钙': 6,
      '硫酸铜': 6,
      '二氧化硫': 5,
      '二氧化碳': 4,
      '酸碱指示剂': 6,
      '石蕊': 5,
      '酚酞': 5,
      '元素周期表': 6,
      '最外层电子': 6,
      '化学': 5,
    },
    'bio': {
      '光合作用': 6,
      '呼吸作用': 6,
      '蒸腾作用': 6,
      '线粒体': 6,
      '叶绿体': 6,
      '细胞核': 5,
      '细胞膜': 5,
      '细胞壁': 5,
      '有丝分裂': 6,
      '减数分裂': 6,
      'dna': 5,
      'rna': 5,
      '染色体': 5,
      '孟德尔': 6,
      '反射弧': 6,
      '神经元': 5,
      '食物链': 5,
      '生态系统': 5,
      '显微镜': 4,
      '基因': 4,
      '生物': 5,
    },
    'chn': {
      '文言文': 6,
      '古诗词': 6,
      '古诗': 5,
      '没有语病': 6,
      '语病': 5,
      '成语': 5,
      '修辞手法': 6,
      '比喻': 4,
      '拟人': 4,
      '排比': 4,
      '加点字': 6,
      '字音': 5,
      '拼音': 5,
      '错别字': 6,
      '通假字': 6,
      '默写': 5,
      '中心思想': 5,
      '思想感情': 5,
      '记叙文': 5,
      '议论文': 5,
      '散文': 4,
      '词句赏析': 5,
      '语文': 5,
    },
    'hist': {
      '辛亥革命': 6,
      '五四运动': 6,
      '洋务运动': 6,
      '戊戌变法': 6,
      '明治维新': 6,
      '文艺复兴': 6,
      '启蒙运动': 6,
      '工业革命': 6,
      '改革开放': 5,
      '不平等条约': 6,
      '南京条约': 6,
      '马关条约': 6,
      '秦始皇': 5,
      '汉武帝': 5,
      '唐太宗': 5,
      '朝代': 4,
      '历史意义': 5,
      '公元前': 4,
      '历史': 5,
    },
    'geo': {
      '经纬度': 6,
      '经线': 5,
      '纬线': 5,
      '等高线': 6,
      '季风气候': 6,
      '洋流': 5,
      '板块构造': 6,
      '喀斯特地貌': 6,
      '水循环': 5,
      '太阳直射点': 6,
      '昼夜长短': 5,
      '人口密度': 5,
      '城市化': 4,
      '降水量': 4,
      '地理': 5,
    },
    'pol': {
      '道德与法治': 6,
      '社会主义核心价值观': 6,
      '人民代表大会': 6,
      '依法治国': 6,
      '宪法': 5,
      '公民权利': 5,
      '公民义务': 5,
      '未成年人保护': 6,
      '政治': 5,
    },
  };

  static const Set<String> _englishFunctionWords = {
    'the',
    'is',
    'are',
    'am',
    'was',
    'were',
    'be',
    'been',
    'being',
    'have',
    'has',
    'had',
    'do',
    'does',
    'did',
    'will',
    'would',
    'can',
    'could',
    'may',
    'might',
    'must',
    'shall',
    'should',
    'to',
    'of',
    'in',
    'on',
    'at',
    'for',
    'with',
    'from',
    'by',
    'about',
    'into',
    'after',
    'before',
    'that',
    'this',
    'these',
    'those',
    'which',
    'what',
    'who',
    'whom',
    'whose',
    'when',
    'where',
    'why',
    'how',
    'and',
    'or',
    'but',
    'because',
    'although',
    'if',
    'unless',
    'not',
    'very',
    'much',
    'many',
    'some',
    'any',
    'you',
    'your',
    'we',
    'our',
    'they',
    'their',
    'them',
    'he',
    'his',
    'him',
    'she',
    'her',
    'it',
    'its',
    'my',
    'me',
    'yesterday',
    'tomorrow',
    'today',
    'please',
    'look',
    'read',
    'passage',
    'choose',
    'answer',
    'sentence',
    'following',
  };

  static const Set<String> _nonEnglishAbbrevTokens = {
    'sin',
    'cos',
    'tan',
    'cot',
    'sec',
    'csc',
    'log',
    'ln',
    'lg',
    'lim',
    'mod',
    'max',
    'min',
    'sqrt',
    'frac',
    'sum',
    'int',
    'det',
    'cm',
    'mm',
    'dm',
    'km',
    'kg',
    'mg',
    'ml',
    'kv',
    'ma',
    'pa',
    'hz',
    'nm',
    'mol',
    'ph',
    'kwh',
    'dna',
    'rna',
    'atp',
    'vs',
    'rt',
    'ab',
    'bc',
    'ac',
    'cd',
    'ad',
    'ef',
    'oa',
    'ob',
    'oc',
  };

  static final RegExp _latexCmd = RegExp(r'\\[a-zA-Z]+');
  static final RegExp _optPrefix = RegExp(r'(?:^|\s)[A-Fa-f][\.、\):：]\s*');
  static final RegExp _englishWord = RegExp(r'\b[A-Za-z]{2,}\b');
  static final RegExp _mathSymbolic = RegExp(
    r'([∠△⊙⊥∥√±×÷≤≥≠≈]|x²|x\^2|\\frac|\\sqrt|\b\d*[xyz]\s*[\+\-\*=])',
  );
  static final RegExp _chemFormula = RegExp(
    r'\b(H2O|CO2|O2|H2|N2|SO2|H2SO4|HCl|NaOH|NaCl|CaCO3|CuSO4|Fe2O3|NH3|CH4|pH)\b',
  );
  static final RegExp _physicsUnit = RegExp(
    r'(\bm/s²?|\bkm/h|\bkWh|\d+\s*[ΩAVWNJ]\b|\d+\s*(?:Pa|Hz|kg|g/cm))',
  );

  /// Classifies [text] into the most likely canonical K12 subject code.
  static SubjectDetectionResult detect(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SubjectDetectionResult(subject: 'other', confidence: 0.0);
    }

    final lower = trimmed.toLowerCase();
    final scores = <String, int>{};
    final signals = <String, List<String>>{};

    for (final entry in _keywordWeights.entries) {
      final subj = entry.key;
      var score = 0;
      final hits = <String>[];
      for (final kw in entry.value.entries) {
        if (lower.contains(kw.key)) {
          score += kw.value;
          hits.add(kw.key);
        }
      }
      if (score > 0) {
        scores[subj] = score;
        signals[subj] = hits;
      }
    }

    if (_mathSymbolic.hasMatch(trimmed)) {
      final matches = _mathSymbolic.allMatches(trimmed).length;
      final boost = matches >= 2 ? 6 : 3;
      scores['math'] = (scores['math'] ?? 0) + boost;
      (signals['math'] ??= []).add('数学符号/代数表达式');
    }

    if (_chemFormula.hasMatch(trimmed)) {
      final matches = _chemFormula.allMatches(trimmed).length;
      scores['chem'] = (scores['chem'] ?? 0) + (matches >= 2 ? 7 : 5);
      (signals['chem'] ??= []).add('化学式');
    }

    if (_physicsUnit.hasMatch(trimmed)) {
      final matches = _physicsUnit.allMatches(trimmed).length;
      scores['phy'] = (scores['phy'] ?? 0) + (matches >= 2 ? 6 : 4);
      (signals['phy'] ??= []).add('物理量纲/单位');
    }

    // Prose English word analysis (after removing LaTeX commands & option prefixes)
    final cleanedForEnglish = trimmed
        .replaceAll(_latexCmd, ' ')
        .replaceAll(_optPrefix, ' ')
        .replaceAll(_chemFormula, ' ');
    final engWords = _englishWord
        .allMatches(cleanedForEnglish)
        .map((m) => m.group(0)!)
        .where((w) => !_nonEnglishAbbrevTokens.contains(w.toLowerCase()))
        .toList();

    final stopHits = engWords
        .where((w) => _englishFunctionWords.contains(w.toLowerCase()))
        .length;

    if (engWords.length >= 4 && stopHits >= 2) {
      final engBoost = engWords.length >= 10
          ? (6 + (stopHits >= 4 ? 6 : 3))
          : (stopHits >= 3 ? 8 : 5);
      scores['eng'] = (scores['eng'] ?? 0) + engBoost;
      (signals['eng'] ??= []).add('英文句段与常用词(${engWords.length})');
    } else if (engWords.length >= 8 && stopHits >= 1) {
      scores['eng'] = (scores['eng'] ?? 0) + 6;
      (signals['eng'] ??= []).add('较多英文词汇(${engWords.length})');
    }

    if (scores.isEmpty) {
      return const SubjectDetectionResult(subject: 'other', confidence: 0.0);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final secondScore = ranked.length > 1 ? ranked[1].value : 0;
    final margin = top.value - secondScore;

    // Normalize into 0.0..1.0 confidence based on strength + lead margin.
    final baseConf = (top.value / 10.0).clamp(0.35, 0.92);
    final marginFactor = top.value == 0
        ? 0.0
        : (0.65 + 0.35 * (margin / top.value)).clamp(0.5, 1.0);
    final conf = (baseConf * marginFactor).clamp(0.0, 0.99);

    return SubjectDetectionResult(
      subject: top.key,
      confidence: conf,
      matchedSignals: signals[top.key] ?? const [],
      scores: scores,
    );
  }

  /// Resolves the best canonical subject code for [text].
  ///
  /// - When [preferredSubject] is `'auto'` / `null` / empty, detects purely from
  ///   [text], falling back to `'other'` if no subject cue matches.
  /// - When [allowOverrideDefault] is `true` (e.g. caller fell back to a
  ///   default `'math'` instead of locking a subject manually), strong evidence
  ///   of another subject overrides the default automatically unless [text]
  ///   also strongly supports [preferredSubject].
  static String resolveSubjectForText(
    String text, {
    String? preferredSubject,
    bool allowOverrideDefault = true,
  }) {
    final trimmedPref = preferredSubject?.trim();
    final explicit =
        (trimmedPref == null ||
            trimmedPref.isEmpty ||
            trimmedPref == SubjectCatalog.autoCode)
        ? null
        : SubjectCatalog.tryParseCode(trimmedPref);

    final det = detect(text);
    if (explicit == null) {
      return det.confidence >= 0.35 ? det.subject : 'other';
    }
    if (!allowOverrideDefault) return explicit;

    if (det.subject != explicit && det.isStrong) {
      final prefScore = det.scores[explicit] ?? 0;
      final topScore = det.scores[det.subject] ?? 0;
      if (prefScore < 4 && prefScore < topScore * 0.45) {
        return det.subject;
      }
    }
    return explicit;
  }

  /// Concatenates human-readable searchable text from a [Question].
  static String searchableTextOfQuestion(Question q) {
    final buf = StringBuffer()
      ..writeln(q.header.title)
      ..writeln(q.plainText);
    final rawOpts = q.body['options'];
    if (rawOpts is List) {
      for (final o in rawOpts) {
        if (o is Map && o['content'] is List) {
          final blocks = (o['content'] as List)
              .whereType<Map<Object?, Object?>>()
              .map(
                (m) => ContentBlock.fromJson(
                  m.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList();
          buf.writeln(ContentTextUtils.extractPlainText(blocks));
        }
      }
    }
    if (q.explanation.isNotEmpty) {
      buf.writeln(ContentTextUtils.extractPlainText(q.explanation));
    }
    return buf.toString();
  }
}

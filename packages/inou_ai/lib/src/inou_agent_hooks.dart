import 'package:dart_agent_core/dart_agent_core.dart';

/// Socratic hint disclosure level while solving a question in practice mode.
enum HintLevel { none, l1Concept, l2KeyStep, l3FullSolution }

/// Reserved tool names governed by InoU agent hooks.
abstract final class InouToolNames {
  static const String readQuestionPublic = 'read_question_public';
  static const String readQuestionAnswer = 'read_question_answer';
}

/// Physically prevents the tutor agent from accessing standard answers or
/// explanations during L1/L2 progressive hinting, both by hiding the answer
/// tool before model invocation and denying execution if invoked anyway.
class AntiSpoilerHook extends AgentHook {
  AntiSpoilerHook({required this.hintLevelProvider});

  final HintLevel Function() hintLevelProvider;

  bool get _isRestricted {
    final level = hintLevelProvider();
    return level == HintLevel.l1Concept || level == HintLevel.l2KeyStep;
  }

  @override
  ModelCallHookResult beforeModelCall(ModelCallHookContext context) {
    if (!_isRestricted) {
      return ModelCallHookResult.proceed(request: context.request);
    }
    final filtered = context.request.tools
        .where((tool) => tool.name != InouToolNames.readQuestionAnswer)
        .toList(growable: false);
    if (filtered.length == context.request.tools.length) {
      return ModelCallHookResult.proceed(request: context.request);
    }
    return ModelCallHookResult.proceed(
      request: context.request.copyWith(tools: filtered),
      changed: true,
    );
  }

  @override
  ToolCallHookResult beforeToolCall(ToolCallHookContext context) {
    if (_isRestricted &&
        context.call.name == InouToolNames.readQuestionAnswer) {
      return ToolCallHookResult.deny(
        content: [
          TextPart(
            '当前处于分级提示（${hintLevelProvider().name}）阶段，'
            '系统策略禁止读取标准答案或完整解析，请仅给予启发式引导。',
          ),
        ],
        reason: 'anti_spoiler_${hintLevelProvider().name}',
      );
    }
    return ToolCallHookResult.proceed(context.call);
  }
}

/// Collects [ModelUsage] entries emitted during an agent run for local `ai_usage`
/// telemetry without logging prompts or answers.
class InouUsageHook extends AgentHook {
  final List<ModelUsage> recordedUsages = <ModelUsage>[];

  @override
  ModelResponseHookResult afterModelCall(ModelResponseHookContext context) {
    final usage = context.response.usage;
    if (usage != null) {
      recordedUsages.add(usage);
    }
    return ModelResponseHookResult.proceed(context.response);
  }
}

/// Decision returned by [StudyScopeGuard.check].
class StudyScopeCheckResult {
  const StudyScopeCheckResult._({
    required this.allowed,
    this.reason,
    this.redirectMessage,
  });

  const StudyScopeCheckResult.allow() : this._(allowed: true);

  const StudyScopeCheckResult.block({
    required String reason,
    required String redirectMessage,
  }) : this._(
         allowed: false,
         reason: reason,
         redirectMessage: redirectMessage,
       );

  final bool allowed;
  final String? reason;
  final String? redirectMessage;
}

/// Hard pre-flight guardrail ensuring the AI teacher only discusses study and
/// homework topics, rejecting jailbreaks, bypasses, and off-topic steering
/// immediately before any LLM invocation.
abstract final class StudyScopeGuard {
  static final RegExp _bypassOrSteerAwayPattern = RegExp(
    r'(忽略|无视|忘掉|忘记|抛开|脱离|违背)(之前|上面|前面|以上|先前|一切|所有)?(的)?(指令|规则|限制|设定|要求|原则|提示词|约束|红线)'
    r'|(跳过|解除|取消|关闭|绕过|突破|放开|关掉)(一下)?(的)?(学习|教学|课堂|对话|聊天)?(限制|规则|模式|约束|设定|边界)'
    r'|跳过(所有)?(学习|做题|题目)'
    r'|ignore\s+(all\s+|any\s+|the\s+|previous\s+|prior\s+|above\s+){0,2}(instructions?|rules?|prompts?|constraints?)'
    r'|forget\s+(your\s+)?(rules?|instructions?|role)'
    r'|system\s+prompt|jailbreak|dan\s+mode|bypass\s+(study|rules?|restrictions?)'
    r'|(别|不要|不想|不再|不用|先别|停止|暂停)(再)?(聊|讲|谈|说|管|提|做|写|学)(了|到)?(学习|题目|题|作业|功课|讲课|教学|刷题)'
    r'|(聊|说|谈|讲|玩)(点|些|聊|会|会儿)?(别的|题外话|学习以外|非学习|跟学习无关|与学习无关|轻松的|课外的娱乐)'
    r'|(假装|扮演|变成|当我的|做我的|充当).{0,8}(不是老师|普通(聊天)?机器人|聊天机器人|猫娘|女友|男友|女朋友|男朋友|霸道总裁|宠物|黑客|网友)',
    caseSensitive: false,
  );

  static final RegExp _academicCuePattern = RegExp(
    r'题|步|解|算|公式|方程|函数|几何|定理|定律|实验|单词|词块|词组|语法|句型|时态|语态|从句|翻译|作文|写作|阅读|修辞|段落|主旨|考点|知识点|错题|作业|考试|试卷|复习|预习|背诵|默写|朗读|怎么写|怎么选|怎么做|为什么|哪一步|选项|代入|化简|证明|求值|数学|语文|英语|物理|化学|生物|历史|地理|道法|政治|文言文|古诗|课本|课文|笔记|黑板|板书|解析|提示|换种解法|解法二|没懂|不懂|卡住|听懂|思路|推导|批改|辅助线',
    caseSensitive: false,
  );

  static final RegExp _offTopicPattern = RegExp(
    r'王者荣耀|原神|和平精英|吃鸡|英雄联盟|\bLOL\b|我的世界|蛋仔派对|第五人格|崩坏|绝区零|无畏契约|三角洲|金铲铲|打游戏|玩游戏|开黑|上分|抽卡|游戏攻略|通关攻略|买皮肤|手游推荐|游戏推荐|陪我打'
    r'|追星|明星八卦|吃瓜八卦|聊八卦|明星绯闻|爱豆|综艺节目|刷抖音|刷快手|刷B站|番剧推荐|动漫推荐|电影推荐|电视剧推荐|小说推荐|好看的(电影|电视剧|动漫|小说|综艺)|霸总小说|言情小说|爽文|网文推荐|推荐.{0,6}(电影|电视剧|动漫|番剧|小说|游戏|手游|综艺|游戏机)'
    r'|谈恋爱|表白话术|写情书|网恋|处cp|撩妹|撩汉|做我女朋友|做我男朋友|抱抱我|亲亲我|叫我老公|叫我老婆'
    r'|讲个笑话|讲一个笑话|讲笑话|讲个段子|讲段子|讲鬼故事|陪我闲聊|随便聊聊|无聊陪我聊|找你闲聊|算命|占卜|塔罗牌|星座运势|生肖运势|买彩票|炒股|股票推荐|基金推荐|加密货币|比特币|推荐外卖|中午吃什么|晚饭吃什么|晚上吃什么|点什么外卖|穿搭推荐|化妆教程|旅游攻略|明天天气|今天天气|天气怎么样',
    caseSensitive: false,
  );

  static StudyScopeCheckResult check({
    required String userText,
    String? boundQuestionText,
    String? boundQuestionTitle,
    String displayName = '诺诺学姐',
  }) {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      return const StudyScopeCheckResult.allow();
    }

    if (_bypassOrSteerAwayPattern.hasMatch(trimmed)) {
      return StudyScopeCheckResult.block(
        reason: 'bypass_or_steer_away',
        redirectMessage: _buildRedirectMessage(
          displayName: displayName,
          boundQuestionTitle: boundQuestionTitle,
        ),
      );
    }

    final offMatch = _offTopicPattern.firstMatch(trimmed);
    if (offMatch != null) {
      final matchedPhrase = offMatch.group(0) ?? '';
      final stemLower = (boundQuestionText ?? '').toLowerCase();
      final appearsInBoundStem =
          matchedPhrase.isNotEmpty &&
          stemLower.isNotEmpty &&
          stemLower.contains(matchedPhrase.toLowerCase());
      if (!appearsInBoundStem && !_academicCuePattern.hasMatch(trimmed)) {
        return StudyScopeCheckResult.block(
          reason: 'off_topic:$matchedPhrase',
          redirectMessage: _buildRedirectMessage(
            displayName: displayName,
            boundQuestionTitle: boundQuestionTitle,
          ),
        );
      }
    }

    return const StudyScopeCheckResult.allow();
  }

  static String _buildRedirectMessage({
    required String displayName,
    String? boundQuestionTitle,
  }) {
    final title = boundQuestionTitle?.trim() ?? '';
    if (title.isNotEmpty) {
      return '我是你的专属学习老师「$displayName」，课堂上只聊学习相关内容，不能跳过或偏离学习哦～'
          '我们先把眼前这道「$title」弄明白吧！你对哪一步有疑问，或者想从哪里开始拆解？';
    }
    return '我是你的专属学习老师「$displayName」，只能陪伴你讨论学科知识、解题思路和学习方法，不能聊学习以外的话题哦～'
        '直接发一道卡住的题目，或者告诉我你想复习哪个知识点，我们马上开始！';
  }
}

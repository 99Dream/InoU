import 'package:inou_domain/inou_domain.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  final nowMs = DateTime(2026, 11, 23, 10, 0).millisecondsSinceEpoch;

  group('Question & StudentResponse protocol', () {
    test('all seeded questions cover all 10 kinds and validate cleanly', () {
      final qs = InouSeedData.defaultQuestions(nowMs);
      final coveredKinds = qs.map((q) => q.kind).toSet();
      expect(coveredKinds, containsAll(QuestionKind.values));

      for (final q in qs) {
        final issues = validateQuestionEnvelope(q);
        expect(issues, isEmpty, reason: 'Question ${q.id} had issues: $issues');

        final roundtrip = Question.fromJson(q.toJson());
        expect(roundtrip.id, q.id);
        expect(roundtrip.kind, q.kind);
        expect(roundtrip.plainText.isNotEmpty, isTrue);

        final pubJson = q.toPublicView().toJson();
        expect(pubJson.containsKey('grading'), isFalse);
        expect(pubJson.containsKey('explanation'), isFalse);
      }
    });

    test('StudentResponse sealed roundtrips across all types', () {
      final responses = <StudentResponse>[
        const ChoiceResponse(
          questionId: 'q1',
          inputMode: InputMode.standard,
          selectedIds: ['A'],
        ),
        const FillResponse(
          questionId: 'q2',
          inputMode: InputMode.standard,
          textEntries: {'s1': '0.5'},
        ),
        const MatchResponse(
          questionId: 'q3',
          inputMode: InputMode.standard,
          pairs: {'L1': 'R3'},
        ),
        const ClassifyResponse(
          questionId: 'q4',
          inputMode: InputMode.standard,
          placements: {'i1': 'pure'},
        ),
        const TextResponse(
          questionId: 'q5',
          inputMode: InputMode.standard,
          parts: {'p1': '答案文本'},
        ),
        const SolveResponse(
          questionId: 'q6',
          inputMode: InputMode.paper,
          steps: ['(x-2)(x-3)=0'],
          inkRegionId: 'reg_1',
        ),
        const DrawResponse(
          questionId: 'q7',
          inputMode: InputMode.paper,
          inkRegionId: 'reg_draw',
        ),
        const SpatialResponse(
          questionId: 'q8',
          inputMode: InputMode.standard,
          points: [(0.15, 0.2)],
          placements: {'lb_wall': 't1'},
        ),
        const WriteResponse(
          questionId: 'q9',
          inputMode: InputMode.standard,
          cells: {'c1': '清脆'},
        ),
      ];

      final groupResp = GroupResponse(
        questionId: 'qg',
        inputMode: InputMode.standard,
        children: {'q1': responses.first},
      );

      for (final r in [...responses, groupResp]) {
        final decoded = StudentResponse.fromJson(r.toJson());
        expect(decoded.type, r.type);
        expect(decoded.questionId, r.questionId);
      }
    });
  });

  group('Validators', () {
    test(
      'detects invalid LaTeX braces, dangling option refs, and nested groups',
      () {
        final base = InouSeedData.defaultQuestions(nowMs).first;
        final badLatex = base.copyWith(
          prompt: const [MathBlock(r'\frac{1}{2')],
        );
        expect(
          validateQuestionEnvelope(badLatex).map((i) => i.code),
          contains('invalid_latex'),
        );

        final danglingAns = base.copyWith(
          grading: const {
            'mode': 'exact',
            'maxScore': 3,
            'answerSets': [
              {
                'id': 'a1',
                'expected': {
                  'selectedIds': ['E'],
                },
              },
            ],
          },
        );
        expect(
          validateQuestionEnvelope(danglingAns).map((i) => i.code),
          contains('dangling_option_ref'),
        );
      },
    );
  });

  group('GradingEngine', () {
    const grader = GradingEngine();

    test('grades choice, fill numeric equivalence, match, classify, spatial, and group', () {
      final qs = InouSeedData.defaultQuestions(nowMs);
      final qById = {for (final q in qs) q.id: q};

      // Choice
      final cOk = grader.grade(
        qById['q_choice_quad']!,
        const ChoiceResponse(
          questionId: 'q_choice_quad',
          inputMode: InputMode.standard,
          selectedIds: ['A'],
        ),
      );
      expect(cOk.verdict, Verdict.correct);
      expect(cOk.score, 3);

      // Fill: 2 and 0.5 == 1/2
      final fOk = grader.grade(
        qById['q_fill_sqrt']!,
        const FillResponse(
          questionId: 'q_fill_sqrt',
          inputMode: InputMode.standard,
          textEntries: {'s1': '２', 's2': '1/2'},
        ),
      );
      expect(fOk.verdict, Verdict.correct);
      expect(fOk.score, 4);

      // Match partial (2/3)
      final mPartial = grader.grade(
        qById['q_match_phy']!,
        const MatchResponse(
          questionId: 'q_match_phy',
          inputMode: InputMode.standard,
          pairs: {'L1': 'R3', 'L2': 'R1', 'L3': 'R1'},
        ),
      );
      expect(mPartial.verdict, Verdict.partial);
      expect(mPartial.score, 2);

      // Classify all 4 correct
      final clsOk = grader.grade(
        qById['q_classify_chem']!,
        const ClassifyResponse(
          questionId: 'q_classify_chem',
          inputMode: InputMode.standard,
          placements: {'i1': 'pure', 'i2': 'mix', 'i3': 'pure', 'i4': 'mix'},
        ),
      );
      expect(clsOk.verdict, Verdict.correct);

      // Group recursive aggregate (1 right, 1 wrong => partial 2/4)
      final grpPart = grader.grade(
        qById['q_group_eng']!,
        const GroupResponse(
          questionId: 'q_group_eng',
          inputMode: InputMode.standard,
          children: {
            'q_group_eng_1': ChoiceResponse(
              questionId: 'q_group_eng_1',
              inputMode: InputMode.standard,
              selectedIds: ['B'],
            ),
            'q_group_eng_2': FillResponse(
              questionId: 'q_group_eng_2',
              inputMode: InputMode.standard,
              textEntries: {'s1': 'wrong'},
            ),
          },
        ),
      );
      expect(grpPart.verdict, Verdict.partial);
      expect(grpPart.score, 2);

      // Solve escalates to AI
      final solveOut = grader.grade(
        qById['q_solve_discriminant']!,
        const SolveResponse(
          questionId: 'q_solve_discriminant',
          inputMode: InputMode.paper,
          inkRegionId: 'reg_1',
        ),
      );
      expect(solveOut.needsAi, isTrue);
    });
  });

  group('MasteryService & WeaknessAnalyzer & SimHash', () {
    test(
      'mastery progresses new -> learning -> reviewing -> mastered at N=3',
      () {
        const service = MasteryService();
        var item = WrongItem(
          id: 'wb_1',
          questionId: 'q1',
          addedVia: AddedVia.practice,
          addedAtMs: nowMs,
        );

        for (final expected in [
          MasteryState.learning,
          MasteryState.reviewing,
          MasteryState.mastered,
        ]) {
          final out = service.recordAttempt(
            existing: item,
            questionId: 'q1',
            verdict: Verdict.correct,
            nowMs: nowMs + 1000,
            collectMode: WrongBookCollectMode.auto,
            myAnswerSummary: 'A',
          );
          item = out.item!;
          expect(item.mastery, expected);
        }
        expect(item.correctStreak, 3);

        // Wrong again resets streak back to learning
        final relapsed = service.recordAttempt(
          existing: item,
          questionId: 'q1',
          verdict: Verdict.wrong,
          nowMs: nowMs + 2000,
          collectMode: WrongBookCollectMode.auto,
          myAnswerSummary: 'B',
        );
        expect(relapsed.item!.mastery, MasteryState.learning);
        expect(relapsed.item!.correctStreak, 0);
      },
    );

    test(
      'WeaknessAnalyzer ranks weakest leaf KP highest and rolls up parents',
      () {
        const analyzer = WeaknessAnalyzer();
        final qs = InouSeedData.defaultQuestions(nowMs);
        final attempts = InouSeedData.defaultAttempts(nowMs);
        final wrongs = InouSeedData.defaultWrongItems(nowMs);
        const nodes = [
          KnowledgeNode(
            id: 'math.m.02',
            parentId: 'math.m',
            subject: 'math',
            stage: 'm',
            name: '方程与不等式',
            level: 1,
            isLeaf: false,
            sort: 1,
          ),
          KnowledgeNode(
            id: 'math.m.02.03.02',
            parentId: 'math.m.02',
            subject: 'math',
            stage: 'm',
            name: '因式分解法解一元二次方程',
            level: 3,
            isLeaf: true,
            sort: 1,
          ),
        ];

        final snapshot = analyzer.analyze(
          questions: qs,
          attempts: attempts,
          wrongItems: wrongs,
          kpNodes: nodes,
          nowMs: nowMs,
        );

        expect(snapshot.rankedWeakLeaves, isNotEmpty);
        expect(
          snapshot.allNodeStats['math.m.02']!.unmasteredCount,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test('SimHash detects near-duplicate questions', () {
      expect(
        ContentTextUtils.isLikelyDuplicate(
          '已知方程 x² - 5x + 6 = 0，则 x 的值为（ ）。',
          '已知方程 x² - 5x + 6 = 0 ，则 x 的值是（ ）',
        ),
        isTrue,
      );
      expect(
        ContentTextUtils.isLikelyDuplicate(
          '已知方程 x² - 5x + 6 = 0，求 x 的值。',
          '甲乙两地相距360km，快车每小时行80km，求相遇时间。',
        ),
        isFalse,
      );
    });

    test('WeaknessAnalyzer returns empty metrics when workspace is clean', () {
      const analyzer = WeaknessAnalyzer();
      final empty = analyzer.analyze(
        questions: const [],
        attempts: const [],
        wrongItems: const [],
        kpNodes: const [],
        nowMs: nowMs,
      );
      expect(empty.subjectMasteryPercent, isEmpty);
      expect(empty.rankedWeakLeaves, isEmpty);
      expect(empty.weeklyTrend.every((p) => p.attemptCount == 0), isTrue);
      expect(empty.weeklyTrend.every((p) => p.accuracyPercent == 0), isTrue);
    });

    test(
      'QuestionSchemaCatalog provides schema specs and guides for all kinds',
      () {
        for (final kind in QuestionKind.values) {
          final spec = QuestionSchemaCatalog.specFor(kind);
          expect(spec.kind, kind);
          expect(spec.generationGuide, isNotEmpty);
          final jsonStr = QuestionSchemaCatalog.formattedSkeletonJson(kind);
          expect(jsonStr, contains('"kind": "${kind.code}"'));
        }
        final guide = QuestionSchemaCatalog.promptGuideForKinds(const [
          QuestionKind.match,
          QuestionKind.classify,
        ]);
        expect(guide, contains('kind="match"'));
        expect(guide, contains('kind="classify"'));
      },
    );

    test(
      'StructuredQuestionTextParser parses JSONL, choice options, and blanks',
      () {
        const jsonl = '''
{"question":{"kind":"choice","header":{"title":"勾股定理判断"},"prompt":[{"type":"text","text":"下列各组数中能构成直角三角形三边的是（ ）。"}],"body":{"options":[{"id":"A","content":[{"type":"text","text":"2, 3, 4"}]},{"id":"B","content":[{"type":"text","text":"3, 4, 5"}]}]},"grading":{"mode":"exact","answerSets":[{"id":"ans-1","expected":{"selectedIds":["B"]}}]}}}
{"question":{"kind":"fill","header":{"title":"平方差公式"},"prompt":[{"type":"text","text":"(a+b)(a-b) = "},{"type":"slot","slotId":"s1"}],"body":{"slots":[{"id":"s1"}]},"grading":{"mode":"exact","answerSets":[{"id":"ans-1","expected":{"entries":[{"slotId":"s1","acceptedValues":[{"type":"text","text":"a^2-b^2"}]}]}}]}}}
''';
        final parsedJsonl = StructuredQuestionTextParser.tryParseJsonOrJsonl(
          jsonl,
          subject: 'math',
          grade: 'g8',
        );
        expect(parsedJsonl, isNotNull);
        expect(parsedJsonl!.length, 2);
        expect(parsedJsonl[0].kind, QuestionKind.choice);
        expect(parsedJsonl[1].kind, QuestionKind.fill);

        const rawChoice = '''
1. 方程 x² - 9 = 0 的正实数根是（ ）。
A. 2
B. 3
C. 4
D. 9
答案：B
解析：x² = 9，正根为 3。
''';
        final choiceQ = StructuredQuestionTextParser.parseTextChunk(
          rawChoice,
          id: 'q_c',
          index: 0,
          subject: 'math',
          grade: 'g8',
          timestampMs: nowMs,
        );
        expect(choiceQ.kind, QuestionKind.choice);
        expect(choiceQ.body['options'], hasLength(4));
        expect(choiceQ.explanation.first, isA<TextBlock>());
        final ansSets = choiceQ.grading['answerSets'] as List<Object?>;
        final expected = (ansSets.first! as Map)['expected'] as Map;
        expect(expected['selectedIds'], ['B']);

        const rawFill = '''
2. 直角边分别为 3 和 4 时，斜边长为 ____。
答案：5
解析：由勾股定理得 5。
''';
        final fillQ = StructuredQuestionTextParser.parseTextChunk(
          rawFill,
          id: 'q_f',
          index: 1,
          subject: 'math',
          grade: 'g8',
          timestampMs: nowMs,
        );
        expect(fillQ.kind, QuestionKind.fill);
        expect(fillQ.prompt.whereType<SlotBlock>(), isNotEmpty);
      },
    );

    test('SubjectDetector & SubjectCatalog accurately classify English/Physics/Chemistry/Chinese even when default subject is math', () {
      expect(SubjectCatalog.tryParseCode('英语'), 'eng');
      expect(SubjectCatalog.tryParseCode('English'), 'eng');
      expect(SubjectCatalog.tryParseCode('道德与法治'), 'pol');
      expect(SubjectCatalog.tryParseCode('auto'), isNull);

      const engQuestion = '''
1. — Excuse me, could you tell me how to get to the museum?
— Go along this street and turn left at the second crossing.
A. Where is it
B. How to get
C. When did you go
D. What is this
答案：B
''';
      final engParsed = StructuredQuestionTextParser.parseTextChunk(
        engQuestion,
        id: 'q_eng_1',
        index: 1,
        subject: 'math', // default fallback should be overridden cleanly
        grade: 'g8',
        timestampMs: nowMs,
      );
      expect(engParsed.meta.subject, 'eng');

      // Explicit user lock should still be respected when requested
      final lockedParsed = StructuredQuestionTextParser.parseTextChunk(
        engQuestion,
        id: 'q_eng_locked',
        index: 2,
        subject: 'eng',
        grade: 'g8',
        timestampMs: nowMs,
        lockSubject: true,
      );
      expect(lockedParsed.meta.subject, 'eng');

      // Math with LaTeX commands & variable letters must NOT misclassify as English
      const latexMath = r'已知函数 $f(x) = \frac{1}{2}x^2 - 3x + 4$，求其在直角坐标系中的最小值。';
      expect(SubjectDetector.detect(latexMath).subject, 'math');

      expect(
        SubjectDetector.detect('一个质量为 2kg 的物体在 10N 的水平恒力作用下产生加速度，求摩擦力。')
            .subject,
        'phy',
      );
      expect(
        SubjectDetector.detect('实验室用 CaCO3 与稀盐酸反应制取 CO2，写出该化学方程式。').subject,
        'chem',
      );
      expect(SubjectDetector.detect('下列句子中没有语病且加点字读音完全正确的一项是？').subject, 'chn');
    });

    test('SequenceQuestionDetector & StructuredQuestionTextParser accurately recognize sorting questions instead of misclassifying as response/solve', () {
      const gradingEngine = GradingEngine();

      // 1. Circled-number Chinese sentence ordering -> fill.sequence (排序题)
      const cnSeq = '''
1. 把下列句子排列成通顺的一段话：
① 春风吹绿了柳梢。
② 燕子从南方飞回来了。
③ 冰雪融化，小河唱起了歌。
答案：③①②
''';
      final parsedCn = StructuredQuestionTextParser.parseTextChunk(
        cnSeq,
        id: 'q_seq_cn',
        index: 1,
        grade: 'g5',
        timestampMs: nowMs,
      );
      expect(parsedCn.kind, QuestionKind.fill);
      expect(parsedCn.isSequence, isTrue);
      expect(parsedCn.displayKindLabel, '排序题');
      expect(parsedCn.presentation.interaction, 'fill.sequence');
      expect(parsedCn.body['bank'], hasLength(3));

      final gradeCn = gradingEngine.grade(
        parsedCn,
        FillResponse(
          questionId: parsedCn.id,
          inputMode: InputMode.standard,
          itemEntries: const {
            's1': ['w3', 'w1', 'w2'],
          },
        ),
      );
      expect(gradeCn.verdict, Verdict.correct);

      // 2. English scrambled sentence (连词成句) -> eng + fill.sequence
      const enSeq = '''
2. 连词成句：you / how / are / ?
答案：How are you?
''';
      final parsedEn = StructuredQuestionTextParser.parseTextChunk(
        enSeq,
        id: 'q_seq_en',
        index: 2,
        grade: 'g7',
        timestampMs: nowMs,
      );
      expect(parsedEn.meta.subject, 'eng');
      expect(parsedEn.kind, QuestionKind.fill);
      expect(parsedEn.isSequence, isTrue);
      expect(parsedEn.displayKindLabel, '排序题');
      expect(parsedEn.body['bank'], hasLength(4));

      final gradeEn = gradingEngine.grade(
        parsedEn,
        FillResponse(
          questionId: parsedEn.id,
          inputMode: InputMode.standard,
          itemEntries: const {
            's1': ['w2', 'w3', 'w1', 'w4'],
          },
        ),
      );
      expect(gradeEn.verdict, Verdict.correct);

      // 3. Rescue AI-mislabeled `response` JSON back into `fill.sequence`
      final mislabeled = Question.coerceFromAiMap({
        'kind': 'response',
        'header': {'title': '连词成句'},
        'prompt': '连词成句：going / am / I / home / .',
        'answer': 'I am going home.',
        'meta': {'subject': 'eng'},
      });
      final rescued = SequenceQuestionDetector.tryRescueAsSequence(mislabeled);
      expect(rescued, isNotNull);
      expect(rescued!.kind, QuestionKind.fill);
      expect(rescued.presentation.interaction, 'fill.sequence');
      expect(rescued.displayKindLabel, '排序题');
      expect(rescued.body['bank'], hasLength(5));

      // 4. Preserve real MCQ sorting questions (`A. ③①②④ B. ③②①④`) as choice
      const mcqSeq = '''
3. 下列句子排列顺序最恰当的一项是（ ）
① 春风吹过田野 ② 冰雪渐渐融化
A. ①②
B. ②①
答案：B
''';
      final parsedMcq = StructuredQuestionTextParser.parseTextChunk(
        mcqSeq,
        id: 'q_mcq_seq',
        index: 3,
        grade: 'g8',
        timestampMs: nowMs,
      );
      expect(parsedMcq.kind, QuestionKind.choice);

      // 5. Genuine open-ended short answer stays response (简答题)
      final openEnded = Question.coerceFromAiMap({
        'kind': 'response',
        'header': {'title': '主旨概括'},
        'prompt': '请结合全文简要分析作者表达了怎样的思想感情？',
        'meta': {'subject': 'chn'},
      });
      expect(SequenceQuestionDetector.tryRescueAsSequence(openEnded), isNull);
      expect(openEnded.kind, QuestionKind.response);

      // 6. Real-exam multi-line English scramble without colon before word bank
      const realExamSeq = '''
23. 连词成句。
Mark和家人去参观博物馆，在展台前，工作人员告诉大家禁止使用闪光灯。请你将下面的单词连成句子，帮助工作人员表达吧！
flash   the   in   museum   No   .
''';
      final realParsed = StructuredQuestionTextParser.parseTextChunk(
        realExamSeq,
        id: 'q_real_23',
        index: 23,
        grade: 'g6',
        timestampMs: nowMs,
      );
      expect(realParsed.meta.subject, 'eng');
      expect(realParsed.kind, QuestionKind.fill);
      expect(realParsed.isSequence, isTrue);
      expect(realParsed.displayKindLabel, '排序题');
      expect(realParsed.body['bank'], hasLength(6));
    });
  });

  group('BlackboardLessonRecord & DiagramSpec', () {
    test('roundtrips JSON and formats revealed steps to Markdown note', () {
      const lesson = BlackboardLessonRecord(
        id: 'bb_1',
        questionId: 'q_geo_1',
        questionTitle: '勾股定理求解',
        hintLevel: 3,
        activeTrackIndex: 0,
        archivedToWrongbook: true,
        updatedAtMs: 123456,
        tracks: [
          BlackboardSolutionTrack(
            id: 'track_1',
            label: '解法一：常规推导',
            revealedCount: 1,
            takeaway: '记住斜边永远最长。',
            diagram: BlackboardDiagramSpec(
              kind: BlackboardDiagramKind.geometry,
              title: '直角三角形',
              elements: [
                BlackboardDiagramElement(
                  id: 'el_1',
                  type: 'polygon',
                  points: [
                    BlackboardDiagramPoint(20, 80, label: 'C'),
                    BlackboardDiagramPoint(80, 80, label: 'B'),
                    BlackboardDiagramPoint(20, 20, label: 'A'),
                  ],
                  color: ChalkColor.white,
                  appearAtStepIndex: 0,
                  highlightOnStepIds: ['step_1'],
                ),
                BlackboardDiagramElement(
                  id: 'el_2',
                  type: 'segment',
                  points: [
                    BlackboardDiagramPoint(20, 80),
                    BlackboardDiagramPoint(50, 50),
                  ],
                  label: '高 CD',
                  color: ChalkColor.yellow,
                  dashed: true,
                  appearAtStepIndex: 1,
                ),
              ],
            ),
            steps: [
              BlackboardStep(
                id: 'step_1',
                stepNumber: 1,
                title: '确定直角边',
                spokenText: '先标出两条直角边 a=3, b=4。',
                emotion: 'thinking',
                lines: [
                  BlackboardLineItem(
                    id: 'l1',
                    tag: '已知',
                    text: '两直角边长',
                    latex: 'a=3, b=4',
                    color: ChalkColor.yellow,
                    annotation: ChalkAnnotationKind.underline,
                  ),
                ],
                checkpoint: BlackboardCheckpoint(
                  prompt: '哪条是斜边？',
                  options: ['AB', 'AC'],
                  correctIndex: 0,
                  answeredSelection: 0,
                ),
                sideNotes: [
                  BlackboardSideNote(
                    id: 'sn_1',
                    targetStepId: 'step_1',
                    studentQuestion: '为什么选 AB？',
                    spokenReply: '因为直角 ∠C 对着斜边 AB。',
                    chalkLines: [
                      BlackboardLineItem(
                        id: 'nl_1',
                        text: '直角所对的边为斜边',
                        color: ChalkColor.blue,
                        annotation: ChalkAnnotationKind.arrow,
                      ),
                    ],
                  ),
                ],
              ),
              BlackboardStep(
                id: 'step_2',
                stepNumber: 2,
                title: '隐藏的下一步',
                spokenText: '求出 c=5。',
                lines: [
                  BlackboardLineItem(
                    id: 'l2',
                    text: '隐藏答案 c=5',
                    color: ChalkColor.green,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final decoded = BlackboardLessonRecord.fromJson(lesson.toJson());
      expect(decoded.id, 'bb_1');
      expect(decoded.tracks, hasLength(1));
      expect(decoded.activeTrack!.diagram.kind, BlackboardDiagramKind.geometry);
      expect(decoded.activeTrack!.diagram.elements, hasLength(2));
      expect(decoded.activeTrack!.steps.first.sideNotes, hasLength(1));
      expect(decoded.activeTrack!.steps.first.checkpoint!.isResolved, isTrue);

      final md = decoded.toMarkdownNote();
      expect(md, contains('确定直角边'));
      expect(md, contains('为什么选 AB？'));
      expect(md, contains('核心避坑：记住斜边永远最长。'));
      // Unrevealed step 2 must not be exported
      expect(md, isNot(contains('隐藏答案 c=5')));
    });
  });

  group('InouDiagnosticsLogger', () {
    test('enforces ring-buffer capacity, counters, listeners, and clear', () {
      final logger = InouDiagnosticsLogger(maxEntries: 5);
      var notifications = 0;
      void onUpdate() => notifications++;
      logger.addListener(onUpdate);

      logger.info('Boot', 'entry 1');
      logger.error('LLM', 'err 2');
      logger.warn('UI', 'warn 3');
      logger.info('Boot', 'entry 4');
      logger.error('LLM', 'err 5');
      logger.warn('UI', 'warn 6');
      logger.error('Capture', 'err 7');

      expect(logger.entries, hasLength(5));
      expect(logger.entries.first.message, 'warn 3');
      expect(logger.entries.last.message, 'err 7');
      expect(logger.errorCount, 2);
      expect(logger.latestError?.message, 'err 7');
      expect(notifications, 7);

      logger.clear();
      expect(logger.entries, isEmpty);
      expect(logger.errorCount, 0);
      expect(logger.latestError, isNull);
      expect(notifications, 8);

      logger.removeListener(onUpdate);
    });

    test('redacts Bearer tokens, prefixed API keys, and kv secrets', () {
      const sample =
          'Header Authorization: Bearer abc.def.ghi failed; '
          'openai=sk-testsecret1234567890 google=AIzaSyDummyKey1234567890123 '
          'query api_key=my_secret_val&token=tok_value_999&key=plainKey123';
      final redacted = InouDiagnosticsLogger.redactSecrets(sample);

      expect(redacted, isNot(contains('abc.def.ghi')));
      expect(redacted, isNot(contains('sk-testsecret1234567890')));
      expect(redacted, isNot(contains('AIzaSyDummyKey1234567890123')));
      expect(redacted, isNot(contains('my_secret_val')));
      expect(redacted, isNot(contains('tok_value_999')));
      expect(redacted, isNot(contains('plainKey123')));
      expect(redacted, contains('Bearer ***REDACTED***'));
      expect(redacted, contains('***REDACTED_KEY***'));

      final logger = InouDiagnosticsLogger();
      logger.error(
        'Gateway',
        'HTTP 401 with Bearer sk-secret999988887777',
        detail: 'x-goog-api-key: AIzaSyDummyKey1234567890123',
        stackTrace: StackTrace.fromString(
          '#0 main (file:///app.dart:10)\n#1 token=my_stack_token_123',
        ),
      );
      final recorded = logger.latestError!;
      expect(recorded.message, isNot(contains('sk-secret999988887777')));
      expect(recorded.detail, isNot(contains('AIzaSyDummyKey1234567890123')));
      expect(recorded.stackTrace, isNot(contains('my_stack_token_123')));
      expect(recorded.message, contains('Bearer ***REDACTED***'));
    });

    test('formatExportText outputs untruncated logs and supports errorsOnly filter', () {
      final logger = InouDiagnosticsLogger();
      final longTail = '${List.filled(60, 'trace_segment').join('_')}_END';
      logger.info('Boot', 'app started cleanly');
      logger.warn('Network', 'slow response');
      logger.error(
        'AI',
        'Request failed with sk-prodsecret1234567890',
        detail: 'multi-line detail\n$longTail',
        stackTrace: StackTrace.fromString(
          '#0 StructuredJsonCaller.callJson\n#1 TutorAgent.sendMessage',
        ),
      );

      final errOnlyReport = logger.formatExportText(
        metadata: const {
          'platform': 'android',
          'header': 'Authorization: Bearer topsecret123',
        },
        errorsOnly: true,
      );

      expect(errOnlyReport, contains('platform: android'));
      expect(errOnlyReport, contains('Bearer ***REDACTED***'));
      expect(errOnlyReport, isNot(contains('topsecret123')));
      expect(errOnlyReport, isNot(contains('sk-prodsecret1234567890')));
      expect(errOnlyReport, isNot(contains('app started cleanly')));
      expect(errOnlyReport, isNot(contains('slow response')));
      expect(errOnlyReport, contains(longTail));
      expect(errOnlyReport, contains('#1 TutorAgent.sendMessage'));

      final allReport = logger.formatExportText(errorsOnly: false);
      expect(allReport, contains('app started cleanly'));
      expect(allReport, contains('slow response'));
      expect(allReport, contains(longTail));
    });
  });

  group('PhotoSearch models, formatReferenceAnswer & WeaknessAnalyzer', () {
    test('Question.formatReferenceAnswer formats choice, fill, sequence, solve, match & response', () {
      final qs = InouSeedData.defaultQuestions(nowMs);
      final qById = {for (final q in qs) q.id: q};

      // Single choice includes option text when short
      final choiceSingle = qById['q_choice_quad']!;
      expect(choiceSingle.formatReferenceAnswer(), startsWith('A'));
      expect(choiceSingle.formatReferenceAnswer(), contains('x_1 = 2'));

      // Multi-select choice joins with 、
      final choiceMulti = choiceSingle.copyWith(
        grading: const {
          'mode': 'exact',
          'maxScore': 3,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'selectedIds': ['A', 'C'],
              },
            },
          ],
        },
      );
      expect(choiceMulti.formatReferenceAnswer(), 'A、C');

      // Multi-slot fill
      final fillMulti = qById['q_fill_sqrt']!;
      expect(fillMulti.formatReferenceAnswer(), '(1) 2；(2) 0.5');

      // Sequence fill
      const seqQ = Question(
        id: 'q_seq_test',
        kind: QuestionKind.fill,
        header: QuestionHeader(title: '连词成句', score: 2),
        prompt: [TextBlock('连词成句：'), SlotBlock('s1')],
        body: {
          'slots': [
            {'id': 's1'},
          ],
          'bank': [
            {
              'id': 'w1',
              'content': [
                {'type': 'text', 'text': 'You'},
              ],
            },
            {
              'id': 'w2',
              'content': [
                {'type': 'text', 'text': 'win'},
              ],
            },
          ],
        },
        presentation: QuestionPresentation(interaction: 'fill.sequence'),
        grading: {
          'mode': 'exact',
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'slotId': 's1',
                    'acceptedValues': [
                      {
                        'type': 'items',
                        'itemIds': ['w1', 'w2'],
                      },
                    ],
                  },
                ],
              },
            },
          ],
        },
        meta: QuestionMeta(subject: 'eng', grade: 'g7'),
      );
      expect(seqQ.formatReferenceAnswer(), 'You win');

      // Solve finalAnswer
      final solveQ = qById['q_solve_discriminant']!;
      expect(solveQ.formatReferenceAnswer(), isNotEmpty);

      // Match pairs
      final matchQ = qById['q_match_phy']!;
      expect(matchQ.formatReferenceAnswer(), contains('→'));

      // Response keywords / referenceAnswer
      const respQ = Question(
        id: 'q_resp_test',
        kind: QuestionKind.response,
        header: QuestionHeader(title: '简答题', score: 4),
        prompt: [TextBlock('简述光合作用的条件。')],
        body: {},
        presentation: QuestionPresentation(interaction: 'response.text'),
        grading: {
          'keywords': ['光', '叶绿体'],
        },
        meta: QuestionMeta(subject: 'bio', grade: 'g7'),
      );
      expect(respQ.formatReferenceAnswer(), '光、叶绿体');
    });

    test('PhotoSearchItem & PhotoSearchSession serialize round-trip cleanly', () {
      final q = InouSeedData.defaultQuestions(nowMs).first;
      final item = PhotoSearchItem(
        id: 'psi_1',
        sortOrder: 1,
        question: q,
        answerSummary: '',
        keyPoints: const ['因式分解', '求根公式'],
        pitfallNote: '注意检查两个根是否均满足题意',
        confidence: 0.91,
        duplicateOfTitle: '相似例题',
        savedQuestionId: q.id,
      );
      expect(item.effectiveAnswerSummary, q.formatReferenceAnswer());

      final session = PhotoSearchSession(
        id: 'pss_1',
        title: '无答案随堂练习',
        subject: 'math',
        localImagePath: 'photo_search/pss_1.jpg',
        sourceDocId: 'doc_ps_1',
        items: [item],
        traces: const ['[工具] P-19 → 生成答案'],
        createdAtMs: nowMs,
      );
      final roundtrip = PhotoSearchSession.fromJson(session.toJson());
      expect(roundtrip.id, 'pss_1');
      expect(roundtrip.title, '无答案随堂练习');
      expect(roundtrip.items, hasLength(1));
      expect(roundtrip.items.first.keyPoints, ['因式分解', '求根公式']);
      expect(roundtrip.items.first.pitfallNote, '注意检查两个根是否均满足题意');
      expect(roundtrip.items.first.savedQuestionId, q.id);
    });

    test('WeaknessAnalyzer includes AddedVia.photoSearch wrong items in diagnostics', () {
      const analyzer = WeaknessAnalyzer();
      final q = InouSeedData.defaultQuestions(nowMs).first;
      const kpNode = KnowledgeNode(
        id: 'math.m.02.03.02',
        parentId: 'math.m.02',
        subject: 'math',
        stage: 'm',
        name: '因式分解法解一元二次方程',
        level: 3,
        isLeaf: true,
        sort: 1,
      );
      final wrongFromPhotoSearch = WrongItem(
        id: 'w_ps_1',
        questionId: q.id,
        addedVia: AddedVia.photoSearch,
        mastery: MasteryState.newWrong,
        errorTags: const [ErrorTag.concept],
        addedAtMs: nowMs,
      );

      final snap = analyzer.analyze(
        questions: [q],
        attempts: const [],
        wrongItems: [wrongFromPhotoSearch],
        kpNodes: const [kpNode],
        nowMs: nowMs,
      );
      expect(snap.subjectMasteryPercent.containsKey('math'), isTrue);
      expect(snap.rankedWeakLeaves, isNotEmpty);
      expect(snap.rankedWeakLeaves.first.kpId, 'math.m.02.03.02');
      expect(snap.rankedWeakLeaves.first.unmasteredCount, 1);
    });

    test('ReportRecord.fromJson coerces LLM variants for day, tasks, and weakPoints', () {
      final report = ReportRecord.fromJson({
        'id': 'rep_test',
        'createdAtMs': nowMs,
        'overallAdvice': '整体稳健',
        'markdown': '## 总结\n继续巩固。',
        'weakPoints': [
          {
            'kpId': 'math.m.02.02.01',
            'title': '一次函数待定系数',
            'reason': '漏写交点坐标',
            'severity': 'medium',
          },
        ],
        'plan': [
          {
            'day': 1,
            'focus': '一次函数专题',
            'tasks': ['完成 3 道变式题', '用黑板讲堂复盘'],
          },
        ],
      });
      expect(report.weakPoints, hasLength(1));
      expect(report.weakPoints.first.kpName, '一次函数待定系数');
      expect(report.weakPoints.first.reasons, ['漏写交点坐标']);
      expect(report.plan, hasLength(1));
      expect(report.plan.first.day, 'Day 1');
      expect(report.plan.first.task, '完成 3 道变式题；用黑板讲堂复盘');
    });
  });
}

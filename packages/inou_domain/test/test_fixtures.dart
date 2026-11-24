import 'package:inou_domain/inou_domain.dart';

/// Test fixtures covering all 10 [QuestionKind]s exclusively for automated tests.
abstract final class InouSeedData {
  static List<StudentProfile> defaultProfiles() => const [
    StudentProfile(
      id: 'profile_xiaoming',
      name: '小明',
      stage: StudyStage.middle,
      grade: '九年级',
      subjects: ['math', 'phy', 'eng', 'chn', 'chem'],
    ),
    StudentProfile(
      id: 'profile_xiaohong',
      name: '小红',
      stage: StudyStage.primary,
      grade: '五年级',
      subjects: ['math', 'chn', 'eng'],
    ),
  ];

  static List<SourceDoc> defaultSourceDocs(int nowMs) => [
    SourceDoc(
      id: 'doc_midterm_math',
      title: '2026九年级数学期中检测卷',
      docType: 'paper',
      subject: 'math',
      grade: 'g9',
      pageCount: 2,
      createdAtMs: nowMs - const Duration(days: 3).inMilliseconds,
    ),
    SourceDoc(
      id: 'doc_phy_elec',
      title: '九年级物理电学单元随堂测',
      docType: 'workbook',
      subject: 'phy',
      grade: 'g9',
      pageCount: 1,
      createdAtMs: nowMs - const Duration(days: 6).inMilliseconds,
    ),
    SourceDoc(
      id: 'doc_all_kinds',
      title: '全题型综合体验示范卷（10种题型）',
      docType: 'other',
      subject: 'math',
      grade: 'g8',
      pageCount: 2,
      createdAtMs: nowMs - const Duration(days: 10).inMilliseconds,
    ),
  ];

  static List<Question> defaultQuestions(int nowMs) {
    return [
      // 1. choice (single) - matches prototype hero question
      Question(
        id: 'q_choice_quad',
        kind: QuestionKind.choice,
        docId: 'doc_midterm_math',
        sourceType: 'photo',
        bbox: const NormalizedBbox(150, 50, 265, 950),
        header: const QuestionHeader(title: '一元二次方程求解', score: 3),
        prompt: const [
          TextBlock('已知方程 '),
          MathBlock('x^2 - 5x + 6 = 0'),
          TextBlock('，则 '),
          MathBlock('x'),
          TextBlock(' 的值为（ ）'),
        ],
        body: const {
          'options': [
            {
              'id': 'A',
              'content': [
                {
                  'type': 'math',
                  'latex': 'x_1 = 2,\\; x_2 = 3',
                  'display': false,
                },
              ],
            },
            {
              'id': 'B',
              'content': [
                {
                  'type': 'math',
                  'latex': 'x_1 = -2,\\; x_2 = -3',
                  'display': false,
                },
              ],
            },
            {
              'id': 'C',
              'content': [
                {
                  'type': 'math',
                  'latex': 'x_1 = 1,\\; x_2 = 6',
                  'display': false,
                },
              ],
            },
            {
              'id': 'D',
              'content': [
                {
                  'type': 'math',
                  'latex': 'x_1 = -1,\\; x_2 = -6',
                  'display': false,
                },
              ],
            },
          ],
        },
        rules: const {'minSelections': 1, 'maxSelections': 1, 'shuffle': false},
        presentation: const QuestionPresentation(
          interaction: 'choice.select',
          config: {'layout': 'list'},
        ),
        grading: const {
          'mode': 'exact',
          'maxScore': 3,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'selectedIds': ['A'],
              },
            },
          ],
        },
        explanation: const [
          TextBlock('使用十字相乘法分解：'),
          MathBlock('x^2 - 5x + 6 = (x - 2)(x - 3) = 0', display: true),
          TextBlock('因此 '),
          MathBlock('x_1 = 2,\\; x_2 = 3'),
          TextBlock('，故选 A。注意常数项为正时两因数与一次项系数同号。'),
        ],
        meta: const QuestionMeta(
          subject: 'math',
          grade: 'g9',
          difficulty: Difficulty.normal,
          kpIds: ['math.m.02.03.02'],
          tags: ['高频易错', '期中卷'],
          sourceNo: '5',
          answerSource: AnswerSource.ai,
          aiConfidence: 0.86,
          uncertainNote: '原图常数项 +6 处有笔迹遮挡，已自动补全并建议核对。',
        ),
        historyVerdicts: const [Verdict.wrong, Verdict.correct, Verdict.wrong],
        createdAtMs: nowMs - const Duration(days: 3).inMilliseconds,
        updatedAtMs: nowMs - const Duration(days: 1).inMilliseconds,
      ),

      // 2. fill (input with math equivalence)
      Question(
        id: 'q_fill_sqrt',
        kind: QuestionKind.fill,
        docId: 'doc_midterm_math',
        sourceType: 'photo',
        header: const QuestionHeader(title: '二次根式与分数运算', score: 4),
        prompt: const [
          TextBlock('计算：'),
          MathBlock('\\sqrt{8} \\div \\sqrt{2} ='),
          SlotBlock('s1'),
          TextBlock('；方程 '),
          MathBlock('2x = 1'),
          TextBlock(' 的解为 '),
          MathBlock('x ='),
          SlotBlock('s2'),
          TextBlock('。'),
        ],
        body: const {
          'slots': [
            {
              'id': 's1',
              'label': '第1空',
              'valueType': 'number',
              'required': true,
            },
            {
              'id': 's2',
              'label': '第2空',
              'valueType': 'number',
              'required': true,
            },
          ],
        },
        presentation: const QuestionPresentation(interaction: 'fill.input'),
        grading: const {
          'mode': 'exact',
          'maxScore': 4,
          'perSlotScore': {'s1': 2, 's2': 2},
          'normalization': {
            'trim': true,
            'caseSensitive': false,
            'fullWidth': true,
            'ignorePunct': false,
          },
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'slotId': 's1',
                    'acceptedValues': [
                      {'type': 'number', 'value': 2, 'tolerance': 0},
                    ],
                  },
                  {
                    'slotId': 's2',
                    'acceptedValues': [
                      {'type': 'number', 'value': 0.5, 'tolerance': 1e-6},
                      {'type': 'text', 'text': '1/2'},
                    ],
                  },
                ],
              },
            },
          ],
        },
        explanation: const [
          MathBlock('\\sqrt{8} \\div \\sqrt{2} = \\sqrt{4} = 2', display: true),
          TextBlock('第二空两边同除以 2 得 x = 1/2（等价于 0.5）。'),
        ],
        meta: const QuestionMeta(
          subject: 'math',
          grade: 'g8',
          difficulty: Difficulty.basic,
          kpIds: ['math.m.01.04.02'],
          tags: ['基础运算'],
          sourceNo: '9',
          answerSource: AnswerSource.paper,
          aiConfidence: 0.96,
        ),
        historyVerdicts: const [Verdict.correct],
        createdAtMs: nowMs - const Duration(days: 3).inMilliseconds,
        updatedAtMs: nowMs - const Duration(days: 3).inMilliseconds,
      ),

      // 3. match
      Question(
        id: 'q_match_phy',
        kind: QuestionKind.match,
        docId: 'doc_phy_elec',
        sourceType: 'photo',
        header: const QuestionHeader(title: '物理量与国际单位连线', score: 3),
        prompt: const [TextBlock('请将左侧的电学物理量与右侧对应的国际单位制（SI）单位相连。')],
        body: const {
          'left': [
            {
              'id': 'L1',
              'content': [
                {'type': 'text', 'text': '电流 (I)'},
              ],
            },
            {
              'id': 'L2',
              'content': [
                {'type': 'text', 'text': '电压 (U)'},
              ],
            },
            {
              'id': 'L3',
              'content': [
                {'type': 'text', 'text': '电阻 (R)'},
              ],
            },
          ],
          'right': [
            {
              'id': 'R1',
              'content': [
                {'type': 'text', 'text': '伏特 (V)'},
              ],
            },
            {
              'id': 'R2',
              'content': [
                {'type': 'text', 'text': '欧姆 (Ω)'},
              ],
            },
            {
              'id': 'R3',
              'content': [
                {'type': 'text', 'text': '安培 (A)'},
              ],
            },
          ],
        },
        rules: const {
          'maxLinksPerLeft': 1,
          'maxLinksPerRight': 1,
          'requireAllLeft': true,
        },
        presentation: const QuestionPresentation(interaction: 'match.connect'),
        grading: const {
          'mode': 'exact',
          'maxScore': 3,
          'partialScore': {'enabled': true, 'perPairScore': 1},
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'pairs': [
                  {'fromId': 'L1', 'toId': 'R3'},
                  {'fromId': 'L2', 'toId': 'R1'},
                  {'fromId': 'L3', 'toId': 'R2'},
                ],
              },
            },
          ],
        },
        explanation: const [TextBlock('国际单位制中，电流单位安培(A)，电压伏特(V)，电阻欧姆(Ω)。')],
        meta: const QuestionMeta(
          subject: 'phy',
          grade: 'g9',
          difficulty: Difficulty.basic,
          kpIds: ['phy.m.04.02.01'],
          tags: ['电学基础'],
          sourceNo: '二-1',
          answerSource: AnswerSource.user,
          aiConfidence: 0.99,
        ),
        historyVerdicts: const [
          Verdict.wrong,
          Verdict.correct,
          Verdict.correct,
        ],
        createdAtMs: nowMs - const Duration(days: 6).inMilliseconds,
        updatedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
      ),

      // 4. solve
      Question(
        id: 'q_solve_discriminant',
        kind: QuestionKind.solve,
        docId: 'doc_midterm_math',
        sourceType: 'photo',
        header: const QuestionHeader(title: '一元二次方程判别式求解', score: 6),
        prompt: const [
          TextBlock('已知关于 '),
          MathBlock('x'),
          TextBlock(' 的方程 '),
          MathBlock('x^2 - 4x + k = 0'),
          TextBlock(' 有两个相等的实数根，求 '),
          MathBlock('k'),
          TextBlock(' 的值并解此方程。'),
        ],
        body: const {
          'steps': [
            {'id': 'st1', 'label': '列判别式', 'score': 2},
            {'id': 'st2', 'label': '求出 k 值', 'score': 2},
            {'id': 'st3', 'label': '写出方程的根', 'score': 2},
          ],
          'finalAnswerSlot': {
            'id': 'fin',
            'label': 'k 的值',
            'valueType': 'number',
          },
        },
        rules: const {'allowImageAnswer': true, 'minSteps': 2},
        presentation: const QuestionPresentation(
          interaction: 'solve.steps',
          config: {'preferMode': 'paper'},
        ),
        grading: const {
          'mode': 'stepwise_ai',
          'maxScore': 6,
          'referenceSolution': [
            {
              'type': 'text',
              'text': '因为方程有两个相等实数根，所以 Δ = (-4)² - 4×1×k = 0，解得 k = 4。',
            },
            {
              'type': 'math',
              'latex': 'x^2 - 4x + 4 = (x - 2)^2 = 0 \\implies x_1 = x_2 = 2',
              'display': true,
            },
          ],
          'scoringPoints': [
            {'stepId': 'st1', 'point': '正确列出 Δ = (-4)² - 4k = 0', 'score': 2},
            {'stepId': 'st2', 'point': '解得 k = 4', 'score': 2},
            {'stepId': 'st3', 'point': '代入方程求得 x₁ = x₂ = 2', 'score': 2},
          ],
          'finalAnswer': {
            'acceptedValues': [
              {'type': 'number', 'value': 4, 'tolerance': 0},
            ],
          },
          'tolerateAlternateMethods': true,
        },
        explanation: const [
          TextBlock('注意题干要求「求 k 的值并解此方程」，很多同学算出 k=4 后忘记继续解出 x₁=x₂=2。'),
        ],
        meta: const QuestionMeta(
          subject: 'math',
          grade: 'g9',
          difficulty: Difficulty.normal,
          kpIds: ['math.m.02.03.03'],
          tags: ['判别式', '解答规范'],
          sourceNo: '18',
          answerSource: AnswerSource.aiVerified,
          aiConfidence: 0.94,
        ),
        historyVerdicts: const [Verdict.wrong],
        createdAtMs: nowMs - const Duration(days: 3).inMilliseconds,
        updatedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
      ),

      // 5. group (reading passage + 2 sub-questions)
      Question(
        id: 'q_group_eng',
        kind: QuestionKind.group,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: const QuestionHeader(title: '英语阅读理解 A 篇', score: 4),
        prompt: const [
          PassageBlock(
            title: 'Smart Mistake Review',
            paragraphs: [
              PassageParagraph(
                no: '1',
                content: [
                  TextBlock(
                    'Many top students review their mistakes in a dedicated notebook every Friday.',
                  ),
                ],
              ),
              PassageParagraph(
                no: '2',
                content: [
                  TextBlock(
                    'Instead of copying the entire problem mindlessly, they circle the exact step where their thinking drifted and write one short rule in their own words.',
                  ),
                ],
              ),
            ],
          ),
        ],
        body: const {
          'questions': [
            {
              'id': 'q_group_eng_1',
              'schema': 1,
              'kind': 'choice',
              'header': {
                'title': '小题 1',
                'description': <Object>[],
                'score': 2,
              },
              'prompt': [
                {
                  'type': 'text',
                  'text': '1. When do the students usually review their wrong-question notebooks?',
                },
              ],
              'body': {
                'options': [
                  {
                    'id': 'A',
                    'content': [
                      {'type': 'text', 'text': 'Every Monday.'},
                    ],
                  },
                  {
                    'id': 'B',
                    'content': [
                      {'type': 'text', 'text': 'Every Friday.'},
                    ],
                  },
                  {
                    'id': 'C',
                    'content': [
                      {'type': 'text', 'text': 'Only before final exams.'},
                    ],
                  },
                ],
              },
              'rules': {'minSelections': 1, 'maxSelections': 1},
              'presentation': {
                'interaction': 'choice.select',
                'config': <String, Object?>{},
              },
              'grading': {
                'mode': 'exact',
                'maxScore': 2,
                'answerSets': [
                  {
                    'id': 'a1',
                    'expected': {
                      'selectedIds': ['B'],
                    },
                  },
                ],
              },
              'explanation': [
                {'type': 'text', 'text': '第 1 段明确提到 every Friday。'},
              ],
              'meta': {
                'subject': 'eng',
                'grade': 'g9',
                'difficulty': 'basic',
                'kpIds': ['eng.m.04.01.01'],
                'answerSource': 'paper',
              },
            },
            {
              'id': 'q_group_eng_2',
              'schema': 1,
              'kind': 'fill',
              'header': {
                'title': '小题 2',
                'description': <Object>[],
                'score': 2,
              },
              'prompt': [
                {'type': 'text', 'text': '2. They circle the exact '},
                {'type': 'slot', 'slotId': 's1'},
                {'type': 'text', 'text': ' where their thinking drifted.'},
              ],
              'body': {
                'slots': [
                  {
                    'id': 's1',
                    'label': '单词',
                    'valueType': 'text',
                    'required': true,
                  },
                ],
              },
              'rules': <String, Object?>{},
              'presentation': {
                'interaction': 'fill.input',
                'config': <String, Object?>{},
              },
              'grading': {
                'mode': 'exact',
                'maxScore': 2,
                'normalization': {
                  'trim': true,
                  'caseSensitive': false,
                  'fullWidth': true,
                  'ignorePunct': true,
                },
                'answerSets': [
                  {
                    'id': 'a1',
                    'expected': {
                      'entries': [
                        {
                          'slotId': 's1',
                          'acceptedValues': [
                            {'type': 'text', 'text': 'step'},
                          ],
                        },
                      ],
                    },
                  },
                ],
              },
              'explanation': [
                {'type': 'text', 'text': '第 2 段：circle the exact step。'},
              ],
              'meta': {
                'subject': 'eng',
                'grade': 'g9',
                'difficulty': 'basic',
                'kpIds': ['eng.m.04.01.01'],
                'answerSource': 'paper',
              },
            },
          ],
        },
        presentation: const QuestionPresentation(
          interaction: 'group.compose',
          config: {'layout': 'stack'},
        ),
        grading: const {'mode': 'aggregate', 'maxScore': 4},
        explanation: const [TextBlock('阅读定位细节词 Friday 与 step。')],
        meta: const QuestionMeta(
          subject: 'eng',
          grade: 'g9',
          difficulty: Difficulty.basic,
          kpIds: ['eng.m.04.01.01'],
          tags: ['阅读理解'],
          sourceNo: '阅读A',
          answerSource: AnswerSource.paper,
        ),
        createdAtMs: nowMs - const Duration(days: 5).inMilliseconds,
      ),

      // 6. classify
      const Question(
        id: 'q_classify_chem',
        kind: QuestionKind.classify,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: QuestionHeader(title: '纯净物与混合物分类', score: 4),
        prompt: [TextBlock('将下列常见物质正确归入「纯净物」或「混合物」。')],
        body: {
          'items': [
            {
              'id': 'i1',
              'content': [
                {'type': 'text', 'text': '冰水混合物'},
              ],
            },
            {
              'id': 'i2',
              'content': [
                {'type': 'text', 'text': '空气'},
              ],
            },
            {
              'id': 'i3',
              'content': [
                {'type': 'text', 'text': '液氧'},
              ],
            },
            {
              'id': 'i4',
              'content': [
                {'type': 'text', 'text': '生理盐水'},
              ],
            },
          ],
          'categories': [
            {
              'id': 'pure',
              'content': [
                {'type': 'text', 'text': '纯净物'},
              ],
            },
            {
              'id': 'mix',
              'content': [
                {'type': 'text', 'text': '混合物'},
              ],
            },
          ],
        },
        presentation: QuestionPresentation(interaction: 'classify.bins'),
        grading: {
          'mode': 'exact',
          'maxScore': 4,
          'partialScore': {'enabled': true, 'perItemScore': 1},
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'placements': [
                  {'itemId': 'i1', 'categoryId': 'pure'},
                  {'itemId': 'i2', 'categoryId': 'mix'},
                  {'itemId': 'i3', 'categoryId': 'pure'},
                  {'itemId': 'i4', 'categoryId': 'mix'},
                ],
              },
            },
          ],
        },
        explanation: [TextBlock('冰与水同为 H₂O，故冰水混合物是纯净物；液氧只含 O₂ 也是纯净物。')],
        meta: QuestionMeta(
          subject: 'chem',
          grade: 'g9',
          difficulty: Difficulty.basic,
          kpIds: ['chem.m.01.02.01'],
          tags: ['概念分类'],
          answerSource: AnswerSource.paper,
        ),
      ),

      // 7. fill.sequence (word ordering)
      const Question(
        id: 'q_fill_seq_eng',
        kind: QuestionKind.fill,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: QuestionHeader(title: '英语连词成句', score: 2),
        prompt: [TextBlock('请按正确语序排列组成一般疑问句：'), SlotBlock('s1')],
        body: {
          'slots': [
            {'id': 's1', 'label': '句子', 'valueType': 'items', 'required': true},
          ],
          'bank': [
            {
              'id': 'w1',
              'content': [
                {'type': 'text', 'text': 'you'},
              ],
            },
            {
              'id': 'w2',
              'content': [
                {'type': 'text', 'text': 'Did'},
              ],
            },
            {
              'id': 'w3',
              'content': [
                {'type': 'text', 'text': 'yesterday'},
              ],
            },
            {
              'id': 'w4',
              'content': [
                {'type': 'text', 'text': 'swim'},
              ],
            },
            {
              'id': 'w5',
              'content': [
                {'type': 'text', 'text': '?'},
              ],
            },
          ],
        },
        presentation: QuestionPresentation(interaction: 'fill.sequence'),
        grading: {
          'mode': 'exact',
          'maxScore': 2,
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
                        'itemIds': ['w2', 'w1', 'w4', 'w3', 'w5'],
                      },
                    ],
                  },
                ],
              },
            },
          ],
        },
        explanation: [TextBlock('一般过去时疑问句语序：Did you swim yesterday?')],
        meta: QuestionMeta(
          subject: 'eng',
          grade: 'g8',
          difficulty: Difficulty.basic,
          kpIds: ['eng.m.03.03.01'],
          answerSource: AnswerSource.paper,
        ),
      ),

      // 8. response (open Chinese translation)
      const Question(
        id: 'q_response_chn',
        kind: QuestionKind.response,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: QuestionHeader(title: '文言文翻译与赏析', score: 4),
        prompt: [
          TextBlock('翻译下面句子并简要分析加点词表达效果：'),
          RichTextBlock([
            RichTextSpan(text: '“潭中鱼可百许头，皆若'),
            RichTextSpan(text: '空游', bold: true, underline: true),
            RichTextSpan(text: '无所依。”'),
          ]),
        ],
        body: {
          'parts': [
            {
              'id': 'p1',
              'label': '句子翻译',
              'acceptedFormats': ['text', 'image'],
              'required': true,
            },
            {
              'id': 'p2',
              'label': '词语赏析',
              'acceptedFormats': ['text', 'image'],
              'required': true,
            },
          ],
        },
        presentation: QuestionPresentation(interaction: 'response.submit'),
        grading: {
          'mode': 'rubric_ai',
          'maxScore': 4,
          'rubric': [
            {'partId': 'p1', 'point': '译出“可/许”（大约）和“依”（依托）', 'score': 2},
            {'partId': 'p2', 'point': '点明“空游”侧面衬托潭水清澈透明', 'score': 2},
          ],
        },
        explanation: [TextBlock('潭中的鱼大约有一百来条，好像在空中游动，没有依托；侧面写水清。')],
        meta: QuestionMeta(
          subject: 'chn',
          grade: 'g8',
          difficulty: Difficulty.normal,
          kpIds: ['chn.m.03.02.02'],
          answerSource: AnswerSource.paper,
        ),
      ),

      // 9. draw (linear function coordinate plotting)
      const Question(
        id: 'q_draw_linear',
        kind: QuestionKind.draw,
        docId: 'doc_midterm_math',
        sourceType: 'manual',
        header: QuestionHeader(title: '一次函数图象作图', score: 4),
        prompt: [
          TextBlock('在平面直角坐标系中画出一次函数 '),
          MathBlock('y = 2x - 2'),
          TextBlock(' 的图象，并标出图象与坐标轴的两个交点坐标。'),
        ],
        body: {
          'canvas': {
            'background': {
              'type': 'axes',
              'xRange': [-4, 4],
              'yRange': [-4, 4],
              'gridStep': 1,
            },
            'aspect': 1.0,
          },
          'tools': ['pen', 'line', 'point', 'eraser'],
          'requirements': [
            {'id': 'r1', 'text': '标出 y 轴交点 (0, -2)', 'score': 1},
            {'id': 'r2', 'text': '标出 x 轴交点 (1, 0)', 'score': 1},
            {'id': 'r3', 'text': '过两点作直线并延伸', 'score': 2},
          ],
        },
        presentation: QuestionPresentation(
          interaction: 'draw.canvas',
          config: {'preferMode': 'paper'},
        ),
        grading: {
          'mode': 'visual_ai',
          'maxScore': 4,
          'referenceDescription': '一条经过 (0,-2) 和 (1,0) 的直线，斜率为 2。',
        },
        explanation: [TextBlock('两点确定一条直线：分别令 x=0 和 y=0 求出交点 (0,-2) 和 (1,0)。')],
        meta: QuestionMeta(
          subject: 'math',
          grade: 'g8',
          difficulty: Difficulty.basic,
          kpIds: ['math.m.03.02.01'],
          answerSource: AnswerSource.aiVerified,
        ),
      ),

      // 10. spatial (diagram label placement)
      const Question(
        id: 'q_spatial_cell',
        kind: QuestionKind.spatial,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: QuestionHeader(title: '植物细胞结构看图标注', score: 4),
        prompt: [TextBlock('请把下方结构标签放置到植物细胞模式图对应 ①–④ 标号区域。')],
        body: {
          'base': {'assetId': 'demo_plant_cell', 'width': 1000, 'height': 750},
          'targets': [
            {
              'id': 't1',
              'label': '①',
              'shape': {
                'type': 'rect',
                'x': 0.08,
                'y': 0.14,
                'w': 0.16,
                'h': 0.14,
              },
            },
            {
              'id': 't2',
              'label': '②',
              'shape': {
                'type': 'rect',
                'x': 0.42,
                'y': 0.36,
                'w': 0.16,
                'h': 0.14,
              },
            },
            {
              'id': 't3',
              'label': '③',
              'shape': {
                'type': 'rect',
                'x': 0.66,
                'y': 0.52,
                'w': 0.18,
                'h': 0.14,
              },
            },
            {
              'id': 't4',
              'label': '④',
              'shape': {'type': 'circle', 'cx': 0.28, 'cy': 0.72, 'r': 0.07},
            },
          ],
          'labels': [
            {
              'id': 'lb_wall',
              'content': [
                {'type': 'text', 'text': '细胞壁'},
              ],
            },
            {
              'id': 'lb_nucleus',
              'content': [
                {'type': 'text', 'text': '细胞核'},
              ],
            },
            {
              'id': 'lb_vacuole',
              'content': [
                {'type': 'text', 'text': '液泡'},
              ],
            },
            {
              'id': 'lb_chloro',
              'content': [
                {'type': 'text', 'text': '叶绿体'},
              ],
            },
          ],
        },
        rules: {'mode': 'place_labels', 'maxPoints': 4},
        presentation: QuestionPresentation(interaction: 'spatial.mark'),
        grading: {
          'mode': 'exact',
          'maxScore': 4,
          'expected': {
            'placements': [
              {'labelId': 'lb_wall', 'targetId': 't1'},
              {'labelId': 'lb_nucleus', 'targetId': 't2'},
              {'labelId': 'lb_vacuole', 'targetId': 't3'},
              {'labelId': 'lb_chloro', 'targetId': 't4'},
            ],
          },
        },
        explanation: [TextBlock('①细胞壁最外层保护支持，②细胞核为遗传中心，③中央液泡，④叶绿体光合作用场所。')],
        meta: QuestionMeta(
          subject: 'bio',
          grade: 'g7',
          difficulty: Difficulty.basic,
          kpIds: ['bio.m.01.02.01'],
          answerSource: AnswerSource.paper,
        ),
      ),

      // 11. write (Chinese dictation / pinyin grid)
      const Question(
        id: 'q_write_poem',
        kind: QuestionKind.write,
        docId: 'doc_all_kinds',
        sourceType: 'manual',
        header: QuestionHeader(title: '看拼音写词与古诗默写', score: 4),
        prompt: [TextBlock('请在田字格或输入框内规范书写下列字词与名句：')],
        body: {
          'cells': [
            {
              'id': 'c1',
              'mode': 'hanzi',
              'prompt': [
                {'type': 'text', 'text': '看拼音写词语：qīng cuì'},
              ],
              'expected': '清脆',
              'grid': 'tian',
              'charCount': 2,
            },
            {
              'id': 'c2',
              'mode': 'hanzi',
              'prompt': [
                {'type': 'text', 'text': '默写：海内存知己，______'},
              ],
              'expected': '天涯若比邻',
              'grid': 'tian',
              'charCount': 5,
            },
          ],
        },
        presentation: QuestionPresentation(interaction: 'write.grid'),
        grading: {
          'mode': 'exact',
          'maxScore': 4,
          'answerSets': [
            {
              'id': 'ans-1',
              'expected': {
                'entries': [
                  {
                    'cellId': 'c1',
                    'acceptedValues': [
                      {'type': 'text', 'text': '清脆'},
                    ],
                    'score': 2,
                  },
                  {
                    'cellId': 'c2',
                    'acceptedValues': [
                      {'type': 'text', 'text': '天涯若比邻'},
                    ],
                    'score': 2,
                  },
                ],
              },
            },
          ],
        },
        explanation: [TextBlock('注意“脆”字右半部分为“危”；“天涯”的“涯”为三点水。')],
        meta: QuestionMeta(
          subject: 'chn',
          grade: 'g7',
          difficulty: Difficulty.basic,
          kpIds: ['chn.m.01.01.01'],
          answerSource: AnswerSource.paper,
        ),
      ),
    ];
  }

  static List<WrongItem> defaultWrongItems(int nowMs) => [
    WrongItem(
      id: 'wb_quad',
      questionId: 'q_choice_quad',
      addedVia: AddedVia.photoMarked,
      mastery: MasteryState.learning,
      correctStreak: 1,
      wrongCount: 2,
      attemptCount: 2,
      errorTags: const [ErrorTag.calc, ErrorTag.careless],
      myWrongAnswer: '选 B (-2 或 -3)',
      teacherMark: 'wrong',
      note: '常数项为 +6 正数时，两个因式常数项同号，和为 -5 所以都是负数！',
      addedAtMs: nowMs - const Duration(days: 3).inMilliseconds,
      lastAttemptAtMs: nowMs - const Duration(days: 1).inMilliseconds,
    ),
    WrongItem(
      id: 'wb_solve_disc',
      questionId: 'q_solve_discriminant',
      addedVia: AddedVia.practice,
      mastery: MasteryState.newWrong,
      correctStreak: 0,
      wrongCount: 1,
      attemptCount: 1,
      errorTags: const [ErrorTag.misread],
      myWrongAnswer: '误列成 Δ > 0，且忘记解方程',
      teacherMark: 'wrong',
      note: '两个相等实根必须列 Δ = 0，且要看清两问。',
      addedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
      lastAttemptAtMs: nowMs - const Duration(days: 2).inMilliseconds,
    ),
    WrongItem(
      id: 'wb_phy_match',
      questionId: 'q_match_phy',
      addedVia: AddedVia.practice,
      mastery: MasteryState.reviewing,
      correctStreak: 2,
      wrongCount: 3,
      attemptCount: 4,
      errorTags: const [ErrorTag.concept],
      myWrongAnswer: '电压误连欧姆',
      note: '再答对 1 次即可毕业掌握！',
      addedAtMs: nowMs - const Duration(days: 6).inMilliseconds,
      lastAttemptAtMs: nowMs - const Duration(days: 1).inMilliseconds,
    ),
    WrongItem(
      id: 'wb_sqrt_fill',
      questionId: 'q_fill_sqrt',
      addedVia: AddedVia.practice,
      mastery: MasteryState.mastered,
      correctStreak: 3,
      wrongCount: 1,
      attemptCount: 4,
      errorTags: const [ErrorTag.careless],
      myWrongAnswer: '第1空写成了 4',
      note: '√8 ÷ √2 = √4 = 2，记得开方！',
      addedAtMs: nowMs - const Duration(days: 8).inMilliseconds,
      lastAttemptAtMs: nowMs - const Duration(days: 2).inMilliseconds,
      masteredAtMs: nowMs - const Duration(days: 2).inMilliseconds,
    ),
    WrongItem(
      id: 'wb_eng_read',
      questionId: 'q_group_eng',
      addedVia: AddedVia.practice,
      mastery: MasteryState.learning,
      correctStreak: 0,
      wrongCount: 2,
      attemptCount: 2,
      errorTags: const [ErrorTag.misread],
      myWrongAnswer: '小题1误选 Every Monday',
      note: '精读第一句定位关键词 Friday。',
      addedAtMs: nowMs - const Duration(days: 4).inMilliseconds,
    ),
    WrongItem(
      id: 'wb_draw_lin',
      questionId: 'q_draw_linear',
      addedVia: AddedVia.practice,
      mastery: MasteryState.newWrong,
      correctStreak: 0,
      wrongCount: 1,
      attemptCount: 1,
      errorTags: const [ErrorTag.method],
      myWrongAnswer: '交点坐标标反成 (-2, 0)',
      note: '与 y 轴交点横坐标是 0，即 (0, -2)。',
      addedAtMs: nowMs - const Duration(days: 1).inMilliseconds,
    ),
  ];

  static List<AttemptRecord> defaultAttempts(int nowMs) => [
    AttemptRecord(
      id: 'att_1',
      sessionId: 'sess_hist_1',
      questionId: 'q_choice_quad',
      inputMode: InputMode.standard,
      verdict: Verdict.wrong,
      score: 0,
      maxScore: 3,
      createdAtMs: nowMs - const Duration(days: 20).inMilliseconds,
    ),
    AttemptRecord(
      id: 'att_2',
      sessionId: 'sess_hist_1',
      questionId: 'q_solve_discriminant',
      inputMode: InputMode.paper,
      verdict: Verdict.wrong,
      score: 2,
      maxScore: 6,
      createdAtMs: nowMs - const Duration(days: 15).inMilliseconds,
    ),
    AttemptRecord(
      id: 'att_3',
      sessionId: 'sess_hist_2',
      questionId: 'q_fill_sqrt',
      inputMode: InputMode.standard,
      verdict: Verdict.correct,
      score: 4,
      maxScore: 4,
      createdAtMs: nowMs - const Duration(days: 10).inMilliseconds,
    ),
    AttemptRecord(
      id: 'att_4',
      sessionId: 'sess_hist_2',
      questionId: 'q_match_phy',
      inputMode: InputMode.standard,
      verdict: Verdict.correct,
      score: 3,
      maxScore: 3,
      createdAtMs: nowMs - const Duration(days: 5).inMilliseconds,
    ),
    AttemptRecord(
      id: 'att_5',
      sessionId: 'sess_hist_3',
      questionId: 'q_group_eng',
      inputMode: InputMode.standard,
      verdict: Verdict.wrong,
      score: 2,
      maxScore: 4,
      createdAtMs: nowMs - const Duration(days: 4).inMilliseconds,
    ),
    AttemptRecord(
      id: 'att_6',
      sessionId: 'sess_hist_3',
      questionId: 'q_classify_chem',
      inputMode: InputMode.standard,
      verdict: Verdict.correct,
      score: 4,
      maxScore: 4,
      createdAtMs: nowMs - const Duration(days: 2).inMilliseconds,
    ),
  ];

  static List<CaptureDraftItem> defaultCaptureDrafts(int nowMs) {
    final qs = defaultQuestions(nowMs);
    return [
      CaptureDraftItem(
        id: 'draft_1',
        sortOrder: 0,
        question: qs[1], // q_fill_sqrt
        confidence: 0.96,
        teacherMark: 'correct',
        studentAnswerSnippet: '2 ； 1/2',
        confirmed: true,
      ),
      CaptureDraftItem(
        id: 'draft_2',
        sortOrder: 1,
        question: qs[0], // q_choice_quad (has red cross & ai_unverified)
        confidence: 0.82,
        teacherMark: 'wrong',
        studentAnswerSnippet: '选 B (-2 或 -3)',
        flaggedWrong: true,
        errorTags: const [ErrorTag.calc, ErrorTag.careless],
      ),
      CaptureDraftItem(
        id: 'draft_3',
        sortOrder: 2,
        question: qs[3], // q_solve_discriminant
        confidence: 0.91,
        teacherMark: 'none',
      ),
      CaptureDraftItem(
        id: 'draft_4',
        sortOrder: 3,
        question: qs[8], // q_draw_linear
        confidence: 0.89,
        teacherMark: 'none',
        duplicateOfTitle: '期末复习卷 第3题（相似度 92%）',
      ),
    ];
  }
}

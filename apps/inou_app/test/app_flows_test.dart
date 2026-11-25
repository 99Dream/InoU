import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inou_ai/inou_ai.dart';
import 'package:inou_app/app/app.dart';
import 'package:inou_app/core/backup/inou_backup_service.dart';
import 'package:inou_app/core/platform/platform_media_service.dart';
import 'package:inou_app/core/security/secret_and_pin_service.dart';
import 'package:inou_app/core/state/app_store.dart';
import 'package:inou_app/core/state/workspace_models.dart';
import 'package:inou_app/core/storage/workspace_storage.dart';
import 'package:inou_app/features/photo_search/presentation/photo_search_page.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/render.dart';
import 'package:material_ui/material_ui.dart';

class _FakePlatformMediaService implements PlatformMediaService {
  _FakePlatformMediaService({
    this.photoBytes,
    this.cutoutInsets = EdgeInsets.zero,
  });

  final Uint8List? photoBytes;
  final EdgeInsets cutoutInsets;
  final List<({String filename, String mimeType, Uint8List bytes})> savedFiles =
      [];

  @override
  Future<EdgeInsets> getDisplayCutoutInsets() async => cutoutInsets;

  @override
  Future<PickedMediaResult?> capturePhoto() async => photoBytes == null
      ? null
      : PickedMediaResult(bytes: photoBytes!, name: 'camera_exam.jpg');

  @override
  Future<PickedMediaResult?> pickGalleryImage() async => photoBytes == null
      ? null
      : PickedMediaResult(bytes: photoBytes!, name: 'gallery_exam.jpg');

  @override
  Future<PickedMediaResult?> pickFile({String mimeType = '*/*'}) async => null;

  @override
  Future<Uint8List?> rotateImage90(Uint8List bytes) async => bytes;

  @override
  Future<bool> saveFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    savedFiles.add((filename: filename, mimeType: mimeType, bytes: bytes));
    return true;
  }

  @override
  Future<bool> shareFile({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    savedFiles.add((filename: filename, mimeType: mimeType, bytes: bytes));
    return true;
  }
}

class _FakeVisionLlmClient implements LLMClient {
  int calls = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    final sys = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join();
    if (sys.contains('版面分析')) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'stop',
        textOutput: jsonEncode({
          'docType': 'paper',
          'suggestedTitle': '真实拍照随堂测试',
          'regions': [
            {
              'index': 1,
              'role': 'question',
              'bbox': [100, 50, 350, 950],
              'kindGuess': 'choice',
            },
          ],
        }),
      );
    }
    if (sys.contains('题目数字化引擎')) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'stop',
        textOutput: jsonEncode({
          'suggestedTitle': '真实拍照随堂测试',
          'items': [
            {
              'sortOrder': 1,
              'bbox': [100, 50, 350, 950],
              'teacherMark': 'wrong',
              'studentAnswerSnippet': '选 B',
              'confidence': 0.96,
              'question': {
                'schema': 1,
                'kind': 'choice',
                'header': {'title': '勾股定理识别题', 'score': 3},
                'prompt': '已知直角三角形两直角边分别为 3 和 4，斜边长为（ ）',
                'options': ['5', '7', '12', '25'],
                'answer': 'A',
                'explanation': '由勾股定理得 √(3²+4²) = 5。',
              },
            },
          ],
        }),
      );
    }
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: jsonEncode({
        'confidence': 0.96,
        'explanation': [
          {'type': 'text', 'text': '由勾股定理得 √(3²+4²) = 5。'},
        ],
      }),
    );
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final msg = await generate(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    return Stream.value(StreamingMessage(modelMessage: msg));
  }
}

WorkspaceSnapshot _createTestSnapshot() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  const profile = StudentProfile(
    id: 'test_stu',
    name: '测试同学',
    stage: StudyStage.middle,
    grade: '九年级',
    subjects: ['math', 'phy', 'eng'],
  );
  final qChoice = Question(
    id: 'q_t_1',
    kind: QuestionKind.choice,
    sourceType: 'manual',
    header: const QuestionHeader(title: '一元二次方程求解', score: 3),
    prompt: const [TextBlock('已知方程 x² - 5x + 6 = 0，则 x 的值为（ ）')],
    body: const {
      'options': [
        {
          'id': 'A',
          'content': [
            {'type': 'text', 'text': '2 或 3'},
          ],
        },
        {
          'id': 'B',
          'content': [
            {'type': 'text', 'text': '-2 或 -3'},
          ],
        },
      ],
    },
    rules: const {'minSelections': 1, 'maxSelections': 1},
    presentation: const QuestionPresentation(interaction: 'choice.select'),
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
    explanation: const [TextBlock('因式分解 (x-2)(x-3)=0 得解为 2 或 3。')],
    meta: const QuestionMeta(
      subject: 'math',
      grade: 'g9',
      kpIds: ['math.m.02.03.02'],
      tags: ['一元二次方程'],
      answerSource: AnswerSource.user,
    ),
    createdAtMs: ts,
    updatedAtMs: ts,
  );
  final qSolve = Question(
    id: 'q_t_2',
    kind: QuestionKind.solve,
    sourceType: 'manual',
    header: const QuestionHeader(title: '一次函数交点求解', score: 6),
    prompt: const [TextBlock('已知 y = 2x + b 经过 (1, 5)，求 b 的值。')],
    body: const {
      'steps': [
        {'id': 'st1', 'label': '代入求值', 'score': 6},
      ],
    },
    rules: const {'allowImageAnswer': true, 'minSteps': 1},
    presentation: const QuestionPresentation(interaction: 'solve.steps'),
    grading: const {
      'mode': 'stepwise_ai',
      'maxScore': 6,
      'scoringPoints': [
        {'stepId': 'st1', 'point': 'b=3', 'score': 6},
      ],
      'finalAnswer': {
        'acceptedValues': [
          {'type': 'number', 'value': 3, 'tolerance': 0},
        ],
      },
    },
    explanation: const [TextBlock('5 = 2 + b，故 b = 3。')],
    meta: const QuestionMeta(
      subject: 'math',
      grade: 'g9',
      kpIds: ['math.m.02.02.01'],
      tags: ['一次函数'],
      answerSource: AnswerSource.user,
    ),
    createdAtMs: ts,
    updatedAtMs: ts,
  );
  final wrong = WrongItem(
    id: 'wb_t_1',
    questionId: qChoice.id,
    addedVia: AddedVia.practice,
    mastery: MasteryState.newWrong,
    correctStreak: 0,
    wrongCount: 1,
    attemptCount: 1,
    errorTags: const [ErrorTag.calc],
    addedAtMs: ts,
  );
  final attempt = AttemptRecord(
    id: 'att_t_1',
    sessionId: 'sess_t_1',
    questionId: qChoice.id,
    inputMode: InputMode.standard,
    verdict: Verdict.wrong,
    score: 0,
    maxScore: 3,
    createdAtMs: ts,
  );
  final endpoints = AiEndpointPresets.defaults();
  return WorkspaceSnapshot(
    profiles: const [profile],
    activeProfileId: profile.id,
    workspaces: {
      profile.id: ProfileWorkspaceData(
        questions: [qChoice, qSolve],
        sourceDocs: [
          SourceDoc(
            id: 'doc_t_1',
            title: '测试期中数学卷',
            docType: 'paper',
            subject: 'math',
            grade: 'g9',
            createdAtMs: ts,
          ),
        ],
        wrongItems: [wrong],
        attempts: [attempt],
      ),
    },
    endpoints: endpoints,
    activeEndpointId: endpoints.first.id,
    preferences: const AppPreferences(
      onboardingCompleted: true,
      consentAccepted: true,
    ),
  );
}

KeyValueBlobStorage _seededStorage() {
  return InMemoryBlobStorage({
    'inou_workspace_snapshot_v1': jsonEncode(_createTestSnapshot().toJson()),
  });
}

Future<void> _pumpHydrated(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Core Services: Security PIN, .inou Backup & AppStore Flows', () {
    test(
      'ParentPinService enforces salted hash & 5-failure 30s lockout',
      () async {
        final storage = InMemoryBlobStorage();
        final pinService = ParentPinService(storage);

        expect(await pinService.hasPinConfigured(), isFalse);
        await pinService.setPin('2580');
        expect(await pinService.hasPinConfigured(), isTrue);

        final rawBlob = await storage.readString('inou_parent_pin_v1');
        expect(rawBlob, isNot(contains('2580')));

        final okRes = await pinService.verifyPin('2580', nowMs: 1000);
        expect(okRes.ok, isTrue);

        for (var i = 0; i < 4; i++) {
          final bad = await pinService.verifyPin('0000', nowMs: 2000 + i);
          expect(bad.ok, isFalse);
          expect(bad.lockedRemainingSeconds, 0);
        }

        final fifth = await pinService.verifyPin('0000', nowMs: 3000);
        expect(fifth.ok, isFalse);
        expect(fifth.lockedRemainingSeconds, 30);

        final duringLock = await pinService.verifyPin('2580', nowMs: 10000);
        expect(duringLock.ok, isFalse);
        expect(duringLock.lockedRemainingSeconds, greaterThan(0));

        final afterLock = await pinService.verifyPin('2580', nowMs: 35000);
        expect(afterLock.ok, isTrue);
      },
    );

    test(
      '.inou backup export/inspect/import preserves data & strips API keys',
      () async {
        final snap = _createTestSnapshot();
        const backup = InouBackupService();
        final bytes = backup.exportArchive(snap);

        expect(bytes.sublist(0, 2), [0x50, 0x4B]);

        final inspected = backup.inspectArchive(bytes);
        expect(inspected.ok, isTrue);
        expect(inspected.sha256Verified, isTrue);
        expect(inspected.profileCount, snap.profiles.length);

        final cloned = backup.importArchive(
          bytes,
          mode: BackupImportMode.newProfile,
          current: snap,
        );
        expect(cloned.profiles.length, snap.profiles.length + 1);
        expect(cloned.activeProfile.name, contains('导入'));
      },
    );

    test(
      'AppStoreNotifier handles camera OCR commit, N=3 mastery & StudyCoach',
      () async {
        final container = ProviderContainer(
          overrides: [
            blobStorageProvider.overrideWithValue(_seededStorage()),
            overrideLlmClientProvider.overrideWithValue(_FakeVisionLlmClient()),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(appStoreProvider.notifier);
        await notifier.hydrate();

        final initialQs = container
            .read(appStoreProvider)
            .activeWorkspace
            .questions
            .length;
        final imgRes = await notifier.ingestImageBytes(
          examBytes: MathVerifyEngine.tinyTestPngBytes,
          subject: 'math',
        );
        expect(imgRes.ok, isTrue);
        expect(imgRes.drafts.length, 1);
        expect(imgRes.drafts.first.question.header.title, '勾股定理识别题');

        final committed = await notifier.commitCaptureDrafts(
          customDocTitle: '真实相机拍摄试卷',
        );
        expect(committed.importedCount, 1);
        expect(
          container.read(appStoreProvider).activeWorkspace.questions.length,
          initialQs + 1,
        );

        final wrong = container
            .read(appStoreProvider)
            .activeWorkspace
            .wrongItems
            .firstWhere((w) => w.mastery == MasteryState.newWrong);
        await notifier.simulateCorrectReview(wrong.id);
        await notifier.simulateCorrectReview(wrong.id);
        final finalOut = await notifier.simulateCorrectReview(wrong.id);
        expect(finalOut.item?.mastery, MasteryState.mastered);

        final rep = await notifier.generateStudyReport();
        expect(rep.report.plan, isNotEmpty);
      },
    );
  });

  group('UI End-to-End Integration Flows (Tablet Studio)', () {
    testWidgets('Standard Practice choice grading & verdict override works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpHydrated(
        tester,
        ProviderScope(
          overrides: [
            blobStorageProvider.overrideWithValue(_seededStorage()),
            inkSnapshotExporterProvider.overrideWithValue(
              (page, {cropRect, pixelRatio = 2.0}) async =>
                  Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
            ),
          ],
          child: const InouApp(),
        ),
      );

      await tester.tap(find.text('做题'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('开练 (2 题)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('提交本题'));
      await tester.pumpAndSettle();
      expect(find.textContaining('正确 (3'), findsOneWidget);

      await tester.tap(find.text('记为错误'));
      await tester.pumpAndSettle();
      expect(find.textContaining('错误 (0'), findsOneWidget);
    });

    testWidgets(
      'Paper Studio draws stroke, expands box & produces score report',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.text('做题'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('进入稿纸'));
        await tester.pumpAndSettle();

        expect(find.byType(InouInkCanvas), findsWidgets);

        final origin = tester.getTopLeft(find.byType(InouInkCanvas).first);
        await tester.timedDragFrom(
          origin + const Offset(100, 120),
          const Offset(120, 20),
          const Duration(milliseconds: 60),
        );
        await tester.pump();

        await tester.tap(find.text('扩高作答区').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('交卷批改'));
        await tester.pumpAndSettle();

        expect(find.text('练习成绩单'), findsOneWidget);
      },
    );

    testWidgets('Camera Capture -> Split Proofread -> Commit & Copilot', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpHydrated(
        tester,
        ProviderScope(
          overrides: [
            blobStorageProvider.overrideWithValue(_seededStorage()),
            platformMediaServiceProvider.overrideWithValue(
              _FakePlatformMediaService(
                photoBytes: MathVerifyEngine.tinyTestPngBytes,
              ),
            ),
            overrideLlmClientProvider.overrideWithValue(_FakeVisionLlmClient()),
            inkSnapshotExporterProvider.overrideWithValue(
              (page, {cropRect, pixelRatio = 2.0}) async =>
                  Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
            ),
          ],
          child: const InouApp(),
        ),
      );

      // Open NuoNuo Copilot Drawer
      await tester.tap(find.text('问诺诺'));
      await tester.pumpAndSettle();
      expect(find.text('诺诺'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      // Real camera flow -> non-blocking background queue -> Global bar -> Split Proofread -> Commit
      await tester.tap(find.text('拍照录题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相机拍照'));
      await tester.pumpAndSettle();
      expect(find.text('开始后台识题'), findsOneWidget);

      await tester.tap(find.text('开始后台识题'));
      await tester.pumpAndSettle();

      // Modal closed immediately while task completed in background
      expect(find.text('去校对'), findsWidgets);
      await tester.tap(find.text('去校对').first);
      await tester.pumpAndSettle();

      expect(find.text('识题校对'), findsOneWidget);
      expect(find.text('勾股定理识别题'), findsOneWidget);
      await tester.tap(find.textContaining('入库 (1 题)'));
      await tester.pumpAndSettle();
      expect(find.text('我的题库'), findsOneWidget);
      expect(find.text('去校对'), findsNothing);
    });

    testWidgets('Analytics report & Settings .inou backup verification work', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpHydrated(
        tester,
        ProviderScope(
          overrides: [blobStorageProvider.overrideWithValue(_seededStorage())],
          child: const InouApp(),
        ),
      );

      await tester.tap(find.text('诊断'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 诊断报告'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('3 日复习建议'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('3 日复习建议'), findsOneWidget);

      // Verify Wrongbook direct controls remain visible (not buried in overflow)
      await tester.tap(find.text('错题本'));
      await tester.pumpAndSettle();
      expect(find.text('打卡答对 +1'), findsOneWidget);
      expect(find.text('AI 变式题 ×3'), findsOneWidget);

      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('设置与 AI 模型引擎'), findsOneWidget);
      await tester.tap(find.text('安全与备份'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('生成 .inou 备份包'));
      await tester.tap(find.text('生成 .inou 备份包'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('仅校验完整性'));
      await tester.tap(find.text('仅校验完整性'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SHA-256 校验通过'), findsOneWidget);
    });

    testWidgets(
      'Capture auto-detects English content without misrouting to Math on phone layout',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byTooltip('拍照录题'));
        await tester.pumpAndSettle();
        expect(find.text('自动识别'), findsOneWidget);

        await tester.tap(find.text('文本 / JSON / JSONL 导入'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).last,
          '1. — How did you go to Beijing last week?\n— I went there by train.\nA. When did you leave\nB. How did you go\n答案：B',
        );
        await tester.pumpAndSettle();

        expect(find.text('自动识别学科：英语'), findsOneWidget);

        await tester.tap(find.text('解析并校对'));
        await tester.pumpAndSettle();

        expect(find.text('识题校对'), findsOneWidget);
        expect(find.text('英语'), findsWidgets);

        // Verify sorting question (连词成句) parses into interactive 排序题 instead of 简答题
        await tester.tap(find.text('清空'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('拍照录题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('文本 / JSON / JSONL 导入'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          '1. 连词成句：you / how / are / ?\n答案：How are you?',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('解析并校对'));
        await tester.pumpAndSettle();
        expect(find.textContaining('排序题'), findsWidgets);
        expect(find.textContaining('简答题'), findsNothing);
      },
    );

    testWidgets(
      'AI Blackboard Classroom supports step-by-step chalk, diagram, checkpoint, circle-to-ask side note, track switch & wrongbook archive',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        // Open Library -> select qSolve (一次函数交点求解) -> open Blackboard Classroom
        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一次函数交点求解'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('黑板讲题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板讲题'));
        await tester.pumpAndSettle();

        expect(find.text('AI 黑板讲堂'), findsOneWidget);
        expect(find.text('常驻动态示意图'), findsOneWidget);
        expect(find.text('第 1/2 步'), findsOneWidget);

        // Switch to L3 (详细解答) inside Blackboard
        await tester.tap(find.text('详细解答'));
        await tester.pumpAndSettle();
        expect(find.text('第 1/4 步'), findsOneWidget);
        expect(find.text('解法一：标准分步精讲'), findsOneWidget);

        // Step forward -> Step 2 shows interactive checkpoint
        await tester.tap(find.text('听懂了，写下一步'));
        await tester.pumpAndSettle();
        expect(find.text('第 2/4 步'), findsOneWidget);
        expect(find.text('先完成上方小提问'), findsOneWidget);

        // Answer checkpoint correctly -> unlocks forward button
        await tester.tap(find.text('把点的横纵坐标分别代入解析式建立方程'));
        await tester.pumpAndSettle();
        expect(find.textContaining('函数通用金钥匙'), findsOneWidget);
        expect(find.text('听懂了，写下一步'), findsOneWidget);

        // Enable Circle-to-Ask Pen and draw a circle across the board
        await tester.tap(find.text('圈选提问笔'));
        await tester.pumpAndSettle();
        await tester.timedDragFrom(
          const Offset(680, 320),
          const Offset(180, 120),
          const Duration(milliseconds: 60),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('已圈选：'), findsOneWidget);
        expect(find.text('已截图'), findsOneWidget);

        // Ask preset question -> renders warm teacher margin note
        await tester.tap(find.text('这个符号或辅助线是什么意思？'));
        await tester.pumpAndSettle();
        expect(find.text('老师批注'), findsOneWidget);
        expect(
          find.textContaining('这个符号或辅助线是什么意思？'),
          findsOneWidget,
        );

        // Switch to 解法二 branch
        await tester.tap(find.text('解法二：逆推检验 / 数形结合'));
        await tester.pumpAndSettle();
        expect(find.text('第 1/2 步'), findsOneWidget);

        // Archive blackboard notes to Wrongbook
        await tester.tap(find.text('收入错题笔记'));
        await tester.pumpAndSettle();
        expect(find.text('已存笔记'), findsOneWidget);

        // Close blackboard and verify Wrongbook contains the saved note
        await tester.tap(find.byTooltip('关闭黑板'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('错题本'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一次函数交点求解').first);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('【黑板板书笔记'),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'AI Blackboard Classroom auto-rotates into full-height landscape layout on portrait phone viewport',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        // Open Wrongbook -> open first wrong item bottom sheet -> open Blackboard
        await tester.tap(find.text('错题本'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一元二次方程求解'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板板书'));
        await tester.pumpAndSettle();

        // Must wrap classroom in a 90-degree RotatedBox on portrait viewport
        final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox).last);
        expect(rotated.quarterTurns, 1);
        expect(find.text('AI 黑板讲堂'), findsOneWidget);
        expect(find.text('听懂了，写下一步'), findsOneWidget);
        // Phone layout hides permanent right chat column by default
        expect(find.text('有问题直接问老师…'), findsNothing);
        expect(find.text('问老师'), findsOneWidget);

        // Pinned question dock displays stem & full choice options by default, and toggles cleanly
        expect(find.text('原题与题目内容'), findsOneWidget);
        expect(find.text('2 或 3'), findsOneWidget);
        expect(find.text('-2 或 -3'), findsOneWidget);
        await tester.tap(find.text('收起原题'));
        await tester.pumpAndSettle();
        expect(find.text('2 或 3'), findsNothing);
        expect(find.text('展开原题'), findsOneWidget);
        await tester.tap(find.text('展开原题'));
        await tester.pumpAndSettle();
        expect(find.text('2 或 3'), findsOneWidget);

        // Tapping '问老师' expands collapsible floating ask box & submits cleanly
        await tester.tap(find.text('问老师'));
        await tester.pumpAndSettle();
        expect(find.text('有问题直接问老师…'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).last,
          '这步怎么分解因式？',
        );
        await tester.tap(find.byTooltip('提问'));
        await tester.pumpAndSettle();
        expect(find.text('有问题直接问老师…'), findsNothing);

        // Step forward inside rotated landscape view without overflow
        await tester.tap(find.text('听懂了，写下一步'));
        await tester.pumpAndSettle();
        expect(find.text('第 2/4 步'), findsOneWidget);
      },
    );

    testWidgets(
      'AI Blackboard Classroom keeps minimal UI with Little Teacher podium & English word bank display',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final ts = DateTime.now().millisecondsSinceEpoch;
        final baseSnap = _createTestSnapshot();
        final engQ = Question(
          id: 'q_eng_bb_ui',
          kind: QuestionKind.fill,
          sourceType: 'manual',
          header: const QuestionHeader(title: '英语连词成句练习', score: 4),
          prompt: const [
            TextBlock('请你将下面的单词连成句子：'),
            SlotBlock('s1'),
          ],
          body: const {
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
                  {'type': 'text', 'text': 'must'},
                ],
              },
              {
                'id': 'w3',
                'content': [
                  {'type': 'text', 'text': 'wait'},
                ],
              },
              {
                'id': 'w4',
                'content': [
                  {'type': 'text', 'text': 'in line'},
                ],
              },
            ],
            'slots': [
              {'id': 's1', 'label': '排序'},
            ],
          },
          presentation: const QuestionPresentation(
            interaction: 'fill.sequence',
          ),
          grading: const {'sampleAnswer': 'You must wait in line.'},
          explanation: const [
            TextBlock('情态动词 must 后接动词原形 wait，固定搭配 wait in line 表示排队等候。'),
          ],
          meta: const QuestionMeta(
            subject: 'math',
            grade: 'g8',
            tags: ['情态动词must'],
            answerSource: AnswerSource.user,
          ),
          createdAtMs: ts,
          updatedAtMs: ts,
        );
        final ws = baseSnap.activeWorkspace;
        final snapWithEng = baseSnap.copyWith(
          workspaces: {
            ...baseSnap.workspaces,
            baseSnap.activeProfileId: ws.copyWith(
              questions: [...ws.questions, engQ],
            ),
          },
        );
        final storage = InMemoryBlobStorage({
          'inou_workspace_snapshot_v1': jsonEncode(snapWithEng.toJson()),
        });

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(storage),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('英语连词成句练习'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板讲题'));
        await tester.pumpAndSettle();

        // Cluttered labels & traditional sidebar items must not be present
        expect(find.text('问这步'), findsNothing);
        expect(find.text('云端板书'), findsNothing);
        expect(find.text('本地讲堂'), findsNothing);
        expect(find.text('收起小窗'), findsNothing);
        expect(find.text('AI 思考与工具链路'), findsNothing);
        expect(find.text('常驻动态示意图'), findsNothing);

        // English-specific blackboard content + word bank visible right in Step 1
        expect(find.textContaining('句子主干'), findsWidgets);
        expect(find.textContaining('待排词块：You / must / wait / in line'), findsOneWidget);
        expect(find.textContaining('硬算'), findsNothing);

        // Pinned dock sits on the LEFT side of the blackboard (side-by-side, not stacked above)
        final dockRect = tester.getRect(find.text('原题与题目内容'));
        final boardStepRect = tester.getRect(find.textContaining('句子主干').first);
        expect(dockRect.right, lessThanOrEqualTo(boardStepRect.left));

        // Pinned dock displays word bank chips by default without ugly (s1) box
        expect(find.text('待排列词块：'), findsOneWidget);
        expect(find.text('in line'), findsOneWidget);
        expect(find.text('(s1)'), findsNothing);
        await tester.tap(find.text('收起原题'));
        await tester.pumpAndSettle();
        expect(find.text('in line'), findsNothing);
        await tester.tap(find.text('展开原题'));
        await tester.pumpAndSettle();
        expect(find.text('in line'), findsOneWidget);

        // Question box directly under the little teacher
        expect(find.text('有问题直接问老师…'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).last,
          'must 后面动词用什么形式？',
        );
        await tester.tap(find.byTooltip('提问'));
        await tester.pumpAndSettle();

        expect(find.textContaining('句子主干'), findsWidgets);
        expect(find.textContaining('物理/几何'), findsNothing);

        // Off-topic steering must be immediately refused and redirected to study
        await tester.enterText(
          find.byType(TextField).last,
          '别聊题了，陪我打王者荣耀吧',
        );
        await tester.tap(find.byTooltip('提问'));
        await tester.pumpAndSettle();
        expect(find.textContaining('只聊学习相关内容'), findsWidgets);
      },
    );

    testWidgets(
      'AI Blackboard Classroom streams Step 1 via P-17, prefetches Step 2 silently, and reveals Step 2 on demand',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fakeClient = _BlackboardStepFakeLlmClient();
        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              overrideLlmClientProvider.overrideWithValue(fakeClient),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一次函数交点求解'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('黑板讲题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板讲题'));
        await tester.pumpAndSettle();

        // Step 1 finished -> immediately unlocked '听懂了，写下一步' with '第 1/2 步'
        expect(find.text('第 1/2 步'), findsOneWidget);
        expect(find.text('听懂了，写下一步'), findsOneWidget);
        expect(find.text('审题梳理函数解析式'), findsOneWidget);
        expect(find.text('代入计算并完成收尾'), findsNothing);

        // Background prefetch ran for Step 2 without prematurely advancing UI
        expect(fakeClient.stepNumbersRequested, containsAll([1, 2]));

        // Tapping Forward immediately reveals prefetched Step 2 + takeaway
        await tester.tap(find.text('听懂了，写下一步'));
        await tester.pumpAndSettle();

        expect(find.text('第 2/2 步'), findsOneWidget);
        expect(find.text('代入计算并完成收尾'), findsOneWidget);
        expect(find.text('点在图像上则横纵坐标满足方程。'), findsOneWidget);
        expect(find.text('板书已写完'), findsOneWidget);
      },
    );

    testWidgets(
      'AI Blackboard Classroom supports two-way TRY_PROMPT evaluation, step pulse feedback, and adaptive Step 2 replanning',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fakeClient = _BlackboardStepFakeLlmClient(includeTryPrompt: true);
        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              overrideLlmClientProvider.overrideWithValue(fakeClient),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一次函数交点求解'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('黑板讲题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板讲题'));
        await tester.pumpAndSettle();

        // Pinned question dock & interactive [[TRY_PROMPT]] are visible right on Step 1
        expect(find.text('原题与题目内容'), findsOneWidget);
        expect(find.text('轮到你试试'), findsOneWidget);
        expect(find.text('提交'), findsOneWidget);
        expect(find.text('有点懵'), findsOneWidget);

        final tryInput = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == '写下你的答案或想法…',
        );
        expect(tryInput, findsOneWidget);

        // Submit an incorrect guess -> P-18 evaluates + invalidates Step 2 prefetch + replans with feedback
        await tester.enterText(tryInput, '我猜 b = 0');
        await tester.tap(find.text('提交'));
        await tester.pumpAndSettle();

        expect(find.textContaining('诺诺提醒'), findsOneWidget);
        expect(find.text('你的作答：我猜 b = 0'), findsOneWidget);
        expect(
          fakeClient.promptsCaptured.any(
            (p) => p.contains('第 2 步') && p.contains('我猜 b = 0'),
          ),
          isTrue,
        );

        // Correct the answer -> P-18 celebrates & resolves checkpoint, unlocking Forward
        await tester.enterText(tryInput, '代入得 5 = 2 + b，所以 b = 3');
        await tester.tap(find.text('提交'));
        await tester.pumpAndSettle();

        expect(find.textContaining('✓ 诺诺点评'), findsOneWidget);
        await tester.tap(find.text('听懂了，写下一步'));
        await tester.pumpAndSettle();

        expect(find.text('代入计算并完成收尾'), findsOneWidget);
        expect(find.text('这一步学得怎么样？'), findsOneWidget);

        // Step pulse bar inline reply -> renders 诺诺回应 directly inside Step 2
        await tester.tap(find.text('试试回答'));
        await tester.pumpAndSettle();
        final pulseInput = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == '说说你的答案、疑问或哪里卡住了…',
        );
        await tester.enterText(pulseInput, '我算出 b = 3 啦，清晰很多');
        await tester.tap(find.text('发给诺诺'));
        await tester.pumpAndSettle();

        expect(find.text('诺诺回应'), findsOneWidget);
      },
    );

    testWidgets(
      'AI Blackboard Classroom respects punch-hole display cutout and native cutout insets in landscape',
      (tester) async {
        tester.view.physicalSize = const Size(840, 390);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewPadding = const FakeViewPadding(left: 44);
        tester.view.padding = const FakeViewPadding(left: 44);
        tester.view.displayFeatures = [
          const ui.DisplayFeature(
            bounds: ui.Rect.fromLTWH(0, 170, 44, 44),
            type: ui.DisplayFeatureType.cutout,
            state: ui.DisplayFeatureState.unknown,
          ),
        ];
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              platformMediaServiceProvider.overrideWithValue(
                _FakePlatformMediaService(
                  cutoutInsets: const EdgeInsets.only(left: 48),
                ),
              ),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byIcon(Icons.library_books_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('一次函数交点求解'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('黑板讲题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('黑板讲题'));
        await tester.pumpAndSettle();

        expect(find.text('AI 黑板讲堂'), findsOneWidget);
        expect(find.text('原题与题目内容'), findsOneWidget);
        expect(tester.getRect(find.text('AI 黑板讲堂')).left, greaterThanOrEqualTo(48));
        expect(tester.getRect(find.text('原题与题目内容')).left, greaterThanOrEqualTo(48));
      },
    );

    testWidgets(
      'Diagnostics log viewer displays untruncated error stack traces and exports redacted .txt report',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        InouDiagnosticsLogger.instance.clear();
        addTearDown(InouDiagnosticsLogger.instance.clear);
        InouDiagnosticsLogger.instance.error(
          'AI',
          'Chat gateway HTTP 500 with Authorization: Bearer sk-testsecret1234567890',
          detail:
              'Upstream body segment 1\n'
              'Upstream body segment 2: TAIL_UNTRUNCATED_DIAG_MARKER_9981',
          stackTrace: StackTrace.fromString(
            '#0 StructuredJsonCaller.callJson (llm_gateway.dart:210)\n'
            '#1 TutorAgentService.sendMessage (tutor_agent_service.dart:118)',
          ),
        );

        final fakeMedia = _FakePlatformMediaService();
        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              platformMediaServiceProvider.overrideWithValue(fakeMedia),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('安全与备份'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('查看完整日志'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看完整日志'));
        await tester.pumpAndSettle();

        expect(find.text('运行诊断日志'), findsOneWidget);
        expect(
          find.textContaining('TAIL_UNTRUNCATED_DIAG_MARKER_9981'),
          findsWidgets,
        );
        expect(find.textContaining('***REDACTED***'), findsWidgets);
        expect(find.textContaining('sk-testsecret1234567890'), findsNothing);

        final dialogSaveBtn = find.descendant(
          of: find.byType(Dialog).last,
          matching: find.text('保存日志文件'),
        );
        await tester.tap(dialogSaveBtn);
        await tester.pumpAndSettle();

        expect(fakeMedia.savedFiles, hasLength(1));
        final exported = fakeMedia.savedFiles.single;
        expect(exported.filename, endsWith('.txt'));
        expect(exported.mimeType, 'text/plain');
        final text = utf8.decode(exported.bytes);
        expect(text, contains('TAIL_UNTRUNCATED_DIAG_MARKER_9981'));
        expect(
          text,
          contains('#1 TutorAgentService.sendMessage (tutor_agent_service.dart:118)'),
        );
        expect(text, contains('***REDACTED***'));
        expect(text, isNot(contains('sk-testsecret1234567890')));
      },
    );

    testWidgets(
      'Practice page switches live between Standard and Paper modes without losing session, verdict, index, or ink strokes',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.text('做题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('开练 (2 题)'));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(Scaffold).last),
        );
        final initialSessionId = container.read(appStoreProvider).activeSession!.id;

        // Answer Q1 and submit in Standard mode
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('提交本题'));
        await tester.pumpAndSettle();
        expect(find.textContaining('正确 (3'), findsOneWidget);

        // Advance to Q2
        await tester.tap(find.widgetWithText(ChoiceChip, '2'));
        await tester.pumpAndSettle();
        expect(find.textContaining('(2/2)'), findsOneWidget);

        // One-tap switch to Paper mode from top AppBar
        await tester.tap(find.text('手写稿纸'));
        await tester.pumpAndSettle();

        expect(find.byType(InouInkCanvas), findsWidgets);
        expect(find.text('标准作答'), findsOneWidget);
        expect(
          container.read(appStoreProvider).activeSession?.id,
          initialSessionId,
        );
        expect(find.textContaining('红笔批注：正确'), findsOneWidget);

        // Draw a stroke on Q2's ink canvas
        final q2Canvas = find.byType(InouInkCanvas).at(1);
        await tester.ensureVisible(q2Canvas);
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(q2Canvas);
        await tester.timedDragFrom(
          origin + const Offset(40, 40),
          const Offset(90, 20),
          const Duration(milliseconds: 60),
        );
        await tester.pump();

        // Switch back to Standard mode -> stays on same session, index (2/2), and Q1 submitted verdict
        await tester.tap(find.text('标准作答'));
        await tester.pumpAndSettle();

        expect(find.textContaining('(2/2)'), findsOneWidget);
        expect(find.text('手写稿纸'), findsOneWidget);
        expect(
          container.read(appStoreProvider).activeSession?.id,
          initialSessionId,
        );

        // Navigate back to Q1 -> already-submitted attempt & score preserved
        await tester.tap(find.widgetWithText(ChoiceChip, '1'));
        await tester.pumpAndSettle();
        expect(find.textContaining('正确 (3'), findsOneWidget);

        // Switch back to Paper mode -> Q2 strokes persisted losslessly
        await tester.tap(find.text('手写稿纸'));
        await tester.pumpAndSettle();
        final q2Id = container.read(appStoreProvider).activeSession!.questionIds[1];
        final savedInk = container
            .read(appStoreProvider)
            .activeWorkspace
            .inkPagesByQuestionId[q2Id];
        expect(savedInk, isNotNull);
        expect(savedInk!.strokes, isNotEmpty);
      },
    );

    testWidgets(
      'Compact phone practice AppBar switches cleanly between Paper and Standard modes without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              inkSnapshotExporterProvider.overrideWithValue(
                (page, {cropRect, pixelRatio = 2.0}) async =>
                    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('做题'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('进入稿纸'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('进入稿纸'));
        await tester.pumpAndSettle();

        expect(find.byType(InouInkCanvas), findsWidgets);
        await tester.tap(find.text('标准作答'));
        await tester.pumpAndSettle();

        expect(find.text('手写稿纸'), findsOneWidget);
        expect(find.byTooltip('黑板讲题'), findsOneWidget);
        expect(find.byTooltip('问诺诺'), findsOneWidget);

        await tester.tap(find.text('手写稿纸'));
        await tester.pumpAndSettle();
        expect(find.byType(InouInkCanvas), findsWidgets);
      },
    );

    testWidgets(
      'Photo Search -> AI Independent Solve -> Save to Library & WrongBook',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              platformMediaServiceProvider.overrideWithValue(
                _FakePlatformMediaService(
                  photoBytes: MathVerifyEngine.tinyTestPngBytes,
                ),
              ),
              overrideLlmClientProvider.overrideWithValue(
                _PhotoSearchFakeVisionLlmClient(),
              ),
            ],
            child: const InouApp(),
          ),
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InouApp)),
        );
        final initialQCount =
            container.read(appStoreProvider).activeWorkspace.questions.length;
        final initialWCount =
            container.read(appStoreProvider).activeWorkspace.wrongItems.length;

        // Open Photo Search from Home
        await tester.ensureVisible(find.text('去搜题'));
        await tester.tap(find.text('去搜题'));
        await tester.pumpAndSettle();
        expect(find.byType(PhotoSearchPage), findsOneWidget);

        // Capture photo & trigger AI solve
        await tester.tap(find.text('相机拍照'));
        await tester.pumpAndSettle();
        expect(find.text('开始 AI 识题求解'), findsOneWidget);
        await tester.tap(find.text('开始 AI 识题求解'));
        await tester.pumpAndSettle();

        // Verify both solved questions, AI answers, explanations & pitfalls render
        expect(find.text('无答案几何填空题'), findsOneWidget);
        expect(find.text('无答案函数计算题'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.text('x = 4'), findsOneWidget);
        expect(find.textContaining('先用勾股定理求高：'), findsOneWidget);
        expect(find.text('#勾股定理求高'), findsOneWidget);
        expect(find.textContaining('移项注意符号'), findsOneWidget);

        // Save item 1 to Question Bank
        await tester.tap(find.text('加入题库').first);
        await tester.pumpAndSettle();
        expect(find.text('已加入题库'), findsWidgets);
        expect(find.text('已在题库'), findsOneWidget);
        var ws = container.read(appStoreProvider).activeWorkspace;
        expect(ws.questions.length, initialQCount + 1);
        expect(
          ws.sourceDocs.any((SourceDoc d) => d.docType == 'photo_search'),
          isTrue,
        );
        expect(
          ws.questions.first.sourceType,
          'photo_search',
        );

        // Save item 1 to WrongBook (idempotent on library question)
        await tester.tap(find.text('加入错题本').first);
        await tester.pumpAndSettle();
        expect(find.text('已在错题本'), findsWidgets);
        ws = container.read(appStoreProvider).activeWorkspace;
        expect(ws.questions.length, initialQCount + 1);
        expect(ws.wrongItems.length, initialWCount + 1);
        expect(ws.wrongItems.first.addedVia, AddedVia.photoSearch);

        // Batch add remaining item 2 to both Library and WrongBook
        await tester.tap(find.text('全部加入错题本'));
        await tester.pumpAndSettle();
        ws = container.read(appStoreProvider).activeWorkspace;
        expect(ws.questions.length, initialQCount + 2);
        expect(ws.wrongItems.length, initialWCount + 2);
        expect(ws.photoSearchHistory, hasLength(1));

        // Open Copilot directly on a photo-searched question
        await tester.tap(
          find
              .descendant(
                of: find.byType(PhotoSearchPage),
                matching: find.text('问诺诺'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('诺诺'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'AI auto-retry banner shows retry count, clean exhausted fallback & recovers cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const rawSecretError = 'DIO_UPSTREAM_502 {"apiKey":"secret-xyz"}';
        final failingClient = _FailingThenRecoverLlmClient(
          failuresBeforeSuccess: 99,
          errorMessage: rawSecretError,
        );

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              platformMediaServiceProvider.overrideWithValue(
                _FakePlatformMediaService(
                  photoBytes: MathVerifyEngine.tinyTestPngBytes,
                ),
              ),
              overrideLlmClientProvider.overrideWithValue(failingClient),
            ],
            child: const InouApp(),
          ),
        );

        await tester.ensureVisible(find.text('去搜题'));
        await tester.tap(find.text('去搜题'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('相机拍照'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('开始 AI 识题求解'));
        await tester.pump(const Duration(milliseconds: 50));

        // Attempt 1 failed -> automatic retry #1 in progress in banner & PhotoSearch view
        final retryBanner = find.byKey(const ValueKey('ai_retry_banner'));
        expect(retryBanner, findsOneWidget);
        expect(
          find.descendant(
            of: retryBanner,
            matching: find.textContaining('正在自动重试（第 1/2 次）'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(PhotoSearchPage),
            matching: find.textContaining('正在自动重试（第 1/2 次）'),
          ),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 450));
        expect(
          find.descendant(
            of: retryBanner,
            matching: find.textContaining('正在自动重试（第 2/2 次）'),
          ),
          findsOneWidget,
        );

        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InouApp)),
        );
        final st = container.read(appStoreProvider);
        expect(failingClient.calls, 3);
        expect(st.photoSearchErrorMessage, isNotNull);
        expect(st.photoSearchErrorMessage, contains('已自动重试 2 次'));
        expect(st.photoSearchErrorMessage, isNot(contains('DIO_UPSTREAM_502')));
        expect(st.photoSearchErrorMessage, isNot(contains('secret-xyz')));

        // Exhausted banner and PhotoSearch inline error strip both hide raw trace
        expect(find.byKey(const ValueKey('ai_retry_banner')), findsOneWidget);
        expect(find.textContaining('已自动重试 2 次仍未成功'), findsWidgets);

        await tester.tap(find.byTooltip('关闭提示'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai_retry_banner')), findsNothing);
      },
    );

    testWidgets(
      'Settings AI tab detects official vs non-official URLs and persists SSE & socket reuse switches',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpHydrated(
          tester,
          ProviderScope(
            overrides: [
              blobStorageProvider.overrideWithValue(_seededStorage()),
              platformMediaServiceProvider.overrideWithValue(
                _FakePlatformMediaService(),
              ),
            ],
            child: const InouApp(),
          ),
        );

        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();

        final urlField = find.widgetWithText(TextField, 'Base URL / 网关地址');
        await tester.enterText(urlField, 'https://api.jelixcode.com/v1');
        await tester.pumpAndSettle();

        expect(find.textContaining('检测到非官方中转/自建地址'), findsOneWidget);
        final sseSwitch = find.byKey(const ValueKey('settings_prefer_sse_switch'));
        final socketSwitch = find.byKey(
          const ValueKey('settings_disable_socket_switch'),
        );
        expect(tester.widget<SwitchListTile>(sseSwitch).value, isTrue);
        expect(tester.widget<SwitchListTile>(socketSwitch).value, isTrue);

        await tester.enterText(urlField, 'https://api.openai.com/v1');
        await tester.pumpAndSettle();
        expect(find.textContaining('检测到官方接口域名'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(socketSwitch).value, isFalse);

        // Manually toggle both switches and save endpoint
        await tester.ensureVisible(sseSwitch);
        await tester.tap(sseSwitch);
        await tester.pumpAndSettle();
        await tester.ensureVisible(socketSwitch);
        await tester.tap(socketSwitch);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(sseSwitch).value, isFalse);
        expect(tester.widget<SwitchListTile>(socketSwitch).value, isTrue);

        final saveBtn = find.text('保存并启用');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InouApp)),
        );
        final ep = container.read(appStoreProvider).activeEndpoint;
        expect(ep.baseUrl, 'https://api.openai.com/v1');
        expect(ep.preferSse, isFalse);
        expect(ep.disableSocketReuse, isTrue);
      },
    );
  });
}

class _FailingThenRecoverLlmClient implements LLMClient {
  _FailingThenRecoverLlmClient({
    required this.failuresBeforeSuccess,
    required this.errorMessage,
  });

  final int failuresBeforeSuccess;
  final String errorMessage;
  int calls = 0;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (calls <= failuresBeforeSuccess) {
      throw StateError(errorMessage);
    }
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: '{}',
    );
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final msg = await generate(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    return Stream.value(StreamingMessage(modelMessage: msg));
  }
}

class _PhotoSearchFakeVisionLlmClient implements LLMClient {
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final sys = messages
        .whereType<SystemMessage>()
        .map((m) => m.content)
        .join();
    if (sys.contains('版面分析')) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'stop',
        textOutput: jsonEncode({
          'docType': 'paper',
          'detectedSubject': 'math',
          'suggestedTitle': '无答案练习卷',
          'regions': [
            {
              'index': 1,
              'role': 'question',
              'bbox': [80, 50, 360, 950],
              'kindGuess': 'fill',
            },
            {
              'index': 2,
              'role': 'question',
              'bbox': [400, 50, 720, 950],
              'kindGuess': 'solve',
            },
          ],
        }),
      );
    }
    if (sys.contains('题目数字化引擎')) {
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'stop',
        textOutput: jsonEncode({
          'suggestedTitle': '无答案练习卷',
          'detectedSubject': 'math',
          'items': [
            {
              'sortOrder': 1,
              'bbox': [80, 50, 360, 950],
              'question': {
                'schema': 1,
                'kind': 'fill',
                'header': {'title': '无答案几何填空题', 'score': 4},
                'prompt': '等腰三角形腰长为 5，底边为 6，则面积为 ____。',
                'meta': {'subject': 'math', 'grade': 'g9', 'answerSource': 'ai'},
              },
            },
            {
              'sortOrder': 2,
              'bbox': [400, 50, 720, 950],
              'question': {
                'schema': 1,
                'kind': 'solve',
                'header': {'title': '无答案函数计算题', 'score': 6},
                'prompt': '已知 2x - 8 = 0，求 x 的值。',
                'meta': {'subject': 'math', 'grade': 'g9', 'answerSource': 'ai'},
              },
            },
          ],
        }),
      );
    }
    if (sys.contains('拍照搜题')) {
      final usr = messages
          .whereType<UserMessage>()
          .expand((m) => m.contents.whereType<TextPart>())
          .map((p) => p.text)
          .join();
      if (usr.contains('等腰三角形')) {
        return ModelMessage(
          model: modelConfig.model,
          stopReason: 'stop',
          textOutput: jsonEncode({
            'grading': {
              'mode': 'exact',
              'maxScore': 4,
              'answerSets': [
                {
                  'id': 'ans-1',
                  'expected': {
                    'entries': [
                      {
                        'slotId': 's1',
                        'acceptedValues': [
                          {'type': 'number', 'value': 12, 'tolerance': 0},
                        ],
                      },
                    ],
                  },
                },
              ],
            },
            'answerSummary': '12',
            'explanation': [
              {'type': 'text', 'text': '先用勾股定理求高：h = √(5² - 3²) = 4，面积 = 1/2 × 6 × 4 = 12。'},
            ],
            'keyPoints': ['勾股定理求高'],
            'pitfallNote': '底边要先取半再代入勾股定理。',
            'confidence': 0.94,
          }),
        );
      }
      return ModelMessage(
        model: modelConfig.model,
        stopReason: 'stop',
        textOutput: jsonEncode({
          'grading': {
            'mode': 'stepwise_ai',
            'maxScore': 6,
            'finalAnswer': {
              'acceptedValues': [
                {'type': 'number', 'value': 4, 'tolerance': 0},
              ],
            },
          },
          'answerSummary': 'x = 4',
          'explanation': [
            {'type': 'text', 'text': '移项得 2x = 8，系数化为 1 得 x = 4。'},
          ],
          'keyPoints': ['移项求解'],
          'pitfallNote': '移项注意符号变化。',
          'confidence': 0.92,
        }),
      );
    }
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: '{}',
    );
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final msg = await generate(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    return Stream.value(StreamingMessage(modelMessage: msg));
  }
}

class _BlackboardStepFakeLlmClient implements LLMClient {
  _BlackboardStepFakeLlmClient({this.includeTryPrompt = false});

  final bool includeTryPrompt;
  final List<int> stepNumbersRequested = <int>[];
  final List<String> promptsCaptured = <String>[];

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    return ModelMessage(
      model: modelConfig.model,
      stopReason: 'stop',
      textOutput: '{}',
    );
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final userText = messages
        .whereType<UserMessage>()
        .expand((m) => m.contents.whereType<TextPart>())
        .map((p) => p.text)
        .join('\n');
    promptsCaptured.add(userText);

    final List<String> chunks;
    if (userText.contains('【学生反馈内容】') && userText.contains('我猜 b = 0')) {
      chunks = const [
        '[[VERDICT]] wrong\n',
        '[[EMO]] encourage\n',
        '[[FEEDBACK]] 差一点哦，把 x = 1, y = 5 再代入一次看看 b 等于几！\n',
      ];
    } else if (userText.contains('【学生反馈内容】') &&
        (userText.contains('5 = 2 + b') ||
            userText.contains('明白') ||
            userText.contains('b = 3 啦'))) {
      chunks = const [
        '[[VERDICT]] correct\n',
        '[[EMO]] celebrate\n',
        '[[FEEDBACK]] 太棒啦，代点求解完全正确！\n',
      ];
    } else {
      final match = RegExp(r'第\s*(\d+)\s*步').firstMatch(userText);
      final stepNum = int.tryParse(match?.group(1) ?? '') ?? 1;
      stepNumbersRequested.add(stepNum);

      if (stepNum == 1) {
        chunks = [
          '[[TOTAL]] 2\n',
          '[[TITLE]] 审题梳理函数解析式\n',
          '[[EMO]] thinking\n',
          '[[SPOKEN]] 先把已知点坐标和一次函数关系式找出来！\n',
          '[[LINE:white:none]] 直线 y = 2x + b 经过点 (1, 5)\n',
          '[[LINE:yellow:underline]] 关键提示：图像上的点必满足函数解析式\n',
          if (includeTryPrompt)
            '[[TRY_PROMPT]] 把 x=1, y=5 代入能列出什么式子？ | 5 = 2 + b 或 b = 3\n',
          '[[MORE]] true\n',
        ];
      } else {
        chunks = const [
          '[[TOTAL]] 2\n',
          '[[TITLE]] 代入计算并完成收尾\n',
          '[[EMO]] celebrate\n',
          '[[SPOKEN]] 把点坐标代入就能算出 b 的值啦！\n',
          '[[LINE:white:none]] 代入 x = 1, y = 5 得 5 = 2×1 + b\n',
          '[[LINE:green:box]] 解得 b = 3，函数为 y = 2x + 3\n',
          '[[MORE]] false\n',
          '[[TAKEAWAY]] 点在图像上则横纵坐标满足方程。\n',
        ];
      }
    }

    return Stream<StreamingMessage>.fromIterable([
      for (final chunk in chunks)
        StreamingMessage(
          modelMessage: ModelMessage(textOutput: chunk, model: modelConfig.model),
        ),
    ]);
  }
}

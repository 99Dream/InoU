import 'content_block.dart';
import 'content_plain_text.dart';
import 'enums.dart';
import 'question_models.dart';

/// Shared detector and structural rescuer for ordering/sorting questions
/// (`排序题` / `连词成句` / `排句成段` -> `QuestionKind.fill` with
/// `presentation.interaction == 'fill.sequence'`, `body.bank`, and
/// `itemIds`-based grading).
abstract final class SequenceQuestionDetector {
  static final RegExp sequenceCueRegex = RegExp(
    r'(?:排序|排顺序|排一排|排成通顺|排成一(?:句|段)|排列顺序|正确顺序|先后顺序|按.{0,8}排列|正确语序|连词成句|组词成句|连句成段|排句成段|调整语序|句子排序|句段排序|词语排序|事件排序|重新排列|打乱顺序|rearrange|unscramble|put\s+(?:the\s+)?(?:words|phrases|sentences|events|steps)\s+(?:in|into)\s+(?:the\s+)?(?:correct\s+|right\s+)?order|in\s+(?:the\s+)?(?:correct|right)\s+order)',
    caseSensitive: false,
  );

  static const String _circledDigits = '①②③④⑤⑥⑦⑧⑨⑩';
  static const String _parenCircledDigits = '⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽';

  static final RegExp _circledMarker = RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩]');
  static final RegExp _numberedParenMarker = RegExp(
    r'(?:^|\s|[\n])[\(（]([1-9]|10)[\)）]\s*',
  );
  static final RegExp _bracketedNumMarker = RegExp(
    r'(?:^|\s|[\n])[\[【]([1-9]|10)[\]】]\s*',
  );
  static final RegExp _permutationPattern = RegExp(
    r'^[①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽A-Fa-f0-9\-\s→>、，,;；\(\)（）]+$',
  );
  static final RegExp _trailingBlanks = RegExp(r'(?:_{2,}|（\s*）|\(\s*\))$');

  /// Inspects [rawText] (or explicit [instructionHint]) and extracts the
  /// normalized instruction plus >= 2 orderable bank chunks if it represents a
  /// sorting/sequencing problem.
  static ({String instruction, List<({String? label, String text})> items})?
  extractOrderableItems(String rawText, {String instructionHint = ''}) {
    final cleaned = rawText
        .replaceAll('\r\n', '\n')
        .replaceFirst(RegExp(r'^\d+[\.、\)]\s*'), '')
        .trim();
    if (cleaned.isEmpty) return null;

    final fullCueContext = '$instructionHint\n$cleaned';
    final hasCue = sequenceCueRegex.hasMatch(fullCueContext);

    // 1. Circled markers (① ② ③ ...) — works with or without newlines
    final circledMatches = _circledMarker.allMatches(cleaned).toList();
    if (circledMatches.length >= 2) {
      // Ensure it is not a choice option permutation snippet unless instruction precedes markers
      final firstIdx = circledMatches.first.start;
      final instruction = cleaned
          .substring(0, firstIdx)
          .replaceFirst(_trailingBlanks, '')
          .trim();
      final items = <({String? label, String text})>[];
      for (var i = 0; i < circledMatches.length; i++) {
        final marker = circledMatches[i].group(0)!;
        final start = circledMatches[i].end;
        final end = i + 1 < circledMatches.length
            ? circledMatches[i + 1].start
            : cleaned.length;
        final body = cleaned.substring(start, end).trim();
        if (body.isNotEmpty) {
          items.add((label: marker, text: '$marker $body'));
        }
      }
      if (items.length >= 2 && (hasCue || firstIdx > 0 || items.length >= 3)) {
        return (
          instruction: instruction.isEmpty ? '请按正确顺序排列以下内容：' : instruction,
          items: items,
        );
      }
    }

    if (!hasCue) return null;

    // 2. Parenthesized / bracketed numbered items: (1) ... (2) ...
    for (final markerRegex in [_numberedParenMarker, _bracketedNumMarker]) {
      final matches = markerRegex.allMatches(cleaned).toList();
      if (matches.length >= 2) {
        final firstStart = matches.first.start;
        final instruction = cleaned
            .substring(0, firstStart)
            .replaceFirst(_trailingBlanks, '')
            .trim();
        final items = <({String? label, String text})>[];
        for (var i = 0; i < matches.length; i++) {
          final numStr = matches[i].group(1)!;
          final label = '($numStr)';
          final start = matches[i].end;
          final end = i + 1 < matches.length
              ? matches[i + 1].start
              : cleaned.length;
          final body = cleaned.substring(start, end).trim();
          if (body.isNotEmpty) {
            items.add((label: label, text: '$label $body'));
          }
        }
        if (items.length >= 2) {
          return (
            instruction: instruction.isEmpty ? '请按正确顺序排列：' : instruction,
            items: items,
          );
        }
      }
    }

    // 3. Separated word / phrase bank (e.g. "连词成句：you / how / are / ?" or "you, are, how")
    final bankSplit = _tryExtractDelimitedBank(cleaned);
    if (bankSplit != null && bankSplit.items.length >= 2) {
      return bankSplit;
    }

    return null;
  }

  static ({String instruction, List<({String? label, String text})> items})?
  _tryExtractDelimitedBank(String cleaned) {
    // Prefer tail after colon when present (e.g., "连词成句：how / are / you / ?")
    var instruction = '';
    var payload = cleaned;
    final colonMatch = RegExp(
      r'^(.*?[:：])\s*(.+)$',
      dotAll: true,
    ).firstMatch(cleaned);
    if (colonMatch != null) {
      final head = colonMatch.group(1)!.trim();
      final tail = colonMatch.group(2)!.trim();
      if (sequenceCueRegex.hasMatch(head) && tail.isNotEmpty) {
        instruction = head;
        payload = tail;
      }
    }

    // Remove trailing underscores / blank placeholders & empty parens
    payload = payload
        .replaceAll(RegExp(r'\s*(?:_{2,}|（\s*）|\(\s*\))\s*$'), '')
        .trim();
    if (payload.isEmpty) return null;

    // 3a. Explicit slash / pipe / arrow separators
    if (payload.contains('/') || payload.contains('|')) {
      final sep = payload.contains('/') ? '/' : '|';
      final tokens = payload
          .split(sep)
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.length >= 2 && tokens.length <= 20) {
        return (
          instruction: instruction.isEmpty ? '连词/排列成句：' : instruction,
          items: [for (final tok in tokens) (label: null, text: tok)],
        );
      }
    }

    // 3b. Comma / enumeration-comma separated tokens when ordering cue is explicit
    final multiLineOrComma = payload
        .split(RegExp(r'[,，、;；\n]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (multiLineOrComma.length >= 2 && multiLineOrComma.length <= 18) {
      // Avoid splitting long full paragraphs that happen to have commas inside prose sentences
      final avgLen =
          multiLineOrComma.fold<int>(0, (s, e) => s + e.length) /
          multiLineOrComma.length;
      if (avgLen <= 28) {
        return (
          instruction: instruction.isEmpty ? '按正确顺序排列：' : instruction,
          items: [for (final tok in multiLineOrComma) (label: null, text: tok)],
        );
      }
    }

    // 3c. Space-separated scrambled English words (e.g. "连词成句：how you are ?")
    if (instruction.isNotEmpty &&
        !payload.contains(RegExp(r'[\u4e00-\u9fff]'))) {
      final spaceTokens = payload
          .split(RegExp(r'\s+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (spaceTokens.length >= 3 && spaceTokens.length <= 16) {
        return (
          instruction: instruction,
          items: [for (final tok in spaceTokens) (label: null, text: tok)],
        );
      }
    }

    // 3d. Multiline real-exam format where Chinese context ends with 。/！ and the
    // trailing line lists scrambled ASCII tokens ("flash   the   in   museum   No   .")
    final lines = cleaned
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length >= 2) {
      final lastLine = lines.last
          .replaceAll(RegExp(r'\s*(?:_{2,}|（\s*）|\(\s*\))\s*$'), '')
          .trim();
      if (lastLine.isNotEmpty &&
          !lastLine.contains(RegExp(r'[\u4e00-\u9fff]'))) {
        final tokens = lastLine
            .split(RegExp(r'\s+'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (tokens.length >= 3 && tokens.length <= 18) {
          final prefixInstruction = lines
              .sublist(0, lines.length - 1)
              .join('\n');
          return (
            instruction: prefixInstruction.isEmpty
                ? '连词成句：'
                : prefixInstruction,
            items: [for (final tok in tokens) (label: null, text: tok)],
          );
        }
      }
    }

    return null;
  }

  /// Builds canonical `body.bank` entries from extracted items.
  static List<Map<String, Object?>> buildBankFromItems(
    List<({String? label, String text})> items,
  ) {
    return [
      for (var i = 0; i < items.length; i++)
        {
          'id': 'w${i + 1}',
          if (items[i].label != null) 'label': items[i].label,
          'content': [
            {'type': 'text', 'text': items[i].text},
          ],
        },
    ];
  }

  /// Coerces heterogeneous LLM/JSON `bank` / `words` / `tokens` / `items` arrays
  /// into canonical `body.bank` entries.
  static List<Map<String, Object?>> normalizeBankList(Object? rawBank) {
    if (rawBank is! List<Object?>) return const [];
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < rawBank.length; i++) {
      final item = rawBank[i];
      if (item is String && item.trim().isNotEmpty) {
        out.add({
          'id': 'w${i + 1}',
          'content': [
            {'type': 'text', 'text': item.trim()},
          ],
        });
      } else if (item is Map) {
        final m = item.map((k, v) => MapEntry(k.toString(), v));
        final id = (m['id'] ?? 'w${i + 1}').toString().trim();
        final contentObj = m['content'];
        List<Map<String, Object?>> blocks;
        if (contentObj is List && contentObj.isNotEmpty) {
          blocks = contentObj
              .whereType<Map<Object?, Object?>>()
              .map((b) => b.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false);
        } else {
          final txt = (m['text'] ?? m['value'] ?? m['label'] ?? '')
              .toString()
              .trim();
          blocks = [
            {'type': 'text', 'text': txt.isEmpty ? id : txt},
          ];
        }
        out.add({
          'id': id.isEmpty ? 'w${i + 1}' : id,
          if (m['label'] != null) 'label': m['label'],
          'content': blocks,
        });
      }
    }
    return out;
  }

  /// Maps an answer string (such as `"③①②"`, `"3, 1, 2"`, `"C A B"`,
  /// `"w3 w1 w2"`, or assembled sentence `"How are you?"`) back into ordered
  /// `body.bank` IDs (`['w3', 'w1', 'w2']`).
  static List<String> matchAnswerToBankIds(
    String answerRaw,
    List<Map<String, Object?>> bank,
  ) {
    final trimmed = answerRaw.trim();
    if (trimmed.isEmpty || bank.isEmpty) return const [];

    final bankIds = bank.map((b) => b['id']?.toString() ?? '').toList();

    // 1. Direct bank ID sequence ("w3 w1 w2" or "w3,w1,w2")
    final explicitIds = RegExp(r'\bw\d+\b')
        .allMatches(trimmed)
        .map((m) => m.group(0)!)
        .where(bankIds.contains)
        .toList();
    if (explicitIds.length >= 2) return explicitIds;

    // 2. Circled digits ("③①②")
    final circledMatches = RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽]')
        .allMatches(trimmed)
        .toList();
    if (circledMatches.isNotEmpty) {
      final mapped = <String>[];
      for (final m in circledMatches) {
        final ch = m.group(0)!;
        var idx = _circledDigits.indexOf(ch);
        if (idx < 0) idx = _parenCircledDigits.indexOf(ch);
        if (idx >= 0 && idx < bankIds.length) {
          final id = bankIds[idx];
          if (!mapped.contains(id)) mapped.add(id);
        }
      }
      if (mapped.length >= 2) return mapped;
    }

    // 3. Pure numeric or letter indices ("3-1-2", "3 1 2", "C B A", "(3)(1)(2)")
    if (_permutationPattern.hasMatch(trimmed)) {
      final numTokens = RegExp(r'\d+').allMatches(trimmed).toList();
      if (numTokens.length >= 2) {
        final mapped = <String>[];
        for (final m in numTokens) {
          final idx = int.tryParse(m.group(0)!);
          if (idx != null && idx >= 1 && idx <= bankIds.length) {
            final id = bankIds[idx - 1];
            if (!mapped.contains(id)) mapped.add(id);
          }
        }
        if (mapped.length >= 2) return mapped;
      }

      final letterTokens = RegExp(r'[A-Fa-f]').allMatches(trimmed).toList();
      if (letterTokens.length >= 2) {
        final mapped = <String>[];
        for (final m in letterTokens) {
          final idx = m.group(0)!.toUpperCase().codeUnitAt(0) - 65;
          if (idx >= 0 && idx < bankIds.length) {
            final id = bankIds[idx];
            if (!mapped.contains(id)) mapped.add(id);
          }
        }
        if (mapped.length >= 2) return mapped;
      }
    }

    // 4. Assembled sentence / ordered text matching (e.g. "How are you?")
    final bankTexts = <({String id, String clean})>[];
    for (var i = 0; i < bank.length; i++) {
      final id = bankIds[i];
      final rawContent = bank[i]['content'];
      var txt = rawContent is List
          ? ContentTextUtils.extractPlainText(
              rawContent
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (m) => ContentBlock.fromJson(
                      m.map((k, v) => MapEntry(k.toString(), v)),
                    ),
                  )
                  .toList(),
            )
          : '';
      txt = txt
          .replaceFirst(RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽]\s*'), '')
          .replaceFirst(RegExp(r'^[\(（]\d+[\)）]\s*'), '')
          .trim();
      bankTexts.add((id: id, clean: txt.toLowerCase()));
    }

    // Tokenize sentence separating punctuation tokens cleanly ("you?" -> ["you", "?"])
    final normAnswer = trimmed
        .replaceAllMapped(RegExp(r'([?.!,。？！，])'), (m) => ' ${m.group(1)} ')
        .trim()
        .toLowerCase();

    var cursor = normAnswer;
    final used = <String>{};
    final result = <String>[];
    while (cursor.isNotEmpty) {
      cursor = cursor.replaceFirst(RegExp(r'^[\s/→>]+'), '');
      if (cursor.isEmpty) break;
      // Match longest unused bank item at current prefix
      ({String id, String clean})? best;
      for (final item in bankTexts) {
        if (used.contains(item.id) || item.clean.isEmpty) continue;
        final itemNorm = item.clean
            .replaceAllMapped(RegExp(r'([?.!,。？！，])'), (m) => ' ${m.group(1)} ')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
        final cursorCollapsed = cursor.replaceAll(RegExp(r'\s+'), ' ');
        if (cursorCollapsed.startsWith(itemNorm)) {
          if (best == null || itemNorm.length > best.clean.length) {
            best = (id: item.id, clean: itemNorm);
          }
        }
      }
      if (best != null) {
        used.add(best.id);
        result.add(best.id);
        final escaped = RegExp.escape(best.clean).replaceAll(r'\ ', r'\s+');
        cursor = cursor.replaceFirst(RegExp('^$escaped'), '').trimLeft();
      } else {
        // Advance past one token to tolerate minor punctuation mismatches
        final spaceIdx = cursor.indexOf(RegExp(r'\s'));
        if (spaceIdx < 0) break;
        cursor = cursor.substring(spaceIdx + 1);
      }
    }

    return result.length >= 2 ? result : const [];
  }

  /// Checks if [q] was misclassified as `response`, `solve`, `fill` (plain input),
  /// or `choice` (with non-permutation fragment options) when it is actually a
  /// sequencing / sorting task, and promotes it to `QuestionKind.fill` +
  /// `interaction == 'fill.sequence'`. Returns `null` if no rescue is needed.
  static Question? tryRescueAsSequence(Question q, {String? rawAnswerHint}) {
    if (q.isSequence) {
      final fixedGrading = _ensureSequenceGrading(
        q,
        rawAnswerHint: rawAnswerHint,
      );
      return fixedGrading;
    }

    if (q.kind == QuestionKind.match ||
        q.kind == QuestionKind.classify ||
        q.kind == QuestionKind.group ||
        q.kind == QuestionKind.draw ||
        q.kind == QuestionKind.spatial ||
        q.kind == QuestionKind.write) {
      return null;
    }

    final existingBank = normalizeBankList(q.body['bank']);
    final stemText = q.plainText;
    final headerTitle = q.header.title;

    // Guard against corrupting valid multiple-choice sorting questions
    // (e.g. A. ③①②④  B. ③②①④  C. ①②③④  D. ②①③④ with single-letter answer).
    if (q.kind == QuestionKind.choice) {
      final rawOpts = q.body['options'] as List<Object?>? ?? const [];
      final optStrings = rawOpts.whereType<Map<Object?, Object?>>().map((o) {
        final c = o['content'];
        return c is List
            ? ContentTextUtils.extractPlainText(
                c
                    .whereType<Map<Object?, Object?>>()
                    .map(
                      (m) => ContentBlock.fromJson(
                        m.map((k, v) => MapEntry(k.toString(), v)),
                      ),
                    )
                    .toList(),
              )
            : '';
      }).toList();
      final looksLikeMcqSequences =
          optStrings.isNotEmpty &&
          optStrings.every((s) => _permutationPattern.hasMatch(s.trim()));
      if (looksLikeMcqSequences || existingBank.isEmpty) {
        // Keep real A/B/C/D MCQ untouched unless the options themselves are sentences with multi-item ordering answer
        final rawAns = rawAnswerHint ?? _extractScalarAnswerFromGrading(q);
        final singleLetterMcq = RegExp(r'^[A-Fa-f]$').hasMatch(rawAns.trim());
        if (looksLikeMcqSequences || singleLetterMcq) {
          return null;
        }
      }
    }

    List<Map<String, Object?>> bank = existingBank;
    String instruction = stemText;

    if (bank.isEmpty) {
      if (q.kind == QuestionKind.choice &&
          sequenceCueRegex.hasMatch('$headerTitle\n$stemText')) {
        final rawOpts = q.body['options'] as List<Object?>? ?? const [];
        final extractedFromOpts = <({String? label, String text})>[];
        for (final o in rawOpts.whereType<Map<Object?, Object?>>()) {
          final oid = o['id']?.toString() ?? '';
          final c = o['content'];
          final txt = c is List
              ? ContentTextUtils.extractPlainText(
                  c
                      .whereType<Map<Object?, Object?>>()
                      .map(
                        (m) => ContentBlock.fromJson(
                          m.map((k, v) => MapEntry(k.toString(), v)),
                        ),
                      )
                      .toList(),
                )
              : '';
          if (txt.trim().isNotEmpty) {
            extractedFromOpts.add((
              label: oid.isEmpty ? null : oid,
              text: oid.isEmpty ? txt.trim() : '$oid. ${txt.trim()}',
            ));
          }
        }
        if (extractedFromOpts.length >= 2) {
          bank = buildBankFromItems(extractedFromOpts);
        }
      }
    }

    if (bank.isEmpty) {
      final extracted = extractOrderableItems(
        stemText,
        instructionHint: headerTitle,
      );
      if (extracted == null || extracted.items.length < 2) return null;
      instruction = extracted.instruction;
      bank = buildBankFromItems(extracted.items);
    }

    final rawAns = (rawAnswerHint != null && rawAnswerHint.trim().isNotEmpty)
        ? rawAnswerHint.trim()
        : _extractScalarAnswerFromGrading(q);
    final matchedIds = matchAnswerToBankIds(rawAns, bank);

    final slots =
        (q.body['slots'] is List && (q.body['slots']! as List).isNotEmpty)
        ? List<Map<String, Object?>>.from(
            (q.body['slots']! as List).whereType<Map<Object?, Object?>>().map(
              (m) => m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
        : const [
            {'id': 's1', 'label': '排序结果', 'valueType': 'text'},
          ];
    final firstSlotId = slots.first['id']?.toString() ?? 's1';

    final promptBlocks = <ContentBlock>[
      TextBlock(
        instruction.trim().isEmpty ? '按正确顺序排列以下内容：' : instruction.trim(),
      ),
      const TextBlock(' '),
      SlotBlock(firstSlotId),
    ];

    final grading = <String, Object?>{
      'mode': 'exact',
      'maxScore': q.maxScore,
      'perSlotScore': {firstSlotId: q.maxScore},
      'answerSets': matchedIds.isNotEmpty
          ? [
              {
                'id': 'ans-1',
                'expected': {
                  'entries': [
                    {
                      'slotId': firstSlotId,
                      'acceptedValues': [
                        {'type': 'items', 'itemIds': matchedIds},
                      ],
                    },
                  ],
                },
              },
            ]
          : const <Object?>[],
    };

    return q.copyWith(
      kind: QuestionKind.fill,
      prompt: promptBlocks,
      body: Map<String, Object?>.unmodifiable({'slots': slots, 'bank': bank}),
      presentation: const QuestionPresentation(interaction: 'fill.sequence'),
      grading: Map<String, Object?>.unmodifiable(grading),
      meta: q.meta.copyWith(
        answerSource: matchedIds.isNotEmpty
            ? (q.meta.answerSource == AnswerSource.user
                  ? AnswerSource.user
                  : q.meta.answerSource)
            : AnswerSource.ai,
        uncertainNote: matchedIds.isEmpty ? '已识别为排序题，请确认词块顺序与标准排序答案。' : null,
      ),
    );
  }

  /// Ensures an already-marked `fill.sequence` question uses `type: 'items'`
  /// (`itemIds`) instead of a flat string if grading was patched as text.
  static Question? _ensureSequenceGrading(Question q, {String? rawAnswerHint}) {
    final bank = normalizeBankList(q.body['bank']);
    if (bank.isEmpty) return null;
    final sets = q.grading['answerSets'] as List<Object?>? ?? const [];
    final hasItemsAlready = sets.any((s) {
      if (s is! Map) return false;
      final entries = (s['expected'] as Map?)?['entries'] as List?;
      if (entries == null || entries.isEmpty) return false;
      final firstAcc = (entries.first as Map?)?['acceptedValues'] as List?;
      return firstAcc != null &&
          firstAcc.any(
            (a) =>
                a is Map &&
                a['type'] == 'items' &&
                (a['itemIds'] as List?)?.isNotEmpty == true,
          );
    });
    if (hasItemsAlready) return null;

    final rawAns = (rawAnswerHint != null && rawAnswerHint.trim().isNotEmpty)
        ? rawAnswerHint.trim()
        : _extractScalarAnswerFromGrading(q);
    final matched = matchAnswerToBankIds(rawAns, bank);
    if (matched.isEmpty) return null;

    final slots = q.body['slots'] as List<Object?>? ?? const [];
    final firstSlotId = (slots.isNotEmpty && slots.first is Map)
        ? ((slots.first! as Map)['id']?.toString() ?? 's1')
        : 's1';

    return q.copyWith(
      grading: Map<String, Object?>.unmodifiable({
        'mode': 'exact',
        'maxScore': q.maxScore,
        'perSlotScore': {firstSlotId: q.maxScore},
        'answerSets': [
          {
            'id': 'ans-1',
            'expected': {
              'entries': [
                {
                  'slotId': firstSlotId,
                  'acceptedValues': [
                    {'type': 'items', 'itemIds': matched},
                  ],
                },
              ],
            },
          },
        ],
      }),
    );
  }

  static String _extractScalarAnswerFromGrading(Question q) {
    final sets = q.grading['answerSets'] as List<Object?>? ?? const [];
    if (sets.isNotEmpty && sets.first is Map) {
      final exp = (sets.first! as Map)['expected'];
      if (exp is Map && exp['entries'] is List) {
        final entries = exp['entries'] as List;
        if (entries.isNotEmpty && entries.first is Map) {
          final acc = (entries.first as Map)['acceptedValues'] as List?;
          if (acc != null && acc.isNotEmpty && acc.first is Map) {
            final first = acc.first as Map;
            if (first['itemIds'] is List) {
              return (first['itemIds'] as List).join(' ');
            }
            return (first['value'] ?? first['text'] ?? '').toString();
          }
        }
      }
      if (exp is Map && exp['selectedIds'] is List) {
        return (exp['selectedIds'] as List).join(' ');
      }
    }
    final fin = q.grading['finalAnswer'];
    if (fin is Map && fin['acceptedValues'] is List) {
      final acc = fin['acceptedValues'] as List;
      if (acc.isNotEmpty && acc.first is Map) {
        final first = acc.first as Map;
        return (first['value'] ?? first['text'] ?? '').toString();
      }
    }
    return (q.grading['referenceAnswer'] ?? q.grading['answer'] ?? '')
        .toString();
  }
}

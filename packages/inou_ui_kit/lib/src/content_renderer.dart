import 'dart:convert';

import 'package:inou_domain/inou_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'inou_theme.dart';

/// Pure-Flutter readable LaTeX math display view converting common K12 LaTeX
/// constructs (`\frac`, `\sqrt`, `\times`, `\div`, `\le`, `\ge`, `\implies`,
/// `^2`, `_1`, Greek symbols, spacing commands) into clean typographic glyphs.
class MathBlockView extends StatelessWidget {
  const MathBlockView({
    super.key,
    required this.latex,
    this.display = false,
    this.textStyle,
  });

  final String latex;
  final bool display;
  final TextStyle? textStyle;

  static String formatReadableLatex(String raw) {
    var s = raw.trim();
    s = s
        .replaceAll(r'\;', ' ')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\quad', '  ')
        .replaceAll(r'\qquad', '    ')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\pm', '±')
        .replaceAll(r'\mp', '∓')
        .replaceAll(r'\le', '≤')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\ge', '≥')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\ne', '≠')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\approx', '≈')
        .replaceAll(r'\implies', ' ⇒ ')
        .replaceAll(r'\Rightarrow', ' ⇒ ')
        .replaceAll(r'\rightarrow', ' → ')
        .replaceAll(r'\to', ' → ')
        .replaceAll(r'\infty', '∞')
        .replaceAll(r'\pi', 'π')
        .replaceAll(r'\Delta', 'Δ')
        .replaceAll(r'\alpha', 'α')
        .replaceAll(r'\beta', 'β')
        .replaceAll(r'\theta', 'θ')
        .replaceAll(r'\angle', '∠')
        .replaceAll(r'\triangle', '△')
        .replaceAll(r'\perp', '⊥')
        .replaceAll(r'\parallel', '∥')
        .replaceAll(r'\because', '∵')
        .replaceAll(r'\therefore', '∴')
        .replaceAll(r'\circ', '°')
        .replaceAll(r'\left(', '(')
        .replaceAll(r'\right)', ')')
        .replaceAll(r'\left[', '[')
        .replaceAll(r'\right]', ']')
        .replaceAll(r'\overline', '')
        .replaceAll(r'\vec', '');

    // Iteratively resolve \frac{a}{b} -> (a)/(b) or clean a/b
    final fracPattern = RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}');
    for (var i = 0; i < 4; i++) {
      s = s.replaceAllMapped(fracPattern, (m) {
        final num = m.group(1)!.trim();
        final den = m.group(2)!.trim();
        final simpleNum = !num.contains(' ') && num.length <= 3;
        final simpleDen = !den.contains(' ') && den.length <= 3;
        return '${simpleNum ? num : '($num)'}/${simpleDen ? den : '($den)'}';
      });
    }

    // \sqrt{x} -> √(x) or √x
    s = s.replaceAllMapped(RegExp(r'\\sqrt\{([^{}]+)\}'), (m) {
      final inner = m.group(1)!.trim();
      return inner.length <= 2 ? '√$inner' : '√($inner)';
    });

    // Simple superscripts & subscripts
    const supMap = {
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
      '+': '⁺',
      '-': '⁻',
      'n': 'ⁿ',
    };
    const subMap = {
      '0': '₀',
      '1': '₁',
      '2': '₂',
      '3': '₃',
      '4': '₄',
      '5': '₅',
      '6': '₆',
      '7': '₇',
      '8': '₈',
      '9': '₉',
      'n': 'ₙ',
      'i': 'ᵢ',
    };

    s = s.replaceAllMapped(RegExp(r'\^\{([^{}]+)\}|\^([0-9n+-])'), (m) {
      final body = m.group(1) ?? m.group(2) ?? '';
      if (body.split('').every(supMap.containsKey)) {
        return body.split('').map((c) => supMap[c]!).join();
      }
      return '^($body)';
    });

    s = s.replaceAllMapped(RegExp(r'_\{([^{}]+)\}|_([0-9ni])'), (m) {
      final body = m.group(1) ?? m.group(2) ?? '';
      if (body.split('').every(subMap.containsKey)) {
        return body.split('').map((c) => subMap[c]!).join();
      }
      return '_$body';
    });

    return s.replaceAll('{', '').replaceAll('}', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final formatted = formatReadableLatex(latex);
    final baseStyle = (textStyle ?? DefaultTextStyle.of(context).style)
        .copyWith(
          fontWeight: FontWeight.w600,
          color: t.textPrimary,
          letterSpacing: 0.2,
        );

    if (display) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.borderHairline),
        ),
        child: Center(
          child: SelectableText(
            formatted,
            style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 15) + 1),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(formatted, style: baseStyle.copyWith(color: t.accent)),
    );
  }
}

/// Renders structured `List<ContentBlock>` stems, passages, tables, diagrams,
/// inline slots, and explanations cleanly without HTML or WebView overhead.
class ContentBlockRenderer extends StatelessWidget {
  const ContentBlockRenderer({
    super.key,
    required this.blocks,
    this.textStyle,
    this.slotValues = const {},
    this.activeSlotId,
    this.onSlotTap,
    this.imageAssetBytes = const {},
  });

  final List<ContentBlock> blocks;
  final TextStyle? textStyle;
  final Map<String, String> slotValues;
  final String? activeSlotId;
  final ValueChanged<String>? onSlotTap;
  final Map<String, String> imageAssetBytes;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    final baseStyle =
        (textStyle ??
        TextStyle(fontSize: 15, height: 1.65, color: context.inou.textPrimary));

    final children = <Widget>[];
    final inlineBuf = <ContentBlock>[];

    void flushInline() {
      if (inlineBuf.isEmpty) return;
      children.add(
        _InlineParagraph(
          blocks: List<ContentBlock>.from(inlineBuf),
          baseStyle: baseStyle,
          slotValues: slotValues,
          activeSlotId: activeSlotId,
          onSlotTap: onSlotTap,
        ),
      );
      inlineBuf.clear();
    }

    for (final block in blocks) {
      final isInline =
          block is TextBlock ||
          block is RichTextBlock ||
          block is SlotBlock ||
          (block is MathBlock && !block.display);
      if (isInline) {
        inlineBuf.add(block);
      } else {
        flushInline();
        children.add(_buildBlockWidget(context, block, baseStyle));
      }
    }
    flushInline();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }

  Widget _buildBlockWidget(
    BuildContext context,
    ContentBlock block,
    TextStyle baseStyle,
  ) {
    final t = context.inou;
    switch (block) {
      case MathBlock(:final latex, :final display):
        return MathBlockView(
          latex: latex,
          display: display,
          textStyle: baseStyle,
        );
      case PassageBlock(:final title, :final paragraphs):
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: t.accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null && title.isNotEmpty) ...[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final p in paragraphs) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.no != null && p.no!.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: t.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: t.borderHairline),
                          ),
                          child: Text(
                            p.no!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: ContentBlockRenderer(
                          blocks: p.content,
                          textStyle: baseStyle.copyWith(fontSize: 14),
                          slotValues: slotValues,
                          activeSlotId: activeSlotId,
                          onSlotTap: onSlotTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      case TableBlock(:final header, :final rows, :final caption):
        final colCount =
            header?.length ?? (rows.isNotEmpty ? rows.first.length : 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (caption != null && caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  caption,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Table(
                border: TableBorder.all(color: t.borderHairline),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  if (header != null)
                    TableRow(
                      decoration: BoxDecoration(color: t.surfaceMuted),
                      children: [
                        for (final cell in header)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ContentBlockRenderer(
                              blocks: cell,
                              textStyle: baseStyle.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (var c = 0; c < colCount; c++)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: c < row.length
                                ? ContentBlockRenderer(
                                    blocks: row[c],
                                    textStyle: baseStyle.copyWith(fontSize: 13),
                                  )
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      case ImageBlock(:final assetId, :final alt, :final width):
        return _buildVisualBox(
          t,
          assetId: assetId,
          alt: alt,
          width: width,
          caption: null,
        );
      case FigureBlock(:final assetId, :final alt, :final caption):
        return _buildVisualBox(
          t,
          assetId: assetId,
          alt: alt,
          width: null,
          caption: caption,
        );
      case MediaPlaceholderBlock(:final mediaType, :final transcript):
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.borderHairline),
          ),
          child: Row(
            children: [
              Icon(Icons.graphic_eq, size: 18, color: t.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  transcript?.isNotEmpty == true
                      ? '[$mediaType 文本] $transcript'
                      : '[$mediaType 媒体占位]',
                  style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                ),
              ),
            ],
          ),
        );
      case TextBlock():
      case RichTextBlock():
      case SlotBlock():
        return const SizedBox.shrink();
    }
  }

  Widget _buildVisualBox(
    InouTokens t, {
    required String assetId,
    required String? alt,
    required double? width,
    required String? caption,
  }) {
    final rawB64 = imageAssetBytes[assetId];
    if (rawB64 != null && rawB64.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          base64Decode(rawB64),
          width: width,
          fit: BoxFit.contain,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.borderHairline),
      ),
      child: Row(
        children: [
          Icon(Icons.polyline_outlined, size: 22, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption ?? '题配示意图 ($assetId)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                if (alt != null && alt.isNotEmpty)
                  Text(
                    alt,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineParagraph extends StatelessWidget {
  const _InlineParagraph({
    required this.blocks,
    required this.baseStyle,
    required this.slotValues,
    required this.activeSlotId,
    required this.onSlotTap,
  });

  final List<ContentBlock> blocks;
  final TextStyle baseStyle;
  final Map<String, String> slotValues;
  final String? activeSlotId;
  final ValueChanged<String>? onSlotTap;

  @override
  Widget build(BuildContext context) {
    final t = context.inou;
    final spans = <InlineSpan>[];

    for (final block in blocks) {
      switch (block) {
        case TextBlock(:final text):
          spans.add(TextSpan(text: text, style: baseStyle));
        case RichTextBlock(spans: final richSpans):
          for (final rs in richSpans) {
            spans.add(
              TextSpan(
                text: rs.text,
                style: baseStyle.copyWith(
                  fontWeight: rs.bold ? FontWeight.w700 : null,
                  fontStyle: rs.italic ? FontStyle.italic : null,
                  decoration: rs.underline ? TextDecoration.underline : null,
                ),
              ),
            );
          }
        case MathBlock(:final latex):
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: MathBlockView(
                latex: latex,
                display: false,
                textStyle: baseStyle,
              ),
            ),
          );
        case SlotBlock(:final slotId):
          final val = slotValues[slotId]?.trim() ?? '';
          final isActive = activeSlotId == slotId;
          final filledColor = t.isDark ? const Color(0xFF93C5FD) : t.accent;
          final emptyColor = isActive ? filledColor : t.textSecondary;
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: onSlotTap == null ? null : () => onSlotTap!(slotId),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(minWidth: 52),
                  decoration: BoxDecoration(
                    color: isActive ? t.accentSoft : t.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? t.accent : t.borderHairline,
                      width: isActive ? 1.8 : 1,
                    ),
                  ),
                  child: Text(
                    val.isNotEmpty ? val : '  ($slotId)  ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (baseStyle.fontSize ?? 15) - 1,
                      fontWeight: FontWeight.w600,
                      color: val.isNotEmpty ? filledColor : emptyColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        default:
          break;
      }
    }

    return Text.rich(TextSpan(children: spans));
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'content_block.dart';

/// Utilities to extract searchable plain text, compute content SHA-256 hashes,
/// and detect near-duplicate questions using a deterministic 64-bit SimHash.
abstract final class ContentTextUtils {
  /// Extracts readable plain text from structured [ContentBlock]s.
  static String extractPlainText(List<ContentBlock> blocks) {
    final buf = StringBuffer();
    for (final block in blocks) {
      switch (block) {
        case TextBlock(:final text):
          buf.write(text);
        case RichTextBlock(:final spans):
          for (final s in spans) {
            buf.write(s.text);
          }
        case MathBlock(:final latex):
          buf.write(' $latex ');
        case TableBlock(:final header, :final rows, :final caption):
          if (caption != null && caption.isNotEmpty) {
            buf.write(' $caption ');
          }
          if (header != null) {
            for (final cell in header) {
              buf.write(' ${extractPlainText(cell)} ');
            }
          }
          for (final row in rows) {
            for (final cell in row) {
              buf.write(' ${extractPlainText(cell)} ');
            }
          }
        case PassageBlock(:final title, :final paragraphs):
          if (title != null && title.isNotEmpty) {
            buf.write(' $title ');
          }
          for (final p in paragraphs) {
            buf.write(' ${extractPlainText(p.content)} ');
          }
        case FigureBlock(:final alt, :final caption):
          if (caption != null) buf.write(' $caption ');
          if (alt != null) buf.write(' $alt ');
        case ImageBlock(:final alt):
          if (alt != null) buf.write(' $alt ');
        case SlotBlock():
          buf.write(' ____ ');
        case MediaPlaceholderBlock(:final transcript):
          if (transcript != null) buf.write(' $transcript ');
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalizes Chinese/English text for deduplication and answer comparison.
  static String normalizeText(
    String raw, {
    bool trim = true,
    bool caseSensitive = false,
    bool fullWidthToHalf = true,
    bool ignorePunct = true,
  }) {
    var s = raw;
    if (fullWidthToHalf) {
      final codeUnits = s.codeUnits.map((c) {
        if (c == 0x3000) return 0x20;
        if (c >= 0xFF01 && c <= 0xFF5E) return c - 0xFEE0;
        return c;
      }).toList();
      s = String.fromCharCodes(codeUnits);
    }
    if (!caseSensitive) {
      s = s.toLowerCase();
    }
    if (ignorePunct) {
      s = s.replaceAll(RegExp(r'''[\s,.;:!?'"`()\[\]{}，。；：！？、“”‘’（）【】]'''), '');
    } else if (trim) {
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return s;
  }

  static String sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Deterministic 64-bit character-trigram SimHash for near-duplicate checks.
  static int simHash64(String rawText) {
    final norm = normalizeText(rawText, ignorePunct: true);
    if (norm.isEmpty) return 0;

    final weights = List<int>.filled(64, 0);
    final shingles = <String>[];
    if (norm.length < 3) {
      shingles.add(norm);
    } else {
      for (var i = 0; i <= norm.length - 3; i++) {
        shingles.add(norm.substring(i, i + 3));
      }
    }

    for (final g in shingles) {
      final digest = sha256.convert(utf8.encode(g)).bytes;
      var h = 0;
      for (var b = 0; b < 8; b++) {
        h = (h << 8) | (digest[b] & 0xFF);
      }
      for (var bit = 0; bit < 64; bit++) {
        final isSet = ((h >> bit) & 1) == 1;
        weights[bit] += isSet ? 1 : -1;
      }
    }

    var result = 0;
    for (var bit = 0; bit < 64; bit++) {
      if (weights[bit] > 0) {
        result |= 1 << bit;
      }
    }
    return result;
  }

  static int hammingDistance64(int a, int b) {
    var x = a ^ b;
    var count = 0;
    for (var i = 0; i < 64; i++) {
      if ((x & 1) == 1) count++;
      x = x >>> 1;
    }
    return count;
  }

  /// Computes character-trigram Jaccard similarity in `[0.0, 1.0]`.
  static double trigramJaccard(String textA, String textB) {
    final normA = normalizeText(textA);
    final normB = normalizeText(textB);
    if (normA.isEmpty || normB.isEmpty) return 0.0;
    Set<String> trigrams(String s) {
      if (s.length < 3) return {s};
      return {for (var i = 0; i <= s.length - 3; i++) s.substring(i, i + 3)};
    }

    final setA = trigrams(normA);
    final setB = trigrams(normB);
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  /// True when normalized texts match identically, trigram Jaccard >= 0.65,
  /// or SimHash Hamming distance is within [threshold].
  static bool isLikelyDuplicate(
    String textA,
    String textB, {
    int threshold = 3,
  }) {
    final normA = normalizeText(textA);
    final normB = normalizeText(textB);
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;
    if (trigramJaccard(normA, normB) >= 0.65) return true;
    final hashA = simHash64(normA);
    final hashB = simHash64(normB);
    return hammingDistance64(hashA, hashB) <= threshold;
  }
}

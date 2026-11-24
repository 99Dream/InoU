import 'package:meta/meta.dart';

/// Strict controlled content blocks shared across question prompts, options,
/// references, and explanations.
@immutable
sealed class ContentBlock {
  const ContentBlock();

  String get type;

  Map<String, Object?> toJson();

  factory ContentBlock.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('ContentBlock requires string "type".');
    }
    return switch (type) {
      'text' => TextBlock.fromJson(json),
      'richText' => RichTextBlock.fromJson(json),
      'math' => MathBlock.fromJson(json),
      'table' => TableBlock.fromJson(json),
      'image' => ImageBlock.fromJson(json),
      'figure' => FigureBlock.fromJson(json),
      'passage' => PassageBlock.fromJson(json),
      'slot' => SlotBlock.fromJson(json),
      'audio' || 'video' => MediaPlaceholderBlock.fromJson(json),
      _ => throw FormatException('Unsupported ContentBlock type: $type'),
    };
  }
}

@immutable
class TextBlock extends ContentBlock {
  const TextBlock(this.text);

  factory TextBlock.fromJson(Map<String, Object?> json) {
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('TextBlock requires string "text".');
    }
    return TextBlock(text);
  }

  final String text;

  @override
  String get type => 'text';

  @override
  Map<String, Object?> toJson() => {'type': type, 'text': text};
}

@immutable
class RichTextSpan {
  const RichTextSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.ruby,
  });

  factory RichTextSpan.fromJson(Map<String, Object?> json) {
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('RichTextSpan requires string "text".');
    }
    return RichTextSpan(
      text: text,
      bold: (json['bold'] as bool?) ?? false,
      italic: (json['italic'] as bool?) ?? false,
      underline: (json['underline'] as bool?) ?? false,
      ruby: json['ruby'] as String?,
    );
  }

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final String? ruby;

  Map<String, Object?> toJson() => {
    'text': text,
    if (bold) 'bold': bold,
    if (italic) 'italic': italic,
    if (underline) 'underline': underline,
    if (ruby != null) 'ruby': ruby,
  };
}

@immutable
class RichTextBlock extends ContentBlock {
  const RichTextBlock(this.spans);

  factory RichTextBlock.fromJson(Map<String, Object?> json) {
    final raw = json['spans'];
    if (raw is! List) {
      throw const FormatException('RichTextBlock requires list "spans".');
    }
    return RichTextBlock(
      raw
          .map((item) => RichTextSpan.fromJson(item as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final List<RichTextSpan> spans;

  @override
  String get type => 'richText';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'spans': spans.map((s) => s.toJson()).toList(growable: false),
  };
}

@immutable
class MathBlock extends ContentBlock {
  const MathBlock(this.latex, {this.display = false});

  factory MathBlock.fromJson(Map<String, Object?> json) {
    final latex = json['latex'];
    if (latex is! String) {
      throw const FormatException('MathBlock requires string "latex".');
    }
    final display = json['display'];
    if (display != null && display is! bool) {
      throw const FormatException('MathBlock "display" must be boolean.');
    }
    return MathBlock(latex, display: (display as bool?) ?? false);
  }

  final String latex;
  final bool display;

  @override
  String get type => 'math';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'latex': latex,
    'display': display,
  };
}

@immutable
class TableBlock extends ContentBlock {
  const TableBlock({required this.rows, this.header, this.caption});

  factory TableBlock.fromJson(Map<String, Object?> json) {
    final rawRows = json['rows'];
    if (rawRows is! List) {
      throw const FormatException('TableBlock requires list "rows".');
    }
    final rows = rawRows
        .map(
          (row) => (row as List)
              .map(
                (cell) => (cell as List)
                    .map(
                      (b) => ContentBlock.fromJson(b as Map<String, Object?>),
                    )
                    .toList(growable: false),
              )
              .toList(growable: false),
        )
        .toList(growable: false);
    final rawHeader = json['header'] as List?;
    final header = rawHeader
        ?.map(
          (cell) => (cell as List)
              .map((b) => ContentBlock.fromJson(b as Map<String, Object?>))
              .toList(growable: false),
        )
        .toList(growable: false);
    return TableBlock(
      rows: rows,
      header: header,
      caption: json['caption'] as String?,
    );
  }

  final List<List<ContentBlock>>? header;
  final List<List<List<ContentBlock>>> rows;
  final String? caption;

  @override
  String get type => 'table';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (caption != null) 'caption': caption,
    if (header != null)
      'header': header!
          .map((c) => c.map((b) => b.toJson()).toList(growable: false))
          .toList(growable: false),
    'rows': rows
        .map(
          (r) => r
              .map((c) => c.map((b) => b.toJson()).toList(growable: false))
              .toList(growable: false),
        )
        .toList(growable: false),
  };
}

@immutable
class ImageBlock extends ContentBlock {
  const ImageBlock({required this.assetId, this.alt, this.width});

  factory ImageBlock.fromJson(Map<String, Object?> json) {
    final assetId = json['assetId'];
    if (assetId is! String || assetId.isEmpty) {
      throw const FormatException('ImageBlock requires non-empty "assetId".');
    }
    final width = json['width'];
    return ImageBlock(
      assetId: assetId,
      alt: json['alt'] as String?,
      width: width is num ? width.toDouble() : null,
    );
  }

  final String assetId;
  final String? alt;
  final double? width;

  @override
  String get type => 'image';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'assetId': assetId,
    if (alt != null) 'alt': alt,
    if (width != null) 'width': width,
  };
}

@immutable
class FigureBlock extends ContentBlock {
  const FigureBlock({required this.assetId, this.caption, this.alt});

  factory FigureBlock.fromJson(Map<String, Object?> json) {
    final assetId = json['assetId'];
    if (assetId is! String || assetId.isEmpty) {
      throw const FormatException('FigureBlock requires non-empty "assetId".');
    }
    return FigureBlock(
      assetId: assetId,
      caption: json['caption'] as String?,
      alt: json['alt'] as String?,
    );
  }

  final String assetId;
  final String? caption;
  final String? alt;

  @override
  String get type => 'figure';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'assetId': assetId,
    if (caption != null) 'caption': caption,
    if (alt != null) 'alt': alt,
  };
}

@immutable
class PassageParagraph {
  const PassageParagraph({required this.content, this.no});

  factory PassageParagraph.fromJson(Map<String, Object?> json) {
    final raw = json['content'];
    if (raw is! List) {
      throw const FormatException('PassageParagraph requires list "content".');
    }
    return PassageParagraph(
      no: json['no'] as String?,
      content: raw
          .map((b) => ContentBlock.fromJson(b as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final String? no;
  final List<ContentBlock> content;

  Map<String, Object?> toJson() => {
    if (no != null) 'no': no,
    'content': content.map((b) => b.toJson()).toList(growable: false),
  };
}

@immutable
class PassageBlock extends ContentBlock {
  const PassageBlock({required this.paragraphs, this.title});

  factory PassageBlock.fromJson(Map<String, Object?> json) {
    final raw = json['paragraphs'];
    if (raw is! List) {
      throw const FormatException('PassageBlock requires list "paragraphs".');
    }
    return PassageBlock(
      title: json['title'] as String?,
      paragraphs: raw
          .map((p) => PassageParagraph.fromJson(p as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final String? title;
  final List<PassageParagraph> paragraphs;

  @override
  String get type => 'passage';

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    if (title != null) 'title': title,
    'paragraphs': paragraphs.map((p) => p.toJson()).toList(growable: false),
  };
}

@immutable
class SlotBlock extends ContentBlock {
  const SlotBlock(this.slotId);

  factory SlotBlock.fromJson(Map<String, Object?> json) {
    final slotId = json['slotId'];
    if (slotId is! String || slotId.isEmpty) {
      throw const FormatException('SlotBlock requires non-empty "slotId".');
    }
    return SlotBlock(slotId);
  }

  final String slotId;

  @override
  String get type => 'slot';

  @override
  Map<String, Object?> toJson() => {'type': type, 'slotId': slotId};
}

@immutable
class MediaPlaceholderBlock extends ContentBlock {
  const MediaPlaceholderBlock({
    required this.mediaType,
    required this.assetId,
    this.transcript,
  });

  factory MediaPlaceholderBlock.fromJson(Map<String, Object?> json) {
    final type = json['type'] as String;
    final assetId = json['assetId'];
    if (assetId is! String || assetId.isEmpty) {
      throw const FormatException(
        'MediaPlaceholderBlock requires non-empty "assetId".',
      );
    }
    return MediaPlaceholderBlock(
      mediaType: type,
      assetId: assetId,
      transcript: json['transcript'] as String?,
    );
  }

  final String mediaType;
  final String assetId;
  final String? transcript;

  @override
  String get type => mediaType;

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'assetId': assetId,
    if (transcript != null) 'transcript': transcript,
  };
}

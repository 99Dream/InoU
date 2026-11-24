import 'package:meta/meta.dart';

/// Node in the built-in curriculum knowledge tree (`kp_tree_v1.json`).
@immutable
class KnowledgeNode {
  const KnowledgeNode({
    required this.id,
    required this.parentId,
    required this.subject,
    required this.stage,
    required this.name,
    required this.level,
    required this.isLeaf,
    required this.sort,
    this.gradeHint,
    this.commonKinds = const [],
    this.description = '',
    this.deprecated = false,
    this.replacedBy,
  });

  factory KnowledgeNode.fromJson(Map<String, Object?> json) {
    return KnowledgeNode(
      id: json['id'] as String,
      parentId: json['parentId'] as String,
      subject: json['subject'] as String,
      stage: json['stage'] as String,
      name: json['name'] as String,
      level: json['level'] as int,
      isLeaf: json['isLeaf'] as bool,
      sort: json['sort'] as int,
      gradeHint: json['gradeHint'] as String?,
      commonKinds: (json['commonKinds'] as List? ?? const [])
          .cast<String>()
          .toList(growable: false),
      description: (json['description'] as String?) ?? '',
      deprecated: (json['deprecated'] as bool?) ?? false,
      replacedBy: json['replacedBy'] as String?,
    );
  }

  final String id;
  final String parentId;
  final String subject;
  final String stage;
  final String name;
  final int level;
  final bool isLeaf;
  final int sort;
  final String? gradeHint;
  final List<String> commonKinds;
  final String description;
  final bool deprecated;
  final String? replacedBy;
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:inou_domain/inou_domain.dart';

/// Loads and indexes the bundled curriculum knowledge tree (`kp_tree_v1.json`).
class KpTreeRepository {
  KpTreeRepository({this.nodes = const []}) {
    _index();
  }

  static const String assetPath = 'assets/knowledge/kp_tree_v1.json';

  final List<KnowledgeNode> nodes;
  final Map<String, KnowledgeNode> _byId = {};
  final Map<String, List<KnowledgeNode>> _childrenOf = {};

  static Future<KpTreeRepository> loadFromAsset() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      final rawList = decoded is List
          ? decoded
          : (decoded is Map && decoded['nodes'] is List
                ? decoded['nodes'] as List
                : const <Object?>[]);
      final parsed = rawList
          .whereType<Map<Object?, Object?>>()
          .map(
            (e) => KnowledgeNode.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .where((n) => !n.deprecated)
          .toList(growable: false);
      return KpTreeRepository(nodes: parsed);
    } catch (_) {
      return KpTreeRepository(nodes: _minimalFallbackNodes());
    }
  }

  void _index() {
    for (final n in nodes) {
      _byId[n.id] = n;
      _childrenOf.putIfAbsent(n.parentId, () => <KnowledgeNode>[]).add(n);
    }
    for (final list in _childrenOf.values) {
      list.sort((a, b) => a.sort.compareTo(b.sort));
    }
  }

  KnowledgeNode? byId(String id) => _byId[id];

  String nameOf(String id) => _byId[id]?.name ?? id;

  List<KnowledgeNode> childrenOf(String parentId) =>
      _childrenOf[parentId] ?? const [];

  List<KnowledgeNode> roots({String? subject, String? stage}) {
    return nodes
        .where(
          (n) =>
              (n.parentId.isEmpty || n.parentId == 'root') &&
              (subject == null || n.subject == subject) &&
              (stage == null || n.stage == stage),
        )
        .toList(growable: false)
      ..sort((a, b) => a.sort.compareTo(b.sort));
  }

  List<KnowledgeNode> leaves({String? subject, String? stage}) {
    return nodes
        .where(
          (n) =>
              n.isLeaf &&
              (subject == null || n.subject == subject) &&
              (stage == null || n.stage == stage),
        )
        .toList(growable: false);
  }

  List<KnowledgeNode> search(String query, {String? subject, int limit = 20}) {
    final q = query.trim().toLowerCase();
    return nodes
        .where(
          (n) =>
              (subject == null || n.subject == subject) &&
              (q.isEmpty ||
                  n.name.toLowerCase().contains(q) ||
                  n.description.toLowerCase().contains(q) ||
                  n.id.toLowerCase().contains(q)),
        )
        .take(limit)
        .toList(growable: false);
  }

  static List<KnowledgeNode> _minimalFallbackNodes() => const [
    KnowledgeNode(
      id: 'math.m.02',
      parentId: 'root',
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
      name: '一元二次方程求解',
      level: 3,
      isLeaf: true,
      sort: 1,
    ),
    KnowledgeNode(
      id: 'math.m.02.03.03',
      parentId: 'math.m.02',
      subject: 'math',
      stage: 'm',
      name: '根的判别式与应用',
      level: 3,
      isLeaf: true,
      sort: 2,
    ),
  ];
}

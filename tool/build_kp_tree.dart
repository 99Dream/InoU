import 'dart:convert';
import 'dart:io';

/// Parses `docs/05-知识点树种子.md` and generates
/// `apps/inou_app/assets/knowledge/kp_tree_v1.json`.
void main(List<String> args) {
  final root = Directory.current;
  final sourceFile = File(
    '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}05-知识点树种子.md',
  );
  if (!sourceFile.existsSync()) {
    stderr.writeln('Source file not found: ${sourceFile.path}');
    exitCode = 1;
    return;
  }

  final outFile = File(
    '${root.path}${Platform.pathSeparator}apps${Platform.pathSeparator}'
    'inou_app${Platform.pathSeparator}assets${Platform.pathSeparator}'
    'knowledge${Platform.pathSeparator}kp_tree_v1.json',
  );
  outFile.parent.createSync(recursive: true);

  final rowPattern = RegExp(
    r'^\|\s*([a-z]+\.[pmh](?:\.\d{2}){1,3})\s*\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|',
  );

  final nodes = <Map<String, Object?>>[];
  final seenIds = <String>{};
  var leafCount = 0;

  for (final line in sourceFile.readAsLinesSync()) {
    final match = rowPattern.matchAsPrefix(line);
    if (match == null) continue;

    final id = match.group(1)!.trim();
    if (!seenIds.add(id)) {
      stderr.writeln('Duplicate knowledge point id: $id');
      exitCode = 1;
      return;
    }

    final parts = id.split('.');
    final subject = parts[0];
    final stage = parts[1];
    final sort = int.parse(parts.last);
    final name = match.group(2)!.trim();
    final parentId = match.group(3)!.trim();
    final level = int.parse(match.group(4)!.trim());
    final isLeaf = match.group(5)!.trim() == '1';
    final gradeHint = match.group(6)!.trim();
    final kindsRaw = match.group(7)!.trim();
    final description = match.group(8)!.trim();

    if (isLeaf) leafCount++;

    final commonKinds = kindsRaw.isEmpty
        ? const <String>[]
        : kindsRaw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

    nodes.add({
      'id': id,
      'parentId': parentId,
      'subject': subject,
      'stage': stage,
      'name': name,
      'level': level,
      'isLeaf': isLeaf,
      'sort': sort,
      'gradeHint': gradeHint.isEmpty ? null : gradeHint,
      'commonKinds': commonKinds,
      'description': description,
      'deprecated': false,
      'replacedBy': null,
    });
  }

  final payload = {
    'treeVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'nodeCount': nodes.length,
    'leafCount': leafCount,
    'nodes': nodes,
  };

  const encoder = JsonEncoder.withIndent('  ');
  outFile.writeAsStringSync('${encoder.convert(payload)}\n');
  stdout.writeln(
    'Generated ${outFile.path}: ${nodes.length} nodes ($leafCount leaves).',
  );
}

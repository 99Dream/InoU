import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:inou_domain/inou_domain.dart';
import 'package:inou_ink/inou_ink.dart';
import 'package:uuid/uuid.dart';

import '../state/workspace_models.dart';

/// How an imported `.inou` ZIP backup merges with current workspace data.
enum BackupImportMode {
  newProfile('new_profile', '导入为新学习档案'),
  merge('merge', '合并到当前档案（保留不冲突项）'),
  overwrite('overwrite', '覆盖当前档案工作区');

  const BackupImportMode(this.code, this.label);
  final String code;
  final String label;
}

/// Summary & SHA-256 verification metadata parsed from a `.inou` package.
@immutable
class BackupInspectionResult {
  const BackupInspectionResult({
    required this.ok,
    this.createdAtMs = 0,
    this.profileCount = 0,
    this.questionCount = 0,
    this.wrongItemCount = 0,
    this.sha256Verified = false,
    this.errorMessage,
    this.snapshot,
  });

  final bool ok;
  final int createdAtMs;
  final int profileCount;
  final int questionCount;
  final int wrongItemCount;
  final bool sha256Verified;
  final String? errorMessage;
  final WorkspaceSnapshot? snapshot;
}

/// Pure-Dart `.inou` ZIP backup exporter & integrity-verified importer
/// (explicitly excludes BYOK API keys and parent PIN secrets).
class InouBackupService {
  const InouBackupService();

  static const String _workspaceEntryName = 'workspace.json';
  static const String _manifestEntryName = 'manifest.json';
  static const Uuid _uuid = Uuid();

  Uint8List exportArchive(WorkspaceSnapshot snapshot) {
    final workspaceJson = jsonEncode(snapshot.toJson());
    final workspaceBytes = utf8.encode(workspaceJson);
    final digest = sha256.convert(workspaceBytes).toString();

    var totalQuestions = 0;
    var totalWrong = 0;
    for (final ws in snapshot.workspaces.values) {
      totalQuestions += ws.questions.length;
      totalWrong += ws.wrongItems.length;
    }

    final manifest = {
      'format': 'inou-backup',
      'version': 1,
      'includesSecrets': false,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'counts': {
        'profiles': snapshot.profiles.length,
        'questions': totalQuestions,
        'wrongItems': totalWrong,
      },
      'checksums': {_workspaceEntryName: digest},
    };
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    final archive = Archive()
      ..addFile(
        ArchiveFile(_manifestEntryName, manifestBytes.length, manifestBytes),
      )
      ..addFile(
        ArchiveFile(_workspaceEntryName, workspaceBytes.length, workspaceBytes),
      );

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded ?? const <int>[]);
  }

  BackupInspectionResult inspectArchive(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFile = archive.findFile(_manifestEntryName);
      final workspaceFile = archive.findFile(_workspaceEntryName);
      if (manifestFile == null || workspaceFile == null) {
        return const BackupInspectionResult(
          ok: false,
          errorMessage: '备份包缺少 manifest.json 或 workspace.json',
        );
      }

      final manifestBytes = _extractFileBytes(manifestFile);
      final workspaceBytes = _extractFileBytes(workspaceFile);
      final manifestMap = (jsonDecode(utf8.decode(manifestBytes)) as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      if (manifestMap['format'] != 'inou-backup') {
        return const BackupInspectionResult(
          ok: false,
          errorMessage: '未知的备份格式标识',
        );
      }

      final checksums = manifestMap['checksums'] as Map?;
      final expectedSha = checksums?[_workspaceEntryName]?.toString() ?? '';
      final actualSha = sha256.convert(workspaceBytes).toString();
      if (expectedSha.isEmpty || expectedSha != actualSha) {
        return const BackupInspectionResult(
          ok: false,
          sha256Verified: false,
          errorMessage: 'SHA-256 完整性校验未通过，文件可能已损坏',
        );
      }

      final wsMap = (jsonDecode(utf8.decode(workspaceBytes)) as Map).map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final snapshot = WorkspaceSnapshot.fromJson(wsMap);
      var totalQuestions = 0;
      var totalWrong = 0;
      for (final ws in snapshot.workspaces.values) {
        totalQuestions += ws.questions.length;
        totalWrong += ws.wrongItems.length;
      }

      return BackupInspectionResult(
        ok: true,
        createdAtMs: (manifestMap['createdAtMs'] as num?)?.toInt() ?? 0,
        profileCount: snapshot.profiles.length,
        questionCount: totalQuestions,
        wrongItemCount: totalWrong,
        sha256Verified: true,
        snapshot: snapshot,
      );
    } catch (e) {
      return BackupInspectionResult(ok: false, errorMessage: '无法解析备份压缩包：$e');
    }
  }

  WorkspaceSnapshot importArchive(
    Uint8List bytes, {
    required BackupImportMode mode,
    required WorkspaceSnapshot current,
  }) {
    final inspection = inspectArchive(bytes);
    if (!inspection.ok || inspection.snapshot == null) {
      throw FormatException(inspection.errorMessage ?? '无效的 .inou 备份文件');
    }
    final imported = inspection.snapshot!;

    switch (mode) {
      case BackupImportMode.overwrite:
        return imported;

      case BackupImportMode.newProfile:
        final srcProfile = imported.activeProfile;
        final srcWs = imported.activeWorkspace;
        final newId = 'profile_imp_${_uuid.v4().substring(0, 6)}';
        final clonedProfile = StudentProfile(
          id: newId,
          name: '${srcProfile.name}（导入）',
          stage: srcProfile.stage,
          grade: srcProfile.grade,
          subjects: srcProfile.subjects,
        );
        final nextWorkspaces = Map<String, ProfileWorkspaceData>.from(
          current.workspaces,
        )..[newId] = srcWs;
        return current.copyWith(
          profiles: [...current.profiles, clonedProfile],
          activeProfileId: newId,
          workspaces: nextWorkspaces,
        );

      case BackupImportMode.merge:
        final currentWs = current.activeWorkspace;
        final incomingWs = imported.activeWorkspace;
        final mergedQuestions = _mergeById(
          currentWs.questions,
          incomingWs.questions,
          (q) => q.id,
        );
        final mergedDocs = _mergeById(
          currentWs.sourceDocs,
          incomingWs.sourceDocs,
          (d) => d.id,
        );
        final mergedWrong = _mergeById(
          currentWs.wrongItems,
          incomingWs.wrongItems,
          (w) => w.id,
        );
        final mergedAttempts = _mergeById(
          currentWs.attempts,
          incomingWs.attempts,
          (a) => a.id,
        );
        final mergedSessions = _mergeById(
          currentWs.sessions,
          incomingWs.sessions,
          (s) => s.id,
        );
        final mergedReports = _mergeById(
          currentWs.reports,
          incomingWs.reports,
          (r) => r.id,
        );
        final mergedThreads = _mergeById(
          currentWs.tutorThreads,
          incomingWs.tutorThreads,
          (t) => t.id,
        );
        final mergedInk = Map<String, InkPageData>.from(
          currentWs.inkPagesByQuestionId,
        );
        for (final e in incomingWs.inkPagesByQuestionId.entries) {
          mergedInk.putIfAbsent(e.key, () => e.value);
        }
        final mergedBlackboards = Map<String, BlackboardLessonRecord>.from(
          currentWs.blackboardLessonsByQuestionId,
        );
        for (final e in incomingWs.blackboardLessonsByQuestionId.entries) {
          mergedBlackboards.putIfAbsent(e.key, () => e.value);
        }

        final nextWs = currentWs.copyWith(
          questions: mergedQuestions,
          sourceDocs: mergedDocs,
          wrongItems: mergedWrong,
          attempts: mergedAttempts,
          sessions: mergedSessions,
          reports: mergedReports,
          tutorThreads: mergedThreads,
          inkPagesByQuestionId: mergedInk,
          blackboardLessonsByQuestionId: mergedBlackboards,
        );
        final nextMap = Map<String, ProfileWorkspaceData>.from(
          current.workspaces,
        )..[current.activeProfile.id] = nextWs;
        return current.copyWith(workspaces: nextMap);
    }
  }

  List<T> _mergeById<T>(
    List<T> existing,
    List<T> incoming,
    String Function(T item) idOf,
  ) {
    final seen = <String>{for (final item in existing) idOf(item)};
    final result = List<T>.from(existing);
    for (final item in incoming) {
      if (seen.add(idOf(item))) {
        result.add(item);
      }
    }
    return result;
  }

  Uint8List _extractFileBytes(ArchiveFile file) {
    final raw = file.content;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return Uint8List(0);
  }
}

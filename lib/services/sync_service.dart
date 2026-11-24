import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/vod_item.dart';
import 'database_service.dart';
import 'playlist_repository.dart';

class SyncImportSummary {
  final int sourcesAdded;
  final int favoritesSynced;
  final int progressSynced;

  const SyncImportSummary({
    required this.sourcesAdded,
    required this.favoritesSynced,
    required this.progressSynced,
  });
}

class SyncService {
  final PlaylistRepository _repo;
  final DatabaseService _db;
  final http.Client _client;

  SyncService({
    required PlaylistRepository repo,
    required DatabaseService db,
    http.Client? client,
  })  : _repo = repo,
        _db = db,
        _client = client ?? http.Client();

  Future<String> exportBackupJson() async {
    final sources = await _repo.loadSavedSources();
    final favorites = await _db.getAllFavorites();
    final progress = await _db.getAllPlaybackProgress();

    final payload = {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sources': sources.map((s) => s.toJson()).toList(),
      'favorites': favorites,
      'playbackProgress': progress.map((p) => p.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<SyncImportSummary> importBackupJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid sync JSON format.');
    }

    final existingSources = await _repo.loadSavedSources();
    final existingIds = existingSources.map((s) => s.id).toSet();
    final activeId = await _repo.loadActiveSourceId();

    int addedSources = 0;
    final mergedSources = List<PlaylistSource>.from(existingSources);
    final rawSources = decoded['sources'];
    if (rawSources is List) {
      for (final item in rawSources) {
        if (item is Map<String, dynamic>) {
          final src = PlaylistSource.fromJson(item);
          if (!existingIds.contains(src.id)) {
            mergedSources.add(src);
            existingIds.add(src.id);
            addedSources++;
          }
        }
      }
    }
    await _repo.saveSources(
      mergedSources,
      activeSourceId: activeId ??
          (mergedSources.isNotEmpty ? mergedSources.first.id : null),
    );

    final favList = <Map<String, dynamic>>[];
    final rawFavs = decoded['favorites'];
    if (rawFavs is List) {
      for (final item in rawFavs) {
        if (item is Map<String, dynamic>) {
          favList.add(item);
        }
      }
    }
    await _db.upsertFavorites(favList);

    final progressList = <PlaybackProgress>[];
    final rawProg = decoded['playbackProgress'];
    if (rawProg is List) {
      for (final item in rawProg) {
        if (item is Map<String, dynamic>) {
          progressList.add(PlaybackProgress.fromJson(item));
        }
      }
    }
    await _db.upsertPlaybackProgress(progressList);

    return SyncImportSummary(
      sourcesAdded: addedSources,
      favoritesSynced: favList.length,
      progressSynced: progressList.length,
    );
  }

  Future<void> pushToWebDav({
    required String fileUrl,
    String? username,
    String? password,
  }) async {
    final jsonStr = await exportBackupJson();
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      ..._authHeader(username, password),
    };
    final res = await _client
        .put(Uri.parse(fileUrl.trim()), headers: headers, body: jsonStr)
        .timeout(const Duration(seconds: 30));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('WebDAV upload failed (HTTP ${res.statusCode}).');
    }
  }

  Future<SyncImportSummary> pullFromWebDav({
    required String fileUrl,
    String? username,
    String? password,
  }) async {
    final res = await _client
        .get(
          Uri.parse(fileUrl.trim()),
          headers: _authHeader(username, password),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('WebDAV download failed (HTTP ${res.statusCode}).');
    }
    return importBackupJson(res.body);
  }

  Map<String, String> _authHeader(String? username, String? password) {
    final u = username?.trim() ?? '';
    final p = password ?? '';
    if (u.isEmpty) return const {};
    final token = base64Encode(utf8.encode('$u:$p'));
    return {'Authorization': 'Basic $token'};
  }
}

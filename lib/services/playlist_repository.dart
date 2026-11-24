import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import 'm3u_parser.dart';
import 'xtream_service.dart';

class PlaylistLoadResult {
  final List<Channel> channels;
  final String? detectedEpgUrl;

  const PlaylistLoadResult({
    required this.channels,
    this.detectedEpgUrl,
  });
}

class PlaylistRepository {
  static const _sourcesKey = 'iptv_saved_sources_v1';
  static const _activeSourceIdKey = 'iptv_active_source_id_v1';

  final http.Client _client;
  final XtreamService _xtreamService;

  PlaylistRepository({
    http.Client? client,
    XtreamService? xtreamService,
  })  : _client = client ?? http.Client(),
        _xtreamService = xtreamService ?? XtreamService(client: client);

  Future<List<PlaylistSource>> loadSavedSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return PlaylistSource.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<String?> loadActiveSourceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeSourceIdKey);
  }

  Future<void> saveSources(
    List<PlaylistSource> sources, {
    String? activeSourceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourcesKey, PlaylistSource.encodeList(sources));
    if (activeSourceId != null) {
      await prefs.setString(_activeSourceIdKey, activeSourceId);
    } else {
      await prefs.remove(_activeSourceIdKey);
    }
  }

  Future<List<Channel>> fetchChannels(PlaylistSource source) async {
    final res = await fetchPlaylist(source);
    return res.channels;
  }

  Future<PlaylistLoadResult> fetchPlaylist(PlaylistSource source) async {
    switch (source.type) {
      case PlaylistSourceType.m3uUrl:
        final url = source.url?.trim() ?? '';
        if (url.isEmpty) {
          throw Exception('Playlist URL is empty.');
        }
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw Exception(
              'Failed to download M3U playlist (HTTP ${response.statusCode}).');
        }
        final parsed = M3uParser.parseWithMetadata(response.body);
        return PlaylistLoadResult(
          channels: parsed.channels,
          detectedEpgUrl: parsed.epgUrl,
        );

      case PlaylistSourceType.m3uFile:
        final path = source.filePath?.trim() ?? '';
        if (path.isEmpty) {
          throw Exception('File path is empty.');
        }
        final file = File(path);
        if (!await file.exists()) {
          throw Exception('Playlist file not found at $path');
        }
        final content = await file.readAsString();
        final parsed = M3uParser.parseWithMetadata(content);
        return PlaylistLoadResult(
          channels: parsed.channels,
          detectedEpgUrl: parsed.epgUrl,
        );

      case PlaylistSourceType.xtream:
        final channels = await _xtreamService.fetchLiveChannels(
          serverUrl: source.url ?? '',
          username: source.username ?? '',
          password: source.password ?? '',
        );
        return PlaylistLoadResult(channels: channels);
    }
  }
}

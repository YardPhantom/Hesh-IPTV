import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/vod_item.dart';

class XtreamService {
  final http.Client _client;

  XtreamService({http.Client? client}) : _client = client ?? http.Client();

  String normalizeBaseUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Future<List<Channel>> fetchLiveChannels({
    required String serverUrl,
    required String username,
    required String password,
    String streamExtension = 'ts',
  }) async {
    final base = normalizeBaseUrl(serverUrl);
    final authQuery =
        'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';

    final categoriesUri =
        Uri.parse('$base/player_api.php?$authQuery&action=get_live_categories');
    final streamsUri =
        Uri.parse('$base/player_api.php?$authQuery&action=get_live_streams');

    final responses = await Future.wait([
      _client.get(categoriesUri).timeout(const Duration(seconds: 20)),
      _client.get(streamsUri).timeout(const Duration(seconds: 30)),
    ]);

    final catRes = responses[0];
    final streamRes = responses[1];

    if (streamRes.statusCode != 200) {
      throw Exception(
          'Xtream server returned HTTP ${streamRes.statusCode} for live streams.');
    }

    final categoryMap = <String, String>{};
    if (catRes.statusCode == 200) {
      final decodedCats = jsonDecode(catRes.body);
      if (decodedCats is List) {
        for (final item in decodedCats) {
          if (item is Map<String, dynamic>) {
            final id = item['category_id']?.toString();
            final name = item['category_name']?.toString();
            if (id != null && name != null && name.isNotEmpty) {
              categoryMap[id] = name;
            }
          }
        }
      }
    }

    final decodedStreams = jsonDecode(streamRes.body);
    if (decodedStreams is! List) {
      throw Exception('Unexpected Xtream response format (expected a list).');
    }

    final channels = <Channel>[];
    for (final item in decodedStreams) {
      if (item is! Map<String, dynamic>) continue;
      final streamId = item['stream_id']?.toString();
      if (streamId == null || streamId.isEmpty) continue;

      final name = item['name']?.toString().trim();
      final catId = item['category_id']?.toString();
      final logo = item['stream_icon']?.toString().trim();
      final epgId = item['epg_channel_id']?.toString().trim();

      final streamUrl =
          '$base/live/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$streamId.$streamExtension';

      channels.add(
        Channel(
          id: 'xtream_$streamId',
          name: (name == null || name.isEmpty) ? 'Stream $streamId' : name,
          streamUrl: streamUrl,
          groupTitle: categoryMap[catId] ?? 'Live TV',
          logoUrl: (logo == null || logo.isEmpty) ? null : logo,
          tvgId: (epgId == null || epgId.isEmpty) ? null : epgId,
        ),
      );
    }

    return channels;
  }

  Future<List<VodItem>> fetchVodMovies({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final base = normalizeBaseUrl(serverUrl);
    final authQuery =
        'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';

    final catUri =
        Uri.parse('$base/player_api.php?$authQuery&action=get_vod_categories');
    final vodUri =
        Uri.parse('$base/player_api.php?$authQuery&action=get_vod_streams');

    final responses = await Future.wait([
      _client.get(catUri).timeout(const Duration(seconds: 20)),
      _client.get(vodUri).timeout(const Duration(seconds: 30)),
    ]);

    if (responses[1].statusCode != 200) {
      throw Exception(
          'Xtream server returned HTTP ${responses[1].statusCode} for VOD.');
    }

    final categoryMap = _parseCategoryMap(responses[0]);
    final decoded = jsonDecode(responses[1].body);
    if (decoded is! List) return [];

    final items = <VodItem>[];
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['stream_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final ext = raw['container_extension']?.toString().trim();
      final finalExt = (ext == null || ext.isEmpty) ? 'mp4' : ext;
      final catId = raw['category_id']?.toString();
      final name = raw['name']?.toString().trim();

      items.add(
        VodItem(
          id: 'vod_$id',
          name: (name == null || name.isEmpty) ? 'Movie $id' : name,
          streamUrl:
              '$base/movie/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$id.$finalExt',
          categoryName: categoryMap[catId] ?? 'Movies',
          posterUrl: _nonEmpty(raw['stream_icon']?.toString()),
          rating: _nonEmpty(raw['rating']?.toString()),
          containerExtension: finalExt,
        ),
      );
    }
    return items;
  }

  Future<List<SeriesItem>> fetchSeries({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final base = normalizeBaseUrl(serverUrl);
    final authQuery =
        'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';

    final catUri = Uri.parse(
        '$base/player_api.php?$authQuery&action=get_series_categories');
    final seriesUri =
        Uri.parse('$base/player_api.php?$authQuery&action=get_series');

    final responses = await Future.wait([
      _client.get(catUri).timeout(const Duration(seconds: 20)),
      _client.get(seriesUri).timeout(const Duration(seconds: 30)),
    ]);

    if (responses[1].statusCode != 200) {
      throw Exception(
          'Xtream server returned HTTP ${responses[1].statusCode} for series.');
    }

    final categoryMap = _parseCategoryMap(responses[0]);
    final decoded = jsonDecode(responses[1].body);
    if (decoded is! List) return [];

    final items = <SeriesItem>[];
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['series_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final catId = raw['category_id']?.toString();
      final name = raw['name']?.toString().trim();

      items.add(
        SeriesItem(
          id: id,
          name: (name == null || name.isEmpty) ? 'Series $id' : name,
          categoryName: categoryMap[catId] ?? 'Series',
          posterUrl: _nonEmpty(raw['cover']?.toString()),
          rating: _nonEmpty(raw['rating']?.toString()),
          plot: _nonEmpty(raw['plot']?.toString()),
        ),
      );
    }
    return items;
  }

  Future<List<SeriesEpisode>> fetchSeriesEpisodes({
    required String serverUrl,
    required String username,
    required String password,
    required String seriesId,
  }) async {
    final base = normalizeBaseUrl(serverUrl);
    final authQuery =
        'username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';
    final uri = Uri.parse(
        '$base/player_api.php?$authQuery&action=get_series_info&series_id=${Uri.encodeQueryComponent(seriesId)}');

    final res = await _client.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception(
          'Xtream server returned HTTP ${res.statusCode} for series info.');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return [];
    final episodesMap = decoded['episodes'];
    if (episodesMap is! Map<String, dynamic>) return [];

    final episodes = <SeriesEpisode>[];
    for (final entry in episodesMap.entries) {
      final seasonNum = int.tryParse(entry.key) ?? 1;
      final list = entry.value;
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final epId = raw['id']?.toString();
        if (epId == null || epId.isEmpty) continue;
        final epNum = int.tryParse(raw['episode_num']?.toString() ?? '') ?? 1;
        final ext = raw['container_extension']?.toString().trim();
        final finalExt = (ext == null || ext.isEmpty) ? 'mp4' : ext;
        final title = raw['title']?.toString().trim();

        episodes.add(
          SeriesEpisode(
            id: 'ep_$epId',
            season: seasonNum,
            episodeNum: epNum,
            title: (title == null || title.isEmpty)
                ? 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}'
                : title,
            streamUrl:
                '$base/series/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/$epId.$finalExt',
            containerExtension: finalExt,
          ),
        );
      }
    }

    episodes.sort((a, b) {
      final sCmp = a.season.compareTo(b.season);
      return sCmp != 0 ? sCmp : a.episodeNum.compareTo(b.episodeNum);
    });
    return episodes;
  }

  Map<String, String> _parseCategoryMap(http.Response res) {
    final map = <String, String>{};
    if (res.statusCode != 200) return map;
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final id = item['category_id']?.toString();
          final name = item['category_name']?.toString();
          if (id != null && name != null && name.isNotEmpty) {
            map[id] = name;
          }
        }
      }
    }
    return map;
  }

  String? _nonEmpty(String? val) {
    if (val == null) return null;
    final t = val.trim();
    return t.isEmpty ? null : t;
  }
}

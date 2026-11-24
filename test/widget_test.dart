import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models/channel.dart';
import 'package:iptv_player/models/vod_item.dart';
import 'package:iptv_player/services/database_service.dart';
import 'package:iptv_player/services/m3u_parser.dart';
import 'package:iptv_player/services/playlist_repository.dart';
import 'package:iptv_player/services/sync_service.dart';
import 'package:iptv_player/services/xmltv_parser.dart';
import 'package:iptv_player/services/xtream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('M3uParser', () {
    test('parses #EXTINF attributes, url-tvg, #EXTGRP, and #EXTVLCOPT headers', () {
      const sample = '''
#EXTM3U url-tvg="https://epg.example.com/guide.xml.gz"
#EXTINF:-1 tvg-id="news.1" tvg-name="News One" tvg-logo="https://img.example.com/news.png" group-title="News, World",News One HD
#EXTVLCOPT:http-user-agent=CustomPlayer/1.0
http://stream.example.com/news/index.m3u8

#EXTINF:-1,Fallback Channel
#EXTGRP:Sports
http://stream.example.com/sports/live.ts
''';

      final result = M3uParser.parseWithMetadata(sample);
      expect(result.epgUrl, 'https://epg.example.com/guide.xml.gz');
      expect(result.channels, hasLength(2));

      expect(result.channels[0].name, 'News One HD');
      expect(result.channels[0].tvgId, 'news.1');
      expect(result.channels[0].logoUrl, 'https://img.example.com/news.png');
      expect(result.channels[0].groupTitle, 'News, World');
      expect(
        result.channels[0].streamUrl,
        'http://stream.example.com/news/index.m3u8',
      );
      expect(result.channels[0].httpHeaders['User-Agent'], 'CustomPlayer/1.0');

      expect(result.channels[1].name, 'Fallback Channel');
      expect(result.channels[1].groupTitle, 'Sports');
      expect(
        result.channels[1].streamUrl,
        'http://stream.example.com/sports/live.ts',
      );
    });
  });

  group('XtreamService', () {
    test('normalizes base URLs', () {
      final service = XtreamService();
      expect(
        service.normalizeBaseUrl('example.com:8080/'),
        'http://example.com:8080',
      );
      expect(
        service.normalizeBaseUrl('https://tv.example.com///'),
        'https://tv.example.com',
      );
    });
  });

  group('XmltvParser', () {
    test('parses XMLTV programme elements and timestamps', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20261123190000 +0000" stop="20261123200000 +0000" channel="news.1">
    <title>Evening News</title>
    <desc>Top stories of the day.</desc>
    <category>News</category>
  </programme>
</tv>
''';

      final programs = XmltvParser.parse(xml);
      expect(programs, hasLength(1));
      expect(programs[0].channelId, 'news.1');
      expect(programs[0].title, 'Evening News');
      expect(programs[0].description, 'Top stories of the day.');
      expect(programs[0].category, 'News');
      expect(
        programs[0].end.difference(programs[0].start),
        const Duration(hours: 1),
      );
    });
  });

  group('DatabaseService', () {
    late DatabaseService db;

    setUp(() {
      sqfliteFfiInit();
      db = DatabaseService(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('persists favorites, recents, and EPG programs', () async {
      const sourceId = 'src1';
      expect(await db.toggleFavorite(sourceId, 'ch1'), isTrue);
      expect(await db.getFavoriteIds(sourceId), {'ch1'});
      expect(await db.toggleFavorite(sourceId, 'ch1'), isFalse);
      expect(await db.getFavoriteIds(sourceId), isEmpty);

      await db.recordRecent(sourceId, 'ch2');
      await db.recordRecent(sourceId, 'ch3');
      final recents = await db.getRecentIds(sourceId);
      expect(recents, containsAll(['ch2', 'ch3']));

      final now = DateTime.now();
      final programs = XmltvParser.parse('''
<tv>
  <programme start="${_fmt(now.subtract(const Duration(minutes: 15)))}" stop="${_fmt(now.add(const Duration(minutes: 45)))}" channel="news.1">
    <title>Live Show</title>
  </programme>
</tv>
''');
      await db.replaceEpgPrograms(programs);

      final current = await db.getCurrentPrograms(['news.1'], now);
      expect(current['news.1']?.title, 'Live Show');

      final range = await db.getProgramsForRange(
        ['news.1'],
        now.subtract(const Duration(hours: 1)),
        now.add(const Duration(hours: 2)),
      );
      expect(range['news.1'], hasLength(1));

      await db.savePlaybackProgress(
        const PlaybackProgress(
          sourceId: sourceId,
          itemId: 'vod_42',
          positionMs: 120000,
          durationMs: 600000,
          updatedAtMs: 1000,
        ),
      );
      final progMap = await db.getPlaybackProgressForSource(sourceId);
      expect(progMap['vod_42']?.ratio, closeTo(0.2, 0.001));
    });
  });

  group('SyncService', () {
    test('exports and imports sources, favorites, and newest playback progress', () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final db = DatabaseService(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final repo = PlaylistRepository();
      final sync = SyncService(repo: repo, db: db);

      await repo.saveSources([
        const PlaylistSource(
          id: 'src_local',
          name: 'Local M3U',
          type: PlaylistSourceType.m3uUrl,
          url: 'https://example.com/tv.m3u',
        ),
      ], activeSourceId: 'src_local');
      await db.toggleFavorite('src_local', 'ch_1');
      await db.savePlaybackProgress(
        const PlaybackProgress(
          sourceId: 'src_local',
          itemId: 'vod_1',
          positionMs: 30000,
          durationMs: 100000,
          updatedAtMs: 500,
        ),
      );

      final exported = await sync.exportBackupJson();

      // Simulate importing on another device with empty state.
      SharedPreferences.setMockInitialValues({});
      final db2 = DatabaseService(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final sync2 = SyncService(repo: PlaylistRepository(), db: db2);
      final summary = await sync2.importBackupJson(exported);

      expect(summary.sourcesAdded, 1);
      expect(summary.favoritesSynced, 1);
      expect(summary.progressSynced, 1);
      expect(await db2.getFavoriteIds('src_local'), {'ch_1'});
      expect((await db2.getPlaybackProgressForSource('src_local'))['vod_1']?.positionMs, 30000);

      await db.close();
      await db2.close();
    });
  });
}

String _fmt(DateTime dt) {
  final utc = dt.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final h = utc.hour.toString().padLeft(2, '0');
  final min = utc.minute.toString().padLeft(2, '0');
  final s = utc.second.toString().padLeft(2, '0');
  return '$y$m$d$h$min$s +0000';
}

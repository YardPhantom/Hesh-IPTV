import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/epg_program.dart';
import '../models/vod_item.dart';

class DatabaseService {
  Database? _db;
  final DatabaseFactory? _customFactory;
  final String? _customPath;

  DatabaseService({
    DatabaseFactory? customFactory,
    String? customPath,
  })  : _customFactory = customFactory,
        _customPath = customPath;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;

    if (_customFactory != null) {
      _db = await _customFactory.openDatabase(
        _customPath ?? inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
      return _db!;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'iptv_library.db');
    _db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPlaybackProgressTable(db);
    }
  }

  Future<void> _createPlaybackProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playback_progress (
        source_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY (source_id, item_id)
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorites (
        source_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        added_at_ms INTEGER NOT NULL,
        PRIMARY KEY (source_id, channel_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE recents (
        source_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        last_watched_ms INTEGER NOT NULL,
        PRIMARY KEY (source_id, channel_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        category TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_epg_channel_time ON epg_programs (channel_id, start_ms, end_ms)',
    );
    await _createPlaybackProgressTable(db);
  }

  Future<Set<String>> getFavoriteIds(String sourceId) async {
    final db = await database;
    final rows = await db.query(
      'favorites',
      columns: ['channel_id'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    return rows.map((r) => r['channel_id'] as String).toSet();
  }

  Future<bool> toggleFavorite(String sourceId, String channelId) async {
    final db = await database;
    final existing = await db.query(
      'favorites',
      columns: ['channel_id'],
      where: 'source_id = ? AND channel_id = ?',
      whereArgs: [sourceId, channelId],
    );
    if (existing.isNotEmpty) {
      await db.delete(
        'favorites',
        where: 'source_id = ? AND channel_id = ?',
        whereArgs: [sourceId, channelId],
      );
      return false;
    } else {
      await db.insert('favorites', {
        'source_id': sourceId,
        'channel_id': channelId,
        'added_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    }
  }

  Future<List<String>> getRecentIds(String sourceId, {int limit = 30}) async {
    final db = await database;
    final rows = await db.query(
      'recents',
      columns: ['channel_id'],
      where: 'source_id = ?',
      whereArgs: [sourceId],
      orderBy: 'last_watched_ms DESC',
      limit: limit,
    );
    return rows.map((r) => r['channel_id'] as String).toList();
  }

  Future<void> recordRecent(String sourceId, String channelId) async {
    final db = await database;
    await db.insert(
      'recents',
      {
        'source_id': sourceId,
        'channel_id': channelId,
        'last_watched_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceEpgPrograms(List<EpgProgram> programs) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('epg_programs');
      final batch = txn.batch();
      for (final p in programs) {
        batch.insert('epg_programs', {
          'channel_id': p.channelId,
          'title': p.title,
          'description': p.description,
          'start_ms': p.start.millisecondsSinceEpoch,
          'end_ms': p.end.millisecondsSinceEpoch,
          'category': p.category,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, EpgProgram>> getCurrentPrograms(
    List<String> channelIds,
    DateTime now,
  ) async {
    if (channelIds.isEmpty) return {};
    final db = await database;
    final nowMs = now.millisecondsSinceEpoch;
    final result = <String, EpgProgram>{};

    // Query in chunks of 400 to stay well below SQLite's 999 bind-parameter limit.
    for (var i = 0; i < channelIds.length; i += 400) {
      final chunk = channelIds.sublist(
        i,
        i + 400 > channelIds.length ? channelIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT channel_id, title, description, start_ms, end_ms, category
        FROM epg_programs
        WHERE channel_id IN ($placeholders)
          AND start_ms <= ? AND end_ms > ?
        ''',
        [...chunk, nowMs, nowMs],
      );
      for (final row in rows) {
        final cid = row['channel_id'] as String;
        result[cid] = _rowToProgram(row);
      }
    }
    return result;
  }

  Future<Map<String, List<EpgProgram>>> getProgramsForRange(
    List<String> channelIds,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    if (channelIds.isEmpty) return {};
    final db = await database;
    final startMs = rangeStart.millisecondsSinceEpoch;
    final endMs = rangeEnd.millisecondsSinceEpoch;
    final result = <String, List<EpgProgram>>{};

    for (var i = 0; i < channelIds.length; i += 400) {
      final chunk = channelIds.sublist(
        i,
        i + 400 > channelIds.length ? channelIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT channel_id, title, description, start_ms, end_ms, category
        FROM epg_programs
        WHERE channel_id IN ($placeholders)
          AND end_ms > ? AND start_ms < ?
        ORDER BY start_ms ASC
        ''',
        [...chunk, startMs, endMs],
      );
      for (final row in rows) {
        final cid = row['channel_id'] as String;
        result.putIfAbsent(cid, () => []).add(_rowToProgram(row));
      }
    }
    return result;
  }

  EpgProgram _rowToProgram(Map<String, Object?> row) {
    return EpgProgram(
      channelId: row['channel_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      start: DateTime.fromMillisecondsSinceEpoch(row['start_ms'] as int),
      end: DateTime.fromMillisecondsSinceEpoch(row['end_ms'] as int),
      category: row['category'] as String?,
    );
  }

  Future<void> savePlaybackProgress(PlaybackProgress progress) async {
    final db = await database;
    await db.insert(
      'playback_progress',
      {
        'source_id': progress.sourceId,
        'item_id': progress.itemId,
        'position_ms': progress.positionMs,
        'duration_ms': progress.durationMs,
        'updated_at_ms': progress.updatedAtMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, PlaybackProgress>> getPlaybackProgressForSource(
    String sourceId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'playback_progress',
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    final map = <String, PlaybackProgress>{};
    for (final row in rows) {
      final p = PlaybackProgress(
        sourceId: row['source_id'] as String,
        itemId: row['item_id'] as String,
        positionMs: row['position_ms'] as int,
        durationMs: row['duration_ms'] as int,
        updatedAtMs: row['updated_at_ms'] as int,
      );
      map[p.itemId] = p;
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    final db = await database;
    return db.query('favorites');
  }

  Future<void> upsertFavorites(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in items) {
        final sid = row['source_id'] as String?;
        final cid = row['channel_id'] as String?;
        final added = (row['added_at_ms'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        if (sid != null && cid != null) {
          batch.insert(
            'favorites',
            {'source_id': sid, 'channel_id': cid, 'added_at_ms': added},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PlaybackProgress>> getAllPlaybackProgress() async {
    final db = await database;
    final rows = await db.query('playback_progress');
    return rows
        .map(
          (row) => PlaybackProgress(
            sourceId: row['source_id'] as String,
            itemId: row['item_id'] as String,
            positionMs: row['position_ms'] as int,
            durationMs: row['duration_ms'] as int,
            updatedAtMs: row['updated_at_ms'] as int,
          ),
        )
        .toList();
  }

  Future<void> upsertPlaybackProgress(List<PlaybackProgress> items) async {
    if (items.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final item in items) {
        final existing = await txn.query(
          'playback_progress',
          columns: ['updated_at_ms'],
          where: 'source_id = ? AND item_id = ?',
          whereArgs: [item.sourceId, item.itemId],
        );
        final existingTs = existing.isNotEmpty
            ? (existing.first['updated_at_ms'] as int)
            : -1;
        if (item.updatedAtMs > existingTs) {
          await txn.insert(
            'playback_progress',
            {
              'source_id': item.sourceId,
              'item_id': item.itemId,
              'position_ms': item.positionMs,
              'duration_ms': item.durationMs,
              'updated_at_ms': item.updatedAtMs,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

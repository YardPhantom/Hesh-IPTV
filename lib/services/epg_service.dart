import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/epg_program.dart';
import 'database_service.dart';
import 'xmltv_parser.dart';
import 'xtream_service.dart';

class EpgService {
  final http.Client _client;
  final DatabaseService _db;
  final XtreamService _xtreamService;

  EpgService({
    required DatabaseService db,
    http.Client? client,
    XtreamService? xtreamService,
  })  : _db = db,
        _client = client ?? http.Client(),
        _xtreamService = xtreamService ?? XtreamService(client: client);

  String? resolveEpgUrl(PlaylistSource source) {
    final custom = source.epgUrl?.trim();
    if (custom != null && custom.isNotEmpty) return custom;

    if (source.type == PlaylistSourceType.xtream &&
        (source.url?.isNotEmpty ?? false) &&
        (source.username?.isNotEmpty ?? false) &&
        (source.password?.isNotEmpty ?? false)) {
      final base = _xtreamService.normalizeBaseUrl(source.url!);
      return '$base/xmltv.php?username=${Uri.encodeQueryComponent(source.username!)}&password=${Uri.encodeQueryComponent(source.password!)}';
    }
    return null;
  }

  /// Downloads XMLTV (`.xml` or `.xml.gz`), parses in a background isolate,
  /// and stores programs in SQLite. Returns the number of programs imported.
  Future<int> refreshEpg(String epgUrl) async {
    final response = await _client
        .get(Uri.parse(epgUrl))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG (HTTP ${response.statusCode}).');
    }

    final bytes = response.bodyBytes;
    final isGzip = (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) ||
        epgUrl.toLowerCase().endsWith('.gz');

    final List<EpgProgram> programs = await Isolate.run(() {
      final xmlText = isGzip
          ? utf8.decode(gzip.decode(bytes), allowMalformed: true)
          : utf8.decode(bytes, allowMalformed: true);
      return XmltvParser.parse(xmlText);
    });

    await _db.replaceEpgPrograms(programs);
    return programs.length;
  }
}

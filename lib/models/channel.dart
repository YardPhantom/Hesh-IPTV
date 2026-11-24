import 'dart:convert';

enum PlaylistSourceType { m3uUrl, m3uFile, xtream }

class Channel {
  final String id;
  final String name;
  final String streamUrl;
  final String groupTitle;
  final String? logoUrl;
  final String? tvgId;
  final Map<String, String> httpHeaders;

  const Channel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.groupTitle = 'Uncategorized',
    this.logoUrl,
    this.tvgId,
    this.httpHeaders = const {},
  });
}

class PlaylistSource {
  final String id;
  final String name;
  final PlaylistSourceType type;
  final String? url;
  final String? filePath;
  final String? username;
  final String? password;
  final String? epgUrl;

  const PlaylistSource({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.filePath,
    this.username,
    this.password,
    this.epgUrl,
  });

  PlaylistSource copyWith({
    String? name,
    String? url,
    String? filePath,
    String? username,
    String? password,
    String? epgUrl,
  }) {
    return PlaylistSource(
      id: id,
      name: name ?? this.name,
      type: type,
      url: url ?? this.url,
      filePath: filePath ?? this.filePath,
      username: username ?? this.username,
      password: password ?? this.password,
      epgUrl: epgUrl ?? this.epgUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'url': url,
        'filePath': filePath,
        'username': username,
        'password': password,
        'epgUrl': epgUrl,
      };

  factory PlaylistSource.fromJson(Map<String, dynamic> json) {
    return PlaylistSource(
      id: json['id'] as String,
      name: json['name'] as String,
      type: PlaylistSourceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PlaylistSourceType.m3uUrl,
      ),
      url: json['url'] as String?,
      filePath: json['filePath'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      epgUrl: json['epgUrl'] as String?,
    );
  }

  static String encodeList(List<PlaylistSource> sources) =>
      jsonEncode(sources.map((s) => s.toJson()).toList());

  static List<PlaylistSource> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => PlaylistSource.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

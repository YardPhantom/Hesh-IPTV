import '../models/channel.dart';

class M3uParseResult {
  final List<Channel> channels;
  final String? epgUrl;

  const M3uParseResult({required this.channels, this.epgUrl});
}

class M3uParser {
  static final RegExp _attrRegex = RegExp(r'([\w-]+)="([^"]*)"');

  /// Parses raw M3U/M3U8 playlist text into a list of [Channel] objects.
  static List<Channel> parse(String content) =>
      parseWithMetadata(content).channels;

  /// Parses raw M3U/M3U8 playlist text and extracts optional `#EXTM3U` EPG URLs.
  static M3uParseResult parseWithMetadata(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final channels = <Channel>[];

    String? epgUrl;
    String? pendingName;
    String? pendingLogo;
    String? pendingTvgId;
    String? pendingGroup;
    final pendingHeaders = <String, String>{};
    int index = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        for (final match in _attrRegex.allMatches(line)) {
          final key = match.group(1)?.toLowerCase() ?? '';
          final val = match.group(2)?.trim() ?? '';
          if ((key == 'url-tvg' || key == 'x-tvg-url') && val.isNotEmpty) {
            epgUrl = val.split(',').first.trim();
          }
        }
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        pendingLogo = null;
        pendingTvgId = null;
        pendingGroup = null;
        pendingHeaders.clear();

        final commaIdx = _findTitleSeparator(line);
        final headerPart = commaIdx >= 0 ? line.substring(0, commaIdx) : line;
        final titlePart =
            commaIdx >= 0 ? line.substring(commaIdx + 1).trim() : '';

        for (final match in _attrRegex.allMatches(headerPart)) {
          final key = match.group(1)?.toLowerCase() ?? '';
          final val = match.group(2)?.trim() ?? '';
          if (val.isEmpty) continue;
          switch (key) {
            case 'tvg-logo':
              pendingLogo = val;
              break;
            case 'tvg-id':
              pendingTvgId = val;
              break;
            case 'group-title':
              pendingGroup = val;
              break;
            case 'tvg-name':
              if (titlePart.isEmpty) {
                pendingName = val;
              }
              break;
          }
        }

        if (titlePart.isNotEmpty) {
          pendingName = titlePart;
        }
        pendingName ??= 'Channel ${index + 1}';
        continue;
      }

      if (line.startsWith('#EXTGRP:')) {
        final grp = line.substring('#EXTGRP:'.length).trim();
        if (grp.isNotEmpty) {
          pendingGroup = grp;
        }
        continue;
      }

      if (line.startsWith('#EXTVLCOPT:')) {
        final opt = line.substring('#EXTVLCOPT:'.length).trim();
        if (opt.startsWith('http-user-agent=')) {
          pendingHeaders['User-Agent'] =
              opt.substring('http-user-agent='.length).trim();
        } else if (opt.startsWith('http-referrer=')) {
          pendingHeaders['Referer'] =
              opt.substring('http-referrer='.length).trim();
        }
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      // Non-comment line is treated as the stream URL.
      final url = line;
      channels.add(
        Channel(
          id: '${index}_${pendingTvgId ?? pendingName ?? url.hashCode}',
          name: pendingName ?? 'Channel ${index + 1}',
          streamUrl: url,
          groupTitle: (pendingGroup == null || pendingGroup.isEmpty)
              ? 'Uncategorized'
              : pendingGroup,
          logoUrl: pendingLogo,
          tvgId: pendingTvgId,
          httpHeaders: Map<String, String>.from(pendingHeaders),
        ),
      );
      index++;
      pendingName = null;
      pendingLogo = null;
      pendingTvgId = null;
      pendingGroup = null;
      pendingHeaders.clear();
    }

    return M3uParseResult(channels: channels, epgUrl: epgUrl);
  }

  /// Finds the comma separating #EXTINF attributes from the channel display name,
  /// ignoring commas inside quoted attribute values.
  static int _findTitleSeparator(String line) {
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        return i;
      }
    }
    return -1;
  }
}

import 'package:xml/xml_events.dart';
import '../models/epg_program.dart';

class XmltvParser {
  static final RegExp _tsRegex = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?',
  );

  /// Streams XMLTV `<programme>` elements without building a full DOM tree.
  static List<EpgProgram> parse(String xmlContent) {
    final programs = <EpgProgram>[];

    String? currentChannel;
    DateTime? currentStart;
    DateTime? currentStop;
    String? currentTitle;
    String? currentDesc;
    String? currentCategory;
    String? activeTag;
    final textBuffer = StringBuffer();

    for (final event in parseEvents(xmlContent)) {
      if (event is XmlStartElementEvent) {
        if (event.name == 'programme') {
          currentChannel = _attr(event, 'channel');
          currentStart = parseXmltvDate(_attr(event, 'start'));
          currentStop = parseXmltvDate(_attr(event, 'stop'));
          currentTitle = null;
          currentDesc = null;
          currentCategory = null;
        } else if (currentChannel != null &&
            (event.name == 'title' ||
                event.name == 'desc' ||
                event.name == 'category')) {
          activeTag = event.name;
          textBuffer.clear();
        }
      } else if (event is XmlTextEvent && activeTag != null) {
        textBuffer.write(event.value);
      } else if (event is XmlCDATAEvent && activeTag != null) {
        textBuffer.write(event.value);
      } else if (event is XmlEndElementEvent) {
        if (event.name == activeTag) {
          final text = textBuffer.toString().trim();
          if (text.isNotEmpty) {
            switch (activeTag) {
              case 'title':
                currentTitle ??= text;
                break;
              case 'desc':
                currentDesc ??= text;
                break;
              case 'category':
                currentCategory ??= text;
                break;
            }
          }
          activeTag = null;
        } else if (event.name == 'programme') {
          if (currentChannel != null &&
              currentChannel.isNotEmpty &&
              currentStart != null &&
              currentStop != null &&
              currentTitle != null &&
              currentTitle.isNotEmpty) {
            programs.add(
              EpgProgram(
                channelId: currentChannel,
                title: currentTitle,
                description: currentDesc,
                start: currentStart,
                end: currentStop,
                category: currentCategory,
              ),
            );
          }
          currentChannel = null;
          currentStart = null;
          currentStop = null;
          currentTitle = null;
          currentDesc = null;
          currentCategory = null;
          activeTag = null;
        }
      }
    }

    return programs;
  }

  static String? _attr(XmlStartElementEvent event, String name) {
    for (final a in event.attributes) {
      if (a.name == name) return a.value.trim();
    }
    return null;
  }

  /// Parses XMLTV timestamps like `20261123193000 -0700` or `20261123193000`.
  static DateTime? parseXmltvDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final match = _tsRegex.firstMatch(raw.trim());
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;
    final offsetStr = match.group(7);

    if (offsetStr == null) {
      return DateTime(year, month, day, hour, minute, second);
    }

    final sign = offsetStr.startsWith('-') ? -1 : 1;
    final offHours = int.parse(offsetStr.substring(1, 3));
    final offMinutes = int.parse(offsetStr.substring(3, 5));
    final offset = Duration(hours: offHours, minutes: offMinutes) * sign;

    final utc = DateTime.utc(year, month, day, hour, minute, second)
        .subtract(offset);
    return utc.toLocal();
  }
}

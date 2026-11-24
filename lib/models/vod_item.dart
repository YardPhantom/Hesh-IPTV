class VodItem {
  final String id;
  final String name;
  final String streamUrl;
  final String categoryName;
  final String? posterUrl;
  final String? rating;
  final String? containerExtension;

  const VodItem({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.categoryName = 'Movies',
    this.posterUrl,
    this.rating,
    this.containerExtension,
  });
}

class SeriesItem {
  final String id;
  final String name;
  final String categoryName;
  final String? posterUrl;
  final String? rating;
  final String? plot;

  const SeriesItem({
    required this.id,
    required this.name,
    this.categoryName = 'Series',
    this.posterUrl,
    this.rating,
    this.plot,
  });
}

class SeriesEpisode {
  final String id;
  final int season;
  final int episodeNum;
  final String title;
  final String streamUrl;
  final String? containerExtension;

  const SeriesEpisode({
    required this.id,
    required this.season,
    required this.episodeNum,
    required this.title,
    required this.streamUrl,
    this.containerExtension,
  });
}

class PlaybackProgress {
  final String sourceId;
  final String itemId;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  const PlaybackProgress({
    required this.sourceId,
    required this.itemId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });

  double get ratio =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'itemId': itemId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtMs': updatedAtMs,
      };

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) {
    return PlaybackProgress(
      sourceId: json['sourceId'] as String,
      itemId: json['itemId'] as String,
      positionMs: (json['positionMs'] as num).toInt(),
      durationMs: (json['durationMs'] as num).toInt(),
      updatedAtMs: (json['updatedAtMs'] as num).toInt(),
    );
  }
}

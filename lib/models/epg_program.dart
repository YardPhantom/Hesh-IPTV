class EpgProgram {
  final String channelId;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  final String? category;

  const EpgProgram({
    required this.channelId,
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.category,
  });

  bool isLiveAt(DateTime now) =>
      !now.isBefore(start) && now.isBefore(end);

  double progressAt(DateTime now) {
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return 0.0;
    final elapsedMs = now.difference(start).inMilliseconds;
    return (elapsedMs / totalMs).clamp(0.0, 1.0);
  }
}

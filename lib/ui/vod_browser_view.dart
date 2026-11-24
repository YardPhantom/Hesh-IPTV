import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../models/vod_item.dart';
import '../services/xtream_service.dart';

class VodBrowserView extends StatefulWidget {
  final PlaylistSource? activeSource;
  final bool isSeriesMode;
  final Map<String, PlaybackProgress> progressMap;
  final void Function({
    required String itemId,
    required String title,
    required String subtitle,
    required String streamUrl,
  }) onPlayMedia;

  const VodBrowserView({
    super.key,
    required this.activeSource,
    required this.isSeriesMode,
    required this.progressMap,
    required this.onPlayMedia,
  });

  @override
  State<VodBrowserView> createState() => _VodBrowserViewState();
}

class _VodBrowserViewState extends State<VodBrowserView> {
  final XtreamService _xtream = XtreamService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _loadedSourceKey;

  List<VodItem> _movies = [];
  List<SeriesItem> _series = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant VodBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSource?.id != widget.activeSource?.id ||
        oldWidget.isSeriesMode != widget.isSeriesMode) {
      _loadIfNeeded();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIfNeeded() async {
    final src = widget.activeSource;
    if (src == null || src.type != PlaylistSourceType.xtream) {
      setState(() {
        _movies = [];
        _series = [];
        _categories = ['All'];
        _error = null;
      });
      return;
    }

    final key = '${src.id}_${widget.isSeriesMode ? 'series' : 'vod'}';
    if (_loadedSourceKey == key) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.isSeriesMode) {
        final list = await _xtream.fetchSeries(
          serverUrl: src.url ?? '',
          username: src.username ?? '',
          password: src.password ?? '',
        );
        if (!mounted) return;
        final cats = {'All', ...list.map((e) => e.categoryName)}.toList();
        setState(() {
          _series = list;
          _categories = cats;
          _selectedCategory = 'All';
          _loadedSourceKey = key;
          _loading = false;
        });
      } else {
        final list = await _xtream.fetchVodMovies(
          serverUrl: src.url ?? '',
          username: src.username ?? '',
          password: src.password ?? '',
        );
        if (!mounted) return;
        final cats = {'All', ...list.map((e) => e.categoryName)}.toList();
        setState(() {
          _movies = list;
          _categories = cats;
          _selectedCategory = 'All';
          _loadedSourceKey = key;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openSeriesPicker(SeriesItem series) async {
    final src = widget.activeSource;
    if (src == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _SeriesEpisodesDialog(
        xtream: _xtream,
        source: src,
        series: series,
        progressMap: widget.progressMap,
        onPlayEpisode: (ep) {
          Navigator.of(context).pop();
          widget.onPlayMedia(
            itemId: ep.id,
            title: '${series.name} - ${ep.title}',
            subtitle: 'Season ${ep.season} • Episode ${ep.episodeNum}',
            streamUrl: ep.streamUrl,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.activeSource;
    if (src == null || src.type != PlaylistSourceType.xtream) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'VOD Movies & Series require an Xtream Codes playlist source.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.white60),
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  _loadedSourceKey = null;
                  _loadIfNeeded();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final q = _query.toLowerCase();
    final filteredMovies = _movies.where((m) {
      if (_selectedCategory != 'All' && m.categoryName != _selectedCategory) {
        return false;
      }
      return q.isEmpty || m.name.toLowerCase().contains(q);
    }).toList();

    final filteredSeries = _series.where((s) {
      if (_selectedCategory != 'All' && s.categoryName != _selectedCategory) {
        return false;
      }
      return q.isEmpty || s.name.toLowerCase().contains(q);
    }).toList();

    final count =
        widget.isSeriesMode ? filteredSeries.length : filteredMovies.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: widget.isSeriesMode
                        ? 'Search series...'
                        : 'Search movies...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedCategory),
                  initialValue: _categories.contains(_selectedCategory)
                      ? _selectedCategory
                      : 'All',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: count == 0
              ? const Center(child: Text('No items found.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.66,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    if (widget.isSeriesMode) {
                      final s = filteredSeries[index];
                      return _PosterCard(
                        title: s.name,
                        subtitle: s.categoryName,
                        posterUrl: s.posterUrl,
                        rating: s.rating,
                        progress: null,
                        onTap: () => _openSeriesPicker(s),
                      );
                    } else {
                      final m = filteredMovies[index];
                      return _PosterCard(
                        title: m.name,
                        subtitle: m.categoryName,
                        posterUrl: m.posterUrl,
                        rating: m.rating,
                        progress: widget.progressMap[m.id],
                        onTap: () => widget.onPlayMedia(
                          itemId: m.id,
                          title: m.name,
                          subtitle: m.categoryName,
                          streamUrl: m.streamUrl,
                        ),
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? posterUrl;
  final String? rating;
  final PlaybackProgress? progress;
  final VoidCallback onTap;

  const _PosterCard({
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.rating,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl != null && posterUrl!.isNotEmpty)
                    Image.network(
                      posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.movie, size: 42, color: Colors.white24),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.movie, size: 42, color: Colors.white24),
                    ),
                  if (rating != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          rating!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (progress != null && progress!.ratio > 0.02)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.ratio,
                        minHeight: 4,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesEpisodesDialog extends StatefulWidget {
  final XtreamService xtream;
  final PlaylistSource source;
  final SeriesItem series;
  final Map<String, PlaybackProgress> progressMap;
  final ValueChanged<SeriesEpisode> onPlayEpisode;

  const _SeriesEpisodesDialog({
    required this.xtream,
    required this.source,
    required this.series,
    required this.progressMap,
    required this.onPlayEpisode,
  });

  @override
  State<_SeriesEpisodesDialog> createState() => _SeriesEpisodesDialogState();
}

class _SeriesEpisodesDialogState extends State<_SeriesEpisodesDialog> {
  late Future<List<SeriesEpisode>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.xtream.fetchSeriesEpisodes(
      serverUrl: widget.source.url ?? '',
      username: widget.source.username ?? '',
      password: widget.source.password ?? '',
      seriesId: widget.series.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.series.name),
      content: SizedBox(
        width: 480,
        height: 460,
        child: FutureBuilder<List<SeriesEpisode>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Failed to load episodes: ${snap.error}'));
            }
            final episodes = snap.data ?? [];
            if (episodes.isEmpty) {
              return const Center(child: Text('No episodes found.'));
            }
            return ListView.builder(
              itemCount: episodes.length,
              itemBuilder: (context, index) {
                final ep = episodes[index];
                final prog = widget.progressMap[ep.id];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      'S${ep.season}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(ep.title, overflow: TextOverflow.ellipsis),
                  subtitle: prog != null && prog.ratio > 0.02
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Episode ${ep.episodeNum} • ${(prog.ratio * 100).round()}% watched'),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: prog.ratio, minHeight: 2),
                          ],
                        )
                      : Text('Episode ${ep.episodeNum}'),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () => widget.onPlayEpisode(ep),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

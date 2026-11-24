import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/vod_item.dart';
import '../services/database_service.dart';
import '../services/epg_service.dart';
import '../services/playlist_repository.dart';
import '../services/sync_service.dart';
import 'add_playlist_dialog.dart';
import 'epg_guide_view.dart';
import 'multi_view_view.dart';
import 'sync_dialog.dart';
import 'vod_browser_view.dart';

enum _ChannelFilterTab { all, favorites, recents }

enum _AppMode { live, guide, movies, series, multiView }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlaylistRepository _repo = PlaylistRepository();
  final DatabaseService _db = DatabaseService();
  late final EpgService _epgService;
  late final SyncService _syncService;
  late final Player _player;
  late final VideoController _videoController;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _epgTickTimer;
  Timer? _vodProgressTimer;

  _AppMode _mode = _AppMode.live;
  List<PlaylistSource> _sources = [];
  PlaylistSource? _activeSource;
  List<Channel> _allChannels = [];
  List<Channel> _filteredChannels = [];
  List<String> _groups = ['All'];
  String _selectedGroup = 'All';
  String _searchQuery = '';
  _ChannelFilterTab _filterTab = _ChannelFilterTab.all;

  Set<String> _favoriteIds = {};
  List<String> _recentIds = [];
  Map<String, EpgProgram> _currentPrograms = {};
  Map<String, List<EpgProgram>> _guidePrograms = {};
  Map<String, PlaybackProgress> _vodProgressMap = {};
  bool _isLoadingEpg = false;
  String? _detectedEpgUrl;

  Channel? _currentChannel;
  String? _activeVodItemId;
  String? _activeVodTitle;
  String? _activeVodSubtitle;

  bool _isLoadingPlaylist = false;
  String? _playlistError;
  String? _playerError;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _volume = 100.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _epgService = EpgService(db: _db);
    _syncService = SyncService(repo: _repo, db: _db);
    _player = Player();
    _videoController = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });
    _player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() => _playerError = err);
      }
    });

    _epgTickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _allChannels.isNotEmpty) {
        _loadEpgFromDb();
      }
    });

    _vodProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistActiveVodProgress();
    });

    _initSavedPlaylists();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _epgTickTimer?.cancel();
    _vodProgressTimer?.cancel();
    _searchCtrl.dispose();
    _player.dispose();
    _db.close();
    super.dispose();
  }

  Future<void> _persistActiveVodProgress() async {
    final itemId = _activeVodItemId;
    final src = _activeSource;
    if (itemId == null || src == null || !_isPlaying) return;
    final pos = _player.state.position.inMilliseconds;
    final dur = _player.state.duration.inMilliseconds;
    if (pos <= 0 || dur <= 0) return;

    final prog = PlaybackProgress(
      sourceId: src.id,
      itemId: itemId,
      positionMs: pos,
      durationMs: dur,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.savePlaybackProgress(prog);
    if (mounted) {
      setState(() => _vodProgressMap[itemId] = prog);
    }
  }

  Future<void> _initSavedPlaylists() async {
    final saved = await _repo.loadSavedSources();
    final activeId = await _repo.loadActiveSourceId();
    if (!mounted) return;
    setState(() {
      _sources = saved;
      if (saved.isNotEmpty) {
        _activeSource = saved.firstWhere(
          (s) => s.id == activeId,
          orElse: () => saved.first,
        );
      }
    });
    if (_activeSource != null) {
      await _loadPlaylist(_activeSource!);
    }
  }

  Future<void> _loadPlaylist(PlaylistSource source) async {
    setState(() {
      _activeSource = source;
      _isLoadingPlaylist = true;
      _playlistError = null;
      _detectedEpgUrl = null;
    });
    await _repo.saveSources(_sources, activeSourceId: source.id);

    try {
      final result = await _repo.fetchPlaylist(source);
      final favs = await _db.getFavoriteIds(source.id);
      final recents = await _db.getRecentIds(source.id);
      final vodProg = await _db.getPlaybackProgressForSource(source.id);
      if (!mounted) return;

      final groupSet = <String>{'All'};
      for (final ch in result.channels) {
        groupSet.add(ch.groupTitle);
      }
      setState(() {
        _allChannels = result.channels;
        _detectedEpgUrl = result.detectedEpgUrl;
        _favoriteIds = favs;
        _recentIds = recents;
        _vodProgressMap = vodProg;
        _groups = groupSet.toList();
        _selectedGroup = 'All';
        _isLoadingPlaylist = false;
      });
      _applyFilters();
      await _loadEpgFromDb();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPlaylist = false;
        _playlistError = e.toString();
      });
    }
  }

  Future<void> _loadEpgFromDb() async {
    final tvgIds = _allChannels
        .map((c) => c.tvgId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (tvgIds.isEmpty) return;

    final now = DateTime.now();
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute >= 30 ? 30 : 0,
    );
    final windowEnd = windowStart.add(const Duration(minutes: 180));

    final current = await _db.getCurrentPrograms(tvgIds, now);
    final range = await _db.getProgramsForRange(tvgIds, windowStart, windowEnd);
    if (!mounted) return;
    setState(() {
      _currentPrograms = current;
      _guidePrograms = range;
    });
  }

  Future<void> _refreshEpg() async {
    if (_activeSource == null) return;
    final epgUrl = _epgService.resolveEpgUrl(_activeSource!) ?? _detectedEpgUrl;
    if (epgUrl == null || epgUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No EPG URL configured on this playlist. Add an XMLTV URL when creating the playlist.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoadingEpg = true);
    try {
      final count = await _epgService.refreshEpg(epgUrl);
      await _loadEpgFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded $count EPG program entries.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('EPG refresh failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingEpg = false);
    }
  }

  Future<void> _openSyncDialog() async {
    final didImport = await showDialog<bool>(
      context: context,
      builder: (_) => SyncDialog(syncService: _syncService),
    );
    if (didImport == true) {
      await _initSavedPlaylists();
    }
  }

  Future<void> _toggleFavorite(Channel channel) async {
    if (_activeSource == null) return;
    final isFav = await _db.toggleFavorite(_activeSource!.id, channel.id);
    if (!mounted) return;
    setState(() {
      final next = Set<String>.from(_favoriteIds);
      if (isFav) {
        next.add(channel.id);
      } else {
        next.remove(channel.id);
      }
      _favoriteIds = next;
    });
    if (_filterTab == _ChannelFilterTab.favorites) {
      _applyFilters();
    }
  }

  void _applyFilters() {
    final q = _searchQuery.toLowerCase();
    Iterable<Channel> base = _allChannels;

    if (_filterTab == _ChannelFilterTab.favorites) {
      base = base.where((ch) => _favoriteIds.contains(ch.id));
    } else if (_filterTab == _ChannelFilterTab.recents) {
      final byId = {for (final ch in _allChannels) ch.id: ch};
      base = _recentIds.map((id) => byId[id]).whereType<Channel>();
    }

    final filtered = base.where((ch) {
      if (_filterTab == _ChannelFilterTab.all &&
          _selectedGroup != 'All' &&
          ch.groupTitle != _selectedGroup) {
        return false;
      }
      if (q.isNotEmpty &&
          !ch.name.toLowerCase().contains(q) &&
          !ch.groupTitle.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    setState(() {
      _filteredChannels = filtered;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      _searchQuery = value.trim();
      _applyFilters();
    });
  }

  Future<void> _playChannel(Channel channel) async {
    setState(() {
      _currentChannel = channel;
      _activeVodItemId = null;
      _activeVodTitle = null;
      _activeVodSubtitle = null;
      _playerError = null;
      _mode = _AppMode.live;
    });
    if (_activeSource != null) {
      await _db.recordRecent(_activeSource!.id, channel.id);
      final recents = await _db.getRecentIds(_activeSource!.id);
      if (mounted) {
        setState(() => _recentIds = recents);
        if (_filterTab == _ChannelFilterTab.recents) {
          _applyFilters();
        }
      }
    }
    await _player.open(
      Media(
        channel.streamUrl,
        httpHeaders: channel.httpHeaders.isEmpty ? null : channel.httpHeaders,
      ),
      play: true,
    );
  }

  Future<void> _playVodMedia({
    required String itemId,
    required String title,
    required String subtitle,
    required String streamUrl,
  }) async {
    setState(() {
      _currentChannel = null;
      _activeVodItemId = itemId;
      _activeVodTitle = title;
      _activeVodSubtitle = subtitle;
      _playerError = null;
      _mode = _AppMode.live;
    });

    await _player.open(Media(streamUrl), play: true);

    final saved = _vodProgressMap[itemId];
    if (saved != null && saved.positionMs > 5000 && saved.ratio < 0.95) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _player.seek(Duration(milliseconds: saved.positionMs));
    }
  }

  Future<void> _addPlaylist() async {
    final source = await showDialog<PlaylistSource>(
      context: context,
      builder: (_) => const AddPlaylistDialog(),
    );
    if (source == null) return;
    setState(() {
      _sources = [..._sources, source];
    });
    await _loadPlaylist(source);
  }

  Future<void> _deleteActivePlaylist() async {
    if (_activeSource == null) return;
    final toRemove = _activeSource!;
    final updated = _sources.where((s) => s.id != toRemove.id).toList();
    setState(() {
      _sources = updated;
      _activeSource = updated.isNotEmpty ? updated.first : null;
      _allChannels = [];
      _filteredChannels = [];
      _groups = ['All'];
      _selectedGroup = 'All';
      _favoriteIds = {};
      _recentIds = [];
      _currentPrograms = {};
      _guidePrograms = {};
      _vodProgressMap = {};
    });
    await _repo.saveSources(updated, activeSourceId: _activeSource?.id);
    if (_activeSource != null) {
      await _loadPlaylist(_activeSource!);
    }
  }

  void _toggleMute() {
    final nextMuted = !_isMuted;
    setState(() => _isMuted = nextMuted);
    _player.setVolume(nextMuted ? 0.0 : _volume);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 840;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space):
            const _TogglePlayIntent(),
        const SingleActivator(LogicalKeyboardKey.keyM):
            const _ToggleMuteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (_) {
              _player.playOrPause();
              return null;
            },
          ),
          _ToggleMuteIntent: CallbackAction<_ToggleMuteIntent>(
            onInvoke: (_) {
              _toggleMute();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('IPTV Player'),
            actions: [
              _modeAction(
                mode: _AppMode.live,
                icon: Icons.live_tv,
                label: 'Live',
              ),
              _modeAction(
                mode: _AppMode.guide,
                icon: Icons.calendar_view_day,
                label: 'Guide',
              ),
              _modeAction(
                mode: _AppMode.movies,
                icon: Icons.movie,
                label: 'Movies',
              ),
              _modeAction(
                mode: _AppMode.series,
                icon: Icons.tv_outlined,
                label: 'Series',
              ),
              _modeAction(
                mode: _AppMode.multiView,
                icon: Icons.grid_view,
                label: 'Multi',
              ),
              IconButton(
                tooltip: 'Cross-Device Sync',
                onPressed: _openSyncDialog,
                icon: const Icon(Icons.cloud_sync_outlined),
              ),
              if (_activeSource != null)
                IconButton(
                  tooltip: 'Refresh EPG',
                  onPressed: _isLoadingEpg ? null : _refreshEpg,
                  icon: _isLoadingEpg
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_repeat),
                ),
              if (_activeSource != null)
                IconButton(
                  tooltip: 'Reload Playlist',
                  onPressed: _isLoadingPlaylist
                      ? null
                      : () => _loadPlaylist(_activeSource!),
                  icon: const Icon(Icons.refresh),
                ),
              if (_activeSource != null)
                IconButton(
                  tooltip: 'Remove Playlist',
                  onPressed: _deleteActivePlaylist,
                  icon: const Icon(Icons.delete_outline),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _addPlaylist,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
          body: _buildBody(context, isWide),
        ),
      ),
    );
  }

  Widget _modeAction({
    required _AppMode mode,
    required IconData icon,
    required String label,
  }) {
    final selected = _mode == mode;
    return IconButton(
      tooltip: label,
      isSelected: selected,
      onPressed: () => setState(() => _mode = mode),
      icon: Icon(
        icon,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (_mode == _AppMode.multiView) {
      return MultiViewView(
        channels: _allChannels,
        initialChannel: _currentChannel,
      );
    }

    if (_mode == _AppMode.movies || _mode == _AppMode.series) {
      return VodBrowserView(
        activeSource: _activeSource,
        isSeriesMode: _mode == _AppMode.series,
        progressMap: _vodProgressMap,
        onPlayMedia: _playVodMedia,
      );
    }

    if (isWide) {
      return Row(
        children: [
          SizedBox(
            width: 370,
            child: _buildSidebar(context),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _mode == _AppMode.guide
                ? _buildEpgGuide()
                : _buildPlayerPane(context),
          ),
        ],
      );
    }

    if (_mode == _AppMode.guide) {
      return _buildEpgGuide();
    }

    final hasMedia = _currentChannel != null || _activeVodItemId != null;
    return Column(
      children: [
        if (hasMedia)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoSurface(context),
          ),
        Expanded(child: _buildSidebar(context)),
      ],
    );
  }

  Widget _buildEpgGuide() {
    return EpgGuideView(
      channels: _filteredChannels.isNotEmpty ? _filteredChannels : _allChannels,
      programsByChannel: _guidePrograms,
      currentChannel: _currentChannel,
      isLoadingEpg: _isLoadingEpg,
      onRefreshEpg: _refreshEpg,
      onSelectChannel: _playChannel,
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Column(
      children: [
        if (_sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: DropdownButtonFormField<PlaylistSource>(
              key: ValueKey(_activeSource?.id),
              initialValue: _activeSource,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Active Playlist',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _sources
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (source) {
                if (source != null) _loadPlaylist(source);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<_ChannelFilterTab>(
            segments: [
              const ButtonSegment(
                value: _ChannelFilterTab.all,
                label: Text('All'),
              ),
              ButtonSegment(
                value: _ChannelFilterTab.favorites,
                label: Text('Favs (${_favoriteIds.length})'),
              ),
              ButtonSegment(
                value: _ChannelFilterTab.recents,
                label: Text('Recent (${_recentIds.length})'),
              ),
            ],
            selected: {_filterTab},
            onSelectionChanged: (sel) {
              setState(() => _filterTab = sel.first);
              _applyFilters();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search ${_allChannels.length} channels...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _searchQuery = '';
                        _applyFilters();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_filterTab == _ChannelFilterTab.all && _groups.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_selectedGroup),
              initialValue:
                  _groups.contains(_selectedGroup) ? _selectedGroup : 'All',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _groups
                  .map(
                    (g) => DropdownMenuItem(
                      value: g,
                      child: Text(g, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (group) {
                if (group != null) {
                  _selectedGroup = group;
                  _applyFilters();
                }
              },
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _buildChannelList(context)),
      ],
    );
  }

  Widget _buildChannelList(BuildContext context) {
    if (_sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.live_tv, size: 56, color: Colors.white38),
              const SizedBox(height: 12),
              const Text(
                'No playlists added yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add an M3U URL, local .m3u file, or Xtream Codes account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addPlaylist,
                icon: const Icon(Icons.add),
                label: const Text('Add Playlist'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingPlaylist) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_playlistError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 8),
              Text(_playlistError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _activeSource == null
                    ? null
                    : () => _loadPlaylist(_activeSource!),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredChannels.isEmpty) {
      return const Center(
        child: Text('No channels match your filter.'),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      itemCount: _filteredChannels.length,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        final isSelected = _currentChannel?.id == channel.id;
        final isFav = _favoriteIds.contains(channel.id);
        final currentProg =
            channel.tvgId != null ? _currentPrograms[channel.tvgId!] : null;

        return ListTile(
          selected: isSelected,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
          leading: _ChannelLogo(logoUrl: channel.logoUrl),
          title: Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentProg != null
                    ? 'Now: ${currentProg.title}'
                    : channel.groupTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: currentProg != null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white60,
                ),
              ),
              if (currentProg != null) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: currentProg.progressAt(now),
                  minHeight: 2,
                ),
              ],
            ],
          ),
          trailing: IconButton(
            tooltip: isFav ? 'Remove Favorite' : 'Add Favorite',
            icon: Icon(
              isFav ? Icons.star : Icons.star_border,
              color: isFav ? Colors.amber : Colors.white54,
              size: 20,
            ),
            onPressed: () => _toggleFavorite(channel),
          ),
          onTap: () => _playChannel(channel),
        );
      },
    );
  }

  Widget _buildPlayerPane(BuildContext context) {
    final hasChannel = _currentChannel != null;
    final hasVod = _activeVodItemId != null;

    if (!hasChannel && !hasVod) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv, size: 72, color: Colors.white24),
            SizedBox(height: 12),
            Text(
              'Select a channel or VOD item to start watching',
              style: TextStyle(fontSize: 16, color: Colors.white60),
            ),
          ],
        ),
      );
    }

    final currentProg = hasChannel && _currentChannel!.tvgId != null
        ? _currentPrograms[_currentChannel!.tvgId!]
        : null;
    final isFav = hasChannel && _favoriteIds.contains(_currentChannel!.id);

    final title = hasChannel ? _currentChannel!.name : (_activeVodTitle ?? '');
    final subtitle = hasChannel
        ? (currentProg != null
            ? 'Now: ${currentProg.title}'
            : _currentChannel!.groupTitle)
        : (_activeVodSubtitle ?? '');

    return Column(
      children: [
        Expanded(child: _buildVideoSurface(context)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: _player.playOrPause,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              if (hasChannel) ...[
                IconButton(
                  tooltip: 'Reconnect Stream',
                  onPressed: () => _playChannel(_currentChannel!),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: isFav ? 'Remove Favorite' : 'Add Favorite',
                  onPressed: () => _toggleFavorite(_currentChannel!),
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : null,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _isMuted ? 'Unmute' : 'Mute',
                onPressed: _toggleMute,
                icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              ),
              SizedBox(
                width: 120,
                child: Slider(
                  value: _isMuted ? 0.0 : _volume,
                  min: 0,
                  max: 100,
                  onChanged: (val) {
                    setState(() {
                      _volume = val;
                      _isMuted = val == 0;
                    });
                    _player.setVolume(val);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoSurface(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Video(controller: _videoController),
        ),
        if (_isBuffering) const Center(child: CircularProgressIndicator()),
        if (_playerError != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Stream error: $_playerError',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_currentChannel != null)
                      TextButton(
                        onPressed: () => _playChannel(_currentChannel!),
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  final String? logoUrl;

  const _ChannelLogo({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.isEmpty) {
      return const CircleAvatar(
        child: Icon(Icons.tv, size: 18),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        logoUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const CircleAvatar(
          child: Icon(Icons.tv, size: 18),
        ),
      ),
    );
  }
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _ToggleMuteIntent extends Intent {
  const _ToggleMuteIntent();
}

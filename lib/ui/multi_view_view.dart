import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';

class MultiViewView extends StatefulWidget {
  final List<Channel> channels;
  final Channel? initialChannel;

  const MultiViewView({
    super.key,
    required this.channels,
    this.initialChannel,
  });

  @override
  State<MultiViewView> createState() => _MultiViewViewState();
}

class _Slot {
  final Player player;
  late final VideoController controller;
  Channel? channel;

  _Slot() : player = Player() {
    controller = VideoController(player);
  }

  Future<void> open(Channel ch) async {
    channel = ch;
    await player.open(
      Media(
        ch.streamUrl,
        httpHeaders: ch.httpHeaders.isEmpty ? null : ch.httpHeaders,
      ),
      play: true,
    );
  }

  Future<void> clear() async {
    channel = null;
    await player.stop();
  }

  void dispose() {
    player.dispose();
  }
}

class _MultiViewViewState extends State<MultiViewView> {
  final List<_Slot> _slots = List.generate(4, (_) => _Slot());
  int _slotCount = 4; // 2 or 4
  int _audioFocusIndex = 0;

  @override
  void initState() {
    super.initState();
    _applyAudioFocus(0);
    if (widget.initialChannel != null) {
      _slots[0].open(widget.initialChannel!);
    }
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  void _applyAudioFocus(int index) {
    setState(() => _audioFocusIndex = index);
    for (int i = 0; i < _slots.length; i++) {
      _slots[i].player.setVolume(i == index ? 100.0 : 0.0);
    }
  }

  Future<void> _pickChannelForSlot(int index) async {
    if (widget.channels.isEmpty) return;
    final picked = await showDialog<Channel>(
      context: context,
      builder: (_) => _ChannelPickerDialog(channels: widget.channels),
    );
    if (picked == null || !mounted) return;
    setState(() {});
    await _slots[index].open(picked);
    _applyAudioFocus(_audioFocusIndex);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final crossAxisCount = _slotCount == 2 ? (isWide ? 2 : 1) : (isWide ? 2 : 1);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.grid_view, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Multi-View',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Spacer(),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('2 Screens')),
                  ButtonSegment(value: 4, label: Text('4 Screens')),
                ],
                selected: {_slotCount},
                onSelectionChanged: (sel) {
                  setState(() => _slotCount = sel.first);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: GridView.builder(
              itemCount: _slotCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 16 / 9,
              ),
              itemBuilder: (context, index) => _buildSlotTile(context, index),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlotTile(BuildContext context, int index) {
    final slot = _slots[index];
    final isAudioFocused = _audioFocusIndex == index;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAudioFocused
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: isAudioFocused ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slot.channel != null)
            Video(controller: slot.controller)
          else
            Center(
              child: FilledButton.tonalIcon(
                onPressed: () => _pickChannelForSlot(index),
                icon: const Icon(Icons.add_to_queue),
                label: Text('Assign Screen ${index + 1}'),
              ),
            ),
          Positioned(
            top: 6,
            left: 8,
            right: 8,
            child: Row(
              children: [
                if (slot.channel != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        slot.channel!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: isAudioFocused ? 'Audio Active' : 'Focus Audio Here',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applyAudioFocus(index),
                  icon: Icon(
                    isAudioFocused ? Icons.volume_up : Icons.volume_off,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Change Channel',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _pickChannelForSlot(index),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                ),
                if (slot.channel != null) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Clear Screen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await slot.clear();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelPickerDialog extends StatefulWidget {
  final List<Channel> channels;

  const _ChannelPickerDialog({required this.channels});

  @override
  State<_ChannelPickerDialog> createState() => _ChannelPickerDialogState();
}

class _ChannelPickerDialogState extends State<_ChannelPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = q.isEmpty
        ? widget.channels
        : widget.channels
            .where((c) => c.name.toLowerCase().contains(q))
            .toList();

    return AlertDialog(
      title: const Text('Select Channel'),
      content: SizedBox(
        width: 400,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Search channels...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final ch = filtered[index];
                  return ListTile(
                    dense: true,
                    title: Text(ch.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(ch.groupTitle, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(ch),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

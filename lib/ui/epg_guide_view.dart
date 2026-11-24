import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';

class EpgGuideView extends StatelessWidget {
  final List<Channel> channels;
  final Map<String, List<EpgProgram>> programsByChannel;
  final Channel? currentChannel;
  final bool isLoadingEpg;
  final VoidCallback onRefreshEpg;
  final ValueChanged<Channel> onSelectChannel;

  const EpgGuideView({
    super.key,
    required this.channels,
    required this.programsByChannel,
    required this.currentChannel,
    required this.isLoadingEpg,
    required this.onRefreshEpg,
    required this.onSelectChannel,
  });

  static const double _pixelsPerMinute = 4.0;
  static const int _windowMinutes = 180; // 3 hours
  static const double _channelColWidth = 170.0;
  static const double _rowHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute >= 30 ? 30 : 0,
    );
    final windowEnd = windowStart.add(const Duration(minutes: _windowMinutes));
    const timelineWidth = _windowMinutes * _pixelsPerMinute;

    // Limit rendered rows to channels that have a tvgId or first 150 channels for snappy layout.
    final guideChannels = channels.where((c) => c.tvgId != null).toList();
    final displayChannels = guideChannels.isNotEmpty
        ? guideChannels.take(150).toList()
        : channels.take(150).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.calendar_view_day, size: 20),
              const SizedBox(width: 8),
              const Text(
                'TV Guide (3-Hour Window)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Spacer(),
              if (isLoadingEpg)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onRefreshEpg,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Refresh EPG'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (programsByChannel.isEmpty && !isLoadingEpg)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_note,
                        size: 56, color: Colors.white30),
                    const SizedBox(height: 12),
                    const Text(
                      'No EPG data loaded for these channels',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add an XMLTV EPG URL to your playlist or tap Refresh EPG.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onRefreshEpg,
                      icon: const Icon(Icons.sync),
                      label: const Text('Load / Refresh EPG'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _channelColWidth + timelineWidth,
                child: Column(
                  children: [
                    _buildTimeHeader(context, windowStart),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: displayChannels.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final channel = displayChannels[index];
                          final progs = channel.tvgId != null
                              ? (programsByChannel[channel.tvgId!] ?? const [])
                              : const <EpgProgram>[];
                          return _buildChannelRow(
                            context,
                            channel,
                            progs,
                            windowStart,
                            windowEnd,
                            now,
                            timelineWidth,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeHeader(BuildContext context, DateTime windowStart) {
    final slots = _windowMinutes ~/ 30;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: _channelColWidth,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const Text(
              'Channel',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          ...List.generate(slots, (i) {
            final slotTime = windowStart.add(Duration(minutes: i * 30));
            final hh = slotTime.hour.toString().padLeft(2, '0');
            final mm = slotTime.minute.toString().padLeft(2, '0');
            return Container(
              width: 30 * _pixelsPerMinute,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Text(
                '$hh:$mm',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChannelRow(
    BuildContext context,
    Channel channel,
    List<EpgProgram> programs,
    DateTime windowStart,
    DateTime windowEnd,
    DateTime now,
    double timelineWidth,
  ) {
    final isSelected = currentChannel?.id == channel.id;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          InkWell(
            onTap: () => onSelectChannel(channel),
            child: Container(
              width: _channelColWidth,
              height: _rowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withAlpha(90)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                    Image.network(
                      channel.logoUrl!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.tv, size: 20),
                    )
                  else
                    const Icon(Icons.tv, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: timelineWidth,
            height: _rowHeight,
            child: Stack(
              children: [
                if (programs.isEmpty)
                  InkWell(
                    onTap: () => onSelectChannel(channel),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text(
                        'No program info',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    ),
                  )
                else
                  ...programs.map((prog) {
                    final clampedStart = prog.start.isBefore(windowStart)
                        ? windowStart
                        : prog.start;
                    final clampedEnd =
                        prog.end.isAfter(windowEnd) ? windowEnd : prog.end;
                    final leftMin =
                        clampedStart.difference(windowStart).inMinutes;
                    final durMin =
                        clampedEnd.difference(clampedStart).inMinutes;
                    if (durMin <= 0) return const SizedBox.shrink();

                    final isLive = prog.isLiveAt(now);
                    return Positioned(
                      left: leftMin * _pixelsPerMinute,
                      width: durMin * _pixelsPerMinute,
                      top: 4,
                      bottom: 4,
                      child: InkWell(
                        onTap: () => onSelectChannel(channel),
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isLive
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withAlpha(140)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isLive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                prog.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (prog.category != null)
                                Text(
                                  prog.category!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white60,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

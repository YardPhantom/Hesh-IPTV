import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/channel.dart';

class AddPlaylistDialog extends StatefulWidget {
  const AddPlaylistDialog({super.key});

  @override
  State<AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<AddPlaylistDialog> {
  PlaylistSourceType _type = PlaylistSourceType.m3uUrl;
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _epgCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _pickedFilePath;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _epgCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (files.isNotEmpty && files.first.path != null) {
      setState(() {
        _pickedFilePath = files.first.path;
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = files.first.name;
        }
        _error = null;
      });
    }
  }

  void _fillPublicTestPlaylist() {
    setState(() {
      _type = PlaylistSourceType.m3uUrl;
      _nameCtrl.text = 'Public Test Streams';
      _urlCtrl.text =
          'https://iptv-org.github.io/iptv/languages/eng.m3u';
      _error = null;
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a playlist name.');
      return;
    }

    final epgUrl = _epgCtrl.text.trim();
    final optionalEpg = epgUrl.isEmpty ? null : epgUrl;

    switch (_type) {
      case PlaylistSourceType.m3uUrl:
        final url = _urlCtrl.text.trim();
        if (url.isEmpty ||
            (!url.startsWith('http://') && !url.startsWith('https://'))) {
          setState(() => _error = 'Enter a valid http:// or https:// M3U URL.');
          return;
        }
        Navigator.of(context).pop(
          PlaylistSource(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: PlaylistSourceType.m3uUrl,
            url: url,
            epgUrl: optionalEpg,
          ),
        );
        break;

      case PlaylistSourceType.m3uFile:
        if (_pickedFilePath == null || _pickedFilePath!.isEmpty) {
          setState(() => _error = 'Please select an M3U/M3U8 file.');
          return;
        }
        Navigator.of(context).pop(
          PlaylistSource(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: PlaylistSourceType.m3uFile,
            filePath: _pickedFilePath,
            epgUrl: optionalEpg,
          ),
        );
        break;

      case PlaylistSourceType.xtream:
        final url = _urlCtrl.text.trim();
        final user = _userCtrl.text.trim();
        final pass = _passCtrl.text;
        if (url.isEmpty || user.isEmpty || pass.isEmpty) {
          setState(() => _error = 'Server URL, username, and password are required.');
          return;
        }
        Navigator.of(context).pop(
          PlaylistSource(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: PlaylistSourceType.xtream,
            url: url,
            username: user,
            password: pass,
            epgUrl: optionalEpg,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Playlist Source'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PlaylistSourceType>(
                segments: const [
                  ButtonSegment(
                    value: PlaylistSourceType.m3uUrl,
                    label: Text('M3U URL'),
                    icon: Icon(Icons.link),
                  ),
                  ButtonSegment(
                    value: PlaylistSourceType.m3uFile,
                    label: Text('M3U File'),
                    icon: Icon(Icons.folder_open),
                  ),
                  ButtonSegment(
                    value: PlaylistSourceType.xtream,
                    label: Text('Xtream'),
                    icon: Icon(Icons.dns),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Playlist Name',
                  hintText: 'e.g. Living Room TV',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_type == PlaylistSourceType.m3uUrl) ...[
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'M3U / M3U8 URL',
                    hintText: 'https://example.com/playlist.m3u8',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _fillPublicTestPlaylist,
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('Fill public iptv-org English playlist'),
                  ),
                ),
              ] else if (_type == PlaylistSourceType.m3uFile) ...[
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open),
                  label: Text(
                    _pickedFilePath == null
                        ? 'Choose .m3u / .m3u8 file'
                        : _pickedFilePath!,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://provider.example.com:8080',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _epgCtrl,
                decoration: const InputDecoration(
                  labelText: 'XMLTV EPG URL (optional)',
                  hintText: 'https://example.com/epg.xml.gz',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add & Load'),
        ),
      ],
    );
  }
}

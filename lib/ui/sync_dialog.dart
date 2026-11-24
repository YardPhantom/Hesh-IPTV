import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';

class SyncDialog extends StatefulWidget {
  final SyncService syncService;

  const SyncDialog({super.key, required this.syncService});

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  static const _webdavUrlKey = 'iptv_webdav_url_v1';
  static const _webdavUserKey = 'iptv_webdav_user_v1';

  final _webdavUrlCtrl = TextEditingController();
  final _webdavUserCtrl = TextEditingController();
  final _webdavPassCtrl = TextEditingController();

  bool _busy = false;
  String? _status;
  bool _isError = false;
  bool _didImport = false;

  @override
  void initState() {
    super.initState();
    _loadSavedWebDav();
  }

  Future<void> _loadSavedWebDav() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _webdavUrlCtrl.text = prefs.getString(_webdavUrlKey) ?? '';
    _webdavUserCtrl.text = prefs.getString(_webdavUserKey) ?? '';
  }

  @override
  void dispose() {
    _webdavUrlCtrl.dispose();
    _webdavUserCtrl.dispose();
    _webdavPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportFile() async {
    setState(() {
      _busy = true;
      _status = null;
      _isError = false;
    });
    try {
      final jsonStr = await widget.syncService.exportBackupJson();
      final bytes = utf8.encode(jsonStr);
      final saveUri = await FilePicker.saveFile(
        dialogTitle: 'Export IPTV Sync Bundle',
        fileName: 'iptv_sync.json',
        bytes: bytes,
      );
      if (saveUri != null) {
        final file = File.fromUri(saveUri);
        if (!await file.exists()) {
          await file.writeAsString(jsonStr);
        }
        setState(() => _status = 'Exported sync bundle to ${file.path}');
      } else {
        setState(() => _status = 'Export cancelled.');
      }
    } catch (e) {
      setState(() {
        _status = 'Export failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    setState(() {
      _busy = true;
      _status = null;
      _isError = false;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty || files.first.path == null) {
        setState(() => _status = 'Import cancelled.');
        return;
      }
      final raw = await File(files.first.path!).readAsString();
      final summary = await widget.syncService.importBackupJson(raw);
      _didImport = true;
      setState(
        () => _status =
            'Imported ${summary.sourcesAdded} new playlists, ${summary.favoritesSynced} favorites, ${summary.progressSynced} resume items.',
      );
    } catch (e) {
      setState(() {
        _status = 'Import failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _webdavPush() async {
    final url = _webdavUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = 'Enter a WebDAV file URL (e.g. https://nas/dav/iptv_sync.json).';
        _isError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _isError = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webdavUrlKey, url);
      await prefs.setString(_webdavUserKey, _webdavUserCtrl.text.trim());

      await widget.syncService.pushToWebDav(
        fileUrl: url,
        username: _webdavUserCtrl.text,
        password: _webdavPassCtrl.text,
      );
      setState(() => _status = 'Pushed sync bundle to WebDAV.');
    } catch (e) {
      setState(() {
        _status = 'WebDAV push failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _webdavPull() async {
    final url = _webdavUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = 'Enter a WebDAV file URL.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _isError = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webdavUrlKey, url);
      await prefs.setString(_webdavUserKey, _webdavUserCtrl.text.trim());

      final summary = await widget.syncService.pullFromWebDav(
        fileUrl: url,
        username: _webdavUserCtrl.text,
        password: _webdavPassCtrl.text,
      );
      _didImport = true;
      setState(
        () => _status =
            'Pulled ${summary.sourcesAdded} new playlists, ${summary.favoritesSynced} favorites, ${summary.progressSynced} resume items.',
      );
    } catch (e) {
      setState(() {
        _status = 'WebDAV pull failed: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cross-Device Sync'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'File / Cloud Folder Sync (OneDrive, Google Drive, Syncthing)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _exportFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Export JSON'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _importFile,
                      icon: const Icon(Icons.download),
                      label: const Text('Import JSON'),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                'WebDAV / NAS Sync',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _webdavUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'WebDAV JSON File URL',
                  hintText: 'https://cloud.example.com/remote.php/dav/files/user/iptv_sync.json',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _webdavUserCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _webdavPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _webdavPush,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Push'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _webdavPull,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Pull'),
                    ),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isError
                        ? Theme.of(context).colorScheme.error
                        : Colors.greenAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_didImport),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

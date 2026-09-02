import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/sync_api.dart';
import '../services/sync_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class SyncTrack {
  final String fileName;
  final SyncTrackStatus status;
  SyncTrack(this.fileName, this.status);
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedPath = 'Папка не выбрана';
  String _syncStatus = 'Ожидание действий';
  bool _isLoading = false;
  List<SyncTrack> _tracks = [];
  StreamSubscription<SyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text =
          prefs.getString('server_ip') ?? 'http://192.168.1.100:8080';
      _apiKeyController.text = prefs.getString('api_key') ?? '';
      _selectedPath = prefs.getString('target_path') ?? 'Папка не выбрана';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', _ipController.text.trim());
    await prefs.setString('api_key', _apiKeyController.text.trim());
    await prefs.setString('target_path', _selectedPath);
  }

  Future<void> _pickDirectory() async {
    String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      setState(() => _selectedPath = directoryPath);
      await _saveSettings();
    }
  }

  Future<void> _runSync() async {
    if (_selectedPath == 'Папка не выбрана') {
      setState(() => _syncStatus = 'Ошибка: Сначала выберите папку!');
      return;
    }

    bool hasAccess = false;
    if (Platform.isAndroid) {
      if (await Permission.audio.isGranted ||
          await Permission.storage.isGranted) {
        hasAccess = true;
      } else {
        final audioStatus = await Permission.audio.request();
        if (audioStatus.isGranted) {
          hasAccess = true;
        } else {
          final storageStatus = await Permission.storage.request();
          hasAccess = storageStatus.isGranted;
        }
      }
    } else {
      hasAccess = true;
    }

    if (!hasAccess) {
      setState(() => _syncStatus =
          'Ошибка: Нет прав на чтение аудиофайлов!\nПроверьте настройки приложения.');
      return;
    }

    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _syncStatus = 'Ошибка: Введите адрес сервера!');
      return;
    }

    await _saveSettings();

    setState(() {
      _isLoading = true;
      _syncStatus = 'Запуск синхронизации...';
      _tracks.clear();
    });

    final api = SyncApi(baseUrl: '$ip/api', apiKey: _apiKeyController.text.trim());
    final syncManager = SyncManager(api: api);

    _syncSubscription = syncManager.startSync(_selectedPath).listen(
      (event) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case StatusUpdate(:final message):
              _syncStatus = message;
            case TracksReady(:final tracks):
              _tracks = tracks
                  .map((t) => SyncTrack(
                      t['fileName'] as String, SyncTrackStatus.waiting))
                  .toList();
            case TrackUpdate(:final fileName, :final status):
              final index = _tracks.indexWhere((t) => t.fileName == fileName);
              if (index != -1) {
                _tracks[index] = SyncTrack(fileName, status);
              }
            case SyncComplete():
              _isLoading = false;
              _syncStatus = 'Синхронизация завершена!';
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _syncStatus = 'Ошибка: $error';
        });
      },
      onDone: () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  Widget _buildStatusIcon(SyncTrackStatus status, ColorScheme colorScheme) {
    switch (status) {
      case SyncTrackStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case SyncTrackStatus.syncing:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
        );
      case SyncTrackStatus.error:
        return const Icon(Icons.error_outline, color: Colors.red, size: 20);
      case SyncTrackStatus.waiting:
        return Icon(Icons.pending_outlined, color: Colors.grey, size: 20);
    }
  }

  Widget _buildStatusText(SyncTrackStatus status) {
    switch (status) {
      case SyncTrackStatus.success:
        return const Text('Готово',
            style: TextStyle(color: Colors.green, fontSize: 12));
      case SyncTrackStatus.syncing:
        return const Text('Загрузка...',
            style: TextStyle(color: Colors.blue, fontSize: 12));
      case SyncTrackStatus.error:
        return const Text('Ошибка',
            style: TextStyle(color: Colors.red, fontSize: 12));
      case SyncTrackStatus.waiting:
        return const Text('Ожидание',
            style: TextStyle(color: Colors.grey, fontSize: 12));
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Icon(Icons.sync, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 10),
                  Text('Kivo Sync',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            Text('Настройки сервера',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'Адрес сервера (с портом)',
                hintText: 'http://192.168.1.XX:8080',
                prefixIcon: const Icon(Icons.dns_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API ключ',
                hintText: 'Введите API ключ',
                prefixIcon: const Icon(Icons.key),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),

            Text('Локальное хранилище',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isLoading ? null : _pickDirectory,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Папка для синхронизации',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(_selectedPath,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.drive_file_rename_outline_outlined,
                        color: colorScheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.pop(context);
                      _runSync();
                    },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync, size: 24),
              label: Text(
                  _isLoading ? 'Синхронизация...' : 'Запустить синхронизацию'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kivo Sync'),
        centerTitle: true,
        elevation: 0,
      ),
      drawer: _buildDrawer(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Общий статус',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: SelectableText(
                _syncStatus,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFE0E0E0),
                    height: 1.4),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Список файлов (${_tracks.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_tracks.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _tracks.clear()),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Очистить'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 400,
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: _tracks.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading ? 'Сканирование файлов...' : 'Список пуст',
                        style:
                            TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading:
                              _buildStatusIcon(track.status, colorScheme),
                          title: Text(track.fileName,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: _buildStatusText(track.status),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

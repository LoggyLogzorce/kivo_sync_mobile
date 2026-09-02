import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/hasher.dart';
import 'sync_api.dart';

enum SyncTrackStatus { waiting, syncing, success, error }

sealed class SyncEvent {
  const SyncEvent();
}

class StatusUpdate extends SyncEvent {
  final String message;
  const StatusUpdate(this.message);
}

class TracksReady extends SyncEvent {
  final List<Map<String, String>> tracks;
  const TracksReady(this.tracks);
}

class TrackUpdate extends SyncEvent {
  final String fileName;
  final SyncTrackStatus status;
  const TrackUpdate(this.fileName, this.status);
}

class SyncComplete extends SyncEvent {
  const SyncComplete();
}

class LocalFileMetadata {
  final File file;
  final String filename;
  String? audioFingerprint;
  String? lrcFingerprint;

  LocalFileMetadata({required this.file, required this.filename});
}

class SyncManager {
  final SyncApi api;

  SyncManager({required this.api});

  Stream<SyncEvent> startSync(String targetDirectoryPath) async* {
    String cleanPath = targetDirectoryPath;
    if (cleanPath.startsWith('content://')) {
      final uri = Uri.parse(targetDirectoryPath);
      if (uri.pathSegments.contains('primary:')) {
        final relativePath = targetDirectoryPath.split('primary%3A').last;
        cleanPath = '/storage/emulated/0/$relativePath';
      }
    }

    final dir = Directory(cleanPath);
    if (!await dir.exists()) {
      throw Exception(
          'Выбранная папка не существует или недоступна: $cleanPath');
    }

    yield const StatusUpdate('🔍 Сканирование локальной папки...');
    final List<FileSystemEntity> entities = await dir.list(recursive: false).toList();
    final List<LocalFileMetadata> localTracks = [];
    final List<LocalFileMetadata> localLyrics = [];

    for (var entity in entities) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        final filename = p.basename(entity.path);

        if (['.mp3', '.wav', '.ogg', '.flac', '.m4a'].contains(ext)) {
          final meta = LocalFileMetadata(file: entity, filename: filename);
          meta.audioFingerprint = await Hasher.computeAudioFingerprint(entity);
          localTracks.add(meta);
        } else if (ext == '.lrc') {
          final meta = LocalFileMetadata(file: entity, filename: filename);
          meta.lrcFingerprint = await Hasher.computeLrcFingerprint(entity);
          localLyrics.add(meta);
        }
      }
    }

    yield const StatusUpdate('📡 Сверка медиатеки с сервером...');
    final List<Map<String, dynamic>> checkData = [];

    for (var track in localTracks) {
      final baseName = p.basenameWithoutExtension(track.filename).toLowerCase();
      final matchedLrc = localLyrics.firstWhere(
        (lrc) =>
            p.basenameWithoutExtension(lrc.filename).toLowerCase() == baseName,
        orElse: () => LocalFileMetadata(file: File(''), filename: ''),
      );

      final Map<String, dynamic> jsonItem = {
        'filename': track.filename,
        'audio_finger_print': track.audioFingerprint,
      };

      if (matchedLrc.filename.isNotEmpty) {
        jsonItem['lrc_finger_print'] = matchedLrc.lrcFingerprint;
      }
      checkData.add(jsonItem);
    }

    final syncPlan = await api.checkSync(checkData);
    if (syncPlan == null) {
      throw Exception('Сервер не вернул план синхронизации (null)');
    }

    final downloads = syncPlan['download'] as List<dynamic>? ?? [];
    final uploads = syncPlan['upload'] as List<dynamic>? ?? [];

    yield StatusUpdate('Найдено локально: ${localTracks.length} треков.\n'
        'План от сервера: Скачать ${downloads.length}, Загрузить ${uploads.length}.\n'
        'Через 3 секунды продолжим...');

    final allFileNames = <String>{
      for (var item in uploads)
        (item as Map<String, dynamic>)['filename'] as String,
      for (var item in downloads)
        (item as Map<String, dynamic>)['filename'] as String,
    };
    yield TracksReady(
      allFileNames
          .map((name) => {'fileName': name, 'status': 'waiting'})
          .toList(),
    );

    await Future.delayed(const Duration(seconds: 3));

    // --- ОБРАБОТКА UPLOAD ---
    int currentUpload = 1;
    for (var item in uploads) {
      final mapItem = item as Map<String, dynamic>;

      if (mapItem['type'] == 'audio') {
        final local = localTracks.firstWhere(
          (t) => t.audioFingerprint == mapItem['audio_fingerprint'],
          orElse: () => LocalFileMetadata(file: File(''), filename: ''),
        );
        if (local.filename.isNotEmpty) {
          yield TrackUpdate(local.filename, SyncTrackStatus.syncing);
          yield StatusUpdate(
              '⬆️ [Загрузка $currentUpload/${uploads.length}]\nОтправка трека:\n${local.filename}');
          await api.uploadTrack(
              mapItem['audio_fingerprint'], local.file, local.filename);
          yield TrackUpdate(local.filename, SyncTrackStatus.success);
        }
      } else if (mapItem['type'] == 'lyrics') {
        final local = localLyrics.firstWhere(
          (l) => l.lrcFingerprint == mapItem['lrc_fingerprint'],
          orElse: () => LocalFileMetadata(file: File(''), filename: ''),
        );
        if (local.filename.isNotEmpty) {
          yield TrackUpdate(local.filename, SyncTrackStatus.syncing);
          yield StatusUpdate(
              '⬆️ [Загрузка $currentUpload/${uploads.length}]\nОтправка лирики:\n${local.filename}');
          await api.uploadLyrics(mapItem['audio_fingerprint'],
              mapItem['lrc_fingerprint'], local.file, local.filename);
          yield TrackUpdate(local.filename, SyncTrackStatus.success);
        }
      }
      currentUpload++;
    }

    // --- ОБРАБОТКА DOWNLOAD ---
    int currentDownload = 1;
    for (var item in downloads) {
      final mapItem = item as Map<String, dynamic>;
      final String savePath = p.join(cleanPath, mapItem['filename']);
      final String filename = mapItem['filename'] ?? 'Неизвестный файл';

      if (mapItem['type'] == 'audio') {
        yield TrackUpdate(filename, SyncTrackStatus.syncing);
        yield StatusUpdate(
            '⬇️ [Скачивание $currentDownload/${downloads.length}]\nЗагрузка трека:\n$filename');
        await api.downloadTrack(mapItem['audio_fingerprint'], savePath);
        yield TrackUpdate(filename, SyncTrackStatus.success);
      } else if (mapItem['type'] == 'lyrics') {
        yield TrackUpdate(filename, SyncTrackStatus.syncing);
        yield StatusUpdate(
            '⬇️ [Скачивание $currentDownload/${downloads.length}]\nЗагрузка лирики:\n$filename');
        await api.downloadLyrics(
            mapItem['audio_fingerprint'], mapItem['lrc_fingerprint'], savePath);
        yield TrackUpdate(filename, SyncTrackStatus.success);
      }
      currentDownload++;
    }

    yield const StatusUpdate('🎉 Все файлы синхронизированы!');
    yield const SyncComplete();
  }
}

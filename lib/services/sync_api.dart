import 'dart:io';
import 'package:dio/dio.dart';

class SyncApi {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
  ));
  final String baseUrl;

  SyncApi({required this.baseUrl, String? apiKey}) {
    if (apiKey != null && apiKey.isNotEmpty) {
      _dio.options.headers['Authorization'] = apiKey;
    }
  }

  /// POST /api/sync/check
  Future<Map<String, dynamic>?> checkSync(List<Map<String, dynamic>> files) async {
    try {
      final response = await _dio.post(
        '$baseUrl/sync/check',
        data: files,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      print('Ошибка checkSync: $e');
    }
    return null;
  }

  /// POST /api/tracks/:audio-fingerprint
  Future<bool> uploadTrack(String fingerprint, File file, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: filename),
      });

      final response = await _dio.post(
        '$baseUrl/tracks/$fingerprint',
        data: formData,
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка uploadTrack: $e');
      return false;
    }
  }

  /// POST /api/tracks/:audio-fingerprint/lyrics/:lrc-fingerprint
  Future<bool> uploadLyrics(String audioFp, String lrcFp, File file, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: filename),
      });

      final response = await _dio.post(
        '$baseUrl/tracks/$audioFp/lyrics/$lrcFp',
        data: formData,
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка uploadLyrics: $e');
      return false;
    }
  }

  /// GET /api/tracks/:audio-fingerprint (Скачивание трека)
  Future<bool> downloadTrack(String fingerprint, String savePath) async {
    try {
      final response = await _dio.download(
        '$baseUrl/tracks/$fingerprint',
        savePath,
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка downloadTrack: $e');
      return false;
    }
  }

  /// GET /api/tracks/:audio-fingerprint/lyrics/:lrc-fingerprint
  Future<bool> downloadLyrics(String audioFp, String lrcFp, String savePath) async {
    try {
      final response = await _dio.download(
        '$baseUrl/tracks/$audioFp/lyrics/$lrcFp',
        savePath,
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка downloadLyrics: $e');
      return false;
    }
  }
}
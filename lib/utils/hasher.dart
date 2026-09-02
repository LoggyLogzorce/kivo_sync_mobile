import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class Hasher {
  /// Вычисление fingerprint для аудио (SHA-256 от первого 1 мегабайта)
  static Future<String> computeAudioFingerprint(File file) async {
    final int byteLength = await file.length();
    // 1024 * 1024 = 1 MB (как в JS-клиенте)
    final int chunkSize = byteLength < 1048576 ? byteLength : 1048576; 
    
    final Stream<List<int>> inputStream = file.openRead(0, chunkSize);
    final List<int> bytes = [];
    
    await for (final chunk in inputStream) {
      bytes.addAll(chunk);
    }
    
    return sha256.convert(bytes).toString();
  }

  /// Вычисление fingerprint для LRC файла (SHA-256 первые 16 символов)
  static Future<String> computeLrcFingerprint(File file) async {
    final String text = await file.readAsString(encoding: utf8);
    final List<int> bytes = utf8.encode(text);
    final String fullHash = sha256.convert(bytes).toString();
    
    // Обрезаем до 16 символов, как в JS: .substring(0, 16)
    return fullHash.substring(0, 16); 
  }
}
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoClipService {
  static Future<Directory> _clipsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'alert_clips'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> saveClip({
    required String sourcePath,
    required int sessionId,
  }) async {
    try {
      final src = File(sourcePath);
      final dir = await _clipsDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dest = p.join(dir.path, 'clip_${sessionId}_$ts.mp4');
      await src.copy(dest);
      await src.delete();
      return dest;
    } catch (e) {
      debugPrint('[VideoClip] saveClip error: $e');
      return null;
    }
  }

  static Future<void> deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static Future<String?> exportToDownloads(String filePath) async {
    try {
      final src = File(filePath);
      final fileName = p.basename(filePath);

      // Android public Downloads (API 29+ scoped storage allows this without WRITE_EXTERNAL_STORAGE)
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final dest = p.join(downloadsDir.path, fileName);
        await src.copy(dest);
        return dest;
      }

      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dest = p.join(extDir.path, fileName);
        await src.copy(dest);
        return dest;
      }
      return null;
    } catch (e) {
      debugPrint('[VideoClip] exportToDownloads error: $e');
      return null;
    }
  }

  static Future<bool> clipExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}

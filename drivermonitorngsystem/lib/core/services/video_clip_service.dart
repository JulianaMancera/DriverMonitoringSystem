import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoClipService {
  static Future<Directory> _clipsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'alert_clips'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Moves a camera temp file into permanent app storage.
  /// Returns the saved path, or null if the source file was missing / copy failed.
  static Future<String?> saveClip({
    required String sourcePath,
    required int sessionId,
  }) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
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

  /// Deletes a file silently — used for safe-drive temp cleanup.
  static Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Copies an alert clip to the device Downloads folder.
  /// Returns the destination path on success, null on failure.
  static Future<String?> exportToDownloads(String filePath) async {
    try {
      final src = File(filePath);
      if (!await src.exists()) return null;

      final fileName = p.basename(filePath);

      // Android public Downloads directory (API 29+ scoped storage allows this
      // without WRITE_EXTERNAL_STORAGE on the app's own external files).
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final dest = p.join(downloadsDir.path, fileName);
        await src.copy(dest);
        return dest;
      }

      // Fallback: app-specific external storage (accessible via file manager)
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

  /// Checks whether a saved clip file still exists on disk.
  static Future<bool> clipExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}

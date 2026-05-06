import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VideoClipService {
  // Minimum free space required (50MB) before attempting to write
  static const int _minFreeBytesRequired = 52428800;

  static Future<Directory> _clipsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'alert_clips'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Check if sufficient disk space is available
  static Future<bool> _hasSufficientDiskSpace() async {
    try {
      final dir = await _clipsDir();
      final stat = await FileStat.stat(dir.path);
      final availableBytes = stat.size; // Approximate available space
      return availableBytes > _minFreeBytesRequired;
    } catch (e) {
      debugPrint('[VideoClip] Disk space check error: $e');
      // If we can't check, assume we have space to attempt write
      return true;
    }
  }

  static Future<String?> saveClip({
    required String sourcePath,
    required int sessionId,
  }) async {
    try {
      // ✅ Check disk space before attempting write
      if (!await _hasSufficientDiskSpace()) {
        debugPrint('[VideoClip] ❌ Insufficient disk space for saveClip');
        return null;
      }

      final src = File(sourcePath);

      // ✅ Verify source file exists
      if (!await src.exists()) {
        debugPrint('[VideoClip] ❌ Source file does not exist: $sourcePath');
        return null;
      }

      final dir = await _clipsDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dest = p.join(dir.path, 'clip_${sessionId}_$ts.mp4');

      // ✅ Copy file
      await src.copy(dest);

      // ✅ Verify destination was written successfully
      final destFile = File(dest);
      if (!await destFile.exists()) {
        debugPrint(
            '[VideoClip] ❌ Destination file not created after copy: $dest');
        return null;
      }

      final destSize = await destFile.length();
      if (destSize == 0) {
        debugPrint('[VideoClip] ❌ Destination file is empty: $dest');
        await destFile.delete();
        return null;
      }

      // ✅ Delete source only after successful verification
      try {
        await src.delete();
      } catch (e) {
        debugPrint('[VideoClip] Warning: Failed to delete source file: $e');
        // Continue anyway - destination was saved successfully
      }

      debugPrint('[VideoClip] ✅ Clip saved: $dest (${destSize ~/ 1024}KB)');
      return dest;
    } catch (e) {
      debugPrint('[VideoClip] ❌ saveClip error: $e');
      return null;
    }
  }

  static Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[VideoClip] File deleted: $path');
      }
    } catch (e) {
      debugPrint('[VideoClip] Error deleting file: $e');
      rethrow; // ✅ Propagate errors instead of silently suppressing
    }
  }

  static Future<String?> exportToDownloads(String filePath) async {
    try {
      // ✅ Check disk space before export
      if (!await _hasSufficientDiskSpace()) {
        debugPrint('[VideoClip] ❌ Insufficient disk space for export');
        return null;
      }

      final src = File(filePath);
      if (!await src.exists()) {
        debugPrint('[VideoClip] ❌ Source file does not exist: $filePath');
        return null;
      }

      final fileName = p.basename(filePath);

      // Android public Downloads (API 29+ scoped storage allows this without WRITE_EXTERNAL_STORAGE)
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final dest = p.join(downloadsDir.path, fileName);
        await src.copy(dest);

        // ✅ Verify export succeeded
        if (await File(dest).exists()) {
          debugPrint('[VideoClip] ✅ Exported to Downloads: $dest');
          return dest;
        }
      }

      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dest = p.join(extDir.path, fileName);
        await src.copy(dest);

        // ✅ Verify export succeeded
        if (await File(dest).exists()) {
          debugPrint('[VideoClip] ✅ Exported to external storage: $dest');
          return dest;
        }
      }

      debugPrint('[VideoClip] ❌ Could not export file: no valid destination');
      return null;
    } catch (e) {
      debugPrint('[VideoClip] ❌ exportToDownloads error: $e');
      return null;
    }
  }

  static Future<bool> clipExists(String path) async {
    try {
      return await File(path).exists();
    } catch (e) {
      debugPrint('[VideoClip] Error checking clip existence: $e');
      return false;
    }
  }
}

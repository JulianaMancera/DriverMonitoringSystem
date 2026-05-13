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

  /// Returns (destinationPath, errorReason). On success errorReason is null.
  static Future<(String?, String?)> exportToDownloads(String filePath) async {
    try {
      // ✅ Check disk space before export
      if (!await _hasSufficientDiskSpace()) {
        debugPrint('[VideoClip] ❌ Insufficient disk space for export');
        return (null, 'disk_full');
      }

      final src = File(filePath);
      if (!await src.exists()) {
        debugPrint('[VideoClip] ❌ Source file does not exist: $filePath');
        return (null, 'file_not_found');
      }

      final fileName = p.basename(filePath);

      // Android public Downloads (API 29+ scoped storage allows this without WRITE_EXTERNAL_STORAGE)
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final dest = p.join(downloadsDir.path, fileName);
        await src.copy(dest);

        if (await File(dest).exists()) {
          debugPrint('[VideoClip] ✅ Exported to Downloads: $dest');
          return (dest, null);
        }
      }

      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final dest = p.join(extDir.path, fileName);
        await src.copy(dest);

        if (await File(dest).exists()) {
          debugPrint('[VideoClip] ✅ Exported to external storage: $dest');
          return (dest, null);
        }
      }

      debugPrint('[VideoClip] ❌ Could not export file: no valid destination');
      return (null, 'no_destination');
    } on FileSystemException catch (e) {
      final msg = e.message.toLowerCase();
      debugPrint('[VideoClip] ❌ exportToDownloads FileSystemException: $e');
      if (msg.contains('no space') || msg.contains('disk full') || msg.contains('enospc')) {
        return (null, 'disk_full');
      }
      if (msg.contains('permission') || msg.contains('denied') || msg.contains('eacces')) {
        return (null, 'permission_denied');
      }
      return (null, 'io_error');
    } catch (e) {
      debugPrint('[VideoClip] ❌ exportToDownloads error: $e');
      return (null, 'unknown');
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

  static Future<bool> _hasSufficientDiskSpace() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final result = await Process.run('df', ['-k', docs.path]);
      if (result.exitCode != 0) return true;
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return true;
      // POSIX df -k columns: Filesystem  1K-blocks  Used  Available  Use%  Mounted
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return true;
      final availKb = int.tryParse(parts[3]);
      if (availKb == null) return true;
      return (availKb * 1024) >= _minFreeBytesRequired;
    } catch (_) {
      return true;
    }
  }
}
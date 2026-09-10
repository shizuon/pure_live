import 'dart:convert';
import 'dart:developer' as developer;

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';

/// Shared UI state. Reading recording badges must not start native services,
/// scan the recording directory, or schedule background resource checks.
class RecorderTaskStore extends GetxService {
  final RxList<LiveRecordTask> tasks = <LiveRecordTask>[].obs;
  final Set<String> interruptedTaskIds = <String>{};

  @override
  void onInit() {
    super.onInit();
    final raw = HivePrefUtil.getString(RecorderKeys.recorderTasks);
    if (raw == null || raw.trim().isEmpty) return;

    final restored = <LiveRecordTask>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          try {
            final task = LiveRecordTask.fromJson(Map<String, dynamic>.from(entry));
            if (task.roomId.trim().isEmpty || !Sites.isSupported(task.platform)) continue;
            if (const <RecordStatus>{
              RecordStatus.preparing,
              RecordStatus.running,
              RecordStatus.reconnecting,
              RecordStatus.processing,
            }.contains(task.status)) {
              interruptedTaskIds.add(task.taskId);
            }
            task
              ..status = RecordStatus.stopped
              ..wasStoppedByUser = false;
            if (restored.every((candidate) => candidate.taskId != task.taskId)) restored.add(task);
          } catch (error) {
            developer.log('Skipped malformed recorder task: $error', name: 'RecorderController');
          }
        }
      }
    } catch (error) {
      developer.log('Restore recorder task list failed: $error', name: 'RecorderController');
    }

    restored.sort((left, right) => left.status.order.compareTo(right.status.order));
    tasks.assignAll(restored);
  }
}

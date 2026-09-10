import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/global/initial_services.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/live_play/widgets/button/record_action_button.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/recorder_task_store.dart';
import 'package:remixicon/remixicon.dart';

class _Settings extends RecordSettingsController {
  _Settings({bool resume = false}) : _autoStartOnBoot = resume.obs;
  final RxBool _autoStartOnBoot;
  final RxBool _enableCacheLimit = false.obs;
  @override
  RxBool get autoStartOnBoot => _autoStartOnBoot;
  @override
  RxBool get enableCacheLimit => _enableCacheLimit;
  @override
  // ignore: must_call_super -- The fixture skips real storage initialization.
  void onInit() {} // No filesystem side effects in the resource-policy test.
}

class _Cache extends CacheService {
  int scans = 0;
  Completer<double>? pending;
  @override
  Future<double> getCacheSize() async {
    scans++;
    if (pending != null) return pending!.future;
    return 0;
  }
}

class _Recorder extends RecorderController {
  int starts = 0;
  @override
  // ignore: must_call_super -- UI fixture does not start native services.
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> restoreAndAutoPoll() async {}
  @override
  Future<LiveRecordTask?> addTask({required LiveRoom room, bool startImmediately = true}) async {
    if (startImmediately) starts++;
    final task = LiveRecordTask.fromRoom(room)..status = RecordStatus.running;
    tasks.add(task);
    return task;
  }
}

class _ResumeRecorder extends RecorderController {
  final resumed = <String>[];
  int permissionFailures = 0;
  @override
  Future<bool> requestStoragePermission() async {
    if (permissionFailures-- > 0) throw StateError('temporary permission failure');
    return true;
  }

  @override
  Future<void> refreshTaskStatus(LiveRecordTask task) async => resumed.add(task.taskId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final room = LiveRoom(roomId: '6657', platform: 'douyu', nick: 'B');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pure_live_lazy_recorder_');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('record badges restore and update without creating recorder or storage services', (tester) async {
    final task = LiveRecordTask.fromRoom(room)..status = RecordStatus.running;
    final raw = jsonEncode([
      task.toJson(),
      task.toJson(),
      {'roomId': ''},
    ]);
    await tester.runAsync(() => HivePrefUtil.setString(RecorderKeys.recorderTasks, raw));
    InitialServices.initLazyControllers();
    final store = Get.find<RecorderTaskStore>();
    expect(store.tasks.length, 1);
    expect(store.tasks.single.status, RecordStatus.stopped);
    expect(store.interruptedTaskIds, {task.taskId});
    // Reading a badge does not overwrite crash-recovery evidence on disk.
    expect(HivePrefUtil.getString(RecorderKeys.recorderTasks), raw);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordActionButton(room: room, taskStore: store, onOpenRecordCenter: () async {}),
        ),
      ),
    );
    expect(find.byIcon(Remix.checkbox_circle_fill), findsOneWidget);
    store.tasks.single.status = RecordStatus.running;
    store.tasks[0] = store.tasks.single;
    await tester.pumpAndSettle();
    expect(find.byIcon(Remix.record_circle_fill), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    expect(Get.isPrepared<RecorderController>(), isTrue);
    expect(Get.isPrepared<RecordSettingsController>(), isTrue);
    expect(Get.isPrepared<CacheService>(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('cache monitoring runs only with an enabled limit and a task that can write', () {
    fakeAsync((async) {
      final store = Get.put(RecorderTaskStore());
      final settings = Get.put<RecordSettingsController>(_Settings());
      final cache = Get.put<CacheService>(_Cache()) as _Cache;
      final recorder = Get.put(RecorderController());
      async.flushMicrotasks();
      expect(recorder.tasks, same(store.tasks));
      expect(async.periodicTimerCount, 0);
      async.elapse(const Duration(minutes: 2));
      expect(cache.scans, 0);

      settings.enableCacheLimit.value = true;
      async.flushMicrotasks();
      expect(cache.scans, 1, reason: 'enabling checks existing files once');
      expect(async.periodicTimerCount, 0);
      final task = LiveRecordTask.fromRoom(room)..status = RecordStatus.running;
      store.tasks.add(task);
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 1);
      async.elapse(const Duration(minutes: 1));
      expect(cache.scans, 3);
      task.status = RecordStatus.stopped;
      recorder.updateTask(task, persist: false);
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
      final before = cache.scans;
      async.elapse(const Duration(minutes: 2));
      expect(cache.scans, before);

      task.status = RecordStatus.processing;
      recorder.updateTask(task, persist: false);
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 1);
      settings.enableCacheLimit.value = false;
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
      Get.delete<RecorderController>(force: true);
      async.flushMicrotasks();
    });
  });

  test('automatic continuation reuses restored UI tasks and only restores once', () async {
    final interrupted = LiveRecordTask.fromRoom(room)..status = RecordStatus.running;
    await HivePrefUtil.setString(RecorderKeys.recorderTasks, jsonEncode([interrupted.toJson()]));
    final store = Get.put(RecorderTaskStore());
    final restoredTask = store.tasks.single;
    Get.put<RecordSettingsController>(_Settings(resume: true));
    final recorder = Get.put<RecorderController>(_ResumeRecorder()) as _ResumeRecorder;
    final first = recorder.restoreAndAutoPoll();
    expect(recorder.restoreAndAutoPoll(), same(first));
    await first;
    expect(recorder.tasks.single, same(restoredTask));
    expect(store.interruptedTaskIds, isEmpty);
    expect(recorder.resumed, [interrupted.taskId]);
    await recorder.restoreAndAutoPoll();
    expect(recorder.resumed.length, 1);
    Get.delete<RecorderController>(force: true);
  });

  test('failed automatic restoration can be retried without replacing task state', () async {
    final task = LiveRecordTask.fromRoom(room);
    await HivePrefUtil.setString(RecorderKeys.recorderTasks, jsonEncode([task.toJson()]));
    final store = Get.put(RecorderTaskStore());
    final restoredTask = store.tasks.single;
    Get.put<RecordSettingsController>(_Settings(resume: true));
    final recorder = Get.put<RecorderController>(_ResumeRecorder()..permissionFailures = 1) as _ResumeRecorder;
    await expectLater(recorder.restoreAndAutoPoll(), throwsStateError);
    await recorder.restoreAndAutoPoll();
    expect(recorder.tasks.single, same(restoredTask));
    expect(recorder.resumed, [task.taskId]);
    Get.delete<RecorderController>(force: true);
  });

  test('a resource check requested during a scan is coalesced and shutdown stops further work', () {
    fakeAsync((async) {
      final store = Get.put(RecorderTaskStore());
      final settings = Get.put<RecordSettingsController>(_Settings());
      final cache = Get.put<CacheService>(_Cache()) as _Cache;
      Get.put(RecorderController());
      final firstScan = Completer<double>();
      cache.pending = firstScan;
      settings.enableCacheLimit.value = true;
      async.flushMicrotasks();
      store.tasks.add(LiveRecordTask.fromRoom(room)..status = RecordStatus.running);
      async.flushMicrotasks();
      expect(cache.scans, 1);
      cache.pending = null;
      firstScan.complete(0);
      async.flushMicrotasks();
      expect(cache.scans, 2, reason: 'do not lose a check while the first scan is pending');
      Get.delete<RecorderController>(force: true);
      async.elapse(const Duration(minutes: 2));
      expect(cache.scans, 2);
    });
  });

  testWidgets('opening and cancelling the menu stays cold; start creates the service exactly once', (tester) async {
    var creations = 0;
    final store = Get.put(RecorderTaskStore());
    Get.lazyPut<RecordSettingsController>(_Settings.new);
    Get.lazyPut<RecorderController>(() {
      creations++;
      return _Recorder();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordActionButton(room: room, taskStore: store, onOpenRecordCenter: () async {}),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(creations, 0);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(creations, 0);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(creations, 1);
    expect((Get.find<RecorderController>() as _Recorder).starts, 1);
    expect(store.tasks.single.roomId, room.roomId);
    expect(find.byIcon(Remix.record_circle_fill), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/iptv/local/database.dart' as database;

class DbService extends GetxService {
  late final database.AppDatabase db;
  Future<void>? _closeFuture;

  /// Close Drift's statement cache and background isolate before Dart VM exit.
  Future<void> close() => _closeFuture ??= db.close();

  Future<DbService> init() async {
    db = database.AppDatabase();
    return this;
  }
}

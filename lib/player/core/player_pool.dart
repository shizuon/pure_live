import '../models/player_engine.dart';
import '../models/player_slot.dart';
import '../interface/unified_player_interface.dart';

class PlayerPool {
  final Map<(PlayerEngine, PlayerSlot), UnifiedPlayer> _cache = {};

  final Future<UnifiedPlayer> Function(PlayerEngine) factory;

  PlayerPool({required this.factory});

  Future<UnifiedPlayer> getPlayer(
    PlayerEngine engine, {
    PlayerSlot slot = PlayerSlot.mainVideo,
    bool audioOnly = false,
  }) async {
    final key = (engine, slot);
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    final player = await factory(engine);

    await player.init(audioOnly: audioOnly);

    _cache[key] = player;

    return player;
  }

  Future<void> removeFromCache(PlayerEngine engine, {PlayerSlot slot = PlayerSlot.mainVideo}) async {
    final key = (engine, slot);
    if (_cache.containsKey(key)) {
      final player = _cache[key]!;
      await player.hardDispose(); // 销毁原生
      _cache.remove(key); // 从缓存删除
    }
  }

  UnifiedPlayer? cachedPlayer(PlayerEngine engine, PlayerSlot slot) => _cache[(engine, slot)];

  Future<void> disposeAll() async {
    for (final player in _cache.values) {
      await player.hardDispose();
    }

    _cache.clear();
  }
}

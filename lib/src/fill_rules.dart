import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'fill_engine.dart';

const blokDoldurmaId = 'oyun-blok-doldurma';

class FillRules extends GameRules<FillLevel> {
  /// Üretim + çözücü türü: 100.000 numaralı bölüm (1000 dünya).
  @override
  int get levelCount => 100000;

  @override
  String get gameId => blokDoldurmaId;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [
        GameModeId.campaign,
        GameModeId.daily,
        GameModeId.weekly,
        GameModeId.challenge,
      ];

  @override
  List<GameStat> get gameStats => const [
        GameStat('pieces_placed', 'Yerleştirilen parça', 'Pieces placed', scale: 40),
        GameStat('shapes_completed', 'Tamamlanan şekil', 'Shapes completed', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('pieces', 'pieces_placed', [20, 50, 100]),
        MissionTemplate('shapes', 'shapes_completed', [3, 6, 12]),
      ];

  @override
  FillLevel generate(LevelSpec spec) => generateFillLevel(spec);

  @override
  Validation validate(FillLevel level, LevelSpec spec) {
    final w = level.width, h = level.height;
    if (level.mask.length != w * h) return const Validation.fail('bad mask');
    if (level.pieces.length < 2) return const Validation.fail('too few pieces');
    // The solution must cover the mask exactly once.
    final cover = List<int>.filled(w * h, 0);
    for (var i = 0; i < level.pieces.length; i++) {
      final p = level.pieces[i];
      if (p.size > 8) return const Validation.fail('piece too big');
      final s = level.solution[i];
      for (final c in p.cells) {
        final x = s[0] + c[0], y = s[1] + c[1];
        if (x < 0 || y < 0 || x >= w || y >= h) return const Validation.fail('out of board');
        cover[y * w + x]++;
      }
      if (!_connected(p)) return const Validation.fail('piece not connected');
    }
    for (var k = 0; k < w * h; k++) {
      if (level.mask[k] ? cover[k] != 1 : cover[k] != 0) {
        return const Validation.fail('solution does not tile the shape');
      }
    }
    // Replay the solution through the game rules.
    final g = FillGame(level);
    for (var i = 0; i < level.pieces.length; i++) {
      g.pieces[i] = level.pieces[i];
      if (!g.place(i, level.solution[i][0], level.solution[i][1])) {
        return const Validation.fail('solution not placeable');
      }
    }
    if (!g.won) return const Validation.fail('solution does not win');
    return Validation.ok(level.pieces.length);
  }

  static bool _connected(FillPiece p) {
    final set = {for (final c in p.cells) '${c[0]},${c[1]}'};
    final seen = <String>{set.first};
    final stack = [set.first];
    while (stack.isNotEmpty) {
      final xy = stack.removeLast().split(',').map(int.parse).toList();
      for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        final k = '${xy[0] + d[0]},${xy[1] + d[1]}';
        if (set.contains(k) && seen.add(k)) stack.add(k);
      }
    }
    return seen.length == set.length;
  }

  /// 3 stars without hints and few corrections, 2 with one hint, else 1.
  static int stars({required int pieces, required int moves, required int hints}) {
    if (hints == 0 && moves <= pieces + 2) return 3;
    if (hints <= 1) return 2;
    return 1;
  }
}

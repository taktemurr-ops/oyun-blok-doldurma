import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_blok_doldurma/oyun_blok_doldurma.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = FillRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('500 bölüm üretilir, doğrulanır ve çözümle kazanılır', () {
    for (var n = 1; n <= 500; n++) {
      final g = rules.build(planner.spec(n));
      expect(g.validation.ok, isTrue, reason: 'level $n');
      final l = g.puzzle;
      final game = FillGame(l);
      for (var i = 0; i < l.pieces.length; i++) {
        game.pieces[i] = l.pieces[i];
        expect(game.place(i, l.solution[i][0], l.solution[i][1]), isTrue);
      }
      expect(game.won, isTrue);
    }
  });

  test('aynı tohum aynı bölümü verir', () {
    final a = rules.build(planner.spec(77)).puzzle;
    final b = rules.build(planner.spec(77)).puzzle;
    expect(a.mask, b.mask);
    expect(a.pieces.map((p) => p.key).toList(), b.pieces.map((p) => p.key).toList());
  });

  test('yerleştirme kuralları, geri alma, ipucu ve kayıt', () {
    final l = rules.build(planner.spec(40)).puzzle;
    final g = FillGame(l);
    expect(g.canPlace(0, -1, -1), isFalse);
    // Hints alone solve the level.
    var guard = 0;
    while (!g.won && guard++ < 100) {
      final h = g.hint();
      expect(h, isNotNull);
      expect(g.place(h!.piece, h.x, h.y), isTrue);
    }
    expect(g.won, isTrue);
    final snap = g.serialize();
    final r = FillGame.restore(l, snap);
    expect(r.won, isTrue);
    g.undo();
    expect(g.won, isFalse);
    // Picking up a placed piece returns it to the tray.
    final placedIdx = g.placed.indexWhere((p) => p != null);
    final p = g.placed[placedIdx]!;
    final c = g.pieces[placedIdx].cells.first;
    expect(g.pickUpAt(p[0] + c[0], p[1] + c[1]), placedIdx);
    expect(g.placed[placedIdx], isNull);
  });

  test('döndürme 4 kez yapılınca parça aynı kalır', () {
    final l = rules.build(planner.spec(120)).puzzle;
    final p = l.pieces.first;
    expect(p.rotated().rotated().rotated().rotated().key, p.key);
  });
}

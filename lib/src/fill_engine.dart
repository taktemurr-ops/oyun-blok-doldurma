// Blok Doldurma: verilen şekli (silueti) parçalarla eksiksiz doldur.
// Saf Dart; Flutter'a bağımlı değil, test edilebilir.

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// A polyomino, normalized so that its minimum x and y are 0.
class FillPiece {
  final List<List<int>> cells; // [x, y]
  final int color; // 1..8
  const FillPiece(this.cells, this.color);

  int get width => cells.map((c) => c[0]).reduce((a, b) => a > b ? a : b) + 1;
  int get height => cells.map((c) => c[1]).reduce((a, b) => a > b ? a : b) + 1;
  int get size => cells.length;

  /// Rotated 90° clockwise, normalized.
  FillPiece rotated() => FillPiece(normalize([for (final c in cells) [-c[1], c[0]]]), color);

  static List<List<int>> normalize(List<List<int>> cs) {
    final minX = cs.map((c) => c[0]).reduce((a, b) => a < b ? a : b);
    final minY = cs.map((c) => c[1]).reduce((a, b) => a < b ? a : b);
    final out = [for (final c in cs) [c[0] - minX, c[1] - minY]];
    out.sort((a, b) => a[1] != b[1] ? a[1] - b[1] : a[0] - b[0]);
    return out;
  }

  String get key => cells.map((c) => '${c[0]},${c[1]}').join(';');

  Map<String, Object> toJson() => {'c': color, 'r': cells.expand((e) => e).toList()};

  static FillPiece fromJson(Map<String, Object?> j) {
    final flat = (j['r'] as List).cast<num>().map((e) => e.toInt()).toList();
    return FillPiece([for (var i = 0; i + 1 < flat.length; i += 2) [flat[i], flat[i + 1]]], (j['c'] as num).toInt());
  }
}

class FillLevel {
  final int width;
  final int height;

  /// true = this cell belongs to the shape that must be filled.
  final List<bool> mask;

  /// Pieces in their *solution* orientation.
  final List<FillPiece> pieces;

  /// Top-left position of each piece in the solution.
  final List<List<int>> solution;

  /// Number of clockwise quarter turns each piece is shown with (0 = as solved).
  final List<int> turns;

  final int difficulty;
  final int seed;

  const FillLevel({
    required this.width,
    required this.height,
    required this.mask,
    required this.pieces,
    required this.solution,
    required this.turns,
    required this.difficulty,
    required this.seed,
  });

  int get cellCount => mask.where((m) => m).length;
  bool get rotationNeeded => turns.any((t) => t != 0);
}

class FillGame {
  final FillLevel level;

  /// Current orientation of each piece.
  late List<FillPiece> pieces;

  /// Placement of each piece ([x, y]) or null while in the tray.
  late List<List<int>?> placed;

  /// Piece index occupying each board cell, -1 = empty.
  late List<int> board;

  int moves = 0;
  final List<String> _undo = [];

  FillGame(this.level) {
    pieces = [
      for (var i = 0; i < level.pieces.length; i++) _turn(level.pieces[i], level.turns[i]),
    ];
    placed = List<List<int>?>.filled(level.pieces.length, null);
    board = List<int>.filled(level.width * level.height, -1);
  }

  static FillPiece _turn(FillPiece p, int t) {
    var q = p;
    for (var k = 0; k < t % 4; k++) {
      q = q.rotated();
    }
    return q;
  }

  int idx(int x, int y) => y * level.width + x;

  bool canPlace(int i, int x, int y) {
    if (placed[i] != null) return false;
    for (final c in pieces[i].cells) {
      final cx = x + c[0], cy = y + c[1];
      if (cx < 0 || cy < 0 || cx >= level.width || cy >= level.height) return false;
      final k = idx(cx, cy);
      if (!level.mask[k] || board[k] != -1) return false;
    }
    return true;
  }

  bool place(int i, int x, int y) {
    if (!canPlace(i, x, y)) return false;
    _undo.add(serialize());
    for (final c in pieces[i].cells) {
      board[idx(x + c[0], y + c[1])] = i;
    }
    placed[i] = [x, y];
    moves++;
    return true;
  }

  /// Takes a placed piece back to the tray. Returns its index or -1.
  int pickUpAt(int x, int y) {
    if (x < 0 || y < 0 || x >= level.width || y >= level.height) return -1;
    final i = board[idx(x, y)];
    if (i < 0) return -1;
    _undo.add(serialize());
    for (var k = 0; k < board.length; k++) {
      if (board[k] == i) board[k] = -1;
    }
    placed[i] = null;
    return i;
  }

  void rotate(int i) {
    if (placed[i] != null) return;
    pieces[i] = pieces[i].rotated();
  }

  bool get won => board.asMap().entries.every((e) => !level.mask[e.key] || e.value != -1);

  int get filledCells => board.where((v) => v != -1).length;

  bool get canUndo => _undo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    _restore(_undo.removeLast());
  }

  /// A correct move from the known solution: (piece, x, y, orientation).
  /// Pieces placed in the wrong spot are taken back first.
  ({int piece, int x, int y})? hint() {
    for (var i = 0; i < pieces.length; i++) {
      final p = placed[i];
      final s = level.solution[i];
      if (p != null && (p[0] != s[0] || p[1] != s[1] || pieces[i].key != level.pieces[i].key)) {
        pickUpAt(p[0] + pieces[i].cells.first[0], p[1] + pieces[i].cells.first[1]);
      }
    }
    for (var i = 0; i < pieces.length; i++) {
      if (placed[i] != null) continue;
      final s = level.solution[i];
      // Solution spot must be free (wrongly placed pieces were picked up above).
      final free = level.pieces[i].cells.every((c) => board[idx(s[0] + c[0], s[1] + c[1])] == -1);
      if (!free) continue;
      pieces[i] = level.pieces[i];
      return (piece: i, x: s[0], y: s[1]);
    }
    return null;
  }

  String serialize() => [
        moves,
        for (var i = 0; i < pieces.length; i++)
          '${pieces[i].key}|${placed[i] == null ? '' : '${placed[i]![0]},${placed[i]![1]}'}',
      ].join('#');

  void _restore(String s) {
    final parts = s.split('#');
    moves = int.parse(parts[0]);
    board = List<int>.filled(level.width * level.height, -1);
    for (var i = 0; i < pieces.length; i++) {
      final kv = parts[i + 1].split('|');
      final cells = [
        for (final c in kv[0].split(';')) [int.parse(c.split(',')[0]), int.parse(c.split(',')[1])]
      ];
      pieces[i] = FillPiece(cells, level.pieces[i].color);
      if (kv[1].isEmpty) {
        placed[i] = null;
      } else {
        final xy = kv[1].split(',').map(int.parse).toList();
        placed[i] = xy;
        for (final c in cells) {
          board[idx(xy[0] + c[0], xy[1] + c[1])] = i;
        }
      }
    }
  }

  static FillGame restore(FillLevel level, String snap) {
    final g = FillGame(level);
    try {
      g._restore(snap);
    } catch (_) {
      return FillGame(level); // corrupt snapshot: start fresh
    }
    return g;
  }
}

/// Deterministic level generator. The shape is carved by cutting a random
/// blob into polyominoes, so every level is solvable by construction.
FillLevel generateFillLevel(LevelSpec spec) {
  final r = SeededRandom(spec.seed);
  final d = spec.difficulty.clamp(1, 10);
  final side = (4 + (d + 1) ~/ 2).clamp(4, 9); // 5x5 .. 9x9
  final w = side, h = side;
  final target = (w * h * (0.50 + 0.035 * d)).round();
  final maxPiece = (3 + d ~/ 3).clamp(3, 6);

  // 1) Grow a connected blob from the centre.
  final mask = List<bool>.filled(w * h, false);
  final start = (h ~/ 2) * w + w ~/ 2;
  mask[start] = true;
  var count = 1;
  final frontier = <int>[];
  void addNeighbours(int i) {
    final x = i % w, y = i ~/ w;
    if (x > 0) frontier.add(i - 1);
    if (x < w - 1) frontier.add(i + 1);
    if (y > 0) frontier.add(i - w);
    if (y < h - 1) frontier.add(i + w);
  }

  addNeighbours(start);
  while (count < target && frontier.isNotEmpty) {
    final k = frontier.removeAt(r.nextInt(frontier.length));
    if (mask[k]) continue;
    mask[k] = true;
    count++;
    addNeighbours(k);
  }

  // 2) Cut the blob into pieces.
  final owner = List<int>.filled(w * h, -1);
  final regions = <List<int>>[];
  List<int> nb(int i) {
    final x = i % w, y = i ~/ w;
    return [
      if (x > 0) i - 1,
      if (x < w - 1) i + 1,
      if (y > 0) i - w,
      if (y < h - 1) i + w,
    ];
  }

  final order = [for (var i = 0; i < w * h; i++) if (mask[i]) i];
  r.shuffle(order);
  for (final s in order) {
    if (owner[s] != -1) continue;
    final id = regions.length;
    final want = r.range(2, maxPiece);
    final reg = <int>[s];
    owner[s] = id;
    while (reg.length < want) {
      final cand = <int>[
        for (final c in reg)
          for (final n in nb(c))
            if (mask[n] && owner[n] == -1) n
      ];
      if (cand.isEmpty) break;
      final n = cand[r.nextInt(cand.length)];
      owner[n] = id;
      reg.add(n);
    }
    regions.add(reg);
  }
  // Merge single cells into a neighbouring piece.
  for (var id = 0; id < regions.length; id++) {
    if (regions[id].length != 1) continue;
    final c = regions[id].first;
    final n = nb(c).firstWhere((n) => mask[n] && owner[n] != id, orElse: () => -1);
    if (n == -1) continue;
    final to = owner[n];
    owner[c] = to;
    regions[to].add(c);
    regions[id] = [];
  }
  final live = regions.where((g) => g.isNotEmpty).toList();

  // 3) Build pieces + solution positions.
  final pieces = <FillPiece>[];
  final solution = <List<int>>[];
  final turns = <int>[];
  for (var k = 0; k < live.length; k++) {
    final cells = [for (final i in live[k]) [i % w, i ~/ w]];
    final minX = cells.map((c) => c[0]).reduce((a, b) => a < b ? a : b);
    final minY = cells.map((c) => c[1]).reduce((a, b) => a < b ? a : b);
    pieces.add(FillPiece(FillPiece.normalize(cells), 1 + k % 8));
    solution.add([minX, minY]);
    turns.add(d >= 5 ? r.nextInt(4) : 0);
  }
  // Shuffle tray order (keep piece/solution/turn triples together).
  final perm = [for (var i = 0; i < pieces.length; i++) i];
  r.shuffle(perm);
  return FillLevel(
    width: w,
    height: h,
    mask: mask,
    pieces: [for (final i in perm) pieces[i]],
    solution: [for (final i in perm) solution[i]],
    turns: [for (final i in perm) turns[i]],
    difficulty: d,
    seed: spec.seed,
  );
}

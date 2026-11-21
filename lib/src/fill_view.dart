import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';

import 'fill_engine.dart';
import 'fill_rules.dart';

class FillView extends StatefulWidget {
  final PlayContext ctx;
  const FillView({super.key, required this.ctx});

  @override
  State<FillView> createState() => _FillViewState();
}

class _FillViewState extends State<FillView> {
  late FillLevel level;
  late FillGame game;
  final GlobalKey _boardKey = GlobalKey();
  int? _selected;
  int? _hoverTray, _hoverX, _hoverY;
  ({int piece, int x, int y})? _hint;
  int _seconds = 0;
  int _hints = 0;
  int _undos = 0;
  Timer? _timer;
  bool _ended = false;

  PlayContext get ctx => widget.ctx;
  bool get _tr => ctx.lang == 'tr';

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<FillLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? FillGame.restore(level, snap) : FillGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  // ---- Actions ---------------------------------------------------------------
  void _place(int i, int x, int y) {
    if (!game.place(i, x, y)) {
      ctx.sfx(Sfx.error);
      return;
    }
    ctx.sfx(Sfx.place);
    setState(() {
      _selected = null;
      _hint = null;
    });
    _persist();
    if (game.won) _win();
  }

  void _win() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.sfx(Sfx.win);
    final pieces = level.pieces.length;
    final stars = FillRules.stars(pieces: pieces, moves: game.moves, hints: _hints);
    ctx.finish(RoundResult(
      won: true,
      score: (level.cellCount * 10 + stars * 50 - _hints * 20).clamp(10, 1 << 20),
      stars: stars,
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'pieces_placed': pieces, 'shapes_completed': 1},
    ));
  }

  Future<void> _useHint() async {
    if (!await ctx.requestHint()) return;
    _hints++;
    setState(() => _hint = game.hint());
    _persist();
  }

  void _undo() {
    if (!game.canUndo) return;
    setState(() {
      game.undo();
      _undos++;
      _hint = null;
    });
    _persist();
  }

  void _reset() {
    setState(() {
      for (var i = 0; i < game.pieces.length; i++) {
        final p = game.placed[i];
        if (p != null) game.pickUpAt(p[0] + game.pieces[i].cells.first[0], p[1] + game.pieces[i].cells.first[1]);
      }
      _hint = null;
      _selected = null;
    });
    _persist();
  }

  // ---- Input mapping ---------------------------------------------------------
  (int, int)? _cellAt(Offset global, {bool round = false}) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    final c = box.size.width / level.width;
    if (round) return ((local.dx / c).round(), (local.dy / c).round());
    final x = (local.dx / c).floor(), y = (local.dy / c).floor();
    if (x < 0 || y < 0 || x >= level.width || y >= level.height) return null;
    return (x, y);
  }

  void _onBoardTap(TapUpDetails d) {
    final cell = _cellAt(d.globalPosition);
    if (cell == null) return;
    final sel = _selected;
    if (sel != null && game.placed[sel] == null) {
      _place(sel, cell.$1, cell.$2);
      return;
    }
    // Tap on a placed piece takes it back to the tray.
    if (game.pickUpAt(cell.$1, cell.$2) >= 0) {
      ctx.sfx(Sfx.tap);
      setState(() => _hint = null);
      _persist();
    }
  }

  Offset _feedbackShift(FillPiece p, double cell) => Offset(-p.width * cell / 2, -p.height * cell - 48);

  // ---- Build -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final boardW = (cons.maxWidth - 24).clamp(200.0, (cons.maxHeight * 0.55).clamp(200.0, 640.0));
      final cell = boardW / level.width;
      // Whole play area is the drop target (piece is drawn above the finger).
      return DragTarget<int>(
        onMove: (d) {
          final p = game.pieces[d.data];
          final c = _cellAt(d.offset + _feedbackShift(p, cell), round: true);
          setState(() {
            _hoverTray = d.data;
            _hoverX = c?.$1;
            _hoverY = c?.$2;
          });
        },
        onLeave: (_) => setState(() => _hoverTray = null),
        onAcceptWithDetails: (d) {
          final x = _hoverX, y = _hoverY;
          setState(() => _hoverTray = null);
          if (x != null && y != null) _place(d.data, x, y);
        },
        builder: (context, _, __) => Column(children: [
          _hud(),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTapUp: _onBoardTap,
              child: Semantics(
                label: 'board',
                child: SizedBox(
                  key: _boardKey,
                  width: boardW,
                  height: cell * level.height,
                  child: CustomPaint(
                    painter: _BoardPainter(
                      game: game,
                      colors: ctx.pieceColors,
                      colorBlind: ctx.colorBlind,
                      symbol: ctx.symbol,
                      preview: _preview(),
                      previewOk: _previewOk(),
                      hint: _hint,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _tray(cell)),
          _buttons(),
        ]),
      );
    });
  }

  Set<int> _preview() {
    final t = _hoverTray, x = _hoverX, y = _hoverY;
    if (t == null || x == null || y == null) return {};
    return {
      for (final c in game.pieces[t].cells)
        if (x + c[0] >= 0 && y + c[1] >= 0 && x + c[0] < level.width && y + c[1] < level.height)
          game.idx(x + c[0], y + c[1])
    };
  }

  bool _previewOk() {
    final t = _hoverTray, x = _hoverX, y = _hoverY;
    return t != null && x != null && y != null && game.canPlace(t, x, y);
  }

  Widget _hud() {
    final total = level.cellCount;
    final done = game.filledCells;
    String two(int v) => v.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tr ? 'Şekli doldur: $done / $total' : 'Fill the shape: $done / $total',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: total == 0 ? 0 : done / total),
          ]),
        ),
        const SizedBox(width: 12),
        Icon(Icons.timer_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        Text(' ${_seconds ~/ 60}:${two(_seconds % 60)}'),
      ]),
    );
  }

  Widget _tray(double boardCell) {
    final free = [for (var i = 0; i < game.pieces.length; i++) if (game.placed[i] == null) i];
    final trayCell = (boardCell * 0.6).clamp(12.0, 30.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 14,
        children: [for (final i in free) _trayPiece(i, trayCell, boardCell)],
      ),
    );
  }

  Widget _trayPiece(int i, double cell, double boardCell) {
    final p = game.pieces[i];
    final piece = _PieceWidget(
      piece: p,
      cell: cell,
      colors: ctx.pieceColors,
      colorBlind: ctx.colorBlind,
      symbol: ctx.symbol,
      selected: _selected == i,
      hinted: _hint?.piece == i,
    );
    return Semantics(
      button: true,
      label: 'piece ${p.size}',
      child: GestureDetector(
        // Tap selects; a second tap on the selected piece rotates it.
        onTap: () => setState(() {
          if (_selected == i) {
            game.rotate(i);
            _persist();
          } else {
            _selected = i;
          }
        }),
        onLongPress: () => setState(() {
          game.rotate(i);
          _persist();
        }),
        child: Draggable<int>(
          data: i,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Transform.translate(
            offset: _feedbackShift(p, boardCell),
            child: _PieceWidget(
              piece: p,
              cell: boardCell,
              colors: ctx.pieceColors,
              colorBlind: ctx.colorBlind,
              symbol: ctx.symbol,
              selected: false,
              hinted: false,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: piece),
          child: piece,
        ),
      ),
    );
  }

  Widget _buttons() {
    Widget b(IconData icon, String tip, VoidCallback? on) =>
        IconButton.filledTonal(onPressed: on, icon: Icon(icon), tooltip: tip);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        b(Icons.lightbulb, ctx.t('hint'), _useHint),
        b(Icons.undo, ctx.t('undo'), game.canUndo ? _undo : null),
        b(Icons.rotate_right, _tr ? 'Döndür' : 'Rotate',
            _selected == null ? null : () => setState(() => game.rotate(_selected!))),
        b(Icons.restart_alt, _tr ? 'Hepsini geri al' : 'Take all back', game.filledCells == 0 ? null : _reset),
      ]),
    );
  }
}

class _PieceWidget extends StatelessWidget {
  final FillPiece piece;
  final double cell;
  final List<Color> colors;
  final bool colorBlind;
  final String Function(int) symbol;
  final bool selected;
  final bool hinted;

  const _PieceWidget({
    required this.piece,
    required this.cell,
    required this.colors,
    required this.colorBlind,
    required this.symbol,
    required this.selected,
    required this.hinted,
  });

  @override
  Widget build(BuildContext context) {
    final color = colors[(piece.color - 1) % colors.length];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hinted ? Colors.amber : (selected ? Theme.of(context).colorScheme.primary : Colors.transparent),
          width: 2,
        ),
      ),
      child: SizedBox(
        width: piece.width * cell,
        height: piece.height * cell,
        child: Stack(children: [
          for (final c in piece.cells)
            Positioned(
              left: c[0] * cell,
              top: c[1] * cell,
              child: Container(
                width: cell - 2,
                height: cell - 2,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(cell * 0.18)),
                child: colorBlind
                    ? Text(symbol(piece.color), style: TextStyle(fontSize: cell * 0.5, color: Colors.white))
                    : null,
              ),
            ),
        ]),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final FillGame game;
  final List<Color> colors;
  final bool colorBlind;
  final String Function(int) symbol;
  final Set<int> preview;
  final bool previewOk;
  final ({int piece, int x, int y})? hint;

  _BoardPainter({
    required this.game,
    required this.colors,
    required this.colorBlind,
    required this.symbol,
    required this.preview,
    required this.previewOk,
    required this.hint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final l = game.level;
    final c = size.width / l.width;
    final slot = Paint()..color = Colors.white.withValues(alpha: 0.14);
    final slotEdge = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final hintCells = <int>{};
    final h = hint;
    if (h != null) {
      for (final e in game.level.pieces[h.piece].cells) {
        hintCells.add(game.idx(h.x + e[0], h.y + e[1]));
      }
    }
    for (var y = 0; y < l.height; y++) {
      for (var x = 0; x < l.width; x++) {
        final i = game.idx(x, y);
        if (!l.mask[i]) continue;
        final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(x * c + 1, y * c + 1, c - 2, c - 2), Radius.circular(c * 0.18));
        final owner = game.board[i];
        if (owner >= 0) {
          final colorId = game.pieces[owner].color;
          canvas.drawRRect(r, Paint()..color = colors[(colorId - 1) % colors.length]);
          if (colorBlind) _text(canvas, symbol(colorId), r.outerRect.center, c * 0.45);
        } else {
          canvas.drawRRect(r, slot);
          canvas.drawRRect(r, slotEdge);
        }
        if (preview.contains(i)) {
          canvas.drawRRect(
              r,
              Paint()
                ..color = (previewOk ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.55));
        }
        if (hintCells.contains(i)) {
          canvas.drawRRect(
              r,
              Paint()
                ..color = Colors.amber
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
        }
      }
    }
  }

  void _text(Canvas canvas, String s, Offset center, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: Colors.white, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

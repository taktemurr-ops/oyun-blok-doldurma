/// Blok Doldurma: verilen şekli parçalarla eksiksiz doldur.
/// Blok Oyunları merkez uygulamasının oyunu.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';

import 'src/fill_rules.dart';
import 'src/fill_view.dart';

export 'src/fill_engine.dart';
export 'src/fill_rules.dart';
export 'src/fill_view.dart';

final blokDoldurmaConfig = GameConfig(
  gameId: blokDoldurmaId,
  title: const ['Blok Doldurma', 'Block Fill', 'Block-Füller', 'Rellena Bloques', 'Remplis les Blocs'],
  tagline: const [
    'Şekli parçalarla eksiksiz doldur!',
    'Fill the shape with every piece!',
    'Fülle die Form mit allen Teilen!',
    '¡Rellena la forma con todas las piezas!',
    'Remplissez la forme avec toutes les pièces !',
  ],
  seedColor: const Color(0xFF8E24AA),
  icon: Icons.extension_rounded,
  rules: FillRules(),
  buildPlay: (ctx) => FillView(ctx: ctx),
  tutorial: const [
    TutorialStep(Icons.pan_tool_alt, [
      'Parçaları tahtadaki şeklin içine sürükle. Boş yer kalmadan doldur.',
      'Drag the pieces into the shape on the board. Leave no gap.',
      'Ziehe die Teile in die Form. Lass keine Lücke.',
      'Arrastra las piezas dentro de la forma sin dejar huecos.',
      'Glissez les pièces dans la forme sans laisser de trou.',
    ]),
    TutorialStep(Icons.rotate_right, [
      'Seçili parçaya tekrar dokun ya da uzun bas: parça döner.',
      'Tap the selected piece again or long-press it to rotate.',
      'Ausgewähltes Teil erneut antippen oder lange drücken: es dreht sich.',
      'Toca de nuevo la pieza o mantenla pulsada para girarla.',
      'Touchez à nouveau la pièce ou appui long pour la tourner.',
    ]),
    TutorialStep(Icons.touch_app, [
      'Yanlış yere koyduğun parçaya dokun, geri gelir.',
      'Tap a placed piece to take it back.',
      'Tippe ein gelegtes Teil an, um es zurückzunehmen.',
      'Toca una pieza colocada para devolverla.',
      'Touchez une pièce posée pour la reprendre.',
    ]),
  ],
);

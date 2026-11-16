import 'dart:io';

import 'package:flutter/services.dart';

/// Carga Inter (la fuente de la app) desde los assets, para las pruebas que
/// miden texto: sin ella todo sale en Ahem, con cada letra tan ancha como
/// alta. Se ejecuta desde `app/`.
Future<void> loadInter() async {
  final inter = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/inter/Inter-$weight.ttf')
        .readAsBytesSync();
    inter.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await inter.load();
}

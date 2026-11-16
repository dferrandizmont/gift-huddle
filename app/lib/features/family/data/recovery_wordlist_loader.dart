import 'package:flutter/services.dart';

import '../../../core/sync/recovery.dart';

/// Carga la lista de palabras del código de recuperación desde los assets y
/// comprueba que es la de BIP-39 (ADR 0004). La fase 2 la usa en Ajustes.
Future<RecoveryWordlist> loadRecoveryWordlist([AssetBundle? bundle]) async =>
    RecoveryWordlist.parse(
      await (bundle ?? rootBundle).loadString(kRecoveryWordlistAsset),
    );

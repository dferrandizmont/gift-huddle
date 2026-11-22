import 'package:flutter/material.dart';

import '../../../core/motion/rolling_number.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/platform/gifts_secure_scope.dart';
import '../../../core/theme/theme.dart';
import '../invites/invite_crypto.dart';

/// El código de verificación de 6 cifras, grande y legible («123 456»), en la
/// tarjeta suave del tema.
///
/// Al aparecer, las cifras ruedan desde vacío de izquierda a derecha y por
/// grupos («123» y, 60 ms después, «456»): la hoja de emparejar acaba de
/// llegar y el número «se escribe». Con [confirmed] (la persona ya ha dicho
/// «coinciden»), junto al título se dibuja un visto. Con «Reducir movimiento»
/// las cifras se cruzan con un fundido y el visto aparece con otro.
class VerificationCodeCard extends StatelessWidget {
  /// Crea la tarjeta con [label] encima y el [code] sin formato.
  const VerificationCodeCard({
    super.key,
    required this.label,
    required this.code,
    this.confirmed = false,
  });

  /// Texto sobre el código («Código de verificación»).
  final String label;

  /// Las 6 cifras, sin espacio.
  final String code;

  /// Si este móvil ya ha confirmado que los dos números coinciden.
  final bool confirmed;

  /// Lo que tarda en empezar a rodar el primer grupo: la hoja ya está arriba.
  static const Duration _rollDelay = Duration(milliseconds: 60);

  /// El hueco del visto, a cada lado del título: así el título no se mueve
  /// cuando el visto aparece y sigue centrado.
  static const double _slot = 24;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final shown = InviteCrypto.formatCode(code);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: t.soft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // El visto se dibuja en su hueco (con un fundido de 150 ms al
              // aparecer); el hueco existe siempre, también sin él.
              SizedBox(
                width: _slot,
                child: ValueSwitcher(
                  alignment: Alignment.centerLeft,
                  dy: 3,
                  child: confirmed
                      ? Align(
                          key: const ValueKey<bool>(true),
                          alignment: Alignment.centerLeft,
                          child: DrawnCheck(
                            color: t.ink,
                            size: 18,
                            delay: const Duration(milliseconds: 60),
                          ),
                        )
                      : const SizedBox(key: ValueKey<bool>(false)),
                ),
              ),
              Flexible(
                child: Text(
                  label,
                  style: t.styles.meta.copyWith(color: t.textOnSoft),
                ),
              ),
              const SizedBox(width: _slot),
            ],
          ),
          const SizedBox(height: 4),
          // Con la letra muy grande el número se encoge en vez de desbordar.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RollingNumber.text(
              text: shown,
              rollFromEmpty: true,
              leftToRight: true,
              delay: _rollDelay,
              style: t.styles.countdownNumber(CountdownSize.compact, t.ink),
            ),
          ),
        ],
      ),
    );
    // En la versión de tienda no se captura el código de emparejar (1.0.6,
    // QA m7).
    return GiftsSecureScope(
      child: Semantics(
        container: true,
        label: '$label ${code.split('').join(' ')}',
        excludeSemantics: true,
        child: card,
      ),
    );
  }
}

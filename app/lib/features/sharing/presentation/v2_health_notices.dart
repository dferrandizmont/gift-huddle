import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/family_devices.dart' show FamilyDeviceRow;
import '../../sync/application/v2_health_provider.dart';
import '../../sync/application/sync_v2_engine.dart' show UnbackedRevocation;
import '../../sync/application/v2_resolution_actions.dart';
import 'device_sheets.dart' show deviceTitle;

// Avisos persistentes de Móviles de la familia que salen del estado v2 (fase 3,
// lote 3b): otro móvil quitó este, sorpresas en pausa y renovación sugerida
// (arriba), y las filas por resolver: accesos sin respaldo y bajas a medias.
// No son fallos de conexión: reintentar no los arregla, y cada uno explica qué
// hacer y lleva a ello.

const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
  borderRadius: RegalosShape.button,
);

/// Une los nombres con comas y «y» antes del último.
String _joinNames(AppLocalizations l10n, List<String> names) {
  if (names.length < 2) return names.join();
  return l10n.healthNamesAnd(
    names.sublist(0, names.length - 1).join(', '),
    names.last,
  );
}

/// Los avisos de arriba: [onReconnect] lleva a conectar este móvil otra vez y
/// [onReview] abre «Revisar móviles». [people] son los nombres por id.
///
/// Si otro móvil quitó este solo sale ese aviso: lo congelado es consecuencia
/// suya. Entran y salen con un muelle suave (fundido con «Reducir
/// movimiento»).
class V2HealthNotices extends StatelessWidget {
  /// Crea los avisos.
  const V2HealthNotices({
    super.key,
    required this.health,
    required this.people,
    required this.onReconnect,
    required this.onReview,
  });

  /// Lo observado del servicio.
  final V2Health health;

  /// Nombres por id de persona.
  final Map<String, String> people;

  /// «Conectar otra vez».
  final VoidCallback onReconnect;

  /// «Revisar móviles».
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final names = [
      for (final id in health.frozenPeople)
        if ((people[id] ?? '').isNotEmpty) people[id]!,
    ]..sort();
    Widget gap(Widget child) =>
        Padding(padding: const EdgeInsets.only(top: 12), child: child);
    return AnimatedRows(
      rows: [
        if (health.revokedByOthers)
          AnimatedRowItem(
            id: 'revoked',
            child: gap(
              _NoticeCard(
                icon: SettingsIcons.shield,
                title: l10n.healthRevokedTitle,
                body: l10n.healthRevokedBody,
                actionLabel: l10n.healthRevokedAction,
                onAction: onReconnect,
              ),
            ),
          )
        else if (health.frozenPeople.isNotEmpty)
          AnimatedRowItem(
            id: 'frozen',
            child: gap(
              _NoticeCard(
                icon: SettingsIcons.lock,
                title: names.isEmpty
                    ? l10n.healthFrozenTitleGeneric
                    : l10n.healthFrozenTitle(_joinNames(l10n, names)),
                body: l10n.healthFrozenBody,
                actionLabel: l10n.deviceReviewOpen,
                onAction: onReview,
              ),
            ),
          ),
        if (health.renewSuggested)
          AnimatedRowItem(
            id: 'renew',
            child: gap(_QuietNote(text: l10n.healthRenewSoon)),
          ),
      ],
    );
  }
}

/// Un aviso con su explicación y una sola acción.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final StrokeIconBuilder icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconChip(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: t.styles.metaStrong.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(body, style: t.styles.meta),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                minimumSize: const Size(44, 48),
                side: BorderSide(color: t.controlBorder),
                shape: _buttonShape,
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon});

  final StrokeIconBuilder icon;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.chip,
        ),
        child: StrokeIcon(
          icon,
          size: 20,
          color: t.textOnSoft,
          strokeWidth: 1.9,
        ),
      ),
    );
  }
}

/// Una nota discreta, sin botón.
class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            ExcludeSemantics(
              child: StrokeIcon(
                SettingsIcons.refresh,
                size: 16,
                color: t.textSecondary,
                strokeWidth: 1.9,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: t.styles.meta)),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------- filas por resolver

enum _Kind { unbacked, departed }

enum _State { idle, busy, done, notNeeded, error }

/// Retira un acceso sin respaldo. Es el único sitio que llama a
/// `revokeUnbackedCredential`, que dice qué ha pasado de verdad: solo
/// [UnbackedRevocation.revoked] cortó el acceso; el resto es que ya no hacía
/// falta. Un error se propaga: nunca se convierte en éxito.
Future<UnbackedRevocation> _revokeUnbacked(
  WidgetRef ref,
  String credentialId,
) => ref
    .read(v2ResolutionActionsProvider)
    .revokeUnbackedCredential(credentialId);

/// Completa la baja de [deviceId]. Es el único sitio que llama a
/// `completeDeparture`: [selfWaitAccepted] dice que el usuario ha aceptado
/// el aviso N7 de la vista previa, y se revalida bajo el cerrojo.
Future<void> _completeDeparture(
  WidgetRef ref,
  String deviceId, {
  required bool selfWaitAccepted,
}) => ref
    .read(v2ResolutionActionsProvider)
    .completeDeparture(deviceId, selfWaitAccepted: selfWaitAccepted);

/// Las filas «Acceso sin respaldo» y «Baja a medias», con su cabecera. Cada
/// una carga, celebra con un visto que se dibuja o enseña el error con
/// «Reintentar». Al resolverse se queda un instante a la vista y se pliega.
class V2ResolutionSection extends ConsumerStatefulWidget {
  /// Crea la sección.
  const V2ResolutionSection({
    super.key,
    required this.health,
    required this.devices,
    required this.people,
    required this.selfName,
  });

  /// Lo observado del servicio.
  final V2Health health;

  /// Los móviles activos del registro, para poner nombre a una baja.
  final List<FamilyDeviceRow>? devices;

  /// Nombres por id de persona.
  final Map<String, String> people;

  /// Nombre de este móvil.
  final String selfName;

  @override
  ConsumerState<V2ResolutionSection> createState() =>
      _V2ResolutionSectionState();
}

class _V2ResolutionSectionState extends ConsumerState<V2ResolutionSection> {
  /// Cuánto se queda a la vista una fila ya resuelta.
  static const Duration _linger = Duration(milliseconds: 1600);

  // Filas resueltas que aún se enseñan, y las que ya se plegaron aunque el
  // estado guardado tarde en dejar de listarlas.
  final Map<String, Timer> _lingering = {};
  final Set<String> _hidden = {};

  // Filas en curso (o con error por reintentar): siguen aunque `health` ya
  // no las liste, porque la propia operación cambia lo observado.
  final Set<String> _pinned = {};

  // Lo que se enseñó de cada fila la última vez que se listó, para seguir
  // pintándola cuando `health` la quita antes de que acabe su resultado.
  final Map<String, (_Kind, String)> _kinds = {};
  final Map<String, String> _titles = {};
  final Map<String, String?> _refs = {};

  @override
  void dispose() {
    for (final timer in _lingering.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _pin(String key, {required bool pinned}) {
    if (pinned) {
      _pinned.add(key);
    } else if (_pinned.contains(key)) {
      // Al cancelar, si `health` ya no la lista, la fila debe irse: se
      // reconstruye la sección en vez de esperar a otra lectura.
      if (mounted) {
        setState(() => _pinned.remove(key));
      } else {
        _pinned.remove(key);
      }
    }
  }

  void _resolved(String key) {
    _pinned.remove(key);
    _lingering[key]?.cancel();
    _lingering[key] = Timer(_linger, () {
      if (!mounted) return;
      setState(() {
        _lingering.remove(key);
        _hidden.add(key);
      });
    });
    // Lo observado cambia: se vuelve a leer.
    ref.invalidate(v2HealthProvider);
  }

  String _nameOf(AppLocalizations l10n, String deviceId) {
    for (final row in widget.devices ?? const <FamilyDeviceRow>[]) {
      if (row.deviceId == deviceId) {
        return deviceTitle(
          l10n,
          row,
          people: widget.people,
          selfName: widget.selfName,
        );
      }
    }
    return l10n.devicesOtherPhone;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final health = widget.health;
    final listed = <String, (_Kind, String)>{
      for (final id in health.unbackedCredentials)
        'unbacked:$id': (_Kind.unbacked, id),
      for (final id in health.departedDevices)
        'departed:$id': (_Kind.departed, id),
    };
    // Lo que ya no se lista y no se ha plegado se puede volver a pedir.
    _hidden.removeWhere((key) => !listed.containsKey(key));
    for (final e in listed.entries) {
      _kinds[e.key] = e.value;
      _titles[e.key] = e.value.$1 == _Kind.unbacked
          ? l10n.healthUnbackedTitle
          : l10n.healthDepartedTitle(_nameOf(l10n, e.value.$2));
      _refs[e.key] = e.value.$1 == _Kind.unbacked
          ? l10n.healthUnbackedRef(_shortRef(e.value.$2))
          : null;
    }
    // Se enseña lo listado y, aunque `health` ya no lo liste, lo que está en
    // curso o acaba de resolverse hasta que venza su tiempo.
    final keys = <String>{
      for (final key in listed.keys)
        if (!_hidden.contains(key)) key,
      for (final key in [..._pinned, ..._lingering.keys])
        if (_kinds.containsKey(key)) key,
    };
    _kinds.removeWhere(
      (key, _) => !keys.contains(key) && !listed.containsKey(key),
    );
    final ordered = keys.toList()
      ..sort((x, y) {
        final kx = _kinds[x]!.$1.index, ky = _kinds[y]!.$1.index;
        return kx != ky
            ? kx.compareTo(ky)
            : _kinds[x]!.$2.compareTo(_kinds[y]!.$2);
      });
    final entries = {for (final key in ordered) key: _kinds[key]!};
    final t = RegalosTokens.of(context);
    return AnimatedRows(
      rows: [
        if (entries.isNotEmpty)
          AnimatedRowItem(
            id: 'header',
            child: SectionHeader(
              title: l10n.healthResolveSection,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            ),
          ),
        for (final e in entries.entries)
          AnimatedRowItem(
            id: e.key,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _ResolveCard(
                kind: e.value.$1,
                id: e.value.$2,
                title: _titles[e.key]!,
                reference: _refs[e.key],
                color: t.surface,
                onPin: ({required pinned}) => _pin(e.key, pinned: pinned),
                onResolved: () => _resolved(e.key),
              ),
            ),
          ),
      ],
    );
  }
}

/// Las primeras letras del id de un acceso, para distinguir uno de otro.
String _shortRef(String id) => id.length <= 8 ? id : id.substring(0, 8);

class _ResolveCard extends ConsumerStatefulWidget {
  const _ResolveCard({
    required this.kind,
    required this.id,
    required this.title,
    required this.reference,
    required this.color,
    required this.onPin,
    required this.onResolved,
  });

  final _Kind kind;
  final String id;
  final String title;
  final String? reference;
  final Color color;
  final void Function({required bool pinned}) onPin;
  final VoidCallback onResolved;

  @override
  ConsumerState<_ResolveCard> createState() => _ResolveCardState();
}

class _ResolveCardState extends ConsumerState<_ResolveCard> {
  _State _state = _State.idle;

  // Ya se confirmó retirar el acceso: «Reintentar» no vuelve a preguntar.
  bool _confirmed = false;

  void _set(_State state) {
    if (mounted) setState(() => _state = state);
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    final haptics = ref.read(hapticsProvider);
    final unbacked = widget.kind == _Kind.unbacked;
    // Mientras dura, la fila sigue aunque `health` deje de listarla.
    widget.onPin(pinned: true);
    // Retirar un acceso corta algo de verdad: se confirma antes.
    if (unbacked && !_confirmed) {
      haptics.warning();
      final sure = await showRegalosConfirm(
        context,
        title: l10n.healthUnbackedConfirmTitle,
        body: l10n.healthUnbackedConfirmBody,
        confirmLabel: l10n.healthUnbackedAction,
        cancelLabel: l10n.actionCancel,
      );
      if (!sure || !mounted) {
        if (mounted) widget.onPin(pinned: false);
        return;
      }
      _confirmed = true;
    }
    _set(_State.busy);
    try {
      if (unbacked) {
        final result = await _revokeUnbacked(ref, widget.id);
        if (!mounted) return;
        if (result == UnbackedRevocation.revoked) {
          haptics.success();
          _set(_State.done);
        } else {
          // Nada que cortar: ya estaba resuelto, lo respalda el registro o
          // ya se conocía a ese móvil.
          haptics.light();
          _set(_State.notNeeded);
        }
      } else {
        // Como al quitar un móvil: si este móvil volvería a esperar
        // aprobación, se avisa antes (N7).
        final preview = await ref
            .read(v2ResolutionActionsProvider)
            .previewDeparture(widget.id);
        if (!mounted) return;
        if (preview.selfWouldWait) {
          haptics.warning();
          final go = await showRegalosConfirm(
            context,
            title: l10n.deviceRemoveWaitTitle,
            body: l10n.deviceRemoveWaitBody,
            confirmLabel: l10n.deviceRemoveWaitAction,
            cancelLabel: l10n.actionCancel,
          );
          if (!go || !mounted) {
            widget.onPin(pinned: false);
            _set(_State.idle);
            return;
          }
        }
        await _completeDeparture(
          ref,
          widget.id,
          selfWaitAccepted: preview.selfWouldWait,
        );
        if (!mounted) return;
        haptics.success();
        _set(_State.done);
      }
      widget.onResolved();
    } on Object {
      // Sin red la operación queda pendiente: se puede repetir.
      if (!mounted) return;
      haptics.error();
      _set(_State.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final unbacked = widget.kind == _Kind.unbacked;
    final action = unbacked
        ? l10n.healthUnbackedAction
        : l10n.healthDepartedAction;

    Widget outlined(String label, VoidCallback onPressed, {Key? key}) =>
        OutlinedButton(
          key: key,
          style: OutlinedButton.styleFrom(
            foregroundColor: t.text,
            minimumSize: const Size(44, 48),
            side: BorderSide(color: t.controlBorder),
            shape: _buttonShape,
          ),
          onPressed: onPressed,
          child: Text(label),
        );

    final Widget footer;
    switch (_state) {
      case _State.idle:
        footer = outlined(action, _run);
      case _State.busy:
        footer = Semantics(
          liveRegion: true,
          label: l10n.healthResolveBusy,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (!reduce) ...[
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.ink,
                      backgroundColor: t.track,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(l10n.healthResolveBusy, style: t.styles.meta),
                ),
              ],
            ),
          ),
        );
      case _State.done:
      case _State.notNeeded:
        final text = _state == _State.notNeeded
            ? l10n.healthUnbackedNotNeeded
            : (unbacked ? l10n.healthUnbackedDone : l10n.healthDepartedDone);
        footer = Semantics(
          liveRegion: true,
          container: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                const SuccessMark(size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: t.styles.metaStrong.copyWith(color: t.text),
                  ),
                ),
              ],
            ),
          ),
        );
      case _State.error:
        footer = Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.healthResolveError,
                style: t.styles.meta.copyWith(color: t.danger),
              ),
              const SizedBox(height: 8),
              outlined(
                l10n.healthRetry,
                _run,
                key: const ValueKey<String>('healthRetry'),
              ),
            ],
          ),
        );
    }

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconChip(
                  icon: unbacked ? SettingsIcons.shield : SettingsIcons.phone,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: t.styles.metaStrong.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unbacked
                            ? l10n.healthUnbackedBody
                            : l10n.healthDepartedBody,
                        style: t.styles.meta,
                      ),
                      if (widget.reference != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.reference!,
                          style: t.styles.meta.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // El pie cambia de estado con un fundido y la tarjeta se ajusta
            // con el muelle suave; con «Reducir movimiento», solo el fundido.
            AnimatedSize(
              duration: reduce ? Duration.zero : RegalosSprings.softDuration,
              curve: RegalosCurves.soft,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: RegalosMotion.fade,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey<_State>(_state),
                  child: footer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

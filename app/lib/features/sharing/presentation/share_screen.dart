import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/sync/model.dart' show Recipient;
import '../../../core/sync/pairing_v2.dart'
    show kSyncProtocolV2, syncProtocolOf;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/presentation/pending_gifts_sheet.dart';
import '../../settings/presentation/settings_column.dart';
import '../../sync/application/family_device_review.dart';
import '../../sync/application/family_device_rows.dart';
import '../../sync/application/pairing_v2_controller.dart';
import '../../sync/application/recovery_providers.dart'
    show RecoveryReadiness, recoveryStatusProvider;
import '../../sync/application/sync_controller.dart';
import '../../sync/application/v2_health_provider.dart';
import '../../sync/data/sync_config.dart' show syncLikelyBlockedProvider;
import '../../sync/data/sync_transport.dart';
import '../../sync/domain/sync_status.dart';
import '../../sync/presentation/invite_screen.dart';
import '../../sync/presentation/join_invite_screen.dart';
import '../../sync/presentation/sync_texts.dart';
import '../../web_device/presentation/connect_web_flow.dart';
import '../application/share_service.dart';
import 'connect_sheet.dart';
import 'device_sheets.dart';
import 'more_options_sheet.dart';
import 'share_error_text.dart';
import 'v2_health_notices.dart';

/// Ajustes › Móviles de la familia (la maqueta de ajustes, Compartir A):
/// responde a «¿está al día?» y «¿quién tiene la lista?».
///
/// Una tarjeta de estado (con «Sincronizar ahora» y los errores), la lista de
/// móviles conectados, un solo botón para conectar otro y «Más opciones». La
/// sincronización no tiene interruptor: empieza sola al conectar el segundo
/// móvil. El fichero `.gifthuddle` vive en «Copia de seguridad».
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  Timer? _tick;

  // El sello que rebota: solo tras un «Sincronizar ahora» que pide la
  // persona, y hasta que vuelve a sincronizar.
  bool _manual = false;
  bool _result = false;

  @override
  void initState() {
    super.initState();
    // «Hace 1 min» se renueva sin que cambie el estado.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _say(String text) {
    showRegalosSnackBar(context, SnackBar(content: Text(text)));
  }

  /// Abre una pantalla por encima de la barra inferior.
  void _open(Widget screen) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openDevice(
    FamilyDeviceEntry entry,
    Map<String, String> people,
    String selfName,
  ) async {
    final result = await showDeviceDetailSheet(
      context,
      entry: entry,
      people: people,
      selfName: selfName,
    );
    if (result == null || !mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final web = entry.row.isWeb;
    switch (result) {
      case DeviceSheetResult.approved:
        _say(l10n.deviceApprovedSnack);
      case DeviceSheetResult.removed:
        _say(web ? l10n.deviceRemovedWebSnack : l10n.deviceRemovedSnack);
      case DeviceSheetResult.removedWithOrphans:
        // Al quitar un móvil pueden quedar otros sueltos: se confirman uno a
        // uno en la bandeja.
        _say(web ? l10n.deviceRemovedWebSnack : l10n.deviceRemovedSnack);
        await _review(people);
      case DeviceSheetResult.removedCutPending:
        _say(
          web
              ? l10n.deviceRemovedWebPendingSnack
              : l10n.deviceRemovedPendingSnack,
        );
      case DeviceSheetResult.removedCutPendingWithOrphans:
        _say(
          web
              ? l10n.deviceRemovedWebPendingSnack
              : l10n.deviceRemovedPendingSnack,
        );
        await _review(people);
      case DeviceSheetResult.removeFailed:
        // La hoja ya se cerró al confirmar: el móvil sigue en la lista y se
        // puede volver a intentar.
        _say(web ? l10n.deviceRemoveWebError : l10n.deviceRemoveError);
    }
  }

  Future<void> _review(Map<String, String> people) =>
      showDeviceReviewSheet(context, people: people);

  Future<void> _connect() async {
    final choice = await showConnectSheet(context);
    if (choice == ConnectChoice.far && mounted) {
      _open(const InviteScreen());
    }
  }

  /// «Conectar la web»: escanear el QR del navegador y elegir de quién es.
  void _connectWeb() => _open(const ConnectWebScreen());

  Future<void> _more(SyncStatus status, {required bool canStopSync}) async {
    final choice = await showMoreOptionsSheet(
      context,
      canStopSync: canStopSync,
      showPrivacy: status.phase != SyncPhase.notConfigured,
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case MoreChoice.scanQr:
        unawaited(context.push('/join'));
      case MoreChoice.pasteLink:
        _open(const JoinInviteScreen());
      case MoreChoice.stopSync:
        await _stop();
    }
  }

  Future<void> _stop() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(syncControllerProvider.notifier).stopSyncing();
      if (mounted) {
        _say(l10n.syncStopDone);
      }
    } on SyncTransportException {
      if (mounted) {
        _say(l10n.syncStopError);
      }
    }
  }

  Future<void> _turnOn() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(syncControllerProvider.notifier).setEnabled(true);
    if (mounted) {
      _say(l10n.syncTurnedOn);
    }
  }

  void _syncNow() {
    _manual = true;
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  Future<void> _sendNow(BuildContext rowContext) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(shareServiceProvider).shareEnvelope(rowContext);
    } on Object catch (error) {
      if (mounted) {
        _say(shareSendErrorMessage(l10n, error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    ref.listen<SyncStatus>(syncControllerProvider, (previous, next) {
      if (next.phase == SyncPhase.synced && _manual) {
        _manual = false;
        setState(() => _result = true);
      } else if (next.phase != SyncPhase.synced && _result) {
        setState(() => _result = false);
      }
    });
    final status = ref.watch(syncControllerProvider);
    final family = ref.watch(familyControllerProvider).value;
    final identity = family?.identity;
    final paired = family?.paired ?? false;
    final myName = identity?.deviceName.trim() ?? '';
    final peerName = identity?.peerName?.trim() ?? '';
    final serverless = status.phase == SyncPhase.notConfigured;
    // Qué protocolo tiene la familia se sabe desde el principio por su marca
    // en el documento: en v2 la lista sale del registro firmado y nunca se
    // pinta la de v1 (ni mientras carga ni si falla la lectura); en v1 sigue
    // siendo este móvil y, si está emparejado, el otro.
    final isV2 =
        family != null && syncProtocolOf(family.doc) == kSyncProtocolV2;
    final devices = isV2 ? ref.watch(familyDeviceRowsProvider) : null;
    final v2Rows = devices?.hasValue == true ? devices!.value : null;
    final v2Failed = devices != null && devices.hasError && v2Rows == null;
    // Si hay otros móviles (la web cuenta). En v2 lo dice el registro firmado
    // (este móvil y los demás, activos): la marca `paired` de la identidad es
    // de v1 y puede quedarse puesta al retirar al último compañero. Mientras
    // el registro carga, falla o no existe (una migración a medias), no se
    // sabe: `null`. Riverpod conserva el valor anterior durante una recarga
    // y tras un error, así que tampoco se afirma nada entonces. En v1, la
    // marca.
    final registryFresh =
        devices != null && !devices.isLoading && !devices.hasError;
    final bool? companions = isV2
        ? (v2Rows == null || !registryFresh ? null : v2Rows.length > 1)
        : paired;
    // Qué móviles hay que revisar (pendientes, huérfanos...): si la lectura
    // falla, la lista sale sin estados.
    final review = isV2
        ? (ref.watch(deviceReviewProvider).value ?? DeviceReview.empty)
        : DeviceReview.empty;
    final entries = v2Rows == null ? null : familyDeviceEntries(v2Rows, review);
    // Un móvil ha entrado (o está entrando) y aún no cuenta como conectado:
    // espera la aprobación o a terminar de conectarse (1.0.6, QA m3). La
    // tarjeta lo dice en vez de «Solo en este móvil».
    final hostPhase = ref.watch(pairingV2HostProvider.select((s) => s.phase));
    final guestPending =
        companions != true &&
        (const {
              PairingV2HostPhase.compare,
              PairingV2HostPhase.confirmPerson,
              PairingV2HostPhase.approving,
              PairingV2HostPhase.done,
            }.contains(hostPhase) ||
            (entries?.any(
                  (e) => !e.isSelf && e.status == FamilyDeviceStatus.pending,
                ) ??
                false));
    // Avisos que no son de conexión: móvil quitado por otro, sorpresas en
    // pausa, accesos sin respaldo y bajas a medias.
    final health = isV2 ? ref.watch(v2HealthProvider).value : null;
    final people = {
      for (final r in family?.fullView.recipients ?? const <Recipient>[])
        r.id: r.name.trim(),
    };
    // Con un código de recuperación activo la lista tiene copia cifrada en el
    // servidor aunque no haya otro móvil: la tarjeta no dice «Solo en este
    // móvil» a secas.
    final recoverySaved = ref.watch(
      recoveryStatusProvider.select(
        (r) =>
            r.readiness == RecoveryReadiness.prepared ||
            r.readiness == RecoveryReadiness.updatePending,
      ),
    );
    // Tras pasar a la sincronización nueva, cada móvil se conecta otra vez.
    final reconnect = ref.watch(syncReconnectNeededProvider).value ?? false;
    final likelyBlocked = ref.watch(syncLikelyBlockedProvider).value ?? false;
    final canStopSync =
        status.active ||
        (status.phase == SyncPhase.disabled && isV2 && reconnect);
    // Conectar la web empareja en v2: solo si esta versión sincroniza.
    final canConnectWeb = ref.watch(pairingV2AvailableProvider);

    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        step: const Duration(milliseconds: 40),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsShare,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              StaggerItem(
                index: 0,
                dy: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (status.phase != SyncPhase.removed)
                        _StatusCard(
                          status: status,
                          paired: companions,
                          guestPending: guestPending,
                          recoverySaved: recoverySaved,
                          celebrate: _result,
                          likelyBlocked: likelyBlocked,
                          onSyncNow: _syncNow,
                          onTurnOn: _turnOn,
                        ),
                      if (reconnect) ...[
                        const SizedBox(height: 12),
                        const _ReconnectNotice(),
                      ],
                      AnimatedSize(
                        duration: RegalosMotion.of(context).reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child:
                            review.isEmpty || (health?.revokedByOthers ?? false)
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _ReviewNotice(
                                  count: review.items.length,
                                  onOpen: () => _review(people),
                                ),
                              ),
                      ),
                      if (health != null)
                        V2HealthNotices(
                          health: health,
                          people: people,
                          onReconnect: () => unawaited(context.push('/join')),
                          onReview: () => _review(people),
                        ),
                      // Regalos en secreto guardados solo en este móvil.
                      if (isV2)
                        const PendingGiftsNotice(
                          padding: EdgeInsets.only(top: 12),
                        ),
                    ],
                  ),
                ),
              ),
              StaggerItem(
                index: 1,
                dy: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: l10n.devicesConnected,
                      trailing: isV2
                          ? (v2Rows != null ? '${v2Rows.length}' : null)
                          : '${paired ? 2 : 1}',
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    ),
                    // Al conectar otro móvil su fila se despliega. Con la
                    // sincronización v2 (ADR 0004) la lista sale del registro
                    // firmado de móviles; en v1 sigue siendo este móvil y,
                    // si está emparejado, el otro. «Quitar este móvil» y el
                    // resto de acciones llegan en otra fase.
                    AnimatedRows(
                      rows: [
                        if (isV2 && entries != null)
                          for (final entry in entries)
                            AnimatedRowItem(
                              id: entry.isSelf ? 'self' : entry.row.deviceId,
                              child: _v2DeviceRow(
                                l10n,
                                entry,
                                people: people,
                                selfName: myName,
                                onTap: () => _openDevice(entry, people, myName),
                              ),
                            )
                        else if (isV2)
                          // Mientras se lee el registro (o si falla), solo
                          // este móvil, que sí se conoce; el resto entra
                          // cuando llegue.
                          AnimatedRowItem(
                            id: 'self',
                            child: _DeviceRow(
                              name: myName.isEmpty
                                  ? l10n.devicesThisPhone
                                  : myName,
                              hint: myName.isEmpty
                                  ? null
                                  : l10n.devicesThisPhone,
                            ),
                          )
                        else ...[
                          AnimatedRowItem(
                            id: 'self',
                            child: _DeviceRow(
                              name: myName.isEmpty
                                  ? l10n.devicesThisPhone
                                  : myName,
                              hint: myName.isEmpty
                                  ? null
                                  : l10n.devicesThisPhone,
                            ),
                          ),
                          if (paired)
                            AnimatedRowItem(
                              id: 'peer',
                              child: _DeviceRow(
                                name: peerName.isEmpty
                                    ? l10n.devicesOtherPhone
                                    : peerName,
                                hint: l10n.devicesPeerHint,
                              ),
                            ),
                        ],
                      ],
                    ),
                    AnimatedSize(
                      duration: RegalosMotion.of(context).reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: v2Failed
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                l10n.devicesListError,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: t.textSecondary,
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    if (health != null && !health.revokedByOthers)
                      V2ResolutionSection(
                        health: health,
                        devices: v2Rows,
                        people: people,
                        selfName: myName,
                      ),
                  ],
                ),
              ),
              StaggerItem(
                index: 2,
                dy: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FilledButton.icon(
                    onPressed: _connect,
                    icon: StrokeIcon(
                      AppIcons.plus,
                      size: 20,
                      color: t.onFill,
                      strokeWidth: 2.2,
                    ),
                    label: Text(l10n.devicesConnect),
                  ),
                ),
              ),
              StaggerItem(
                index: 3,
                dy: 10,
                child: Container(
                  margin: const EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.separator)),
                  ),
                  child: Column(
                    children: [
                      // Sin servidor la lista no viaja sola: tras conectar,
                      // se envía con el fichero.
                      if (serverless && paired)
                        Builder(
                          builder: (rowContext) => SettingsRow(
                            icon: SettingsIcons.upload,
                            title: l10n.devicesSendNow,
                            hint: l10n.devicesSendNowHint,
                            onTap: () => _sendNow(rowContext),
                          ),
                        ),
                      if (canConnectWeb)
                        SettingsRow(
                          icon: SettingsIcons.computer,
                          title: l10n.devicesConnectWeb,
                          hint: l10n.devicesConnectWebHint,
                          onTap: _connectWeb,
                        ),
                      SettingsRow(
                        icon: SettingsIcons.dots,
                        title: l10n.devicesMore,
                        hint: canStopSync
                            ? l10n.devicesMoreHint
                            : l10n.devicesJoinOther,
                        onTap: () => _more(status, canStopSync: canStopSync),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La fila de un móvil del registro v2. Título: la persona del móvil; si no
/// tiene (o no se conoce), el nombre del móvil; si tampoco, «Otro móvil» (o
/// «Este móvil» para el propio). Subtítulo: «Este móvil», «Conectado a esta
/// familia» o, según su estado, que espera aprobación, está congelado, hay que
/// confirmar de quién es o aún no abre las sorpresas. Se toca para abrir su
/// hoja.
Widget _v2DeviceRow(
  AppLocalizations l10n,
  FamilyDeviceEntry entry, {
  required Map<String, String> people,
  required String selfName,
  required VoidCallback onTap,
}) {
  final row = entry.row;
  final name = deviceTitle(l10n, row, people: people, selfName: selfName);
  final String? hint;
  if (row.isSelf) {
    hint = name == l10n.devicesThisPhone ? null : l10n.devicesThisPhone;
  } else {
    hint = switch (entry.status) {
      FamilyDeviceStatus.pending => l10n.devicesPeerPending,
      FamilyDeviceStatus.frozen => l10n.devicesPeerFrozen,
      FamilyDeviceStatus.reconfirm => l10n.devicesPeerReconfirm,
      FamilyDeviceStatus.noPerson =>
        row.isWeb ? l10n.devicesWebHint : l10n.devicesPeerNoPerson,
      FamilyDeviceStatus.active =>
        row.isWeb ? l10n.devicesWebHint : l10n.devicesPeerHint,
    };
  }
  return _DeviceRow(name: name, hint: hint, onTap: onTap, isWeb: row.isWeb);
}

/// El aviso de que hay móviles por revisar, con el botón que abre la bandeja.
class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: StrokeIcon(
                    tablerAlertTriangle,
                    size: 18,
                    color: t.text,
                    strokeWidth: 1.9,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deviceReviewNoticeTitle,
                        style: t.styles.metaStrong.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.deviceReviewNoticeBody(count),
                        style: t.styles.meta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                minimumSize: const Size(44, 44),
                side: BorderSide(color: t.controlBorder),
                shape: const RoundedRectangleBorder(
                  borderRadius: RegalosShape.button,
                ),
              ),
              onPressed: onOpen,
              child: Text(l10n.deviceReviewOpen),
            ),
          ],
        ),
      ),
    );
  }
}

/// El aviso de volver a conectar los móviles para la sincronización nueva: lo
/// que hay que hacer y cómo (cada móvil se conecta otra vez comparando un
/// número).
class _ReconnectNotice extends StatelessWidget {
  const _ReconnectNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: StrokeIcon(
                tablerAlertTriangle,
                size: 18,
                color: t.text,
                strokeWidth: 1.9,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pairingV2ReconnectTitle,
                    style: t.styles.metaStrong.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.pairingV2ReconnectBody, style: t.styles.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un móvil de la lista «Conectados»: cuadro con el icono, nombre y frase. Una
/// web lleva el icono de ordenador.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    this.hint,
    this.onTap,
    this.isWeb = false,
  });

  final String name;
  final String? hint;
  final VoidCallback? onTap;
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return SettingsRow(
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.chip,
        ),
        child: StrokeIcon(
          isWeb ? SettingsIcons.computer : SettingsIcons.phone,
          size: 20,
          color: t.textOnSoft,
          strokeWidth: 1.9,
        ),
      ),
      title: name,
      hint: hint,
      onTap: onTap,
    );
  }
}

/// La tarjeta de estado: marca, título, frase y, si toca, «Sincronizar
/// ahora» o «Encender».
///
/// Al pedir «Sincronizar ahora» pasa a una barra de progreso y vuelve con el
/// sello rebotando ([celebrate]). El cambio de un estado a otro es un fundido
/// de 150 ms; con «Reducir movimiento» no hay barra que se mueva ni rebote.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.paired,
    required this.recoverySaved,
    required this.celebrate,
    required this.onSyncNow,
    required this.onTurnOn,
    this.likelyBlocked = false,
    this.guestPending = false,
  });

  final SyncStatus status;

  /// Otro móvil espera la aprobación o está terminando de conectarse: en vez
  /// de «Solo en este móvil», la tarjeta dice que lo espera.
  final bool guestPending;

  /// Sin conexión con ninguna ruta varias veces seguidas: la frase sugiere
  /// que el operador puede estar bloqueando el servicio.
  final bool likelyBlocked;

  /// Si hay otro móvil conectado; `null` si no se sabe (el registro de móviles
  /// aún no se ha leído).
  final bool? paired;

  /// Si hay un código de recuperación activo (copia cifrada en el servidor).
  final bool recoverySaved;
  final bool celebrate;
  final VoidCallback onSyncNow;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;

    Widget mark(StrokeIconBuilder icon, {bool muted = false}) => Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? t.ideaStroke : t.ink,
        borderRadius: RegalosShape.chip,
      ),
      child: StrokeIcon(icon, size: 20, color: t.bg, strokeWidth: 2),
    );
    Widget syncNow() => Semantics(
      container: true,
      button: true,
      label: l10n.syncNowTitle,
      excludeSemantics: true,
      onTap: onSyncNow,
      child: InkWell(
        onTap: onSyncNow,
        customBorder: const RoundedRectangleBorder(
          borderRadius: RegalosShape.button,
        ),
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: StrokeIcon(
              SettingsIcons.refresh,
              color: t.ink,
              strokeWidth: 1.9,
            ),
          ),
        ),
      ),
    );

    Widget? leading;
    Widget? trailing;
    Widget? below;
    String title;
    String? body;
    // La pista del bloqueo (1.0.6): una segunda frase bajo la primera, no en su
    // lugar, para que se vea qué pasa con los cambios y qué probar.
    String? hint;
    // Con un solo móvil la tarjeta dice «Solo en este móvil», salvo que la
    // sincronización esté a la espera del segundo o apagada, que se dice.
    final phase =
        paired == null ||
            paired! ||
            status.phase == SyncPhase.waitingForPeer ||
            status.phase == SyncPhase.disabled ||
            status.phase == SyncPhase.removed
        ? status.phase
        : SyncPhase.noFamily;
    // Con el segundo móvil ya conectado (registro leído), «a la espera del
    // segundo» está anticuado: la sincronización lo deja así hasta su siguiente
    // vuelta, pero la lista de abajo ya enseña los dos móviles. Mientras no
    // sincronice, la tarjeta dice que está pendiente (y deja «Sincronizar
    // ahora»). Sin saber si hay otro móvil no se afirma nada: sale el estado
    // tal cual.
    final shown = paired == true && phase == SyncPhase.waitingForPeer
        ? SyncPhase.idle
        : phase;
    switch (shown) {
      case SyncPhase.noFamily || SyncPhase.waitingForPeer when guestPending:
        leading = mark(SettingsIcons.phone);
        title = l10n.devicesPendingTitle;
        body = l10n.devicesPendingBody;
      case SyncPhase.noFamily:
        if (recoverySaved) {
          leading = mark(SettingsIcons.shield);
          title = l10n.devicesRecoveryTitle;
          body = l10n.devicesRecoveryBody;
        } else {
          leading = mark(SettingsIcons.phone);
          title = l10n.devicesSoloTitle;
          body = l10n.devicesSoloBody;
        }
      case SyncPhase.waitingForPeer:
        // Sin «Sincronizar ahora»: hasta que haya un segundo móvil no se
        // habla con el servidor y el botón no haría nada.
        leading = mark(
          recoverySaved ? SettingsIcons.shield : SettingsIcons.phone,
        );
        title = recoverySaved
            ? l10n.devicesRecoveryTitle
            : l10n.devicesSoloTitle;
        body = recoverySaved
            ? l10n.devicesRecoveryBody
            : l10n.syncStatusWaitingPeer;
      case SyncPhase.notConfigured:
        // Dos móviles en una versión sin servidor: están conectados, pero la
        // lista solo viaja con el fichero o el QR.
        leading = mark(SettingsIcons.phone);
        title = l10n.devicesManualTitle;
        body = l10n.devicesManualBody;
      case SyncPhase.disabled:
        leading = mark(SettingsIcons.cloudOff, muted: true);
        title = l10n.devicesOffTitle;
        body = l10n.devicesOffBody;
        trailing = TextButton(
          style: TextButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.button,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: onTurnOn,
          child: Text(l10n.devicesTurnOn),
        );
      case SyncPhase.removed:
        leading = mark(SettingsIcons.cloudOff, muted: true);
        title = l10n.healthRevokedTitle;
        body = l10n.healthRevokedBody;
      case SyncPhase.syncing:
        title = l10n.syncStatusSyncing;
        below = reduce
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: t.ink,
                  backgroundColor: t.track,
                ),
              );
      case SyncPhase.idle:
        leading = mark(AppIcons.check);
        title = l10n.syncStatusIdle;
        body = l10n.devicesEncrypted;
        trailing = syncNow();
      case SyncPhase.synced:
        leading = celebrate
            ? const SuccessMark(
                size: 32,
                checkDelay: Duration(milliseconds: 160),
              )
            : mark(AppIcons.check);
        title = l10n.devicesUpToDateTitle;
        body = l10n.devicesUpToDateBody(syncStatusText(l10n, status));
        trailing = syncNow();
      case SyncPhase.offline:
        leading = mark(SettingsIcons.cloudOff, muted: true);
        title = l10n.devicesOfflineTitle;
        body = l10n.devicesOfflineBody;
        if (likelyBlocked) hint = l10n.syncBlockedHint;
        trailing = syncNow();
      case SyncPhase.error:
        leading = mark(tablerAlertTriangle, muted: true);
        title = l10n.syncStatusError;
        body = syncIssueText(l10n, status);
        trailing = syncNow();
    }

    final content = Row(
      key: ValueKey<Object>((phase, celebrate, hint != null, guestPending)),
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: t.styles.rowTitleCompact.copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.textOnSoft,
                ),
              ),
              if (body != null)
                Text(body, style: t.styles.meta.copyWith(color: t.textOnSoft)),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint, style: t.styles.meta.copyWith(color: t.textOnSoft)),
              ],
              if (below != null) ...[const SizedBox(height: 8), below],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing],
      ],
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 66),
        padding: EdgeInsets.fromLTRB(12, 10, trailing == null ? 12 : 4, 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
        ),
        child: AnimatedSwitcher(
          duration: RegalosMotion.fade,
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
          child: content,
        ),
      ),
    );
  }
}

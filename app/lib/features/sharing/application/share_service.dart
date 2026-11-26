import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/task_runner.dart';
import '../../../core/platform/document_exchange.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/exchange_file.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/wish_boundary.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/family_store.dart';
import '../../family/domain/family_errors.dart';
import '../../sync/application/app_sync_v2_local.dart';
import '../../sync/application/exchange_v2.dart';

export '../../../core/platform/document_exchange.dart'
    show tempDirectoryProvider;

/// Intercambiar cambios entre móviles con sobres cifrados.
class ShareService {
  /// Crea el servicio.
  ShareService(this._ref);

  final Ref _ref;

  FamilyController get _controller =>
      _ref.read(familyControllerProvider.notifier);

  /// Si la familia ya ha pasado al formato 2 del común (la marca
  /// irreversible, ADR 0005, B4). Con ella el sobre de siempre está
  /// cerrado en los dos sentidos (va sin firma de escritor y solo con la
  /// `familyKey`, que un revocado conserva) y se usa el fichero de
  /// intercambio nuevo (B6, [ExchangeV2]).
  Future<bool> _cut() async =>
      await _ref.read(familyStoreProvider).readCommonFormatFloor() >= 2;

  /// Lo de [run] sobre lo local v2, dentro de la cola de la familia.
  Future<T> _v2<T>(Future<T> Function(AppSyncV2Local local) run) =>
      _ref.read(v2FamilyLockProvider).run(() async {
        final local = await AppSyncV2Local.load(_ref);
        if (local == null) {
          throw const ExchangeNotReadyException(
            'la familia aún no está lista para el formato nuevo',
          );
        }
        return run(local);
      });

  /// Crea el sobre con el documento entero. Sin la marca del formato 2, el
  /// de siempre, cifrado con la clave de la familia; con ella, el fichero de
  /// intercambio firmado con sus paquetes (B6).
  ///
  /// Lanza [NoFamilyException] si todavía no hay familia y
  /// [ExchangeNotAllowedException] si este móvil aún no puede repartir la
  /// clave común (pendiente de aprobar).
  Future<Uint8List> buildEnvelope() async {
    final state = await _ref.read(familyControllerProvider.future);
    final identity = state.identity;
    final key = _controller.familyKey;
    if (identity == null || key == null) {
      throw const NoFamilyException();
    }
    if (await _cut()) {
      return _v2((local) => ExchangeV2(local).export());
    }
    // Solo el común publicable: sin los regalos de las personas protegidas
    // (revisión de seguridad, lote 6, 2). Sin identidad v2 no hay protección posible.
    final doc = await _ref.read(v2FamilyLockProvider).run<FamilyDoc>(() async {
      final local = await AppSyncV2Local.load(_ref);
      if (local != null) return publishableCommonFor(local);
      // Una familia v2 sin lo local listo no se exporta sin filtrar.
      if (await _ref.read(familyStoreProvider).readSyncV2() != null) {
        throw const ExchangeNotReadyException(
          'la familia v2 aún no está lista para exportar',
        );
      }
      // Sin identidad v2 tampoco sale nada privado de los deseos.
      return state.doc.wishBoundary();
    });
    return seal(
      doc: doc.toJson(),
      listId: identity.listId,
      fromNode: identity.node,
      at: doc.maxStamp?.pack() ?? '',
      key: key,
      // 1.0.7: versión exterior que 1.0.6 rechaza antes de fusionar.
      version: kFileEnvelopeVersion,
    );
  }

  /// Escribe el sobre como fichero `.gifthuddle` en el directorio temporal.
  Future<XFile> exportEnvelope() async => _ref
      .read(documentExchangeProvider)
      .exportBytes(await buildEnvelope(), envelopeFileName(clock.now()));

  /// Comparte el sobre con la hoja de compartir del sistema.
  Future<ShareResult> shareEnvelope(BuildContext context) async {
    final text = AppLocalizations.of(context).shareEnvelopeText;
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return _ref
        .read(documentExchangeProvider)
        .shareBytes(
          await buildEnvelope(),
          envelopeFileName(clock.now()),
          text: text,
          origin: origin,
        );
  }

  /// Abre un sobre recibido, lo mezcla con la lista y guarda.
  ///
  /// Lanza una [EnvelopeException] si no es un sobre válido, es de otra
  /// lista o no se puede descifrar con la clave de la familia;
  /// [ImportClockDriftException] si el otro móvil tiene la hora mal, y
  /// [NoFamilyException] si todavía no hay familia.
  ///
  /// Con la marca del formato 2 solo entra el fichero de intercambio (B6):
  /// el de siempre da [ExchangeLegacyFileException] y no toca nada; además
  /// puede lanzar [ExchangeGenerationException],
  /// [ExchangeRevokedWriterException] y [ExchangeMissingKeyException] (el
  /// fichero queda guardado y se vuelve a probar al sincronizar). Sin la
  /// marca, un fichero nuevo da [ExchangeNotReadyException].
  Future<ImportSummary> importEnvelopeBytes(Uint8List bytes) async {
    // Rechazar basura antes de esperar al almacenamiento o comprobar si
    // hay familia: también un móvil vacío debe decir que no es un envío.
    // La versión exterior (y que case con la cabecera) se valida antes de
    // cargar nada: cargar la familia puede terminar una operación de
    // protección interrumpida o revocar a un invitado pendiente, y un fichero
    // rechazado no puede tocar lo local.
    if (isExchangeFile(bytes)) {
      ExchangeFile.parse(bytes);
    } else {
      peekHeader(bytes, acceptFileVersion: true);
    }
    final state = await _ref.read(familyControllerProvider.future);
    final identity = state.identity;
    final key = _controller.familyKey;
    if (identity == null || key == null) {
      throw const NoFamilyException();
    }
    if (await _cut()) {
      if (isLegacyEnvelope(bytes)) {
        throw const ExchangeLegacyFileException(
          'la familia ya no usa sobres sin firma: hay que volver a guardarlo '
          'desde un móvil actualizado',
        );
      }
      return _v2((local) async {
        final opened = await ExchangeV2(local)
            .receive(bytes, nowMillis: clock.now().millisecondsSinceEpoch);
        return _controller.mergeRemoteWithinLock(
          opened.doc,
          fromNode: opened.fromNode,
        );
      });
    }
    if (isExchangeFile(bytes)) {
      throw const ExchangeNotReadyException(
        'este móvil aún no ha pasado al formato nuevo: hay que sincronizar',
      );
    }
    final header = peekHeader(bytes, acceptFileVersion: true);
    if (header.listId != identity.listId) {
      throw const EnvelopeWrongListException('el sobre es de otra lista');
    }
    final opened = await _openOffThread(bytes, key.bytes, identity.listId);
    final FamilyDoc remote;
    try {
      remote = FamilyDoc.fromJson(opened.doc);
    } on FormatException {
      throw const EnvelopeFormatException('documento no válido');
    }
    return _controller.mergeRemote(remote, fromNode: opened.fromNode);
  }

  /// Importa un sobre pegado como texto (enlace, fragmento o base64url).
  Future<ImportSummary> importFromText(String text) =>
      importEnvelopeBytes(parseShared(text));
}

class _Opened {
  const _Opened(this.fromNode, this.doc);

  final String fromNode;
  final Map<String, Object?> doc;
}

/// Descifra y descomprime fuera del hilo de la interfaz.
Future<_Opened> _openOffThread(
  Uint8List bytes,
  Uint8List keyBytes,
  String listId,
) => runTask(() async {
  final opened = await open(
    bytes,
    key: FamilyKey(keyBytes),
    expectedListId: listId,
    acceptFileVersion: true,
  );
  return _Opened(opened.header.fromNode, opened.doc);
});

/// El servicio de compartir.
final shareServiceProvider = Provider<ShareService>(ShareService.new);

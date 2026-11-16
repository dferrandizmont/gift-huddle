// Los ficheros `.gifthuddle` de intercambio tras el corte al formato 2 del
// común (ADR 0005, lote B6), sobre [SyncV2Local]. No depende de Flutter.
//
// - **Guardar:** el común de ahora sellado con la candidata sellable de
//   `kid` menor y firmado por este móvil, los paquetes v4 de esa candidata
//   para el resto de su audiencia y solo las fichas que hacen falta para
//   abrirlos (escritor, creador y audiencia) (`ExchangeFile`).
// - **Abrir** (tras la revisión de seguridad, A1-A3): el registro del fichero
//   **no se guarda nunca**. Decide la vista local de antes; las fichas del
//   fichero solo sirven en memoria para resolver resúmenes de ids que ya
//   están enlazados con la misma clave. Revocaciones y miembros nuevos solo
//   llegan por el servidor o al emparejar. Primero una sola verificación de
//   la firma del común; después, los paquetes de esa candidata; después, el
//   común. Todo eso fuera del hilo de la interfaz (`runTask`).
//   - Otra lista o generación: se rechaza.
//   - Un autor revocado (de verdad), una firma que no vale o basura: se
//     rechaza, sin guardar nada.
//   - Falta la clave, o el escritor (con firma comprobada) aún no es activo
//     en este móvil: se guarda el fichero entero aparte (retenido de
//     fichero) y cada sincronización lo vuelve a probar; nunca es un
//     documento vacío. Si no se puede autenticar al escritor: «sincroniza y
//     vuelve a abrirlo», sin guardar nada.
//   - Un fichero firmado antiguo (otra candidata) de un escritor que sigue
//     activo entra si este móvil tiene esa candidata o el fichero la trae.
// - Nada de aquí baja la marca del formato mínimo, toca el registro ni las
//   credenciales: un fichero (o una copia) antiguo no rebaja la familia ni
//   rehabilita a un revocado.
//
// Quien llama toma la cola de la familia (`V2FamilyLock`): aquí se escribe
// la clave común y los retenidos.
//
// API para la copia de recuperación (fase 3, lote 5): es otro formato. Puede
// reutilizar [CommonV2Cycle.sealForFile] y [CommonV2Cycle.receiveFile] para
// el común, pero lleva además el llavero, los contextos y la marca bajo el
// código de recuperación; al restaurar, [SyncV2Local.raiseCommonFormatFloor]
// solo sube y el registro solo se fusiona.
library;

import 'dart:typed_data';

import '../../../core/platform/task_runner.dart';
import '../../../core/sync/access_policy.dart' show livePeopleOf;
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/exchange_file.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/protected_doc.dart' show publishableCommon;
import 'common_v2.dart';
import 'common_v2_cutover.dart' show kCommonFormatLatest;
import 'sync_v2_engine.dart' show SyncV2Local;

/// Un común de fichero abierto, aún sin fusionar.
class ExchangeOpened {
  /// Crea el resultado.
  const ExchangeOpened({required this.doc, required this.fromNode});

  /// El documento común del fichero.
  final FamilyDoc doc;

  /// El nodo para la fusión (el escritor, o el de este móvil si es suyo).
  final String fromNode;
}

/// El común de [local] que puede salir de este móvil en una exportación:
/// el común local sin los regalos públicos de las personas protegidas
/// ([publishableCommon]). Nunca parte de la proyección autorizada.
Future<FamilyDoc> publishableCommonFor(
  SyncV2Local local, {
  DeviceRegistry? registry,
}) async {
  final common = await local.common();
  final view = await (registry ?? await local.registry()).viewFor(
    me: local.identity.deviceId,
    mySigningKey: local.keys.publicKeys.signing,
    livePeople: livePeopleOf(common),
  );
  return publishableCommon(
    common: common,
    slots: await local.slots(),
    keyring: await local.updateKeyring((k) => k),
    view: view,
  );
}

/// Guardar y abrir ficheros `.gifthuddle` de intercambio en el formato 2.
class ExchangeV2 {
  /// Crea el intercambio sobre [local]. [run] ejecuta lo criptográfico fuera
  /// del hilo de la interfaz (por defecto `runTask`).
  ExchangeV2(this.local, {CommonTaskRunner? run}) : _run = run ?? runTask;

  /// Lo local.
  final SyncV2Local local;

  final CommonTaskRunner _run;

  Future<void> _requireCut() async {
    final floor = await local.commonFormatFloor();
    if (floor > kCommonFormatLatest) {
      throw const EnvelopeFormatException(
        'la familia usa un formato posterior: hay que actualizar la app',
      );
    }
    if (floor < kCommonFormatLatest) {
      throw const ExchangeNotReadyException(
        'este móvil aún no ha pasado al formato nuevo: hay que sincronizar',
      );
    }
  }

  Future<RegistryView> _viewOf(DeviceRegistry registry) async =>
      registry.viewFor(
        me: local.identity.deviceId,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: livePeopleOf(await local.common()),
      );

  /// El fichero con lo de este móvil. Lanza [ExchangeNotAllowedException] si
  /// este móvil no puede repartir la clave común (pendiente o revocado),
  /// [ExchangeNotReadyException] sin la marca del formato 2 y
  /// [EnvelopeTooLargeException] si no cabe.
  Future<Uint8List> export() async {
    await _requireCut();
    final registry = await local.registry();
    final view = await _viewOf(registry);
    final sealed = await CommonV2Cycle(local).sealForFile(
      common: await publishableCommonFor(local, registry: registry),
      view: view,
      run: _run,
    );
    return ExchangeFile(
      listId: local.identity.listId,
      syncId: local.identity.syncId,
      records: [
        for (final digest in sealed.recordDigests.toList()..sort())
          ?registry.recordByDigest(digest)?.toJson(),
      ],
      packages: sealed.packages,
      common: sealed.common,
    ).encode();
  }

  /// Abre [bytes] con la vista local: verifica el común, abre su paquete y
  /// lo descifra. Deja guardado solo lo que se haya aprendido de la clave
  /// común (o el fichero, si espera); el registro local no cambia. El
  /// documento lo fusiona quien llama.
  ///
  /// Lanza [EnvelopeWrongListException] si es de otra lista,
  /// [ExchangeGenerationException] si es de otra generación,
  /// [ExchangeRevokedWriterException] si lo escribió un revocado,
  /// [ExchangeMissingKeyException] si falta la clave o el escritor no está
  /// confirmado aquí (`kept`: el fichero queda guardado),
  /// [EnvelopeAuthException] si la firma o el cifrado no valen,
  /// [ExchangeNotReadyException] sin la marca del formato 2 y
  /// [EnvelopeFormatException] o [EnvelopeTooLargeException] si no es un
  /// fichero válido.
  Future<ExchangeOpened> receive(
    Uint8List bytes, {
    required int nowMillis,
  }) async {
    await _requireCut();
    final file = ExchangeFile.parse(bytes);
    if (file.listId != local.identity.listId) {
      throw const EnvelopeWrongListException('el fichero es de otra lista');
    }
    if (file.syncId != local.identity.syncId) {
      throw const ExchangeGenerationException(
        'el fichero es de otra generación de la lista',
      );
    }
    final registry = await local.registry();
    final view = await _viewOf(registry);
    if (view.revokedByOthers) {
      throw const ExchangeNotAllowedException(
        'este móvil ya no es de la familia',
      );
    }
    final got = await CommonV2Cycle(local).receiveFile(
      bytes: bytes,
      file: file,
      registry: registry,
      view: view,
      nowMillis: nowMillis,
      run: _run,
    );
    switch (got.status) {
      case RemoteCommonStatus.opened:
        final writer = got.writer!;
        return ExchangeOpened(
          doc: got.doc!,
          fromNode: writer == view.me ? local.node : writer,
        );
      case RemoteCommonStatus.revokedWriter:
        throw const ExchangeRevokedWriterException(
          'lo ha escrito un móvil que ya no es de la familia',
        );
      case RemoteCommonStatus.missingKey:
        throw ExchangeMissingKeyException(
          got.retained
              ? 'falta la clave del fichero: se ha guardado para más tarde'
              : 'falta la clave del fichero: hay que sincronizar y volver a '
                    'abrirlo',
          kept: got.retained,
        );
      case RemoteCommonStatus.unknownWriter when got.writer != null:
        // Firma comprobada de un móvil que aquí no es activo todavía.
        throw ExchangeMissingKeyException(
          got.retained
              ? 'el escritor aún no está confirmado aquí: se ha guardado'
              : 'el escritor aún no está confirmado aquí: hay que '
                    'sincronizar y volver a abrirlo',
          kept: got.retained,
        );
      case RemoteCommonStatus.unknownWriter:
        // Nadie que este móvil conozca: puede ser un miembro nuevo que aún
        // no ha visto. No se guarda nada.
        throw const ExchangeMissingKeyException(
          'escritor desconocido: hay que sincronizar y volver a abrirlo',
          kept: false,
        );
      case _:
        throw const EnvelopeAuthException('firma o cifrado no válidos');
    }
  }
}

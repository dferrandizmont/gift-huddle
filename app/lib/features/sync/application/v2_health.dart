/// Últimas observaciones del servicio, guardadas en el almacén seguro v2.
/// Los permisos y escritores se vuelven a derivar de los datos locales.
class V2Health {
  V2Health({
    Iterable<String> frozenPeople = const [],
    this.revokedByOthers = false,
    Iterable<String> unbackedCredentials = const [],
    Iterable<String> departedDevices = const [],
    Iterable<String> frozenWriterDeviceIds = const [],
    this.renewSuggested = false,
    this.writerSlotsFull = false,
    this.commonBlocked = false,
    this.commonBlockedWriter,
    this.commonPackagesFull = false,
    this.commonKeyringFull = false,
    this.retainedCommons = 0,
    this.pendingSelfPerson,
  }) : frozenPeople = Set.unmodifiable(frozenPeople),
       unbackedCredentials = Set.unmodifiable(unbackedCredentials),
       departedDevices = Set.unmodifiable(departedDevices),
       frozenWriterDeviceIds = Set.unmodifiable(frozenWriterDeviceIds);

  /// Conserva sus datos, pero este móvil no puede abrirlos hasta ser aprobado.
  final Set<String> frozenPeople;

  /// Solo la interfaz (no se guarda): si este móvil espera la aprobación de
  /// otro, la persona que ha elegido (cadena vacía si no ha elegido ninguna).
  /// Es la que nombra el aviso de sorpresas en pausa.
  final String? pendingSelfPerson;

  /// Revocación verificada, id ocupado por otras claves o servicio revocado.
  final bool revokedByOthers;

  /// Ids de móvil de las credenciales de servicio sin respaldo en el registro.
  final Set<String> unbackedCredentials;

  /// Miembros cuya credencial ya está revocada: falta completar el registro.
  final Set<String> departedDevices;

  /// Escritores de slots que esperan aprobación; impiden compactar borrados.
  final Set<String> frozenWriterDeviceIds;

  /// Conviene renovar esta generación antes de alcanzar su límite permanente.
  final bool renewSuggested;

  /// Este móvil ha llegado a su tope de slots (uno por persona protegida):
  /// alguna alta no se ha publicado. Renovar no lo arregla.
  final bool writerSlotsFull;

  /// El común del servidor no se puede abrir desde aquí (falta la clave o
  /// no se reconoce al escritor): no se sustituye mientras dura la espera
  /// (ADR 0005, B3) y los cambios locales esperan.
  final bool commonBlocked;

  /// Quién escribió el común bloqueado (id sin autenticar): la interfaz pide
  /// confirmarlo o revocarlo. Al revocarlo, el común se sustituye.
  final String? commonBlockedWriter;

  /// El reparto de la clave común no cabe en el servidor: no se sustituye
  /// el común y conviene renovar.
  final bool commonPackagesFull;

  /// El llavero común ha llegado a su tope duro.
  final bool commonKeyringFull;

  /// Comunes del servidor guardados aparte, sin fusionar, para recuperarlos
  /// a mano (ilegibles, falsos o de un revocado).
  final int retainedCommons;

  Map<String, Object?> toJson() => {
    'unbacked': unbackedCredentials.toList()..sort(),
    'departed': departedDevices.toList()..sort(),
    'renew': renewSuggested,
    if (writerSlotsFull) 'writerFull': true,
    if (revokedByOthers) 'revoked': true,
    if (revokedByOthers) 'revocationConfirmed': true,
    if (commonBlocked) 'commonBlocked': true,
    if (commonBlockedWriter != null) 'commonBlockedWriter': commonBlockedWriter,
    if (commonPackagesFull) 'commonPackagesFull': true,
    if (commonKeyringFull) 'commonKeyringFull': true,
    if (retainedCommons > 0) 'retainedCommons': retainedCommons,
  };

  factory V2Health.fromJson(Object? json) {
    if (json is! Map) return V2Health();
    Iterable<String> ids(Object? raw) =>
        raw is List ? raw.whereType<String>() : const <String>[];
    return V2Health(
      unbackedCredentials: ids(json['unbacked']),
      departedDevices: ids(json['departed']),
      renewSuggested: json['renew'] == true,
      writerSlotsFull: json['writerFull'] == true,
      // Versiones anteriores guardaban cualquier 401 como retirada. Sin esta
      // evidencia se vuelve a consultar el servicio; el registro firmado se
      // comprueba por separado y sigue siendo válido aunque falte la marca.
      revokedByOthers:
          json['revoked'] == true && json['revocationConfirmed'] == true,
      commonBlocked: json['commonBlocked'] == true,
      commonBlockedWriter: json['commonBlockedWriter'] is String
          ? json['commonBlockedWriter'] as String
          : null,
      commonPackagesFull: json['commonPackagesFull'] == true,
      commonKeyringFull: json['commonKeyringFull'] == true,
      retainedCommons:
          json['retainedCommons'] is int &&
              (json['retainedCommons'] as int) >= 0
          ? json['retainedCommons'] as int
          : 0,
    );
  }
}

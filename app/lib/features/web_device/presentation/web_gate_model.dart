import 'package:flutter/foundation.dart';

/// Por qué falló el emparejamiento de la web.
enum WebConnectFailure {
  /// El QR o el código caducó.
  expired,

  /// El código que enseñó el móvil no era el de la web.
  codeMismatch,

  /// El móvil rechazó la conexión.
  rejected,

  /// No hubo red o el servidor no contestó.
  network,

  /// La invitación desapareció antes de caducar: el móvil canceló o la
  /// borró, o ya no está en el servidor.
  cancelled,

  /// El móvil (o esta web) necesita actualizarse: no hay código que comparar.
  outdated,
}

/// Lo que la puerta web enseña en cada momento.
///
/// El motor (otro lote) decide cuál es y la interfaz solo lo pinta: ninguna
/// pantalla deduce nada del estado de la sesión por su cuenta.
@immutable
sealed class WebGateView {
  const WebGateView();
}

/// Esperando a que el móvil escanee el QR.
final class WebGateConnect extends WebGateView {
  /// Crea el estado; [url] es `https://web.gifthuddle.app/w#...`.
  const WebGateConnect({required this.url});

  /// Lo que codifica el QR.
  final String url;
}

/// Comparando el código de seis cifras; esperando a que el móvil apruebe.
final class WebGateComparing extends WebGateView {
  /// Crea el estado; [code] son las seis cifras, sin espacio.
  const WebGateComparing({required this.code, this.confirmed = false});

  /// Las seis cifras, sin espacio.
  final String code;

  /// Si la persona ya ha dicho en la web que los códigos coinciden: entonces
  /// solo falta que el móvil apruebe.
  final bool confirmed;
}

/// El emparejamiento falló.
final class WebGateConnectFailed extends WebGateView {
  /// Crea el estado.
  const WebGateConnectFailed(this.reason);

  /// Qué pasó.
  final WebConnectFailure reason;
}

/// Hay que elegir el PIN o la frase del ordenador.
final class WebGateChoosePin extends WebGateView {
  /// Crea el estado; [personName] es «Nora» en «Este ordenador es de Nora».
  const WebGateChoosePin({required this.personName});

  /// De quién es este ordenador.
  final String personName;
}

/// Pide el PIN o la frase.
///
/// Cada fallo llega como una instancia nueva con [wrongPin]: la puerta la
/// reconoce por identidad para vaciar el campo y hacer temblar la fila. La
/// cuenta atrás de [retryAfter] también empieza con cada instancia.
final class WebGateUnlock extends WebGateView {
  /// Crea el estado.
  const WebGateUnlock({
    this.attemptsLeft,
    this.retryAfter,
    this.wrongPin = false,
  });

  /// Intentos que quedan antes de suspender la web, si el Worker lo dijo.
  final int? attemptsLeft;

  /// Espera hasta el siguiente intento, si la hay.
  final Duration? retryAfter;

  /// El último PIN era erróneo.
  final bool wrongPin;
}

/// Demasiados intentos: la guarda está suspendida.
final class WebGateSuspended extends WebGateView {
  /// Crea el estado.
  const WebGateSuspended();
}

/// El ordenador ya no está conectado a la familia.
final class WebGateDisconnected extends WebGateView {
  /// Crea el estado; [unsentChanges] son los cambios sin subir guardados.
  const WebGateDisconnected({
    this.unsentChanges = 0,
    this.confirmErase = false,
  });

  /// Cambios sin subir que siguen cifrados en este ordenador.
  final int unsentChanges;

  /// Reconnection first uses the existing explicit erasure confirmation.
  final bool confirmErase;
}

/// La caja cifrada de este ordenador está dañada y no se puede abrir.
///
/// Pasa con una caja anterior a la comprobación de integridad o si alguien
/// ha borrado o alterado una entrada del almacén del navegador. Solo queda
/// borrar los datos de este ordenador y volver a conectarlo desde un móvil.
final class WebGateDamaged extends WebGateView {
  /// Crea el estado.
  const WebGateDamaged();
}

/// La web ya está abierta en otra pestaña.
final class WebGateOtherTab extends WebGateView {
  /// Crea el estado.
  const WebGateOtherTab();
}

/// Tapa que oculta el contenido (bloqueo o pestaña oculta). Sin acciones.
final class WebGateLocked extends WebGateView {
  /// Crea el estado.
  const WebGateLocked();
}

/// Sesión abierta: se ve la app.
final class WebGateOpen extends WebGateView {
  /// Crea el estado.
  const WebGateOpen();
}

/// Resultado de cambiar el PIN desde Ajustes.
enum WebPinChangeResult {
  /// Cambiado.
  changed,

  /// El PIN actual no era el correcto.
  wrongCurrent,

  /// No se pudo guardar; no cambió nada.
  failed,
}

/// Lo que llama la interfaz de la web. El motor lo implementa.
///
/// Los `Future` terminan cuando la acción ya se ha resuelto; el resultado se ve
/// en el [WebGateView] siguiente, salvo en [changePin].
abstract interface class WebGateActions {
  /// Descarta el emparejamiento en curso y enseña un QR nuevo.
  Future<void> restartPairing();

  /// Intenta desbloquear con [pin] (PIN o frase).
  Future<void> submitPin(String pin);

  /// Fija [pin] como PIN o frase de este ordenador. La interfaz ya comprobó
  /// `VaultCrypto.validPin`.
  Future<void> choosePin(String pin);

  /// Toma el uso de la web para esta pestaña (la otra se bloquea).
  Future<void> useHere();

  /// Vuelve a comprobar si la guarda sigue suspendida.
  Future<void> retry();

  /// Empareja otra vez este ordenador.
  Future<void> reconnect();

  /// Borra los datos locales de un ordenador desconectado (sin revocar nada:
  /// ya no tiene credencial).
  Future<void> eraseComputer();

  /// Bloquea la sesión ahora.
  Future<void> lock();

  /// Cambia el PIN o la frase: [current] se comprueba contra la guarda antes
  /// de guardar [next] (la interfaz ya comprobó `validPin(next)`).
  Future<WebPinChangeResult> changePin(String current, String next);

  /// Revoca la credencial de este ordenador y borra todo lo guardado en él.
  Future<void> forgetComputer();
}

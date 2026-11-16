import 'dart:async';

/// Cola compartida por las transacciones sobre el estado local de una familia.
/// No es reentrante: dentro de [run] se usan los motores sin volver a tomarla.
/// Un fallo llega al llamador y no impide ejecutar la siguiente transacción.
class V2FamilyLock {
  Future<void> _tail = Future<void>.value();

  /// Toma la cola hasta que termina [transaction], también si lanza un error.
  Future<T> run<T>(Future<T> Function() transaction) {
    final result = _tail.then((_) => transaction());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

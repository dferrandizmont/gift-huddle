/// Resultado de cambiar «Este móvil es de».
enum ChangeSelfPersonResult {
  /// Ficha v2 guardada; otro móvil debe aprobarla. Se publica en la próxima
  /// vuelta de sincronización.
  pendingApproval,

  /// Sin familia v2: solo ha cambiado la identidad local. También en un
  /// móvil solo cuya ficha nunca ha salido de él (1.0.6): la ficha nueva es
  /// la primera y vale sin aprobación.
  localOnly,

  /// La persona ya era esa, no existe, o todavía no hay familia.
  unchanged,
}

/// Se agotaron los cambios de ficha permitidos para este móvil.
class SelfPersonSequenceExhaustedException implements Exception {
  const SelfPersonSequenceExhaustedException();

  @override
  String toString() => 'SelfPersonSequenceExhaustedException';
}

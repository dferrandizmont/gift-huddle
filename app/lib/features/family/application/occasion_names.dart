import '../../../core/sync/model.dart';

/// El nombre que guardan las ocasiones de serie (Tió, Papá Noel, Reyes y los
/// cumpleaños): ninguno. El documento no guarda un texto traducido, porque lo
/// leen móviles en otros idiomas; cada móvil pone el nombre al mostrarlas,
/// según el tipo y, en los cumpleaños, la persona (`occasionTitle`).
const String kSeedOccasionName = '';

/// Las ocasiones fijas que se proponen según la región.
///
/// [region] es un código `ES`, `ES-CT`, `US`... El Tió es de Cataluña; los
/// Reyes, de España; Papá Noel va en todas.
Set<OccasionKind> suggestedOccasionKinds(String region) {
  final code = region.toUpperCase();
  if (code == 'ES-CT') {
    return {OccasionKind.tio, OccasionKind.santa, OccasionKind.kings};
  }
  if (code == 'ES' || code.startsWith('ES-')) {
    return {OccasionKind.santa, OccasionKind.kings};
  }
  return {OccasionKind.santa};
}

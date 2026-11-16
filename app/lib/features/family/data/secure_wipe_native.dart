import 'storage_native.dart' show kSecureStorage;

/// Borra todo lo que la app tiene en el almacén seguro del sistema, con las
/// mismas opciones con las que se escribe ([kSecureStorage]). En iOS borra
/// las entradas del servicio de la app sea cual sea su accesibilidad.
Future<void> wipeSecureStorage() => kSecureStorage.deleteAll();

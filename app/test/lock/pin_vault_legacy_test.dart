// Un `lock.pin` guardado por una versión anterior (PBKDF2-HMAC-SHA256 de
// `cryptography`) se sigue abriendo con su PIN y rechaza otro: el hash lo
// calculó aparte Node (`crypto.pbkdf2Sync('482915', salt, 200000, 32,
// 'sha256')`), así que cambiar la derivación rompe esta prueba.
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/lock/data/pin_vault.dart';

import '../helpers/memory_stores.dart';

const _legacy =
    '{"v":1,"len":6,"alg":"pbkdf2-sha256","iter":200000,'
    '"salt":"AwoRGB8mLTQ7QklQV15lbA",'
    '"hash":"aC_nWZFH04WBqWnkL-oxc0k9CSi2nFxv5LPhumUcDBw"}';

void main() {
  test('a legacy lock.pin opens with its PIN and rejects another', () async {
    final secrets = MemorySecretStore()..values['lock.pin'] = _legacy;
    final vault = PinVault(secrets: secrets, useIsolate: false);
    expect(await vault.pinLength(), 6);
    expect(await vault.verify('482915'), isA<PinOk>());
    expect(await vault.verify('482916'), isA<PinWrong>());
  });
}

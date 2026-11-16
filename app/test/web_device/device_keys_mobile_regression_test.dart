import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';

import '../helpers/memory_stores.dart';

void main() {
  test(
    'mobile identity and surprise keyring still use secure storage',
    () async {
      final secrets = MemorySecretStore();
      final mobile = DeviceKeysStore(secrets, enabled: true);
      final keys = await mobile.create();
      expect((await mobile.read())!.toJson(), keys.toJson());
      await mobile.saveKeyring('family', SurpriseKeyring.empty);
      expect(
        secrets.values.keys,
        containsAll([kDeviceKeysSecret, kSurpriseKeysSecret]),
      );
      expect((await mobile.readKeyring('family')).people, isEmpty);
      await mobile.clear();
      expect(await mobile.read(), isNull);
      expect(secrets.values, isEmpty);
    },
  );
}

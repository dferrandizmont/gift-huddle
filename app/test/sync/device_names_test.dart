import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_names.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

void main() {
  test('names survive serialization, concurrent edits and late delivery', () {
    final base = FamilyDoc.empty('family');
    final a = HlcClock(node: 'aritz-phone');
    final b = HlcClock(node: 'nora-phone');
    final aritz = withDeviceName(base, a, a.node, ' Pixel de Aritz ');
    final nora = withDeviceName(base, b, b.node, 'iPhone de Nora');
    final merged = FamilyDoc.fromJson(aritz.merge(nora).toJson());
    expect(deviceNameIn(merged, a.node), 'Pixel de Aritz');
    expect(deviceNameIn(merged, b.node), 'iPhone de Nora');
    expect(withDeviceName(merged, a, a.node, 'Pixel de Aritz'), same(merged));
    expect(withDeviceName(merged, a, a.node, ' '), same(merged));
    final renamed = withDeviceName(merged, b, b.node, 'Móvil de Nora');
    expect(deviceNameIn(renamed.merge(nora), b.node), 'Móvil de Nora');
    expect(deviceNameIn(base, b.node), isNull);
    final deleted = renamed.delete(b, Collections.meta, 'device:${b.node}');
    expect(deviceNameIn(deleted, b.node), isNull);
    expect(withDeviceName(deleted, b, b.node, 'Móvil de Nora'), same(deleted));
  });
}

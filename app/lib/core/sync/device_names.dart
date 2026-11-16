/// Display names travel inside the encrypted common document, never the
/// public device registry. They are labels and grant no permissions.
library;

import 'family_doc.dart';
import 'hlc.dart';
import 'model.dart';

String? deviceNameIn(FamilyDoc doc, String deviceId) {
  final record = doc.record(Collections.meta, 'device:$deviceId');
  final name = record?['name'];
  if (record?.isDeleted != false || name is! String) return null;
  final clean = name.trim();
  return clean.isEmpty ? null : clean;
}

FamilyDoc withDeviceName(
  FamilyDoc doc,
  HlcClock clock,
  String deviceId,
  String name,
) {
  final clean = name.trim();
  if (clean.isEmpty ||
      doc.record(Collections.meta, 'device:$deviceId')?.isDeleted == true ||
      deviceNameIn(doc, deviceId) == clean) {
    return doc;
  }
  return doc.set(clock, Collections.meta, 'device:$deviceId', {'name': clean});
}

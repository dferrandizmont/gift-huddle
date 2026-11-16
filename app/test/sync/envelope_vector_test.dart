import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';

// Vector fijo para la futura web: la misma clave, nonce y documento deben dar
// siempre este sobre, y la web debe poder descifrarlo. Si cambia la version de
// 'archive' y el deflate sale distinto, regenerar el vector y el JSON del ADR.
const _envelope =
    'UkcBAGB7ImF0IjoiMDAwMWEyYjNjNGQ1LTAwMDMtbm9kby1hcml0eiIsImZyb20iOiJub2RvLWFyaXR6Iiwia2luZCI6ImZhbWlseSIsImwiOiJsaXN0YS0wMDAxIiwidiI6MX2goaKjpKWmp6ipqqtNTrYBDAYv6dDvKYXNNpFsImZtREDmiCdQQyM0AuB6bp47Cavn7Jxud1LLhSMwrjMQscudM_pJzHPyDl5M8YsV0GLeL7AsD8NC32iE';

void main() {
  final key = FamilyKey(List<int>.generate(32, (i) => i));
  final nonce = List<int>.generate(12, (i) => 0xA0 + i);
  final doc = <String, Object?>{
    'items': [
      {'id': 'i1', 'name': 'Muñeca con sombrero'},
    ],
    'v': 1,
  };

  test(
    'seal con clave, nonce y documento fijos da el sobre de referencia',
    () async {
      final bytes = await sealWithNonceForTesting(
        doc: doc,
        listId: 'lista-0001',
        fromNode: 'nodo-aritz',
        at: '0001a2b3c4d5-0003-nodo-aritz',
        key: key,
        nonce: nonce,
      );
      expect(encodeBase64Url(bytes), _envelope);
    },
  );

  test('el sobre de referencia se abre', () async {
    final opened = await open(
      decodeBase64Url(_envelope),
      key: key,
      expectedListId: 'lista-0001',
    );
    expect(opened.doc, doc);
  });

  test('docs/adr/0001-vector-de-prueba.json coincide con la constante', () {
    final file = io.File('../docs/adr/0001-vector-de-prueba.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(json['envelopeBase64Url'], _envelope);
    expect(json['keyBase64Url'], key.toBase64Url());
    expect(json['nonceBase64Url'], encodeBase64Url(nonce));
    expect(jsonDecode(json['documentJson']! as String), doc);
  });
}

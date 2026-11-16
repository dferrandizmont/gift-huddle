// GENERADO desde docs/adr/0005-vector-*.json para las pruebas en el navegador
// (no hay dart:io). x25519_vector_test.dart comprueba que son iguales.
// ignore_for_file: lines_longer_than_80_chars
library;

const kCommonKeyVectors = r'''{
  "about": "ADR 0005, lote B1. Binarios en base64url sin relleno; kid y contexto en hexadecimal. Semillas de las claves de dispositivo: X25519 y Ed25519 (como DeviceKeys.fromSeedsForTesting).",
  "listId": "list-1",
  "syncId": "QUJDREVGR0hJSktMTU5PUA",
  "devices": {
    "aritz-phone": {
      "agreementSeed": "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
      "signingSeed": "ZWVlZWVlZWVlZWVlZWVlZWVlZWVlZWVlZWVlZWVlZWU",
      "agreementPublic": "pOCSkrZRwni5dyxWn1-puxPZBrRqtoyd-dwrRAn4ogk",
      "signingPublic": "1i8Bah79Hk_feT60LNhEceG6nwzwTRKHtcxx9hYofLg",
      "recordDigest": "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI"
    },
    "leo-phone": {
      "agreementSeed": "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI",
      "signingSeed": "ZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmY",
      "agreementPublic": "zo060cy2M-x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk",
      "signingPublic": "NLTZBDFWy23PC-sKKUm3VZyUDSvLbb6MU6mzAnjjp0Y",
      "recordDigest": "M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0"
    },
    "nora-phone": {
      "agreementSeed": "AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM",
      "signingSeed": "Z2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2dnZ2c",
      "agreementPublic": "Xf7dO2vUf2-ijuFdlp1bsOpTd01Ii9r53xxuASSz7yI",
      "signingPublic": "EqQVksi3wX1AWeeym2Ho_5bHQV8vgDNI8vAX4Fueodo",
      "recordDigest": "Nevq7b-GrwRQ3GN5YS0M5P8urc3kbI0o_b4HuCGzOxw"
    }
  },
  "epoch": {
    "domain": "gift-huddle-epoch-context-v2",
    "descriptor": {
      "l": "list-1",
      "m": [
        [
          "aritz-phone",
          "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI"
        ],
        [
          "leo-phone",
          "M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0"
        ],
        [
          "nora-phone",
          "Nevq7b-GrwRQ3GN5YS0M5P8urc3kbI0o_b4HuCGzOxw"
        ]
      ],
      "r": [],
      "sid": "QUJDREVGR0hJSktMTU5PUA",
      "v": 2
    },
    "canonical": "{\"l\":\"list-1\",\"m\":[[\"aritz-phone\",\"tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI\"],[\"leo-phone\",\"M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0\"],[\"nora-phone\",\"Nevq7b-GrwRQ3GN5YS0M5P8urc3kbI0o_b4HuCGzOxw\"]],\"r\":[],\"sid\":\"QUJDREVGR0hJSktMTU5PUA\",\"v\":2}",
    "context": "9702bb2edf902199937d0403a9f39b7c906828ca8b774bd20d1f1008396232d8"
  },
  "candidate": {
    "kidDomain": "gift-huddle-family-kid-v1",
    "creatorDomain": "gift-huddle-family-candidate-v1",
    "json": {
      "v": 1,
      "l": "list-1",
      "sid": "QUJDREVGR0hJSktMTU5PUA",
      "s": "family",
      "e": 1,
      "ctx": "9702bb2edf902199937d0403a9f39b7c906828ca8b774bd20d1f1008396232d8",
      "kid": "1275552b71019f40ae5669f40f8527214cc994c61ae133445ab6a0bcee38ddf2",
      "c": "aritz-phone",
      "cr": "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI",
      "a": [
        [
          "aritz-phone",
          "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI"
        ],
        [
          "leo-phone",
          "M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0"
        ],
        [
          "nora-phone",
          "Nevq7b-GrwRQ3GN5YS0M5P8urc3kbI0o_b4HuCGzOxw"
        ]
      ],
      "cs": "_N41q6Pxkta7Nm2_MQ7wVT-2f01NsUOHdbXejCHa9vxbJzdDTIc7-i1xlIRZWUZY3dZV3MJOQ_ieW8a8m-CxDA",
      "k": "BwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSY"
    }
  },
  "keyBundleV4": {
    "domain": "gift-huddle-key-bundle-v4",
    "ephemeralSeed": "ERERERERERERERERERERERERERERERERERERERERERE",
    "json": {
      "v": 4,
      "l": "list-1",
      "sid": "QUJDREVGR0hJSktMTU5PUA",
      "s": "family",
      "e": 1,
      "ctx": "9702bb2edf902199937d0403a9f39b7c906828ca8b774bd20d1f1008396232d8",
      "kid": "1275552b71019f40ae5669f40f8527214cc994c61ae133445ab6a0bcee38ddf2",
      "c": "aritz-phone",
      "cr": "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI",
      "cs": "_N41q6Pxkta7Nm2_MQ7wVT-2f01NsUOHdbXejCHa9vxbJzdDTIc7-i1xlIRZWUZY3dZV3MJOQ_ieW8a8m-CxDA",
      "from": "aritz-phone",
      "fr": "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI",
      "to": "leo-phone",
      "tr": "M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0",
      "a": [
        [
          "aritz-phone",
          "tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI"
        ],
        [
          "leo-phone",
          "M88Qn8C5KtFt4SiBMVqAVHIQ_FHys9XsdNy0YA5KJn0"
        ],
        [
          "nora-phone",
          "Nevq7b-GrwRQ3GN5YS0M5P8urc3kbI0o_b4HuCGzOxw"
        ]
      ],
      "epk": "e06Qm75__kTEZaIgA31gjuNYl9Me-XLwf3SJLLD3PxM",
      "n": "IiIiIiIiIiIiIiIi",
      "ct": "UT2qD_hEOoRnuufYsXUpN9EPo5sWrdmSSEO9wozOm_SYOyvz4NNYLMNw8MplLUrN",
      "sig": "B0DZUbUPEeGSuVPjZJlPEoWav4KAWQphXdMWHPTOBcLgFaWfKodVbuW-ER3xKDolcxHU9pHIXXVogPYEeTW4BQ"
    }
  },
  "commonEnvelope": {
    "signatureDomain": "gift-huddle-common-v2",
    "contentKey": "HKDF-SHA256(secreto, sal vacía, info = signatureDomain ‖ 0x00 ‖ kid)",
    "documentJson": "{\"v\":1,\"listId\":\"list-1\",\"c\":{\"gifts\":{\"g1\":{\"deleted\":[true,\"004102444800001-0003-aritz-phone\"],\"giverId\":[null,\"004102444800001-0003-aritz-phone\"],\"note\":[null,\"004102444800001-0003-aritz-phone\"],\"plannedCents\":[null,\"004102444800001-0003-aritz-phone\"],\"recipientId\":[null,\"004102444800001-0003-aritz-phone\"],\"status\":[null,\"004102444800001-0003-aritz-phone\"],\"surprise\":[null,\"004102444800001-0003-aritz-phone\"],\"title\":[null,\"004102444800001-0003-aritz-phone\"],\"year\":[null,\"004102444800001-0003-aritz-phone\"]}},\"recipients\":{\"leo\":{\"archived\":[false,\"004102444800001-0001-aritz-phone\"],\"colorIndex\":[1,\"004102444800001-0001-aritz-phone\"],\"name\":[\"Leo\",\"004102444800001-0001-aritz-phone\"]}}}}",
    "header": "{\"ctx\":\"9702bb2edf902199937d0403a9f39b7c906828ca8b774bd20d1f1008396232d8\",\"e\":1,\"kid\":\"1275552b71019f40ae5669f40f8527214cc994c61ae133445ab6a0bcee38ddf2\",\"l\":\"list-1\",\"r\":7,\"s\":\"family\",\"sid\":\"QUJDREVGR0hJSktMTU5PUA\",\"v\":2,\"w\":\"aritz-phone\",\"wr\":\"tlfGbUwdTT7dHVokhuA2dNAYg8Wt2k_cDsD1WPsn3pI\"}",
    "nonce": "MzMzMzMzMzMzMzMz",
    "envelope": "UkcCASN7ImN0eCI6Ijk3MDJiYjJlZGY5MDIxOTk5MzdkMDQwM2E5ZjM5YjdjOTA2ODI4Y2E4Yjc3NGJkMjBkMWYxMDA4Mzk2MjMyZDgiLCJlIjoxLCJraWQiOiIxMjc1NTUyYjcxMDE5ZjQwYWU1NjY5ZjQwZjg1MjcyMTRjYzk5NGM2MWFlMTMzNDQ1YWI2YTBiY2VlMzhkZGYyIiwibCI6Imxpc3QtMSIsInIiOjcsInMiOiJmYW1pbHkiLCJzaWQiOiJRVUpEUkVWR1IwaEpTa3RNVFU1UFVBIiwidiI6MiwidyI6ImFyaXR6LXBob25lIiwid3IiOiJ0bGZHYlV3ZFRUN2RIVm9raHVBMmROQVlnOFd0MmtfY0RzRDFXUHNuM3BJIn0zMzMzMzMzMzMzMzManyJumhcKb59A2hQUK57vNsDaRtqfZRodqW9KqwT2NqWc1ykk---LvH5J07D3pCYir4keWL8A5IfgP1NIvoYjCxmKWzUzqvcyhZufrgrH-rxxYTLRIOcrZ8u3EvzQu47HbJ_5xRobAxia_3otlwP1sURehONb_q0wBhou6IEFZaBaZcX5EoGtnd-lkM1sbQj_OC_7YQNQ6YYTWXANXy5BlrvwPSEQe5yuhBiRanv2bdpLfYQOucz_VklLlhb6H11d-PGeihBfH2UDxcOoND5KV8dt7IUWSI_8ffgnNe1WQDg2Arzyobw9qfKx-pafOCK5SJrtXarUz7JP9PVUw64v8g6jae7l8_R37DpeRNCiscj7XobbCA"
  }
}
''';

const kX25519Vectors = r'''{
  "about": "ADR 0005, B5. X25519 con la clave privada de semilla agreementSeed (hexadecimal). secret null: rechazado (secreto de ceros). Las siete primeras son de orden bajo; las cinco últimas llevan el bit alto, que el RFC 7748 enmascara.",
  "agreementSeed": "0202020202020202020202020202020202020202020202020202020202020202",
  "agreementPublic": "ce8d3ad1ccb633ec7b70c17814a5c76ecd029685050d344745ba05870e587d59",
  "control": {
    "public": "a4e09292b651c278b9772c569f5fa9bb13d906b46ab68c9df9dc2b4409f8a209",
    "secret": "2ed76ab549b1e73c031eb49c9448f0798aea81b698279a0c3dc3e49fbfc4b953"
  },
  "points": [
    {
      "public": "0000000000000000000000000000000000000000000000000000000000000000",
      "secret": null
    },
    {
      "public": "0100000000000000000000000000000000000000000000000000000000000000",
      "secret": null
    },
    {
      "public": "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
      "secret": null
    },
    {
      "public": "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
      "secret": null
    },
    {
      "public": "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "secret": null
    },
    {
      "public": "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "secret": null
    },
    {
      "public": "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "secret": null
    },
    {
      "public": "cdeb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b880",
      "secret": "b575257f865030758a0fd7e49333e444caeb9f2a0110f65177fbf577db62ed13"
    },
    {
      "public": "4c9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f11d7",
      "secret": "4cecba515b67885378ca894eca461bd9e579de4a925f96824d29422538a97031"
    },
    {
      "public": "d9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "secret": "0f94e8abc88ec11029245097936ced3d61506387e8f2923c60324f2319d0f563"
    },
    {
      "public": "daffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "secret": "0cc2395f22a3d710a0baebd615f7a72338db77354739665b4c6a27356753fd43"
    },
    {
      "public": "dbffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "secret": "d3af98d8f3a737837da1e66ee5d59367afb9b8f3916b4df907f9432edd52003f"
    }
  ]
}
''';

# Inter (fuente de la app)

- Proyecto: Inter, by The Inter Project Authors (https://github.com/rsms/inter)
- Versión: 4.1 (última release estable, publicada el 2024-11-16)
- Descarga: https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
- Descargado: 2026-11-12
- SHA-256 del ZIP (`Inter-4.1.zip`, 33 707 794 bytes): `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e`
- Origen en el ZIP: `extras/ttf/` (TTF estáticos), `LICENSE.txt`
- Licencia: SIL Open Font License 1.1 (`LICENSE.txt` en esta carpeta)

## Ficheros

| Fichero | Peso | SHA-256 |
|---|---|---|
| `Inter-Regular.ttf` (400) | 411 640 B | `40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82` |
| `Inter-Medium.ttf` (500) | 417 300 B | `97ad806f526e41546d46365bb3a393145f75b7b1568913db74549ad8b8dba872` |
| `Inter-SemiBold.ttf` (600) | 419 744 B | `78a843fade9d4612a5567302fb595b56976eb5fcebf4fea5a5912d638bafcde3` |
| `Inter-Bold.ttf` (700) | 420 428 B | `288316099b1e0a47a4716d159098005eef7c0066921f34e3200393dbdb01947f` |
| `LICENSE.txt` | 4 380 B | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |

Se declaran en `app/pubspec.yaml` bajo `flutter: fonts:` con la familia `Inter`.
No se cargan por red ni con `google_fonts`: van dentro de la app.

## Actualizar

1. Descargar el ZIP de la nueva release y comprobar su SHA-256 contra la página de releases.
2. Copiar los cuatro `extras/ttf/Inter-*.ttf` y el `LICENSE.txt` a esta carpeta.
3. Poner aquí la versión, la URL, la fecha y los SHA-256 nuevos.
4. Revisar que la licencia sigue siendo OFL 1.1.

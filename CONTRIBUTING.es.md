# Contribuir a Gift Huddle

[English](CONTRIBUTING.md) · Español

Describe el problema, el comportamiento esperado y la verificación en tu PR.
Limita los cambios y usa datos inventados (Aritz, Nora y Leo).
Comunica problemas de seguridad según [SECURITY.md](SECURITY.md).

## Compilar y probar

Usa Flutter 3.47.7, con Android SDK o macOS y Xcode para iOS.

```sh
cd app && flutter pub get && flutter gen-l10n && dart run build_runner build -d && flutter test
```

Ejecuta también `flutter analyze` desde `app/`. La firma de release lee un
fichero local `key.properties` que no está en el repositorio; usa builds debug.

El Worker de Cloudflare necesita Node.js 22 y pnpm 10:

```sh
cd server && pnpm install && pnpm test
```

## Reglas del proyecto

- Sin cuentas ni analítica. No introduzcas seguimiento ni datos personales.
- Los textos de interfaz van en ARB: español como fuente, catalán e inglés
  (`app/lib/l10n/`).
- La sincronización fusiona por campo con relojes lógicos y borrados mediante
  lápidas. Los cambios del modelo incluyen pruebas en `app/test/sync`.
- `app/` contiene Flutter, `server/` el Worker y `docs/adr/` las decisiones.
- No incluyas claves ni credenciales de release en los PR.
- Haz commits con el nombre y la dirección que quieras, pero sin dirección
  Gmail ni Googlemail (CI las rechaza en commits, etiquetas y ficheros); los
  commits del mantenedor deben usar `dev@mainshai.com`.

Al enviar un PR aceptas publicar tu contribución bajo GPL-3.0-or-later,
según [LICENSE](LICENSE).

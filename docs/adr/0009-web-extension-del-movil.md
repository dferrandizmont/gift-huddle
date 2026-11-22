# ADR 0009 · La web, extensión del móvil de su persona (1.0.6)

Estado: aceptada (implementada en `fix/web-secretos-106`). Diseño completo: revisión de diseño de la 1.0.6, apartado A. Completa los ADR 0003 (W3, §8) y 0004.

## Decisión

- **W5.** Una web W lee las sorpresas de P si un móvil E de su misma persona (`E.person == W.person`), con derecho a P y que avaló la ficha actual de W, le entrega la clave. El predicado nuevo es `RegistryView.ownWebs()`. `entitled`, `relayable`, `selfApproved` y `changePerson` no cambian.
- **Paquete:** el `KeyBundle` v3 de siempre, con `to = W`. La audiencia de la candidata no se toca. En la cabecera del paquete va la audiencia más W, porque un paquete siempre nombra a su destinatario. La web lo abre con `openSurpriseKeyAsWeb`, usando la vista de una raíz móvil de su persona. Como ningún móvil de X tiene la clave de X, la web de X nunca la recibe.
- **Claves solo en memoria** (`WebSecrets`): se rehacen en cada desbloqueo. Con sorpresas abiertas, la web se bloquea a los 5 minutos sin uso.
- **Escritura (buzón en forma de slot):** la web sella un `SealedSlot` con sus cambios pendientes de P (`buildWebInbox`) y lo sube con `PUT S/slots/{P}/{W}`. Solo lo recogen los móviles de su persona (`absorbWebInbox`), con estas reglas:
  - todo o nada: como mucho 40 registros y 10 lápidas, ninguna marca del futuro y ningún registro ajeno;
  - un alta (`webNew`) entra solo si el id no existe;
  - una edición o un borrado se aplica solo a un id vivo;
  - como mucho 20 lápidas al día;
  - cada móvil guarda la última recogida por (P, W), y el slot propio la declara en `s[W]`.

  El buzón nunca entra en `SlotSet`. Los demás móviles lo ignoran (`IgnoredSlotReason.webInbox`; un 1.0.5 lo rechaza con `relayable` y lo vuelve a bajar mientras exista).
- **Confirmar en la web:** una entrada está recogida cuando un slot de un móvil de su persona ya la contiene o declara `s[W]` ≥ un buzón que la llevaba. Sin entradas, la web borra su fila.
- **Worker:** `PUT S/slots/{persona}/{dispositivo}` solo para la web y su propio id, con `If-Match`. Como mucho `V2_MAX_WEB_SLOTS = 8` slots por web, que cuentan en el tope de la lista. Revocar la web borra sus filas en el acto.
- **Capa de pantalla de la web:** se calcula con su propio id y su persona (`screenView`). La raíz móvil solo verifica firmas.
- **Emparejar la web:** hereda la persona del móvil y pasa por el mismo intento obligatorio de proteger a su persona que un móvil.

## Fuera (1.0.7)

- Cambiar un regalo de persona desde la web cuando alguien está protegido: se aparta y se hace desde el móvil.
- Recoger desde cualquier móvil con derecho, no solo los de la persona de la web.
- Claves no extraíbles de WebCrypto.
- Caducar los buzones abandonados.

## Riesgos aceptados

- Un ordenador compartido con la sesión abierta enseña los secretos de los demás. Lo cubren el bloqueo de 5 minutos y el aviso.
- Un XSS con la caja abierta puede leer y escribir los secretos de los demás, pero no los de X. Lo que escriba pasa por el móvil de X y por los topes.
- El manifiesto deja ver que la web de X tocó las sorpresas de P, y cuándo.
- **Aprobar una web entrega claves (B9 de la revisión de seguridad).** Avalar desde el móvil de X la ficha de una web que dice ser de X la mete en `ownWebs()`: una web que otro emparejó «para X» o cuya ficha cambió a X vería las sorpresas de los demás en cuanto X la confirme. No es más débil que aprobar un cambio de persona de un móvil. El diálogo de aprobar debe decirlo: «podrá ver y cambiar los regalos en secreto de los demás; confírmalo solo si lo conectaste tú». Es tarea de las pantallas.
- **Vaciar sin borrar (B8).** El freno diario cuenta lápidas, no ediciones: una web comprometida puede dejar en blanco hasta 40 regalos por buzón editando sus campos. Es lo mismo que puede un móvil comprometido; un freno real sería contar los registros recogidos por día (1.0.7 si hace falta).
- **Épocas anteriores.** El móvil solo entrega a la web las claves de la época actual. Tras una rotación, la web no abre los slots que aún no se han vuelto a sellar. Como cada slot es acumulativo, dura poco.

## Después de la revisión de seguridad

- M2: un paquete por (web, ficha, persona, época, `kid`), recordado en `V2SyncState.webShares`; se vuelve a emitir si desaparece. En la web, una persona sin ningún slot legible no cuenta como abierta: se ve su bloque.
- M3: si el Worker rechaza el buzón (tope, tamaño, renovación, un Worker sin la ruta), ese buzón espera 10 minutos y el común se sigue publicando. Hay que desplegar el Worker antes que la web.
- M4: el bloqueo se vuelve a calcular en cuanto se abren los secretos.
- B1: la última recogida se siembra también desde `s[web]` del slot propio y no se borra mientras la web siga en el registro.
- B2: un buzón que espera no obliga a publicar, y se vuelve a bajar como mucho una vez por hora (`kWebInboxRetry`).
- B3: también la revocación firmada de la renovación borra los buzones en el acto.
- B4: con un escritor ilegible, el buzón espera.
- B5: la persona con un buzón recogido sigue en `deferred` hasta que su slot entra.
- B6: al recoger se ignoran `webNew`, `movedIn` y `publishSalt`.
- B7: las escrituras del buzón no gastan intentos, la última revisión de cada persona se conserva, y un alta se mide con `webNew`.

## Revisión de seguridad final de `int/106`

- M1: la capa de pantalla de la web oculta también las personas de todas las fichas del móvil que avaló su ficha siendo de su persona (`webPhonePeople`). Si ese móvil cambia de persona, la web no pinta ni la de antes ni la nueva.
- M2: `sync-gh.mainshai.com` es el nombre definitivo de la reserva y un compromiso permanente (va en los binarios de tienda). La zona no se suelta, y lleva la misma WAF, TLS mínimo, sin registros, CAA y bloqueo de registrador.
- B1: el invitado 1.0.6 manda `hp` en su respuesta. El anfitrión que eligió la persona no gasta la respuesta de un 1.0.5 (`PairingGuestOutdatedException`) y no deja una credencial fantasma.
- B5: «solo regala» se salta la protección únicamente si en el común no hay ningún regalo vivo para esa persona (`nothingToProtectFor`), y eso mismo se comprueba en el checkpoint exacto.
- B8, decidido: no se arregla en la 1.0.6. La ficha del invitado ya llega al registro del servidor durante `confirm` (la vuelta de sincronización que fija el checkpoint). Para no contarla habría que llevar una lista local duradera por todas las decisiones de compañía y purga (capa, protección, las dos generaciones), sin poder distinguir siempre si la aprobación llegó a entrar. Se acepta. El texto del fallo de aprobar debe decir que, tras un intento fallido, este móvil sigue ocultando lo suyo (pantallas).

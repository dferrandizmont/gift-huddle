# ADR 0010 · Deseos propios y sorpresas por regalo

Estado: aceptada, alcance recortado (decisiones de producto de Daniel, 2026-11-23; 1 a 6, 8, 9 y la versión mínima, confirmadas el mismo día). Diseño técnico pendiente de revisión. Sale en la 1.0.7, en Android e iOS a la vez. Cambia el ADR 0004 (sorpresas) y el ADR 0009 (web).

## Por qué

Hoy, cuando una persona tiene móvil, todos sus regalos van al bloque secreto y su móvil no ve ninguno. Pero cada persona también apunta cosas que quiere que le regalen: esas ya las conoce, porque las ha escrito ella. Ocultarlas no protege nada y le quita a la app un uso natural: hacer tu propia lista de deseos.

## Decisiones de producto (2026-11-23)

1. **Deseo propio:** un regalo que la persona P apunta para sí misma es un **deseo**. P lo ve y lo edita como lo escribió.
2. **Lo que hacen los demás con un deseo no se ve en el móvil de P:** quién lo regala, el estado (decidido, comprado…), los precios, la tienda y las notas de quien regala van ocultos. Para P, su deseo sigue igual para siempre, aunque ya esté comprado. Los demás ven que está cogido, para no comprarlo dos veces.
3. **Si P borra un deseo que alguien ya ha cogido,** a quien lo cogió le queda su regalo con el aviso «Nora lo quitó de su lista». Nada se pierde.
4. **Lo que otro apunta para P es sorpresa por defecto.** Al crearlo puede elegir «Visible para Nora»; entonces P lo ve como un deseo más (contenido visible, lo que hagan los demás con él, oculto, igual que en 2).
5. **Sección «Sorpresas» siempre visible** en los dispositivos de P (móvil y web), desde que se une, haya o no algo dentro: un bloque fijo, sin número, sin fechas ni ocasión. Si solo apareciera con algo dentro, su ausencia diría que no hay nada.
6. **Lo que ya existe sigue oculto.** Hoy no se guarda quién escribió cada regalo: todos los regalos actuales de una persona protegida siguen en su bloque secreto. Solo lo que P apunte desde la 1.0.7 será deseo.
7. **No se destapa después de la ocasión** (propuesta del líder, a confirmar por Daniel): destaparlo enseñaría precios y quién regaló qué, y obliga a publicar regalos ya cifrados. Si se echa de menos, se estudia aparte.
8. **Niños con móvil:** lo mismo que un adulto. Sin móvil (Leo), nada cambia: no hay protección.
9. **La web de P se comporta como el móvil de P:** ve y edita sus deseos, no sus sorpresas. La web de otro sigue viendo y editando las sorpresas de P (ADR 0009, W5).

## Lo que no puede pasar

- Ninguna acción de otro sobre un deseo (cogerlo, cambiar el estado, ponerle precio, editarlo, borrarlo de su lado) cambia nada que el móvil o la web de P puedan leer o medir: ni el registro del deseo, ni su reloj, ni el orden, ni el tamaño de lo que P recibe.
- La sección «Sorpresas» no depende de si hay sorpresas.
- Presupuesto, buscador, totales, Reparto y exportaciones legibles del dispositivo de P no cuentan lo oculto (como hoy).
- Un móvil en la 1.0.6 no puede mover un deseo al bloque secreto (hoy la reconciliación pasa al bloque secreto todo regalo público de una persona protegida) ni perderlo. Decidido: la unión y la sincronización entre 1.0.6 y 1.0.7 se cortan como en la 1.0.6 («los dos móviles necesitan la última versión»).
- Cualquier cambio del modelo pasa por `test/sync` (regla del repo).

## Preguntas para el diseño técnico

- Cómo se guarda un deseo: ¿colección nueva en el documento común (que un móvil antiguo conserva sin entender), o un campo en el regalo? Qué hacen con ella las fusiones, las lápidas, la compactación y `publishableCommon`.
- Cómo se guarda «lo que hacen los demás»: registro en el bloque secreto que apunta al deseo; cómo se enlaza sin que el enlace se vea fuera del bloque.
- Quién puede editar el contenido visible de un deseo: solo su autor, o también los demás sabiendo que P lo verá.
- Pasar un regalo de oculto a visible para P y al revés, con las reglas del lote 6 (ids nuevos al publicar).
- Cómo se marca el autor sin depender de lo que diga el propio móvil (registro firmado, `DeviceResolver`).
- Compatibilidad con la 1.0.6 y la web antigua, y versión mínima.
- Topes: deseos por persona, tamaño del documento común.

## Alcance decidido (2026-11-23, tras el diseño técnico)

Base: la opción A de `0010-diseno-astra.md`. Recortes y decisiones:

- **En la app, los deseos salen con los regalos normales** de la persona (una sola lista a la vista). Por dentro se guardan aparte: colección `wishes` en el común y `wishPlans` dentro del bloque secreto. Guardarlos como un campo del regalo (opción B) haría que un móvil 1.0.6 los pasara al bloque secreto y que coger un deseo cambiara el registro que ve P.
- **Sin ritmo fijo de transporte** (fase 4 del diseño técnico fuera): se mantiene el resellado inmediato. Que se vea en el tráfico de red que un bloque cambió queda como límite aceptado, igual que en el lote 6. Daniel: «nadie se pondrá a sniffar la red».
- **Sin firmas por campo:** el autor de un deseo es la persona aprobada del dispositivo que lo crea, según el registro de móviles. Solo esa persona (P) edita o quita el contenido visible de sus deseos; la app de los demás no lo permite. Una app modificada por un familiar no está en el modelo de amenazas.
- **Sugerencia «Visible para Nora»:** quien la apunta la crea; desde entonces solo Nora la edita o la quita. Quien la sugirió solo cambia su plan.
- **Corte de versión:** al emparejar (capacidad nueva en oferta y respuesta, móvil y web) y en los ficheros (discriminador exterior). Sin suelo en el Worker: un 1.0.6 conserva `wishes` sin entenderlos y no puede crear planes.
- **Tope:** 200 deseos vivos por persona.
- **No se destapa** después de la ocasión.
- **Fases:** 1) corte de versión; 2) modelo `wishes` y autor; 3) `wishPlans`, coger, soltar, conflictos, «lo quitó de su lista»; 4) fronteras (común publicable, exportaciones, búsqueda, presupuesto, Reparto, web); 5) interfaz (subagente Sonnet high).

## Borrado de una persona (2026-11-26)

Al borrar a una persona, sus deseos reciben lápidas aunque quien borre no sea su titular. Es parte de la cascada de una operación ya autorizada sobre la persona, igual que el borrado de sus regalos. Las operaciones individuales de edición y retirada de deseos siguen reservadas a su titular.

## Límites de la web en la 1.0.7 (2026-11-23)

- La web de otra persona coge, edita y suelta un deseo de P (W5), pero no sugiere deseos visibles («Visible para…»), no convierte una reserva en sorpresa ni la borra: esos controles no salen en la web. «Borrar mi reserva» suelta la reserva.
- En la web, un deseo cogido sale como deseo con su estado (no como la reserva), también en la búsqueda.

## Familias con móviles de la 1.0.6 y de la 1.0.7 (revisión de seguridad, 2026-11-23)

Sin suelo en el Worker, una familia emparejada antes de actualizar sigue sincronizando con móviles de las dos versiones. Un 1.0.6 abre los slots de móvil que llevan planes pero descarta los planes (`scopeDocOnly`), y rechaza entero el buzón de una web que los lleva (cuenta cualquier colección que no sea `gifts` como ajena), regalos incluidos.

- **Capacidad por móvil («wp»).** Todo slot y todo buzón que sella la 1.0.7 anuncia `"wp": 1` en el cuerpo cifrado y firmado, junto a «cap». No puede ir en la cabecera: un 1.0.6 rechaza cualquier cabecera que no sea la suya (`flags > 1`, tamaño exacto) y sí ignora las claves desconocidas del cuerpo (comprobado con el fixture `protected_envelope_v106.dart`). Un móvil sin «wp», o del que no hay slot abierto, cuenta como que no entiende los planes.
- **Cuándo se escriben planes.** Coger, editar, soltar, borrar o convertir un plan solo se hace si todos los demás móviles con derecho a leer el bloque (`entitledDevices`) anuncian «wp» (`wishPlansAllowed`); si no, error tipado `WishPlanError.devicesNeedUpdate` («Actualiza los demás móviles») y no se escribe ni se encola nada. La web aplica la misma regla con los slots que lee. El móvil que recoge un buzón con planes sin que todos los anuncien lo deja esperando (no lo rechaza ni lo recoge).
- **Borrado de un regalador.** Si quitar su asignación de un plan requiere escribir en un ámbito con algún lector sin «wp», se devuelve `WishPlanError.devicesNeedUpdate`. El común y todos los ámbitos afectados se guardan juntos cuando se puede aplicar la cascada completa.
- **Planes y regalos nunca comparten buzón.** La web sella primero el buzón de regalos y solo cuando no queda ninguno por entregar, el de planes; así un rechazo no se lleva ediciones de regalos.
- **Solo cuenta lo que el móvil recogió.** La web busca en el historial la revisión exacta que declara el móvil (`s[web]`). Las entradas de un buzón sustituido antes de su recogida se vuelven a ofrecer. Para un buzón con planes, la declaración lleva además `ps[web]` con la misma revisión, emitida al abrir el buzón con soporte para planes. La recogida transitiva copia esa marca y el rechazo (`x`) con la revisión a la que pertenecen. Actualizar un móvil que conserva un `s[web]` antiguo no añade la marca.
- **Un buzón rechazado no es un buzón entregado.** Un móvil 1.0.7 que rechaza un buzón entero lo declara en su slot (`"x"`), además de `s[web]`; la web da entonces sus entradas por descartadas con aviso, no por entregadas.
- **Un plan que llega antes que su deseo** (el móvil aún no tiene el común de la web) deja el buzón esperando; **si el deseo ya es una lápida**, el plan entra con su título copiado y sale como «quitado de la lista».
- **Web antigua en la misma caja:** los cambios privados se guardan en la cola con `aside: true` (la 1.0.6 los aparta) y la 1.0.7 los encamina por su clase. El común que la web guarda, publica o instala al emparejarse pasa por `wishBoundary()`.
- **Tras restaurar**, el suelo del reloj público sale solo de datos públicos; los ámbitos privados conservan sus propias marcas.
- **Respuesta de emparejamiento:** el Worker comprueba que el `sv` firmado en la respuesta es el verificador con el que se registra la credencial; las respuestas de la 1.0.6 (sin `sv`) se aceptan como antes.

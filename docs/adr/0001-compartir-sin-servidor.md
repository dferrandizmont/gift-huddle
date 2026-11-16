# ADR 0001 · Compartir la lista entre móviles sin cuentas ni servidor

Fecha: 2026-11-09. Estado: aceptada (se aprobó el modelo «QR en persona + enlaces sin clave»).

## Contexto
Dos adultos de la misma casa tienen que ver la misma lista; los abuelos y tíos, solo una parte. Sin cuentas, sin login de Google, sin servidor en la fase 1 (la especificación de producto §3.6). El texto original ponía la clave dentro de cada enlace (`#k=...`), con lo que cualquiera que viera el enlace podía leer la lista.

## Decisión
1. **Clave de la familia.** El primer móvil genera una clave aleatoria de 256 bits y un identificador de lista. Se pasa al segundo móvil **una sola vez, por QR en persona** (sobre de emparejamiento: id de lista, clave, nombre del dispositivo). Nunca viaja por mensajería.
2. **Sobres de cambios.** Cada «Enviar» empaqueta el estado (o lo cambiado) como JSON → compresión **deflate en bruto** → cifrado **AES-256-GCM** con la clave de la familia (nonce aleatorio de 96 bits, datos asociados = cabecera del sobre) → base64url. Viaja como enlace (`https://<dominio>/s#<sobre>`) o como fichero `.regalos` por la hoja de compartir. **El sobre no lleva la clave**: interceptado no sirve.
3. **Enlace de solo lectura (fase 2).** Proyección filtrada (lo que ese regalador puede ver), cifrada con una clave propia de esa vista que sí va en el fragmento `#`; el servidor de la web nunca ve el fragmento. Se revoca rotando la clave de esa vista.
4. **Fusión.** Cada entidad tiene id UUID v4; cada campo, su marca de un **reloj lógico híbrido** (milisegundos, contador, id de dispositivo), comparada en ese orden. Gana la marca mayor por campo. La fusión es conmutativa, asociativa e idempotente.
   - **Borrados (actualizado el 2026-11-12).** Un borrado es una lápida y es **final**: en `deleted`, `true` gana a cualquier otro valor aunque su marca sea más vieja, así que ninguna edición la deshace. Al borrar, el registro vacía el resto de sus campos (valor `null`, con una marca nueva, para que el vaciado viaje y gane también en los móviles antiguos). Un registro que acaba borrado pierde el valor de todos sus campos al fusionar (conservan su marca), de modo que una edición concurrente o posterior en otro móvil no lo resucita ni vuelve a dejar su contenido legible. Las lápidas de versiones anteriores, que conservaban el contenido, se vacían al cargar y al fusionar, y se vuelven a borrar con el reloj de ahora para que el vaciado gane por marca. Consecuencia: «nada se pierde» ya no cubre las ediciones concurrentes de un registro borrado; ganan los borrados. La versión del documento y del sobre no cambia.
   - **Sin huérfanos.** Un regalo cuya persona es una lápida, y el cumpleaños de esa persona, no se muestran (`FamilyView.fromDoc`); no se escribe nada y se corrige solo. Guardar un regalo de una persona ya eliminada no escribe nada.
   - **Borrar un regalo con «Deshacer».** La lápida del regalo no se escribe hasta que caduca el aviso con «Deshacer» (el contenido sigue en el documento, en memoria, y solo se oculta de la vista) o la app pasa a segundo plano. Así «Deshacer» es posible aunque la lápida sea final.

## Por qué así
- AES-GCM y deflate-raw existen nativos en el navegador (WebCrypto y `DecompressionStream('deflate-raw')`), así que la página web de solo lectura descifra sin bibliotecas. XChaCha20 y brotli/zstd, que proponía el texto original, no.
- El reloj lógico híbrido evita que un móvil con la hora mal gane siempre o pierda siempre.

## Consecuencias
- Hasta tener dominio, el transporte práctico es el fichero `.regalos` y el enlace con un dominio provisional; el códec no depende del transporte.
- Si un QR no basta para un sobre grande, se usa el fichero o el enlace; el QR solo se usa para emparejar.
- La sincronización automática (fase 3, Worker + KV) reutiliza los mismos sobres cifrados.

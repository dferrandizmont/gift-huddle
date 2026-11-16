// Guarda contra un fallo de dart2wasm (Flutter 3.47) que paró la web 1.0.1:
// con `Pbkdf2`, `Hkdf` y `Argon2id` de `cryptography` en el mismo programa,
// el selector `deriveKey` se queda sin destino y el compilador cambia la
// llamada por `unreachable` (ver lib/core/sync/hkdf.dart y
// lib/features/web_device/data/vault_pbkdf2_web.dart).
//
//   sh tool/check_wasm_unreachable.sh            # compila, vuelca y comprueba
//   node tool/check_wasm_unreachable.mjs <main.wat> [--write-baseline]
//
// Sencilla y sin heurísticas de flujo:
//  1. Lee el volcado de `wasm-opt --print` entero, con los paréntesis
//     equilibrados hasta el final, y exige haber leído todas las funciones
//     (las mismas que cabeceras `(func` hay) y al menos una de la app. Si no,
//     falla.
//  2. En cada función de la app (clases y funciones de `lib/`), cuenta los
//     `(unreachable)` que no van justo detrás de un terminador (`throw`,
//     `throw_ref`, `rethrow`, `br`, `br_table`, `return…`, `unreachable`) ni de
//     una llamada a una función `Never` revisada (`neverReturn`, que se
//     comprueba: existe y no devuelve nada). El primero de un bloque también
//     cuenta.
//  3. Compara ese recuento con `tool/wasm_unreachable_baseline.json`,
//     revisado a mano (una línea de motivo por función). Una función nueva o
//     un número mayor que el de la línea base hace fallar la guarda. Si baja,
//     lo dice para que se actualice.
// Con --write-baseline reescribe la línea base con lo que encuentra,
// conservando los motivos que ya había; las entradas nuevas quedan con
// motivo "REVIEW" y la guarda falla hasta que alguien las revise.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const writeBaseline = args.includes('--write-baseline');
if (!file) {
  console.error('uso: node tool/check_wasm_unreachable.mjs <main.wat> [--write-baseline]');
  process.exit(2);
}
const here = path.dirname(fileURLToPath(import.meta.url));
const baselineFile = path.join(here, 'wasm_unreachable_baseline.json');

const TERMINATORS = new Set([
  'throw', 'throw_ref', 'rethrow', 'br', 'br_table', 'return',
  'return_call', 'return_call_ref', 'return_call_indirect', 'unreachable',
]);

/** Funciones revisadas cuyo tipo Dart es `Never`: lanzan y no vuelven. */
const neverReturn = new Set([
  // SDK (dart2wasm).
  'Error._throw',
  'Error._throwWithCurrentStackTrace',
  'Error.throwWithStackTrace',
  'Object._invokeNoSuchMethod',
  '_throwErrorWithoutDetails',
  '_TypeError._throwNullCheckErrorWithCurrentStack',
  '_throwIndexError',
  '_throwRangeError',
  '_throwLateErrorFieldADI',
  '_throwLateErrorFieldAI',
  '_throwLateErrorFieldNI',
  '_throwLateErrorLocalADI',
  '_throwLateErrorLocalAI',
  '_throwLateErrorLocalNI',
  // riverpod.
  'throwProviderException',
  // App.
  '_badCapsule', // recovery_capsule.dart
  '_invalid', // recovery_file.dart
  'SyncV2Client._inviteFail', // sync_transport_v2.dart
  'SyncV2Client._fail', // sync_transport_v2.dart
  'BaseSyncTransport._fail', // sync_transport_common.dart
  'WebSyncController._deny', // web_sync_controller.dart
]);

// Los nombres de la app: clases, mixins, enums, extension types y funciones
// de primer nivel de lib/.
const lib = path.join(here, '..', 'lib');
const appNames = new Set();
for (const entry of fs.readdirSync(lib, { recursive: true })) {
  if (!String(entry).endsWith('.dart')) continue;
  const source = fs.readFileSync(path.join(lib, String(entry)), 'utf8');
  for (const m of source.matchAll(/^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*(?:class|mixin|enum|extension type)\s+(\w+)/gm)) appNames.add(m[1]);
  for (const m of source.matchAll(/^(?![ \t])(?!(?:import|export|part|library|class|enum|mixin|typedef|extension|abstract|final|sealed|const|var)\b)[\w<>?, ]+?\s(\w+)\s*\(/gm)) appNames.add(m[1]);
}
function isApp(fn) {
  if (fn.includes('package:regalos/')) return true; // closures carry their file
  return appNames.has(fn.replace(/^new /, '').split(/[ .]/)[0]);
}
const unescape = (name) => name.replace(/\\20/g, ' ');
// Closure names carry the checkout path (`file:///…/app/lib/x.dart:12:3`):
// the baseline uses `package:regalos/x.dart` (no path, no line), so another
// checkout, or an edit elsewhere in the file, keeps the same key.
const normalize = (name) =>
  unescape(name).replace(
    /file:\/\/\/\S*?\/app\/lib\/(\S+?\.dart)(:\d+:\d+)?(?=[\s)]|$)/g,
    'package:regalos/$1',
  );

function fail(message) {
  console.error(message);
  process.exit(1);
}

// --- 1. Parse the whole dump. Strings and comments are skipped so their
// parentheses do not count; every `(func` at module level must close.
const text = fs.readFileSync(file, 'utf8');
// Defined functions start their own line; imports (`(import … (func $…))`)
// have no body and are not counted.
const headers = (text.match(/^[ \t]*\(func\s+\$/gm) ?? []).length;
const functions = []; // { name, node }
{
  const re = /\(|\)|"(?:[^"\\]|\\.)*"|;;[^\n]*|[^\s()";]+/g;
  const stack = [];
  let m;
  while ((m = re.exec(text))) {
    const t = m[0];
    if (t === '(') {
      const node = { head: null, atoms: [], kids: [] };
      if (stack.length) stack[stack.length - 1].kids.push(node);
      stack.push(node);
    } else if (t === ')') {
      const node = stack.pop();
      if (!node) fail('unbalanced parentheses: a `)` closes nothing');
      if (stack.length === 1) {
        if (node.head === 'func' && node.atoms[0]?.startsWith('$')) {
          functions.push({ name: normalize(node.atoms[0].slice(1)), node });
        }
        stack[0].kids.length = 0; // keep only the functions in memory
      }
    } else if (t.startsWith('"') || t.startsWith(';;')) {
      // A string or a comment: no structure.
    } else {
      const top = stack[stack.length - 1];
      if (!top) continue;
      if (top.head === null) top.head = t;
      else top.atoms.push(t);
    }
  }
  if (stack.length !== 0) fail(`unbalanced parentheses: ${stack.length} still open at the end`);
}
if (headers === 0 || functions.length !== headers) {
  fail(`parsed ${functions.length} functions but the dump has ${headers} \`(func\` headers`);
}
const byName = new Map(functions.map((f) => [f.name, f.node]));
for (const name of neverReturn) {
  const node = byName.get(name);
  if (node && node.kids.some((k) => k.head === 'result')) {
    fail(`neverReturn: ${name} returns a value; review the list`);
  }
}
const app = functions.filter((f) => isApp(f.name));
if (app.length === 0) fail('no app (package:regalos) function: built with --no-strip-wasm?');

// --- 2. Count the `unreachable`s not right after a terminator.
function stopsBefore(prev) {
  if (!prev) return false; // first of its block: counts
  if (TERMINATORS.has(prev.head)) return true;
  return prev.head === 'call' && neverReturn.has(unescape((prev.atoms[0] ?? '').slice(1)));
}
/** What comes before a counted `unreachable`, for the baseline's reason. */
function kindOf(prev, parent) {
  if (!prev) return `first in ${parent.head}`;
  if (prev.head === 'drop' && prev.kids[0]?.head === 'call' && prev.kids[0].atoms[0] === '$State.widget') return 'widget';
  if (prev.head === 'call') return `call ${unescape((prev.atoms[0] ?? '').slice(1))}`;
  return prev.head;
}
// Type annotations are not instructions: the one before `unreachable` is
// the previous instruction, or none (first of its block or function).
const ANNOTATIONS = new Set(['param', 'result', 'type', 'local', 'export', 'import']);
function previousInstruction(node, i) {
  for (let j = i - 1; j >= 0; j--) {
    if (!ANNOTATIONS.has(node.kids[j].head)) return node.kids[j];
  }
  return undefined;
}
function count(node, kinds) {
  let n = 0;
  node.kids.forEach((k, i) => {
    const prev = previousInstruction(node, i);
    if (k.head === 'unreachable' && !stopsBefore(prev)) {
      n++;
      const kind = kindOf(prev, node);
      kinds.set(kind, (kinds.get(kind) ?? 0) + 1);
    }
    n += count(k, kinds);
  });
  return n;
}
const found = new Map();
const kindsOf = new Map();
for (const { name, node } of app) {
  // Closures of one file may share a normalised name: their counts add up.
  const kinds = kindsOf.get(name) ?? new Map();
  const n = count(node, kinds);
  if (n > 0) {
    found.set(name, (found.get(name) ?? 0) + n);
    kindsOf.set(name, kinds);
  }
}

// Reasons reviewed once per kind: dart2wasm/binaryen leave `unreachable`
// after a `try`/`loop`/`block`/`if` whose every path already returned,
// branched away or threw (the lowering of `async`, `try`/`catch` and
// exhaustive `switch`), after the last `br_if` of an exhaustive `switch`,
// as the first instruction of a block no path falls into, and in the body of
// widgets the web never creates (`drop (State.widget)`). Anything else (a
// plain call, a `drop` of a call, a `local.set`…) is how the `deriveKey`
// bug looked: it stays "REVIEW" and fails until a person writes its reason.
// A function whose body starts with `unreachable` is one the compiler
// believes nobody calls: that is the bug's other face, so "first in func" is
// never structural and must be reviewed.
const STRUCTURAL = /^(try|try_table|loop|block|if|br_if|first in (block|loop|then|else|do|catch|catch_all|try)|widget)$/;
const KIND_REASON = {
  try: 'try whose paths all return/throw',
  try_table: 'try_table whose paths all return/throw',
  loop: 'loop that only exits by branching',
  block: 'block whose exits all branch away (async state or switch)',
  if: 'if whose branches all return/throw',
  br_if: 'last case of an exhaustive switch',
  widget: 'widget build the web never creates',
};
function reasonFor(kinds) {
  const parts = [...kinds].map(([k, n]) => `${KIND_REASON[k] ?? k} ×${n}`);
  const ok = [...kinds.keys()].every((k) => STRUCTURAL.test(k));
  return ok ? `kind-reviewed: ${parts.join('; ')}` : `REVIEW: ${parts.join('; ')}`;
}

// --- 3. Compare with the reviewed baseline.
const baseline = fs.existsSync(baselineFile)
  ? JSON.parse(fs.readFileSync(baselineFile, 'utf8'))
  : {};
let reference = baseline;
if (writeBaseline) {
  reference = {};
  for (const name of [...found.keys()].sort()) {
    const kept = baseline[name]?.why;
    reference[name] = {
      count: found.get(name),
      why: kept && !kept.startsWith('REVIEW') ? kept : reasonFor(kindsOf.get(name)),
    };
  }
  fs.writeFileSync(baselineFile, `${JSON.stringify(reference, null, 2)}\n`);
  console.log(`baseline written: ${found.size} functions`);
}
const problems = [];
for (const [name, n] of found) {
  const entry = reference[name];
  if (!entry) problems.push(`NEW    ${name}: ${n}`);
  else if (n > entry.count) problems.push(`MORE   ${name}: ${n} > ${entry.count}`);
  else if (!entry.why || entry.why.startsWith('REVIEW')) problems.push(`REVIEW ${name}: ${entry.why ?? 'no reason'}`);
}
for (const [name, entry] of Object.entries(reference)) {
  const n = found.get(name) ?? 0;
  if (n < entry.count) console.log(`fewer  ${name}: ${n} < ${entry.count} (update the baseline)`);
}
for (const p of problems) console.log(p);
console.log(`\n${functions.length} functions parsed (${headers} headers), ${app.length} from the app; ${found.size} with unreachable not after a terminator; ${problems.length} problem(s)`);
process.exit(problems.length > 0 ? 1 : 0);

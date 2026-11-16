import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Canal nativo (el mismo que recibe los ficheros `.regalos`): `deviceModel`
/// devuelve el modelo del móvil (Android `Build.MODEL`, iOS `UIDevice.model`).
const MethodChannel _nativeChannel = MethodChannel(
  'com.dferrandizmont.regalos/incoming',
);

/// Longitud máxima del nombre de un móvil.
const int kDeviceNameMaxChars = 24;

/// Los nombres por defecto que guardaron las versiones anteriores, en el
/// idioma del móvil que los creó. Se tratan como «sin nombre».
const List<String> kLegacyDeviceNames = [
  'Mi móvil',
  'My phone',
  'El meu mòbil',
];

/// Si [name] es uno de los nombres por defecto de las versiones anteriores.
bool isLegacyDeviceName(String name) =>
    kLegacyDeviceNames.contains(name.trim());

/// El modelo de este móvil («OnePlus NE2213», «iPhone»), o vacío si no se
/// puede saber. Sin dependencias: lo da el código nativo.
Future<String> readDeviceModel() async {
  try {
    final model = await _nativeChannel.invokeMethod<String>('deviceModel');
    return _tidy(model ?? '');
  } on Object {
    return '';
  }
}

String _tidy(String raw) {
  final clean = raw.replaceAll(RegExp(r'\p{C}', unicode: true), '').trim();
  final runes = clean.runes;
  return runes.length <= kDeviceNameMaxChars
      ? clean
      : String.fromCharCodes(runes.take(kDeviceNameMaxChars)).trim();
}

/// El nombre que se propone para este móvil (su modelo). Las pruebas lo
/// sustituyen.
final suggestedDeviceNameProvider = FutureProvider<String>(
  (ref) => readDeviceModel(),
);

/// Solo viaja el nombre escrito o aceptado en el campo editable. Un campo
/// vacío no autoriza compartir el modelo, aunque ya se haya leído.
String deviceNameToSend(WidgetRef ref, String typed) => _tidy(typed);

/// Campo del nombre corto de este móvil, propuesto a partir de su modelo y
/// editable. Rellena [controller] solo si la persona no ha escrito nada y
/// [initial] (lo que ya había guardado) está vacío o es un nombre por defecto
/// de una versión anterior.
class DeviceNameField extends ConsumerStatefulWidget {
  /// Crea el campo.
  const DeviceNameField({
    super.key,
    required this.controller,
    this.initial = '',
  });

  /// Controlador del texto.
  final TextEditingController controller;

  /// Nombre que ya tenía este móvil, si lo tenía.
  final String initial;

  @override
  ConsumerState<DeviceNameField> createState() => _DeviceNameFieldState();
}

class _DeviceNameFieldState extends ConsumerState<DeviceNameField> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initial.trim();
    if (initial.isNotEmpty && !isLegacyDeviceName(initial)) {
      if (widget.controller.text.isEmpty) {
        widget.controller.text = initial;
      }
      return;
    }
    unawaited(
      ref.read(suggestedDeviceNameProvider.future).then((model) {
        if (mounted && model.isNotEmpty && widget.controller.text.isEmpty) {
          widget.controller.text = model;
        }
      }, onError: (Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      textCapitalization: TextCapitalization.words,
      inputFormatters: [LengthLimitingTextInputFormatter(kDeviceNameMaxChars)],
      decoration: InputDecoration(
        labelText: l10n.obDeviceNameLabel,
        helperText: l10n.obDeviceNameHint,
        helperMaxLines: 2,
      ),
    );
  }
}

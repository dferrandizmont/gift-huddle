// Iconos de Ajustes y Compartir. Los trazos son los de la maqueta
// de ajustes (Tabler Icons outline, MIT, © Paweł Kuna;
// la licencia ya está en el registro de licencias de la app).
import 'stroke_icon.dart';
import 'svg_path.dart';

/// Los iconos de las filas de Ajustes, de «Móviles de la familia» y de
/// «Copia de seguridad». Todos sobre la rejilla de 24.
abstract final class SettingsIcons {
  static final StrokeIconBuilder people = svgIcon(const [
    'M5 7a4 4 0 1 0 8 0a4 4 0 1 0 -8 0',
    'M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2',
    'M16 3.13a4 4 0 0 1 0 7.75',
    'M21 21v-2a4 4 0 0 0 -3 -3.85',
  ]);

  static final StrokeIconBuilder gift = svgIcon(const [
    'M3 9a1 1 0 0 1 1 -1h16a1 1 0 0 1 1 1v2a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1z',
    'M12 8l0 13',
    'M19 12v7a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-7',
    'M7.5 8a2.5 2.5 0 0 1 0 -5a4.8 8 0 0 1 4.5 5a4.8 8 0 0 1 4.5 -5a2.5 2.5 0 0 1 0 5',
  ]);

  static final StrokeIconBuilder calendar = svgIcon(const [
    'M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12z',
    'M16 3v4',
    'M8 3v4',
    'M4 11h16',
  ]);

  static final StrokeIconBuilder archive = svgIcon(const [
    'M3 6a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2z',
    'M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-10',
    'M10 12l4 0',
  ]);

  static final StrokeIconBuilder lock = svgIcon(const [
    'M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2v-6z',
    'M11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0',
    'M8 11v-4a4 4 0 1 1 8 0v4',
  ]);

  static final StrokeIconBuilder language = svgIcon(const [
    'M4 5h7',
    'M9 3v2c0 4.418 -2.239 8 -5 8',
    'M5 9c0 2.144 2.952 3.908 6.7 4',
    'M12 20l4 -9l4 9',
    'M19.1 18h-6.2',
  ]);

  static final StrokeIconBuilder palette = svgIcon(const [
    'M12 21a9 9 0 0 1 0 -18c4.97 0 9 3.582 9 8c0 1.06 -.474 2.078 -1.318 2.828c-.844 .75 -1.989 1.172 -3.182 1.172h-2.5a2 2 0 0 0 -1 3.75a1.3 1.3 0 0 1 -1 2.25',
    'M8.5 10.5h.01',
    'M12.5 7.5h.01',
    'M16.5 10.5h.01',
  ]);

  static final StrokeIconBuilder phone = svgIcon(const [
    'M6 5a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-14z',
    'M11 4h2',
    'M12 17v.01',
  ]);

  static final StrokeIconBuilder devices = svgIcon(const [
    'M13 9a1 1 0 0 1 1 -1h6a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1h-6a1 1 0 0 1 -1 -1v-10z',
    'M18 8v-3a1 1 0 0 0 -1 -1h-13a1 1 0 0 0 -1 1v12a1 1 0 0 0 1 1h9',
    'M16 9h2',
  ]);

  static final StrokeIconBuilder computer = svgIcon(const [
    'M3 5a1 1 0 0 1 1 -1h16a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1v-10',
    'M7 20h10',
    'M9 16l-1 4',
    'M15 16l1 4',
  ]);

  static final StrokeIconBuilder shield = svgIcon(const [
    'M12 3a12 12 0 0 0 8.5 3a12 12 0 0 1 -8.5 15a12 12 0 0 1 -8.5 -15a12 12 0 0 0 8.5 -3',
    'M9 12l2 2l4 -4',
  ]);

  static final StrokeIconBuilder heart = svgIcon(const [
    'M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572',
  ]);

  static final StrokeIconBuilder info = svgIcon(const [
    'M3 5a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14z',
    'M12 8h.01',
    'M11 12h1v4h1',
  ]);

  /// Un círculo con interrogante (Tabler «help»): la guía «Cómo funciona».
  static final StrokeIconBuilder help = svgIcon(const [
    'M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0',
    'M12 17l0 .01',
    'M12 13.5a1.5 1.5 0 0 1 1 -1.5a2.6 2.6 0 1 0 -3 -4',
  ]);

  static final StrokeIconBuilder qr = svgIcon(const [
    'M4 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1z',
    'M7 17l0 .01',
    'M14 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1z',
    'M7 7l0 .01',
    'M4 15a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1z',
    'M17 7l0 .01',
    'M14 14l3 0',
    'M20 14l0 .01',
    'M14 14l0 3',
    'M14 20l3 0',
    'M17 17l3 0',
    'M20 17l0 3',
  ]);

  static final StrokeIconBuilder link = svgIcon(const [
    'M9 15l6 -6',
    'M11 6l.463 -.536a5 5 0 0 1 7.071 7.072l-.534 .464',
    'M13 18l-.397 .534a5.068 5.068 0 0 1 -7.127 0a4.972 4.972 0 0 1 0 -7.071l.524 -.463',
  ]);

  static final StrokeIconBuilder refresh = svgIcon(const [
    'M20 11a8.1 8.1 0 0 0 -15.5 -2m-.5 -4v4h4',
    'M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4',
  ]);

  static final StrokeIconBuilder download = svgIcon(const [
    'M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2 -2v-2',
    'M7 11l5 5l5 -5',
    'M12 4l0 12',
  ]);

  static final StrokeIconBuilder upload = svgIcon(const [
    'M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2 -2v-2',
    'M7 9l5 -5l5 5',
    'M12 4l0 12',
  ]);

  static final StrokeIconBuilder clipboard = svgIcon(const [
    'M9 5h-2a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-12a2 2 0 0 0 -2 -2h-2',
    'M9 5a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2a2 2 0 0 1 -2 2h-2a2 2 0 0 1 -2 -2z',
  ]);

  static final StrokeIconBuilder leave = svgIcon(const [
    'M14 8v-2a2 2 0 0 0 -2 -2h-7a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2 -2v-2',
    'M9 12h12l-3 -3',
    'M18 15l3 -3',
  ]);

  static final StrokeIconBuilder cloudOff = svgIcon(const [
    'M9.58 5.548c.24 -.11 .492 -.207 .752 -.286c1.88 -.572 3.956 -.193 5.444 1c1.488 1.19 2.162 3.007 1.77 4.769h.99c1.913 0 3.464 1.56 3.464 3.486c0 .957 -.383 1.824 -1.003 2.454m-2.997 1.033h-11.343c-2.572 -.004 -4.657 -2.011 -4.657 -4.487c0 -2.475 2.085 -4.482 4.657 -4.482c.13 -.582 .37 -1.128 .7 -1.62',
    'M3 3l18 18',
  ]);

  static final StrokeIconBuilder dots = svgIcon(const [
    'M5 12h.01',
    'M12 12h.01',
    'M19 12h.01',
  ]);

  /// Un enlace que se abre fuera de la app (Tabler `external-link`).
  static final StrokeIconBuilder externalLink = svgIcon(const [
    'M12 6h-6a2 2 0 0 0 -2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-6',
    'M11 13l9 -9',
    'M15 4h5v5',
  ]);

  /// Un correo (Tabler `mail`).
  static final StrokeIconBuilder mail = svgIcon(const [
    'M3 7a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v10a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-10',
    'M3 7l9 6l9 -6',
  ]);

  /// Borrar todo (Tabler `trash`).
  static final StrokeIconBuilder trash = svgIcon(const [
    'M4 7l16 0',
    'M10 11l0 6',
    'M14 11l0 6',
    'M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2 -2l1 -12',
    'M9 7v-3a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v3',
  ]);

  /// Una llave (Tabler «key»): el código de recuperación.
  static final StrokeIconBuilder key = svgIcon(const [
    'M16.555 3.843l3.602 3.602a2.877 2.877 0 0 1 0 4.069l-2.643 2.643a2.877 2.877 0 0 1 -4.069 0l-.301 -.301l-6.558 6.558a2 2 0 0 1 -1.239 .578l-.175 .008h-1.172a1 1 0 0 1 -.993 -.883l-.007 -.117v-1.172a2 2 0 0 1 .467 -1.284l.119 -.13l.414 -.414h2v-2h2v-2l2.144 -2.144l-.301 -.301a2.877 2.877 0 0 1 0 -4.069l2.643 -2.643a2.877 2.877 0 0 1 4.069 0z',
    'M15 9h.01',
  ]);

  static final StrokeIconBuilder arrowBack = svgIcon(const [
    'M5 12l14 0',
    'M5 12l6 6',
    'M5 12l6 -6',
  ]);
}

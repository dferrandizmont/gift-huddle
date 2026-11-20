import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ca.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ca'),
    Locale('en'),
    Locale('es'),
  ];

  /// Nombre comercial de la app (no se traduce).
  ///
  /// In es, this message translates to:
  /// **'Gift Huddle'**
  String get appTitle;

  /// Etiqueta accesible de la barra inferior.
  ///
  /// In es, this message translates to:
  /// **'Navegación principal'**
  String get navMainLabel;

  /// Destino de la barra inferior: la lista de regalos de cada persona a la que se regala (pareja, hermanos, sobrinos, niños...).
  ///
  /// In es, this message translates to:
  /// **'Personas'**
  String get navPeople;

  /// Destino de la barra inferior y título de su pantalla: la rejilla de quién regala qué a cada persona (Reparto).
  ///
  /// In es, this message translates to:
  /// **'Reparto'**
  String get navFamily;

  /// Etiqueta corta de Reparto en la barra inferior; tiene que caber en una línea (el título de la pantalla es navFamily).
  ///
  /// In es, this message translates to:
  /// **'Reparto'**
  String get navFamilyShort;

  /// Destino de la barra inferior: Navidad, Reyes, cumpleaños y otras fechas.
  ///
  /// In es, this message translates to:
  /// **'Ocasiones'**
  String get navOccasions;

  /// Destino de la barra inferior y título de la pantalla de ajustes.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get navSettings;

  /// Título del estado vacío de la pantalla Personas.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay personas'**
  String get emptyPeopleTitle;

  /// Explicación del estado vacío de la pantalla Personas.
  ///
  /// In es, this message translates to:
  /// **'Añade a las personas a las que regaláis para empezar sus listas de regalos.'**
  String get emptyPeopleMessage;

  /// Título del estado vacío de la pantalla Familia.
  ///
  /// In es, this message translates to:
  /// **'Nadie ha apuntado regalos'**
  String get emptyFamilyTitle;

  /// Explicación del estado vacío de la pantalla Familia.
  ///
  /// In es, this message translates to:
  /// **'Aquí verás quién regala qué a cada persona.'**
  String get emptyFamilyMessage;

  /// Título del estado vacío de la pantalla Ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Sin ocasiones'**
  String get emptyOccasionsTitle;

  /// Explicación del estado vacío de la pantalla Ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Navidad, cumpleaños y otras fechas aparecerán aquí con su cuenta atrás.'**
  String get emptyOccasionsMessage;

  /// Etiqueta accesible del botón de volver; {title} es el nombre de la pantalla anterior.
  ///
  /// In es, this message translates to:
  /// **'Volver a {title}'**
  String backTo(String title);

  /// Entrada de Ajustes y título de su pantalla: color, tema claro u oscuro y temas de ocasión.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get settingsAppearance;

  /// Fila de Ajustes para elegir el idioma de la app.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settingsLanguage;

  /// Opción de idioma que sigue al del móvil.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get settingsLanguageSystem;

  /// Nombre del español en su propia lengua; igual en los tres idiomas.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get settingsLanguageSpanish;

  /// Nombre del catalán en su propia lengua; igual en los tres idiomas.
  ///
  /// In es, this message translates to:
  /// **'Català'**
  String get settingsLanguageCatalan;

  /// Nombre del inglés en su propia lengua; igual en los tres idiomas.
  ///
  /// In es, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Cabecera de la sección donde se elige el color de la app.
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get appearanceColorSection;

  /// Etiqueta accesible del grupo de seis muestras de color.
  ///
  /// In es, this message translates to:
  /// **'Color de la app'**
  String get appearanceColorGroup;

  /// Cabecera de la sección claro/oscuro.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get appearanceThemeSection;

  /// Etiqueta accesible del selector Sistema / Claro / Oscuro.
  ///
  /// In es, this message translates to:
  /// **'Tema claro u oscuro'**
  String get appearanceThemeGroup;

  /// Opción de tema: sigue el del teléfono.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// Opción de tema claro.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// Opción de tema oscuro.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// Interruptor que activa los temas de ocasión.
  ///
  /// In es, this message translates to:
  /// **'Temas de ocasión (Navidad, cumpleaños)'**
  String get appearanceOccasionTitle;

  /// Explicación bajo el interruptor de temas de ocasión.
  ///
  /// In es, this message translates to:
  /// **'La lista de una ocasión cambia de acento y cabecera.'**
  String get appearanceOccasionHint;

  /// Interruptor que activa las vibraciones suaves al tocar.
  ///
  /// In es, this message translates to:
  /// **'Vibraciones'**
  String get appearanceHapticsTitle;

  /// Explicación bajo el interruptor de vibraciones.
  ///
  /// In es, this message translates to:
  /// **'Pequeños toques al marcar, elegir o cuando algo llega.'**
  String get appearanceHapticsHint;

  /// Cabecera de la muestra con una fila de regalo y una cuenta atrás.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get appearancePreview;

  /// Nombre del color lavanda (el de serie).
  ///
  /// In es, this message translates to:
  /// **'Lavanda'**
  String get accentLavender;

  /// Nombre del color salvia.
  ///
  /// In es, this message translates to:
  /// **'Salvia'**
  String get accentSage;

  /// Nombre del color melocotón.
  ///
  /// In es, this message translates to:
  /// **'Melocotón'**
  String get accentPeach;

  /// Nombre del color cielo.
  ///
  /// In es, this message translates to:
  /// **'Cielo'**
  String get accentSky;

  /// Nombre del color rosa.
  ///
  /// In es, this message translates to:
  /// **'Rosa'**
  String get accentRose;

  /// Nombre del color mantequilla.
  ///
  /// In es, this message translates to:
  /// **'Mantequilla'**
  String get accentButter;

  /// Estado de un regalo: solo es una idea.
  ///
  /// In es, this message translates to:
  /// **'Idea'**
  String get statusIdea;

  /// Estado de un regalo: ya se sabe cuál es, falta comprarlo.
  ///
  /// In es, this message translates to:
  /// **'Decidido'**
  String get statusDecided;

  /// Estado de un regalo: comprado, aún no ha llegado.
  ///
  /// In es, this message translates to:
  /// **'Comprado'**
  String get statusBought;

  /// Estado de un regalo: el pedido ya está en casa.
  ///
  /// In es, this message translates to:
  /// **'Llegó'**
  String get statusArrived;

  /// Estado de un regalo: envuelto y listo.
  ///
  /// In es, this message translates to:
  /// **'Envuelto'**
  String get statusWrapped;

  /// Estado de un regalo: ya se ha entregado.
  ///
  /// In es, this message translates to:
  /// **'Entregado'**
  String get statusDelivered;

  /// Etiqueta accesible de la casilla de estado cuando se puede tocar para cambiarlo.
  ///
  /// In es, this message translates to:
  /// **'Cambiar estado de {item}. Estado actual: {status}'**
  String statusCheckboxLabel(String item, String status);

  /// Etiqueta accesible de un estado que solo se muestra.
  ///
  /// In es, this message translates to:
  /// **'Estado: {status}'**
  String statusReadOnlyLabel(String status);

  /// Quien regala todavía no está decidido.
  ///
  /// In es, this message translates to:
  /// **'Sin asignar'**
  String get giverUnassigned;

  /// Texto junto al número de la tarjeta de cuenta atrás. {name} lleva su artículo si hace falta (Reyes, el cumpleaños).
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{día para {name}} other{días para {name}}}'**
  String countdownDaysFor(int count, String name);

  /// Fecha de hoy bajo la cuenta atrás.
  ///
  /// In es, this message translates to:
  /// **'Hoy es {date}'**
  String todayIs(DateTime date);

  /// Regalo de ejemplo de la vista previa de Apariencia.
  ///
  /// In es, this message translates to:
  /// **'Estación de bomberos de bloques'**
  String get previewGiftName;

  /// Quien regala en la vista previa: la propia casa.
  ///
  /// In es, this message translates to:
  /// **'Nosotros'**
  String get previewGiver;

  /// Ocasión de ejemplo de la cuenta atrás de la vista previa.
  ///
  /// In es, this message translates to:
  /// **'Reyes'**
  String get previewOccasion;

  /// Texto que acompaña al fichero .gifthuddle al compartirlo por WhatsApp, correo u otra app.
  ///
  /// In es, this message translates to:
  /// **'Cambios de Gift Huddle: ábrelo con la app.'**
  String get shareEnvelopeText;

  /// Nombre de la ocasión del Tió de Nadal, guardada al crear las ocasiones de serie.
  ///
  /// In es, this message translates to:
  /// **'Tió'**
  String get occasionNameTio;

  /// Nombre de la ocasión de Navidad (25 de diciembre), guardada al crear las ocasiones de serie.
  ///
  /// In es, this message translates to:
  /// **'Navidad'**
  String get occasionNameSanta;

  /// Nombre de la ocasión de los Reyes Magos (6 de enero), guardada al crear las ocasiones de serie.
  ///
  /// In es, this message translates to:
  /// **'Reyes'**
  String get occasionNameKings;

  /// Nombre de la ocasión de cumpleaños de una persona.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños de {name}'**
  String occasionBirthdayOf(String name);

  /// Error al importar: los datos no son un sobre válido.
  ///
  /// In es, this message translates to:
  /// **'Este fichero o texto no es un envío de Gift Huddle.'**
  String get shareErrorNotEnvelope;

  /// Error al importar: el sobre es de otra lista.
  ///
  /// In es, this message translates to:
  /// **'Este envío es de otra familia. Conecta los móviles con el código QR.'**
  String get shareErrorWrongList;

  /// Error al importar: la clave no vale o el sobre está manipulado.
  ///
  /// In es, this message translates to:
  /// **'No se puede abrir este envío. Puede estar dañado o ser de otra familia.'**
  String get shareErrorAuth;

  /// Error al importar: el sobre supera el tamaño máximo.
  ///
  /// In es, this message translates to:
  /// **'Este envío es demasiado grande.'**
  String get shareErrorTooLarge;

  /// Error al importar: este móvil todavía no tiene familia.
  ///
  /// In es, this message translates to:
  /// **'Primero crea tu familia o únete a una con el código QR.'**
  String get shareErrorNoFamily;

  /// Error al importar: el reloj del otro móvil va más de un día adelantado.
  ///
  /// In es, this message translates to:
  /// **'El otro móvil tiene la fecha y la hora mal puestas. Corrígelas y vuelve a enviarlo.'**
  String get shareErrorClockDrift;

  /// Error al importar: un fichero .gifthuddle antiguo (sin firma) en una familia que ya usa el formato nuevo.
  ///
  /// In es, this message translates to:
  /// **'Este fichero es de una versión anterior de Gift Huddle y ya no se abre. Guárdalo y pide que te lo envíen de nuevo desde un móvil actualizado.'**
  String get shareErrorLegacyFile;

  /// Error al importar o guardar: el móvil aún no ha pasado al formato nuevo de la familia.
  ///
  /// In es, this message translates to:
  /// **'Este móvil todavía no está al día con la familia. Sincroniza y vuelve a abrir el fichero.'**
  String get shareErrorNotReady;

  /// Error al importar: el fichero es de otra generación de la lista (tras una renovación).
  ///
  /// In es, this message translates to:
  /// **'Este fichero es de una versión anterior de la lista. Pide que te envíen uno nuevo.'**
  String get shareErrorGeneration;

  /// Error al importar: el autor del fichero está revocado.
  ///
  /// In es, this message translates to:
  /// **'Este fichero lo guardó un móvil que ya no es de la familia. No se ha añadido nada.'**
  String get shareErrorRevokedWriter;

  /// Error al importar: falta la clave del fichero; queda guardado y se vuelve a probar al sincronizar.
  ///
  /// In es, this message translates to:
  /// **'Todavía no se puede abrir este fichero. Se ha guardado y se abrirá solo cuando sincronices.'**
  String get shareErrorMissingKey;

  /// Error al importar: falta la clave o el autor aún no está confirmado en este móvil, y el fichero no se ha guardado.
  ///
  /// In es, this message translates to:
  /// **'Todavía no se puede abrir este fichero. Sincroniza y vuelve a abrirlo.'**
  String get shareErrorSyncAndReopen;

  /// Error al guardar: el móvil está pendiente de aprobar o ya no es de la familia.
  ///
  /// In es, this message translates to:
  /// **'Este móvil aún no puede guardar copias. Otro móvil de la familia tiene que aprobarlo primero.'**
  String get shareErrorNotAllowed;

  /// Error al emparejar: el texto del QR no es válido.
  ///
  /// In es, this message translates to:
  /// **'Este código QR no es de Gift Huddle.'**
  String get pairErrorInvalidCode;

  /// Título de la pantalla de bloqueo.
  ///
  /// In es, this message translates to:
  /// **'Introduce tu PIN'**
  String get lockEnterPin;

  /// Etiqueta accesible de los puntos del PIN; {count} es cuántos dígitos hay escritos y {total} cuántos tiene como máximo.
  ///
  /// In es, this message translates to:
  /// **'PIN: {count} de {total} dígitos'**
  String lockPinProgress(int count, int total);

  /// Botón de la pantalla de bloqueo que comprueba el PIN.
  ///
  /// In es, this message translates to:
  /// **'Desbloquear'**
  String get lockUnlock;

  /// Etiqueta accesible de la tecla de borrar del teclado numérico.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get lockBackspace;

  /// Etiqueta accesible del botón de desbloqueo biométrico.
  ///
  /// In es, this message translates to:
  /// **'Usar huella o rostro'**
  String get lockBiometric;

  /// Motivo que enseña el sistema al pedir la huella o el rostro.
  ///
  /// In es, this message translates to:
  /// **'Desbloquea Gift Huddle'**
  String get lockBiometricReason;

  /// Aviso bajo el ajuste de desbloqueo con huella o rostro: avisa de que sirve cualquier huella o cara dada de alta en el móvil.
  ///
  /// In es, this message translates to:
  /// **'Cualquier huella o cara registrada en el móvil podrá abrir la app.'**
  String get lockBiometricNotice;

  /// Mensaje de la pantalla que tapa la app cuando falla la lectura del estado del bloqueo.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido comprobar el bloqueo.'**
  String get lockLoadError;

  /// Botón que repite la lectura del bloqueo tras un fallo.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get lockRetry;

  /// Aviso tras un PIN equivocado; {count} son los intentos que quedan antes de la espera.
  ///
  /// In es, this message translates to:
  /// **'PIN incorrecto. {count, plural, one{Queda {count} intento} other{Quedan {count} intentos}} antes de tener que esperar.'**
  String lockWrongPin(int count);

  /// Aviso tras un PIN equivocado cuando ya toca esperar.
  ///
  /// In es, this message translates to:
  /// **'PIN incorrecto.'**
  String get lockWrongPinNow;

  /// Aviso de espera tras demasiados fallos; {time} es el tiempo que falta, como 0:30.
  ///
  /// In es, this message translates to:
  /// **'Demasiados intentos. Vuelve a probar en {time}.'**
  String lockWait(String time);

  /// Título de la pantalla para crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'Crea un PIN'**
  String get pinSetupTitle;

  /// Explicación bajo el título al crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'De 4 a 6 dígitos. Protege tu lista en este móvil.'**
  String get pinSetupMessage;

  /// Título del segundo paso al crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'Repite el PIN'**
  String get pinConfirmTitle;

  /// Aviso al confirmar un PIN distinto del primero.
  ///
  /// In es, this message translates to:
  /// **'Los PIN no coinciden. Inténtalo de nuevo.'**
  String get pinMismatch;

  /// Botón del primer paso al crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get pinContinue;

  /// Botón del segundo paso al crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'Guardar PIN'**
  String get pinSave;

  /// Botón para dejar el PIN para más tarde en el primer uso.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get pinSkip;

  /// Título del aviso que se ofrece al crear el PIN en un móvil con huella o rostro.
  ///
  /// In es, this message translates to:
  /// **'¿Activar huella o rostro?'**
  String get pinBiometricOfferTitle;

  /// Botón que activa la huella o el rostro al crear el PIN.
  ///
  /// In es, this message translates to:
  /// **'Activar'**
  String get pinBiometricOfferEnable;

  /// Botón que guarda lo que se edita.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get actionSave;

  /// Botón que cierra sin guardar.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get actionCancel;

  /// Botón que borra, tras confirmar.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get actionDelete;

  /// Botón para pasar al paso siguiente del primer uso.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get actionNext;

  /// Etiqueta accesible del botón de volver.
  ///
  /// In es, this message translates to:
  /// **'Atrás'**
  String get actionBack;

  /// Etiqueta de un botón que abre la edición.
  ///
  /// In es, this message translates to:
  /// **'Editar'**
  String get actionEdit;

  /// Botón o etiqueta accesible para cerrar una pantalla o un aviso.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get actionClose;

  /// Botón que cierra una hoja o un aviso informativo.
  ///
  /// In es, this message translates to:
  /// **'Hecho'**
  String get actionDone;

  /// Botón que archiva una persona, quien regala o una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Archivar'**
  String get actionArchive;

  /// Botón que recupera algo archivado.
  ///
  /// In es, this message translates to:
  /// **'Recuperar'**
  String get actionRestore;

  /// Acción del aviso tras cambiar el estado de un regalo.
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get actionUndo;

  /// Etiqueta del campo del nombre.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get fieldName;

  /// Error cuando falta el nombre.
  ///
  /// In es, this message translates to:
  /// **'Escribe un nombre.'**
  String get fieldNameRequired;

  /// Campo del regalo: la persona que lo recibe.
  ///
  /// In es, this message translates to:
  /// **'Para quién'**
  String get fieldFor;

  /// Campo y filtro: quién regala.
  ///
  /// In es, this message translates to:
  /// **'Quién regala'**
  String get fieldGiver;

  /// Campo y filtro: la ocasión del regalo.
  ///
  /// In es, this message translates to:
  /// **'Ocasión'**
  String get fieldOccasion;

  /// Campo y filtro: el estado del regalo.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get fieldStatus;

  /// Número de regalos.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Sin regalos} one{{count} regalo} other{{count} regalos}}'**
  String giftCount(int count);

  /// Edad de una persona.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{{count} año} other{{count} años}}'**
  String ageYears(int count);

  /// Nombre de este móvil si no se escribe otro; lo ve el otro móvil al emparejar.
  ///
  /// In es, this message translates to:
  /// **'Mi móvil'**
  String get deviceNameDefault;

  /// Nombre de quien regala que se crea al empezar: la propia casa.
  ///
  /// In es, this message translates to:
  /// **'Nosotros'**
  String get giverUs;

  /// Etiqueta y campo: lo que regala esta persona lo paga la casa y cuenta en el presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Paga la casa'**
  String get giverHouseholdPays;

  /// Explicación bajo el interruptor «Paga la casa».
  ///
  /// In es, this message translates to:
  /// **'Si lo paga la casa, cuenta en el presupuesto.'**
  String get giverHouseholdPaysHint;

  /// Texto junto al número de la cuenta atrás de un cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{día para el cumpleaños de {name}} other{días para el cumpleaños de {name}}}'**
  String countdownDaysForBirthday(int count, String name);

  /// Progreso del primer uso.
  ///
  /// In es, this message translates to:
  /// **'Paso {step} de {total}'**
  String onboardingStepOf(int step, int total);

  /// Título de la primera pantalla del primer uso.
  ///
  /// In es, this message translates to:
  /// **'Te damos la bienvenida a Gift Huddle'**
  String get obWelcomeTitle;

  /// Qué es la app, en una frase.
  ///
  /// In es, this message translates to:
  /// **'Apunta qué regala cada uno a cada persona, para que nadie repita y a nadie le falte.'**
  String get obWelcomeBody;

  /// Aviso de privacidad de la bienvenida.
  ///
  /// In es, this message translates to:
  /// **'Sin cuentas. Si sincronizáis dos móviles, la lista viaja cifrada y solo vuestros móviles pueden leerla.'**
  String get obWelcomePrivacy;

  /// Campo con el nombre de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Nombre de este móvil'**
  String get obDeviceNameLabel;

  /// Explicación del nombre de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Es el nombre que verá el otro móvil. Puedes cambiarlo.'**
  String get obDeviceNameHint;

  /// Botón de la bienvenida.
  ///
  /// In es, this message translates to:
  /// **'Empezar'**
  String get obStart;

  /// Pregunta sobre el botón «Escanear el QR» de la bienvenida.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tenéis la lista en otro móvil?'**
  String get obHaveListTitle;

  /// Título del paso de personas.
  ///
  /// In es, this message translates to:
  /// **'¿A quién le regaláis?'**
  String get obPeopleTitle;

  /// Explicación del paso de personas.
  ///
  /// In es, this message translates to:
  /// **'Añade a las personas a las que regaláis: pareja, hermanos, sobrinos, niños… Hace falta al menos una.'**
  String get obPeopleBody;

  /// Botón para añadir una persona.
  ///
  /// In es, this message translates to:
  /// **'Añadir persona'**
  String get obPeopleAdd;

  /// Aviso cuando no hay ninguna persona en el primer uso.
  ///
  /// In es, this message translates to:
  /// **'Añade al menos una persona para seguir.'**
  String get obPeopleNeedOne;

  /// Etiqueta accesible del botón de quitar de la lista del primer uso.
  ///
  /// In es, this message translates to:
  /// **'Quitar a {name}'**
  String obRemove(String name);

  /// Título del paso de quién regala.
  ///
  /// In es, this message translates to:
  /// **'¿Quién regala?'**
  String get obGiversTitle;

  /// Explicación del paso de quién regala.
  ///
  /// In es, this message translates to:
  /// **'«Nosotros» ya está creado y paga la casa. Añade a los abuelos, los tíos…'**
  String get obGiversBody;

  /// Título de los botones de sugerencia.
  ///
  /// In es, this message translates to:
  /// **'Añadir rápido'**
  String get obGiversSuggestions;

  /// Sugerencia de quién regala.
  ///
  /// In es, this message translates to:
  /// **'Abuelos'**
  String get obGiverGrandparents;

  /// Sugerencia de quién regala.
  ///
  /// In es, this message translates to:
  /// **'Tíos'**
  String get obGiverUncles;

  /// Sugerencia de quién regala.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get obGiverFriends;

  /// Etiqueta accesible de un botón de sugerencia.
  ///
  /// In es, this message translates to:
  /// **'Añadir {name}'**
  String obAddNamed(String name);

  /// Título de la hoja y botón para dar de alta a quien regala.
  ///
  /// In es, this message translates to:
  /// **'Añadir quién regala'**
  String get giverNew;

  /// Título de la hoja para cambiar a quien regala.
  ///
  /// In es, this message translates to:
  /// **'Editar quién regala'**
  String get giverEdit;

  /// Ejemplo en el campo del nombre de quien regala.
  ///
  /// In es, this message translates to:
  /// **'Abuelos, Tía Marta y Jordi…'**
  String get giverNameHint;

  /// Título del paso de ocasiones.
  ///
  /// In es, this message translates to:
  /// **'¿Cuándo hay regalos?'**
  String get obOccasionsTitle;

  /// Explicación del paso de ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Elige las fechas de siempre. Los cumpleaños salen solos de las fechas que hayas puesto.'**
  String get obOccasionsBody;

  /// Cabecera de la lista de cumpleaños del primer uso.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños (se crean solos)'**
  String get obBirthdaysSection;

  /// Aviso cuando ninguna persona tiene cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Si añades la fecha de nacimiento de alguien, su cumpleaños aparecerá aquí.'**
  String get obNoBirthdays;

  /// Cabecera de las ocasiones añadidas a mano.
  ///
  /// In es, this message translates to:
  /// **'Otras fechas'**
  String get obOtherOccasions;

  /// Botón para añadir una ocasión en el primer uso.
  ///
  /// In es, this message translates to:
  /// **'Añadir otra fecha'**
  String get obAddOccasion;

  /// Título del paso del PIN.
  ///
  /// In es, this message translates to:
  /// **'Protege los regalos'**
  String get obPinTitle;

  /// Explicación del paso del PIN.
  ///
  /// In es, this message translates to:
  /// **'Crea un PIN para que nadie vea los regalos si coge el móvil. Podrás cambiarlo en Ajustes.'**
  String get obPinBody;

  /// Botón del paso del PIN.
  ///
  /// In es, this message translates to:
  /// **'Crear PIN'**
  String get obPinCreate;

  /// Texto del botón mientras se guarda todo.
  ///
  /// In es, this message translates to:
  /// **'Preparando tu lista…'**
  String get obFinishing;

  /// Error al terminar el primer uso.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido guardar. Inténtalo otra vez.'**
  String get obSaveError;

  /// Título de la hoja para añadir una persona.
  ///
  /// In es, this message translates to:
  /// **'Nueva persona'**
  String get personNew;

  /// Título de la hoja y etiqueta del botón para cambiar una persona.
  ///
  /// In es, this message translates to:
  /// **'Editar persona'**
  String get personEdit;

  /// Grupo de muestras de color de una persona.
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get personColor;

  /// Campo libre con la relación: pareja, hermano, sobrina…
  ///
  /// In es, this message translates to:
  /// **'Relación (opcional)'**
  String get personRelation;

  /// Ejemplo del campo de relación.
  ///
  /// In es, this message translates to:
  /// **'Pareja, hermano, sobrina…'**
  String get personRelationHint;

  /// Título del campo de cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños (opcional)'**
  String get personBirthday;

  /// Botón que abre el selector de fecha.
  ///
  /// In es, this message translates to:
  /// **'Elegir fecha'**
  String get personBirthdayPick;

  /// Cuando no hay fecha de cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Sin fecha'**
  String get personBirthdayNone;

  /// Etiqueta accesible del botón que quita la fecha.
  ///
  /// In es, this message translates to:
  /// **'Quitar fecha'**
  String get personBirthdayClear;

  /// Casilla para guardar solo el día y el mes.
  ///
  /// In es, this message translates to:
  /// **'No guardar el año'**
  String get personBirthdayNoYear;

  /// Regalos de una persona que faltan por comprar.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{falta {count} por comprar} other{faltan {count} por comprar}}'**
  String personPendingBuy(int count);

  /// Todos los regalos de una persona están comprados.
  ///
  /// In es, this message translates to:
  /// **'todo comprado'**
  String get personAllBought;

  /// Botón flotante de la lista.
  ///
  /// In es, this message translates to:
  /// **'Añadir regalo'**
  String get giftAdd;

  /// Regalos sin ocasión.
  ///
  /// In es, this message translates to:
  /// **'Sin ocasión'**
  String get giftNoOccasion;

  /// Estado vacío de la lista de una persona.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay regalos para {name}'**
  String giftsEmptyTitle(String name);

  /// Explicación del estado vacío de la lista de una persona.
  ///
  /// In es, this message translates to:
  /// **'Apunta una idea, aunque todavía no sepas qué comprar.'**
  String get giftsEmptyMessage;

  /// Etiqueta de un regalo sorpresa.
  ///
  /// In es, this message translates to:
  /// **'Sorpresa'**
  String get giftTagSurprise;

  /// Etiqueta de un regalo que alguien ha pedido.
  ///
  /// In es, this message translates to:
  /// **'Encargo'**
  String get giftTagRequest;

  /// Línea de un regalo encargado.
  ///
  /// In es, this message translates to:
  /// **'Lo pidió {name}'**
  String giftRequestedBy(String name);

  /// Línea con la talla o la edad.
  ///
  /// In es, this message translates to:
  /// **'Talla o edad: {size}'**
  String giftSizeLine(String size);

  /// Precio real y previsto de un regalo.
  ///
  /// In es, this message translates to:
  /// **'{actual} (previsto {planned})'**
  String giftPriceActualPlanned(String actual, String planned);

  /// Aviso tras cambiar el estado de un regalo.
  ///
  /// In es, this message translates to:
  /// **'{item}: {status}'**
  String giftStatusChanged(String item, String status);

  /// Título del selector de estados.
  ///
  /// In es, this message translates to:
  /// **'Estado de {item}'**
  String giftStatusPickerTitle(String item);

  /// Palabra entre lo gastado y lo previsto: «72 € de 145 €».
  ///
  /// In es, this message translates to:
  /// **'de'**
  String get budgetOf;

  /// Mini presupuesto de la casa para una persona.
  ///
  /// In es, this message translates to:
  /// **'La casa · {name}'**
  String budgetHouseFor(String name);

  /// Mini presupuesto de la casa en total.
  ///
  /// In es, this message translates to:
  /// **'La casa · total'**
  String get budgetHouseTotal;

  /// Etiqueta accesible de una barra de presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Gastado: {spent} de {planned}'**
  String budgetBarLabel(String spent, String planned);

  /// Botón que abre los filtros.
  ///
  /// In es, this message translates to:
  /// **'Filtros'**
  String get filtersButton;

  /// Título de la hoja de filtros.
  ///
  /// In es, this message translates to:
  /// **'Filtrar regalos'**
  String get filtersSheetTitle;

  /// Filtro de ocasión sin limitar.
  ///
  /// In es, this message translates to:
  /// **'Todas'**
  String get filterAnyOccasion;

  /// Filtro de quién regala sin limitar.
  ///
  /// In es, this message translates to:
  /// **'Todos'**
  String get filterAnyGiver;

  /// Filtro de estado sin limitar.
  ///
  /// In es, this message translates to:
  /// **'Todos'**
  String get filterAnyStatus;

  /// Filtro: regalos que son una idea o están decididos.
  ///
  /// In es, this message translates to:
  /// **'Falta comprar'**
  String get filterNeedsBuy;

  /// Filtro: regalos que ya han llegado y no están envueltos.
  ///
  /// In es, this message translates to:
  /// **'Falta envolver'**
  String get filterNeedsWrap;

  /// Etiqueta accesible de un filtro activo.
  ///
  /// In es, this message translates to:
  /// **'Quitar filtro {name}'**
  String filterRemove(String name);

  /// Botón que quita todos los filtros.
  ///
  /// In es, this message translates to:
  /// **'Quitar filtros'**
  String get filterClear;

  /// Aviso cuando los filtros no dejan ningún regalo.
  ///
  /// In es, this message translates to:
  /// **'Ningún regalo cumple los filtros.'**
  String get filterNoResults;

  /// Título del editor de un regalo nuevo.
  ///
  /// In es, this message translates to:
  /// **'Nuevo regalo'**
  String get giftEditorNewTitle;

  /// Título del editor de un regalo existente.
  ///
  /// In es, this message translates to:
  /// **'Editar regalo'**
  String get giftEditorEditTitle;

  /// Editor de un regalo abierto desde el botón Añadir regalo cuando aún no hay ninguna persona: invita a crearla.
  ///
  /// In es, this message translates to:
  /// **'Añade primero a la persona que recibirá el regalo.'**
  String get giftEditorNoPeople;

  /// Error del editor de regalo cuando se intenta guardar sin haber elegido persona.
  ///
  /// In es, this message translates to:
  /// **'Elige para quién es el regalo.'**
  String get giftRecipientRequired;

  /// Aviso tras guardar un regalo nuevo desde el botón Añadir regalo de Personas u Ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Regalo añadido a {name}'**
  String giftAddedNotice(String name);

  /// Acción del aviso de regalo añadido: abre la lista de esa persona.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get giftAddedView;

  /// Campo con el nombre del regalo.
  ///
  /// In es, this message translates to:
  /// **'Regalo'**
  String get giftFieldTitle;

  /// Ejemplo del campo del regalo.
  ///
  /// In es, this message translates to:
  /// **'Pijama de astronautas, talla 8'**
  String get giftFieldTitleHint;

  /// Error cuando falta el nombre del regalo.
  ///
  /// In es, this message translates to:
  /// **'Escribe qué regalo es.'**
  String get giftFieldTitleRequired;

  /// Cabecera de los campos de precio.
  ///
  /// In es, this message translates to:
  /// **'Precio'**
  String get giftPriceSection;

  /// Precio previsto.
  ///
  /// In es, this message translates to:
  /// **'Previsto'**
  String get giftFieldPlanned;

  /// Precio real.
  ///
  /// In es, this message translates to:
  /// **'Real'**
  String get giftFieldActual;

  /// Error de un precio mal escrito.
  ///
  /// In es, this message translates to:
  /// **'Escribe un importe, por ejemplo 12,50.'**
  String get giftPriceInvalid;

  /// Campo de la tienda.
  ///
  /// In es, this message translates to:
  /// **'Tienda'**
  String get giftFieldStore;

  /// Campo del enlace al regalo.
  ///
  /// In es, this message translates to:
  /// **'Enlace'**
  String get giftFieldUrl;

  /// Botón y ayuda que abren en el navegador el enlace de un regalo.
  ///
  /// In es, this message translates to:
  /// **'Abrir enlace'**
  String get giftLinkOpen;

  /// Aviso cuando el enlace de un regalo no se puede abrir: se copia al portapapeles.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir el navegador. Enlace copiado.'**
  String get giftLinkCopied;

  /// Campo de nota.
  ///
  /// In es, this message translates to:
  /// **'Nota'**
  String get giftFieldNote;

  /// Campo de la talla o la edad del juguete.
  ///
  /// In es, this message translates to:
  /// **'Talla o edad'**
  String get giftFieldSize;

  /// Interruptor de encargo.
  ///
  /// In es, this message translates to:
  /// **'Es un encargo: lo pidió alguien'**
  String get giftRequestSwitch;

  /// Campo: quién pidió el regalo.
  ///
  /// In es, this message translates to:
  /// **'Quién lo pidió'**
  String get giftRequestedByField;

  /// Opción para escribir un nombre que no está en la lista.
  ///
  /// In es, this message translates to:
  /// **'Otra persona…'**
  String get giftRequestedByOther;

  /// Campo del nombre libre de quien pidió el regalo.
  ///
  /// In es, this message translates to:
  /// **'Nombre de quien lo pidió'**
  String get giftRequestedByName;

  /// Campo con la nota del encargo.
  ///
  /// In es, this message translates to:
  /// **'Nota del encargo'**
  String get giftRequestNote;

  /// Interruptor de sorpresa.
  ///
  /// In es, this message translates to:
  /// **'Es una sorpresa'**
  String get giftSurpriseSwitch;

  /// Explicación del interruptor de sorpresa.
  ///
  /// In es, this message translates to:
  /// **'Se marca para que nadie lo cuente delante de quien lo recibe.'**
  String get giftSurpriseHint;

  /// Botón que borra el regalo.
  ///
  /// In es, this message translates to:
  /// **'Borrar regalo'**
  String get giftDelete;

  /// Título del diálogo que pregunta antes de borrar algo.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar «{name}»?'**
  String confirmDeleteTitle(String name);

  /// Consecuencia de borrar, en el diálogo de confirmación.
  ///
  /// In es, this message translates to:
  /// **'Se borra también en los móviles de tu familia.'**
  String get confirmDeleteBody;

  /// Línea de la cabecera de una persona: lo comprado de su próxima ocasión.
  ///
  /// In es, this message translates to:
  /// **'{occasion} · {done} de {total} comprados'**
  String personCompletionProgress(String occasion, int done, int total);

  /// Línea de la cabecera de una persona cuando ya tiene todo comprado.
  ///
  /// In es, this message translates to:
  /// **'Todo comprado para {occasion}'**
  String personCompletionDone(String occasion);

  /// Error al guardar un regalo.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido guardar el regalo.'**
  String get giftSaveError;

  /// Título del aviso de duplicado al guardar.
  ///
  /// In es, this message translates to:
  /// **'Posible duplicado'**
  String get giftDuplicateTitle;

  /// Texto del aviso de duplicado al guardar.
  ///
  /// In es, this message translates to:
  /// **'«{title}» se parece a un regalo que ya está apuntado para {person} ({giver}).'**
  String giftDuplicateBody(String title, String person, String giver);

  /// Botón que guarda aunque haya un posible duplicado.
  ///
  /// In es, this message translates to:
  /// **'Guardar igualmente'**
  String get giftDuplicateSave;

  /// Botón que lleva a revisar un posible duplicado.
  ///
  /// In es, this message translates to:
  /// **'Revisar'**
  String get giftDuplicateReview;

  /// Subtítulo de la pantalla Familia.
  ///
  /// In es, this message translates to:
  /// **'Quién regala qué a cada persona'**
  String get familySubtitle;

  /// Cabecera de la primera columna de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'Regala'**
  String get familyGiverHeader;

  /// Celda de la rejilla con regalos sin precio.
  ///
  /// In es, this message translates to:
  /// **'Sin precio'**
  String get familyNoPrice;

  /// Celda vacía de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'Nada aún'**
  String get familyNothingYet;

  /// Leyenda de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'Todo comprado'**
  String get familyLegendAllBought;

  /// Leyenda de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'Algo pendiente'**
  String get familyLegendPending;

  /// Leyenda de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'Posible duplicado'**
  String get familyLegendDuplicate;

  /// Etiqueta accesible de una celda de la rejilla con regalos.
  ///
  /// In es, this message translates to:
  /// **'{giver} para {person}: {gifts}, {price}, {state}'**
  String familyCellLabel(
    String giver,
    String person,
    String gifts,
    String price,
    String state,
  );

  /// Etiqueta accesible de una celda vacía de la rejilla.
  ///
  /// In es, this message translates to:
  /// **'{giver} para {person}: nada todavía, añadir regalo'**
  String familyCellEmptyLabel(String giver, String person);

  /// Aviso corto de duplicado sobre la rejilla: para quién y qué regalo.
  ///
  /// In es, this message translates to:
  /// **'Posible duplicado: «{title}» para {person}'**
  String familyDuplicateBanner(String person, String title);

  /// Cuántos duplicados más hay además del que se enseña.
  ///
  /// In es, this message translates to:
  /// **'y {count} más'**
  String familyDuplicateMore(int count);

  /// Título de la hoja y etiqueta del botón para añadir una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Nueva ocasión'**
  String get occasionNew;

  /// Título de la hoja para cambiar una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Editar ocasión'**
  String get occasionEdit;

  /// Ejemplo del campo del nombre de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Comunión, fin de curso…'**
  String get occasionNameHint;

  /// Campo de la fecha de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Fecha'**
  String get occasionDate;

  /// Botón que abre el selector de fecha de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Elegir fecha'**
  String get occasionDatePick;

  /// Error cuando falta la fecha de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Elige una fecha.'**
  String get occasionDateRequired;

  /// Interruptor de ocasión que se repite.
  ///
  /// In es, this message translates to:
  /// **'Se repite cada año'**
  String get occasionRepeats;

  /// Aviso en la hoja de un cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'La fecha sale del cumpleaños de la persona.'**
  String get occasionBirthdayDateHint;

  /// Días que faltan para una ocasión.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Hoy} one{Falta {count} día} other{Faltan {count} días}}'**
  String occasionDaysLeft(int count);

  /// Ocasión que no se repite y ya pasó.
  ///
  /// In es, this message translates to:
  /// **'Ya pasó'**
  String get occasionPassed;

  /// Fila de Ocasiones que abre el presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto de la casa'**
  String get budgetCardTitle;

  /// Descripción de la fila del presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto, gastado y lo que queda'**
  String get budgetCardHint;

  /// Cabecera de la lista de personas en una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Cada persona'**
  String get occasionPeopleSection;

  /// Cuántos regalos hay en casa sin envolver.
  ///
  /// In es, this message translates to:
  /// **'por envolver'**
  String get occasionToWrap;

  /// Cuántos regalos comprados no han llegado.
  ///
  /// In es, this message translates to:
  /// **'por llegar'**
  String get occasionToArrive;

  /// Aviso en una ocasión sin regalos.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay regalos para esta ocasión.'**
  String get occasionNoGifts;

  /// Una persona sin regalos en una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Sin regalos todavía'**
  String get occasionNoGiftsYet;

  /// Etiqueta accesible de la barra de reparto entre ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Reparto de {name}: {parts}'**
  String occasionSplitLabel(String name, String parts);

  /// Cabecera de lo decidido sin comprar, agrupado por tienda.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de comprar'**
  String get occasionPendingBuySection;

  /// Aviso cuando no hay nada pendiente de comprar.
  ///
  /// In es, this message translates to:
  /// **'Nada decidido todavía. Cuando una idea pase a Decidido, aparecerá aquí agrupada por tienda.'**
  String get occasionPendingEmpty;

  /// Grupo de regalos sin tienda.
  ///
  /// In es, this message translates to:
  /// **'Sin tienda'**
  String get occasionStoreNone;

  /// Etiqueta accesible del botón de comprado.
  ///
  /// In es, this message translates to:
  /// **'Marcar {item} como comprado'**
  String occasionMarkBought(String item);

  /// Cabecera de los regalos que son solo una idea.
  ///
  /// In es, this message translates to:
  /// **'Ideas'**
  String get occasionIdeasSection;

  /// Título de la pantalla del presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto'**
  String get budgetTitle;

  /// Subtítulo del presupuesto cuando ninguna ocasión tiene presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Lo pones tú en cada ocasión. Gastado suma el precio real de lo que paga la casa; si algo ya está comprado y no tiene precio real, cuenta el previsto.'**
  String get budgetSubtitle;

  /// Subtítulo del presupuesto cuando alguna ocasión tiene presupuesto: las tres cifras solo cuentan esas.
  ///
  /// In es, this message translates to:
  /// **'Lo pones tú en cada ocasión. Las tres cifras solo incluyen ocasiones con presupuesto. «Gastado» suma los precios reales de lo que paga la casa. Si algo ya está comprado y no tiene precio real, cuenta el previsto.'**
  String get budgetSubtitleBudgeted;

  /// Número grande del presupuesto: lo previsto.
  ///
  /// In es, this message translates to:
  /// **'Previsto'**
  String get budgetPlanned;

  /// Número grande del presupuesto: lo gastado.
  ///
  /// In es, this message translates to:
  /// **'Gastado'**
  String get budgetSpent;

  /// Número grande del presupuesto: lo que queda.
  ///
  /// In es, this message translates to:
  /// **'Queda'**
  String get budgetLeft;

  /// Número grande del presupuesto cuando se gasta más de lo previsto.
  ///
  /// In es, this message translates to:
  /// **'Te pasas'**
  String get budgetOver;

  /// Cabecera del presupuesto por persona.
  ///
  /// In es, this message translates to:
  /// **'Por persona'**
  String get budgetByPerson;

  /// Cabecera del presupuesto por ocasión.
  ///
  /// In es, this message translates to:
  /// **'Por ocasión'**
  String get budgetByOccasion;

  /// Nota al pie del presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Lo que regalan los abuelos o los tíos cuenta como regalo, no como gasto de la casa.'**
  String get budgetNote;

  /// Estado vacío del presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay regalos que pague la casa. Marca «Paga la casa» en quien regala y pon un precio previsto.'**
  String get budgetEmpty;

  /// Campo opcional del editor de ocasión.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto (opcional)'**
  String get occasionBudgetField;

  /// Ayuda bajo el campo de presupuesto del editor de ocasión.
  ///
  /// In es, this message translates to:
  /// **'Lo que queréis gastar en esta ocasión. Déjalo vacío si no hay.'**
  String get occasionBudgetHint;

  /// Cifra grande del presupuesto: lo que la familia ha puesto de presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto'**
  String get budgetFigure;

  /// Ocasión o total sin presupuesto puesto.
  ///
  /// In es, this message translates to:
  /// **'Sin presupuesto'**
  String get budgetNone;

  /// Botón para poner el presupuesto de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Poner presupuesto'**
  String get budgetSetAction;

  /// Etiqueta del botón de editar el presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Cambiar presupuesto'**
  String get budgetEditAction;

  /// Etiqueta accesible del botón de poner el presupuesto de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Poner presupuesto a {name}'**
  String budgetSetFor(String name);

  /// Etiqueta accesible del botón de cambiar el presupuesto de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Cambiar el presupuesto de {name}'**
  String budgetEditFor(String name);

  /// Línea bajo las cifras: lo que quedaría si se compra lo que falta.
  ///
  /// In es, this message translates to:
  /// **'Si compras lo que falta, te quedarán {amount}'**
  String budgetLeftIfBought(String amount);

  /// Línea bajo las cifras de Presupuesto: lo gastado en ocasiones sin presupuesto y en regalos sin ocasión, que las tres cifras no cuentan.
  ///
  /// In es, this message translates to:
  /// **'Además, la casa ha gastado {amount} fuera de las ocasiones con presupuesto.'**
  String budgetSpentOutside(String amount);

  /// Línea bajo las cifras: lo que se pasaría si se compra lo que falta.
  ///
  /// In es, this message translates to:
  /// **'Si compras lo que falta, te pasarás {amount}'**
  String budgetOverIfBought(String amount);

  /// Título de la hoja del importe del presupuesto de una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Presupuesto de {name}'**
  String budgetSheetTitle(String name);

  /// Ayuda de la hoja del presupuesto.
  ///
  /// In es, this message translates to:
  /// **'Déjalo vacío para quitar el presupuesto.'**
  String get budgetSheetHint;

  /// Pista accesible de las tarjetas del presupuesto: al pulsarlas se abren sus regalos.
  ///
  /// In es, this message translates to:
  /// **'Ver regalos'**
  String get budgetOpenGifts;

  /// Marca de una ocasión archivada en la lista del presupuesto: sus cifras se ven en su fila pero no suman en el total.
  ///
  /// In es, this message translates to:
  /// **'Archivada · no suma'**
  String get budgetArchivedTag;

  /// Botón del presupuesto cuando no hay ninguna ocasión activa: abre el editor de ocasión.
  ///
  /// In es, this message translates to:
  /// **'Crear ocasión'**
  String get budgetCreateOccasion;

  /// Entrada de Ajustes y título de la pantalla de quién regala.
  ///
  /// In es, this message translates to:
  /// **'Quién regala'**
  String get settingsGivers;

  /// Entrada de Ajustes y título de su pantalla.
  ///
  /// In es, this message translates to:
  /// **'Bloqueo'**
  String get settingsSecurity;

  /// Entrada de Ajustes y título de su pantalla.
  ///
  /// In es, this message translates to:
  /// **'Móviles de la familia'**
  String get settingsShare;

  /// Entrada de Ajustes y título de su pantalla.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get settingsAbout;

  /// Versión de la app.
  ///
  /// In es, this message translates to:
  /// **'Versión {version}'**
  String aboutVersion(String version);

  /// Texto de privacidad de Acerca de.
  ///
  /// In es, this message translates to:
  /// **'Sin cuentas ni publicidad. Tus regalos solo salen del móvil, siempre cifrados, si conectas otro móvil o la web, creas un código de recuperación o envías una copia.'**
  String get aboutPrivacy;

  /// Fila de Acerca de que abre la política de privacidad en el navegador.
  ///
  /// In es, this message translates to:
  /// **'Política de privacidad'**
  String get aboutPrivacyPolicy;

  /// Frase bajo la fila Política de privacidad de Acerca de.
  ///
  /// In es, this message translates to:
  /// **'Se abre en el navegador.'**
  String get aboutPrivacyPolicyHint;

  /// Aviso cuando la política no se puede abrir en el navegador: el enlace se copia al portapapeles.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir el navegador. Enlace copiado.'**
  String get aboutPrivacyPolicyCopied;

  /// Fila de Acerca de que abre el correo de soporte en la app de correo.
  ///
  /// In es, this message translates to:
  /// **'Ayuda y soporte'**
  String get aboutSupport;

  /// Frase bajo la fila Ayuda y soporte de Acerca de.
  ///
  /// In es, this message translates to:
  /// **'Escríbenos desde tu app de correo.'**
  String get aboutSupportHint;

  /// Aviso cuando no hay app de correo: la dirección de soporte se copia al portapapeles.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir el correo. Dirección copiada: {email}'**
  String aboutSupportCopied(String email);

  /// Explicación de archivar.
  ///
  /// In es, this message translates to:
  /// **'Archivar quita algo de las listas sin borrar sus regalos; se recupera en Ajustes › Archivo. Eliminar lo borra para siempre.'**
  String get manageArchiveHint;

  /// Etiqueta accesible del botón de archivar.
  ///
  /// In es, this message translates to:
  /// **'Archivar {name}'**
  String manageArchiveLabel(String name);

  /// Etiqueta accesible del botón de recuperar.
  ///
  /// In es, this message translates to:
  /// **'Recuperar {name}'**
  String manageRestoreLabel(String name);

  /// Interruptor del PIN en Seguridad.
  ///
  /// In es, this message translates to:
  /// **'Bloqueo con PIN'**
  String get securityPinTitle;

  /// Descripción del interruptor del PIN.
  ///
  /// In es, this message translates to:
  /// **'Pide el PIN al abrir la app.'**
  String get securityPinHint;

  /// Fila para cambiar el PIN y título de su pantalla.
  ///
  /// In es, this message translates to:
  /// **'Cambiar PIN'**
  String get securityChangePin;

  /// Interruptor de la biometría.
  ///
  /// In es, this message translates to:
  /// **'Huella o rostro'**
  String get securityBiometrics;

  /// Descripción del interruptor de la biometría.
  ///
  /// In es, this message translates to:
  /// **'Abre la app sin teclear el PIN.'**
  String get securityBiometricsHint;

  /// Aviso cuando no hay biometría disponible.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no tiene huella ni rostro configurados.'**
  String get securityBiometricsUnavailable;

  /// Error al activar la biometría.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido activar. Comprueba la huella o el rostro del móvil.'**
  String get securityBiometricsFailed;

  /// Título de la pantalla que pide el PIN para quitarlo.
  ///
  /// In es, this message translates to:
  /// **'Quitar el PIN'**
  String get securityDisableTitle;

  /// Explicación al quitar el PIN.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN para quitar el bloqueo.'**
  String get securityDisablePrompt;

  /// Explicación al cambiar el PIN.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN actual.'**
  String get securityChangeCurrentPrompt;

  /// Aviso tras activar el PIN.
  ///
  /// In es, this message translates to:
  /// **'PIN activado.'**
  String get securityPinEnabled;

  /// Aviso tras quitar el PIN.
  ///
  /// In es, this message translates to:
  /// **'Bloqueo desactivado.'**
  String get securityPinDisabled;

  /// Aviso tras cambiar el PIN.
  ///
  /// In es, this message translates to:
  /// **'PIN cambiado.'**
  String get securityPinChanged;

  /// Nota al pie de Seguridad.
  ///
  /// In es, this message translates to:
  /// **'Sin PIN, cualquiera que coja el móvil puede ver los regalos.'**
  String get securityNote;

  /// Fila de Compartir, botón de la bienvenida y título de la pantalla de lectura.
  ///
  /// In es, this message translates to:
  /// **'Escanear el QR'**
  String get shareJoinTitle;

  /// Aviso cuando el portapapeles está vacío.
  ///
  /// In es, this message translates to:
  /// **'No hay nada que pegar. Copia antes el enlace o el texto que te enviaron.'**
  String get sharePasteEmpty;

  /// Error al enviar cambios.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido preparar el envío.'**
  String get shareSendError;

  /// Explicación de la pantalla del QR.
  ///
  /// In es, this message translates to:
  /// **'En el otro móvil abre Gift Huddle, toca «Unirme a una familia», luego «Escanear el QR» y apunta la cámara a este código.'**
  String get showQrIntro;

  /// Aviso de no hacer captura del QR.
  ///
  /// In es, this message translates to:
  /// **'No hagas captura ni lo compartas: este código da acceso a toda la lista. Enséñalo solo en persona.'**
  String get showQrWarning;

  /// Etiqueta accesible del código QR.
  ///
  /// In es, this message translates to:
  /// **'Código QR para conectar otro móvil'**
  String get showQrLabel;

  /// Subtítulo de la pantalla de lectura.
  ///
  /// In es, this message translates to:
  /// **'Apunta la cámara al código QR del otro móvil.'**
  String get joinIntro;

  /// Texto mientras el sistema pregunta por el permiso de cámara del lector de QR (sobre fondo negro, junto a un indicador).
  ///
  /// In es, this message translates to:
  /// **'Esperando el permiso de la cámara…'**
  String get scannerWaitingPermission;

  /// Título del aviso del lector de QR cuando se ha denegado el permiso de cámara y se puede volver a pedir.
  ///
  /// In es, this message translates to:
  /// **'Hace falta la cámara'**
  String get scannerDeniedTitle;

  /// Explicación bajo el título cuando se ha denegado la cámara: para qué se usa y que no se guarda nada.
  ///
  /// In es, this message translates to:
  /// **'Solo se usa para leer el código QR; no se guarda ninguna imagen.'**
  String get scannerDeniedBody;

  /// Título del aviso del lector de QR cuando la cámara está bloqueada para siempre y solo se activa en los ajustes.
  ///
  /// In es, this message translates to:
  /// **'La cámara está bloqueada'**
  String get scannerBlockedTitle;

  /// Explicación cuando la cámara está bloqueada: hay que activarla en los ajustes del móvil.
  ///
  /// In es, this message translates to:
  /// **'El permiso de cámara está denegado. Actívalo en los ajustes del móvil para leer el código QR.'**
  String get scannerBlockedBody;

  /// Título del aviso del lector de QR cuando el sistema no contestó a la petición de la cámara.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir la cámara'**
  String get scannerFailedTitle;

  /// Explicación cuando el sistema no contestó: se puede volver a intentar.
  ///
  /// In es, this message translates to:
  /// **'El móvil no ha contestado a la petición del permiso. Reintenta.'**
  String get scannerFailedBody;

  /// Botón del aviso del lector de QR: vuelve a pedir el permiso de cámara.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get scannerRetry;

  /// Botón del aviso del lector de QR: abre los ajustes de la app para dar el permiso de cámara.
  ///
  /// In es, this message translates to:
  /// **'Abrir ajustes'**
  String get scannerOpenSettings;

  /// Título del aviso al unirse a otra familia teniendo datos.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya tiene una lista'**
  String get joinConflictTitle;

  /// Texto del aviso al unirse a otra familia teniendo datos.
  ///
  /// In es, this message translates to:
  /// **'Si te unes a la del otro móvil, esta lista se sustituye y se pierden sus regalos. ¿Seguir?'**
  String get joinConflictBody;

  /// Botón que confirma sustituir la lista.
  ///
  /// In es, this message translates to:
  /// **'Sustituir y unirme'**
  String get joinReplace;

  /// Título del aviso tras emparejar.
  ///
  /// In es, this message translates to:
  /// **'Móviles conectados'**
  String get joinDoneTitle;

  /// Texto del aviso tras emparejar.
  ///
  /// In es, this message translates to:
  /// **'Ya estás en la familia de {name}. Pídele que te envíe los cambios para ver la lista.'**
  String joinDoneBody(String name);

  /// Título del aviso al abrir un fichero .gifthuddle.
  ///
  /// In es, this message translates to:
  /// **'Cambios recibidos'**
  String get incomingTitle;

  /// Resumen cuando el envío no trae nada nuevo.
  ///
  /// In es, this message translates to:
  /// **'Ya lo tenías todo al día.'**
  String get incomingNothing;

  /// Resumen cuando solo cambian personas u ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Se han actualizado personas u ocasiones.'**
  String get incomingOtherChanges;

  /// Título del aviso de error al importar.
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir el envío'**
  String get incomingFailedTitle;

  /// Parte del resumen de un envío: regalos nuevos.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{{count} regalo nuevo} other{{count} regalos nuevos}}'**
  String importAdded(int count);

  /// Parte del resumen de un envío: regalos cambiados.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{{count} cambiado} other{{count} cambiados}}'**
  String importChanged(int count);

  /// Parte del resumen de un envío: regalos borrados.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{{count} borrado} other{{count} borrados}}'**
  String importDeleted(int count);

  /// Fila que fuerza una sincronización.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar ahora'**
  String get syncNowTitle;

  /// Fila que saca este móvil de la sincronización de la familia (si es el último, borra la copia del servidor) y la apaga.
  ///
  /// In es, this message translates to:
  /// **'Dejar de sincronizar'**
  String get syncStopTitle;

  /// Descripción de Dejar de sincronizar.
  ///
  /// In es, this message translates to:
  /// **'Este móvil deja de enviar y recibir cambios.'**
  String get syncStopHint;

  /// Título del aviso de confirmación de Dejar de sincronizar.
  ///
  /// In es, this message translates to:
  /// **'¿Dejar de sincronizar?'**
  String get syncStopConfirmTitle;

  /// Texto del aviso de confirmación de Dejar de sincronizar.
  ///
  /// In es, this message translates to:
  /// **'Este móvil sale de la sincronización de la familia y deja de enviar y recibir cambios; los demás móviles siguen sincronizando entre ellos. Si es el último, también se borra la copia cifrada del servidor. Lo que hay en cada móvil se queda como está. Para volver a sincronizar, conéctalo de nuevo con otro móvil de la familia.'**
  String get syncStopConfirmBody;

  /// Aviso tras dejar de sincronizar.
  ///
  /// In es, this message translates to:
  /// **'Sincronización apagada.'**
  String get syncStopDone;

  /// Error al dejar de sincronizar.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido contactar con el servidor. Comprueba la conexión e inténtalo de nuevo.'**
  String get syncStopError;

  /// Nota de privacidad al pie de la pantalla de sincronización.
  ///
  /// In es, this message translates to:
  /// **'El servidor guarda la lista cifrada con una clave que solo tienen vuestros móviles. No ve nombres, regalos ni precios, pero sí cuándo y desde qué IP se conecta cada móvil.'**
  String get syncPrivacyNote;

  /// Estado: no hay servidor configurado.
  ///
  /// In es, this message translates to:
  /// **'La sincronización no está disponible en esta versión.'**
  String get syncStatusNotConfigured;

  /// Estado: todavía no hay familia.
  ///
  /// In es, this message translates to:
  /// **'Crea tu familia o únete a una para sincronizar.'**
  String get syncStatusNoFamily;

  /// Estado: la persona apagó la sincronización.
  ///
  /// In es, this message translates to:
  /// **'Apagada'**
  String get syncStatusDisabled;

  /// Estado: encendida, todavía sin sincronizar.
  ///
  /// In es, this message translates to:
  /// **'Pendiente de sincronizar'**
  String get syncStatusIdle;

  /// Estado: encendida, pero la familia aún no tiene un segundo móvil emparejado; hasta entonces no se sube nada al servidor.
  ///
  /// In es, this message translates to:
  /// **'Empezará cuando emparejes otro móvil'**
  String get syncStatusWaitingPeer;

  /// Aviso en el móvil que enseñó el QR de emparejar cuando el otro móvil ya ha entrado y no se sabe su nombre.
  ///
  /// In es, this message translates to:
  /// **'Se ha conectado otro móvil'**
  String get peerConnected;

  /// Aviso en el móvil que enseñó el QR de emparejar cuando el otro móvil ya ha entrado, con el nombre de ese móvil.
  ///
  /// In es, this message translates to:
  /// **'Se ha conectado otro móvil: {name}'**
  String peerConnectedNamed(String name);

  /// Estado: hablando con el servidor.
  ///
  /// In es, this message translates to:
  /// **'Sincronizando…'**
  String get syncStatusSyncing;

  /// Estado: sincronizado hace menos de un minuto.
  ///
  /// In es, this message translates to:
  /// **'Sincronizado ahora'**
  String get syncStatusSyncedNow;

  /// Estado: sincronizado hace unos minutos.
  ///
  /// In es, this message translates to:
  /// **'Sincronizado hace {minutes} min'**
  String syncStatusSyncedMinutes(int minutes);

  /// Estado: sincronizado hace unas horas.
  ///
  /// In es, this message translates to:
  /// **'Sincronizado hace {hours} h'**
  String syncStatusSyncedHours(int hours);

  /// Estado: sincronizado hace unos días.
  ///
  /// In es, this message translates to:
  /// **'Sincronizado hace {days} d'**
  String syncStatusSyncedDays(int days);

  /// Estado: no hay red; los cambios están guardados en el móvil.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión, se enviará luego'**
  String get syncStatusOffline;

  /// Estado: error de sincronización.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido sincronizar'**
  String get syncStatusError;

  /// Detalle del error: autenticación rechazada.
  ///
  /// In es, this message translates to:
  /// **'El servidor no acepta la clave de esta familia.'**
  String get syncIssueAuth;

  /// Detalle del error: el reloj del otro móvil va más de un día adelantado.
  ///
  /// In es, this message translates to:
  /// **'Otro móvil tiene la fecha y la hora mal puestas. Corrígelas en ese móvil.'**
  String get syncIssueClockDrift;

  /// Detalle del error: el sobre pasa del límite de tamaño.
  ///
  /// In es, this message translates to:
  /// **'La lista es demasiado grande para sincronizar.'**
  String get syncIssueTooLarge;

  /// Detalle del error: fallo del servidor.
  ///
  /// In es, this message translates to:
  /// **'El servidor no responde bien. Se volverá a intentar.'**
  String get syncIssueServer;

  /// Detalle del error: límite de peticiones.
  ///
  /// In es, this message translates to:
  /// **'Demasiadas peticiones seguidas. Se volverá a intentar en un momento.'**
  String get syncIssueRateLimited;

  /// Detalle del error: el sobre del servidor no se puede descifrar.
  ///
  /// In es, this message translates to:
  /// **'Los datos del servidor no se pueden abrir con la clave de esta familia.'**
  String get syncIssueUnreadable;

  /// Detalle del error: otro fallo.
  ///
  /// In es, this message translates to:
  /// **'Algo ha fallado. Se volverá a intentar.'**
  String get syncIssueUnknown;

  /// Fila de Compartir y título de la pantalla para invitar con un enlace.
  ///
  /// In es, this message translates to:
  /// **'Invitar a alguien'**
  String get inviteRowTitle;

  /// Fila de Compartir y título de la pantalla para entrar con un enlace de invitación.
  ///
  /// In es, this message translates to:
  /// **'Unirme con un enlace'**
  String get joinInviteRowTitle;

  /// Texto principal de la pantalla Invitar a alguien.
  ///
  /// In es, this message translates to:
  /// **'Crea un enlace para que otra persona se una a tu familia desde su móvil, sin estar delante.'**
  String get inviteIntro;

  /// Explicación de que hará falta aprobar la petición.
  ///
  /// In es, this message translates to:
  /// **'El enlace no lleva ninguna clave: solo sirve para pedir entrada. Te llegará la petición con un código de 6 cifras y tendrás que aceptarla tú. Caduca a las 24 horas y sirve para una sola persona.'**
  String get inviteHowItWorks;

  /// Botón que crea la invitación y abre la hoja de compartir.
  ///
  /// In es, this message translates to:
  /// **'Crear enlace e invitar'**
  String get inviteCreate;

  /// Aviso cuando no se puede invitar porque la sincronización no está lista.
  ///
  /// In es, this message translates to:
  /// **'Para invitar a distancia hace falta tener la sincronización encendida y con conexión.'**
  String get inviteNeedSync;

  /// Botón que abre la pantalla de sincronización.
  ///
  /// In es, this message translates to:
  /// **'Encender la sincronización'**
  String get inviteGoToSync;

  /// Texto que acompaña al enlace al compartirlo.
  ///
  /// In es, this message translates to:
  /// **'Te invito a mi lista de Gift Huddle. Abre el enlace y pide entrar: {link}'**
  String inviteShareText(String link);

  /// Título mientras nadie ha pedido entrar.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que abran el enlace'**
  String get inviteWaitingTitle;

  /// Texto mientras nadie ha pedido entrar.
  ///
  /// In es, this message translates to:
  /// **'Cuando la otra persona lo abra, aquí verás su petición. Puedes salir de esta pantalla: la invitación sigue activa hasta que caduque.'**
  String get inviteWaitingBody;

  /// Cuándo caduca la invitación.
  ///
  /// In es, this message translates to:
  /// **'Caduca el {date} a las {time}'**
  String inviteExpires(DateTime date, DateTime time);

  /// Botón que vuelve a abrir la hoja de compartir con el mismo enlace.
  ///
  /// In es, this message translates to:
  /// **'Compartir el enlace otra vez'**
  String get inviteShareAgain;

  /// Botón que mata la invitación en el servidor.
  ///
  /// In es, this message translates to:
  /// **'Cancelar invitación'**
  String get inviteCancel;

  /// Título cuando llega una petición de entrada.
  ///
  /// In es, this message translates to:
  /// **'{name} quiere unirse'**
  String inviteRequestTitle(String name);

  /// Explicación en la pantalla de aprobación.
  ///
  /// In es, this message translates to:
  /// **'Si no esperabas esta petición, recházala. Si los dos códigos no coinciden, no des acceso.'**
  String get inviteRequestBody;

  /// Etiqueta del código de 6 cifras.
  ///
  /// In es, this message translates to:
  /// **'Código de verificación'**
  String get inviteCodeLabel;

  /// Botón que da acceso tras comparar el código con la otra persona.
  ///
  /// In es, this message translates to:
  /// **'Los códigos coinciden, dar acceso'**
  String get inviteAccept;

  /// Botón que rechaza la petición de entrada.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get inviteReject;

  /// Título tras aceptar.
  ///
  /// In es, this message translates to:
  /// **'Invitación aceptada'**
  String get inviteApprovedTitle;

  /// Texto tras dar acceso.
  ///
  /// In es, this message translates to:
  /// **'{name} ya puede entrar: su móvil está recogiendo la clave.'**
  String inviteApprovedBody(String name);

  /// Texto tras rechazar o cancelar.
  ///
  /// In es, this message translates to:
  /// **'Has rechazado la petición. El enlace ya no sirve.'**
  String get inviteRejectedBody;

  /// Texto cuando la invitación caducó.
  ///
  /// In es, this message translates to:
  /// **'La invitación ha caducado.'**
  String get inviteExpiredBody;

  /// Botón para empezar otra invitación.
  ///
  /// In es, this message translates to:
  /// **'Invitar a otra persona'**
  String get inviteNew;

  /// Error de red al invitar.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar con el servidor. Inténtalo de nuevo.'**
  String get inviteErrorNetwork;

  /// Otro error al invitar.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido completar la invitación. Inténtalo de nuevo.'**
  String get inviteErrorUnknown;

  /// Texto principal de la pantalla Unirme con un enlace.
  ///
  /// In es, this message translates to:
  /// **'Pega el enlace que te enviaron. Quien te invitó tendrá que aceptar tu petición.'**
  String get joinInviteIntro;

  /// Campo donde se pega el enlace.
  ///
  /// In es, this message translates to:
  /// **'Enlace de invitación'**
  String get joinInviteFieldLabel;

  /// Botón que pega el portapapeles en el campo del enlace.
  ///
  /// In es, this message translates to:
  /// **'Pegar'**
  String get joinInvitePaste;

  /// Botón que envía la petición de entrada.
  ///
  /// In es, this message translates to:
  /// **'Pedir entrada'**
  String get joinInviteAsk;

  /// Error: el texto pegado no es una invitación.
  ///
  /// In es, this message translates to:
  /// **'Este texto no es un enlace de invitación de Gift Huddle.'**
  String get joinInviteBadLink;

  /// Error: no hay servidor configurado.
  ///
  /// In es, this message translates to:
  /// **'Las invitaciones a distancia no están disponibles en esta versión.'**
  String get joinInviteUnavailable;

  /// Error de red al pedir entrada.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar con el servidor. Comprueba la conexión.'**
  String get joinInviteNetwork;

  /// Error: el paquete cifrado no se pudo abrir.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido abrir la invitación. Pide un enlace nuevo.'**
  String get joinInviteTampered;

  /// Otro error al unirse con un enlace.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido completar. Inténtalo de nuevo.'**
  String get joinInviteUnknown;

  /// Error: la invitación ya tiene una petición.
  ///
  /// In es, this message translates to:
  /// **'Esta invitación ya la ha pedido otra persona. Pide un enlace nuevo.'**
  String get joinInviteTaken;

  /// Resultado cuando la invitación murió.
  ///
  /// In es, this message translates to:
  /// **'La invitación ha caducado o no se ha aceptado.'**
  String get joinInviteGone;

  /// Título mientras se espera la aprobación.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que te acepten'**
  String get joinInviteWaitingTitle;

  /// Texto mientras se espera a que la otra persona vea la petición.
  ///
  /// In es, this message translates to:
  /// **'Quien te invitó tiene que ver tu petición. En unos segundos verás aquí un código para comparar con esa persona. Puedes esperar hasta 10 minutos.'**
  String get joinInviteWaitingBody;

  /// Título de la comparación del código.
  ///
  /// In es, this message translates to:
  /// **'Compara el código'**
  String get joinInviteConfirmTitle;

  /// Texto de la comparación del código.
  ///
  /// In es, this message translates to:
  /// **'Pregunta a quien te invitó qué código ve en su móvil. Tiene que ser el mismo que este. Cuando lo confirme en su móvil, entrarás en la familia.'**
  String get joinInviteConfirmBody;

  /// Botón que cancela porque el código no coincide.
  ///
  /// In es, this message translates to:
  /// **'No coincide, cancelar'**
  String get joinInviteMismatch;

  /// Texto tras cancelar por un código distinto.
  ///
  /// In es, this message translates to:
  /// **'Has cancelado y no has entrado en la familia. Pide a quien te invitó un enlace nuevo.'**
  String get joinInviteMismatchBody;

  /// Aviso tras entrar con una invitación.
  ///
  /// In es, this message translates to:
  /// **'Ya estás en la familia de {name}. La lista llegará en unos segundos.'**
  String joinInviteDoneBody(String name);

  /// Botón que vuelve al principio de Unirme con un enlace.
  ///
  /// In es, this message translates to:
  /// **'Volver a empezar'**
  String get joinInviteRestart;

  /// Detalle del error: el servidor rechaza la primera subida por tamaño (máx. 256 KiB).
  ///
  /// In es, this message translates to:
  /// **'La lista es demasiado grande para la primera subida.'**
  String get syncIssueFirstUpload;

  /// Aviso sobre el código en la pantalla de aprobación.
  ///
  /// In es, this message translates to:
  /// **'Compara este código con el que ve la otra persona.'**
  String get inviteCompareNotice;

  /// Línea bajo el código mientras quien invita aún no ha dado acceso.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que confirme en su móvil…'**
  String get joinInviteWaitingForConfirm;

  /// Chip del selector de ocasión de Reparto que enseña los regalos de todas las ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Todas'**
  String get familyChipAll;

  /// Chip del selector de ocasión de Reparto que reúne los cumpleaños de todas las personas.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños'**
  String get familyChipBirthdays;

  /// Etiqueta accesible del grupo de chips que eligen la ocasión en Reparto.
  ///
  /// In es, this message translates to:
  /// **'Ocasión'**
  String get familyOccasionPickerLabel;

  /// Subtítulo de Reparto cuando se ven los regalos de todas las ocasiones.
  ///
  /// In es, this message translates to:
  /// **'Todas las ocasiones'**
  String get familyForAll;

  /// Subtítulo de Reparto con la ocasión elegida y su fecha: «Para Reyes, 6 de enero».
  ///
  /// In es, this message translates to:
  /// **'Para {name}, {date}'**
  String familyForOccasion(String name, String date);

  /// Subtítulo de Reparto cuando se ven los cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Para los cumpleaños'**
  String get familyForBirthdays;

  /// Parte de la etiqueta accesible de una celda de Reparto con las ocasiones de sus regalos; {names} es una lista separada por comas como «Tió, Reyes».
  ///
  /// In es, this message translates to:
  /// **'para {names}'**
  String familyCellOccasions(String names);

  /// Etiqueta accesible de los indicadores del carrusel de cuenta atrás de Personas.
  ///
  /// In es, this message translates to:
  /// **'Ocasión {page} de {total}'**
  String peopleCarouselPage(int page, int total);

  /// Etiqueta accesible de los indicadores del carrusel de cuenta atrás de Personas cuando se ven dos tarjetas a la vez (tablet).
  ///
  /// In es, this message translates to:
  /// **'Ocasiones {first} y {last} de {total}'**
  String peopleCarouselRange(int first, int last, int total);

  /// Título de la lista de tipos al crear una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Tipo de ocasión'**
  String get occasionTypeTitle;

  /// Tipo de ocasión: la fecha cambia cada año.
  ///
  /// In es, this message translates to:
  /// **'Año Nuevo Chino'**
  String get occasionKindChineseNewYear;

  /// Tipo de ocasión: regalo de casados.
  ///
  /// In es, this message translates to:
  /// **'Boda'**
  String get occasionKindWedding;

  /// Tipo de ocasión: aniversario de pareja o de boda.
  ///
  /// In es, this message translates to:
  /// **'Aniversario'**
  String get occasionKindAnniversary;

  /// Tipo de ocasión: 23 de abril, libro y rosa.
  ///
  /// In es, this message translates to:
  /// **'Sant Jordi'**
  String get occasionKindSantJordi;

  /// Tipo de ocasión: 14 de febrero.
  ///
  /// In es, this message translates to:
  /// **'San Valentín'**
  String get occasionKindValentine;

  /// Tipo de ocasión: bautizo o nacimiento de un bebé.
  ///
  /// In es, this message translates to:
  /// **'Bautizo o nacimiento'**
  String get occasionKindBaptism;

  /// Tipo de ocasión: primera comunión.
  ///
  /// In es, this message translates to:
  /// **'Comunión'**
  String get occasionKindCommunion;

  /// Tipo de ocasión: graduación o fin de curso.
  ///
  /// In es, this message translates to:
  /// **'Graduación o fin de curso'**
  String get occasionKindGraduation;

  /// Tipo de ocasión libre: con nombre, color e icono a elegir.
  ///
  /// In es, this message translates to:
  /// **'Otra'**
  String get occasionKindCustom;

  /// Aviso bajo la fecha de la ocasión Año Nuevo Chino.
  ///
  /// In es, this message translates to:
  /// **'La fecha cambia cada año y se calcula sola.'**
  String get occasionChineseNewYearHint;

  /// Etiqueta de la fila de colores de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get occasionCustomColor;

  /// Etiqueta de la fila de iconos de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Icono'**
  String get occasionCustomIcon;

  /// Nombre del color turquesa de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Turquesa'**
  String get occasionColorTeal;

  /// Nombre del color pizarra de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Pizarra'**
  String get occasionColorSlate;

  /// Nombre del icono estrella de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Estrella'**
  String get occasionIconStar;

  /// Nombre del icono corazón de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Corazón'**
  String get occasionIconHeart;

  /// Nombre del icono casa de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Casa'**
  String get occasionIconHome;

  /// Nombre del icono viaje de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Viaje'**
  String get occasionIconTrip;

  /// Nombre del icono escuela de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Escuela'**
  String get occasionIconSchool;

  /// Nombre del icono mascota de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Mascota'**
  String get occasionIconPets;

  /// Nombre del icono bebé de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Bebé'**
  String get occasionIconBaby;

  /// Nombre del icono trabajo de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Trabajo'**
  String get occasionIconWork;

  /// Nombre del icono música de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Música'**
  String get occasionIconMusic;

  /// Nombre del icono deporte de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Deporte'**
  String get occasionIconSport;

  /// Nombre del icono flor de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Flor'**
  String get occasionIconFlower;

  /// Nombre del icono fiesta de una ocasión «Otra».
  ///
  /// In es, this message translates to:
  /// **'Fiesta'**
  String get occasionIconParty;

  /// Título de la sección del carrusel de próximas ocasiones en Personas.
  ///
  /// In es, this message translates to:
  /// **'Próximas ocasiones'**
  String get peopleUpcomingTitle;

  /// Fecha de hoy a la derecha del título del carrusel.
  ///
  /// In es, this message translates to:
  /// **'Hoy, {date}'**
  String todayShort(DateTime date);

  /// Unidad junto al número de la tarjeta del carrusel.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{día} other{días}}'**
  String daysUnit(int count);

  /// Regalos comprados de una ocasión, en la tarjeta del carrusel.
  ///
  /// In es, this message translates to:
  /// **'{done} de {total} {total, plural, one{regalo comprado} other{regalos comprados}}'**
  String occasionGiftsBought(int done, int total);

  /// Grupo de la lista de ocasiones: fiestas y demás fechas que no son cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Fiestas'**
  String get occasionsGroupCelebrations;

  /// Grupo de la lista de ocasiones: los cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños'**
  String get occasionsGroupBirthdays;

  /// Fila de totales al pie de la rejilla de Reparto: importe y regalos de cada persona.
  ///
  /// In es, this message translates to:
  /// **'Total'**
  String get familyTotalRow;

  /// Cabecera de la primera columna de la rejilla de Reparto: las personas que reciben.
  ///
  /// In es, this message translates to:
  /// **'Recibe'**
  String get familyRecipientHeader;

  /// Leyenda de la rejilla: celda vacía.
  ///
  /// In es, this message translates to:
  /// **'Nada'**
  String get familyLegendNothing;

  /// Leyenda de la rejilla: hay regalos y falta comprar alguno.
  ///
  /// In es, this message translates to:
  /// **'Por comprar'**
  String get familyLegendToBuy;

  /// Bajo el nombre de una persona: cuántos regalos suyos no tienen quién los regale.
  ///
  /// In es, this message translates to:
  /// **'{count} sin quién'**
  String familyNoGiverCount(int count);

  /// Título de la hoja de una celda vacía.
  ///
  /// In es, this message translates to:
  /// **'{giver} aún no regala nada a {person}'**
  String repartoSheetNobodyYet(String giver, String person);

  /// Texto de la hoja de una celda vacía cuando la persona tiene regalos sin quién regala.
  ///
  /// In es, this message translates to:
  /// **'{person} tiene regalos sin quién los regale: toca «¿Quién?» para darlos.'**
  String repartoSheetUnassignedHint(String person);

  /// Texto de la hoja de una celda vacía cuando no hay nada que repartir.
  ///
  /// In es, this message translates to:
  /// **'Apunta un regalo nuevo para empezar.'**
  String get repartoSheetStartHint;

  /// Resumen bajo el título de la hoja de una celda con regalos.
  ///
  /// In es, this message translates to:
  /// **'{gifts} · {price} · toca quién regala para cambiarlo'**
  String repartoSheetSummary(String gifts, String price);

  /// Chip de un regalo que aún no tiene quién lo regale.
  ///
  /// In es, this message translates to:
  /// **'¿Quién?'**
  String get repartoSheetWho;

  /// Opción del chip de quién regala para dejar el regalo sin dueño.
  ///
  /// In es, this message translates to:
  /// **'Nadie'**
  String get repartoSheetNobody;

  /// Botón de la hoja de una celda con regalos.
  ///
  /// In es, this message translates to:
  /// **'Añadir regalo'**
  String get repartoSheetAddGift;

  /// Botón de la hoja de una celda vacía.
  ///
  /// In es, this message translates to:
  /// **'Regalo nuevo de {giver}'**
  String repartoSheetNewGiftFrom(String giver);

  /// Enlace de la hoja a la lista completa de la persona.
  ///
  /// In es, this message translates to:
  /// **'Ver la lista de {person}'**
  String repartoSheetOpenList(String person);

  /// Título de la hoja con los regalos de una persona que nadie ha asumido.
  ///
  /// In es, this message translates to:
  /// **'Sin quién regala'**
  String get repartoSheetNoGiver;

  /// Etiqueta accesible del chip de quién regala en la hoja.
  ///
  /// In es, this message translates to:
  /// **'Quién regala: {giver}. Cambiar'**
  String repartoSheetChipLabel(String giver);

  /// Etiqueta accesible de la hoja de una celda.
  ///
  /// In es, this message translates to:
  /// **'Regalos de {giver} para {person}'**
  String repartoSheetLabel(String giver, String person);

  /// Pista bajo el teclado de bloqueo cuando la huella o el rostro están activados.
  ///
  /// In es, this message translates to:
  /// **'Toca la huella para entrar'**
  String get lockBiometricHint;

  /// Etiqueta accesible del conmutador de las dos vistas de Reparto.
  ///
  /// In es, this message translates to:
  /// **'Vista de Reparto'**
  String get repartoViewLabel;

  /// Botón del conmutador: la vista de rejilla.
  ///
  /// In es, this message translates to:
  /// **'Rejilla'**
  String get repartoViewGrid;

  /// Botón del conmutador: la vista por ocasión. También es el subtítulo de Reparto en esa vista.
  ///
  /// In es, this message translates to:
  /// **'Por ocasión'**
  String get repartoViewOccasion;

  /// Título de las casillas con el número de regalos de cada persona en una ocasión.
  ///
  /// In es, this message translates to:
  /// **'Cuántos paquetes abre cada uno'**
  String get repartoOccasionPackets;

  /// En la franja de una ocasión: cuántos regalos faltan por comprar.
  ///
  /// In es, this message translates to:
  /// **'{count} por comprar'**
  String repartoOccasionToBuy(int count);

  /// En la tarjeta de una persona sin regalos en la ocasión que se ve.
  ///
  /// In es, this message translates to:
  /// **'Nada en {occasion}'**
  String repartoOccasionNothingIn(String occasion);

  /// Chip para añadir el primer regalo de una persona en la ocasión.
  ///
  /// In es, this message translates to:
  /// **'Añadir'**
  String get repartoOccasionAddShort;

  /// Título de una ocasión sin ningún regalo.
  ///
  /// In es, this message translates to:
  /// **'Nada todavía en {occasion}'**
  String repartoOccasionEmptyTitle(String occasion);

  /// Frase de una ocasión sin regalos.
  ///
  /// In es, this message translates to:
  /// **'Cuando apuntes un regalo para este día, aquí verás quién lo trae y cuántos paquetes abre cada uno.'**
  String get repartoOccasionEmptyMessage;

  /// Nombre de la hoja de una persona de Reparto, para el lector de pantalla.
  ///
  /// In es, this message translates to:
  /// **'Ficha de {person}'**
  String repartoPersonSheetLabel(String person);

  /// Etiqueta del nombre de una persona en Reparto: abre su ficha.
  ///
  /// In es, this message translates to:
  /// **'Abrir la ficha de {person}'**
  String repartoPersonOpen(String person);

  /// Etiqueta junto al nombre de la persona dueña de este móvil en Reparto (rejilla, lista por ocasión y su ficha).
  ///
  /// In es, this message translates to:
  /// **'Yo'**
  String get repartoSelfTag;

  /// Nombre de la persona dueña de este móvil para el lector de pantalla; va dentro de «Abrir la ficha de…».
  ///
  /// In es, this message translates to:
  /// **'{name} (yo)'**
  String repartoSelfName(String name);

  /// Frase bajo el nombre en la ficha de una persona de Reparto.
  ///
  /// In es, this message translates to:
  /// **'Cómo sale en Reparto. No se borra ningún regalo.'**
  String get repartoPersonSheetSub;

  /// Casilla de la ficha: la persona sale (o no) en Reparto.
  ///
  /// In es, this message translates to:
  /// **'Sale en el reparto'**
  String get repartoPersonInReparto;

  /// Explicación de la casilla «Sale en el reparto».
  ///
  /// In es, this message translates to:
  /// **'Si lo quitas, pasa a «Fuera del reparto».'**
  String get repartoPersonInRepartoHint;

  /// Título de la lista de ocasiones de la ficha: una casilla por ocasión.
  ///
  /// In es, this message translates to:
  /// **'Le regaláis en'**
  String get repartoPersonOccasions;

  /// Bloque plegable al final de la rejilla con las personas que no salen en Reparto.
  ///
  /// In es, this message translates to:
  /// **'Fuera del reparto · {count}'**
  String familyOutsideTitle(int count);

  /// Bajo el nombre de una persona del bloque «Fuera del reparto».
  ///
  /// In es, this message translates to:
  /// **'No sale en el reparto'**
  String get familyOutsideNote;

  /// Botón que devuelve una persona al reparto.
  ///
  /// In es, this message translates to:
  /// **'Volver a incluir'**
  String get familyIncludeAgain;

  /// Franja gris de la fila de una persona a la que no se le regala en la ocasión que se ve.
  ///
  /// In es, this message translates to:
  /// **'No le regaláis en {occasion}'**
  String familyExcludedStrip(String occasion);

  /// Bajo el nombre de una persona en «Todas»: las ocasiones en las que no se le regala.
  ///
  /// In es, this message translates to:
  /// **'Sin {occasions}'**
  String familySkipsLabel(String occasions);

  /// Leyenda de la rejilla: franja gris, no se le regala en esa ocasión.
  ///
  /// In es, this message translates to:
  /// **'No le regaláis'**
  String get familyLegendExcluded;

  /// Grupo de la vista por ocasión con las personas a las que no se les regala en ella.
  ///
  /// In es, this message translates to:
  /// **'No les regaláis en {occasion}'**
  String repartoOccasionNotGiving(String occasion);

  /// Botón que elimina para siempre una persona, quien regala o una ocasión, tras confirmar.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get actionEliminate;

  /// Etiqueta accesible del botón de eliminar.
  ///
  /// In es, this message translates to:
  /// **'Eliminar {name}'**
  String manageDeleteLabel(String name);

  /// Línea bajo el nombre en Ajustes › Personas: explica por qué Archivar y Eliminar están desactivados para la persona elegida en «Este móvil es de».
  ///
  /// In es, this message translates to:
  /// **'Es la persona de este móvil.'**
  String get manageLockedThisDevice;

  /// Línea bajo el nombre en Ajustes › Personas: explica por qué Archivar y Eliminar están desactivados para la persona dueña de otro móvil conectado de la familia.
  ///
  /// In es, this message translates to:
  /// **'Es la persona de otro móvil de la familia.'**
  String get manageLockedOtherDevice;

  /// Título del diálogo que pregunta antes de eliminar a una persona o a quien regala.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar a {name}?'**
  String deletePersonTitle(String name);

  /// Título del diálogo que pregunta antes de eliminar una ocasión.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar «{name}»?'**
  String deleteOccasionTitle(String name);

  /// Consecuencia de eliminar a una persona: sus regalos se eliminan con ella. Vacío si no tiene.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{} one{Se eliminará también su regalo.} other{Se eliminarán también sus {count} regalos.}}'**
  String deletePersonGifts(int count);

  /// Consecuencia de eliminar a una persona que tiene ocasión de cumpleaños.
  ///
  /// In es, this message translates to:
  /// **'Su cumpleaños también desaparece.'**
  String get deleteBirthdayToo;

  /// Consecuencia de eliminar a quien regala: sus regalos no se borran. Vacío si no tiene.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{} one{Su regalo se quedará sin quién regala.} other{Sus {count} regalos se quedarán sin quién regala.}}'**
  String deleteGiverGifts(int count);

  /// Consecuencia de eliminar una ocasión: sus regalos no se borran. Vacío si no tiene.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{} one{Su regalo se quedará sin ocasión.} other{Sus {count} regalos se quedarán sin ocasión.}}'**
  String deleteOccasionGifts(int count);

  /// Aviso final de todo diálogo de eliminar.
  ///
  /// In es, this message translates to:
  /// **'No se puede deshacer. Se elimina también en los móviles de tu familia.'**
  String get deleteIrreversible;

  /// Consecuencia de eliminar a una persona que había pedido regalos para otras.
  ///
  /// In es, this message translates to:
  /// **'En los regalos que pidió, se borra quién los pidió.'**
  String get deleteRequestedByToo;

  /// Consecuencia de eliminar a quien regala si pagaba la casa y tenía regalos.
  ///
  /// In es, this message translates to:
  /// **'Sus importes dejan de contar en el presupuesto de la casa.'**
  String get deleteGiverBudget;

  /// Aviso cuando falla el guardado al eliminar.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido eliminar. Inténtalo de nuevo.'**
  String get deleteError;

  /// Aviso del editor de regalos cuando el regalo o su persona se eliminaron en otro móvil.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: este regalo ya no está disponible en este móvil.'**
  String get giftNotSaved;

  /// Aviso tras borrar un regalo, con la acción Deshacer.
  ///
  /// In es, this message translates to:
  /// **'«{name}» borrado'**
  String giftDeletedNotice(String name);

  /// Primer grupo de Ajustes: personas, quién regala, ocasiones y archivo.
  ///
  /// In es, this message translates to:
  /// **'Familia'**
  String get settingsSectionFamily;

  /// Grupo de Ajustes con lo que solo afecta a este móvil: de quién es, bloqueo, idioma y apariencia.
  ///
  /// In es, this message translates to:
  /// **'Este móvil'**
  String get settingsSectionDevice;

  /// Primera fila del grupo Este móvil en Ajustes; a su derecha va el nombre de la persona dueña de este móvil, o Nadie.
  ///
  /// In es, this message translates to:
  /// **'Este móvil es de'**
  String get settingsSelf;

  /// Valor de la fila Este móvil es de cuando no se ha elegido a nadie, y última opción de su hoja.
  ///
  /// In es, this message translates to:
  /// **'Nadie'**
  String get settingsSelfNobody;

  /// Título de la hoja donde se elige la persona dueña de este móvil.
  ///
  /// In es, this message translates to:
  /// **'¿De quién es este móvil?'**
  String get settingsSelfSheetTitle;

  /// Frase bajo el título de la hoja ¿De quién es este móvil?: la elección se queda en este móvil.
  ///
  /// In es, this message translates to:
  /// **'Solo vale en este móvil; no se comparte.'**
  String get settingsSelfSheetHint;

  /// Aviso cuando falla el guardado al elegir de quién es este móvil.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido guardar. Inténtalo de nuevo.'**
  String get settingsSelfError;

  /// Grupo de Ajustes con los móviles de la familia y la copia de seguridad.
  ///
  /// In es, this message translates to:
  /// **'Compartir y copia'**
  String get settingsSectionShare;

  /// Último grupo de Ajustes: acerca de la app.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get settingsSectionAbout;

  /// Fila de Ajustes y título de la pantalla que reúne lo archivado.
  ///
  /// In es, this message translates to:
  /// **'Archivo'**
  String get settingsArchive;

  /// Fila de Ajustes y título de la pantalla del fichero .gifthuddle.
  ///
  /// In es, this message translates to:
  /// **'Copia de seguridad'**
  String get settingsBackup;

  /// Fila de Ajustes que abre Acerca de; a su derecha va el número de versión.
  ///
  /// In es, this message translates to:
  /// **'Acerca de Gift Huddle'**
  String get settingsAboutApp;

  /// Última fila de Ajustes, en rojo, y botón final de su confirmación: borra todos los datos de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Borrar todo'**
  String get eraseAllTitle;

  /// Frase bajo la fila Borrar todo de Ajustes.
  ///
  /// In es, this message translates to:
  /// **'La lista, el PIN y los ajustes de este móvil.'**
  String get eraseAllHint;

  /// Título del primer diálogo de Borrar todo.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar todo?'**
  String get eraseAllConfirmTitle;

  /// Texto del primer diálogo de Borrar todo: qué se borra, que no se puede deshacer y que los demás móviles no cambian.
  ///
  /// In es, this message translates to:
  /// **'Se borran de este móvil la lista entera, el PIN y los ajustes, y la app vuelve a empezar de cero. No se puede deshacer. Los demás móviles de tu familia conservan su copia.'**
  String get eraseAllConfirmBody;

  /// Frase que se añade al primer diálogo de Borrar todo cuando la app puede sincronizar: este móvil sale antes de la familia y solo el último borra la copia del servidor.
  ///
  /// In es, this message translates to:
  /// **'Antes, este móvil sale de la sincronización de la familia; si es el último, también se borra la copia cifrada del servidor.'**
  String get eraseAllConfirmServer;

  /// Botón del primer diálogo de Borrar todo: lleva al último paso.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get eraseAllContinue;

  /// Título del segundo diálogo de Borrar todo, donde se escribe una palabra para confirmar.
  ///
  /// In es, this message translates to:
  /// **'Último paso'**
  String get eraseAllTypeTitle;

  /// Texto del segundo diálogo de Borrar todo; word es la palabra de eraseAllWord.
  ///
  /// In es, this message translates to:
  /// **'Escribe {word} para confirmar que quieres borrarlo todo.'**
  String eraseAllTypeBody(String word);

  /// Palabra que hay que escribir para confirmar Borrar todo. Se compara sin distinguir mayúsculas.
  ///
  /// In es, this message translates to:
  /// **'BORRAR'**
  String get eraseAllWord;

  /// Etiqueta del campo donde se escribe la palabra que confirma Borrar todo.
  ///
  /// In es, this message translates to:
  /// **'Confirmación'**
  String get eraseAllFieldLabel;

  /// Estado del diálogo de Borrar todo mientras se borra la copia del servidor.
  ///
  /// In es, this message translates to:
  /// **'Borrando…'**
  String get eraseAllWorking;

  /// Título del diálogo de Borrar todo cuando el servidor no responde.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido contactar con el servidor'**
  String get eraseAllServerFailedTitle;

  /// Texto del diálogo de Borrar todo cuando el servidor no responde: qué pasa si se borra solo lo local.
  ///
  /// In es, this message translates to:
  /// **'Comprueba la conexión y reinténtalo. Si borras solo este móvil, seguirá en la lista de móviles de tu familia hasta que otro lo quite, y la copia cifrada se queda en el servidor para los demás (o hasta que caduque, si era el último).'**
  String get eraseAllServerFailedBody;

  /// Botón del diálogo de Borrar todo cuando el servidor no responde: lo intenta otra vez.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get eraseAllRetry;

  /// Botón del diálogo de Borrar todo cuando el servidor no responde: borra lo local y deja la copia del servidor.
  ///
  /// In es, this message translates to:
  /// **'Borrar solo este móvil'**
  String get eraseAllLocalOnly;

  /// Aviso cuando falla el borrado de los datos de este móvil.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido borrar todo. Inténtalo de nuevo.'**
  String get eraseAllFailed;

  /// Explicación de la pantalla que pide el PIN entre el primer diálogo de Borrar todo y el último paso.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN para seguir con el borrado.'**
  String get eraseAllPinPrompt;

  /// Motivo que enseña el sistema al pedir la huella o el rostro antes del último paso de Borrar todo.
  ///
  /// In es, this message translates to:
  /// **'Confirma que quieres borrar todo'**
  String get eraseAllBiometricReason;

  /// Valor de la fila Bloqueo cuando no hay PIN.
  ///
  /// In es, this message translates to:
  /// **'Sin bloqueo'**
  String get settingsLockOff;

  /// Valor de la fila Bloqueo cuando hay PIN sin huella ni rostro.
  ///
  /// In es, this message translates to:
  /// **'PIN'**
  String get settingsLockPin;

  /// Valor de la fila Bloqueo cuando hay PIN y huella o rostro.
  ///
  /// In es, this message translates to:
  /// **'PIN y biometría'**
  String get settingsLockPinBiometrics;

  /// Valor de la fila Apariencia: el color y el tema elegidos.
  ///
  /// In es, this message translates to:
  /// **'{accent} · {theme}'**
  String settingsAppearanceValue(String accent, String theme);

  /// Frase bajo la opción Sistema de la hoja de idioma: el idioma que usa el móvil.
  ///
  /// In es, this message translates to:
  /// **'Ahora: {language}'**
  String settingsLanguageSystemNow(String language);

  /// Valor de la fila Móviles de la familia cuando no hay otro móvil conectado.
  ///
  /// In es, this message translates to:
  /// **'Solo este'**
  String get settingsDevicesOnlyThis;

  /// Valor de la fila Móviles de la familia: cuántos hay y el estado en una o dos palabras.
  ///
  /// In es, this message translates to:
  /// **'{count} · {status}'**
  String settingsDevicesValue(int count, String status);

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'al día'**
  String get syncShortUpToDate;

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'sincronizando'**
  String get syncShortSyncing;

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'pendiente'**
  String get syncShortPending;

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'sin conexión'**
  String get syncShortOffline;

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'con error'**
  String get syncShortError;

  /// Estado de la sincronización en minúsculas, tras el número de móviles.
  ///
  /// In es, this message translates to:
  /// **'apagada'**
  String get syncShortOff;

  /// Subtítulo de la pantalla Archivo.
  ///
  /// In es, this message translates to:
  /// **'Fuera de las listas, con sus regalos guardados.'**
  String get archiveSubtitle;

  /// Subtítulo de la pantalla Archivo cuando está vacía.
  ///
  /// In es, this message translates to:
  /// **'No hay nada archivado.'**
  String get archiveEmpty;

  /// Nota al pie de la pantalla Archivo.
  ///
  /// In es, this message translates to:
  /// **'Archivar no borra nada. Eliminar sí, y para siempre.'**
  String get archiveNote;

  /// Título de la tarjeta de estado cuando no hay otro móvil conectado.
  ///
  /// In es, this message translates to:
  /// **'Solo en este móvil'**
  String get devicesSoloTitle;

  /// Frase de la tarjeta de estado cuando no hay otro móvil conectado.
  ///
  /// In es, this message translates to:
  /// **'Conecta otro para ver la misma lista en los dos.'**
  String get devicesSoloBody;

  /// Título de la tarjeta de estado cuando no hay otro móvil conectado pero hay un código de recuperación activo: la lista tiene una copia cifrada en el servidor.
  ///
  /// In es, this message translates to:
  /// **'Copia de recuperación guardada'**
  String get devicesRecoveryTitle;

  /// Frase de la tarjeta de estado con un código de recuperación activo y ningún otro móvil conectado.
  ///
  /// In es, this message translates to:
  /// **'La lista tiene una copia cifrada que se recupera con tu código. Conecta otro móvil para verla en los dos.'**
  String get devicesRecoveryBody;

  /// Título de la tarjeta de estado con dos móviles conectados en una versión sin servidor de sincronización.
  ///
  /// In es, this message translates to:
  /// **'Conectados por fichero o QR'**
  String get devicesManualTitle;

  /// Frase de la tarjeta de estado con dos móviles conectados en una versión sin servidor; debajo está la fila Enviar la lista ahora.
  ///
  /// In es, this message translates to:
  /// **'Sin sincronización automática: envía la lista cuando cambie.'**
  String get devicesManualBody;

  /// Título de la tarjeta de estado con la sincronización al día.
  ///
  /// In es, this message translates to:
  /// **'Todo al día'**
  String get devicesUpToDateTitle;

  /// Frase de la tarjeta de estado al día; status es «Sincronizado hace 1 min».
  ///
  /// In es, this message translates to:
  /// **'{status}. Cifrado de extremo a extremo.'**
  String devicesUpToDateBody(String status);

  /// Frase de la tarjeta de estado antes de la primera sincronización.
  ///
  /// In es, this message translates to:
  /// **'Cifrado de extremo a extremo.'**
  String get devicesEncrypted;

  /// Título de la tarjeta de estado tras «Dejar de sincronizar».
  ///
  /// In es, this message translates to:
  /// **'Sincronización apagada'**
  String get devicesOffTitle;

  /// Frase de la tarjeta de estado con la sincronización apagada.
  ///
  /// In es, this message translates to:
  /// **'Los cambios no salen de este móvil.'**
  String get devicesOffBody;

  /// Botón de la tarjeta de estado que vuelve a encender la sincronización.
  ///
  /// In es, this message translates to:
  /// **'Encender'**
  String get devicesTurnOn;

  /// Aviso tras encender la sincronización.
  ///
  /// In es, this message translates to:
  /// **'Sincronización encendida.'**
  String get syncTurnedOn;

  /// Título de la tarjeta de estado sin red.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get devicesOfflineTitle;

  /// Frase de la tarjeta de estado sin red.
  ///
  /// In es, this message translates to:
  /// **'Los cambios se enviarán cuando vuelva.'**
  String get devicesOfflineBody;

  /// Cabecera de la lista de móviles de la familia; a su derecha va cuántos hay.
  ///
  /// In es, this message translates to:
  /// **'Conectados'**
  String get devicesConnected;

  /// Nombre o frase del móvil propio en la lista de conectados.
  ///
  /// In es, this message translates to:
  /// **'Este móvil'**
  String get devicesThisPhone;

  /// Nombre del móvil conectado cuando no se sabe cómo se llama.
  ///
  /// In es, this message translates to:
  /// **'Otro móvil'**
  String get devicesOtherPhone;

  /// Frase bajo el nombre del otro móvil en la lista de conectados.
  ///
  /// In es, this message translates to:
  /// **'Conectado a esta familia'**
  String get devicesPeerHint;

  /// Frase bajo un móvil conectado que se unió con «Elegir después» y todavía no tiene persona.
  ///
  /// In es, this message translates to:
  /// **'Sin persona: aún no abre las sorpresas'**
  String get devicesPeerNoPerson;

  /// Línea discreta bajo la lista de móviles de la familia cuando no se ha podido leer el registro de móviles.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer la lista de móviles.'**
  String get devicesListError;

  /// Botón principal de Móviles de la familia y título de su hoja.
  ///
  /// In es, this message translates to:
  /// **'Conectar otro móvil'**
  String get devicesConnect;

  /// Pregunta de la hoja Conectar otro móvil.
  ///
  /// In es, this message translates to:
  /// **'¿Dónde está el otro móvil?'**
  String get devicesConnectQuestion;

  /// Opción de la hoja Conectar otro móvil: se enseña un QR en persona.
  ///
  /// In es, this message translates to:
  /// **'Está aquí'**
  String get devicesHereTitle;

  /// Frase de la opción Está aquí.
  ///
  /// In es, this message translates to:
  /// **'Enséñale un código QR. Es lo más rápido.'**
  String get devicesHereHint;

  /// Opción de la hoja Conectar otro móvil: se envía un enlace de invitación.
  ///
  /// In es, this message translates to:
  /// **'Está lejos'**
  String get devicesFarTitle;

  /// Frase de la opción Está lejos.
  ///
  /// In es, this message translates to:
  /// **'Envíale un enlace. Tú apruebas quién entra.'**
  String get devicesFarHint;

  /// Fila de Móviles de la familia en una versión sin servidor: envía el fichero .gifthuddle al otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Enviar la lista ahora'**
  String get devicesSendNow;

  /// Frase de la fila Enviar la lista ahora.
  ///
  /// In es, this message translates to:
  /// **'Con un fichero .gifthuddle, por donde quieras.'**
  String get devicesSendNowHint;

  /// Fila de Móviles de la familia y título de su hoja.
  ///
  /// In es, this message translates to:
  /// **'Más opciones'**
  String get devicesMore;

  /// Frase de la fila Más opciones.
  ///
  /// In es, this message translates to:
  /// **'Unirme a otra familia, dejar de sincronizar'**
  String get devicesMoreHint;

  /// Fila de Más opciones y título de su paso.
  ///
  /// In es, this message translates to:
  /// **'Unir este móvil a otra familia'**
  String get devicesJoinOther;

  /// Frase de la fila Unir este móvil a otra familia.
  ///
  /// In es, this message translates to:
  /// **'Sustituye la lista de este móvil.'**
  String get devicesJoinOtherHint;

  /// Aviso del paso Unir este móvil a otra familia.
  ///
  /// In es, this message translates to:
  /// **'Si te unes a otra familia, la lista de este móvil se sustituye y se pierden sus regalos.'**
  String get devicesJoinOtherWarning;

  /// Opción para unirse a otra familia leyendo el QR del otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Escanear su QR'**
  String get devicesScanTitle;

  /// Frase de la opción Escanear su QR.
  ///
  /// In es, this message translates to:
  /// **'El otro móvil lo enseña en «Conectar otro móvil».'**
  String get devicesScanHint;

  /// Opción para unirse a otra familia con un enlace.
  ///
  /// In es, this message translates to:
  /// **'Pegar un enlace de invitación'**
  String get devicesPasteLinkTitle;

  /// Frase de la opción Pegar un enlace de invitación.
  ///
  /// In es, this message translates to:
  /// **'Si te lo enviaron por mensaje.'**
  String get devicesPasteLinkHint;

  /// Fila de Más opciones y título del paso con la nota de privacidad.
  ///
  /// In es, this message translates to:
  /// **'Cómo se protege la lista'**
  String get devicesPrivacyTitle;

  /// Botón que cierra una explicación.
  ///
  /// In es, this message translates to:
  /// **'Entendido'**
  String get actionUnderstood;

  /// Subtítulo de la pantalla Copia de seguridad.
  ///
  /// In es, this message translates to:
  /// **'Un fichero .gifthuddle cifrado con toda la lista.'**
  String get backupSubtitle;

  /// Fila de Copia de seguridad: abre la hoja de compartir con el fichero.
  ///
  /// In es, this message translates to:
  /// **'Guardar una copia'**
  String get backupSaveTitle;

  /// Frase de la fila Guardar una copia.
  ///
  /// In es, this message translates to:
  /// **'Un fichero .gifthuddle cifrado, donde tú quieras.'**
  String get backupSaveHint;

  /// Fila de Copia de seguridad y título de su hoja.
  ///
  /// In es, this message translates to:
  /// **'Recuperar una copia'**
  String get backupRestoreTitle;

  /// Frase de la fila Recuperar una copia.
  ///
  /// In es, this message translates to:
  /// **'Desde un fichero o desde el portapapeles.'**
  String get backupRestoreHint;

  /// Subtítulo de la hoja Recuperar una copia.
  ///
  /// In es, this message translates to:
  /// **'Se fusiona con lo que hay: no se pierde nada.'**
  String get backupRestoreSubtitle;

  /// Opción de la hoja Recuperar una copia.
  ///
  /// In es, this message translates to:
  /// **'Pegar desde el portapapeles'**
  String get backupPasteTitle;

  /// Frase de la opción Pegar desde el portapapeles.
  ///
  /// In es, this message translates to:
  /// **'Si te llegó como enlace o como texto.'**
  String get backupPasteHint;

  /// Nota de la hoja Recuperar una copia: cómo se abre un fichero.
  ///
  /// In es, this message translates to:
  /// **'Para abrir un fichero .gifthuddle, tócalo en Archivos o en el mensaje donde te llegó y elige Gift Huddle.'**
  String get backupFileNote;

  /// Nota al pie de la pantalla Copia de seguridad.
  ///
  /// In es, this message translates to:
  /// **'La copia va cifrada con la clave de la familia: hoy solo se abre en un móvil que ya esté conectado.'**
  String get backupNote;

  /// Texto mientras se prepara la conexión de otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Preparando la conexión…'**
  String get pairingV2Preparing;

  /// Aviso bajo el QR o el enlace: caduca y no da acceso por sí solo.
  ///
  /// In es, this message translates to:
  /// **'El código caduca a las 24 horas y solo sirve para pedir entrada: nadie entra sin que compares un número con el otro móvil.'**
  String get pairingV2NoticeExpires;

  /// Título de la pantalla del enlace para un móvil lejano.
  ///
  /// In es, this message translates to:
  /// **'Comparte el enlace'**
  String get pairingV2FarTitle;

  /// Explicación del enlace que se comparte con un móvil lejano.
  ///
  /// In es, this message translates to:
  /// **'Envíaselo a quien quieras conectar. Cuando lo abra y pida entrar, aquí verás un número para compararlo.'**
  String get pairingV2FarBody;

  /// Botón que abre la hoja de compartir con el enlace.
  ///
  /// In es, this message translates to:
  /// **'Compartir el enlace'**
  String get pairingV2Share;

  /// Estado mientras nadie ha respondido a la invitación.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que el otro móvil lea el código…'**
  String get pairingV2WaitingHere;

  /// Título del paso de comparar el número de seis cifras.
  ///
  /// In es, this message translates to:
  /// **'Compara el número'**
  String get pairingV2CompareTitle;

  /// Explicación en el móvil que invita al comparar el número.
  ///
  /// In es, this message translates to:
  /// **'El otro móvil enseña un número. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden»; si no, «No coinciden».'**
  String get pairingV2HostCompareBody;

  /// Botón: los dos números son el mismo.
  ///
  /// In es, this message translates to:
  /// **'Coinciden'**
  String get pairingV2Match;

  /// Botón: los números son distintos; se cancela.
  ///
  /// In es, this message translates to:
  /// **'No coinciden'**
  String get pairingV2NoMatch;

  /// Aviso en el móvil que invita cuando el otro no eligió persona.
  ///
  /// In es, this message translates to:
  /// **'El otro móvil todavía no ha dicho de quién es. Puedes darle acceso igualmente: podrá elegirlo más adelante y, hasta entonces, no abrirá las sorpresas.'**
  String get pairingV2NoPersonWarning;

  /// Progreso al aprobar.
  ///
  /// In es, this message translates to:
  /// **'Dando acceso al otro móvil…'**
  String get pairingV2Approving;

  /// El anfitrión solo sabe que envió la aprobación, no si el invitado terminó.
  ///
  /// In es, this message translates to:
  /// **'Acceso enviado. El otro móvil tiene que terminar la conexión.'**
  String get pairingV2HostDone;

  /// La versión de la aprobación no es compatible con este móvil.
  ///
  /// In es, this message translates to:
  /// **'Los dos móviles tienen que tener la última versión de Gift Huddle. Actualiza el que esté desfasado y vuelve a empezar.'**
  String get pairingV2VersionMismatch;

  /// Mensaje cuando se cancela o caduca la conexión en el móvil que invita.
  ///
  /// In es, this message translates to:
  /// **'Se ha cancelado y el código ya no sirve. Puedes empezar de nuevo.'**
  String get pairingV2HostCancelled;

  /// Error genérico en el móvil que invita.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar el otro móvil. Inténtalo de nuevo.'**
  String get pairingV2HostFailed;

  /// Error cuando no hay servidor, sincronización apagada o red.
  ///
  /// In es, this message translates to:
  /// **'Para conectar otro móvil hace falta tener la sincronización encendida y conexión a internet.'**
  String get pairingV2NotReady;

  /// Título al elegir la persona dueña del móvil al entrar.
  ///
  /// In es, this message translates to:
  /// **'¿De quién es este móvil?'**
  String get pairingV2ChooseTitle;

  /// Explicación de por qué se elige la persona.
  ///
  /// In es, this message translates to:
  /// **'El que tienes en la mano. Elige a quien lo usa y Gift Huddle sabrá qué sorpresas esconderle.'**
  String get pairingV2ChooseBody;

  /// Explicación cuando este móvil ya tenía a una persona en «Este móvil es de» y sale premarcada.
  ///
  /// In es, this message translates to:
  /// **'Lo tenías marcado como de {name}. Confírmalo o elige a otra persona.'**
  String pairingV2ChooseBodySelf(String name);

  /// Botón que confirma la persona premarcada como dueña de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get pairingV2ChooseContinue;

  /// Botón para no elegir persona ahora.
  ///
  /// In es, this message translates to:
  /// **'Elegir después'**
  String get pairingV2ChooseLaterTitle;

  /// Aviso de lo que pasa al no elegir persona (N2).
  ///
  /// In es, this message translates to:
  /// **'Si no eliges ahora, este móvil no abrirá las sorpresas hasta que elijas a la persona y quien te invitó lo apruebe.'**
  String get pairingV2ChooseLaterBody;

  /// Texto cuando no hay personas que elegir.
  ///
  /// In es, this message translates to:
  /// **'Este móvil todavía no conoce a nadie de esta familia, así que de momento no se puede elegir. Podrás hacerlo cuando llegue la lista.'**
  String get pairingV2ChooseNone;

  /// Estado del invitado antes de ver el número.
  ///
  /// In es, this message translates to:
  /// **'Esperando al otro móvil. En unos segundos verás aquí un número para comparar.'**
  String get pairingV2GuestWaitingCode;

  /// Explicación en el móvil invitado al comparar.
  ///
  /// In es, this message translates to:
  /// **'Mira el número que enseña el otro móvil. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden».'**
  String get pairingV2GuestCompareBody;

  /// Estado del invitado tras pulsar Coinciden.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que el otro móvil dé acceso…'**
  String get pairingV2GuestWaitingApproval;

  /// Cuerpo de la hoja de éxito del invitado.
  ///
  /// In es, this message translates to:
  /// **'Ya estás en la familia. La lista llegará en unos segundos.'**
  String get pairingV2GuestDoneBody;

  /// Mensaje del invitado al cancelar.
  ///
  /// In es, this message translates to:
  /// **'No has entrado en la familia. Pide a quien te invitó que empiece de nuevo.'**
  String get pairingV2GuestCancelled;

  /// Aviso en Móviles de la familia: hay que volver a conectar.
  ///
  /// In es, this message translates to:
  /// **'Vuelve a conectar los móviles para la nueva sincronización'**
  String get pairingV2ReconnectTitle;

  /// Explicación del aviso de volver a conectar.
  ///
  /// In es, this message translates to:
  /// **'Cada móvil se conecta otra vez con «Conectar otro móvil» y comparando un número.'**
  String get pairingV2ReconnectBody;

  /// Título del paso del móvil que invita donde se confirma aparte de quién dice ser el móvil nuevo; name es la persona que eligió.
  ///
  /// In es, this message translates to:
  /// **'Este móvil dice ser de {name}'**
  String pairingV2ClaimTitle(String name);

  /// Texto bajo el título del paso que confirma de quién es el móvil nuevo.
  ///
  /// In es, this message translates to:
  /// **'Confírmalo solo si de verdad es su móvil: con él verá las sorpresas para los demás, nunca las suyas.'**
  String get pairingV2ClaimBody;

  /// Botón que confirma que el móvil nuevo es de esa persona.
  ///
  /// In es, this message translates to:
  /// **'Sí, es de {name}'**
  String pairingV2ClaimYes(String name);

  /// Botón que dice que el móvil nuevo no es de esa persona: la invitación se cancela.
  ///
  /// In es, this message translates to:
  /// **'No es suyo'**
  String get pairingV2ClaimNo;

  /// Título del aviso antes de pasar la familia de la sincronización antigua a la nueva al conectar otro móvil.
  ///
  /// In es, this message translates to:
  /// **'¿Pasar a la sincronización nueva?'**
  String get pairingV2MigrateTitle;

  /// Texto del aviso antes de pasar la familia a la sincronización nueva: no se puede deshacer y hay que volver a conectar los demás móviles.
  ///
  /// In es, this message translates to:
  /// **'Para conectar otro móvil, esta familia pasa a la sincronización nueva, más segura. No se puede deshacer: los móviles que ya estaban conectados dejan de recibir los cambios de este hasta que los vuelvas a conectar, uno a uno, con «Conectar otro móvil». No se pierde nada.'**
  String get pairingV2MigrateBody;

  /// Botón del aviso que pasa la familia a la sincronización nueva.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get pairingV2MigrateContinue;

  /// Explicación de la pantalla que pide el PIN antes de unirse a otra familia sustituyendo la lista de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN para sustituir la lista de este móvil.'**
  String get joinReplacePinPrompt;

  /// Motivo que enseña el sistema al pedir la huella o el rostro antes de sustituir la lista de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Confirma que quieres sustituir la lista de este móvil'**
  String get joinReplaceBiometricReason;

  /// Frase bajo un móvil de la lista que espera que otro lo apruebe.
  ///
  /// In es, this message translates to:
  /// **'Espera aprobación'**
  String get devicesPeerPending;

  /// Frase bajo un móvil cuyos cambios están congelados hasta que se apruebe o se quite.
  ///
  /// In es, this message translates to:
  /// **'Congelado: espera aprobación'**
  String get devicesPeerFrozen;

  /// Frase bajo un móvil conectado que hay que volver a confirmar uno a uno.
  ///
  /// In es, this message translates to:
  /// **'Confirma de quién es'**
  String get devicesPeerReconfirm;

  /// Título del aviso de Móviles de la familia cuando hay móviles que confirmar.
  ///
  /// In es, this message translates to:
  /// **'Hay móviles por revisar'**
  String get deviceReviewNoticeTitle;

  /// Cuerpo del aviso de móviles por revisar.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Un móvil espera que lo confirmes.} other{{count} móviles esperan que los confirmes.}}'**
  String deviceReviewNoticeBody(int count);

  /// Botón del aviso que abre la bandeja de móviles por revisar, y título de la hoja.
  ///
  /// In es, this message translates to:
  /// **'Revisar móviles'**
  String get deviceReviewOpen;

  /// Qué móvil de la bandeja se está viendo: «1 de 3».
  ///
  /// In es, this message translates to:
  /// **'{current} de {total}'**
  String deviceReviewProgress(int current, int total);

  /// Título de la bandeja cuando no queda ningún móvil por confirmar.
  ///
  /// In es, this message translates to:
  /// **'Todo revisado'**
  String get deviceReviewDoneTitle;

  /// Frase de la bandeja vacía.
  ///
  /// In es, this message translates to:
  /// **'No queda ningún móvil por confirmar.'**
  String get deviceReviewDoneBody;

  /// Fila de la hoja de un móvil: la persona dueña.
  ///
  /// In es, this message translates to:
  /// **'De quién es'**
  String get deviceDetailOwner;

  /// Valor de «De quién es» cuando el móvil no tiene persona.
  ///
  /// In es, this message translates to:
  /// **'Sin persona'**
  String get deviceDetailNoPerson;

  /// Fila de la hoja de un móvil: su estado.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get deviceDetailStatus;

  /// Estado de un móvil activo de la familia.
  ///
  /// In es, this message translates to:
  /// **'Conectado'**
  String get deviceStatusActive;

  /// Estado de un móvil activo sin persona.
  ///
  /// In es, this message translates to:
  /// **'Conectado, sin persona'**
  String get deviceStatusNoPerson;

  /// Estado de un móvil que otro tiene que aprobar.
  ///
  /// In es, this message translates to:
  /// **'Espera aprobación'**
  String get deviceStatusPending;

  /// Estado de un móvil congelado.
  ///
  /// In es, this message translates to:
  /// **'Congelado'**
  String get deviceStatusFrozen;

  /// Estado de un móvil que hay que confirmar de nuevo.
  ///
  /// In es, this message translates to:
  /// **'Falta confirmar de quién es'**
  String get deviceStatusReconfirm;

  /// Nota en la hoja del propio móvil: no se quita desde aquí.
  ///
  /// In es, this message translates to:
  /// **'Este es tu móvil. Para dejar de sincronizarlo, usa «Dejar de sincronizar» en «Más opciones».'**
  String get deviceDetailSelfNote;

  /// Botón de la hoja de un móvil que lo saca de la familia.
  ///
  /// In es, this message translates to:
  /// **'Quitar este móvil'**
  String get deviceRemoveTitle;

  /// Frase del botón Quitar este móvil.
  ///
  /// In es, this message translates to:
  /// **'Deja de recibir la lista nueva.'**
  String get deviceRemoveHint;

  /// Título del diálogo de confirmar quitar un móvil.
  ///
  /// In es, this message translates to:
  /// **'¿Quitar este móvil?'**
  String get deviceRemoveConfirmTitle;

  /// Consecuencias de quitar un móvil de la familia.
  ///
  /// In es, this message translates to:
  /// **'Deja de recibir los cambios nuevos al momento. Lo que ya tiene guardado no se le puede borrar. Lo que solo estaba en ese móvil puede perderse. No se puede deshacer.'**
  String get deviceRemoveConfirmBody;

  /// Botón de confirmar que quita el móvil.
  ///
  /// In es, this message translates to:
  /// **'Quitar móvil'**
  String get deviceRemoveConfirmAction;

  /// Título del aviso al quitar el único móvil que aprobó el cambio de persona de este.
  ///
  /// In es, this message translates to:
  /// **'Este móvil volverá a esperar aprobación'**
  String get deviceRemoveWaitTitle;

  /// Cuerpo del aviso N7 al quitar un móvil.
  ///
  /// In es, this message translates to:
  /// **'El móvil que vas a quitar es el único que aprobó el cambio de persona de este móvil. Si lo quitas, este móvil esperará la aprobación de otro de la familia y, hasta entonces, no abrirá las sorpresas.'**
  String get deviceRemoveWaitBody;

  /// Botón del aviso N7 que sigue con quitar el móvil.
  ///
  /// In es, this message translates to:
  /// **'Quitar igualmente'**
  String get deviceRemoveWaitAction;

  /// Aviso tras quitar un móvil.
  ///
  /// In es, this message translates to:
  /// **'Móvil quitado'**
  String get deviceRemovedSnack;

  /// Error al quitar un móvil.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido quitar el móvil. Inténtalo de nuevo con conexión.'**
  String get deviceRemoveError;

  /// Pregunta al aprobar un móvil con persona.
  ///
  /// In es, this message translates to:
  /// **'¿Este móvil es de {name}?'**
  String deviceApproveQuestion(String name);

  /// Pregunta al aprobar un móvil sin persona.
  ///
  /// In es, this message translates to:
  /// **'¿Aprobar este móvil?'**
  String get deviceApproveQuestionNoPerson;

  /// Botón que aprueba el móvil de una persona.
  ///
  /// In es, this message translates to:
  /// **'Sí, es de {name}'**
  String deviceApproveYes(String name);

  /// Botón que aprueba un móvil sin persona.
  ///
  /// In es, this message translates to:
  /// **'Aprobar este móvil'**
  String get deviceApproveYesNoPerson;

  /// Deja un móvil para más tarde en la bandeja.
  ///
  /// In es, this message translates to:
  /// **'Después'**
  String get deviceApproveLater;

  /// Explicación al aprobar un móvil recién llegado.
  ///
  /// In es, this message translates to:
  /// **'Compruébalo en persona antes de aprobarlo: un móvil aprobado recibe la lista de la familia.'**
  String get deviceApproveNewcomer;

  /// Explicación al aprobar un móvil que cambió de persona.
  ///
  /// In es, this message translates to:
  /// **'Ha cambiado de persona. Al aprobarlo, desde ahora podrá avalar a otros móviles de la familia.'**
  String get deviceApprovePersonChanged;

  /// Explicación al confirmar un huérfano.
  ///
  /// In es, this message translates to:
  /// **'Dejó de estar enlazado a este móvil. Si lo apruebas, vuelve a recibir las sorpresas que le tocan.'**
  String get deviceApproveOrphan;

  /// Explicación al confirmar de vuelta un móvil desenlazado.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya no está enlazado a la familia, pero te confirmó a ti. Apruébalo solo si lo conoces.'**
  String get deviceApproveDetached;

  /// Explicación al revisar un móvil congelado.
  ///
  /// In es, this message translates to:
  /// **'Sus cambios están congelados y no se pueden limpiar los borrados hasta que lo apruebes o lo quites.'**
  String get deviceApproveFrozen;

  /// Aviso tras aprobar un móvil.
  ///
  /// In es, this message translates to:
  /// **'Móvil aprobado'**
  String get deviceApprovedSnack;

  /// Error al aprobar un móvil.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido aprobar el móvil.'**
  String get deviceApproveError;

  /// Aviso cuando la ficha de un móvil cambió mientras se revisaba.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ha cambiado: revisa de nuevo.'**
  String get deviceChangedNotice;

  /// Aviso tras quitar un móvil cuyo acceso en el servidor aún no se ha cortado.
  ///
  /// In es, this message translates to:
  /// **'Quitado de este móvil. Falta cortar su acceso: se hará en cuanto haya conexión.'**
  String get deviceRemovedPendingSnack;

  /// Frase añadida a la explicación de un móvil cuya ficha ya cambió: al aprobarlo podrá avalar a otros.
  ///
  /// In es, this message translates to:
  /// **'Su ficha ha cambiado: al aprobarlo, desde ahora podrá avalar a otros móviles de la familia.'**
  String get deviceApproveCanVouch;

  /// Título de la puerta de la versión web antes de emparejar el ordenador con un móvil.
  ///
  /// In es, this message translates to:
  /// **'Conecta este ordenador'**
  String get webGateConnectTitle;

  /// Explicación bajo el título de conectar el ordenador.
  ///
  /// In es, this message translates to:
  /// **'Se empareja una sola vez con tu móvil. Después solo necesitarás tu PIN.'**
  String get webGateConnectIntro;

  /// Primer paso de las instrucciones de la puerta web (conectar y desbloquear una web suspendida).
  ///
  /// In es, this message translates to:
  /// **'Abre Gift Huddle en tu móvil.'**
  String get webGateStepOpenApp;

  /// Segundo paso de conectar la web: la ruta en el móvil.
  ///
  /// In es, this message translates to:
  /// **'Ve a Móviles de la familia y toca Conectar la web.'**
  String get webGateConnectStep2;

  /// Tercer paso de conectar la web: se refiere al código QR de la pantalla.
  ///
  /// In es, this message translates to:
  /// **'Escanea este código.'**
  String get webGateConnectStep3;

  /// Indicador discreto mientras la web espera a que el móvil escanee el QR.
  ///
  /// In es, this message translates to:
  /// **'Esperando al móvil…'**
  String get webGateConnectWaiting;

  /// Título del paso en que se compara el código de seis cifras con el móvil.
  ///
  /// In es, this message translates to:
  /// **'Comprueba el código'**
  String get webGateCompareTitle;

  /// Texto sobre el código de seis cifras.
  ///
  /// In es, this message translates to:
  /// **'Código de verificación'**
  String get webGateCompareLabel;

  /// Instrucción al comparar el código con el móvil.
  ///
  /// In es, this message translates to:
  /// **'Comprueba que en el móvil sale el mismo código, confírmalo aquí y apruébalo también en el móvil.'**
  String get webGateCompareBody;

  /// Indicador de espera mientras el móvil aprueba la conexión.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que el móvil lo apruebe…'**
  String get webGateCompareWaiting;

  /// Texto que sustituye a los botones de comparar cuando la persona ya ha confirmado en la web que los códigos coinciden; solo falta que el móvil apruebe.
  ///
  /// In es, this message translates to:
  /// **'Has confirmado el código aquí'**
  String get webGateCompareConfirmed;

  /// Título cuando falla el emparejamiento de la web.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar'**
  String get webGateFailedTitle;

  /// Motivo del fallo: el QR o el código caducó.
  ///
  /// In es, this message translates to:
  /// **'El código ha caducado. Empieza otra vez para ver uno nuevo.'**
  String get webGateFailedExpired;

  /// Motivo del fallo: el código del móvil era distinto.
  ///
  /// In es, this message translates to:
  /// **'Los códigos no coincidían, así que no se ha conectado nada. Empieza otra vez.'**
  String get webGateFailedMismatch;

  /// Motivo del fallo: el móvil rechazó la conexión.
  ///
  /// In es, this message translates to:
  /// **'El móvil ha rechazado la conexión. Empieza otra vez si quieres intentarlo de nuevo.'**
  String get webGateFailedRejected;

  /// Motivo del fallo: sin red.
  ///
  /// In es, this message translates to:
  /// **'No hay conexión con el servidor. Comprueba tu conexión y empieza otra vez.'**
  String get webGateFailedNetwork;

  /// Motivo del fallo: el móvil canceló la conexión o la invitación ya no existe.
  ///
  /// In es, this message translates to:
  /// **'El móvil ha cancelado la conexión o la invitación ya no está disponible. Empieza otra vez y vuelve a conectar desde el móvil.'**
  String get webGateFailedCancelled;

  /// Botón que reinicia el emparejamiento de la web con un QR nuevo.
  ///
  /// In es, this message translates to:
  /// **'Empezar otra vez'**
  String get webGateStartAgain;

  /// Título al elegir el PIN; {name} es la persona dueña del ordenador.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador es de {name}'**
  String webGateChoosePinTitle(String name);

  /// Explicación al elegir el PIN o la frase de la web.
  ///
  /// In es, this message translates to:
  /// **'Elige un PIN o una frase para abrirlo. Te lo pediremos cada vez que entres.'**
  String get webGateChoosePinBody;

  /// Etiqueta del campo del PIN o la frase.
  ///
  /// In es, this message translates to:
  /// **'PIN o frase'**
  String get webGatePinLabel;

  /// Etiqueta del campo que repite el PIN o la frase.
  ///
  /// In es, this message translates to:
  /// **'Repite el PIN o la frase'**
  String get webGatePinRepeatLabel;

  /// Botón que muestra lo escrito en el campo del PIN.
  ///
  /// In es, this message translates to:
  /// **'Mostrar'**
  String get webGatePinShow;

  /// Botón que oculta lo escrito en el campo del PIN.
  ///
  /// In es, this message translates to:
  /// **'Ocultar'**
  String get webGatePinHide;

  /// Regla del PIN o la frase de la web.
  ///
  /// In es, this message translates to:
  /// **'6 cifras o más, o una frase de 8 caracteres o más.'**
  String get webGatePinRule;

  /// Pista al elegir el PIN de la web.
  ///
  /// In es, this message translates to:
  /// **'Puedes usar el mismo PIN que en tu móvil.'**
  String get webGatePinSameHint;

  /// Error cuando el PIN y su repetición son distintos.
  ///
  /// In es, this message translates to:
  /// **'No coinciden. Escríbelos otra vez.'**
  String get webGatePinMismatch;

  /// Aviso de que el PIN de la web no se puede recuperar.
  ///
  /// In es, this message translates to:
  /// **'Si lo olvidas, tendrás que volver a conectar este ordenador desde un móvil.'**
  String get webGatePinNoRecover;

  /// Botón que confirma el PIN elegido.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get webGateContinue;

  /// Texto del botón de continuar mientras se guarda el PIN.
  ///
  /// In es, this message translates to:
  /// **'Guardando…'**
  String get webGateSaving;

  /// Título de la pantalla de desbloqueo de la web.
  ///
  /// In es, this message translates to:
  /// **'Desbloquea Gift Huddle'**
  String get webGateUnlockTitle;

  /// Explicación bajo el título de desbloquear la web.
  ///
  /// In es, this message translates to:
  /// **'Escribe el PIN o la frase de este ordenador.'**
  String get webGateUnlockBody;

  /// Botón que desbloquea la web.
  ///
  /// In es, this message translates to:
  /// **'Desbloquear'**
  String get webGateUnlock;

  /// Texto del botón mientras se comprueba el PIN.
  ///
  /// In es, this message translates to:
  /// **'Desbloqueando…'**
  String get webGateUnlocking;

  /// Error de desbloqueo de la web.
  ///
  /// In es, this message translates to:
  /// **'PIN o frase incorrectos.'**
  String get webGateWrongPin;

  /// Intentos que quedan antes de que la guarda suspenda la web.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Te queda {count} intento.} other{Te quedan {count} intentos.}}'**
  String webGateAttemptsLeft(int count);

  /// Cuenta atrás entre intentos de desbloqueo; {seconds} son los segundos que faltan.
  ///
  /// In es, this message translates to:
  /// **'Espera {seconds} s para probar otra vez.'**
  String webGateWait(int seconds);

  /// Título cuando la web queda suspendida por intentos fallidos.
  ///
  /// In es, this message translates to:
  /// **'Demasiados intentos'**
  String get webGateSuspendedTitle;

  /// Explicación de la web suspendida.
  ///
  /// In es, this message translates to:
  /// **'Desbloquéalo desde un móvil. No se ha borrado nada.'**
  String get webGateSuspendedBody;

  /// Segundo paso para desbloquear una web suspendida desde el móvil.
  ///
  /// In es, this message translates to:
  /// **'Ve a Móviles de la familia y toca Web.'**
  String get webGateSuspendedStep2;

  /// Tercer paso para desbloquear una web suspendida desde el móvil.
  ///
  /// In es, this message translates to:
  /// **'Toca Permitir desbloquear otra vez.'**
  String get webGateSuspendedStep3;

  /// Botón que vuelve a comprobar si la web sigue suspendida.
  ///
  /// In es, this message translates to:
  /// **'Probar otra vez'**
  String get webGateRetry;

  /// Título cuando la familia ha quitado este ordenador o la lista ya no existe.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador ya no está conectado'**
  String get webGateDisconnectedTitle;

  /// Explicación de la web desconectada.
  ///
  /// In es, this message translates to:
  /// **'Se ha quitado de la familia desde un móvil o la lista ya no existe.'**
  String get webGateDisconnectedBody;

  /// Aviso de cambios sin subir guardados en la web desconectada.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Hay {count} cambio sin subir guardado en este ordenador, cifrado.} other{Hay {count} cambios sin subir guardados en este ordenador, cifrados.}}'**
  String webGateDisconnectedUnsent(int count);

  /// Botón que empareja de nuevo la web desconectada.
  ///
  /// In es, this message translates to:
  /// **'Conectar otra vez'**
  String get webGateReconnect;

  /// Botón que borra todo lo guardado en la web desconectada.
  ///
  /// In es, this message translates to:
  /// **'Borrar los datos de este ordenador'**
  String get webGateErase;

  /// Título del diálogo que confirma borrar los datos de la web.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar los datos de este ordenador?'**
  String get webGateEraseTitle;

  /// Texto del diálogo de borrar los datos sin cambios pendientes.
  ///
  /// In es, this message translates to:
  /// **'Se borra todo lo que Gift Huddle guarda aquí. No se puede deshacer.'**
  String get webGateEraseBody;

  /// Texto del diálogo de borrar los datos cuando hay cambios sin subir.
  ///
  /// In es, this message translates to:
  /// **'Se borra todo lo que Gift Huddle guarda aquí, también los cambios sin subir. No se puede deshacer.'**
  String get webGateEraseBodyUnsent;

  /// Título de la puerta web cuando la caja cifrada del ordenador está dañada.
  ///
  /// In es, this message translates to:
  /// **'Los datos de este ordenador están dañados'**
  String get webGateDamagedTitle;

  /// Explica que la caja no se puede leer y que hay que borrarla y volver a conectar el ordenador; avisa de que se pierden los cambios sin subir.
  ///
  /// In es, this message translates to:
  /// **'No se pueden leer de forma segura. Para seguir, bórralos y vuelve a conectar este ordenador desde un móvil. Los cambios que no se hubieran subido se perderán.'**
  String get webGateDamagedBody;

  /// Línea que recomienda quitar la web anterior desde el móvil (Ajustes, Móviles de la familia).
  ///
  /// In es, this message translates to:
  /// **'En el móvil, quita la web anterior en Móviles de la familia.'**
  String get webGateDamagedPhoneHint;

  /// Título cuando la web ya está abierta en otra pestaña.
  ///
  /// In es, this message translates to:
  /// **'Gift Huddle está abierto en otra pestaña'**
  String get webGateOtherTabTitle;

  /// Explicación de la pestaña duplicada.
  ///
  /// In es, this message translates to:
  /// **'Solo se puede usar en una pestaña a la vez.'**
  String get webGateOtherTabBody;

  /// Botón que pasa el uso de la web a esta pestaña.
  ///
  /// In es, this message translates to:
  /// **'Usar aquí'**
  String get webGateUseHere;

  /// Etiqueta de accesibilidad de la tapa que oculta el contenido al bloquear.
  ///
  /// In es, this message translates to:
  /// **'Gift Huddle bloqueado'**
  String get webGateLockedLabel;

  /// Título de la sección de Ajustes de la versión web.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador'**
  String get webSettingsTitle;

  /// Fila de Ajustes de la web que cambia el PIN o la frase.
  ///
  /// In es, this message translates to:
  /// **'Cambiar PIN'**
  String get webSettingsChangePin;

  /// Detalle de la fila Cambiar PIN.
  ///
  /// In es, this message translates to:
  /// **'El que abre Gift Huddle en este ordenador.'**
  String get webSettingsChangePinHint;

  /// Título de la hoja que cambia el PIN o la frase de la web.
  ///
  /// In es, this message translates to:
  /// **'Cambiar PIN o frase'**
  String get webSettingsChangePinTitle;

  /// Campo del PIN o la frase actual.
  ///
  /// In es, this message translates to:
  /// **'PIN o frase actual'**
  String get webSettingsCurrentPin;

  /// Campo del PIN o la frase nuevos.
  ///
  /// In es, this message translates to:
  /// **'Nuevo PIN o frase'**
  String get webSettingsNewPin;

  /// Campo que repite el PIN o la frase nuevos.
  ///
  /// In es, this message translates to:
  /// **'Repite el nuevo PIN o la frase'**
  String get webSettingsNewPinRepeat;

  /// Error al cambiar el PIN con un actual equivocado.
  ///
  /// In es, this message translates to:
  /// **'El PIN o la frase actual no es correcto.'**
  String get webSettingsCurrentWrong;

  /// Error genérico al cambiar el PIN de la web.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido cambiar. Inténtalo otra vez.'**
  String get webSettingsChangeFailed;

  /// Aviso tras cambiar el PIN de la web.
  ///
  /// In es, this message translates to:
  /// **'PIN cambiado.'**
  String get webSettingsPinChanged;

  /// Fila de Ajustes de la web que bloquea la sesión.
  ///
  /// In es, this message translates to:
  /// **'Bloquear ahora'**
  String get webSettingsLockNow;

  /// Fila de Ajustes de la web que saca este ordenador de la familia.
  ///
  /// In es, this message translates to:
  /// **'Olvidar este ordenador'**
  String get webSettingsForget;

  /// Detalle de la fila Olvidar este ordenador.
  ///
  /// In es, this message translates to:
  /// **'Sale de la familia y borra lo guardado en él.'**
  String get webSettingsForgetHint;

  /// Título del diálogo que confirma olvidar el ordenador.
  ///
  /// In es, this message translates to:
  /// **'¿Olvidar este ordenador?'**
  String get webSettingsForgetTitle;

  /// Texto del diálogo de olvidar el ordenador.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador saldrá de la familia y se borrará lo que Gift Huddle guarda en él, también los cambios sin subir. En tus móviles no cambia nada. Para volver a usarlo tendrás que conectarlo otra vez.'**
  String get webSettingsForgetBody;

  /// Botón que confirma olvidar el ordenador.
  ///
  /// In es, this message translates to:
  /// **'Olvidar'**
  String get webSettingsForgetConfirm;

  /// Aviso cuando el navegador no garantiza guardar los datos de la web.
  ///
  /// In es, this message translates to:
  /// **'El navegador podría borrar los datos de este ordenador si le falta espacio.'**
  String get webSettingsPersistenceDenied;

  /// Aviso dentro de la web sobre cambios apartados por ser de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Hay {count} cambio que no se puede subir porque es para una persona protegida. Se guarda en este ordenador.} other{Hay {count} cambios que no se pueden subir porque son para una persona protegida. Se guardan en este ordenador.}}'**
  String webSetAsideNotice(int count);

  /// Línea discreta al elegir el PIN: si el código no coincidía, hay que reiniciar el emparejamiento.
  ///
  /// In es, this message translates to:
  /// **'Si tu móvil no mostró el mismo código, no sigas: toca Empezar otra vez.'**
  String get webGateChoosePinCheck;

  /// Título de la confirmación para reiniciar el emparejamiento al elegir el PIN.
  ///
  /// In es, this message translates to:
  /// **'¿Empezar otra vez?'**
  String get webGateRestartTitle;

  /// Explica qué pasa al reiniciar el emparejamiento al elegir el PIN.
  ///
  /// In es, this message translates to:
  /// **'Se descartará esta conexión y aparecerá un código QR nuevo. El PIN que hayas escrito no se guardará.'**
  String get webGateRestartBody;

  /// Botón que confirma reiniciar el emparejamiento.
  ///
  /// In es, this message translates to:
  /// **'Sí, empezar otra vez'**
  String get webGateRestartConfirm;

  /// Aviso dentro de la web, una vez por sesión, de los PIN fallidos desde el último desbloqueo correcto.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{Hubo {count} intento fallido de desbloquear este ordenador desde la última vez. Si no fuiste tú, cambia el PIN.} other{Hubo {count} intentos fallidos de desbloquear este ordenador desde la última vez. Si no fuiste tú, cambia el PIN.}}'**
  String webFailedAttemptsNotice(int count);

  /// Título de la fila de una web (un ordenador) en Móviles de la familia, con la persona de la web.
  ///
  /// In es, this message translates to:
  /// **'Web de {name}'**
  String devicesWebOf(String name);

  /// Título de la fila de una web cuya persona no se conoce.
  ///
  /// In es, this message translates to:
  /// **'Web'**
  String get devicesWebTitle;

  /// Frase de la fila de una web en Móviles de la familia.
  ///
  /// In es, this message translates to:
  /// **'Ordenador conectado a esta familia'**
  String get devicesWebHint;

  /// Fila de Móviles de la familia que conecta la versión web.
  ///
  /// In es, this message translates to:
  /// **'Conectar la web'**
  String get devicesConnectWeb;

  /// Frase bajo «Conectar la web».
  ///
  /// In es, this message translates to:
  /// **'Para apuntar regalos desde el ordenador.'**
  String get devicesConnectWebHint;

  /// Título de la pantalla que conecta la web desde el móvil.
  ///
  /// In es, this message translates to:
  /// **'Conectar la web'**
  String get connectWebTitle;

  /// Explicación de qué es conectar la web, con la dirección de la web.
  ///
  /// In es, this message translates to:
  /// **'Para apuntar regalos desde el ordenador: abre web.gifthuddle.app y escanea el código que aparece.'**
  String get connectWebIntro;

  /// Aviso cuando el QR leído no es el de la web de Gift Huddle.
  ///
  /// In es, this message translates to:
  /// **'Ese código no es el de la web de Gift Huddle. Escanea el que aparece en el ordenador.'**
  String get connectWebScanInvalid;

  /// Pregunta de a quién pertenece el ordenador que se conecta.
  ///
  /// In es, this message translates to:
  /// **'¿De quién es este ordenador?'**
  String get connectWebWhoseTitle;

  /// Explicación bajo la pregunta de a quién pertenece el ordenador.
  ///
  /// In es, this message translates to:
  /// **'Elige quién lo va a usar. El ordenador se conectará como suyo.'**
  String get connectWebWhoseBody;

  /// Aviso si no hay personas entre las que elegir al conectar la web.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay personas. Añade una persona antes de conectar la web.'**
  String get connectWebNoPeople;

  /// Mientras el ordenador responde tras escanear su código.
  ///
  /// In es, this message translates to:
  /// **'Esperando a que el ordenador responda…'**
  String get connectWebWaiting;

  /// Explicación de comparar el código con el que enseña el ordenador.
  ///
  /// In es, this message translates to:
  /// **'El ordenador enseña un código. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden»; si no, «No coinciden».'**
  String get connectWebCompareBody;

  /// Mientras se da acceso al ordenador.
  ///
  /// In es, this message translates to:
  /// **'Dando acceso al ordenador…'**
  String get connectWebApproving;

  /// Título cuando el ordenador ya está conectado.
  ///
  /// In es, this message translates to:
  /// **'Ordenador conectado'**
  String get connectWebDoneTitle;

  /// Lo que falta por hacer en el ordenador al terminar.
  ///
  /// In es, this message translates to:
  /// **'En el ordenador, elige un PIN para abrir Gift Huddle.'**
  String get connectWebDoneBody;

  /// Cuando el código del ordenador ya no vale y hay que pedir otro.
  ///
  /// In es, this message translates to:
  /// **'Este código ya no vale. En el ordenador, toca Empezar otra vez y escanea el nuevo.'**
  String get connectWebNewQr;

  /// Botón para volver a escanear otro código del ordenador.
  ///
  /// In es, this message translates to:
  /// **'Escanear otro código'**
  String get connectWebScanAgain;

  /// No se ha podido conectar el ordenador.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido conectar el ordenador. En el ordenador, toca Empezar otra vez y escanea el nuevo código.'**
  String get connectWebFailed;

  /// Se canceló la conexión del ordenador.
  ///
  /// In es, this message translates to:
  /// **'Se ha cancelado y el código ya no sirve. En el ordenador, toca Empezar otra vez.'**
  String get connectWebCancelled;

  /// Fila de la hoja de una web que permite desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'Permitir desbloquear otra vez'**
  String get deviceWebResume;

  /// Frase bajo «Permitir desbloquear otra vez».
  ///
  /// In es, this message translates to:
  /// **'Si el ordenador se suspendió por demasiados intentos de PIN. No se borra nada.'**
  String get deviceWebResumeHint;

  /// Título de la confirmación de permitir desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'¿Permitir desbloquear otra vez?'**
  String get deviceWebResumeTitle;

  /// Cuerpo de la confirmación de permitir desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador volverá a aceptar intentos de PIN. Hazlo solo si ha sido su dueño quien se ha equivocado.'**
  String get deviceWebResumeBody;

  /// Botón que confirma permitir desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'Permitir'**
  String get deviceWebResumeConfirm;

  /// Resultado de permitir desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'Listo. El ordenador ya puede volver a desbloquearse.'**
  String get deviceWebResumeDone;

  /// Fallo al permitir desbloquear otra vez.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido. Comprueba la conexión e inténtalo otra vez.'**
  String get deviceWebResumeError;

  /// Botón de la hoja de una web que le quita el acceso.
  ///
  /// In es, this message translates to:
  /// **'Quitar esta web'**
  String get deviceRemoveWebTitle;

  /// Frase del botón Quitar esta web.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador deja de recibir la lista nueva.'**
  String get deviceRemoveWebHint;

  /// Título del diálogo de confirmar quitar una web.
  ///
  /// In es, this message translates to:
  /// **'¿Quitar esta web?'**
  String get deviceRemoveWebConfirmTitle;

  /// Consecuencias de quitar una web de la familia.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador dejará de tener acceso y de recibir los cambios nuevos al momento. Lo que ya tiene en pantalla no se le puede borrar. Lo que solo estaba en ese ordenador puede perderse. No se puede deshacer.'**
  String get deviceRemoveWebConfirmBody;

  /// Botón de confirmar que quita la web.
  ///
  /// In es, this message translates to:
  /// **'Quitar web'**
  String get deviceRemoveWebConfirmAction;

  /// Aviso tras quitar una web.
  ///
  /// In es, this message translates to:
  /// **'Web quitada'**
  String get deviceRemovedWebSnack;

  /// Aviso tras quitar una web cuyo acceso en el servidor aún no se ha cortado.
  ///
  /// In es, this message translates to:
  /// **'Quitada de este móvil. Falta cortar su acceso: se hará en cuanto haya conexión.'**
  String get deviceRemovedWebPendingSnack;

  /// Error al quitar una web.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido quitar la web. Inténtalo de nuevo con conexión.'**
  String get deviceRemoveWebError;

  /// Estado discreto de la web: todo guardado.
  ///
  /// In es, this message translates to:
  /// **'Guardado'**
  String get webSyncSaved;

  /// Estado discreto de la web: sin conexión.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get webSyncOffline;

  /// Estado de la web cuando ningún móvil la ha confirmado.
  ///
  /// In es, this message translates to:
  /// **'Este ordenador espera a que un móvil lo confirme'**
  String get webSyncAwaitingConfirm;

  /// Mensaje cuando se intenta en la web algo que solo se hace en un móvil.
  ///
  /// In es, this message translates to:
  /// **'Esto no se puede hacer desde el ordenador. Hazlo desde un móvil.'**
  String get webOperationUnavailable;

  /// Título de la hoja que avisa antes de cambiar «Este móvil es de» en una familia con otros móviles.
  ///
  /// In es, this message translates to:
  /// **'¿Cambiar de quién es este móvil?'**
  String get selfChangeConfirmTitle;

  /// Introducción de la hoja de cambio de persona.
  ///
  /// In es, this message translates to:
  /// **'Vas a decir que este móvil es de {name}. Eso cambia lo que puede ver, no solo el nombre.'**
  String selfChangeConfirmIntro(String name);

  /// Introducción de la hoja de cambio de persona cuando se elige Nadie.
  ///
  /// In es, this message translates to:
  /// **'Vas a dejar este móvil sin persona. Eso cambia lo que puede ver, no solo el nombre.'**
  String get selfChangeConfirmIntroNobody;

  /// Primera consecuencia del cambio de persona.
  ///
  /// In es, this message translates to:
  /// **'Este móvil dejará de ver los regalos de {name} y sus sorpresas.'**
  String selfChangeEffectHides(String name);

  /// Primera consecuencia del cambio cuando se elige Nadie.
  ///
  /// In es, this message translates to:
  /// **'Este móvil se quedará sin persona asignada y no podrá ver sorpresas mientras siga así.'**
  String get selfChangeEffectNobody;

  /// Segunda consecuencia del cambio de persona.
  ///
  /// In es, this message translates to:
  /// **'Hasta que otro móvil de la familia lo apruebe, este móvil no verá las sorpresas de nadie.'**
  String get selfChangeEffectWait;

  /// Tercera consecuencia del cambio de persona.
  ///
  /// In es, this message translates to:
  /// **'Los móviles que este había aprobado pueden tener que confirmarse otra vez.'**
  String get selfChangeEffectReconfirm;

  /// Botón que confirma el cambio de persona de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Cambiar de persona'**
  String get selfChangeConfirmAction;

  /// Título de la hoja que se enseña tras cambiar de persona en una familia con otros móviles.
  ///
  /// In es, this message translates to:
  /// **'Esperando aprobación de otro móvil'**
  String get selfChangePendingTitle;

  /// Cuerpo de la hoja de espera de aprobación.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya es de {name}. Otro móvil de la familia tiene que aprobarlo; mientras tanto, no verás las sorpresas de nadie.'**
  String selfChangePendingBody(String name);

  /// Cuerpo de la hoja de espera de aprobación cuando se eligió Nadie.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya no tiene una persona asignada y espera la aprobación de otro móvil de la familia. Aunque lo aprueben, no podrá ver sorpresas mientras no tenga una persona asignada.'**
  String get selfChangePendingBodyNobody;

  /// Frase de la hoja de espera cuando hay móviles sueltos por confirmar.
  ///
  /// In es, this message translates to:
  /// **'Algunos móviles que habías aprobado esperan que los confirmes otra vez.'**
  String get selfChangePendingOrphans;

  /// Título del aviso cuando se agotan los cambios de persona.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya no puede cambiar de persona'**
  String get selfChangeExhaustedTitle;

  /// Cuerpo del aviso cuando se agotan los cambios de persona.
  ///
  /// In es, this message translates to:
  /// **'Ha usado todos los cambios que permite la lista de móviles. Puede volver a conectarse a la familia como un móvil nuevo, en persona, desde otro móvil.'**
  String get selfChangeExhaustedBody;

  /// Frase bajo la fila Este móvil es de mientras otro móvil no apruebe este.
  ///
  /// In es, this message translates to:
  /// **'Esperando aprobación de otro móvil'**
  String get selfWaitingHint;

  /// Título del aviso persistente de Móviles de la familia cuando otro móvil ha quitado este.
  ///
  /// In es, this message translates to:
  /// **'Otro móvil de la familia ha quitado este'**
  String get healthRevokedTitle;

  /// Cuerpo del aviso de móvil quitado por otro.
  ///
  /// In es, this message translates to:
  /// **'Lo que tienes guardado sigue en este móvil, pero ya no se sincroniza. Reintentar no sirve: hay que volver a conectarlo con otro móvil de la familia, en persona.'**
  String get healthRevokedBody;

  /// Botón del aviso de móvil quitado: lleva a unirse a la familia desde otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Conectar otra vez'**
  String get healthRevokedAction;

  /// Título del aviso de sorpresas congeladas con los nombres de las personas.
  ///
  /// In es, this message translates to:
  /// **'Sorpresas en pausa para {names}'**
  String healthFrozenTitle(String names);

  /// Título del aviso de sorpresas congeladas sin nombres.
  ///
  /// In es, this message translates to:
  /// **'Sorpresas en pausa'**
  String get healthFrozenTitleGeneric;

  /// Cuerpo del aviso de sorpresas congeladas.
  ///
  /// In es, this message translates to:
  /// **'No se ha perdido nada. Para ver las sorpresas, este móvil debe tener una persona de la familia asignada y estar aprobado por otro móvil de la familia.'**
  String get healthFrozenBody;

  /// Une los nombres de una lista: todos menos el último, y el último.
  ///
  /// In es, this message translates to:
  /// **'{head} y {last}'**
  String healthNamesAnd(String head, String last);

  /// Fila discreta de Móviles de la familia: la generación actual se acerca a su límite.
  ///
  /// In es, this message translates to:
  /// **'Conviene renovar la lista pronto'**
  String get healthRenewSoon;

  /// Cabecera de las filas de accesos sin respaldo y bajas a medias.
  ///
  /// In es, this message translates to:
  /// **'Por resolver'**
  String get healthResolveSection;

  /// Fila: un acceso del servidor que no figura en la lista de móviles.
  ///
  /// In es, this message translates to:
  /// **'Acceso sin respaldo'**
  String get healthUnbackedTitle;

  /// Explicación de la fila Acceso sin respaldo.
  ///
  /// In es, this message translates to:
  /// **'Un acceso al servidor no figura en la lista de móviles de la familia. Si no lo reconoces, retíralo.'**
  String get healthUnbackedBody;

  /// Identificador corto de un acceso sin respaldo.
  ///
  /// In es, this message translates to:
  /// **'Referencia: {ref}'**
  String healthUnbackedRef(String ref);

  /// Botón de la fila Acceso sin respaldo y de su confirmación.
  ///
  /// In es, this message translates to:
  /// **'Retirar acceso'**
  String get healthUnbackedAction;

  /// Título de la confirmación de retirar un acceso sin respaldo.
  ///
  /// In es, this message translates to:
  /// **'¿Retirar este acceso?'**
  String get healthUnbackedConfirmTitle;

  /// Cuerpo de la confirmación de retirar un acceso sin respaldo.
  ///
  /// In es, this message translates to:
  /// **'Se corta el acceso de ese móvil al servidor de la familia. Si era un móvil tuyo, tendrás que conectarlo otra vez en persona. No se puede deshacer.'**
  String get healthUnbackedConfirmBody;

  /// Resultado de retirar un acceso sin respaldo.
  ///
  /// In es, this message translates to:
  /// **'Acceso retirado'**
  String get healthUnbackedDone;

  /// Fila: un móvil con el acceso ya cortado pero sin baja completa.
  ///
  /// In es, this message translates to:
  /// **'Baja a medias: {name}'**
  String healthDepartedTitle(String name);

  /// Explicación de la fila Baja a medias.
  ///
  /// In es, this message translates to:
  /// **'Ya no tiene acceso al servidor, pero falta completar su baja en la lista de móviles para actualizar los permisos y las claves.'**
  String get healthDepartedBody;

  /// Botón de la fila Baja a medias.
  ///
  /// In es, this message translates to:
  /// **'Completar la baja'**
  String get healthDepartedAction;

  /// Resultado de completar una baja.
  ///
  /// In es, this message translates to:
  /// **'Baja completada'**
  String get healthDepartedDone;

  /// Etiqueta accesible mientras se resuelve una fila.
  ///
  /// In es, this message translates to:
  /// **'Un momento'**
  String get healthResolveBusy;

  /// Error de red al resolver una fila.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido completar. Comprueba la conexión e inténtalo de nuevo.'**
  String get healthResolveError;

  /// Botón para repetir la acción que falló.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get healthRetry;

  /// Resultado de retirar un acceso cuando otro móvil ya lo respalda: no se ha retirado nada.
  ///
  /// In es, this message translates to:
  /// **'Ya no hace falta quitar este acceso.'**
  String get healthUnbackedNotNeeded;

  /// Frase bajo el título de la hoja ¿De quién es este móvil? en una familia con la sincronización nueva: la elección se comparte y afecta a lo que se ve.
  ///
  /// In es, this message translates to:
  /// **'La persona que elijas determina qué regalos y sorpresas puedes ver en este móvil. El cambio se comparte con los demás móviles de la familia.'**
  String get settingsSelfSheetHintV2;

  /// Fila de la hoja de una persona que abre la protección de sus regalos.
  ///
  /// In es, this message translates to:
  /// **'Regalos en secreto'**
  String get protectionRowTitle;

  /// Frase bajo la fila de regalos en secreto.
  ///
  /// In es, this message translates to:
  /// **'Que {name} no vea sus regalos en su móvil.'**
  String protectionRowHint(String name);

  /// Estado de la protección: sin proteger.
  ///
  /// In es, this message translates to:
  /// **'Desactivado'**
  String get protectionStatusOff;

  /// Estado de la protección: pedida, a la espera de un móvil con permiso.
  ///
  /// In es, this message translates to:
  /// **'Pedido'**
  String get protectionStatusRequested;

  /// Estado de la protección: activa.
  ///
  /// In es, this message translates to:
  /// **'Activo'**
  String get protectionStatusActive;

  /// Título de la hoja de protección de una persona.
  ///
  /// In es, this message translates to:
  /// **'Regalos en secreto para {name}'**
  String protectionSheetTitle(String name);

  /// Explicación de la protección de una persona.
  ///
  /// In es, this message translates to:
  /// **'Con los regalos en secreto activados, el móvil de {name} no muestra ningún regalo para {name}, ni cuántos hay. El resto de la familia los sigue viendo.'**
  String protectionIntro(String name);

  /// Primera consecuencia de activar la protección.
  ///
  /// In es, this message translates to:
  /// **'Los demás móviles de la familia con permiso siguen viéndolos y editándolos.'**
  String get protectionEffectOthers;

  /// Segunda consecuencia: lo ya recibido no se retira.
  ///
  /// In es, this message translates to:
  /// **'Los regalos que el móvil de {name} ya recibió antes de activarla no se pueden retirar de él.'**
  String protectionEffectKept(String name);

  /// Tercera consecuencia: la confirmación la da un móvil con permiso.
  ///
  /// In es, this message translates to:
  /// **'Hace falta un móvil con permiso que lo confirme.'**
  String get protectionEffectConfirm;

  /// Botón que pide activar la protección.
  ///
  /// In es, this message translates to:
  /// **'Pedir protección'**
  String get protectionRequest;

  /// Título del estado pedido.
  ///
  /// In es, this message translates to:
  /// **'Protección pedida'**
  String get protectionRequestedTitle;

  /// Explicación del estado pedido cuando este móvil no puede confirmar.
  ///
  /// In es, this message translates to:
  /// **'Esperando a un móvil con permiso que la confirme. Hasta entonces, los regalos de {name} no se muestran en ningún móvil.'**
  String protectionWaitingBody(String name);

  /// Explicación del estado pedido cuando este móvil puede confirmar.
  ///
  /// In es, this message translates to:
  /// **'Este móvil tiene permiso para confirmarla. Al activarla, los regalos de {name} dejan de mostrarse en su móvil.'**
  String protectionConfirmBody(String name);

  /// Botón que confirma la protección pedida.
  ///
  /// In es, this message translates to:
  /// **'Activar ahora'**
  String get protectionActivate;

  /// Título del estado activo.
  ///
  /// In es, this message translates to:
  /// **'Protección activa'**
  String get protectionActiveTitle;

  /// Explicación del estado activo.
  ///
  /// In es, this message translates to:
  /// **'{name} no ve ninguno de sus regalos en su móvil.'**
  String protectionActiveBody(String name);

  /// Botón que desactiva la protección.
  ///
  /// In es, this message translates to:
  /// **'Desactivar protección'**
  String get protectionDeactivate;

  /// Título del diálogo de confirmación al desactivar.
  ///
  /// In es, this message translates to:
  /// **'¿Desactivar los regalos en secreto de {name}?'**
  String protectionDeactivateTitle(String name);

  /// Cuerpo del diálogo de confirmación al desactivar.
  ///
  /// In es, this message translates to:
  /// **'Se publicarán todos los regalos disponibles de {name}, de cualquier año, también los que están pendientes en este móvil. Después {name} los verá en su móvil.'**
  String protectionDeactivateBody(String name);

  /// Botón rojo del diálogo al desactivar.
  ///
  /// In es, this message translates to:
  /// **'Desactivar'**
  String get protectionDeactivateConfirm;

  /// Aviso cuando este móvil no puede desactivar la protección.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no puede desactivarla ahora: hace falta permiso y la clave actual de {name}.'**
  String protectionCannotDeactivate(String name);

  /// Aviso cuando falla pedir, activar o desactivar la protección.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido cambiar la protección. No se ha modificado nada.'**
  String get protectionChangeFailed;

  /// Bloque fijo y borroso que ocupa el lugar de los regalos de una persona protegida; sin cifras.
  ///
  /// In es, this message translates to:
  /// **'Regalos en secreto para {name}'**
  String secretBlockTitle(String name);

  /// Frase bajo el bloque de regalos en secreto.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no los muestra.'**
  String get secretBlockNote;

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Los regalos de {name} están en secreto y no se pueden guardar así.'**
  String protectionReason_protectedPerson(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no tiene permiso para los regalos en secreto de {name}. Pide ayuda a otro móvil de la familia con permiso.'**
  String protectionReason_noEntitlement(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Este móvil es de {name}: aquí no se pueden crear ni ver sus regalos mientras estén en secreto.'**
  String protectionReason_ownRequestsRestricted(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Falta la clave actual de los regalos de {name}. Otro móvil con permiso tiene que darte acceso.'**
  String protectionReason_missingEpochKey(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Falta que un móvil con permiso confirme la protección de {name}.'**
  String protectionReason_protectionPending(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'No se puede abrir una parte de los regalos de {name}. No se ha cambiado nada: recupera el acceso antes de seguir.'**
  String protectionReason_unreadableSlot(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Los regalos en secreto de {name} han llegado al límite. Borra alguno para poder añadir más.'**
  String protectionReason_blockFull(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Este regalo es demasiado grande para guardarlo en secreto. Acorta las notas.'**
  String protectionReason_giftTooLarge(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya no tiene sitio para guardar más regalos en secreto. Pide a otro móvil con permiso que los añada.'**
  String protectionReason_writerSlotsFull(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Ahora mismo no cabe más en los regalos en secreto de la familia.'**
  String protectionReason_slotsFull(String name);

  /// Motivo por el que no se pueden guardar o elegir los regalos de una persona protegida.
  ///
  /// In es, this message translates to:
  /// **'Los regalos en secreto necesitan que este móvil esté conectado a la familia con la versión nueva.'**
  String protectionReason_requiresV2(String name);

  /// Se añade tras el motivo cuando un regalo para una persona protegida se rechaza.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado el regalo.'**
  String get giftProtectedRejected;

  /// Aviso cuando un regalo secreto se guarda cifrado en este móvil pero aún no en la lista.
  ///
  /// In es, this message translates to:
  /// **'Guardado solo en este móvil. Queda pendiente de guardar y compartir.'**
  String get giftSavedLocally;

  /// Acción del aviso de guardado local.
  ///
  /// In es, this message translates to:
  /// **'Ver pendientes'**
  String get giftSavedLocallyAction;

  /// Explicación de la restricción de las peticiones propias en el editor.
  ///
  /// In es, this message translates to:
  /// **'Mientras la protección esté activa, este móvil no puede crear ni ver regalos para su propia persona. Pídelo a otra persona de la familia.'**
  String get giftOwnRequestRestricted;

  /// Título de la hoja de regalos pendientes de guardar o compartir.
  ///
  /// In es, this message translates to:
  /// **'Regalos pendientes'**
  String get pendingGiftsTitle;

  /// Explicación de la hoja de regalos pendientes.
  ///
  /// In es, this message translates to:
  /// **'Estos regalos están guardados cifrados solo en este móvil. Hasta que se guarden y se compartan con la familia, los demás móviles no los ven. Si pierdes este móvil antes, se pierden.'**
  String get pendingGiftsIntro;

  /// Botón que reintenta guardar los regalos pendientes de una persona.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get pendingGiftsRetry;

  /// Texto del botón mientras reintenta.
  ///
  /// In es, this message translates to:
  /// **'Reintentando'**
  String get pendingGiftsRetrying;

  /// Resultado de reintentar cuando siguen pendientes.
  ///
  /// In es, this message translates to:
  /// **'Todavía no cabe. No se ha publicado nada y los regalos se conservan en este móvil.'**
  String get pendingGiftsStill;

  /// Aviso cuando falla el reintento.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido reintentar. Los regalos siguen guardados en este móvil.'**
  String get pendingGiftsRetryError;

  /// Título cuando ya no quedan pendientes.
  ///
  /// In es, this message translates to:
  /// **'Todo guardado'**
  String get pendingGiftsDoneTitle;

  /// Cuerpo cuando ya no quedan pendientes.
  ///
  /// In es, this message translates to:
  /// **'Ya no queda ningún regalo pendiente.'**
  String get pendingGiftsDoneBody;

  /// Aviso discreto con el número de regalos pendientes.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, one{{count} regalo pendiente de guardar} other{{count} regalos pendientes de guardar}}'**
  String pendingGiftsNotice(int count);

  /// Acción del aviso de regalos pendientes.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get pendingGiftsNoticeAction;

  /// Título de la columna derecha de Personas en escritorio: la próxima ocasión, las demás y el presupuesto de la casa.
  ///
  /// In es, this message translates to:
  /// **'Resumen'**
  String get peopleSummaryTitle;

  /// Frase sobre los botones de ocasión en la lista vacía de una persona (escritorio): cada botón abre el editor con esa ocasión.
  ///
  /// In es, this message translates to:
  /// **'O apunta el primero para una próxima ocasión'**
  String get giftsEmptyOccasionsHint;

  /// Regalos comprados de una ocasión, abreviado, en las filas de 56 px de «Resumen» y de encima de la lista de Personas (escritorio).
  ///
  /// In es, this message translates to:
  /// **'{done} de {total} comprados'**
  String occasionGiftsBoughtShort(int done, int total);

  /// Título de la pantalla de inicio del tablero de la web de escritorio y de su sección en la barra lateral.
  ///
  /// In es, this message translates to:
  /// **'Hoy'**
  String get boardToday;

  /// Título de los carriles del tablero «Hoy» (web de escritorio).
  ///
  /// In es, this message translates to:
  /// **'Qué toca ahora'**
  String get boardNowTitle;

  /// Subtítulo del tablero «Hoy»: la fecha de hoy y los regalos comprados.
  ///
  /// In es, this message translates to:
  /// **'{date} · {bought} de {total, plural, one{{total} regalo comprado} other{{total} regalos comprados}}'**
  String boardSubtitle(String date, int bought, int total);

  /// Carril del tablero: regalos que todavía son una idea.
  ///
  /// In es, this message translates to:
  /// **'Por decidir'**
  String get boardLaneDecide;

  /// Carril del tablero: regalos decididos que faltan por comprar.
  ///
  /// In es, this message translates to:
  /// **'Por comprar'**
  String get boardLaneBuy;

  /// Carril del tablero: regalos comprados que no han llegado a casa.
  ///
  /// In es, this message translates to:
  /// **'Por llegar'**
  String get boardLaneArrive;

  /// Carril del tablero: regalos en casa que faltan por envolver.
  ///
  /// In es, this message translates to:
  /// **'Por envolver'**
  String get boardLaneWrap;

  /// Carril del tablero: regalos envueltos, listos para entregar.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get boardLaneReady;

  /// Carril del tablero sin regalos.
  ///
  /// In es, this message translates to:
  /// **'Nada por aquí'**
  String get boardLaneEmpty;

  /// Acción de accesibilidad de una fila del tablero: pasar el regalo al carril indicado.
  ///
  /// In es, this message translates to:
  /// **'Mover a {lane}'**
  String boardMoveTo(String lane);

  /// El «+» de la cabecera de un carril del tablero (ayuda y lector de pantalla).
  ///
  /// In es, this message translates to:
  /// **'Añadir regalo en {lane}'**
  String boardLaneAdd(String lane);

  /// Aviso (y anuncio para lectores de pantalla) tras pasar un regalo a otro carril del tablero, arrastrándolo o con el teclado.
  ///
  /// In es, this message translates to:
  /// **'{item}: {lane}'**
  String boardGiftMoved(String item, String lane);

  /// Frase bajo el título de Ocasiones en la web de escritorio.
  ///
  /// In es, this message translates to:
  /// **'Elige una ocasión para ver su tablero.'**
  String get boardOccasionsHint;

  /// Enlace al final de la tira de ocasiones de Hoy, a la pantalla Ocasiones, con cuántas ocasiones hay en total.
  ///
  /// In es, this message translates to:
  /// **'Ver todas ({count})'**
  String boardSeeAll(int count);

  /// Título del estado vacío del presupuesto en la web de escritorio.
  ///
  /// In es, this message translates to:
  /// **'Nada previsto todavía'**
  String get boardBudgetEmptyTitle;

  /// Botón de la cabecera de una ocasión que abre el selector de fecha.
  ///
  /// In es, this message translates to:
  /// **'Cambiar fecha'**
  String get boardChangeDate;

  /// Etiqueta del índice de Ajustes en la web de escritorio.
  ///
  /// In es, this message translates to:
  /// **'Apartados'**
  String get boardSettingsIndex;

  /// Etiqueta de accesibilidad del panel fijo del editor de regalo, a la derecha del tablero.
  ///
  /// In es, this message translates to:
  /// **'Editor de regalo'**
  String get boardEditorLabel;

  /// Texto de una tarjeta de ocasión o de una persona de la web de escritorio cuando aún no tiene ningún regalo (en lugar de «0 de 0 comprados»).
  ///
  /// In es, this message translates to:
  /// **'Sin regalos todavía'**
  String get boardNoGiftsYet;

  /// Botón de la barra lateral de la web de escritorio que la pliega a un raíl de iconos.
  ///
  /// In es, this message translates to:
  /// **'Plegar la barra lateral'**
  String get boardSidebarCollapse;

  /// Botón del raíl de la web de escritorio que despliega la barra lateral.
  ///
  /// In es, this message translates to:
  /// **'Desplegar la barra lateral'**
  String get boardSidebarExpand;

  /// Texto del campo de búsqueda de la barra lateral de la web de escritorio.
  ///
  /// In es, this message translates to:
  /// **'Buscar un regalo'**
  String get boardSearchHint;

  /// Resultado vacío de la búsqueda de regalos de la barra lateral.
  ///
  /// In es, this message translates to:
  /// **'Ningún regalo coincide'**
  String get boardSearchNone;

  /// Etiqueta del selector que filtra por persona los carriles de «Hoy» en la web.
  ///
  /// In es, this message translates to:
  /// **'Persona'**
  String get boardPersonFilter;

  /// Opción del selector de persona de «Hoy» que enseña los regalos de todos.
  ///
  /// In es, this message translates to:
  /// **'Todas las personas'**
  String get boardPersonFilterAll;

  /// Etiqueta accesible del botón que vacía un campo de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'Borrar la búsqueda'**
  String get searchClear;

  /// Cabecera de la columna del estado del regalo en la tabla de una persona (web de escritorio).
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get boardColStatus;

  /// Cabecera de la columna de quién regala en la tabla de una persona (web de escritorio).
  ///
  /// In es, this message translates to:
  /// **'Quién regala'**
  String get boardColGiver;

  /// Cabecera de la columna de la talla o la edad en la tabla de una persona (web de escritorio).
  ///
  /// In es, this message translates to:
  /// **'Talla'**
  String get boardColSize;

  /// Título de la columna lateral de Reparto (web de escritorio) con los regalos que todavía no tienen quién los regale.
  ///
  /// In es, this message translates to:
  /// **'Sin quién regala'**
  String get boardRepartoNoGiver;

  /// Texto de la columna lateral de Reparto cuando no queda ningún regalo sin quién regale.
  ///
  /// In es, this message translates to:
  /// **'Todos los regalos tienen quién los regale.'**
  String get boardRepartoNoGiverNone;

  /// Título de la columna lateral de Reparto (web de escritorio) con los regalos que parecen repetidos.
  ///
  /// In es, this message translates to:
  /// **'Posibles duplicados'**
  String get boardRepartoDuplicates;

  /// Texto de la columna lateral de Reparto cuando no hay posibles duplicados.
  ///
  /// In es, this message translates to:
  /// **'Ningún regalo parece repetido.'**
  String get boardRepartoDuplicatesNone;

  /// Etiqueta del botón de más acciones de una fila de Ajustes en la web de escritorio.
  ///
  /// In es, this message translates to:
  /// **'Más acciones de {name}'**
  String boardRowMore(String name);

  /// Título de la guía de uso y de su fila en Ajustes.
  ///
  /// In es, this message translates to:
  /// **'Cómo funciona'**
  String get tourTitle;

  /// Botón de la guía que la cierra sin llegar al final.
  ///
  /// In es, this message translates to:
  /// **'Saltar'**
  String get tourSkip;

  /// Etiqueta accesible de los puntos de la guía.
  ///
  /// In es, this message translates to:
  /// **'Página {page} de {total}'**
  String tourPageOf(int page, int total);

  /// Guía, página 1: título.
  ///
  /// In es, this message translates to:
  /// **'Apunta cada regalo'**
  String get tour1Title;

  /// Guía, página 1: una frase.
  ///
  /// In es, this message translates to:
  /// **'Elige a quién, para qué ocasión y quién lo regala. Con una idea basta.'**
  String get tour1Body;

  /// Guía, página 2: título.
  ///
  /// In es, this message translates to:
  /// **'Márcalo como comprado'**
  String get tour2Title;

  /// Guía, página 2: una frase. «Pendiente de comprar» y «por llegar» son los nombres que tienen en el detalle de una ocasión (occasionPendingBuySection y occasionToArrive).
  ///
  /// In es, this message translates to:
  /// **'Toca la casilla y el regalo sale de «Pendiente de comprar» y pasa a «por llegar». Si te equivocas, lo deshaces al momento.'**
  String get tour2Body;

  /// Guía, página 3: título.
  ///
  /// In es, this message translates to:
  /// **'Personas y ocasiones'**
  String get tour3Title;

  /// Guía, página 3: una frase.
  ///
  /// In es, this message translates to:
  /// **'Cada persona tiene su lista. Navidad, Reyes y cumpleaños la ordenan, y el reparto dice quién paga qué.'**
  String get tour3Body;

  /// Guía, página 4: título.
  ///
  /// In es, this message translates to:
  /// **'La familia comparte la lista'**
  String get tour4Title;

  /// Guía, página 4: una frase.
  ///
  /// In es, this message translates to:
  /// **'Conecta otro móvil con un QR, en persona. Todo viaja cifrado y los cambios llegan solos.'**
  String get tour4Body;

  /// Guía, página 5: título.
  ///
  /// In es, this message translates to:
  /// **'Sorpresas a salvo'**
  String get tour5Title;

  /// Guía, página 5: una frase.
  ///
  /// In es, this message translates to:
  /// **'El móvil de cada persona no ve sus propios regalos. Con PIN o biometría, sin cuentas ni anuncios.'**
  String get tour5Body;

  /// Guía, página 6: título.
  ///
  /// In es, this message translates to:
  /// **'También en el ordenador'**
  String get tour6Title;

  /// Guía, página 6: una frase.
  ///
  /// In es, this message translates to:
  /// **'Conecta el navegador una vez y tendrás la lista en una pantalla grande.'**
  String get tour6Body;

  /// Regalo de muestra de las demostraciones de la guía.
  ///
  /// In es, this message translates to:
  /// **'Patinete'**
  String get tourDemoScooter;

  /// Regalo de muestra de las demostraciones de la guía.
  ///
  /// In es, this message translates to:
  /// **'Puzle'**
  String get tourDemoPuzzle;

  /// Regalo de muestra de las demostraciones de la guía.
  ///
  /// In es, this message translates to:
  /// **'Pijama'**
  String get tourDemoPajamas;

  /// Ocasión de muestra de las demostraciones de la guía.
  ///
  /// In es, this message translates to:
  /// **'Navidad'**
  String get tourDemoChristmas;

  /// Ocasión de muestra de las demostraciones de la guía.
  ///
  /// In es, this message translates to:
  /// **'Cumpleaños'**
  String get tourDemoBirthday;

  /// Texto de la demostración de conectar dos móviles.
  ///
  /// In es, this message translates to:
  /// **'Conectado'**
  String get tourDemoConnected;

  /// Texto de la demostración de conectar dos móviles: lo que viaja va cifrado.
  ///
  /// In es, this message translates to:
  /// **'Cifrado'**
  String get tourDemoEncrypted;

  /// Texto de la demostración de privacidad: en el móvil de Aritz no se ven sus regalos.
  ///
  /// In es, this message translates to:
  /// **'Regalos ocultos'**
  String get tourDemoHidden;

  /// Fila de Ajustes y título de la pantalla del código de recuperación (24 palabras para recuperar la lista en otro móvil).
  ///
  /// In es, this message translates to:
  /// **'Código de recuperación'**
  String get settingsRecovery;

  /// Valor de la fila Código de recuperación cuando aún no hay código.
  ///
  /// In es, this message translates to:
  /// **'Sin crear'**
  String get recoveryValueNone;

  /// Valor de la fila Código de recuperación cuando la copia cifrada está lista.
  ///
  /// In es, this message translates to:
  /// **'Preparado'**
  String get recoveryValuePrepared;

  /// Valor de la fila Código de recuperación mientras se prepara o actualiza la copia.
  ///
  /// In es, this message translates to:
  /// **'Preparando'**
  String get recoveryValuePending;

  /// No description provided for @recoveryValueUnconfirmed.
  ///
  /// In es, this message translates to:
  /// **'Sin comprobar'**
  String get recoveryValueUnconfirmed;

  /// No description provided for @recoveryUnconfirmedTitle.
  ///
  /// In es, this message translates to:
  /// **'Falta comprobar el código'**
  String get recoveryUnconfirmedTitle;

  /// No description provided for @recoveryUnconfirmedBody.
  ///
  /// In es, this message translates to:
  /// **'El código aún no cuenta como guardado. Continúa para comprobar las palabras o comprueba un fichero que ya hayas guardado. Si las palabras ya se mostraron, se creará un código nuevo y el anterior dejará de valer.'**
  String get recoveryUnconfirmedBody;

  /// Valor de la fila Código de recuperación cuando necesita atención.
  ///
  /// In es, this message translates to:
  /// **'Revisar'**
  String get recoveryValueAttention;

  /// Valor de la fila Código de recuperación cuando la lista se ha pasado a otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Traspasada'**
  String get recoveryValueTransferred;

  /// Subtítulo de la pantalla Código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Para recuperar la lista en un móvil nuevo.'**
  String get recoverySubtitle;

  /// Título del estado sin código en la pantalla Código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Prepara un código para recuperar la lista si pierdes este móvil'**
  String get recoveryAbsentTitle;

  /// Explicación del estado sin código: qué recupera y la copia cifrada con un solo móvil.
  ///
  /// In es, this message translates to:
  /// **'Con 24 palabras puedes recuperar la lista y todo lo que este móvil puede ver en otro móvil. Si solo tienes este móvil, se activa una copia cifrada en el servidor: sin las palabras, nadie puede leerla.'**
  String get recoveryAbsentBody;

  /// Aviso del estado sin código.
  ///
  /// In es, this message translates to:
  /// **'Quien tenga las palabras puede entrar como este móvil. No recuperan lo que nunca se llegó a sincronizar.'**
  String get recoveryAbsentWarn;

  /// Botón que empieza a crear el código.
  ///
  /// In es, this message translates to:
  /// **'Crear código de recuperación'**
  String get recoveryCreate;

  /// Título del estado con la copia preparada.
  ///
  /// In es, this message translates to:
  /// **'Código preparado'**
  String get recoveryPreparedTitle;

  /// Explicación del estado con la copia preparada.
  ///
  /// In es, this message translates to:
  /// **'La copia cifrada está lista. Las palabras no se pueden volver a ver: si las pierdes, cambia el código.'**
  String get recoveryPreparedBody;

  /// Título mientras se prepara o actualiza la copia de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Preparando la copia…'**
  String get recoveryPendingTitle;

  /// Explicación mientras se prepara o actualiza la copia.
  ///
  /// In es, this message translates to:
  /// **'Se está guardando la copia cifrada. Hace falta conexión; se completa sola cuando la haya.'**
  String get recoveryPendingBody;

  /// Título del estado que necesita atención en Código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Hay que revisar el código'**
  String get recoveryAttentionTitle;

  /// Fila y título para crear un código nuevo que sustituye al anterior.
  ///
  /// In es, this message translates to:
  /// **'Cambiar el código'**
  String get recoveryChange;

  /// Frase bajo la fila Cambiar el código.
  ///
  /// In es, this message translates to:
  /// **'Los ficheros y las palabras anteriores dejarán de servir.'**
  String get recoveryChangeHint;

  /// Fila (en rojo) que borra la copia de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Quitar el código'**
  String get recoveryRemove;

  /// Frase bajo la fila Quitar el código.
  ///
  /// In es, this message translates to:
  /// **'Las palabras dejarán de valer y se borra la copia.'**
  String get recoveryRemoveHint;

  /// Título del diálogo de confirmación al quitar el código.
  ///
  /// In es, this message translates to:
  /// **'¿Quitar el código de recuperación?'**
  String get recoveryRemoveTitle;

  /// Texto del diálogo de confirmación al quitar el código.
  ///
  /// In es, this message translates to:
  /// **'Se borra la copia de recuperación y las 24 palabras dejan de valer. Podrás crear otro código cuando quieras.'**
  String get recoveryRemoveBody;

  /// Aviso extra del diálogo de quitar el código cuando no queda otro móvil ni la web: también se retira la copia del servidor.
  ///
  /// In es, this message translates to:
  /// **'Como no hay otro móvil ni la web conectados, también se borra la copia cifrada de la lista del servidor y la lista vuelve a estar solo en este móvil.'**
  String get recoveryRemoveSoloNote;

  /// Botón rojo que confirma quitar el código.
  ///
  /// In es, this message translates to:
  /// **'Quitar código'**
  String get recoveryRemoveConfirm;

  /// Aviso tras quitar el código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Código quitado'**
  String get recoveryRemoved;

  /// Botón que repite lo que falló en la recuperación.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get recoveryRetry;

  /// Título del primer paso al crear el código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Crear el código'**
  String get recoveryIntroTitle;

  /// Título del primer paso al cambiar el código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Cambiar el código'**
  String get recoveryRotateTitle;

  /// Explicación del primer paso al crear el código.
  ///
  /// In es, this message translates to:
  /// **'Verás 24 palabras. Con ellas puedes recuperar la lista y todo lo que este móvil puede ver en otro móvil.'**
  String get recoveryIntroBody;

  /// Explicación del primer paso al cambiar el código.
  ///
  /// In es, this message translates to:
  /// **'Se creará un código nuevo. El anterior dejará de valer cuando el nuevo esté preparado: los ficheros y las palabras anteriores dejarán de servir.'**
  String get recoveryRotateBody;

  /// Primera idea del aviso previo al código.
  ///
  /// In es, this message translates to:
  /// **'Apúntalas en papel o guárdalas en un gestor de contraseñas.'**
  String get recoveryPoint1;

  /// Segunda idea del aviso previo al código.
  ///
  /// In es, this message translates to:
  /// **'Quien las tenga puede entrar como este móvil.'**
  String get recoveryPoint2;

  /// Tercera idea del aviso previo al código.
  ///
  /// In es, this message translates to:
  /// **'No recuperan lo que nunca se sincronizó.'**
  String get recoveryPoint3;

  /// Botón que pasa al siguiente paso del código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get recoveryContinue;

  /// Título de la pantalla que pide el PIN antes de enseñar el código.
  ///
  /// In es, this message translates to:
  /// **'Código de recuperación'**
  String get recoveryAuthTitle;

  /// Frase de la pantalla que pide el PIN antes de enseñar el código.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN para ver las palabras.'**
  String get recoveryAuthMessage;

  /// Motivo que se enseña al pedir la huella o el rostro antes de enseñar el código.
  ///
  /// In es, this message translates to:
  /// **'Confirma que eres tú para ver el código de recuperación'**
  String get recoveryAuthBiometric;

  /// Texto del botón mientras se crea el código.
  ///
  /// In es, this message translates to:
  /// **'Preparando el código…'**
  String get recoveryMaking;

  /// Título del paso que enseña las palabras.
  ///
  /// In es, this message translates to:
  /// **'Tus 24 palabras'**
  String get recoveryWordsTitle;

  /// Explicación del paso que enseña las palabras.
  ///
  /// In es, this message translates to:
  /// **'Apúntalas en orden. Cuando salgas de este proceso, no podrás volver a verlas.'**
  String get recoveryWordsBody;

  /// Aviso del paso que enseña las palabras.
  ///
  /// In es, this message translates to:
  /// **'Quien tenga estas palabras puede entrar como este móvil. No hagas captura ni las envíes por mensaje.'**
  String get recoveryWordsWarn;

  /// Etiqueta accesible de cada palabra del código.
  ///
  /// In es, this message translates to:
  /// **'Palabra {number}: {word}'**
  String recoveryWordItem(int number, String word);

  /// Botón que cambia las palabras por el QR.
  ///
  /// In es, this message translates to:
  /// **'Ver código QR'**
  String get recoveryShowQr;

  /// Botón que cambia el QR por las palabras.
  ///
  /// In es, this message translates to:
  /// **'Ver las palabras'**
  String get recoveryShowWords;

  /// Explicación bajo el QR de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Este QR permite recuperar la lista igual que las 24 palabras. No hagas capturas ni lo envíes por mensaje.'**
  String get recoveryQrBody;

  /// Etiqueta accesible del QR de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Código QR de recuperación'**
  String get recoveryQrLabel;

  /// Botón que pasa a comprobar las palabras.
  ///
  /// In es, this message translates to:
  /// **'Ya las he guardado'**
  String get recoveryWordsSaved;

  /// Texto que tapa las palabras cuando la app no está en primer plano.
  ///
  /// In es, this message translates to:
  /// **'Palabras ocultas'**
  String get recoveryHidden;

  /// Frase bajo Palabras ocultas.
  ///
  /// In es, this message translates to:
  /// **'Vuelve a la app para verlas.'**
  String get recoveryHiddenBody;

  /// Título del diálogo al salir de las palabras sin terminar.
  ///
  /// In es, this message translates to:
  /// **'¿Salir sin guardar las palabras?'**
  String get recoveryLeaveTitle;

  /// Texto del diálogo al salir de las palabras sin terminar.
  ///
  /// In es, this message translates to:
  /// **'No se volverán a mostrar. Si sales, tendrás que cambiar el código para ver unas nuevas.'**
  String get recoveryLeaveBody;

  /// Botón que confirma salir sin guardar las palabras.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get recoveryLeaveConfirm;

  /// Botón que cancela salir sin guardar las palabras.
  ///
  /// In es, this message translates to:
  /// **'Seguir aquí'**
  String get recoveryLeaveStay;

  /// Título del paso que pide tres palabras.
  ///
  /// In es, this message translates to:
  /// **'Comprueba que las has guardado'**
  String get recoveryCheckTitle;

  /// Explicación del paso que pide tres palabras por su número.
  ///
  /// In es, this message translates to:
  /// **'Escribe las palabras {a}, {b} y {c}.'**
  String recoveryCheckBody(int a, int b, int c);

  /// Etiqueta de cada campo de la comprobación.
  ///
  /// In es, this message translates to:
  /// **'Palabra {number}'**
  String recoveryCheckField(int number);

  /// Error de la comprobación de tres palabras.
  ///
  /// In es, this message translates to:
  /// **'Alguna palabra no coincide. Míralas otra vez.'**
  String get recoveryCheckWrong;

  /// Botón de la comprobación que vuelve a las palabras.
  ///
  /// In es, this message translates to:
  /// **'Ver las palabras otra vez'**
  String get recoveryCheckBack;

  /// Botón de la comprobación de tres palabras.
  ///
  /// In es, this message translates to:
  /// **'Comprobar'**
  String get recoveryCheckButton;

  /// Título final cuando la copia ya está confirmada.
  ///
  /// In es, this message translates to:
  /// **'Código preparado'**
  String get recoveryDonePreparedTitle;

  /// Texto final cuando la copia ya está confirmada.
  ///
  /// In es, this message translates to:
  /// **'Si pierdes este móvil, podrás recuperar la lista con tu código de recuperación.'**
  String get recoveryDonePreparedBody;

  /// Texto final mientras la copia aún no está confirmada.
  ///
  /// In es, this message translates to:
  /// **'Todavía no está listo: se está guardando la copia cifrada. Hace falta conexión y se completa sola.'**
  String get recoveryDonePendingBody;

  /// Botón que cierra el flujo del código cuando está preparado.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get recoveryDoneButton;

  /// Botón que cierra el flujo del código sin esperar a la copia.
  ///
  /// In es, this message translates to:
  /// **'Cerrar y seguir luego'**
  String get recoveryCloseLater;

  /// Título del problema de red al recuperar o mantener el código.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get recoveryProblemOfflineTitle;

  /// Explicación del problema de red.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido llegar al servidor. Comprueba la conexión y reintenta; lo hecho hasta ahora se conserva.'**
  String get recoveryProblemOfflineBody;

  /// Título del problema de código incorrecto.
  ///
  /// In es, this message translates to:
  /// **'Ese código no abre ninguna lista'**
  String get recoveryProblemWrongTitle;

  /// Explicación del problema de código incorrecto.
  ///
  /// In es, this message translates to:
  /// **'Revisa las palabras o prueba con otro código. Si lo cambiaron, usa el más reciente.'**
  String get recoveryProblemWrongBody;

  /// Título del problema de código retirado.
  ///
  /// In es, this message translates to:
  /// **'Ese código ya no vale'**
  String get recoveryProblemRetiredTitle;

  /// Explicación del problema de código retirado.
  ///
  /// In es, this message translates to:
  /// **'Se cambió o se quitó desde otro móvil. Busca el código más reciente.'**
  String get recoveryProblemRetiredBody;

  /// Título del problema de móvil quitado de la familia.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya no está en la familia'**
  String get recoveryProblemRemovedTitle;

  /// Explicación del problema de móvil quitado de la familia.
  ///
  /// In es, this message translates to:
  /// **'Se quitó este móvil de la lista, así que no se puede recuperar con este código.'**
  String get recoveryProblemRemovedBody;

  /// Título del problema de recuperación incompleta.
  ///
  /// In es, this message translates to:
  /// **'La recuperación se quedó a medias'**
  String get recoveryProblemIncompleteTitle;

  /// Explicación del problema de recuperación incompleta.
  ///
  /// In es, this message translates to:
  /// **'Falta una parte de la lista. Lo descargado se conserva. Vuelve a intentarlo con conexión o, si tienes otro móvil conectado a esta familia, abre allí la app un momento.'**
  String get recoveryProblemIncompleteBody;

  /// Título del problema de operación pendiente.
  ///
  /// In es, this message translates to:
  /// **'Hay otra operación en marcha'**
  String get recoveryProblemBusyTitle;

  /// Explicación del problema de operación pendiente.
  ///
  /// In es, this message translates to:
  /// **'Espera un momento y reintenta.'**
  String get recoveryProblemBusyBody;

  /// Título del problema de copia no soportada o dañada.
  ///
  /// In es, this message translates to:
  /// **'No se puede abrir esta copia'**
  String get recoveryProblemUnsupportedTitle;

  /// Explicación del problema de copia no soportada o dañada.
  ///
  /// In es, this message translates to:
  /// **'Puede que haga falta actualizar la app, o que la copia esté dañada.'**
  String get recoveryProblemUnsupportedBody;

  /// Título del problema de recuperación no disponible.
  ///
  /// In es, this message translates to:
  /// **'No disponible ahora'**
  String get recoveryProblemUnavailableTitle;

  /// Explicación del problema de recuperación no disponible.
  ///
  /// In es, this message translates to:
  /// **'La recuperación no está disponible en este móvil.'**
  String get recoveryProblemUnavailableBody;

  /// Título del problema genérico.
  ///
  /// In es, this message translates to:
  /// **'Algo no ha salido bien'**
  String get recoveryProblemOtherTitle;

  /// Explicación del problema genérico.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido terminar. Reintenta; si sigue igual, prueba más tarde.'**
  String get recoveryProblemOtherBody;

  /// Botón de la bienvenida que abre la recuperación con las 24 palabras.
  ///
  /// In es, this message translates to:
  /// **'Tengo un código de recuperación'**
  String get obHaveRecoveryCode;

  /// Título de la pantalla donde se escriben las 24 palabras.
  ///
  /// In es, this message translates to:
  /// **'Recuperar la lista'**
  String get recoverTitle;

  /// Explicación de la pantalla donde se escriben las 24 palabras.
  ///
  /// In es, this message translates to:
  /// **'Escribe las 24 palabras en orden o escanea el código QR de recuperación.'**
  String get recoverBody;

  /// Etiqueta de cada campo de palabra al recuperar.
  ///
  /// In es, this message translates to:
  /// **'Palabra {number}'**
  String recoverWordField(int number);

  /// Contador de palabras válidas escritas.
  ///
  /// In es, this message translates to:
  /// **'{count} de 24 palabras'**
  String recoverFilled(int count);

  /// Botón que pega las 24 palabras de golpe.
  ///
  /// In es, this message translates to:
  /// **'Pegar las 24 palabras'**
  String get recoverPaste;

  /// Botón que abre la cámara para leer el QR del código.
  ///
  /// In es, this message translates to:
  /// **'Escanear el QR'**
  String get recoverScan;

  /// Botón que empieza la recuperación.
  ///
  /// In es, this message translates to:
  /// **'Recuperar la lista'**
  String get recoverSubmit;

  /// Error de una palabra que no existe.
  ///
  /// In es, this message translates to:
  /// **'La palabra {number} no está en la lista.'**
  String recoverWordUnknown(int number);

  /// Error cuando las 24 palabras no pasan la suma de control.
  ///
  /// In es, this message translates to:
  /// **'Las palabras no forman un código válido. Revisa el orden y que no falte ninguna.'**
  String get recoverChecksum;

  /// Aviso al pegar sin texto copiado.
  ///
  /// In es, this message translates to:
  /// **'No hay nada copiado.'**
  String get recoverPasteEmpty;

  /// Aviso al pegar un texto que no tiene 24 palabras.
  ///
  /// In es, this message translates to:
  /// **'Lo copiado no tiene 24 palabras.'**
  String get recoverPasteWrong;

  /// Aviso al leer un QR que no es el código.
  ///
  /// In es, this message translates to:
  /// **'Ese QR no es un código de recuperación.'**
  String get recoverQrWrong;

  /// Título de la pantalla de la cámara.
  ///
  /// In es, this message translates to:
  /// **'Escanear el QR del código'**
  String get recoverScanTitle;

  /// Frase de la pantalla de la cámara.
  ///
  /// In es, this message translates to:
  /// **'Apunta la cámara al código QR de recuperación.'**
  String get recoverScanBody;

  /// Título mientras se recupera.
  ///
  /// In es, this message translates to:
  /// **'Recuperando la lista'**
  String get recoverProgressTitle;

  /// Frase mientras se recupera.
  ///
  /// In es, this message translates to:
  /// **'No cierres la app. Puede tardar un minuto.'**
  String get recoverProgressBody;

  /// Primer paso del progreso de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Buscando la copia'**
  String get recoverStepFind;

  /// Segundo paso del progreso de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Comprobando el código'**
  String get recoverStepCheck;

  /// Tercer paso del progreso de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Descargando la lista'**
  String get recoverStepDownload;

  /// Cuarto paso del progreso de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Instalando en este móvil'**
  String get recoverStepInstall;

  /// Título del resultado al recuperar.
  ///
  /// In es, this message translates to:
  /// **'Lista recuperada'**
  String get recoverDoneTitle;

  /// Resultado: la persona a la que pertenece el móvil recuperado.
  ///
  /// In es, this message translates to:
  /// **'Este móvil es de {name}.'**
  String recoverDoneSelf(String name);

  /// Resultado: el móvil recuperado no tiene persona de Yo.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no tiene persona asignada. Puedes elegirla en Ajustes.'**
  String get recoverDoneNoSelf;

  /// Resultado: cuántas personas tiene la lista recuperada.
  ///
  /// In es, this message translates to:
  /// **'Tu lista tiene {count, plural, one{1 persona} other{{count} personas}}.'**
  String recoverDonePeople(int count);

  /// Botón que entra en la lista recuperada.
  ///
  /// In es, this message translates to:
  /// **'Entrar en la lista'**
  String get recoverEnter;

  /// Botón que vuelve a pedir las palabras tras un código que no vale.
  ///
  /// In es, this message translates to:
  /// **'Escribir otro código'**
  String get recoverOtherCode;

  /// Título de la pantalla de solo lectura tras traspasar la lista.
  ///
  /// In es, this message translates to:
  /// **'Esta lista se ha pasado a otro móvil'**
  String get transferredTitle;

  /// Explicación de la pantalla de solo lectura tras traspasar la lista.
  ///
  /// In es, this message translates to:
  /// **'Tu lista ahora está en otro móvil o en otra app, y esta app ya no se usa para ella. Lo que ves aquí es una copia de solo lectura: no se ha borrado nada.'**
  String get transferredBody;

  /// Etiqueta de la copia que se ve tras traspasar la lista.
  ///
  /// In es, this message translates to:
  /// **'Solo lectura'**
  String get transferredReadOnly;

  /// Título del problema de código de otra familia.
  ///
  /// In es, this message translates to:
  /// **'Este código es de otra familia'**
  String get recoveryProblemFamilyTitle;

  /// Explicación del problema de código de otra familia.
  ///
  /// In es, this message translates to:
  /// **'Sustituiría la lista que tienes en este móvil. Si no es lo que quieres, cancela la recuperación.'**
  String get recoveryProblemFamilyBody;

  /// Título cuando la copia cifrada no ha quedado preparada.
  ///
  /// In es, this message translates to:
  /// **'La copia todavía no está lista'**
  String get recoveryProblemNotReadyTitle;

  /// Explicación cuando la copia cifrada no ha quedado preparada.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido dejar la copia cifrada en el servidor, así que no se enseñan las palabras. Reintenta con conexión.'**
  String get recoveryProblemNotReadyBody;

  /// Título del diálogo cuando el código es de otra familia.
  ///
  /// In es, this message translates to:
  /// **'¿Sustituir la lista de este móvil?'**
  String get recoverReplaceTitle;

  /// Texto del diálogo cuando el código es de otra familia.
  ///
  /// In es, this message translates to:
  /// **'Este código es de otra familia. Si continúas, la lista de esa familia sustituirá a la que tienes en este móvil. La lista anterior se conserva en el móvil, pero deja de verse.'**
  String get recoverReplaceBody;

  /// Botón que confirma sustituir la familia de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Sustituir'**
  String get recoverReplaceConfirm;

  /// Botón que descarta una recuperación a medias en este móvil.
  ///
  /// In es, this message translates to:
  /// **'Cancelar la recuperación'**
  String get recoverAbandon;

  /// Título del diálogo al cancelar la recuperación.
  ///
  /// In es, this message translates to:
  /// **'¿Cancelar la recuperación?'**
  String get recoverAbandonTitle;

  /// Texto del diálogo al cancelar la recuperación.
  ///
  /// In es, this message translates to:
  /// **'Se descartan los datos temporales de esta recuperación en este móvil. Cancelar no reactiva el móvil anterior si ya quedó en solo lectura. Podrás volver a introducir el código.'**
  String get recoverAbandonBody;

  /// Botón que confirma cancelar la recuperación.
  ///
  /// In es, this message translates to:
  /// **'Cancelar recuperación'**
  String get recoverAbandonConfirm;

  /// Botón que no cancela la recuperación.
  ///
  /// In es, this message translates to:
  /// **'Seguir'**
  String get recoverAbandonKeep;

  /// Aviso cuando cancelar la recuperación falla.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido cancelar. Reintenta en un momento.'**
  String get recoverAbandonFailed;

  /// Texto del diálogo al cancelar una recuperación cuya reclamación ya se envió.
  ///
  /// In es, this message translates to:
  /// **'La lista ya se ha pasado a este código y el otro móvil se ha quedado en solo lectura; cancelar no lo deshace. Para usarla tendrás que escribir el código otra vez.'**
  String get recoverAbandonBodyClaimed;

  /// Aviso extra en los móviles que no pueden bloquear las capturas (iPhone).
  ///
  /// In es, this message translates to:
  /// **'Este móvil no puede bloquear las capturas de pantalla: no hagas ninguna.'**
  String get recoveryWordsWarnNoBlock;

  /// Título del diálogo al salir de la pantalla de recuperar con una recuperación a medias.
  ///
  /// In es, this message translates to:
  /// **'¿Salir de la recuperación?'**
  String get recoverLeaveTitle;

  /// Texto del diálogo al salir de la pantalla de recuperar con una recuperación a medias.
  ///
  /// In es, this message translates to:
  /// **'Se queda a medias en este móvil. Podrás reanudarla o cancelarla desde la pantalla de bienvenida.'**
  String get recoverLeaveBody;

  /// Título del aviso de la bienvenida cuando hay una recuperación a medias.
  ///
  /// In es, this message translates to:
  /// **'Hay una recuperación en curso'**
  String get recoverPendingTitle;

  /// Texto del aviso de la bienvenida cuando hay una recuperación a medias.
  ///
  /// In es, this message translates to:
  /// **'Se quedó a medias en este móvil. Reanúdala o cancélala antes de crear una familia o unirte a otra.'**
  String get recoverPendingBody;

  /// Botón que reanuda una recuperación a medias.
  ///
  /// In es, this message translates to:
  /// **'Reanudar'**
  String get recoverResume;

  /// Título del problema de recuperación pendiente al crear o unirse a una familia.
  ///
  /// In es, this message translates to:
  /// **'Hay una recuperación a medias'**
  String get recoveryProblemPendingTitle;

  /// Explicación del problema de recuperación pendiente.
  ///
  /// In es, this message translates to:
  /// **'Reanúdala o cancélala antes de crear una familia o unirte a otra.'**
  String get recoveryProblemPendingBody;

  /// Botón que cancela el mantenimiento atascado del código de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Cancelar la preparación'**
  String get recoveryMaintCancel;

  /// Título del diálogo al cancelar el mantenimiento del código.
  ///
  /// In es, this message translates to:
  /// **'¿Cancelar la preparación del código?'**
  String get recoveryMaintCancelTitle;

  /// Texto del diálogo al cancelar el mantenimiento del código.
  ///
  /// In es, this message translates to:
  /// **'El código que ya tengas sigue valiendo. Se deja de preparar lo que estaba en marcha.'**
  String get recoveryMaintCancelBody;

  /// Botón que confirma cancelar el mantenimiento del código.
  ///
  /// In es, this message translates to:
  /// **'Cancelar preparación'**
  String get recoveryMaintCancelConfirm;

  /// Frase de la pantalla que pide el PIN antes de quitar el código.
  ///
  /// In es, this message translates to:
  /// **'Escribe tu PIN para quitar el código.'**
  String get recoveryRemoveAuthMessage;

  /// Motivo de la huella o el rostro antes de quitar el código.
  ///
  /// In es, this message translates to:
  /// **'Confirma que quieres quitar el código de recuperación'**
  String get recoveryRemoveBiometric;

  /// Botón de la pantalla de solo lectura que abre la recuperación con las 24 palabras.
  ///
  /// In es, this message translates to:
  /// **'Recuperar con mi código'**
  String get transferredRecover;

  /// Botón (en rojo) de la pantalla de solo lectura que borra todo lo de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Borrar todo de este móvil'**
  String get transferredErase;

  /// Valor accesible de un paso de la recuperación ya hecho.
  ///
  /// In es, this message translates to:
  /// **'hecho'**
  String get recoverStepDoneValue;

  /// Valor accesible del paso de la recuperación que está en curso.
  ///
  /// In es, this message translates to:
  /// **'en curso'**
  String get recoverStepActiveValue;

  /// Botón de la pantalla de las palabras que abre el guardado en un fichero.
  ///
  /// In es, this message translates to:
  /// **'Guardar en un fichero'**
  String get recoveryFileAction;

  /// Título de la pantalla para guardar el código en un fichero.
  ///
  /// In es, this message translates to:
  /// **'Guardar en un fichero'**
  String get recoveryFileTitle;

  /// Explicación de la pantalla para guardar el código en un fichero.
  ///
  /// In es, this message translates to:
  /// **'Además de las palabras, puedes guardar el código en un fichero. Quien tenga el fichero puede recuperar la lista y entrar como este móvil.'**
  String get recoveryFileBody;

  /// Aviso: el fichero es personal y no se envía a la familia.
  ///
  /// In es, this message translates to:
  /// **'Es un fichero personal: no lo envíes a la familia. Guárdalo donde puedas abrirlo aunque pierdas este móvil.'**
  String get recoveryFilePersonal;

  /// Casilla para proteger el fichero con una contraseña (desactivada por defecto).
  ///
  /// In es, this message translates to:
  /// **'Proteger con contraseña'**
  String get recoveryFileProtect;

  /// Aviso bajo la casilla cuando no se protege con contraseña.
  ///
  /// In es, this message translates to:
  /// **'Sin contraseña, el fichero vale tanto como las palabras: quien lo consiga puede usarlo.'**
  String get recoveryFileProtectOffHint;

  /// Texto bajo la casilla cuando se protege con contraseña.
  ///
  /// In es, this message translates to:
  /// **'Robar el fichero no basta: hace falta la contraseña.'**
  String get recoveryFileProtectOnHint;

  /// Etiqueta del campo de contraseña del fichero.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get recoveryFilePassword;

  /// Etiqueta del campo que repite la contraseña del fichero.
  ///
  /// In es, this message translates to:
  /// **'Repite la contraseña'**
  String get recoveryFilePasswordRepeat;

  /// Botón que muestra la contraseña escrita.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get recoveryFilePasswordShow;

  /// Botón que oculta la contraseña escrita.
  ///
  /// In es, this message translates to:
  /// **'Ocultar'**
  String get recoveryFilePasswordHide;

  /// Ayuda bajo el campo de contraseña nueva. {min} es el mínimo de caracteres.
  ///
  /// In es, this message translates to:
  /// **'Mínimo {min} caracteres. Usa el gestor de contraseñas o varias palabras elegidas al azar.'**
  String recoveryFilePasswordHelp(int min);

  /// Aviso: olvidar la contraseña inutiliza el fichero pero no las palabras.
  ///
  /// In es, this message translates to:
  /// **'Si olvidas la contraseña, el fichero no sirve para nada. Las 24 palabras seguirán valiendo.'**
  String get recoveryFilePasswordForgot;

  /// Motivo: contraseña demasiado corta. {min} es el mínimo.
  ///
  /// In es, this message translates to:
  /// **'Es muy corta: mínimo {min} caracteres.'**
  String recoveryFilePwTooShort(int min);

  /// Motivo: contraseña demasiado larga. {max} es el máximo.
  ///
  /// In es, this message translates to:
  /// **'Es demasiado larga: máximo {max} caracteres.'**
  String recoveryFilePwTooLong(int max);

  /// Motivo: la contraseña repite un carácter o un bloque corto.
  ///
  /// In es, this message translates to:
  /// **'Repite un mismo carácter o bloque.'**
  String get recoveryFilePwRepeated;

  /// Motivo: la contraseña es solo números.
  ///
  /// In es, this message translates to:
  /// **'No puede ser solo números.'**
  String get recoveryFilePwDigits;

  /// Motivo: la contraseña es una fila o secuencia de teclado.
  ///
  /// In es, this message translates to:
  /// **'Parece una fila o secuencia de teclas.'**
  String get recoveryFilePwKeyboard;

  /// Motivo: la contraseña contiene el nombre de la app.
  ///
  /// In es, this message translates to:
  /// **'No puede contener el nombre de la app.'**
  String get recoveryFilePwAppName;

  /// Motivo: la contraseña es una frase muy frecuente.
  ///
  /// In es, this message translates to:
  /// **'Es una frase demasiado común.'**
  String get recoveryFilePwCommon;

  /// Motivo: las dos contraseñas no coinciden.
  ///
  /// In es, this message translates to:
  /// **'Las dos contraseñas no coinciden.'**
  String get recoveryFilePwMismatch;

  /// Botón que guarda el fichero con el selector del sistema.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get recoveryFileSave;

  /// Botón para guardar otra copia del fichero tras guardar una.
  ///
  /// In es, this message translates to:
  /// **'Guardar otra copia'**
  String get recoveryFileSaveAgain;

  /// Botón que comparte el fichero con la hoja de compartir del sistema.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get recoveryFileShare;

  /// Texto que acompaña al fichero al compartirlo.
  ///
  /// In es, this message translates to:
  /// **'Fichero de recuperación de Gift Huddle. Es personal: no lo reenvíes a la familia.'**
  String get recoveryFileShareText;

  /// Principio del nombre del fichero guardado; se le añade la fecha y la extensión. Sin espacios, tildes ni mayúsculas.
  ///
  /// In es, this message translates to:
  /// **'gift-huddle-recuperacion'**
  String get recoveryFileStem;

  /// Título mientras se prepara la clave de la contraseña del fichero.
  ///
  /// In es, this message translates to:
  /// **'Protegiendo el fichero…'**
  String get recoveryFileDerivingTitle;

  /// Texto mientras se prepara la clave de la contraseña (unos segundos).
  ///
  /// In es, this message translates to:
  /// **'Se prepara la clave de la contraseña. Tarda unos segundos; no cierres la app.'**
  String get recoveryFileDerivingBody;

  /// Título cuando el fichero se ha guardado y comprobado.
  ///
  /// In es, this message translates to:
  /// **'Fichero guardado'**
  String get recoveryFileSavedTitle;

  /// Texto cuando el fichero se ha guardado y el código queda comprobado.
  ///
  /// In es, this message translates to:
  /// **'Se ha vuelto a leer desde donde lo guardaste y el código está comprobado. Puedes guardar otra copia.'**
  String get recoveryFileSavedBody;

  /// Error: lo releído del destino no coincide.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido comprobar lo guardado'**
  String get recoveryFileProblemVerifyTitle;

  /// Explicación del error de relectura.
  ///
  /// In es, this message translates to:
  /// **'Lo que se ha leído del destino no coincide. Guárdalo de nuevo, quizá en otro sitio.'**
  String get recoveryFileProblemVerifyBody;

  /// Error: no se pudo leer el fichero.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer el fichero'**
  String get recoveryFileProblemUnreadableTitle;

  /// Explicación del error de lectura.
  ///
  /// In es, this message translates to:
  /// **'Comprueba que el fichero está disponible en este móvil e inténtalo otra vez.'**
  String get recoveryFileProblemUnreadableBody;

  /// Error: este móvil no puede abrir el selector de ficheros.
  ///
  /// In es, this message translates to:
  /// **'Este móvil no puede abrir el selector de ficheros'**
  String get recoveryFileProblemUnavailableTitle;

  /// Explicación del error de selector no disponible.
  ///
  /// In es, this message translates to:
  /// **'Prueba con Compartir o usa las 24 palabras.'**
  String get recoveryFileProblemUnavailableBody;

  /// Error: ya hay un selector abierto.
  ///
  /// In es, this message translates to:
  /// **'Ya hay un selector abierto'**
  String get recoveryFileProblemPickerBusyTitle;

  /// Explicación del error de selector ocupado.
  ///
  /// In es, this message translates to:
  /// **'Ciérralo y vuelve a intentarlo.'**
  String get recoveryFileProblemPickerBusyBody;

  /// Error: el fichero elegido no es de recuperación.
  ///
  /// In es, this message translates to:
  /// **'No es un fichero de recuperación'**
  String get recoveryFileProblemNotFileTitle;

  /// Explicación del error de fichero no válido.
  ///
  /// In es, this message translates to:
  /// **'Elige el fichero que guardaste al crear el código. Termina en .gifthuddle.'**
  String get recoveryFileProblemNotFileBody;

  /// Error: el fichero es de una versión más nueva.
  ///
  /// In es, this message translates to:
  /// **'Fichero de una versión más nueva'**
  String get recoveryFileProblemNewerTitle;

  /// Explicación del error de versión más nueva.
  ///
  /// In es, this message translates to:
  /// **'Actualiza la app y vuelve a intentarlo.'**
  String get recoveryFileProblemNewerBody;

  /// Error: contraseña incorrecta o fichero dañado.
  ///
  /// In es, this message translates to:
  /// **'Contraseña incorrecta o fichero dañado'**
  String get recoveryFileProblemPasswordTitle;

  /// Explicación del error de contraseña (no se distingue de un fichero dañado).
  ///
  /// In es, this message translates to:
  /// **'Revisa la contraseña. Si no la recuerdas, usa las 24 palabras.'**
  String get recoveryFileProblemPasswordBody;

  /// Error: el fichero es de otro código, no del vigente.
  ///
  /// In es, this message translates to:
  /// **'Este fichero es de otro código'**
  String get recoveryFileProblemNotCurrentTitle;

  /// Explicación del error de fichero de otro código.
  ///
  /// In es, this message translates to:
  /// **'Se guardó con un código anterior y ya no vale. Busca uno más reciente o cambia el código.'**
  String get recoveryFileProblemNotCurrentBody;

  /// Aviso: este móvil ya tiene una lista y el fichero solo sirve para un móvil vacío.
  ///
  /// In es, this message translates to:
  /// **'Este móvil ya tiene una lista'**
  String get recoveryFileProblemHasFamilyTitle;

  /// Explicación del aviso de móvil con lista.
  ///
  /// In es, this message translates to:
  /// **'El fichero de recuperación sirve para un móvil vacío. No se ha usado.'**
  String get recoveryFileProblemHasFamilyBody;

  /// Botón de Ajustes que comprueba un fichero de recuperación ya guardado.
  ///
  /// In es, this message translates to:
  /// **'Comprobar un fichero'**
  String get recoveryCheckFileAction;

  /// Título de la pantalla Comprobar un fichero.
  ///
  /// In es, this message translates to:
  /// **'Comprobar un fichero'**
  String get recoveryCheckFileTitle;

  /// Explicación de la pantalla Comprobar un fichero.
  ///
  /// In es, this message translates to:
  /// **'Elige el fichero de recuperación que guardaste. Si abre el código de este móvil, queda comprobado. No se guarda ni se envía nada.'**
  String get recoveryCheckFileBody;

  /// Botón que abre el selector de ficheros del sistema para elegir un fichero de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Elegir fichero'**
  String get recoveryFilePick;

  /// Título del paso que pide la contraseña de un fichero.
  ///
  /// In es, this message translates to:
  /// **'Contraseña del fichero'**
  String get recoveryFilePasswordTitle;

  /// Explicación del paso que pide la contraseña de un fichero protegido.
  ///
  /// In es, this message translates to:
  /// **'Este fichero está protegido. Escribe la contraseña que pusiste al guardarlo.'**
  String get recoveryFilePasswordOpenBody;

  /// Botón que abre el fichero con la contraseña escrita.
  ///
  /// In es, this message translates to:
  /// **'Abrir el fichero'**
  String get recoveryFileOpen;

  /// Título mientras se comprueba un fichero.
  ///
  /// In es, this message translates to:
  /// **'Comprobando el fichero…'**
  String get recoveryFileCheckingTitle;

  /// Texto mientras se comprueba un fichero.
  ///
  /// In es, this message translates to:
  /// **'Un momento.'**
  String get recoveryFileCheckingBody;

  /// Título cuando un fichero abre el código vigente.
  ///
  /// In es, this message translates to:
  /// **'Código comprobado'**
  String get recoveryCheckFileOkTitle;

  /// Texto cuando un fichero abre el código vigente.
  ///
  /// In es, this message translates to:
  /// **'El fichero abre el código de este móvil. Si pierdes el móvil, podrás recuperar la lista con él.'**
  String get recoveryCheckFileOkBody;

  /// Botón de la bienvenida para recuperar la lista con un fichero de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Recuperar con fichero'**
  String get obRecoverWithFile;

  /// Título de la pantalla de recuperar con un fichero.
  ///
  /// In es, this message translates to:
  /// **'Recuperar con un fichero'**
  String get recoverFileTitle;

  /// Explicación de la pantalla de recuperar con un fichero.
  ///
  /// In es, this message translates to:
  /// **'Elige el fichero de recuperación que guardaste al crear el código. Termina en .gifthuddle.'**
  String get recoverFileBody;

  /// Aviso cuando la app se abrió con un fichero de recuperación desde Archivos u otra app.
  ///
  /// In es, this message translates to:
  /// **'Has abierto un fichero de recuperación.'**
  String get recoverFileReceived;

  /// Título de la confirmación antes de recuperar con un fichero.
  ///
  /// In es, this message translates to:
  /// **'¿Recuperar con este fichero?'**
  String get recoverFileConfirmTitle;

  /// Texto de la confirmación antes de recuperar con un fichero.
  ///
  /// In es, this message translates to:
  /// **'Este móvil recuperará la lista y entrará como el móvil que guardó el código. Si no es tu fichero, no continúes.'**
  String get recoverFileConfirmBody;

  /// Botón para elegir otro fichero de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Elegir otro fichero'**
  String get recoverFileOther;

  /// Título del aviso cuando llega un segundo fichero de recuperación mientras se usa uno.
  ///
  /// In es, this message translates to:
  /// **'Ha llegado otro fichero'**
  String get recoverFileWaitingTitle;

  /// Pregunta cuando llega un segundo fichero de recuperación.
  ///
  /// In es, this message translates to:
  /// **'Estabas con otro fichero de recuperación. ¿Quieres cambiar a este?'**
  String get recoverFileWaitingBody;

  /// Botón para cambiar al fichero recién llegado.
  ///
  /// In es, this message translates to:
  /// **'Cambiar de fichero'**
  String get recoverFileWaitingSwitch;

  /// Botón para seguir con el fichero de antes.
  ///
  /// In es, this message translates to:
  /// **'Seguir con el actual'**
  String get recoverFileWaitingKeep;

  /// Título del error cuando cambió la persona de «Yo» (o hay una invalidación pendiente) y el código ya no vale.
  ///
  /// In es, this message translates to:
  /// **'Este código ya no es el de tu persona actual'**
  String get recoveryProblemPersonTitle;

  /// Explicación del error de código que ya no es el de la persona actual.
  ///
  /// In es, this message translates to:
  /// **'Cambió la persona de este móvil o hay un cambio pendiente. Crea un código nuevo y guarda ese.'**
  String get recoveryProblemPersonBody;

  /// Error al leer la familia local antes de abrir un fichero recibido.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido leer la lista de este móvil'**
  String get recoveryFileProblemStorageTitle;

  /// Conserva el fichero y pide reintentar sin asumir que el móvil esté vacío.
  ///
  /// In es, this message translates to:
  /// **'El fichero sigue a la espera. Vuelve a intentarlo: antes de recuperar, la app tiene que comprobar que este móvil no tiene ya una lista.'**
  String get recoveryFileProblemStorageBody;

  /// No description provided for @cameraRestricted.
  ///
  /// In es, this message translates to:
  /// **'La cámara está restringida en este dispositivo (por ejemplo, con Tiempo de uso). Puedes permitirla en Ajustes > Tiempo de uso > Restricciones de contenido y privacidad.'**
  String get cameraRestricted;

  /// Botón de la bienvenida y título de su hoja: unirse a la lista de otro móvil.
  ///
  /// In es, this message translates to:
  /// **'Unirme a una familia'**
  String get obJoinFamily;

  /// Frase bajo el título de la hoja «Unirme a una familia».
  ///
  /// In es, this message translates to:
  /// **'Elige cómo conectarte con el móvil que ya tiene la lista.'**
  String get obJoinFamilyHint;

  /// Frase de la opción del QR en la hoja «Unirme a una familia».
  ///
  /// In es, this message translates to:
  /// **'Está contigo: escanea su código.'**
  String get obJoinQrHint;

  /// Frase de la opción del enlace en la hoja «Unirme a una familia».
  ///
  /// In es, this message translates to:
  /// **'Está lejos: pega el enlace que te envió.'**
  String get obJoinLinkHint;

  /// Botón de la bienvenida y título de su hoja: recuperar la lista desde una copia.
  ///
  /// In es, this message translates to:
  /// **'Restaurar una copia'**
  String get obRestoreBackup;

  /// Frase bajo el título de la hoja «Restaurar una copia».
  ///
  /// In es, this message translates to:
  /// **'Elige con qué recuperas la lista.'**
  String get obRestoreBackupHint;

  /// Frase de la opción del código de recuperación en la hoja «Restaurar una copia».
  ///
  /// In es, this message translates to:
  /// **'Escribe las 24 palabras que guardaste.'**
  String get obRestoreCodeHint;

  /// Frase de la opción del fichero en la hoja «Restaurar una copia».
  ///
  /// In es, this message translates to:
  /// **'Abre el fichero de recuperación que guardaste.'**
  String get obRestoreFileHint;

  /// Cabecera de la sección del selector de quién regala con las personas de la familia que aún no son quién regala.
  ///
  /// In es, this message translates to:
  /// **'Personas'**
  String get giverPeopleSection;

  /// Frase bajo una persona del selector de quién regala en un regalo secreto: hay que añadirla antes como quién regala.
  ///
  /// In es, this message translates to:
  /// **'Antes se añade como quién regala'**
  String get giverPeopleHintAdd;

  /// Frase bajo una persona del selector cuya entrada de quién regala estaba archivada.
  ///
  /// In es, this message translates to:
  /// **'Se recupera como quién regala'**
  String get giverPeopleHintRecover;

  /// Título del paso previo en un regalo secreto.
  ///
  /// In es, this message translates to:
  /// **'¿Añadir a {name} como quién regala?'**
  String giverPersonAddTitle(String name);

  /// Texto del paso previo: explica por qué hay que añadir a la persona como quién regala antes de elegirla en un regalo secreto.
  ///
  /// In es, this message translates to:
  /// **'Este regalo es una sorpresa. Para no delatarla, primero hay que añadir a {name} como quién regala para toda la familia, y se verá en todos los móviles sin relación con este regalo. Después podrás elegir a {name} aquí.'**
  String giverPersonAddBody(String name);

  /// Botón del paso previo: añade a la persona como quién regala para toda la familia.
  ///
  /// In es, this message translates to:
  /// **'Añadir a {name} como quién regala'**
  String giverPersonAddConfirm(String name);

  /// Aviso cuando falla el alta de una persona como quién regala.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido añadir a {name} como quién regala.'**
  String giverPersonAddFailed(String name);

  /// Aviso cuando el editor se cierra solo porque el regalo ya no está autorizado en este móvil (otro móvil lo movió a una persona protegida, por ejemplo).
  ///
  /// In es, this message translates to:
  /// **'Este regalo ya no se puede ver en este móvil.'**
  String get giftNoLongerVisible;

  /// Primera frase del diálogo de eliminar a quien regala: nombra lo que se elimina.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Se elimina {names}.} other{Se eliminan estos {count} registros: {names}.}}'**
  String deleteGiverRows(int count, String names);

  /// Títulos de los regalos que se quedan sin quién regala; más indica cuántos no caben en la lista.
  ///
  /// In es, this message translates to:
  /// **'{more, plural, =0{Afecta a: {titles}.} other{Afecta a: {titles} y {more} más.}}'**
  String deleteGiverGiftTitles(String titles, int more);

  /// Consecuencia de eliminar a quien regala si está enlazado a una persona.
  ///
  /// In es, this message translates to:
  /// **'{name} sigue en Personas: solo se elimina como quién regala.'**
  String deleteGiverLinkedNote(String name);

  /// Primera frase del diálogo de eliminar cuando lo que se elimina cambió (otro móvil) y se pide confirmar de nuevo.
  ///
  /// In es, this message translates to:
  /// **'Ha cambiado mientras tenías el aviso abierto. Esto es lo que se eliminaría ahora:'**
  String get deleteImpactChanged;

  /// Consecuencia de eliminar a una persona que también es quién regala en algunos regalos.
  ///
  /// In es, this message translates to:
  /// **'Su nombre seguirá apareciendo en los regalos que dio, como quién regala.'**
  String get deletePersonLinkedGiver;

  /// Título del aviso al intentar eliminar o archivar a la persona de este móvil.
  ///
  /// In es, this message translates to:
  /// **'Este móvil es de {name}'**
  String devicePersonBlockedThisTitle(String name);

  /// Texto del aviso al intentar eliminar o archivar a la persona de este móvil.
  ///
  /// In es, this message translates to:
  /// **'{name} es la persona de este móvil, así que no se puede eliminar ni archivar desde aquí. Para hacerlo, elige antes a otra persona en «Este móvil es de», en Ajustes.'**
  String devicePersonBlockedThisBody(String name);

  /// Título del aviso al intentar eliminar o archivar a la persona dueña de otro móvil de la familia.
  ///
  /// In es, this message translates to:
  /// **'{name} tiene su propio móvil'**
  String devicePersonBlockedOtherTitle(String name);

  /// Texto del aviso al intentar eliminar o archivar a la persona dueña de otro móvil de la familia.
  ///
  /// In es, this message translates to:
  /// **'{name} tiene su propio móvil en la familia, así que no se puede eliminar ni archivar desde aquí.'**
  String devicePersonBlockedOtherBody(String name);

  /// Línea bajo quién regala en Ajustes cuando está enlazado a una persona.
  ///
  /// In es, this message translates to:
  /// **'Enlazado a una persona: su nombre y color se cambian en Personas.'**
  String get giverLinkedLine;

  /// Frase bajo el nombre (no editable) de quién regala enlazado a una persona.
  ///
  /// In es, this message translates to:
  /// **'El nombre y el color son los de {name}. Cámbialos en Personas.'**
  String giverLinkedNameHint(String name);

  /// Fila de la hoja de quién regala y título de la hoja que elige la persona.
  ///
  /// In es, this message translates to:
  /// **'Enlazar con una persona'**
  String get giverLinkLabel;

  /// Frase bajo la fila de enlazar quién regala con una persona.
  ///
  /// In es, this message translates to:
  /// **'Su nombre y color pasarán a ser los de la persona.'**
  String get giverLinkHint;

  /// Frase bajo una persona de la hoja de enlazar que ya tiene su propio quién regala.
  ///
  /// In es, this message translates to:
  /// **'Ya es quién regala: se unirán en una columna'**
  String get giverLinkExistingHint;

  /// Título de la confirmación de enlazar quién regala con una persona.
  ///
  /// In es, this message translates to:
  /// **'¿Enlazar con {name}?'**
  String giverLinkConfirmTitle(String name);

  /// Texto de la confirmación de enlazar quién regala con una persona.
  ///
  /// In es, this message translates to:
  /// **'«{giver}» pasará a llamarse {name}, con su color, y seguirá los cambios de {name} en Personas. Sus regalos se mantienen.'**
  String giverLinkConfirmBody(String giver, String name);

  /// Botón que confirma enlazar quién regala con una persona.
  ///
  /// In es, this message translates to:
  /// **'Enlazar'**
  String get giverLinkConfirm;

  /// Fila de la hoja de quién regala enlazado a una persona.
  ///
  /// In es, this message translates to:
  /// **'Desenlazar de la persona'**
  String get giverUnlinkLabel;

  /// Título de la confirmación de desenlazar quién regala.
  ///
  /// In es, this message translates to:
  /// **'¿Desenlazar de {name}?'**
  String giverUnlinkConfirmTitle(String name);

  /// Texto de la confirmación de desenlazar quién regala.
  ///
  /// In es, this message translates to:
  /// **'Seguirá como quién regala con el nombre y el color de ahora, pero ya no cambiará con {name}. Sus regalos se mantienen.'**
  String giverUnlinkConfirmBody(String name);

  /// Botón que confirma desenlazar quién regala.
  ///
  /// In es, this message translates to:
  /// **'Desenlazar'**
  String get giverUnlinkConfirm;

  /// Aviso cuando falla enlazar o desenlazar quién regala.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido cambiar el enlace. Inténtalo de nuevo.'**
  String get giverLinkError;

  /// Aviso cuando un cambio de un regalo se rechaza porque el regalo no está a la vista.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: este regalo ya no está disponible en este móvil.'**
  String get giftWriteGiftUnavailable;

  /// Aviso cuando se rechaza un cambio porque la persona que recibe el regalo ya no existe.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: la persona a la que va el regalo ya no existe.'**
  String get giftWriteRecipientGone;

  /// Aviso cuando quien regala y quien recibe serían la misma persona.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: quien regala no puede ser quien recibe el regalo.'**
  String get giftWriteInvalidPair;

  /// Aviso cuando quien regala se eliminó mientras tanto.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: quien regala ya no existe.'**
  String get giftWriteGiverGone;

  /// Aviso cuando quien regala se archivó mientras tanto.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: quien regala está archivado.'**
  String get giftWriteGiverArchived;

  /// Aviso cuando la persona elegida como quien regala se eliminó mientras tanto.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: esa persona ya no existe.'**
  String get giftWritePersonGone;

  /// Aviso cuando la persona elegida como quien regala se archivó mientras tanto.
  ///
  /// In es, this message translates to:
  /// **'No se ha guardado: esa persona está archivada.'**
  String get giftWritePersonArchived;

  /// Aviso al desenlazar quién regala cuando otro móvil ya lo había cambiado.
  ///
  /// In es, this message translates to:
  /// **'Ya no estaba enlazado a {name}.'**
  String giverUnlinkStale(String name);

  /// Aviso cuando el diálogo de eliminar se cierra porque no se pudo recalcular lo que se elimina.
  ///
  /// In es, this message translates to:
  /// **'No se ha podido comprobar qué se elimina. Vuelve a abrir el aviso.'**
  String get deleteImpactUnavailable;

  /// Texto del diálogo de eliminar mientras se recalcula lo que se elimina: no enseña títulos ni recuentos.
  ///
  /// In es, this message translates to:
  /// **'Comprobando lo que se elimina…'**
  String get deleteImpactChecking;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ca', 'en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ca':
      return AppLocalizationsCa();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

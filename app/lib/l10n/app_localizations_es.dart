// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Gift Huddle';

  @override
  String get navMainLabel => 'Navegación principal';

  @override
  String get navPeople => 'Personas';

  @override
  String get navFamily => 'Reparto';

  @override
  String get navFamilyShort => 'Reparto';

  @override
  String get navOccasions => 'Ocasiones';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get emptyPeopleTitle => 'Aún no hay personas';

  @override
  String get emptyPeopleMessage =>
      'Añade a las personas a las que regaláis para empezar sus listas de regalos.';

  @override
  String get emptyFamilyTitle => 'Faltan personas';

  @override
  String get emptyFamilyMessage =>
      'Para ver el reparto, hace falta al menos una persona que regale y una que reciba.';

  @override
  String get emptyOccasionsTitle => 'Sin ocasiones';

  @override
  String get emptyOccasionsMessage =>
      'Navidad, cumpleaños y otras fechas aparecerán aquí con su cuenta atrás.';

  @override
  String backTo(String title) {
    return 'Volver a $title';
  }

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Sistema';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageCatalan => 'Català';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get appearanceColorSection => 'Color';

  @override
  String get appearanceColorGroup => 'Color de la app';

  @override
  String get appearanceThemeSection => 'Tema';

  @override
  String get appearanceThemeGroup => 'Tema claro u oscuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get appearanceOccasionTitle =>
      'Temas de ocasión (Navidad, cumpleaños)';

  @override
  String get appearanceOccasionHint =>
      'El color y la cabecera de la lista cambian según la ocasión.';

  @override
  String get appearanceHapticsTitle => 'Vibraciones';

  @override
  String get appearanceHapticsHint =>
      'Desactiva esta opción para apagar todas las vibraciones de la app, incluidas las que notas al marcar una casilla, eliminar un regalo o introducir un PIN incorrecto.';

  @override
  String get appearancePreview => 'Vista previa';

  @override
  String get accentLavender => 'Lavanda';

  @override
  String get accentSage => 'Salvia';

  @override
  String get accentPeach => 'Melocotón';

  @override
  String get accentSky => 'Cielo';

  @override
  String get accentRose => 'Rosa';

  @override
  String get accentButter => 'Mantequilla';

  @override
  String get statusIdea => 'Idea';

  @override
  String get statusDecided => 'Decidido';

  @override
  String get statusBought => 'Comprado';

  @override
  String get statusArrived => 'Llegó';

  @override
  String get statusWrapped => 'Envuelto';

  @override
  String get statusDelivered => 'Entregado';

  @override
  String statusCheckboxLabel(String item, String status) {
    return 'Cambiar estado de $item. Estado actual: $status';
  }

  @override
  String statusReadOnlyLabel(String status) {
    return 'Estado: $status';
  }

  @override
  String get giverUnassigned => 'Sin asignar';

  @override
  String countdownDaysFor(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días para $name',
      one: 'día para $name',
    );
    return '$_temp0';
  }

  @override
  String todayIs(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hoy es $dateString';
  }

  @override
  String get previewGiftName => 'Estación de bomberos de bloques';

  @override
  String get previewGiver => 'Nosotros';

  @override
  String get previewOccasion => 'Reyes';

  @override
  String get shareEnvelopeText =>
      'Abre el fichero con Gift Huddle para ver los cambios en la lista.';

  @override
  String get occasionNameTio => 'Tió';

  @override
  String get occasionNameSanta => 'Navidad';

  @override
  String get occasionNameKings => 'Reyes';

  @override
  String occasionBirthdayOf(String name) {
    return 'Cumpleaños de $name';
  }

  @override
  String get shareErrorNotEnvelope =>
      'Este fichero o texto no es un envío de Gift Huddle.';

  @override
  String get shareErrorWrongList =>
      'Este envío es de otra familia. Conecta los móviles con el código QR.';

  @override
  String get shareErrorAuth =>
      'No se puede abrir este envío. Puede estar dañado o ser de otra familia.';

  @override
  String get shareErrorTooLarge => 'Este envío es demasiado grande.';

  @override
  String get shareErrorNoFamily =>
      'Primero crea tu familia o únete a una con el código QR.';

  @override
  String get shareErrorClockDrift =>
      'El reloj del otro móvil va adelantado. Revisa la fecha y la hora en ese móvil y vuelve a enviar la lista desde él.';

  @override
  String get shareErrorLegacyFile =>
      'Este fichero es de una versión anterior de Gift Huddle. Guárdalo y pide que te envíen uno nuevo creado con la app actualizada.';

  @override
  String get shareErrorNotReady =>
      'Este móvil todavía no está al día con la familia. Sincroniza e inténtalo de nuevo.';

  @override
  String get shareErrorGeneration =>
      'Este fichero es de una versión anterior de la lista. Pide que te envíen uno nuevo.';

  @override
  String get shareErrorRevokedWriter =>
      'Este fichero lo guardó un móvil que ya no es de la familia. No se ha añadido nada.';

  @override
  String get shareErrorMissingKey =>
      'Todavía no se puede abrir este fichero. Se ha guardado y se volverá a intentar cuando sincronices.';

  @override
  String get shareErrorSyncAndReopen =>
      'Todavía no se puede abrir este fichero. Sincroniza y vuelve a abrirlo.';

  @override
  String get shareErrorNotAllowed =>
      'Este móvil aún no puede guardar copias. Otro móvil de la familia tiene que aprobarlo primero.';

  @override
  String get pairErrorInvalidCode => 'Este código QR no es de Gift Huddle.';

  @override
  String get lockEnterPin => 'Introduce tu PIN';

  @override
  String lockPinProgress(int count, int total) {
    return 'PIN: $count de $total dígitos';
  }

  @override
  String get lockUnlock => 'Desbloquear';

  @override
  String get lockBackspace => 'Borrar';

  @override
  String get lockBiometric => 'Usar huella o rostro';

  @override
  String get lockBiometricReason => 'Desbloquea Gift Huddle';

  @override
  String get lockBiometricNotice =>
      'Cualquier huella o cara registrada en el móvil podrá abrir la app.';

  @override
  String lockBiometricNamed(String name) {
    return 'Usar $name';
  }

  @override
  String lockBiometricHintNamed(String name) {
    return 'Toca el botón de $name para desbloquear la app';
  }

  @override
  String get lockBiometricNoticeFace =>
      'Cualquier persona que tenga la cara registrada en Face ID podrá abrir la app.';

  @override
  String get lockBiometricNoticeTouch =>
      'Cualquier persona que tenga una huella registrada en Touch ID podrá abrir la app.';

  @override
  String pinBiometricOfferTitleNamed(String name) {
    return '¿Activar $name?';
  }

  @override
  String get securityBiometricsUnavailableIos =>
      'Este móvil no tiene Face ID ni Touch ID configurados.';

  @override
  String securityBiometricsFailedNamed(String name) {
    return 'No se ha podido activar. Comprueba que $name esté configurado en los Ajustes del móvil.';
  }

  @override
  String get giftDiscardTitle => '¿Descartar los cambios?';

  @override
  String get giftDiscardBody =>
      'Los cambios de este regalo todavía no se han guardado.';

  @override
  String get actionDiscard => 'Descartar';

  @override
  String get giftKeepEditing => 'Seguir editando';

  @override
  String get lockLoadError => 'No se ha podido comprobar el bloqueo.';

  @override
  String get lockRetry => 'Reintentar';

  @override
  String lockWrongPin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Quedan $count intentos',
      one: 'Queda $count intento',
    );
    return 'PIN incorrecto. $_temp0 antes de tener que esperar.';
  }

  @override
  String get lockWrongPinNow => 'PIN incorrecto.';

  @override
  String lockWait(String time) {
    return 'Demasiados intentos. Inténtalo de nuevo en $time.';
  }

  @override
  String get pinSetupTitle => 'Crea un PIN';

  @override
  String get pinSetupMessage =>
      'De 4 a 6 dígitos. Protege tu lista en este móvil.';

  @override
  String get pinConfirmTitle => 'Repite el PIN';

  @override
  String get pinMismatch => 'Los PIN no coinciden. Inténtalo de nuevo.';

  @override
  String get pinContinue => 'Continuar';

  @override
  String get pinSave => 'Guardar PIN';

  @override
  String get pinSkip => 'Ahora no';

  @override
  String get pinBiometricOfferTitle => '¿Activar huella o rostro?';

  @override
  String get pinBiometricOfferEnable => 'Activar';

  @override
  String get actionSave => 'Guardar';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionDelete => 'Borrar';

  @override
  String get actionNext => 'Siguiente';

  @override
  String get actionBack => 'Atrás';

  @override
  String get actionEdit => 'Editar';

  @override
  String get actionClose => 'Cerrar';

  @override
  String get actionDone => 'Hecho';

  @override
  String get actionArchive => 'Archivar';

  @override
  String get actionRestore => 'Recuperar';

  @override
  String get actionUndo => 'Deshacer';

  @override
  String get fieldName => 'Nombre';

  @override
  String get fieldNameRequired => 'Escribe un nombre.';

  @override
  String get fieldFor => 'Para quién';

  @override
  String get fieldGiver => 'Quién regala';

  @override
  String get fieldOccasion => 'Ocasión';

  @override
  String get fieldStatus => 'Estado';

  @override
  String giftCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regalos',
      one: '$count regalo',
      zero: 'Sin regalos',
    );
    return '$_temp0';
  }

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count años',
      one: '$count año',
    );
    return '$_temp0';
  }

  @override
  String get deviceNameDefault => 'Mi móvil';

  @override
  String get giverUs => 'Nosotros';

  @override
  String get giverHouseholdPays => 'Paga la casa';

  @override
  String get giverHouseholdPaysHint =>
      'Si lo activas, sus regalos cuentan en el presupuesto de la casa.';

  @override
  String countdownDaysForBirthday(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días para el cumpleaños de $name',
      one: 'día para el cumpleaños de $name',
    );
    return '$_temp0';
  }

  @override
  String onboardingStepOf(int step, int total) {
    return 'Paso $step de $total';
  }

  @override
  String get obWelcomeTitle => 'Te damos la bienvenida a Gift Huddle';

  @override
  String get obWelcomeBody =>
      'Apunta quién regala qué y a quién. Así nadie repite regalo y nadie se queda sin el suyo.';

  @override
  String get obWelcomePrivacy =>
      'Sin cuentas. Si sincronizáis dos móviles, la lista viaja cifrada y solo vuestros móviles pueden leerla.';

  @override
  String get obDeviceNameLabel => 'Nombre de este móvil';

  @override
  String get obDeviceNameHint =>
      'Este nombre aparecerá en el otro móvil. Puedes cambiarlo.';

  @override
  String get obStart => 'Empezar';

  @override
  String get obHaveListTitle => '¿Ya tenéis una lista?';

  @override
  String get obPeopleTitle => '¿A quién le regaláis?';

  @override
  String get obPeopleBody =>
      'Añade a las personas a las que regaláis: pareja, hermanos, sobrinos, niños… Hace falta al menos una.';

  @override
  String get obPeopleAdd => 'Añadir persona';

  @override
  String get obPeopleNeedOne => 'Añade al menos una persona para seguir.';

  @override
  String obRemove(String name) {
    return 'Quitar $name';
  }

  @override
  String get obGiversTitle => '¿Quién regala?';

  @override
  String get obGiversBody =>
      '«Nosotros» ya está en la lista para los regalos que pagáis en casa. También puedes añadir a los abuelos, los tíos…';

  @override
  String get obGiversSuggestions => 'Sugerencias';

  @override
  String get obGiverGrandparents => 'Abuelos';

  @override
  String get obGiverUncles => 'Tíos';

  @override
  String get obGiverFriends => 'Amigos';

  @override
  String obAddNamed(String name) {
    return 'Añadir $name';
  }

  @override
  String get giverNew => 'Añadir quién regala';

  @override
  String get giverEdit => 'Editar quién regala';

  @override
  String get giverNameHint => 'Abuelos, Tía Nora y Leo…';

  @override
  String get obOccasionsTitle => '¿Cuándo hay regalos?';

  @override
  String get obOccasionsBody =>
      'Elige cuándo hacéis regalos. Si indicas la fecha de nacimiento de alguien, aparecerá su cumpleaños.';

  @override
  String get obBirthdaysSection => 'Cumpleaños (se crean solos)';

  @override
  String get obNoBirthdays =>
      'Si añades la fecha de nacimiento de alguien, su cumpleaños aparecerá aquí.';

  @override
  String get obOtherOccasions => 'Otras fechas';

  @override
  String get obAddOccasion => 'Añadir otra fecha';

  @override
  String get obPinTitle => 'Bloquea la app';

  @override
  String get obPinBody =>
      'Crea un PIN para que nadie vea los regalos si coge el móvil. Podrás cambiarlo en Ajustes.';

  @override
  String get obPinCreate => 'Crear PIN';

  @override
  String get obFinishing => 'Preparando tu lista…';

  @override
  String get obSaveError => 'No se ha podido guardar. Inténtalo de nuevo.';

  @override
  String get personNew => 'Nueva persona';

  @override
  String get personEdit => 'Editar persona';

  @override
  String get personColor => 'Color';

  @override
  String get personRelation => 'Relación (opcional)';

  @override
  String get personRelationHint => 'Pareja, hermano, sobrina…';

  @override
  String get personBirthday => 'Cumpleaños (opcional)';

  @override
  String get personBirthdayPick => 'Elegir fecha';

  @override
  String get personBirthdayNone => 'Sin fecha';

  @override
  String get personBirthdayClear => 'Quitar fecha';

  @override
  String get personBirthdayNoYear => 'No guardar el año';

  @override
  String personPendingBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'faltan $count por comprar',
      one: 'falta $count por comprar',
    );
    return '$_temp0';
  }

  @override
  String get personAllBought => 'todo comprado';

  @override
  String get giftAdd => 'Añadir regalo';

  @override
  String get giftNoOccasion => 'Sin ocasión';

  @override
  String giftsEmptyTitle(String name) {
    return 'Aún no hay regalos para $name';
  }

  @override
  String get giftsEmptyMessage =>
      'Apunta una idea, aunque todavía no sepas qué comprar.';

  @override
  String get giftTagSurprise => 'Sorpresa';

  @override
  String get giftTagRequest => 'Encargo';

  @override
  String giftRequestedBy(String name) {
    return 'Lo pidió $name';
  }

  @override
  String giftSizeLine(String size) {
    return 'Talla o edad: $size';
  }

  @override
  String giftPriceActualPlanned(String actual, String planned) {
    return '$actual (previsto $planned)';
  }

  @override
  String giftStatusChanged(String item, String status) {
    return '$item: $status';
  }

  @override
  String giftStatusPickerTitle(String item) {
    return 'Estado de $item';
  }

  @override
  String get budgetOf => 'de';

  @override
  String budgetHouseFor(String name) {
    return 'La casa · $name';
  }

  @override
  String get budgetHouseTotal => 'La casa · total';

  @override
  String budgetBarLabel(String spent, String planned) {
    return 'Gastado: $spent de $planned';
  }

  @override
  String get filtersButton => 'Filtros';

  @override
  String get filtersSheetTitle => 'Filtrar regalos';

  @override
  String get filterAnyOccasion => 'Todas';

  @override
  String get filterAnyGiver => 'Todos';

  @override
  String get filterAnyStatus => 'Todos';

  @override
  String get filterNeedsBuy => 'Falta comprar';

  @override
  String get filterNeedsWrap => 'Falta envolver';

  @override
  String filterRemove(String name) {
    return 'Quitar filtro $name';
  }

  @override
  String get filterClear => 'Quitar filtros';

  @override
  String get filterNoResults => 'Ningún regalo coincide con los filtros.';

  @override
  String get giftEditorNewTitle => 'Nuevo regalo';

  @override
  String get giftEditorEditTitle => 'Editar regalo';

  @override
  String get giftEditorNoPeople =>
      'Añade primero a la persona que recibirá el regalo.';

  @override
  String get giftRecipientRequired => 'Elige para quién es el regalo.';

  @override
  String giftAddedNotice(String name) {
    return 'Regalo añadido a la lista de $name';
  }

  @override
  String get giftAddedView => 'Ver';

  @override
  String get giftFieldTitle => 'Regalo';

  @override
  String get giftFieldTitleHint => 'Pijama de astronautas, talla 8';

  @override
  String get giftFieldTitleRequired => 'Escribe qué regalo es.';

  @override
  String get giftPriceSection => 'Precio';

  @override
  String get giftFieldPlanned => 'Previsto';

  @override
  String get giftFieldActual => 'Real';

  @override
  String get giftPriceInvalid => 'Escribe un importe, por ejemplo 12,50.';

  @override
  String get giftFieldStore => 'Tienda';

  @override
  String get giftFieldUrl => 'Enlace';

  @override
  String get giftLinkOpen => 'Abrir enlace';

  @override
  String get giftLinkCopied =>
      'No se ha podido abrir el navegador. Enlace copiado.';

  @override
  String get giftFieldNote => 'Nota';

  @override
  String get giftFieldSize => 'Talla o edad';

  @override
  String get giftRequestSwitch => 'Es un encargo: lo pidió alguien';

  @override
  String get giftRequestedByField => 'Quién lo pidió';

  @override
  String get giftRequestedByOther => 'Otra persona…';

  @override
  String get giftRequestedByName => 'Nombre de quien lo pidió';

  @override
  String get giftRequestNote => 'Nota del encargo';

  @override
  String get giftSurpriseSwitch => 'Es una sorpresa';

  @override
  String get giftSurpriseHint =>
      'Se marca para que nadie lo cuente delante de quien lo recibe.';

  @override
  String get giftDelete => 'Eliminar regalo';

  @override
  String confirmDeleteTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get confirmDeleteBody =>
      'Se elimina también en los móviles de tu familia.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done de $total comprados';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Todo comprado para $occasion';
  }

  @override
  String get giftSaveError =>
      'No se ha podido guardar el regalo. Inténtalo de nuevo.';

  @override
  String get giftDuplicateTitle => 'Posible duplicado';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return 'Puede que este regalo ya esté en la lista de $person como «$title». Quién regala: $giver.';
  }

  @override
  String get giftDuplicateSave => 'Guardar igualmente';

  @override
  String get giftDuplicateReview => 'Revisar';

  @override
  String get familySubtitle => 'Quién regala qué a cada persona';

  @override
  String get familyGiverHeader => 'Regala';

  @override
  String get familyNoPrice => 'Sin precio';

  @override
  String get familyNothingYet => 'Nada aún';

  @override
  String get familyLegendAllBought => 'Todo comprado';

  @override
  String get familyLegendPending => 'Algo pendiente';

  @override
  String get familyLegendDuplicate => 'Posible duplicado';

  @override
  String familyCellLabel(
    String giver,
    String person,
    String gifts,
    String price,
    String state,
  ) {
    return '$giver para $person: $gifts, $price, $state';
  }

  @override
  String familyCellEmptyLabel(String giver, String person) {
    return '$giver para $person: nada todavía, añadir regalo';
  }

  @override
  String familyDuplicateBanner(String person, String title) {
    return 'Posible duplicado: «$title» para $person';
  }

  @override
  String familyDuplicateMore(int count) {
    return 'y $count más';
  }

  @override
  String get occasionNew => 'Nueva ocasión';

  @override
  String get occasionEdit => 'Editar ocasión';

  @override
  String get occasionNameHint => 'Comunión, fin de curso…';

  @override
  String get occasionDate => 'Fecha';

  @override
  String get occasionDatePick => 'Elegir fecha';

  @override
  String get occasionDateRequired => 'Elige una fecha.';

  @override
  String get occasionRepeats => 'Se repite cada año';

  @override
  String get occasionBirthdayDateHint =>
      'La fecha sale del cumpleaños de la persona.';

  @override
  String occasionDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Faltan $count días',
      one: 'Falta $count día',
      zero: 'Hoy',
    );
    return '$_temp0';
  }

  @override
  String get occasionPassed => 'Ya pasó';

  @override
  String get budgetCardTitle => 'Presupuesto de la casa';

  @override
  String get budgetCardHint => 'Presupuesto, gastado y lo que queda';

  @override
  String get occasionPeopleSection => 'Por persona';

  @override
  String get occasionToWrap => 'por envolver';

  @override
  String get occasionToArrive => 'por llegar';

  @override
  String get occasionNoGifts => 'Todavía no hay regalos para esta ocasión.';

  @override
  String get occasionNoGiftsYet => 'Sin regalos todavía';

  @override
  String occasionSplitLabel(String name, String parts) {
    return 'Regalos para $name por ocasión: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Pendiente de comprar';

  @override
  String get occasionPendingEmpty =>
      'No hay compras pendientes. Aquí aparecen los regalos con el estado «Decidido», agrupados por tienda.';

  @override
  String get occasionStoreNone => 'Sin tienda';

  @override
  String occasionMarkBought(String item) {
    return 'Marcar como comprado: $item';
  }

  @override
  String get occasionIdeasSection => 'Ideas';

  @override
  String get budgetTitle => 'Presupuesto';

  @override
  String get budgetSubtitle =>
      'Puedes poner un presupuesto en cada ocasión. «Gastado» suma los precios reales de los regalos que paga la casa. Si ya se ha comprado un regalo y falta el precio real, cuenta el previsto.';

  @override
  String get budgetSubtitleBudgeted =>
      'Puedes poner un presupuesto en cada ocasión. Las tres cifras solo incluyen ocasiones con presupuesto. «Gastado» suma los precios reales de los regalos que paga la casa. Si ya se ha comprado un regalo y falta el precio real, cuenta el previsto.';

  @override
  String get budgetPlanned => 'Previsto';

  @override
  String get budgetSpent => 'Gastado';

  @override
  String get budgetLeft => 'Disponible';

  @override
  String get budgetOver => 'Te pasas';

  @override
  String get budgetByPerson => 'Por persona';

  @override
  String get budgetByOccasion => 'Por ocasión';

  @override
  String get budgetNote =>
      'Solo suma lo que paga la casa. Los regalos que pagan otras personas, como los abuelos, quedan fuera del gasto de la casa.';

  @override
  String get budgetEmpty =>
      'Todavía no hay regalos que pague la casa. Activa «Paga la casa» en la ficha de quien regala y añade el precio previsto al regalo.';

  @override
  String get occasionBudgetField => 'Presupuesto (opcional)';

  @override
  String get occasionBudgetHint =>
      'Lo que quieres gastar en esta ocasión. Déjalo vacío si no hay presupuesto.';

  @override
  String get budgetFigure => 'Presupuesto';

  @override
  String get budgetNone => 'Sin presupuesto';

  @override
  String get budgetSetAction => 'Poner presupuesto';

  @override
  String get budgetEditAction => 'Cambiar presupuesto';

  @override
  String budgetSetFor(String name) {
    return 'Poner presupuesto a $name';
  }

  @override
  String budgetEditFor(String name) {
    return 'Cambiar el presupuesto de $name';
  }

  @override
  String budgetLeftIfBought(String amount) {
    return 'Si compras lo que falta, te quedarás con $amount';
  }

  @override
  String budgetSpentOutside(String amount) {
    return 'Además, la casa ha gastado $amount fuera de las ocasiones con presupuesto.';
  }

  @override
  String budgetOverIfBought(String amount) {
    return 'Si compras lo que falta, te pasarás $amount';
  }

  @override
  String budgetSheetTitle(String name) {
    return 'Presupuesto de $name';
  }

  @override
  String get budgetSheetHint => 'Déjalo vacío para quitar el presupuesto.';

  @override
  String get budgetOpenGifts => 'Ver regalos';

  @override
  String get budgetArchivedTag => 'Archivada · no suma';

  @override
  String get budgetCreateOccasion => 'Crear ocasión';

  @override
  String get settingsGivers => 'Quién regala';

  @override
  String get settingsSecurity => 'Bloqueo';

  @override
  String get settingsShare => 'Móviles de la familia';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String aboutVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get aboutPrivacy =>
      'Sin cuentas ni publicidad. La lista solo sale de tu móvil si conectas otro móvil o la web, creas un código de recuperación o envías una copia. Siempre va cifrada.';

  @override
  String get aboutPrivacyPolicy => 'Política de privacidad';

  @override
  String get aboutPrivacyPolicyHint => 'Se abre en el navegador.';

  @override
  String get aboutPrivacyPolicyCopied =>
      'No se ha podido abrir el navegador. Enlace copiado.';

  @override
  String get aboutSupport => 'Ayuda y soporte';

  @override
  String get aboutSupportHint => 'Escríbenos desde tu app de correo.';

  @override
  String aboutSupportCopied(String email) {
    return 'No se ha podido abrir el correo. Dirección copiada: $email';
  }

  @override
  String get manageArchiveHint =>
      'Archivar quita algo de las listas sin eliminar sus regalos; se recupera en Ajustes › Archivo. Eliminar lo borra para siempre.';

  @override
  String manageArchiveLabel(String name) {
    return 'Archivar $name';
  }

  @override
  String manageRestoreLabel(String name) {
    return 'Recuperar $name';
  }

  @override
  String get securityPinTitle => 'Bloqueo con PIN';

  @override
  String get securityPinHint => 'Pide el PIN al abrir la app.';

  @override
  String get securityChangePin => 'Cambiar PIN';

  @override
  String get securityBiometrics => 'Huella o rostro';

  @override
  String get securityBiometricsHint => 'Abre la app sin teclear el PIN.';

  @override
  String get securityBiometricsUnavailable =>
      'Este móvil no tiene huella ni rostro configurados.';

  @override
  String get securityBiometricsFailed =>
      'No se ha podido activar. Comprueba que la huella o el rostro estén configurados en el móvil.';

  @override
  String get securityDisableTitle => 'Quitar el PIN';

  @override
  String get securityDisablePrompt => 'Escribe tu PIN para quitar el bloqueo.';

  @override
  String get securityChangeCurrentPrompt => 'Escribe tu PIN actual.';

  @override
  String get securityPinEnabled => 'PIN activado.';

  @override
  String get securityPinDisabled => 'Bloqueo desactivado.';

  @override
  String get securityPinChanged => 'PIN cambiado.';

  @override
  String get securityNote =>
      'Sin PIN, cualquiera que coja el móvil puede ver los regalos.';

  @override
  String get shareJoinTitle => 'Escanear el QR';

  @override
  String get sharePasteEmpty =>
      'No hay nada que pegar. Copia antes el enlace o el texto que te enviaron.';

  @override
  String get shareSendError => 'No se ha podido preparar el envío.';

  @override
  String get showQrIntro =>
      'En el otro móvil abre Gift Huddle, toca «Unirme a una familia», luego «Escanear el QR» y apunta la cámara a este código.';

  @override
  String get showQrWarning =>
      'No hagas capturas de pantalla ni lo compartas: este código da acceso a toda la lista. Enséñalo solo en persona.';

  @override
  String get showQrLabel => 'Código QR para conectar otro móvil';

  @override
  String get joinIntro => 'Apunta la cámara al código QR del otro móvil.';

  @override
  String get scannerWaitingPermission => 'Esperando el permiso de la cámara…';

  @override
  String get scannerDeniedTitle => 'Hace falta la cámara';

  @override
  String get scannerDeniedBody =>
      'Solo se usa para leer el código QR; no se guarda ninguna imagen.';

  @override
  String get scannerBlockedTitle => 'La cámara está bloqueada';

  @override
  String get scannerBlockedBody =>
      'El permiso de cámara está denegado. Actívalo en los ajustes del móvil para leer el código QR.';

  @override
  String get scannerFailedTitle => 'No se ha podido abrir la cámara';

  @override
  String get scannerFailedBody =>
      'El móvil no ha contestado a la petición del permiso. Inténtalo de nuevo.';

  @override
  String get scannerRetry => 'Reintentar';

  @override
  String get scannerOpenSettings => 'Abrir ajustes';

  @override
  String get joinConflictTitle => 'Este móvil ya tiene una lista';

  @override
  String get joinConflictBody =>
      'Si te unes a la lista del otro móvil, perderás la lista de este móvil y los regalos que contiene.';

  @override
  String get joinReplace => 'Sustituir y unirme';

  @override
  String get joinDoneTitle => 'Móviles conectados';

  @override
  String joinDoneBody(String name) {
    return 'Ya estás en la familia de $name. Pídele que te envíe los cambios para ver la lista.';
  }

  @override
  String get incomingTitle => 'Cambios recibidos';

  @override
  String get incomingNothing => 'Ya lo tenías todo al día.';

  @override
  String get incomingOtherChanges => 'Se han actualizado personas u ocasiones.';

  @override
  String get incomingFailedTitle => 'No se ha podido abrir el envío';

  @override
  String importAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regalos nuevos',
      one: '$count regalo nuevo',
    );
    return '$_temp0';
  }

  @override
  String importChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regalos modificados',
      one: '$count regalo modificado',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regalos eliminados',
      one: '$count regalo eliminado',
    );
    return '$_temp0';
  }

  @override
  String get syncNowTitle => 'Sincronizar ahora';

  @override
  String get syncStopTitle => 'Dejar de sincronizar';

  @override
  String get syncStopHint => 'Este móvil deja de enviar y recibir cambios.';

  @override
  String get syncStopConfirmTitle => '¿Dejar de sincronizar?';

  @override
  String get syncStopConfirmBody =>
      'Este móvil dejará de enviar y recibir cambios. Los demás seguirán sincronizándose entre sí. Si ningún otro móvil ni la web tienen acceso a la lista, se borrará la copia cifrada para sincronizar. Cada móvil conservará sus datos. Para volver a sincronizar, conecta de nuevo este móvil con otro de la familia.';

  @override
  String get syncStopDone => 'Sincronización apagada.';

  @override
  String get syncStopError =>
      'No se ha podido contactar con el servidor. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get syncPrivacyNote =>
      'El servidor guarda la lista cifrada con una clave que solo tienen vuestros móviles. No ve nombres, regalos ni precios, pero sí cuándo y desde qué IP se conecta cada móvil.';

  @override
  String get syncStatusNotConfigured =>
      'La sincronización no está disponible en esta versión.';

  @override
  String get syncStatusNoFamily =>
      'Crea tu familia o únete a una para sincronizar.';

  @override
  String get syncStatusDisabled => 'Apagada';

  @override
  String get syncStatusIdle => 'Pendiente de sincronizar';

  @override
  String get syncStatusWaitingPeer =>
      'La sincronización empezará cuando conectes otro móvil.';

  @override
  String get peerConnected => 'Se ha conectado otro móvil';

  @override
  String peerConnectedNamed(String name) {
    return 'Se ha conectado otro móvil: $name';
  }

  @override
  String get syncStatusSyncing => 'Sincronizando…';

  @override
  String get syncStatusSyncedNow => 'Sincronizado ahora';

  @override
  String syncStatusSyncedMinutes(int minutes) {
    return 'Sincronizado hace $minutes min';
  }

  @override
  String syncStatusSyncedHours(int hours) {
    return 'Sincronizado hace $hours h';
  }

  @override
  String syncStatusSyncedDays(int days) {
    return 'Sincronizado hace $days d';
  }

  @override
  String get syncStatusOffline => 'Sin conexión, los cambios se enviarán luego';

  @override
  String get syncStatusError => 'No se ha podido sincronizar';

  @override
  String get syncIssueAuth => 'El servidor no acepta la clave de esta familia.';

  @override
  String get syncIssueClockDrift =>
      'El reloj de otro móvil va adelantado. Revisa la fecha y la hora en ese móvil.';

  @override
  String get syncIssueTooLarge =>
      'La lista es demasiado grande para sincronizar.';

  @override
  String get syncIssueServer =>
      'El servidor no responde bien. Se volverá a intentar.';

  @override
  String get syncIssueRateLimited =>
      'Demasiadas peticiones seguidas. Se volverá a intentar en un momento.';

  @override
  String get syncIssueUnreadable =>
      'Los datos del servidor no se pueden abrir con la clave de esta familia.';

  @override
  String get syncIssueUnknown => 'Algo ha fallado. Se volverá a intentar.';

  @override
  String get inviteRowTitle => 'Invitar a alguien';

  @override
  String get joinInviteRowTitle => 'Unirme con un enlace';

  @override
  String get inviteIntro =>
      'Crea un enlace para que otra persona se una a tu familia desde su móvil, sin estar delante.';

  @override
  String get inviteHowItWorks =>
      'El enlace no contiene ninguna clave. Sirve para una sola persona y caduca a las 24 horas. Cuando esa persona pida entrar, recibirás su petición con un código de 6 cifras. Tú decides si le das acceso.';

  @override
  String get inviteCreate => 'Crear enlace e invitar';

  @override
  String get inviteNeedSync =>
      'Para invitar a distancia, hace falta conexión a internet y tener la sincronización encendida.';

  @override
  String get inviteGoToSync => 'Encender la sincronización';

  @override
  String inviteShareText(String link) {
    return 'Te invito a mi lista de Gift Huddle. Abre el enlace y pide entrar: $link';
  }

  @override
  String get inviteWaitingTitle => 'Esperando la petición';

  @override
  String get inviteWaitingBody =>
      'Cuando la otra persona pida entrar, verás su petición aquí. Puedes salir de esta pantalla. La invitación seguirá activa hasta que caduque.';

  @override
  String inviteExpires(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'Caduca el $dateString a las $timeString';
  }

  @override
  String get inviteShareAgain => 'Compartir el enlace otra vez';

  @override
  String get inviteCancel => 'Cancelar invitación';

  @override
  String inviteRequestTitle(String name) {
    return '$name quiere unirse';
  }

  @override
  String get inviteRequestBody =>
      'Si no esperabas esta petición, recházala. Si los dos códigos no coinciden, no des acceso.';

  @override
  String get inviteCodeLabel => 'Código de verificación';

  @override
  String get inviteAccept => 'Los códigos coinciden, dar acceso';

  @override
  String get inviteReject => 'Rechazar';

  @override
  String get inviteApprovedTitle => 'Invitación aceptada';

  @override
  String inviteApprovedBody(String name) {
    return '$name ya puede entrar: su móvil está recogiendo la clave.';
  }

  @override
  String get inviteRejectedBody =>
      'La invitación se ha cancelado. El enlace ya no sirve.';

  @override
  String get inviteExpiredBody => 'La invitación ha caducado.';

  @override
  String get inviteNew => 'Invitar a otra persona';

  @override
  String get inviteErrorNetwork =>
      'No se ha podido conectar con el servidor. Inténtalo de nuevo.';

  @override
  String get inviteErrorUnknown =>
      'No se ha podido completar la invitación. Inténtalo de nuevo.';

  @override
  String get joinInviteIntro =>
      'Pega el enlace que te enviaron. Quien te invitó tendrá que aceptar tu petición.';

  @override
  String get joinInviteFieldLabel => 'Enlace de invitación';

  @override
  String get joinInvitePaste => 'Pegar';

  @override
  String get joinInviteAsk => 'Pedir entrada';

  @override
  String get joinInviteBadLink =>
      'Este texto no es un enlace de invitación de Gift Huddle.';

  @override
  String get joinInviteUnavailable =>
      'Las invitaciones a distancia no están disponibles en esta versión.';

  @override
  String get joinInviteNetwork =>
      'No se ha podido conectar con el servidor. Comprueba la conexión.';

  @override
  String get joinInviteTampered =>
      'No se ha podido abrir la invitación. Pide un enlace nuevo.';

  @override
  String get joinInviteUnknown =>
      'No se ha podido completar la conexión. Inténtalo de nuevo.';

  @override
  String get joinInviteTaken =>
      'Otra persona ya ha pedido entrar con este enlace. Pide un enlace nuevo.';

  @override
  String get joinInviteGone => 'La invitación ha caducado o no se ha aceptado.';

  @override
  String get joinInviteWaitingTitle => 'Esperando a que te acepten';

  @override
  String get joinInviteWaitingBody =>
      'Quien te invitó tiene que ver tu petición. Cuando su móvil responda, verás aquí un código para comparar. Este móvil espera la confirmación hasta 10 minutos.';

  @override
  String get joinInviteConfirmTitle => 'Compara el código';

  @override
  String get joinInviteConfirmBody =>
      'Pregunta a quien te invitó qué código ve en su móvil. Tiene que ser el mismo que este. Cuando lo confirme en su móvil, entrarás en la familia.';

  @override
  String get joinInviteMismatch => 'No coincide, cancelar';

  @override
  String get joinInviteMismatchBody =>
      'Has cancelado y no has entrado en la familia. Pide a quien te invitó un enlace nuevo.';

  @override
  String joinInviteDoneBody(String name) {
    return 'Ya estás en la familia de $name. La lista llegará en unos segundos.';
  }

  @override
  String get joinInviteRestart => 'Volver a empezar';

  @override
  String get syncIssueFirstUpload =>
      'La lista es demasiado grande para la primera subida.';

  @override
  String get inviteCompareNotice =>
      'Compara este código con el que ve la otra persona.';

  @override
  String get joinInviteWaitingForConfirm =>
      'Esperando a que confirme en su móvil…';

  @override
  String get familyChipAll => 'Todas';

  @override
  String get familyChipBirthdays => 'Cumpleaños';

  @override
  String get familyOccasionPickerLabel => 'Ocasión';

  @override
  String get familyForAll => 'Todas las ocasiones';

  @override
  String familyForOccasion(String name, String date) {
    return 'Para $name, $date';
  }

  @override
  String get familyForBirthdays => 'Para los cumpleaños';

  @override
  String familyCellOccasions(String names) {
    return 'para $names';
  }

  @override
  String peopleCarouselPage(int page, int total) {
    return 'Ocasión $page de $total';
  }

  @override
  String peopleCarouselRange(int first, int last, int total) {
    return 'Ocasiones $first y $last de $total';
  }

  @override
  String get occasionTypeTitle => 'Tipo de ocasión';

  @override
  String get occasionKindChineseNewYear => 'Año Nuevo Chino';

  @override
  String get occasionKindWedding => 'Boda';

  @override
  String get occasionKindAnniversary => 'Aniversario';

  @override
  String get occasionKindSantJordi => 'Sant Jordi';

  @override
  String get occasionKindValentine => 'San Valentín';

  @override
  String get occasionKindBaptism => 'Bautizo o nacimiento';

  @override
  String get occasionKindCommunion => 'Comunión';

  @override
  String get occasionKindGraduation => 'Graduación o fin de curso';

  @override
  String get occasionKindCustom => 'Otra';

  @override
  String get occasionChineseNewYearHint =>
      'La fecha cambia cada año y se calcula sola.';

  @override
  String get occasionCustomColor => 'Color';

  @override
  String get occasionCustomIcon => 'Icono';

  @override
  String get occasionColorTeal => 'Turquesa';

  @override
  String get occasionColorSlate => 'Pizarra';

  @override
  String get occasionIconStar => 'Estrella';

  @override
  String get occasionIconHeart => 'Corazón';

  @override
  String get occasionIconHome => 'Casa';

  @override
  String get occasionIconTrip => 'Viaje';

  @override
  String get occasionIconSchool => 'Escuela';

  @override
  String get occasionIconPets => 'Mascota';

  @override
  String get occasionIconBaby => 'Bebé';

  @override
  String get occasionIconWork => 'Trabajo';

  @override
  String get occasionIconMusic => 'Música';

  @override
  String get occasionIconSport => 'Deporte';

  @override
  String get occasionIconFlower => 'Flor';

  @override
  String get occasionIconParty => 'Fiesta';

  @override
  String get peopleUpcomingTitle => 'Próximas ocasiones';

  @override
  String todayShort(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Hoy, $dateString';
  }

  @override
  String daysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '$_temp0';
  }

  @override
  String occasionGiftsBought(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'regalos comprados',
      one: 'regalo comprado',
    );
    return '$done de $total $_temp0';
  }

  @override
  String get occasionsGroupCelebrations => 'Fiestas';

  @override
  String get occasionsGroupBirthdays => 'Cumpleaños';

  @override
  String get familyTotalRow => 'Total';

  @override
  String get familyRecipientHeader => 'Recibe';

  @override
  String get familyLegendNothing => 'Nada';

  @override
  String get familyLegendToBuy => 'Por comprar';

  @override
  String familyNoGiverCount(int count) {
    return '$count sin asignar';
  }

  @override
  String repartoSheetNobodyYet(String giver, String person) {
    return 'Aún no hay regalos de $giver para $person';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return 'Hay regalos sin asignar para $person. Toca «Sin asignar» en un regalo para elegir quién lo regala.';
  }

  @override
  String get repartoSheetStartHint => 'Apunta un regalo nuevo para empezar.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · toca un nombre para cambiar quién regala';
  }

  @override
  String get repartoSheetWho => 'Sin asignar';

  @override
  String get repartoSheetNobody => 'Nadie';

  @override
  String get repartoSheetAddGift => 'Añadir regalo';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'Añadir regalo de $giver';
  }

  @override
  String repartoSheetOpenList(String person) {
    return 'Ver la lista de $person';
  }

  @override
  String get repartoSheetNoGiver => 'Sin asignar';

  @override
  String repartoSheetChipLabel(String giver) {
    return 'Quién regala: $giver. Cambiar';
  }

  @override
  String repartoSheetLabel(String giver, String person) {
    return 'Regalos de $giver para $person';
  }

  @override
  String get lockBiometricHint => 'Toca el botón de la huella para desbloquear';

  @override
  String get repartoViewLabel => 'Vista de Reparto';

  @override
  String get repartoViewGrid => 'Rejilla';

  @override
  String get repartoViewOccasion => 'Por ocasión';

  @override
  String get repartoOccasionPackets => 'Cuántos paquetes abre cada uno';

  @override
  String repartoOccasionToBuy(int count) {
    return '$count por comprar';
  }

  @override
  String repartoOccasionNothingIn(String occasion) {
    return 'Nada en $occasion';
  }

  @override
  String get repartoOccasionAddShort => 'Añadir';

  @override
  String repartoOccasionEmptyTitle(String occasion) {
    return 'Nada todavía en $occasion';
  }

  @override
  String get repartoOccasionEmptyMessage =>
      'Cuando apuntes un regalo para este día, aquí verás quién lo trae y cuántos paquetes abre cada uno.';

  @override
  String repartoPersonSheetLabel(String person) {
    return 'Ficha de $person';
  }

  @override
  String repartoPersonOpen(String person) {
    return 'Abrir la ficha de $person';
  }

  @override
  String get repartoSelfTag => 'Yo';

  @override
  String repartoSelfName(String name) {
    return '$name (yo)';
  }

  @override
  String get repartoPersonSheetSub =>
      'Cómo sale en Reparto. No se elimina ningún regalo.';

  @override
  String get repartoPersonInReparto => 'Sale en el reparto';

  @override
  String get repartoPersonInRepartoHint =>
      'Si lo quitas, pasa a «Fuera del reparto».';

  @override
  String get repartoPersonOccasions => 'Le regaláis en';

  @override
  String familyOutsideTitle(int count) {
    return 'Fuera del reparto · $count';
  }

  @override
  String get familyOutsideNote => 'No sale en el reparto';

  @override
  String get familyIncludeAgain => 'Volver a incluir';

  @override
  String familyExcludedStrip(String occasion) {
    return 'No le regaláis en $occasion';
  }

  @override
  String familySkipsLabel(String occasions) {
    return 'Sin $occasions';
  }

  @override
  String get familyLegendExcluded => 'No le regaláis';

  @override
  String repartoOccasionNotGiving(String occasion) {
    return 'No les regaláis en $occasion';
  }

  @override
  String get actionEliminate => 'Eliminar';

  @override
  String manageDeleteLabel(String name) {
    return 'Eliminar $name';
  }

  @override
  String get manageLockedThisDevice => 'Es la persona de este móvil.';

  @override
  String get manageLockedOtherDevice =>
      'Es la persona de otro móvil de la familia.';

  @override
  String deletePersonTitle(String name) {
    return '¿Eliminar a $name?';
  }

  @override
  String deleteOccasionTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String deletePersonGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'También se eliminarán los $count regalos que hay para esta persona.',
      one: 'También se eliminará el regalo que hay para esta persona.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo =>
      'Su cumpleaños también se eliminará de la lista de ocasiones.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Sus $count regalos seguirán en la lista sin nadie asignado en «Quién regala».',
      one:
          'Su regalo seguirá en la lista sin nadie asignado en «Quién regala».',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String deleteOccasionGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sus $count regalos se quedarán sin ocasión.',
      one: 'Su regalo se quedará sin ocasión.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteIrreversible =>
      'No se puede deshacer. Se elimina también en los móviles de tu familia.';

  @override
  String get deleteRequestedByToo =>
      'Su nombre dejará de aparecer en los regalos que pidió para otras personas.';

  @override
  String get deleteGiverBudget =>
      'Sus importes dejan de contar en el presupuesto de la casa.';

  @override
  String get deleteError => 'No se ha podido eliminar. Inténtalo de nuevo.';

  @override
  String get giftNotSaved =>
      'No se ha guardado: este regalo ya no está disponible en este móvil.';

  @override
  String giftDeletedNotice(String name) {
    return '«$name» eliminado';
  }

  @override
  String get settingsSectionFamily => 'Familia';

  @override
  String get settingsSectionDevice => 'Este móvil';

  @override
  String get settingsSelf => 'Este móvil es de';

  @override
  String get settingsSelfNobody => 'Nadie';

  @override
  String get settingsSelfSheetTitle => '¿De quién es este móvil?';

  @override
  String get settingsSelfSheetHint =>
      'Solo vale en este móvil; no se comparte.';

  @override
  String get settingsSelfError =>
      'No se ha podido guardar. Inténtalo de nuevo.';

  @override
  String get settingsSectionShare => 'Compartir y copia';

  @override
  String get settingsSectionAbout => 'Acerca de';

  @override
  String get settingsArchive => 'Archivo';

  @override
  String get settingsBackup => 'Copia de seguridad';

  @override
  String get settingsAboutApp => 'Acerca de Gift Huddle';

  @override
  String get eraseAllTitle => 'Borrar todo';

  @override
  String get eraseAllHint => 'La lista, el PIN y los ajustes de este móvil.';

  @override
  String get eraseAllConfirmTitle => '¿Borrar todo?';

  @override
  String get eraseAllConfirmBody =>
      'Se borran de este móvil la lista entera, el PIN y los ajustes, y la app vuelve a empezar de cero. No se puede deshacer. Los demás móviles de tu familia conservan su copia.';

  @override
  String get eraseAllConfirmServer =>
      'Antes, este móvil sale de la sincronización de la familia. Si no queda otro móvil ni la web conectados, también se borra la copia cifrada para sincronizar.';

  @override
  String get eraseAllContinue => 'Continuar';

  @override
  String get eraseAllTypeTitle => 'Último paso';

  @override
  String eraseAllTypeBody(String word) {
    return 'Escribe $word para confirmar que quieres borrarlo todo.';
  }

  @override
  String get eraseAllWord => 'BORRAR';

  @override
  String get eraseAllFieldLabel => 'Confirmación';

  @override
  String get eraseAllWorking => 'Borrando…';

  @override
  String get eraseAllServerFailedTitle =>
      'No se ha podido contactar con el servidor';

  @override
  String get eraseAllServerFailedBody =>
      'Comprueba la conexión e inténtalo de nuevo. Si borras los datos solo aquí, este móvil seguirá en «Móviles de la familia» hasta que alguien lo quite desde otro móvil. Los demás móviles y la web que tengan acceso podrán seguir usando la copia cifrada para sincronizar. Si nadie vuelve a acceder a ella, caducará.';

  @override
  String get eraseAllRetry => 'Reintentar';

  @override
  String get eraseAllLocalOnly => 'Borrar solo en este móvil';

  @override
  String get eraseAllFailed =>
      'No se ha podido borrar todo. Inténtalo de nuevo.';

  @override
  String get eraseAllPinPrompt => 'Escribe tu PIN para continuar.';

  @override
  String get eraseAllBiometricReason => 'Confirma que quieres borrar todo';

  @override
  String get settingsLockOff => 'Sin bloqueo';

  @override
  String get settingsLockPin => 'PIN';

  @override
  String get settingsLockPinBiometrics => 'PIN y biometría';

  @override
  String settingsAppearanceValue(String accent, String theme) {
    return '$accent · $theme';
  }

  @override
  String settingsLanguageSystemNow(String language) {
    return 'Ahora: $language';
  }

  @override
  String get settingsDevicesOnlyThis => 'Solo este';

  @override
  String settingsDevicesValue(int count, String status) {
    return '$count · $status';
  }

  @override
  String get syncShortUpToDate => 'al día';

  @override
  String get syncShortSyncing => 'sincronizando';

  @override
  String get syncShortPending => 'pendiente';

  @override
  String get syncShortOffline => 'sin conexión';

  @override
  String get syncShortError => 'con error';

  @override
  String get syncShortOff => 'apagada';

  @override
  String get archiveSubtitle =>
      'Lo que archivas deja de aparecer en las listas, pero conserva sus regalos.';

  @override
  String get archiveEmpty => 'No hay nada archivado.';

  @override
  String get archiveNote =>
      'Archivar no borra nada. Eliminar sí, y para siempre.';

  @override
  String get devicesSoloTitle => 'Solo en este móvil';

  @override
  String get devicesSoloBody =>
      'Conecta otro para ver la misma lista en los dos.';

  @override
  String get devicesRecoveryTitle => 'Copia de recuperación guardada';

  @override
  String get devicesRecoveryBody =>
      'Con tu código puedes recuperar la lista a partir de la copia cifrada para sincronizar. Conecta otro móvil para ver la lista en los dos.';

  @override
  String get devicesManualTitle => 'Conectados por fichero o QR';

  @override
  String get devicesManualBody =>
      'Sin sincronización automática: envía la lista cuando cambie.';

  @override
  String get devicesUpToDateTitle => 'Todo al día';

  @override
  String devicesUpToDateBody(String status) {
    return '$status. Cifrado de extremo a extremo.';
  }

  @override
  String get devicesEncrypted => 'Cifrado de extremo a extremo.';

  @override
  String get devicesOffTitle => 'Sincronización apagada';

  @override
  String get devicesOffBody => 'Los cambios no salen de este móvil.';

  @override
  String get devicesTurnOn => 'Encender';

  @override
  String get syncTurnedOn => 'Sincronización encendida.';

  @override
  String get devicesOfflineTitle => 'Sin conexión';

  @override
  String get devicesOfflineBody => 'Los cambios se enviarán cuando vuelva.';

  @override
  String get devicesConnected => 'Conectados';

  @override
  String get devicesThisPhone => 'Este móvil';

  @override
  String get devicesOtherPhone => 'Otro móvil';

  @override
  String get devicesPeerHint => 'Conectado a esta familia';

  @override
  String get devicesPeerNoPerson => 'Sin persona: aún no ve las sorpresas';

  @override
  String get devicesListError => 'No se ha podido leer la lista de móviles.';

  @override
  String get devicesConnect => 'Conectar otro móvil';

  @override
  String get devicesConnectQuestion => '¿Dónde está el otro móvil?';

  @override
  String get devicesHereTitle => 'Está aquí';

  @override
  String get devicesHereHint => 'Enséñale un código QR. Es lo más rápido.';

  @override
  String get devicesFarTitle => 'Está lejos';

  @override
  String get devicesFarHint => 'Envíale un enlace. Tú apruebas quién entra.';

  @override
  String get devicesSendNow => 'Enviar la lista ahora';

  @override
  String get devicesSendNowHint =>
      'Con un fichero .gifthuddle, por donde quieras.';

  @override
  String get devicesMore => 'Más opciones';

  @override
  String get devicesMoreHint => 'Unirme a otra familia, dejar de sincronizar';

  @override
  String get devicesJoinOther => 'Unir este móvil a otra familia';

  @override
  String get devicesJoinOtherHint => 'Sustituye la lista de este móvil.';

  @override
  String get devicesJoinOtherWarning =>
      'Si te unes a otra familia, su lista sustituirá a la de este móvil. En este móvil perderás los regalos de la lista actual.';

  @override
  String get devicesScanTitle => 'Escanear su QR';

  @override
  String get devicesScanHint =>
      'El otro móvil lo enseña en «Conectar otro móvil».';

  @override
  String get devicesPasteLinkTitle => 'Pegar un enlace de invitación';

  @override
  String get devicesPasteLinkHint => 'Si te lo enviaron por mensaje.';

  @override
  String get devicesPrivacyTitle => 'Cómo se protege la lista';

  @override
  String get actionUnderstood => 'Entendido';

  @override
  String get backupSubtitle =>
      'Un fichero .gifthuddle cifrado con toda la lista.';

  @override
  String get backupSaveTitle => 'Guardar una copia';

  @override
  String get backupSaveHint =>
      'Un fichero .gifthuddle cifrado, donde tú quieras.';

  @override
  String get backupRestoreTitle => 'Recuperar una copia';

  @override
  String get backupRestoreHint => 'Desde un fichero o desde el portapapeles.';

  @override
  String get backupRestoreSubtitle =>
      'La copia se combina con la lista de este móvil. No se pierde nada.';

  @override
  String get backupPasteTitle => 'Pegar desde el portapapeles';

  @override
  String get backupPasteHint => 'Si te llegó como enlace o como texto.';

  @override
  String get backupFileNote =>
      'Para abrir un fichero .gifthuddle, tócalo en Archivos o en el mensaje donde te llegó y elige Gift Huddle.';

  @override
  String get backupNote =>
      'La copia está cifrada con la clave de la familia. Solo puedes abrirla en un móvil que ya forme parte de esa familia.';

  @override
  String get pairingV2Preparing => 'Preparando la conexión…';

  @override
  String get pairingV2NoticeExpires =>
      'La invitación caduca a las 24 horas y solo sirve para pedir entrada. Antes de dar acceso, compara el código que aparece en los dos móviles.';

  @override
  String get pairingV2FarTitle => 'Comparte el enlace';

  @override
  String get pairingV2FarBody =>
      'Envíaselo a quien quieras conectar. Cuando lo abra y pida entrar, aquí verás un código para compararlo.';

  @override
  String get pairingV2Share => 'Compartir el enlace';

  @override
  String get pairingV2WaitingHere =>
      'Esperando a que la otra persona pida entrar…';

  @override
  String get pairingV2CompareTitle => 'Compara el código';

  @override
  String get pairingV2HostCompareBody =>
      'El otro móvil enseña un código. Tiene que ser el mismo que este. Si es el mismo, toca «Coinciden». Si es distinto, toca «No coinciden».';

  @override
  String get pairingV2Match => 'Coinciden';

  @override
  String get pairingV2NoMatch => 'No coinciden';

  @override
  String get pairingV2NoPersonWarning =>
      'El otro móvil todavía no ha dicho de quién es. Puedes darle acceso igualmente: podrá elegirlo más adelante y, hasta entonces, no abrirá las sorpresas.';

  @override
  String get pairingV2Approving => 'Dando acceso al otro móvil…';

  @override
  String get pairingV2HostDone =>
      'Acceso enviado. El otro móvil tiene que completar la conexión.';

  @override
  String get pairingV2VersionMismatch =>
      'Los dos móviles tienen que tener la última versión de Gift Huddle. Actualiza el que esté desfasado y vuelve a empezar.';

  @override
  String get pairingV2HostCancelled =>
      'La invitación se ha cancelado y ya no sirve. Puedes empezar de nuevo.';

  @override
  String get pairingV2HostFailed =>
      'No se ha podido conectar el otro móvil. Inténtalo de nuevo.';

  @override
  String get pairingV2NotReady =>
      'Para continuar, hace falta conexión a internet y tener la sincronización encendida.';

  @override
  String get pairingV2ChooseTitle => '¿De quién es este móvil?';

  @override
  String get pairingV2ChooseBody =>
      'El que tienes en la mano. Elige a quien lo usa y Gift Huddle sabrá qué sorpresas esconderle.';

  @override
  String pairingV2ChooseBodySelf(String name) {
    return 'Lo tenías marcado como de $name. Confírmalo o elige a otra persona.';
  }

  @override
  String get pairingV2ChooseContinue => 'Continuar';

  @override
  String get pairingV2ChooseLaterTitle => 'Elegir después';

  @override
  String get pairingV2ChooseLaterBody =>
      'Si no eliges ahora, este móvil no abrirá las sorpresas hasta que elijas a la persona y quien te invitó lo apruebe.';

  @override
  String get pairingV2ChooseNone =>
      'Este móvil todavía no conoce a nadie de esta familia, así que de momento no se puede elegir. Podrás hacerlo cuando llegue la lista.';

  @override
  String get pairingV2GuestWaitingCode =>
      'Cuando el otro móvil responda, verás aquí un código para comparar.';

  @override
  String get pairingV2GuestCompareBody =>
      'Compara este código con el que ve la otra persona. Si son iguales, toca «Coinciden».';

  @override
  String get pairingV2GuestWaitingApproval =>
      'Esperando a que el otro móvil dé acceso…';

  @override
  String get pairingV2GuestDoneBody =>
      'Ya estás en la familia. La lista llegará en unos segundos.';

  @override
  String get pairingV2GuestCancelled =>
      'No has entrado en la familia. Pide a quien te invitó que empiece de nuevo.';

  @override
  String get pairingV2ReconnectTitle =>
      'Vuelve a conectar los móviles para la nueva sincronización';

  @override
  String get pairingV2ReconnectBody =>
      'Cada móvil se conecta otra vez con «Conectar otro móvil» y comparando un código.';

  @override
  String pairingV2ClaimTitle(String name) {
    return '¿El otro móvil es de $name?';
  }

  @override
  String get pairingV2ClaimBody =>
      'Confírmalo solo si de verdad es su móvil: con él verá las sorpresas para los demás, nunca las suyas.';

  @override
  String pairingV2ClaimYes(String name) {
    return 'Sí, es de $name';
  }

  @override
  String get pairingV2ClaimNo => 'No es suyo';

  @override
  String get pairingV2MigrateTitle => '¿Pasar a la sincronización nueva?';

  @override
  String get pairingV2MigrateBody =>
      'Si continúas, esta familia pasa a la sincronización nueva, más segura. No se puede deshacer. Los móviles que ya estaban conectados dejan de recibir los cambios de este hasta que los vuelvas a conectar, uno a uno, con «Conectar otro móvil». No se pierde nada.';

  @override
  String get pairingV2MigrateContinue => 'Continuar';

  @override
  String get joinReplacePinPrompt =>
      'Escribe tu PIN para sustituir la lista de este móvil.';

  @override
  String get joinReplaceBiometricReason =>
      'Confirma que quieres sustituir la lista de este móvil';

  @override
  String get devicesPeerPending => 'Espera aprobación';

  @override
  String get devicesPeerFrozen => 'Cambios en pausa: espera aprobación';

  @override
  String get devicesPeerReconfirm => 'Confirma de quién es';

  @override
  String get deviceReviewNoticeTitle => 'Hay móviles por revisar';

  @override
  String deviceReviewNoticeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count móviles esperan que los confirmes.',
      one: 'Un móvil espera que lo confirmes.',
    );
    return '$_temp0';
  }

  @override
  String get deviceReviewOpen => 'Revisar móviles';

  @override
  String deviceReviewProgress(int current, int total) {
    return '$current de $total';
  }

  @override
  String get deviceReviewDoneTitle => 'Todo revisado';

  @override
  String get deviceReviewDoneBody => 'No queda ningún móvil por confirmar.';

  @override
  String get deviceDetailOwner => 'De quién es';

  @override
  String get deviceDetailNoPerson => 'Sin persona';

  @override
  String get deviceDetailStatus => 'Estado';

  @override
  String get deviceStatusActive => 'Conectado';

  @override
  String get deviceStatusNoPerson => 'Conectado, sin persona';

  @override
  String get deviceStatusPending => 'Espera aprobación';

  @override
  String get deviceStatusFrozen => 'Cambios en pausa';

  @override
  String get deviceStatusReconfirm => 'Falta confirmar de quién es';

  @override
  String get deviceDetailSelfNote =>
      'Este es tu móvil. Para dejar de sincronizarlo, usa «Dejar de sincronizar» en «Más opciones».';

  @override
  String get deviceRemoveTitle => 'Quitar este móvil';

  @override
  String get deviceRemoveHint => 'Dejará de recibir los cambios de la lista.';

  @override
  String get deviceRemoveConfirmTitle => '¿Quitar este móvil?';

  @override
  String get deviceRemoveConfirmBody =>
      'Deja de recibir los cambios nuevos al momento. Lo que ya tiene guardado no se le puede borrar. Lo que solo estaba en ese móvil puede perderse. No se puede deshacer.';

  @override
  String get deviceRemoveConfirmAction => 'Quitar móvil';

  @override
  String get deviceRemoveWaitTitle => 'Tu móvil volverá a esperar aprobación';

  @override
  String get deviceRemoveWaitBody =>
      'Solo el móvil que vas a quitar aprobó el cambio de persona en el tuyo. Si lo quitas, no podrás ver las sorpresas en tu móvil hasta que otro móvil de la familia apruebe el cambio.';

  @override
  String get deviceRemoveWaitAction => 'Quitar igualmente';

  @override
  String get deviceRemovedSnack => 'Móvil quitado';

  @override
  String get deviceRemoveError =>
      'No se ha podido quitar el móvil. Inténtalo de nuevo con conexión.';

  @override
  String deviceApproveQuestion(String name) {
    return '¿Este móvil es de $name?';
  }

  @override
  String get deviceApproveQuestionNoPerson => '¿Aprobar este móvil?';

  @override
  String deviceApproveYes(String name) {
    return 'Sí, es de $name';
  }

  @override
  String get deviceApproveYesNoPerson => 'Aprobar este móvil';

  @override
  String get deviceApproveLater => 'Después';

  @override
  String get deviceApproveNewcomer =>
      'Compruébalo en persona antes de aprobarlo: un móvil aprobado recibe la lista de la familia.';

  @override
  String get deviceApprovePersonChanged =>
      'Ha cambiado de persona. Si lo apruebas, podrá aprobar otros móviles de la familia.';

  @override
  String get deviceApproveOrphan =>
      'Hay que confirmar de nuevo de quién es. Si lo apruebas, volverá a ver las sorpresas para los demás.';

  @override
  String get deviceApproveDetached =>
      'Este móvil ya no está conectado a la familia, pero antes confirmó el tuyo. Apruébalo solo si lo reconoces.';

  @override
  String get deviceApproveFrozen =>
      'Sus cambios están en pausa hasta que lo apruebes o lo quites.';

  @override
  String get deviceApprovedSnack => 'Móvil aprobado';

  @override
  String get deviceApproveError =>
      'No se ha podido aprobar el móvil. Inténtalo de nuevo.';

  @override
  String get deviceChangedNotice =>
      'Han cambiado los datos del móvil. Revísalos de nuevo.';

  @override
  String get deviceRemovedPendingSnack =>
      'Móvil quitado. Perderá el acceso en cuanto haya conexión.';

  @override
  String get deviceApproveCanVouch =>
      'Ha cambiado de persona: si lo apruebas, podrá aprobar otros móviles de la familia.';

  @override
  String get webGateConnectTitle => 'Conecta este ordenador';

  @override
  String get webGateConnectIntro =>
      'Solo hay que hacerlo una vez, con tu móvil. Después entrarás con el PIN o la frase que elijas.';

  @override
  String get webGateStepOpenApp => 'Abre Gift Huddle en tu móvil.';

  @override
  String get webGateConnectStep2 =>
      'Ve a Ajustes › Móviles de la familia y toca «Conectar la web».';

  @override
  String get webGateConnectStep3 => 'Escanea este código.';

  @override
  String get webGateConnectWaiting => 'Esperando al móvil…';

  @override
  String get webGateCompareTitle => 'Compara el código';

  @override
  String get webGateCompareLabel => 'Código de verificación';

  @override
  String get webGateCompareBody =>
      'Comprueba que en el móvil sale el mismo código, confírmalo aquí y apruébalo también en el móvil.';

  @override
  String get webGateCompareWaiting =>
      'Esperando a que toques «Coinciden» en el móvil…';

  @override
  String get webGateCompareConfirmed => 'Has confirmado el código aquí';

  @override
  String get webGateFailedTitle => 'No se ha podido conectar';

  @override
  String get webGateFailedExpired =>
      'El código ha caducado. Empieza otra vez para ver uno nuevo.';

  @override
  String get webGateFailedMismatch =>
      'Los códigos no coincidían, así que no se ha conectado nada. Empieza otra vez.';

  @override
  String get webGateFailedRejected =>
      'El móvil ha rechazado la conexión. Si quieres conectar este ordenador, empieza otra vez.';

  @override
  String get webGateFailedNetwork =>
      'No hay conexión con el servidor. Comprueba tu conexión y empieza otra vez.';

  @override
  String get webGateFailedCancelled =>
      'El móvil ha cancelado la conexión o el código ya no sirve. Empieza otra vez y escanea el código nuevo con el móvil.';

  @override
  String get webGateStartAgain => 'Empezar otra vez';

  @override
  String webGateChoosePinTitle(String name) {
    return 'Este ordenador es de $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Elige un PIN o una frase para desbloquear Gift Huddle cada vez que abras la web en este ordenador.';

  @override
  String get webGatePinLabel => 'PIN o frase';

  @override
  String get webGatePinRepeatLabel => 'Repite el PIN o la frase';

  @override
  String get webGatePinShow => 'Mostrar';

  @override
  String get webGatePinHide => 'Ocultar';

  @override
  String get webGatePinRule =>
      '6 cifras o más, o una frase de 8 caracteres o más.';

  @override
  String get webGatePinSameHint => 'Puedes usar el mismo PIN que en tu móvil.';

  @override
  String get webGatePinMismatch => 'No coinciden. Escríbelos otra vez.';

  @override
  String get webGatePinNoRecover =>
      'Si lo olvidas, tendrás que volver a conectar este ordenador desde un móvil.';

  @override
  String get webGateContinue => 'Continuar';

  @override
  String get webGateSaving => 'Guardando…';

  @override
  String get webGateUnlockTitle => 'Desbloquea Gift Huddle';

  @override
  String get webGateUnlockBody =>
      'Escribe el PIN o la frase que elegiste para Gift Huddle en este ordenador.';

  @override
  String get webGateUnlock => 'Desbloquear';

  @override
  String get webGateUnlocking => 'Desbloqueando…';

  @override
  String get webGateWrongPin => 'PIN o frase incorrectos.';

  @override
  String webGateAttemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Te quedan $count intentos.',
      one: 'Te queda $count intento.',
    );
    return '$_temp0';
  }

  @override
  String webGateWait(int seconds) {
    return 'Espera $seconds s para probar otra vez.';
  }

  @override
  String get webGateSuspendedTitle => 'Demasiados intentos';

  @override
  String get webGateSuspendedBody =>
      'Para volver a intentarlo, permítelo antes desde un móvil. No se ha borrado nada.';

  @override
  String get webGateSuspendedStep2 =>
      'Ve a Ajustes › Móviles de la familia y toca «Web».';

  @override
  String get webGateSuspendedStep3 => 'Toca «Permitir más intentos de PIN».';

  @override
  String get webGateRetry => 'Reintentar';

  @override
  String get webGateDisconnectedTitle => 'Este ordenador ya no está conectado';

  @override
  String get webGateDisconnectedBody =>
      'Se ha quitado de la familia desde un móvil o la lista ya no existe.';

  @override
  String webGateDisconnectedUnsent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hay $count cambios sin subir. Están guardados y cifrados en este ordenador.',
      one:
          'Hay $count cambio sin subir. Está guardado y cifrado en este ordenador.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Conectar otra vez';

  @override
  String get webGateErase =>
      'Borrar los datos de Gift Huddle en este ordenador';

  @override
  String get webGateEraseTitle =>
      '¿Borrar los datos de Gift Huddle en este ordenador?';

  @override
  String get webGateEraseBody =>
      'Se borra todo lo que Gift Huddle guarda aquí. No se puede deshacer.';

  @override
  String get webGateEraseBodyUnsent =>
      'Se borra todo lo que Gift Huddle guarda aquí, también los cambios sin subir. No se puede deshacer.';

  @override
  String get webGateDamagedTitle =>
      'Los datos de Gift Huddle en este ordenador están dañados';

  @override
  String get webGateDamagedBody =>
      'No se pueden leer de forma segura. Para seguir, bórralos y vuelve a conectar este ordenador desde un móvil. Perderás los cambios que no se hayan subido.';

  @override
  String get webGateDamagedPhoneHint =>
      'En el móvil, ve a Ajustes › Móviles de la familia y quita la web anterior.';

  @override
  String get webGateOtherTabTitle => 'Gift Huddle está abierto en otra pestaña';

  @override
  String get webGateOtherTabBody =>
      'Solo se puede usar en una pestaña a la vez.';

  @override
  String get webGateUseHere => 'Usar aquí';

  @override
  String get webGateLockedLabel => 'Gift Huddle bloqueado';

  @override
  String get webSettingsTitle => 'Este ordenador';

  @override
  String get webSettingsChangePin => 'Cambiar PIN';

  @override
  String get webSettingsChangePinHint =>
      'El que abre Gift Huddle en este ordenador.';

  @override
  String get webSettingsChangePinTitle => 'Cambiar PIN o frase';

  @override
  String get webSettingsCurrentPin => 'PIN o frase actual';

  @override
  String get webSettingsNewPin => 'Nuevo PIN o frase';

  @override
  String get webSettingsNewPinRepeat => 'Repite el nuevo PIN o la frase';

  @override
  String get webSettingsCurrentWrong =>
      'Comprueba que has escrito bien el PIN o la frase actual.';

  @override
  String get webSettingsChangeFailed =>
      'No se ha podido cambiar. Inténtalo de nuevo.';

  @override
  String get webSettingsPinChanged => 'Se ha cambiado el PIN o la frase.';

  @override
  String get webSettingsLockNow => 'Bloquear ahora';

  @override
  String get webSettingsForget => 'Olvidar este ordenador';

  @override
  String get webSettingsForgetHint =>
      'Saldrá de la familia y se borrarán los datos de Gift Huddle guardados en él.';

  @override
  String get webSettingsForgetTitle => '¿Olvidar este ordenador?';

  @override
  String get webSettingsForgetBody =>
      'Este ordenador saldrá de la familia. Se borrarán los datos de Gift Huddle guardados aquí, incluidos los cambios sin subir. En tus móviles no cambia nada. Para volver a usar Gift Huddle aquí, tendrás que conectar el ordenador de nuevo.';

  @override
  String get webSettingsForgetConfirm => 'Olvidar';

  @override
  String get webSettingsPersistenceDenied =>
      'Si queda poco espacio, el navegador podría borrar los datos que Gift Huddle guarda aquí.';

  @override
  String webSetAsideNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hay $count cambios que no se pueden subir porque son para una persona protegida. Se guardan en este ordenador.',
      one:
          'Hay $count cambio que no se puede subir porque es para una persona protegida. Se guarda en este ordenador.',
    );
    return '$_temp0';
  }

  @override
  String get webGateChoosePinCheck =>
      'Si los códigos no coincidían, no sigas: pulsa «Empezar otra vez».';

  @override
  String get webGateRestartTitle => '¿Empezar otra vez?';

  @override
  String get webGateRestartBody =>
      'Se descartará esta conexión y aparecerá un código QR nuevo. El PIN que hayas escrito no se guardará.';

  @override
  String get webGateRestartConfirm => 'Sí, empezar otra vez';

  @override
  String webFailedAttemptsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ha habido $count intentos fallidos desde la última vez que se desbloqueó Gift Huddle aquí. Si no has sido tú, cambia el PIN.',
      one:
          'Ha habido $count intento fallido desde la última vez que se desbloqueó Gift Huddle aquí. Si no has sido tú, cambia el PIN.',
    );
    return '$_temp0';
  }

  @override
  String devicesWebOf(String name) {
    return 'Web de $name';
  }

  @override
  String get devicesWebTitle => 'Web';

  @override
  String get devicesWebHint => 'Ordenador conectado a esta familia';

  @override
  String get devicesConnectWeb => 'Conectar la web';

  @override
  String get devicesConnectWebHint =>
      'Para apuntar regalos desde el ordenador.';

  @override
  String get connectWebTitle => 'Conectar la web';

  @override
  String get connectWebIntro =>
      'Para apuntar regalos desde el ordenador: abre web.gifthuddle.app y escanea el código que aparece.';

  @override
  String get connectWebScanInvalid =>
      'Ese código no es el de la web de Gift Huddle. Escanea el que aparece en el ordenador.';

  @override
  String get connectWebWhoseTitle => '¿De quién es este ordenador?';

  @override
  String get connectWebWhoseBody =>
      'Elige quién va a usar la lista desde el ordenador.';

  @override
  String get connectWebNoPeople =>
      'Todavía no hay personas. Añade una persona antes de conectar la web.';

  @override
  String get connectWebWaiting => 'Esperando a que el ordenador responda…';

  @override
  String get connectWebCompareBody =>
      'El ordenador enseña un código. Tiene que ser el mismo que este. Si es el mismo, toca «Coinciden». Si es distinto, toca «No coinciden».';

  @override
  String get connectWebApproving => 'Dando acceso al ordenador…';

  @override
  String get connectWebDoneTitle => 'Ordenador conectado';

  @override
  String get connectWebDoneBody =>
      'En el ordenador, elige un PIN para abrir Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'Este código ya no vale. En el ordenador, pulsa «Empezar otra vez». Escanea el código nuevo con el móvil.';

  @override
  String get connectWebScanAgain => 'Escanear otro código';

  @override
  String get connectWebFailed =>
      'No se ha podido conectar el ordenador. Pulsa «Empezar otra vez» en el ordenador. Escanea el código nuevo con el móvil.';

  @override
  String get connectWebCancel => 'Cancelar conexión';

  @override
  String get connectWebCancelled =>
      'Se ha cancelado la conexión y el código ya no sirve. En el ordenador, pulsa «Empezar otra vez».';

  @override
  String get deviceWebResume => 'Permitir más intentos de PIN';

  @override
  String get deviceWebResumeHint =>
      'Si la web ya no acepta el PIN tras demasiados intentos fallidos. No se borra nada.';

  @override
  String get deviceWebResumeTitle => '¿Permitir más intentos de PIN?';

  @override
  String get deviceWebResumeBody =>
      'Este ordenador volverá a aceptar intentos de PIN. Hazlo solo si ha sido su dueño quien se ha equivocado.';

  @override
  String get deviceWebResumeConfirm => 'Permitir';

  @override
  String get deviceWebResumeDone => 'Listo. La web vuelve a aceptar el PIN.';

  @override
  String get deviceWebResumeError =>
      'No se han podido permitir más intentos de PIN. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get deviceRemoveWebTitle => 'Quitar esta web';

  @override
  String get deviceRemoveWebHint =>
      'Este ordenador dejará de recibir los cambios de la lista.';

  @override
  String get deviceRemoveWebConfirmTitle => '¿Quitar esta web?';

  @override
  String get deviceRemoveWebConfirmBody =>
      'Este ordenador dejará de tener acceso y de recibir los cambios nuevos al momento. Lo que ya tiene en pantalla no se le puede borrar. Lo que solo estaba en ese ordenador puede perderse. No se puede deshacer.';

  @override
  String get deviceRemoveWebConfirmAction => 'Quitar web';

  @override
  String get deviceRemovedWebSnack => 'Web quitada';

  @override
  String get deviceRemovedWebPendingSnack =>
      'Web quitada. El ordenador perderá el acceso en cuanto haya conexión.';

  @override
  String get deviceRemoveWebError =>
      'No se ha podido quitar la web. Inténtalo de nuevo con conexión.';

  @override
  String get webSyncSaved => 'Guardado';

  @override
  String get webSyncOffline => 'Sin conexión';

  @override
  String get webSyncAwaitingConfirm =>
      'Pendiente de confirmación desde un móvil';

  @override
  String get webOperationUnavailable =>
      'Esto no se puede hacer desde el ordenador. Hazlo desde un móvil.';

  @override
  String get selfChangeConfirmTitle => '¿Cambiar de quién es este móvil?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'Vas a decir que este móvil es de $name. Esto cambia qué regalos y sorpresas puedes ver en él.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'Vas a dejar este móvil sin una persona asignada. Esto cambia qué regalos y sorpresas puedes ver en él.';

  @override
  String selfChangeEffectHides(String name) {
    return 'Si los regalos para $name están en secreto, no verás ninguno en este móvil.';
  }

  @override
  String get selfChangeEffectNobody =>
      'Este móvil se quedará sin persona asignada y no podrá ver sorpresas mientras siga así.';

  @override
  String get selfChangeEffectWait =>
      'Hasta que se apruebe el cambio desde otro móvil de la familia, en este no verás las sorpresas de nadie.';

  @override
  String get selfChangeEffectReconfirm =>
      'Puede que tengas que volver a confirmar algunos móviles que aprobaste desde este.';

  @override
  String get selfChangeConfirmAction => 'Cambiar de persona';

  @override
  String get selfChangePendingTitle => 'Esperando aprobación de otro móvil';

  @override
  String selfChangePendingBody(String name) {
    return 'Este móvil ya es de $name. Otro móvil de la familia tiene que aprobarlo; mientras tanto, no verás las sorpresas de nadie.';
  }

  @override
  String get selfChangePendingBodyNobody =>
      'Este móvil ya no tiene una persona asignada y espera la aprobación de otro móvil de la familia. Aunque lo aprueben, no podrá ver sorpresas mientras no tenga una persona asignada.';

  @override
  String get selfChangePendingOrphans =>
      'Algunos móviles que habías aprobado esperan que los confirmes otra vez.';

  @override
  String get selfChangeExhaustedTitle =>
      'Este móvil ya no puede cambiar de persona';

  @override
  String get selfChangeExhaustedBody =>
      'Has llegado al límite de cambios de persona en este móvil. Para elegir a otra persona, vuelve a conectarlo a la familia como un móvil nuevo. Necesitarás tener a mano otro móvil de la familia.';

  @override
  String get selfWaitingHint => 'Esperando aprobación de otro móvil';

  @override
  String get healthRevokedTitle => 'Han quitado este móvil de la familia';

  @override
  String get healthRevokedBody =>
      'Tus datos siguen en este móvil. Para que vuelva a sincronizarse, conéctalo de nuevo en persona con otro móvil de la familia.';

  @override
  String get healthRevokedAction => 'Conectar otra vez';

  @override
  String healthFrozenTitle(String names) {
    return 'Sorpresas en pausa para $names';
  }

  @override
  String get healthFrozenTitleGeneric => 'Sorpresas en pausa';

  @override
  String get healthFrozenBody =>
      'No se ha perdido nada. Para ver las sorpresas, este móvil debe tener una persona de la familia asignada y estar aprobado por otro móvil de la familia.';

  @override
  String healthNamesAnd(String head, String last) {
    return '$head y $last';
  }

  @override
  String get healthRenewSoon => 'Conviene renovar la lista pronto';

  @override
  String get healthResolveSection => 'Por resolver';

  @override
  String get healthUnbackedTitle => 'Acceso sin identificar';

  @override
  String get healthUnbackedBody =>
      'Un acceso al servidor no figura en la lista de móviles de la familia. Si no lo reconoces, retíralo.';

  @override
  String healthUnbackedRef(String ref) {
    return 'Referencia: $ref';
  }

  @override
  String get healthUnbackedAction => 'Retirar acceso';

  @override
  String get healthUnbackedConfirmTitle => '¿Retirar este acceso?';

  @override
  String get healthUnbackedConfirmBody =>
      'Se corta el acceso de ese móvil al servidor de la familia. Si era un móvil tuyo, tendrás que conectarlo otra vez en persona. No se puede deshacer.';

  @override
  String get healthUnbackedDone => 'Acceso retirado';

  @override
  String healthDepartedTitle(String name) {
    return 'Baja a medias: $name';
  }

  @override
  String get healthDepartedBody =>
      'Ya no tiene acceso al servidor, pero falta completar su baja en la lista de móviles para actualizar los permisos y las claves.';

  @override
  String get healthDepartedAction => 'Completar la baja';

  @override
  String get healthDepartedDone => 'Baja completada';

  @override
  String get healthResolveBusy => 'Un momento';

  @override
  String get healthResolveError =>
      'No se ha podido completar. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get healthRetry => 'Reintentar';

  @override
  String get healthUnbackedNotNeeded => 'Ya no hace falta quitar este acceso.';

  @override
  String get settingsSelfSheetHintV2 =>
      'La persona que elijas determina qué regalos y sorpresas puedes ver en este móvil. El cambio se comparte con los demás móviles de la familia.';

  @override
  String get protectionRowTitle => 'Regalos en secreto';

  @override
  String protectionRowHint(String name) {
    return 'Que $name no vea sus regalos en su móvil.';
  }

  @override
  String get protectionStatusOff => 'Desactivados';

  @override
  String get protectionStatusRequested => 'Por confirmar';

  @override
  String get protectionStatusActive => 'Activos';

  @override
  String protectionSheetTitle(String name) {
    return 'Regalos en secreto para $name';
  }

  @override
  String protectionIntro(String name) {
    return 'Con la protección activa, $name no ve en su móvil qué regalos hay para $name ni cuántos son.';
  }

  @override
  String get protectionEffectOthers =>
      'Los demás móviles de la familia con permiso siguen viéndolos y editándolos.';

  @override
  String protectionEffectKept(String name) {
    return 'La protección no puede retirar los regalos que ya habían llegado al móvil de $name.';
  }

  @override
  String get protectionEffectConfirm =>
      'Hace falta un móvil con permiso que lo confirme.';

  @override
  String get protectionRequest => 'Pedir protección';

  @override
  String get protectionRequestedTitle => 'Protección pedida';

  @override
  String protectionWaitingBody(String name) {
    return 'Esperando a un móvil con permiso que la confirme. Hasta entonces, los regalos de $name no se muestran en ningún móvil.';
  }

  @override
  String protectionConfirmBody(String name) {
    return 'Este móvil tiene permiso para confirmarla. Al activarla, los regalos de $name dejan de mostrarse en su móvil.';
  }

  @override
  String get protectionActivate => 'Activar ahora';

  @override
  String get protectionActiveTitle => 'Protección activa';

  @override
  String protectionActiveBody(String name) {
    return '$name no ve ninguno de sus regalos en su móvil.';
  }

  @override
  String get protectionDeactivate => 'Desactivar protección';

  @override
  String protectionDeactivateTitle(String name) {
    return '¿Desactivar los regalos en secreto para $name?';
  }

  @override
  String protectionDeactivateBody(String name) {
    return 'Los regalos para $name que estén disponibles en este móvil dejarán de estar en secreto. Se incluyen los de cualquier año y los pendientes en este móvil. Cuando se sincronicen los cambios, $name podrá verlos en su móvil.';
  }

  @override
  String get protectionDeactivateConfirm => 'Desactivar';

  @override
  String protectionCannotDeactivate(String name) {
    return 'Este móvil no puede desactivarla ahora: hace falta permiso y la clave actual de $name.';
  }

  @override
  String get protectionChangeFailed =>
      'No se ha podido cambiar la protección. No se ha modificado nada.';

  @override
  String protectionNeedConfirmer(String name) {
    return 'Para proteger los regalos de $name hace falta un móvil de otra persona de la familia. En Ajustes, elige de quién es este móvil en «Este móvil es de». Aprueba el cambio desde otro móvil o conecta otro móvil a la familia. Si ya lo has hecho, sincroniza.';
  }

  @override
  String protectionNeedConfirmerOwn(String name) {
    return 'Desde este móvil no se pueden proteger los regalos de $name. Pide a otra persona de la familia que lo haga desde el suyo.';
  }

  @override
  String protectionRequesterPending(String name) {
    return 'Falta que alguien de la familia apruebe desde otro móvil el cambio en «Este móvil es de». Hasta entonces no puedes pedir protección para los regalos de $name.';
  }

  @override
  String protectionRequesterRevoked(String name) {
    return 'Este móvil ya no forma parte de la familia, así que no puede pedir la protección de los regalos de $name.';
  }

  @override
  String protectionRequesterAmbiguous(String name) {
    return 'No se sabe con seguridad de quién es este móvil, así que no puede pedir la protección de los regalos de $name. Sincroniza e inténtalo de nuevo.';
  }

  @override
  String protectionRecipientUnavailable(String name) {
    return '$name ya no está en la lista. No se puede pedir protección para sus regalos.';
  }

  @override
  String get protectionRegistryUnavailable =>
      'Este móvil todavía no está al día con la familia. Sincroniza e inténtalo de nuevo.';

  @override
  String secretBlockTitle(String name) {
    return 'Regalos en secreto para $name';
  }

  @override
  String get secretBlockNote => 'Este móvil no los muestra.';

  @override
  String protectionReason_protectedPerson(String name) {
    return 'Los regalos de $name están en secreto y no se pueden guardar así.';
  }

  @override
  String protectionReason_noEntitlement(String name) {
    return 'Este móvil no tiene acceso a los regalos en secreto para $name. Pide ayuda a alguien de la familia que tenga un móvil con permiso.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'Este móvil es de $name. Aquí no puedes crear ni ver regalos en secreto para $name.';
  }

  @override
  String protectionReason_missingEpochKey(String name) {
    return 'Falta la clave actual de los regalos de $name. Otro móvil con permiso tiene que darte acceso.';
  }

  @override
  String protectionReason_protectionPending(String name) {
    return 'Falta que un móvil con permiso confirme la protección de $name.';
  }

  @override
  String protectionReason_unreadableSlot(String name) {
    return 'No se puede abrir una parte de los regalos de $name. No se ha cambiado nada: recupera el acceso antes de seguir.';
  }

  @override
  String protectionReason_blockFull(String name) {
    return 'Has llegado al límite de regalos en secreto para $name. Elimina alguno para poder añadir más.';
  }

  @override
  String protectionReason_giftTooLarge(String name) {
    return 'Acorta las notas para poder guardar este regalo en secreto.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'Este móvil ha llegado a su límite de regalos en secreto. Pide a alguien que añada los nuevos desde otro móvil con permiso.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'Ahora mismo no se pueden añadir más regalos en secreto a la lista de la familia.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Los regalos en secreto necesitan que este móvil esté conectado a la familia con la versión nueva.';
  }

  @override
  String get giftProtectedRejected => 'No se ha guardado el regalo.';

  @override
  String get giftSavedLocally =>
      'Guardado solo en este móvil. Aún falta añadirlo a la lista y compartirlo.';

  @override
  String get giftSavedLocallyAction => 'Ver pendientes';

  @override
  String get giftOwnRequestRestricted =>
      'Con la protección activa, no puedes añadir ni ver regalos para ti en este móvil. Pide a otra persona de la familia que apunte el regalo.';

  @override
  String get pendingGiftsTitle => 'Regalos pendientes';

  @override
  String get pendingGiftsIntro =>
      'Estos regalos están cifrados y solo se guardan en este móvil. Aún no aparecen en la lista compartida de la familia. Si pierdes el móvil antes de que se añadan a la lista, perderás también estos regalos.';

  @override
  String get pendingGiftsRetry => 'Reintentar';

  @override
  String get pendingGiftsRetrying => 'Reintentando';

  @override
  String get pendingGiftsStill =>
      'Todavía no hay sitio. Los regalos siguen guardados solo en este móvil.';

  @override
  String get pendingGiftsRetryError =>
      'No se ha podido reintentar. Los regalos siguen guardados en este móvil.';

  @override
  String get pendingGiftsDoneTitle => 'Todo guardado';

  @override
  String get pendingGiftsDoneBody => 'Ya no queda ningún regalo pendiente.';

  @override
  String pendingGiftsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regalos pendientes de guardar',
      one: '$count regalo pendiente de guardar',
    );
    return '$_temp0';
  }

  @override
  String get pendingGiftsNoticeAction => 'Ver';

  @override
  String get peopleSummaryTitle => 'Resumen';

  @override
  String get giftsEmptyOccasionsHint =>
      'O apunta el primero para una próxima ocasión';

  @override
  String occasionGiftsBoughtShort(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'comprados',
      one: 'comprado',
    );
    return '$done de $total $_temp0';
  }

  @override
  String get boardToday => 'Hoy';

  @override
  String get boardNowTitle => 'Qué toca ahora';

  @override
  String boardSubtitle(String date, int bought, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total regalos comprados',
      one: '$total regalo comprado',
    );
    return '$date · $bought de $_temp0';
  }

  @override
  String get boardLaneDecide => 'Por decidir';

  @override
  String get boardLaneBuy => 'Por comprar';

  @override
  String get boardLaneArrive => 'Por llegar';

  @override
  String get boardLaneWrap => 'Por envolver';

  @override
  String get boardLaneReady => 'Listo';

  @override
  String get boardLaneEmpty => 'Nada por aquí';

  @override
  String boardMoveTo(String lane) {
    return 'Mover a «$lane»';
  }

  @override
  String boardLaneAdd(String lane) {
    return 'Añadir regalo a «$lane»';
  }

  @override
  String boardGiftMoved(String item, String lane) {
    return '$item: $lane';
  }

  @override
  String get boardOccasionsHint => 'Elige una ocasión para ver su tablero.';

  @override
  String boardSeeAll(int count) {
    return 'Ver todas ($count)';
  }

  @override
  String get boardBudgetEmptyTitle => 'Nada previsto todavía';

  @override
  String get boardChangeDate => 'Cambiar fecha';

  @override
  String get boardSettingsIndex => 'Apartados';

  @override
  String get boardEditorLabel => 'Editor de regalo';

  @override
  String get boardNoGiftsYet => 'Sin regalos todavía';

  @override
  String get boardSidebarCollapse => 'Plegar la barra lateral';

  @override
  String get boardSidebarExpand => 'Desplegar la barra lateral';

  @override
  String get boardSearchHint => 'Buscar un regalo';

  @override
  String get boardSearchNone => 'Ningún regalo coincide';

  @override
  String get boardPersonFilter => 'Persona';

  @override
  String get boardPersonFilterAll => 'Todas las personas';

  @override
  String get searchClear => 'Borrar la búsqueda';

  @override
  String get boardColStatus => 'Estado';

  @override
  String get boardColGiver => 'Quién regala';

  @override
  String get boardColSize => 'Talla';

  @override
  String get boardRepartoNoGiver => 'Sin asignar';

  @override
  String get boardRepartoNoGiverNone =>
      'Todos los regalos tienen quién los regale.';

  @override
  String get boardRepartoDuplicates => 'Posibles duplicados';

  @override
  String get boardRepartoDuplicatesNone => 'Ningún regalo parece repetido.';

  @override
  String boardRowMore(String name) {
    return 'Más acciones de $name';
  }

  @override
  String get tourTitle => 'Cómo funciona';

  @override
  String get tourSkip => 'Saltar';

  @override
  String tourPageOf(int page, int total) {
    return 'Página $page de $total';
  }

  @override
  String get tour1Title => 'Apunta cada regalo';

  @override
  String get tour1Body =>
      'Elige para quién es el regalo, la ocasión y quién lo regala. Con una idea basta.';

  @override
  String get tour2Title => 'Márcalo como comprado';

  @override
  String get tour2Body =>
      'Toca la casilla y el regalo sale de «Pendiente de comprar» y pasa a «por llegar». Si te equivocas, lo deshaces al momento.';

  @override
  String get tour3Title => 'Personas y ocasiones';

  @override
  String get tour3Body =>
      'La lista de cada persona agrupa los regalos por ocasión, como Navidad, Reyes o cumpleaños. En «Reparto» ves quién paga cada regalo.';

  @override
  String get tour4Title => 'La familia comparte la lista';

  @override
  String get tour4Body =>
      'Conecta otro móvil con un QR, en persona. Todo viaja cifrado y los cambios llegan solos.';

  @override
  String get tour5Title => 'Sorpresas a salvo';

  @override
  String get tour5Body =>
      'En tu móvil no se muestran los regalos que son para ti. Puedes bloquear la app con PIN o biometría. Sin cuentas ni anuncios.';

  @override
  String get tour6Title => 'También en el ordenador';

  @override
  String get tour6Body =>
      'Conecta la web una vez y tendrás la lista en una pantalla grande.';

  @override
  String get tourDemoScooter => 'Patinete';

  @override
  String get tourDemoPuzzle => 'Puzle';

  @override
  String get tourDemoPajamas => 'Pijama';

  @override
  String get tourDemoChristmas => 'Navidad';

  @override
  String get tourDemoBirthday => 'Cumpleaños';

  @override
  String get tourDemoConnected => 'Conectado';

  @override
  String get tourDemoEncrypted => 'Cifrado';

  @override
  String get tourDemoHidden => 'Regalos en secreto';

  @override
  String get settingsRecovery => 'Código de recuperación';

  @override
  String get recoveryValueNone => 'Sin crear';

  @override
  String get recoveryValuePrepared => 'Preparado';

  @override
  String get recoveryValuePending => 'Preparando';

  @override
  String get recoveryValueUnconfirmed => 'Sin comprobar';

  @override
  String get recoveryUnconfirmedTitle => 'Falta comprobar el código';

  @override
  String get recoveryUnconfirmedBody =>
      'El código aún no cuenta como guardado. Si guardaste un fichero, puedes comprobarlo. Si no, continúa con las palabras: si ya las viste, al continuar se creará un código nuevo y el anterior dejará de valer.';

  @override
  String get recoveryValueAttention => 'Revisar';

  @override
  String get recoveryValueTransferred => 'Lista traspasada';

  @override
  String get recoverySubtitle => 'Para recuperar la lista en un móvil nuevo.';

  @override
  String get recoveryAbsentTitle =>
      'Prepara un código para recuperar la lista si pierdes este móvil';

  @override
  String get recoveryAbsentBody =>
      'Al crear el código, la app guarda una copia cifrada para sincronizar, aunque solo tengas este móvil. Con las 24 palabras podrás recuperar en otro móvil la parte de la lista que puedes ver y que se haya sincronizado.';

  @override
  String get recoveryAbsentWarn =>
      'Quien tenga las palabras tendrá el mismo acceso a la lista que tienes en este móvil. Solo se puede recuperar lo que se haya sincronizado.';

  @override
  String get recoveryCreate => 'Crear código de recuperación';

  @override
  String get recoveryPreparedTitle => 'Código preparado';

  @override
  String get recoveryPreparedBody =>
      'La copia cifrada está lista. Las palabras no se pueden volver a ver: si las pierdes, cambia el código.';

  @override
  String get recoveryPendingTitle => 'Preparando la copia…';

  @override
  String get recoveryPendingBody =>
      'Se está guardando la copia cifrada. Hace falta conexión; se completa sola cuando la haya.';

  @override
  String get recoveryAttentionTitle => 'Hay que revisar el código';

  @override
  String get recoveryChange => 'Cambiar el código';

  @override
  String get recoveryChangeHint =>
      'Los ficheros y las palabras anteriores dejarán de servir.';

  @override
  String get recoveryRemove => 'Borrar el código';

  @override
  String get recoveryRemoveHint =>
      'Las palabras dejarán de valer y se borra la copia.';

  @override
  String get recoveryRemoveTitle => '¿Borrar el código de recuperación?';

  @override
  String get recoveryRemoveBody =>
      'Se borra la copia de recuperación y las 24 palabras dejan de valer. Podrás crear otro código cuando quieras.';

  @override
  String get recoveryRemoveSoloNote =>
      'Como no hay otro móvil ni la web conectados, también se borra la copia cifrada para sincronizar, y la lista vuelve a estar solo en este móvil.';

  @override
  String get recoveryRemoveConfirm => 'Borrar código';

  @override
  String get recoveryRemoved => 'Código borrado';

  @override
  String get recoveryRetry => 'Reintentar';

  @override
  String get recoveryIntroTitle => 'Crear el código';

  @override
  String get recoveryRotateTitle => 'Cambiar el código';

  @override
  String get recoveryIntroBody =>
      'Verás 24 palabras. Con ellas puedes recuperar en otro móvil la lista y todo lo que ves en este.';

  @override
  String get recoveryRotateBody =>
      'Se creará un código nuevo. El anterior dejará de valer cuando el nuevo esté preparado: los ficheros y las palabras anteriores dejarán de servir.';

  @override
  String get recoveryPoint1 =>
      'Apúntalas en papel o guárdalas en un gestor de contraseñas.';

  @override
  String get recoveryPoint2 =>
      'Quien las tenga tendrá el mismo acceso a la lista que tienes en este móvil.';

  @override
  String get recoveryPoint3 => 'No recuperan lo que nunca se sincronizó.';

  @override
  String get recoveryContinue => 'Continuar';

  @override
  String get recoveryAuthTitle => 'Código de recuperación';

  @override
  String get recoveryAuthMessage => 'Escribe tu PIN para ver las palabras.';

  @override
  String get recoveryAuthBiometric =>
      'Confirma que eres tú para ver el código de recuperación';

  @override
  String get recoveryMaking => 'Preparando el código…';

  @override
  String get recoveryWordsTitle => 'Tus 24 palabras';

  @override
  String get recoveryWordsBody =>
      'Apúntalas en orden. Cuando salgas de este proceso, no podrás volver a verlas.';

  @override
  String get recoveryWordsWarn =>
      'Quien tenga estas palabras tendrá el mismo acceso a la lista que tienes en este móvil. No hagas capturas de pantalla ni envíes las palabras por mensaje.';

  @override
  String recoveryWordItem(int number, String word) {
    return 'Palabra $number: $word';
  }

  @override
  String get recoveryShowQr => 'Ver código QR';

  @override
  String get recoveryShowWords => 'Ver las palabras';

  @override
  String get recoveryQrBody =>
      'Este QR permite recuperar la lista igual que las 24 palabras. No hagas capturas ni lo envíes por mensaje.';

  @override
  String get recoveryQrLabel => 'Código QR de recuperación';

  @override
  String get recoveryWordsSaved => 'Ya las he guardado';

  @override
  String get recoveryHidden => 'Palabras ocultas';

  @override
  String get recoveryHiddenBody => 'Vuelve a la app para verlas.';

  @override
  String get recoveryLeaveTitle => '¿Salir sin guardar las palabras?';

  @override
  String get recoveryLeaveBody =>
      'No se volverán a mostrar. Si sales, tendrás que cambiar el código para ver unas nuevas.';

  @override
  String get recoveryLeaveConfirm => 'Salir';

  @override
  String get recoveryLeaveStay => 'Seguir aquí';

  @override
  String get recoveryCheckTitle => 'Comprueba que las has guardado';

  @override
  String recoveryCheckBody(int a, int b, int c) {
    return 'Escribe las palabras $a, $b y $c.';
  }

  @override
  String recoveryCheckField(int number) {
    return 'Palabra $number';
  }

  @override
  String get recoveryCheckWrong =>
      'Alguna palabra no coincide. Míralas otra vez.';

  @override
  String get recoveryCheckBack => 'Ver las palabras otra vez';

  @override
  String get recoveryCheckButton => 'Comprobar';

  @override
  String get recoveryDonePreparedTitle => 'Código preparado';

  @override
  String get recoveryDonePreparedBody =>
      'Si pierdes este móvil, podrás recuperar la lista con tu código de recuperación.';

  @override
  String get recoveryDonePendingBody =>
      'Todavía no está listo: se está guardando la copia cifrada. Hace falta conexión y se completa sola.';

  @override
  String get recoveryDoneButton => 'Listo';

  @override
  String get recoveryCloseLater => 'Cerrar y seguir luego';

  @override
  String get recoveryProblemOfflineTitle => 'Sin conexión';

  @override
  String get recoveryProblemOfflineBody =>
      'No se ha podido conectar con el servidor. Se conserva lo que has hecho. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get recoveryProblemWrongTitle => 'Ese código no abre ninguna lista';

  @override
  String get recoveryProblemWrongBody =>
      'Revisa las palabras o prueba con otro código. Si lo cambiaron, usa el más reciente.';

  @override
  String get recoveryProblemRetiredTitle => 'Ese código ya no vale';

  @override
  String get recoveryProblemRetiredBody =>
      'Se cambió o se borró desde otro móvil. Busca el código más reciente.';

  @override
  String get recoveryProblemRemovedTitle =>
      'Este móvil ya no está en la familia';

  @override
  String get recoveryProblemRemovedBody =>
      'Este código es de un móvil que se quitó de la familia. Ya no sirve para recuperar la lista.';

  @override
  String get recoveryProblemIncompleteTitle =>
      'La recuperación se quedó a medias';

  @override
  String get recoveryProblemIncompleteBody =>
      'Falta una parte de la lista. Lo descargado se conserva. Inténtalo de nuevo cuando tengas conexión. Si tienes otro móvil conectado a esta familia, también puedes abrir allí la app un momento.';

  @override
  String get recoveryProblemBusyTitle => 'Hay otra operación en marcha';

  @override
  String get recoveryProblemBusyBody =>
      'Espera un momento e inténtalo de nuevo.';

  @override
  String get recoveryProblemUnsupportedTitle => 'No se puede abrir esta copia';

  @override
  String get recoveryProblemUnsupportedBody =>
      'Puede que haga falta actualizar la app, o que la copia esté dañada.';

  @override
  String get recoveryProblemUnavailableTitle => 'No disponible ahora';

  @override
  String get recoveryProblemUnavailableBody =>
      'La recuperación no está disponible en este móvil.';

  @override
  String get recoveryProblemOtherTitle => 'Algo no ha salido bien';

  @override
  String get recoveryProblemOtherBody =>
      'No se ha podido terminar. Inténtalo de nuevo. Si el problema continúa, prueba más tarde.';

  @override
  String get obHaveRecoveryCode => 'Usar el código de recuperación';

  @override
  String get recoverTitle => 'Recuperar la lista';

  @override
  String get recoverBody =>
      'Escribe las 24 palabras en orden o escanea el código QR de recuperación.';

  @override
  String recoverWordField(int number) {
    return 'Palabra $number';
  }

  @override
  String recoverFilled(int count) {
    return '$count de 24 palabras';
  }

  @override
  String get recoverPaste => 'Pegar las 24 palabras';

  @override
  String get recoverScan => 'Escanear el QR';

  @override
  String get recoverSubmit => 'Recuperar la lista';

  @override
  String recoverWordUnknown(int number) {
    return 'Revisa cómo has escrito la palabra $number.';
  }

  @override
  String get recoverChecksum =>
      'Las palabras no forman un código válido. Comprueba que sean las de tu código y que estén en el mismo orden.';

  @override
  String get recoverPasteEmpty => 'No hay nada copiado.';

  @override
  String get recoverPasteWrong =>
      'Lo copiado no tiene 24 palabras. Copia el código entero y pégalo de nuevo.';

  @override
  String get recoverQrWrong => 'Ese QR no es un código de recuperación.';

  @override
  String get recoverScanTitle => 'Escanear el QR';

  @override
  String get recoverScanBody =>
      'Apunta la cámara al código QR de recuperación.';

  @override
  String get recoverProgressTitle => 'Recuperando la lista';

  @override
  String get recoverProgressBody =>
      'No cierres la app. Puede tardar un minuto.';

  @override
  String get recoverStepFind => 'Buscando la copia';

  @override
  String get recoverStepCheck => 'Comprobando el código';

  @override
  String get recoverStepDownload => 'Descargando la lista';

  @override
  String get recoverStepInstall => 'Guardando la lista en este móvil';

  @override
  String get recoverDoneTitle => 'Lista recuperada';

  @override
  String recoverDoneSelf(String name) {
    return 'Este móvil es de $name.';
  }

  @override
  String get recoverDoneNoSelf =>
      'Falta indicar de quién es este móvil. Puedes hacerlo en Ajustes.';

  @override
  String recoverDonePeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas',
      one: '1 persona',
    );
    return 'Tu lista tiene $_temp0.';
  }

  @override
  String get recoverEnter => 'Entrar en la lista';

  @override
  String get recoverOtherCode => 'Escribir otro código';

  @override
  String get transferredTitle => 'Esta lista se ha traspasado';

  @override
  String get transferredBody =>
      'Tu lista está ahora en otro móvil o en otra app. Aquí puedes consultarla, pero ya no puedes editarla. No se ha borrado nada.';

  @override
  String get transferredReadOnly => 'Solo lectura';

  @override
  String get recoveryProblemFamilyTitle => 'Este código es de otra familia';

  @override
  String get recoveryProblemFamilyBody =>
      'Sustituiría la lista que tienes en este móvil. Si no es lo que quieres, cancela la recuperación.';

  @override
  String get recoveryProblemNotReadyTitle => 'La copia todavía no está lista';

  @override
  String get recoveryProblemNotReadyBody =>
      'Las 24 palabras aún no están disponibles. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get recoverReplaceTitle => '¿Sustituir la lista de este móvil?';

  @override
  String get recoverReplaceBody =>
      'Este código es de otra familia. Si continúas, verás su lista en este móvil. La que usas ahora seguirá guardada aquí, pero ya no la verás.';

  @override
  String get recoverReplaceConfirm => 'Sustituir';

  @override
  String get recoverAbandon => 'Cancelar la recuperación';

  @override
  String get recoverAbandonTitle => '¿Cancelar la recuperación?';

  @override
  String get recoverAbandonBody =>
      'Si cancelas, este móvil borrará los datos temporales de la recuperación. Si en el móvil anterior ya solo podías consultar la lista, seguirá así. Podrás volver a usar el código.';

  @override
  String get recoverAbandonConfirm => 'Cancelar recuperación';

  @override
  String get recoverAbandonKeep => 'Seguir';

  @override
  String get recoverAbandonFailed =>
      'Algo no ha salido bien. Inténtalo de nuevo en un momento.';

  @override
  String get recoverAbandonBodyClaimed =>
      'En el otro móvil ya solo puedes consultar la lista. Si cancelas, seguirá así. Para recuperar la lista tendrás que volver a usar este código.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'Este móvil no puede bloquear las capturas de pantalla: no hagas ninguna.';

  @override
  String get recoverLeaveTitle => '¿Salir de la recuperación?';

  @override
  String get recoverLeaveBody =>
      'La recuperación quedará pendiente en este móvil. Podrás reanudarla o cancelarla más tarde.';

  @override
  String get recoverPendingTitle => 'Recuperación pendiente';

  @override
  String get recoverPendingBody =>
      'Se quedó a medias en este móvil. Reanúdala o cancélala antes de crear una familia o unirte a otra.';

  @override
  String get recoverResume => 'Reanudar';

  @override
  String get recoveryProblemPendingTitle => 'Hay una recuperación a medias';

  @override
  String get recoveryProblemPendingBody =>
      'Reanúdala o cancélala antes de crear una familia o unirte a otra.';

  @override
  String get recoveryMaintCancel => 'Cancelar la preparación';

  @override
  String get recoveryMaintCancelTitle => '¿Cancelar la preparación del código?';

  @override
  String get recoveryMaintCancelBody =>
      'El código que ya tengas sigue valiendo. Se deja de preparar lo que estaba en marcha.';

  @override
  String get recoveryMaintCancelConfirm => 'Cancelar preparación';

  @override
  String get recoveryRemoveAuthMessage =>
      'Escribe tu PIN para borrar el código.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirma que quieres borrar el código de recuperación';

  @override
  String get transferredRecover => 'Recuperar con mi código';

  @override
  String get transferredErase => 'Borrar los datos de esta app';

  @override
  String get recoverStepDoneValue => 'hecho';

  @override
  String get recoverStepActiveValue => 'en curso';

  @override
  String get recoveryFileAction => 'Guardar en un fichero';

  @override
  String get recoveryFileTitle => 'Guardar en un fichero';

  @override
  String get recoveryFileBody =>
      'También puedes guardar el código en un fichero. Quien pueda abrirlo podrá recuperar la lista con el mismo acceso que tienes en este móvil.';

  @override
  String get recoveryFilePersonal =>
      'Es un fichero personal: no lo envíes a la familia. Guárdalo donde puedas abrirlo aunque pierdas este móvil.';

  @override
  String get recoveryFileProtect => 'Proteger con contraseña';

  @override
  String get recoveryFileProtectOffHint =>
      'Sin contraseña, el fichero vale tanto como las palabras: quien lo consiga puede usarlo.';

  @override
  String get recoveryFileProtectOnHint =>
      'Robar el fichero no basta: hace falta la contraseña.';

  @override
  String get recoveryFilePassword => 'Contraseña';

  @override
  String get recoveryFilePasswordRepeat => 'Repite la contraseña';

  @override
  String get recoveryFilePasswordShow => 'Ver';

  @override
  String get recoveryFilePasswordHide => 'Ocultar';

  @override
  String recoveryFilePasswordHelp(int min) {
    return 'Mínimo $min caracteres. Usa el gestor de contraseñas o varias palabras elegidas al azar.';
  }

  @override
  String get recoveryFilePasswordForgot =>
      'Si olvidas la contraseña, no podrás abrir el fichero. Aún podrás recuperar la lista con las 24 palabras.';

  @override
  String recoveryFilePwTooShort(int min) {
    return 'Es muy corta: mínimo $min caracteres.';
  }

  @override
  String recoveryFilePwTooLong(int max) {
    return 'Es demasiado larga: máximo $max caracteres.';
  }

  @override
  String get recoveryFilePwRepeated => 'Se repite un mismo carácter o bloque.';

  @override
  String get recoveryFilePwDigits => 'No puede ser solo números.';

  @override
  String get recoveryFilePwKeyboard => 'Parece una fila o secuencia de teclas.';

  @override
  String get recoveryFilePwAppName => 'No puede contener el nombre de la app.';

  @override
  String get recoveryFilePwCommon => 'Es una frase demasiado común.';

  @override
  String get recoveryFilePwMismatch => 'Las dos contraseñas no coinciden.';

  @override
  String get recoveryFileSave => 'Guardar';

  @override
  String get recoveryFileSaveAgain => 'Guardar otra copia';

  @override
  String get recoveryFileShare => 'Compartir';

  @override
  String get recoveryFileShareText =>
      'Fichero de recuperación de Gift Huddle. Es personal: no lo reenvíes a la familia.';

  @override
  String get recoveryFileStem => 'gift-huddle-recuperacion';

  @override
  String get recoveryFileDerivingTitle => 'Procesando el fichero…';

  @override
  String get recoveryFileDerivingBody =>
      'Mantén la app abierta. Este paso tarda unos segundos.';

  @override
  String get recoveryFileSavedTitle => 'Fichero guardado';

  @override
  String get recoveryFileSavedBody =>
      'Se ha vuelto a leer desde donde lo guardaste y el código está comprobado. Puedes guardar otra copia.';

  @override
  String get recoveryFileProblemVerifyTitle =>
      'No se ha podido comprobar lo guardado';

  @override
  String get recoveryFileProblemVerifyBody =>
      'El fichero no se ha guardado bien. Guárdalo de nuevo, quizá en otro sitio.';

  @override
  String get recoveryFileProblemUnreadableTitle =>
      'No se ha podido leer el fichero';

  @override
  String get recoveryFileProblemUnreadableBody =>
      'Comprueba que el fichero está disponible en este móvil e inténtalo de nuevo.';

  @override
  String get recoveryFileProblemUnavailableTitle =>
      'Este móvil no puede abrir el selector de ficheros';

  @override
  String get recoveryFileProblemUnavailableBody =>
      'Prueba con «Compartir» o usa las 24 palabras.';

  @override
  String get recoveryFileProblemPickerBusyTitle =>
      'Ya hay un selector de ficheros abierto';

  @override
  String get recoveryFileProblemPickerBusyBody =>
      'Ciérralo e inténtalo de nuevo.';

  @override
  String get recoveryFileProblemNotFileTitle =>
      'No es un fichero de recuperación';

  @override
  String get recoveryFileProblemNotFileBody =>
      'Elige el fichero que guardaste al crear el código. Termina en .gifthuddle.';

  @override
  String get recoveryFileProblemNewerTitle =>
      'Fichero de una versión más nueva';

  @override
  String get recoveryFileProblemNewerBody =>
      'Actualiza la app e inténtalo de nuevo.';

  @override
  String get recoveryFileProblemPasswordTitle =>
      'Contraseña incorrecta o fichero dañado';

  @override
  String get recoveryFileProblemPasswordBody =>
      'Revisa la contraseña. Si no la recuerdas, usa las 24 palabras.';

  @override
  String get recoveryFileProblemNotCurrentTitle =>
      'Este fichero es de otro código';

  @override
  String get recoveryFileProblemNotCurrentBody =>
      'Este fichero contiene un código anterior y ya no sirve. Busca un fichero más reciente o cambia el código.';

  @override
  String get recoveryFileProblemHasFamilyTitle =>
      'Este móvil ya tiene una lista';

  @override
  String get recoveryFileProblemHasFamilyBody =>
      'El fichero de recuperación solo sirve en un móvil sin lista. No se ha usado.';

  @override
  String get recoveryCheckFileAction => 'Comprobar un fichero';

  @override
  String get recoveryCheckFileTitle => 'Comprobar un fichero';

  @override
  String get recoveryCheckFileBody =>
      'Elige el fichero de recuperación que guardaste. La app comprobará si contiene el código de este móvil. No se guarda ni se envía nada.';

  @override
  String get recoveryFilePick => 'Elegir fichero';

  @override
  String get recoveryFilePasswordTitle => 'Contraseña del fichero';

  @override
  String get recoveryFilePasswordOpenBody =>
      'Este fichero está protegido. Escribe la contraseña que pusiste al guardarlo.';

  @override
  String get recoveryFileOpen => 'Abrir el fichero';

  @override
  String get recoveryFileCheckingTitle => 'Comprobando el fichero…';

  @override
  String get recoveryFileCheckingBody => 'Un momento.';

  @override
  String get recoveryCheckFileOkTitle => 'Código comprobado';

  @override
  String get recoveryCheckFileOkBody =>
      'El fichero contiene el código de este móvil. Si pierdes el móvil, podrás usar el fichero para recuperar la lista.';

  @override
  String get obRecoverWithFile => 'Usar el fichero de recuperación';

  @override
  String get recoverFileTitle => 'Recuperar con un fichero';

  @override
  String get recoverFileBody =>
      'Elige el fichero de recuperación que guardaste al crear el código. Termina en .gifthuddle.';

  @override
  String get recoverFileReceived => 'Has abierto un fichero de recuperación.';

  @override
  String get recoverFileConfirmTitle => '¿Recuperar con este fichero?';

  @override
  String get recoverFileConfirmBody =>
      'Este móvil recuperará la lista y ocupará en la familia el lugar del móvil que guardó el código. Continúa solo si el fichero es tuyo.';

  @override
  String get recoverFileOther => 'Elegir otro fichero';

  @override
  String get recoverFileWaitingTitle => '¿Cambiar de fichero?';

  @override
  String get recoverFileWaitingBody =>
      'Ha llegado un nuevo fichero de recuperación mientras usabas otro.';

  @override
  String get recoverFileWaitingSwitch => 'Usar el nuevo';

  @override
  String get recoverFileWaitingKeep => 'Seguir con el actual';

  @override
  String get recoveryProblemPersonTitle =>
      'El código ya no vale para la persona elegida';

  @override
  String get recoveryProblemPersonBody =>
      'Ha cambiado la persona elegida en «Este móvil es de» o hay un cambio pendiente. Crea un código nuevo y guárdalo.';

  @override
  String get recoveryFileProblemStorageTitle =>
      'No se ha podido leer la lista de este móvil';

  @override
  String get recoveryFileProblemStorageBody =>
      'El fichero sigue pendiente de abrir. La app necesita comprobar si ya hay una lista en este móvil. Inténtalo de nuevo.';

  @override
  String get cameraRestricted =>
      'Este móvil tiene restringido el acceso a la cámara. Si usas Tiempo de uso, revisa Ajustes > Tiempo de uso > Restricciones de contenido y privacidad.';

  @override
  String get obJoinFamily => 'Unirme a una familia';

  @override
  String get obJoinFamilyHint =>
      'Elige cómo conectarte con el móvil que ya tiene la lista.';

  @override
  String get obJoinQrHint =>
      'Si tienes el otro móvil a mano, escanea su código QR.';

  @override
  String get obJoinLinkHint =>
      'Si el otro móvil está lejos, pega el enlace que te han enviado.';

  @override
  String get obRestoreBackup => 'Recuperar una copia';

  @override
  String get obRestoreBackupHint => 'Elige cómo recuperar la lista.';

  @override
  String get obRestoreCodeHint => 'Escribe las 24 palabras que guardaste.';

  @override
  String get obRestoreFileHint =>
      'Abre el fichero de recuperación que guardaste.';

  @override
  String get giverPeopleSection => 'Personas';

  @override
  String get giverPeopleHintAdd => 'Primero se añade a quienes regalan';

  @override
  String get giverPeopleHintRecover => 'Volverá a la lista de quienes regalan';

  @override
  String giverPersonAddTitle(String name) {
    return '¿Añadir a $name a la lista de quienes regalan?';
  }

  @override
  String giverPersonAddBody(String name) {
    return 'Este regalo es una sorpresa. Primero, añade a $name a la lista de quienes regalan. Toda la familia verá su nombre en esa lista, sin ninguna referencia al regalo. Después podrás elegir a $name aquí.';
  }

  @override
  String giverPersonAddConfirm(String name) {
    return 'Añadir a $name';
  }

  @override
  String giverPersonAddFailed(String name) {
    return 'No se ha podido añadir a $name a la lista de quienes regalan. Inténtalo de nuevo.';
  }

  @override
  String get giftNoLongerVisible =>
      'Este regalo ya no se puede ver en este móvil.';

  @override
  String deleteGiverRows(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminan estos $count nombres: $names.',
      one: 'Se elimina $names.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverGiftTitles(String titles, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: 'Afecta a: $titles y $more más.',
      zero: 'Afecta a: $titles.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverLinkedNote(String name) {
    return '$name seguirá en «Personas». Solo se eliminará de «Quién regala».';
  }

  @override
  String get deleteImpactChanged =>
      'La lista ha cambiado. Antes de confirmar, revisa qué se eliminará.';

  @override
  String get deletePersonLinkedGiver =>
      'Su nombre seguirá en «Quién regala» en los regalos que hace a otras personas.';

  @override
  String devicePersonBlockedThisTitle(String name) {
    return 'Este móvil es de $name';
  }

  @override
  String devicePersonBlockedThisBody(String name) {
    return 'Para eliminar o archivar a $name, ve a Ajustes y elige primero a otra persona en «Este móvil es de».';
  }

  @override
  String devicePersonBlockedOtherTitle(String name) {
    return '$name tiene su propio móvil';
  }

  @override
  String devicePersonBlockedOtherBody(String name) {
    return '$name tiene su propio móvil en la familia, así que no se puede eliminar ni archivar desde aquí.';
  }

  @override
  String get giverLinkedLine =>
      'Enlazado a una persona: su nombre y color se cambian en Personas.';

  @override
  String giverLinkedNameHint(String name) {
    return 'El nombre y el color son los de $name. Cámbialos en Personas.';
  }

  @override
  String get giverLinkLabel => 'Enlazar con una persona';

  @override
  String get giverLinkHint =>
      'Su nombre y color pasarán a ser los de la persona.';

  @override
  String get giverLinkExistingHint =>
      'Ya regala. Las dos columnas de Reparto se unirán en una.';

  @override
  String giverLinkConfirmTitle(String name) {
    return '¿Enlazar con $name?';
  }

  @override
  String giverLinkConfirmBody(String giver, String name) {
    return '«$giver» usará el nombre y el color de $name. Si los cambias en la ficha de $name en Personas, también cambiarán aquí. Se conservarán los regalos.';
  }

  @override
  String get giverLinkConfirm => 'Enlazar';

  @override
  String get giverUnlinkLabel => 'Desenlazar de la persona';

  @override
  String giverUnlinkConfirmTitle(String name) {
    return '¿Desenlazar de $name?';
  }

  @override
  String giverUnlinkConfirmBody(String name) {
    return 'Seguirá en la lista de quienes regalan con su nombre, su color y sus regalos actuales. Los cambios que hagas en la ficha de $name ya no se aplicarán aquí.';
  }

  @override
  String get giverUnlinkConfirm => 'Desenlazar';

  @override
  String get giverLinkError =>
      'No se ha podido cambiar el enlace. Inténtalo de nuevo.';

  @override
  String get giftWriteGiftUnavailable =>
      'No se ha guardado: este regalo ya no está disponible en este móvil.';

  @override
  String get giftWriteRecipientGone =>
      'No se ha guardado: la persona que iba a recibir el regalo ya no está en la lista.';

  @override
  String get giftWriteInvalidPair =>
      'No se ha guardado: quien regala no puede ser quien recibe el regalo.';

  @override
  String get giftWriteGiverGone =>
      'No se ha guardado: quien regala ya no está en la lista.';

  @override
  String get giftWriteGiverArchived =>
      'No se ha guardado: quien regala está archivado.';

  @override
  String get giftWritePersonGone =>
      'No se ha guardado: esa persona ya no está en la lista.';

  @override
  String get giftWritePersonArchived =>
      'No se ha guardado: esa persona está archivada.';

  @override
  String giverUnlinkStale(String name) {
    return 'Ya no estaba enlazado a $name.';
  }

  @override
  String get deleteImpactUnavailable =>
      'No se ha podido comprobar qué se eliminaría. Inténtalo de nuevo.';

  @override
  String get deleteImpactChecking => 'Comprobando lo que se elimina…';
}

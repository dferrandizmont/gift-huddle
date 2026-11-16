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
  String get emptyFamilyTitle => 'Nadie ha apuntado regalos';

  @override
  String get emptyFamilyMessage =>
      'Aquí verás quién regala qué a cada persona.';

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
      'La lista de una ocasión cambia de acento y cabecera.';

  @override
  String get appearanceHapticsTitle => 'Vibraciones';

  @override
  String get appearanceHapticsHint =>
      'Pequeños toques al marcar, elegir o cuando algo llega.';

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
  String get shareEnvelopeText => 'Cambios de Gift Huddle: ábrelo con la app.';

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
      'El otro móvil tiene la fecha y la hora mal puestas. Corrígelas y vuelve a enviarlo.';

  @override
  String get shareErrorLegacyFile =>
      'Este fichero es de una versión anterior de Gift Huddle y ya no se abre. Guárdalo y pide que te lo envíen de nuevo desde un móvil actualizado.';

  @override
  String get shareErrorNotReady =>
      'Este móvil todavía no está al día con la familia. Sincroniza y vuelve a abrir el fichero.';

  @override
  String get shareErrorGeneration =>
      'Este fichero es de una versión anterior de la lista. Pide que te envíen uno nuevo.';

  @override
  String get shareErrorRevokedWriter =>
      'Este fichero lo guardó un móvil que ya no es de la familia. No se ha añadido nada.';

  @override
  String get shareErrorMissingKey =>
      'Todavía no se puede abrir este fichero. Se ha guardado y se abrirá solo cuando sincronices.';

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
    return 'Demasiados intentos. Vuelve a probar en $time.';
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
      'Si lo paga la casa, cuenta en el presupuesto.';

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
      'Apunta qué regala cada uno a cada persona, para que nadie repita y a nadie le falte.';

  @override
  String get obWelcomePrivacy =>
      'Sin cuentas. Si sincronizáis dos móviles, la lista viaja cifrada y solo vuestros móviles pueden leerla.';

  @override
  String get obDeviceNameLabel => 'Nombre de este móvil';

  @override
  String get obDeviceNameHint =>
      'Es el nombre que verá el otro móvil. Puedes cambiarlo.';

  @override
  String get obStart => 'Empezar';

  @override
  String get obHaveListTitle => '¿Ya tenéis la lista en otro móvil?';

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
    return 'Quitar a $name';
  }

  @override
  String get obGiversTitle => '¿Quién regala?';

  @override
  String get obGiversBody =>
      '«Nosotros» ya está creado y paga la casa. Añade a los abuelos, los tíos…';

  @override
  String get obGiversSuggestions => 'Añadir rápido';

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
  String get giverNameHint => 'Abuelos, Tía Marta y Jordi…';

  @override
  String get obOccasionsTitle => '¿Cuándo hay regalos?';

  @override
  String get obOccasionsBody =>
      'Elige las fechas de siempre. Los cumpleaños salen solos de las fechas que hayas puesto.';

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
  String get obPinTitle => 'Protege los regalos';

  @override
  String get obPinBody =>
      'Crea un PIN para que nadie vea los regalos si coge el móvil. Podrás cambiarlo en Ajustes.';

  @override
  String get obPinCreate => 'Crear PIN';

  @override
  String get obFinishing => 'Preparando tu lista…';

  @override
  String get obSaveError => 'No se ha podido guardar. Inténtalo otra vez.';

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
  String get filterNoResults => 'Ningún regalo cumple los filtros.';

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
    return 'Regalo añadido a $name';
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
  String get giftDelete => 'Borrar regalo';

  @override
  String confirmDeleteTitle(String name) {
    return '¿Borrar «$name»?';
  }

  @override
  String get confirmDeleteBody =>
      'Se borra también en los móviles de tu familia.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done de $total comprados';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Todo comprado para $occasion';
  }

  @override
  String get giftSaveError => 'No se ha podido guardar el regalo.';

  @override
  String get giftDuplicateTitle => 'Posible duplicado';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return '«$title» se parece a un regalo que ya está apuntado para $person ($giver).';
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
  String get budgetCardHint => 'Previsto, gastado y lo que queda';

  @override
  String get occasionPeopleSection => 'Cada persona';

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
    return 'Reparto de $name: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Pendiente de comprar';

  @override
  String get occasionPendingEmpty =>
      'Nada decidido todavía. Cuando una idea pase a Decidido, aparecerá aquí agrupada por tienda.';

  @override
  String get occasionStoreNone => 'Sin tienda';

  @override
  String occasionMarkBought(String item) {
    return 'Marcar $item como comprado';
  }

  @override
  String get occasionIdeasSection => 'Ideas';

  @override
  String get budgetTitle => 'Presupuesto';

  @override
  String get budgetSubtitle => 'Solo lo que paga la casa';

  @override
  String get budgetPlanned => 'Previsto';

  @override
  String get budgetSpent => 'Gastado';

  @override
  String get budgetLeft => 'Queda';

  @override
  String get budgetOver => 'Te pasas';

  @override
  String get budgetByPerson => 'Por persona';

  @override
  String get budgetByOccasion => 'Por ocasión';

  @override
  String get budgetNote =>
      'Lo que regalan los abuelos o los tíos cuenta como regalo, no como gasto de la casa.';

  @override
  String get budgetEmpty =>
      'Todavía no hay regalos que pague la casa. Marca «Paga la casa» en quien regala y pon un precio previsto.';

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
      'Sin cuentas ni publicidad. Tus regalos solo salen del móvil, siempre cifrados, si conectas otro móvil o la web, creas un código de recuperación o envías una copia.';

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
      'Archivar quita algo de las listas sin borrar sus regalos; se recupera en Ajustes › Archivo. Eliminar lo borra para siempre.';

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
      'No se ha podido activar. Comprueba la huella o el rostro del móvil.';

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
      'En el otro móvil abre Gift Huddle, toca «Escanear el QR» y apunta la cámara a este código.';

  @override
  String get showQrWarning =>
      'No hagas captura ni lo compartas: este código da acceso a toda la lista. Enséñalo solo en persona.';

  @override
  String get showQrLabel => 'Código QR para conectar otro móvil';

  @override
  String get joinIntro => 'Apunta la cámara al código QR del otro móvil.';

  @override
  String get joinCameraError =>
      'No se puede usar la cámara. Revisa el permiso de cámara en los ajustes del móvil.';

  @override
  String get joinConflictTitle => 'Este móvil ya tiene una lista';

  @override
  String get joinConflictBody =>
      'Si te unes a la del otro móvil, esta lista se sustituye y se pierden sus regalos. ¿Seguir?';

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
  String get incomingFailedTitle => 'No se pudo abrir el envío';

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
      other: '$count cambiados',
      one: '$count cambiado',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count borrados',
      one: '$count borrado',
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
      'Este móvil sale de la sincronización de la familia y deja de enviar y recibir cambios; los demás móviles siguen sincronizando entre ellos. Si es el último, también se borra la copia cifrada del servidor. Lo que hay en cada móvil se queda como está. Para volver a sincronizar, conéctalo de nuevo con otro móvil de la familia.';

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
  String get syncStatusWaitingPeer => 'Empezará cuando emparejes otro móvil';

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
  String get syncStatusOffline => 'Sin conexión, se enviará luego';

  @override
  String get syncStatusError => 'No se ha podido sincronizar';

  @override
  String get syncIssueAuth => 'El servidor no acepta la clave de esta familia.';

  @override
  String get syncIssueClockDrift =>
      'Otro móvil tiene la fecha y la hora mal puestas. Corrígelas en ese móvil.';

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
      'El enlace no lleva ninguna clave: solo sirve para pedir entrada. Te llegará la petición con un código de 6 cifras y tendrás que aceptarla tú. Caduca a las 24 horas y sirve para una sola persona.';

  @override
  String get inviteCreate => 'Crear enlace e invitar';

  @override
  String get inviteNeedSync =>
      'Para invitar a distancia hace falta tener la sincronización encendida y con conexión.';

  @override
  String get inviteGoToSync => 'Encender la sincronización';

  @override
  String inviteShareText(String link) {
    return 'Te invito a mi lista de Gift Huddle. Abre el enlace y pide entrar: $link';
  }

  @override
  String get inviteWaitingTitle => 'Esperando a que abran el enlace';

  @override
  String get inviteWaitingBody =>
      'Cuando la otra persona lo abra, aquí verás su petición. Puedes salir de esta pantalla: la invitación sigue activa hasta que caduque.';

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
      'Has rechazado la petición. El enlace ya no sirve.';

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
      'No se ha podido completar. Inténtalo de nuevo.';

  @override
  String get joinInviteTaken =>
      'Esta invitación ya la ha pedido otra persona. Pide un enlace nuevo.';

  @override
  String get joinInviteGone => 'La invitación ha caducado o no se ha aceptado.';

  @override
  String get joinInviteWaitingTitle => 'Esperando a que te acepten';

  @override
  String get joinInviteWaitingBody =>
      'Quien te invitó tiene que ver tu petición. En unos segundos verás aquí un código para comparar con esa persona. Puedes esperar hasta 10 minutos.';

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
    return '$count sin quién';
  }

  @override
  String repartoSheetNobodyYet(String giver, String person) {
    return '$giver aún no regala nada a $person';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return '$person tiene regalos sin quién los regale: toca «¿Quién?» para darlos.';
  }

  @override
  String get repartoSheetStartHint => 'Apunta un regalo nuevo para empezar.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · toca quién regala para cambiarlo';
  }

  @override
  String get repartoSheetWho => '¿Quién?';

  @override
  String get repartoSheetNobody => 'Nadie';

  @override
  String get repartoSheetAddGift => 'Añadir regalo';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'Regalo nuevo de $giver';
  }

  @override
  String repartoSheetOpenList(String person) {
    return 'Ver la lista de $person';
  }

  @override
  String get repartoSheetNoGiver => 'Sin quién regala';

  @override
  String repartoSheetChipLabel(String giver) {
    return 'Quién regala: $giver. Cambiar';
  }

  @override
  String repartoSheetLabel(String giver, String person) {
    return 'Regalos de $giver para $person';
  }

  @override
  String get lockBiometricHint => 'Toca la huella para entrar';

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
      'Cómo sale en Reparto. No se borra ningún regalo.';

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
      other: 'Se eliminarán también sus $count regalos.',
      one: 'Se eliminará también su regalo.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo => 'Su cumpleaños también desaparece.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sus $count regalos se quedarán sin quién regala.',
      one: 'Su regalo se quedará sin quién regala.',
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
      'En los regalos que pidió, se borra quién los pidió.';

  @override
  String get deleteGiverBudget =>
      'Sus importes dejan de contar en el presupuesto de la casa.';

  @override
  String get deleteError => 'No se ha podido eliminar. Inténtalo de nuevo.';

  @override
  String get giftNotSaved =>
      'No se ha guardado: este regalo ya no existe, lo ha borrado otro móvil.';

  @override
  String giftDeletedNotice(String name) {
    return '«$name» borrado';
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
      'Antes, este móvil sale de la sincronización de la familia; si es el último, también se borra la copia cifrada del servidor.';

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
      'Comprueba la conexión y reinténtalo. Si borras solo este móvil, seguirá en la lista de móviles de tu familia hasta que otro lo quite, y la copia cifrada se queda en el servidor para los demás (o hasta que caduque, si era el último).';

  @override
  String get eraseAllRetry => 'Reintentar';

  @override
  String get eraseAllLocalOnly => 'Borrar solo este móvil';

  @override
  String get eraseAllFailed =>
      'No se ha podido borrar todo. Inténtalo de nuevo.';

  @override
  String get eraseAllPinPrompt => 'Escribe tu PIN para seguir con el borrado.';

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
      'Fuera de las listas, con sus regalos guardados.';

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
      'La lista tiene una copia cifrada que se recupera con tu código. Conecta otro móvil para verla en los dos.';

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
  String get devicesPeerNoPerson => 'Sin persona: aún no abre las sorpresas';

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
      'Si te unes a otra familia, la lista de este móvil se sustituye y se pierden sus regalos.';

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
      'Se fusiona con lo que hay: no se pierde nada.';

  @override
  String get backupPasteTitle => 'Pegar desde el portapapeles';

  @override
  String get backupPasteHint => 'Si te llegó como enlace o como texto.';

  @override
  String get backupFileNote =>
      'Para abrir un fichero .gifthuddle, tócalo en Archivos o en el mensaje donde te llegó y elige Gift Huddle.';

  @override
  String get backupNote =>
      'La copia va cifrada con la clave de la familia: hoy solo se abre en un móvil que ya esté conectado.';

  @override
  String get pairingV2Preparing => 'Preparando la conexión…';

  @override
  String get pairingV2NoticeExpires =>
      'El código caduca a las 24 horas y solo sirve para pedir entrada: nadie entra sin que compares un número con el otro móvil.';

  @override
  String get pairingV2FarTitle => 'Comparte el enlace';

  @override
  String get pairingV2FarBody =>
      'Envíaselo a quien quieras conectar. Cuando lo abra y pida entrar, aquí verás un número para compararlo.';

  @override
  String get pairingV2Share => 'Compartir el enlace';

  @override
  String get pairingV2WaitingHere =>
      'Esperando a que el otro móvil lea el código…';

  @override
  String get pairingV2CompareTitle => 'Compara el número';

  @override
  String get pairingV2HostCompareBody =>
      'El otro móvil enseña un número. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden»; si no, «No coinciden».';

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
      'Acceso enviado. El otro móvil tiene que terminar la conexión.';

  @override
  String get pairingV2VersionMismatch =>
      'Los dos móviles tienen que tener la última versión de Gift Huddle. Actualiza el que esté desfasado y vuelve a empezar.';

  @override
  String get pairingV2HostCancelled =>
      'Se ha cancelado y el código ya no sirve. Puedes empezar de nuevo.';

  @override
  String get pairingV2HostFailed =>
      'No se ha podido conectar el otro móvil. Inténtalo de nuevo.';

  @override
  String get pairingV2NotReady =>
      'Para conectar otro móvil hace falta tener la sincronización encendida y conexión a internet.';

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
      'Esperando al otro móvil. En unos segundos verás aquí un número para comparar.';

  @override
  String get pairingV2GuestCompareBody =>
      'Mira el número que enseña el otro móvil. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden».';

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
      'Cada móvil se conecta otra vez con «Conectar otro móvil» y comparando un número.';

  @override
  String pairingV2ClaimTitle(String name) {
    return 'Este móvil dice ser de $name';
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
      'Para conectar otro móvil, esta familia pasa a la sincronización nueva, más segura. No se puede deshacer: los móviles que ya estaban conectados dejan de recibir los cambios de este hasta que los vuelvas a conectar, uno a uno, con «Conectar otro móvil». No se pierde nada.';

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
  String get devicesPeerFrozen => 'Congelado: espera aprobación';

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
  String get deviceStatusFrozen => 'Congelado';

  @override
  String get deviceStatusReconfirm => 'Falta confirmar de quién es';

  @override
  String get deviceDetailSelfNote =>
      'Este es tu móvil. Para dejar de sincronizarlo, usa «Dejar de sincronizar» en «Más opciones».';

  @override
  String get deviceRemoveTitle => 'Quitar este móvil';

  @override
  String get deviceRemoveHint => 'Deja de recibir la lista nueva.';

  @override
  String get deviceRemoveConfirmTitle => '¿Quitar este móvil?';

  @override
  String get deviceRemoveConfirmBody =>
      'Deja de recibir los cambios nuevos al momento. Lo que ya tiene guardado no se le puede borrar. Lo que solo estaba en ese móvil puede perderse. No se puede deshacer.';

  @override
  String get deviceRemoveConfirmAction => 'Quitar móvil';

  @override
  String get deviceRemoveWaitTitle => 'Este móvil volverá a esperar aprobación';

  @override
  String get deviceRemoveWaitBody =>
      'El móvil que vas a quitar es el único que aprobó el cambio de persona de este móvil. Si lo quitas, este móvil esperará la aprobación de otro de la familia y, hasta entonces, no abrirá las sorpresas.';

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
      'Ha cambiado de persona. Al aprobarlo, desde ahora podrá avalar a otros móviles de la familia.';

  @override
  String get deviceApproveOrphan =>
      'Dejó de estar enlazado a este móvil. Si lo apruebas, vuelve a recibir las sorpresas que le tocan.';

  @override
  String get deviceApproveDetached =>
      'Este móvil ya no está enlazado a la familia, pero te confirmó a ti. Apruébalo solo si lo conoces.';

  @override
  String get deviceApproveFrozen =>
      'Sus cambios están congelados y no se pueden limpiar los borrados hasta que lo apruebes o lo quites.';

  @override
  String get deviceApprovedSnack => 'Móvil aprobado';

  @override
  String get deviceApproveError => 'No se ha podido aprobar el móvil.';

  @override
  String get deviceChangedNotice => 'Este móvil ha cambiado: revisa de nuevo.';

  @override
  String get deviceRemovedPendingSnack =>
      'Quitado de este móvil. Falta cortar su acceso: se hará en cuanto haya conexión.';

  @override
  String get deviceApproveCanVouch =>
      'Su ficha ha cambiado: al aprobarlo, desde ahora podrá avalar a otros móviles de la familia.';

  @override
  String get webGateConnectTitle => 'Conecta este ordenador';

  @override
  String get webGateConnectIntro =>
      'Se empareja una sola vez con tu móvil. Después solo necesitarás tu PIN.';

  @override
  String get webGateStepOpenApp => 'Abre Gift Huddle en tu móvil.';

  @override
  String get webGateConnectStep2 =>
      'Ve a Móviles de la familia y toca Conectar la web.';

  @override
  String get webGateConnectStep3 => 'Escanea este código.';

  @override
  String get webGateConnectWaiting => 'Esperando al móvil…';

  @override
  String get webGateCompareTitle => 'Comprueba el código';

  @override
  String get webGateCompareLabel => 'Código de verificación';

  @override
  String get webGateCompareBody =>
      'Comprueba que en el móvil sale el mismo código y apruébalo allí.';

  @override
  String get webGateCompareWaiting => 'Esperando a que el móvil lo apruebe…';

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
      'El móvil ha rechazado la conexión. Empieza otra vez si quieres intentarlo de nuevo.';

  @override
  String get webGateFailedNetwork =>
      'No hay conexión con el servidor. Comprueba tu conexión y empieza otra vez.';

  @override
  String get webGateStartAgain => 'Empezar otra vez';

  @override
  String webGateChoosePinTitle(String name) {
    return 'Este ordenador es de $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Elige un PIN o una frase para abrirlo. Te lo pediremos cada vez que entres.';

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
      'Escribe el PIN o la frase de este ordenador.';

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
      'Desbloquéalo desde un móvil. No se ha borrado nada.';

  @override
  String get webGateSuspendedStep2 => 'Ve a Móviles de la familia y toca Web.';

  @override
  String get webGateSuspendedStep3 => 'Toca Permitir desbloquear otra vez.';

  @override
  String get webGateRetry => 'Probar otra vez';

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
          'Hay $count cambios sin subir guardados en este ordenador, cifrados.',
      one: 'Hay $count cambio sin subir guardado en este ordenador, cifrado.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Conectar otra vez';

  @override
  String get webGateErase => 'Borrar los datos de este ordenador';

  @override
  String get webGateEraseTitle => '¿Borrar los datos de este ordenador?';

  @override
  String get webGateEraseBody =>
      'Se borra todo lo que Gift Huddle guarda aquí. No se puede deshacer.';

  @override
  String get webGateEraseBodyUnsent =>
      'Se borra todo lo que Gift Huddle guarda aquí, también los cambios sin subir. No se puede deshacer.';

  @override
  String get webGateDamagedTitle => 'Los datos de este ordenador están dañados';

  @override
  String get webGateDamagedBody =>
      'No se pueden leer de forma segura. Para seguir, bórralos y vuelve a conectar este ordenador desde un móvil. Los cambios que no se hubieran subido se perderán.';

  @override
  String get webGateDamagedPhoneHint =>
      'En el móvil, quita la web anterior en Móviles de la familia.';

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
      'El PIN o la frase actual no es correcto.';

  @override
  String get webSettingsChangeFailed =>
      'No se ha podido cambiar. Inténtalo otra vez.';

  @override
  String get webSettingsPinChanged => 'PIN cambiado.';

  @override
  String get webSettingsLockNow => 'Bloquear ahora';

  @override
  String get webSettingsForget => 'Olvidar este ordenador';

  @override
  String get webSettingsForgetHint =>
      'Sale de la familia y borra lo guardado en él.';

  @override
  String get webSettingsForgetTitle => '¿Olvidar este ordenador?';

  @override
  String get webSettingsForgetBody =>
      'Este ordenador saldrá de la familia y se borrará lo que Gift Huddle guarda en él, también los cambios sin subir. En tus móviles no cambia nada. Para volver a usarlo tendrás que conectarlo otra vez.';

  @override
  String get webSettingsForgetConfirm => 'Olvidar';

  @override
  String get webSettingsPersistenceDenied =>
      'El navegador podría borrar los datos de este ordenador si le falta espacio.';

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
      'Si tu móvil no mostró el mismo código, no sigas: toca Empezar otra vez.';

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
          'Hubo $count intentos fallidos de desbloquear este ordenador desde la última vez. Si no fuiste tú, cambia el PIN.',
      one:
          'Hubo $count intento fallido de desbloquear este ordenador desde la última vez. Si no fuiste tú, cambia el PIN.',
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
      'Elige quién lo va a usar. El ordenador se conectará como suyo.';

  @override
  String get connectWebNoPeople =>
      'Todavía no hay personas. Añade una persona antes de conectar la web.';

  @override
  String get connectWebWaiting => 'Esperando a que el ordenador responda…';

  @override
  String get connectWebCompareBody =>
      'El ordenador enseña un código. Tiene que ser el mismo que este. Si lo es, pulsa «Coinciden»; si no, «No coinciden».';

  @override
  String get connectWebApproving => 'Dando acceso al ordenador…';

  @override
  String get connectWebDoneTitle => 'Ordenador conectado';

  @override
  String get connectWebDoneBody =>
      'En el ordenador, elige un PIN para abrir Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'Este código ya no vale. En el ordenador, toca Empezar otra vez y escanea el nuevo.';

  @override
  String get connectWebScanAgain => 'Escanear otro código';

  @override
  String get connectWebFailed =>
      'No se ha podido conectar el ordenador. En el ordenador, toca Empezar otra vez y escanea el nuevo código.';

  @override
  String get connectWebCancelled =>
      'Se ha cancelado y el código ya no sirve. En el ordenador, toca Empezar otra vez.';

  @override
  String get deviceWebResume => 'Permitir desbloquear otra vez';

  @override
  String get deviceWebResumeHint =>
      'Si el ordenador se suspendió por demasiados intentos de PIN. No se borra nada.';

  @override
  String get deviceWebResumeTitle => '¿Permitir desbloquear otra vez?';

  @override
  String get deviceWebResumeBody =>
      'Este ordenador volverá a aceptar intentos de PIN. Hazlo solo si ha sido su dueño quien se ha equivocado.';

  @override
  String get deviceWebResumeConfirm => 'Permitir';

  @override
  String get deviceWebResumeDone =>
      'Listo. El ordenador ya puede volver a desbloquearse.';

  @override
  String get deviceWebResumeError =>
      'No se ha podido. Comprueba la conexión e inténtalo otra vez.';

  @override
  String get deviceRemoveWebTitle => 'Quitar esta web';

  @override
  String get deviceRemoveWebHint =>
      'Este ordenador deja de recibir la lista nueva.';

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
      'Quitada de este móvil. Falta cortar su acceso: se hará en cuanto haya conexión.';

  @override
  String get deviceRemoveWebError =>
      'No se ha podido quitar la web. Inténtalo de nuevo con conexión.';

  @override
  String get webSyncSaved => 'Guardado';

  @override
  String get webSyncOffline => 'Sin conexión';

  @override
  String get webSyncAwaitingConfirm =>
      'Este ordenador espera a que un móvil lo confirme';

  @override
  String get webOperationUnavailable =>
      'Esto no se puede hacer desde el ordenador. Hazlo desde un móvil.';

  @override
  String get selfChangeConfirmTitle => '¿Cambiar de quién es este móvil?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'Vas a decir que este móvil es de $name. Eso cambia lo que puede ver, no solo el nombre.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'Vas a dejar este móvil sin persona. Eso cambia lo que puede ver, no solo el nombre.';

  @override
  String selfChangeEffectHides(String name) {
    return 'Este móvil dejará de ver los regalos de $name y sus sorpresas.';
  }

  @override
  String get selfChangeEffectNobody =>
      'Este móvil se quedará sin persona asignada y no podrá ver sorpresas mientras siga así.';

  @override
  String get selfChangeEffectWait =>
      'Hasta que otro móvil de la familia lo apruebe, este móvil no verá las sorpresas de nadie.';

  @override
  String get selfChangeEffectReconfirm =>
      'Los móviles que este había aprobado pueden tener que confirmarse otra vez.';

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
      'Ha usado todos los cambios que permite la lista de móviles. Puede volver a conectarse a la familia como un móvil nuevo, en persona, desde otro móvil.';

  @override
  String get selfWaitingHint => 'Esperando aprobación de otro móvil';

  @override
  String get healthRevokedTitle => 'Otro móvil de la familia ha quitado este';

  @override
  String get healthRevokedBody =>
      'Lo que tienes guardado sigue en este móvil, pero ya no se sincroniza. Reintentar no sirve: hay que volver a conectarlo con otro móvil de la familia, en persona.';

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
  String get healthUnbackedTitle => 'Acceso sin respaldo';

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
  String get protectionStatusOff => 'Desactivado';

  @override
  String get protectionStatusRequested => 'Pedido';

  @override
  String get protectionStatusActive => 'Activo';

  @override
  String protectionSheetTitle(String name) {
    return 'Regalos en secreto para $name';
  }

  @override
  String protectionIntro(String name) {
    return 'Con esto activo, el móvil de $name no muestra ningún regalo para $name, ni cuántos hay. El resto de la familia los sigue viendo.';
  }

  @override
  String get protectionEffectOthers =>
      'Los demás móviles de la familia con permiso siguen viéndolos y editándolos.';

  @override
  String protectionEffectKept(String name) {
    return 'Los regalos que el móvil de $name ya recibió antes de activarla no se pueden retirar de él.';
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
    return '¿Desactivar los regalos en secreto de $name?';
  }

  @override
  String protectionDeactivateBody(String name) {
    return 'Se publicarán todos los regalos disponibles de $name, de cualquier año, también los que están pendientes en este móvil. Después $name los verá en su móvil.';
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
    return 'Este móvil no tiene permiso para los regalos en secreto de $name. Pide ayuda a otro móvil de la familia con permiso.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'Este móvil es de $name: aquí no se pueden crear ni ver sus regalos mientras estén en secreto.';
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
    return 'Los regalos en secreto de $name han llegado al límite. Borra alguno para poder añadir más.';
  }

  @override
  String protectionReason_giftTooLarge(String name) {
    return 'Este regalo es demasiado grande para guardarlo en secreto. Acorta las notas.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'Este móvil ya no tiene sitio para guardar más regalos en secreto. Pide a otro móvil con permiso que los añada.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'Ahora mismo no cabe más en los regalos en secreto de la familia.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Los regalos en secreto necesitan que este móvil esté conectado a la familia con la versión nueva.';
  }

  @override
  String get giftProtectedRejected => 'No se ha guardado el regalo.';

  @override
  String get giftSavedLocally =>
      'Guardado solo en este móvil. Queda pendiente de guardar y compartir.';

  @override
  String get giftSavedLocallyAction => 'Ver pendientes';

  @override
  String get giftOwnRequestRestricted =>
      'Mientras la protección esté activa, este móvil no puede crear ni ver regalos para su propia persona. Pídelo a otra persona de la familia.';

  @override
  String get pendingGiftsTitle => 'Regalos pendientes';

  @override
  String get pendingGiftsIntro =>
      'Estos regalos están guardados cifrados solo en este móvil. Hasta que se guarden y se compartan con la familia, los demás móviles no los ven. Si pierdes este móvil antes, se pierden.';

  @override
  String get pendingGiftsRetry => 'Reintentar';

  @override
  String get pendingGiftsRetrying => 'Reintentando';

  @override
  String get pendingGiftsStill =>
      'Todavía no cabe. No se ha publicado nada y los regalos se conservan en este móvil.';

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
    return '$done de $total comprados';
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
  String get boardOccasionsHint => 'Elige una ocasión para ver su tablero.';

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
  String get boardColStatus => 'Estado';

  @override
  String get boardColGiver => 'Quién regala';

  @override
  String get boardColSize => 'Talla';

  @override
  String get boardRepartoNoGiver => 'Sin quién regala';

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
      'Elige a quién, para qué ocasión y quién lo regala. Con una idea basta.';

  @override
  String get tour2Title => 'Márcalo como comprado';

  @override
  String get tour2Body =>
      'Toca la casilla y el regalo sale de «Pendiente de comprar» y pasa a «por llegar». Si te equivocas, lo deshaces al momento.';

  @override
  String get tour3Title => 'Personas y ocasiones';

  @override
  String get tour3Body =>
      'Cada persona tiene su lista. Navidad, Reyes y cumpleaños la ordenan, y el reparto dice quién paga qué.';

  @override
  String get tour4Title => 'La familia comparte la lista';

  @override
  String get tour4Body =>
      'Conecta otro móvil con un QR, en persona. Todo viaja cifrado y los cambios llegan solos.';

  @override
  String get tour5Title => 'Sorpresas a salvo';

  @override
  String get tour5Body =>
      'El móvil de cada persona no ve sus propios regalos. Con PIN o biometría, sin cuentas ni anuncios.';

  @override
  String get tour6Title => 'También en el ordenador';

  @override
  String get tour6Body =>
      'Conecta el navegador una vez y tendrás la lista en una pantalla grande.';

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
  String get tourDemoHidden => 'Regalos ocultos';

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
  String get recoveryUnconfirmedTitle => 'Falta comprobar las palabras';

  @override
  String get recoveryUnconfirmedBody =>
      'El código aún no cuenta como guardado. Continúa para comprobar las palabras. Si ya se mostraron, se creará un código nuevo y el anterior dejará de valer.';

  @override
  String get recoveryValueAttention => 'Revisar';

  @override
  String get recoveryValueTransferred => 'Traspasada';

  @override
  String get recoverySubtitle => 'Para recuperar la lista en un móvil nuevo.';

  @override
  String get recoveryAbsentTitle =>
      'Prepara un código para recuperar la lista si pierdes este móvil';

  @override
  String get recoveryAbsentBody =>
      'Con 24 palabras puedes recuperar la lista y todo lo que este móvil puede ver en otro móvil. Si solo tienes este móvil, se activa una copia cifrada en el servidor: sin las palabras, nadie puede leerla.';

  @override
  String get recoveryAbsentWarn =>
      'Quien tenga las palabras puede entrar como este móvil. No recuperan lo que nunca se llegó a sincronizar.';

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
  String get recoveryChangeHint => 'El anterior dejará de valer.';

  @override
  String get recoveryRemove => 'Quitar el código';

  @override
  String get recoveryRemoveHint =>
      'Las palabras dejarán de valer y se borra la copia.';

  @override
  String get recoveryRemoveTitle => '¿Quitar el código de recuperación?';

  @override
  String get recoveryRemoveBody =>
      'Se borra la copia de recuperación y las 24 palabras dejan de valer. Podrás crear otro código cuando quieras.';

  @override
  String get recoveryRemoveSoloNote =>
      'Como no hay otro móvil ni la web conectados, también se borra la copia cifrada de la lista del servidor y la lista vuelve a estar solo en este móvil.';

  @override
  String get recoveryRemoveConfirm => 'Quitar código';

  @override
  String get recoveryRemoved => 'Código quitado';

  @override
  String get recoveryRetry => 'Reintentar';

  @override
  String get recoveryIntroTitle => 'Crear el código';

  @override
  String get recoveryRotateTitle => 'Cambiar el código';

  @override
  String get recoveryIntroBody =>
      'Verás 24 palabras. Con ellas puedes recuperar la lista y todo lo que este móvil puede ver en otro móvil.';

  @override
  String get recoveryRotateBody =>
      'Se creará un código nuevo. El anterior dejará de valer cuando el nuevo esté preparado.';

  @override
  String get recoveryPoint1 =>
      'Apúntalas en papel o guárdalas en un gestor de contraseñas.';

  @override
  String get recoveryPoint2 => 'Quien las tenga puede entrar como este móvil.';

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
      'Quien tenga estas palabras puede entrar como este móvil. No hagas captura ni las envíes por mensaje.';

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
      'Si pierdes este móvil, podrás recuperar la lista con las 24 palabras.';

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
      'No se ha podido llegar al servidor. Comprueba la conexión y reintenta; lo hecho hasta ahora se conserva.';

  @override
  String get recoveryProblemWrongTitle => 'Ese código no abre ninguna lista';

  @override
  String get recoveryProblemWrongBody =>
      'Revisa las palabras o prueba con otro código. Si lo cambiaron, usa el más reciente.';

  @override
  String get recoveryProblemRetiredTitle => 'Ese código ya no vale';

  @override
  String get recoveryProblemRetiredBody =>
      'Se cambió o se quitó desde otro móvil. Busca el código más reciente.';

  @override
  String get recoveryProblemRemovedTitle =>
      'Este móvil ya no está en la familia';

  @override
  String get recoveryProblemRemovedBody =>
      'Se quitó este móvil de la lista, así que no se puede recuperar con este código.';

  @override
  String get recoveryProblemIncompleteTitle =>
      'La recuperación se quedó a medias';

  @override
  String get recoveryProblemIncompleteBody =>
      'Falta una parte de la lista. Lo descargado se conserva. Vuelve a intentarlo con conexión o, si tienes otro móvil conectado a esta familia, abre allí la app un momento.';

  @override
  String get recoveryProblemBusyTitle => 'Hay otra operación en marcha';

  @override
  String get recoveryProblemBusyBody => 'Espera un momento y reintenta.';

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
      'No se ha podido terminar. Reintenta; si sigue igual, prueba más tarde.';

  @override
  String get obHaveRecoveryCode => 'Tengo un código de recuperación';

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
    return 'La palabra $number no está en la lista.';
  }

  @override
  String get recoverChecksum =>
      'Las palabras no forman un código válido. Revisa el orden y que no falte ninguna.';

  @override
  String get recoverPasteEmpty => 'No hay nada copiado.';

  @override
  String get recoverPasteWrong => 'Lo copiado no tiene 24 palabras.';

  @override
  String get recoverQrWrong => 'Ese QR no es un código de recuperación.';

  @override
  String get recoverScanTitle => 'Escanear el QR del código';

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
  String get recoverStepInstall => 'Instalando en este móvil';

  @override
  String get recoverDoneTitle => 'Lista recuperada';

  @override
  String recoverDoneSelf(String name) {
    return 'Este móvil es de $name.';
  }

  @override
  String get recoverDoneNoSelf =>
      'Este móvil no tiene persona asignada. Puedes elegirla en Ajustes.';

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
  String get transferredTitle => 'Esta lista se ha pasado a otro móvil';

  @override
  String get transferredBody =>
      'Tu lista ahora está en otro móvil o en otra app, y esta app ya no se usa para ella. Lo que ves aquí es una copia de solo lectura: no se ha borrado nada.';

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
      'No se ha podido dejar la copia cifrada en el servidor, así que no se enseñan las palabras. Reintenta con conexión.';

  @override
  String get recoverReplaceTitle => '¿Sustituir la lista de este móvil?';

  @override
  String get recoverReplaceBody =>
      'Este código es de otra familia. Si continúas, la lista de esa familia sustituirá a la que tienes en este móvil. La lista anterior se conserva en el móvil, pero deja de verse.';

  @override
  String get recoverReplaceConfirm => 'Sustituir';

  @override
  String get recoverAbandon => 'Cancelar la recuperación';

  @override
  String get recoverAbandonTitle => '¿Cancelar la recuperación?';

  @override
  String get recoverAbandonBody =>
      'Se descartan los datos temporales de esta recuperación en este móvil. Cancelar no reactiva el móvil anterior si ya quedó en solo lectura. Podrás volver a introducir el código.';

  @override
  String get recoverAbandonConfirm => 'Cancelar recuperación';

  @override
  String get recoverAbandonKeep => 'Seguir';

  @override
  String get recoverAbandonFailed =>
      'No se ha podido cancelar. Reintenta en un momento.';

  @override
  String get recoverAbandonBodyClaimed =>
      'La lista ya se ha pasado a este código y el otro móvil se ha quedado en solo lectura; cancelar no lo deshace. Para usarla tendrás que escribir el código otra vez.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'Este móvil no puede bloquear las capturas de pantalla: no hagas ninguna.';

  @override
  String get recoverLeaveTitle => '¿Salir de la recuperación?';

  @override
  String get recoverLeaveBody =>
      'Se queda a medias en este móvil. Podrás reanudarla o cancelarla desde la pantalla de bienvenida.';

  @override
  String get recoverPendingTitle => 'Hay una recuperación en curso';

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
      'Escribe tu PIN para quitar el código.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirma que quieres quitar el código de recuperación';

  @override
  String get transferredRecover => 'Recuperar con mi código';

  @override
  String get transferredErase => 'Borrar todo de este móvil';

  @override
  String get recoverStepDoneValue => 'hecho';

  @override
  String get recoverStepActiveValue => 'en curso';
}

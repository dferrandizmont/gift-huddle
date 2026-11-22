// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Catalan Valencian (`ca`).
class AppLocalizationsCa extends AppLocalizations {
  AppLocalizationsCa([String locale = 'ca']) : super(locale);

  @override
  String get appTitle => 'Gift Huddle';

  @override
  String get navMainLabel => 'Navegació principal';

  @override
  String get navPeople => 'Persones';

  @override
  String get navFamily => 'Repartiment';

  @override
  String get navFamilyShort => 'Repartiment';

  @override
  String get navOccasions => 'Ocasions';

  @override
  String get navSettings => 'Ajustos';

  @override
  String get emptyPeopleTitle => 'Encara no hi ha persones';

  @override
  String get emptyPeopleMessage =>
      'Afegeix les persones a qui regaleu per començar les seves llistes de regals.';

  @override
  String get emptyFamilyTitle => 'Falten persones';

  @override
  String get emptyFamilyMessage =>
      'Per veure el repartiment, cal que hi hagi algú que faci regals i algú que en rebi.';

  @override
  String get emptyOccasionsTitle => 'Sense ocasions';

  @override
  String get emptyOccasionsMessage =>
      'Nadal, aniversaris i altres dates apareixeran aquí amb el compte enrere.';

  @override
  String backTo(String title) {
    return 'Tornar a $title';
  }

  @override
  String get settingsAppearance => 'Aparença';

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
  String get appearanceColorGroup => 'Color de l\'app';

  @override
  String get appearanceThemeSection => 'Tema';

  @override
  String get appearanceThemeGroup => 'Tema clar o fosc';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Clar';

  @override
  String get themeDark => 'Fosc';

  @override
  String get appearanceOccasionTitle => 'Temes d\'ocasió (Nadal, aniversari)';

  @override
  String get appearanceOccasionHint =>
      'El color i la capçalera de la llista canvien segons l\'ocasió.';

  @override
  String get appearanceHapticsTitle => 'Vibracions';

  @override
  String get appearanceHapticsHint =>
      'Desactiva aquesta opció per desactivar totes les vibracions de l\'app, incloses les que notes quan marques una casella, elimines un regal o introdueixes un PIN incorrecte.';

  @override
  String get appearancePreview => 'Vista prèvia';

  @override
  String get accentLavender => 'Lavanda';

  @override
  String get accentSage => 'Sàlvia';

  @override
  String get accentPeach => 'Préssec';

  @override
  String get accentSky => 'Cel';

  @override
  String get accentRose => 'Rosa';

  @override
  String get accentButter => 'Mantega';

  @override
  String get statusIdea => 'Idea';

  @override
  String get statusDecided => 'Decidit';

  @override
  String get statusBought => 'Comprat';

  @override
  String get statusArrived => 'Ha arribat';

  @override
  String get statusWrapped => 'Embolicat';

  @override
  String get statusDelivered => 'Lliurat';

  @override
  String statusCheckboxLabel(String item, String status) {
    return 'Canviar l\'estat de $item. Estat actual: $status';
  }

  @override
  String statusReadOnlyLabel(String status) {
    return 'Estat: $status';
  }

  @override
  String get giverUnassigned => 'Sense assignar';

  @override
  String countdownDaysFor(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dies per a $name',
      one: 'dia per a $name',
    );
    return '$_temp0';
  }

  @override
  String todayIs(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Avui és $dateString';
  }

  @override
  String get previewGiftName => 'Parc de bombers de blocs';

  @override
  String get previewGiver => 'Nosaltres';

  @override
  String get previewOccasion => 'Reis';

  @override
  String get shareEnvelopeText =>
      'Obre el fitxer amb Gift Huddle per veure els canvis a la llista.';

  @override
  String get occasionNameTio => 'Tió';

  @override
  String get occasionNameSanta => 'Nadal';

  @override
  String get occasionNameKings => 'Reis';

  @override
  String occasionBirthdayOf(String name) {
    return 'Aniversari de $name';
  }

  @override
  String get shareErrorNotEnvelope =>
      'Aquest fitxer o text no és un enviament de Gift Huddle.';

  @override
  String get shareErrorWrongList =>
      'Aquest enviament és d\'una altra família. Connecta els mòbils amb el codi QR.';

  @override
  String get shareErrorAuth =>
      'No es pot obrir aquest enviament. Pot estar malmès o ser d\'una altra família.';

  @override
  String get shareErrorTooLarge => 'Aquest enviament és massa gran.';

  @override
  String get shareErrorNoFamily =>
      'Primer crea la teva família o uneix-te a una amb el codi QR.';

  @override
  String get shareErrorClockDrift =>
      'El rellotge de l\'altre mòbil va avançat. Revisa la data i l\'hora d\'aquell mòbil i torna a enviar la llista des d\'allà.';

  @override
  String get shareErrorLegacyFile =>
      'Aquest fitxer és d\'una versió anterior de Gift Huddle. Desa\'l i demana que te n\'enviïn un de nou creat amb l\'app actualitzada.';

  @override
  String get shareErrorNotReady =>
      'Aquest mòbil encara no està al dia amb la família. Sincronitza i torna-ho a provar.';

  @override
  String get shareErrorGeneration =>
      'Aquest fitxer és d\'una versió anterior de la llista. Demana que te n\'enviïn un de nou.';

  @override
  String get shareErrorRevokedWriter =>
      'Aquest fitxer el va desar un mòbil que ja no és de la família. No s\'hi ha afegit res.';

  @override
  String get shareErrorMissingKey =>
      'Encara no es pot obrir aquest fitxer. S\'ha desat i es tornarà a provar quan sincronitzis.';

  @override
  String get shareErrorSyncAndReopen =>
      'Encara no es pot obrir aquest fitxer. Sincronitza i torna\'l a obrir.';

  @override
  String get shareErrorNotAllowed =>
      'Aquest mòbil encara no pot desar còpies. Primer l\'ha d\'aprovar un altre mòbil de la família.';

  @override
  String get pairErrorInvalidCode => 'Aquest codi QR no és de Gift Huddle.';

  @override
  String get lockEnterPin => 'Introdueix el teu PIN';

  @override
  String lockPinProgress(int count, int total) {
    return 'PIN: $count de $total dígits';
  }

  @override
  String get lockUnlock => 'Desbloquejar';

  @override
  String get lockBackspace => 'Esborrar';

  @override
  String get lockBiometric => 'Fer servir l\'empremta o el rostre';

  @override
  String get lockBiometricReason => 'Desbloqueja Gift Huddle';

  @override
  String get lockBiometricNotice =>
      'Qualsevol empremta o cara registrada al mòbil podrà obrir l\'app.';

  @override
  String lockBiometricNamed(String name) {
    return 'Fer servir $name';
  }

  @override
  String lockBiometricHintNamed(String name) {
    return 'Toca el botó de $name per desbloquejar l\'app';
  }

  @override
  String get lockBiometricNoticeFace =>
      'Qualsevol persona que tingui la cara registrada a Face ID podrà obrir l\'app.';

  @override
  String get lockBiometricNoticeTouch =>
      'Qualsevol persona que tingui una empremta registrada a Touch ID podrà obrir l\'app.';

  @override
  String pinBiometricOfferTitleNamed(String name) {
    return 'Vols activar $name?';
  }

  @override
  String get securityBiometricsUnavailableIos =>
      'Aquest mòbil no té Face ID ni Touch ID configurats.';

  @override
  String securityBiometricsFailedNamed(String name) {
    return 'No s\'ha pogut activar. Comprova que $name estigui configurat a la Configuració del mòbil.';
  }

  @override
  String get giftDiscardTitle => 'Vols descartar els canvis?';

  @override
  String get giftDiscardBody =>
      'Els canvis d\'aquest regal encara no s\'han desat.';

  @override
  String get actionDiscard => 'Descartar';

  @override
  String get giftKeepEditing => 'Continuar editant';

  @override
  String get lockLoadError => 'No s\'ha pogut comprovar el bloqueig.';

  @override
  String get lockRetry => 'Reintentar';

  @override
  String lockWrongPin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Queden $count intents',
      one: 'Queda $count intent',
    );
    return 'PIN incorrecte. $_temp0 abans d\'haver d\'esperar.';
  }

  @override
  String get lockWrongPinNow => 'PIN incorrecte.';

  @override
  String lockWait(String time) {
    return 'Massa intents. Torna-ho a provar d\'aquí a $time.';
  }

  @override
  String get pinSetupTitle => 'Crea un PIN';

  @override
  String get pinSetupMessage =>
      'De 4 a 6 dígits. Protegeix la teva llista en aquest mòbil.';

  @override
  String get pinConfirmTitle => 'Repeteix el PIN';

  @override
  String get pinMismatch => 'Els PIN no coincideixen. Torna-ho a provar.';

  @override
  String get pinContinue => 'Continuar';

  @override
  String get pinSave => 'Desar el PIN';

  @override
  String get pinSkip => 'Ara no';

  @override
  String get pinBiometricOfferTitle => 'Vols activar l\'empremta o el rostre?';

  @override
  String get pinBiometricOfferEnable => 'Activar';

  @override
  String get actionSave => 'Desar';

  @override
  String get actionCancel => 'Cancel·lar';

  @override
  String get actionDelete => 'Esborrar';

  @override
  String get actionNext => 'Següent';

  @override
  String get actionBack => 'Enrere';

  @override
  String get actionEdit => 'Editar';

  @override
  String get actionClose => 'Tancar';

  @override
  String get actionDone => 'Fet';

  @override
  String get actionArchive => 'Arxivar';

  @override
  String get actionRestore => 'Recuperar';

  @override
  String get actionUndo => 'Desfer';

  @override
  String get fieldName => 'Nom';

  @override
  String get fieldNameRequired => 'Escriu un nom.';

  @override
  String get fieldFor => 'Per a qui';

  @override
  String get fieldGiver => 'Qui regala';

  @override
  String get fieldOccasion => 'Ocasió';

  @override
  String get fieldStatus => 'Estat';

  @override
  String giftCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals',
      one: '$count regal',
      zero: 'Cap regal',
    );
    return '$_temp0';
  }

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anys',
      one: '$count any',
    );
    return '$_temp0';
  }

  @override
  String get deviceNameDefault => 'El meu mòbil';

  @override
  String get giverUs => 'Nosaltres';

  @override
  String get giverHouseholdPays => 'Ho paga la casa';

  @override
  String get giverHouseholdPaysHint =>
      'Si ho actives, els seus regals compten al pressupost de la casa.';

  @override
  String countdownDaysForBirthday(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dies perquè $name faci anys',
      one: 'dia perquè $name faci anys',
    );
    return '$_temp0';
  }

  @override
  String onboardingStepOf(int step, int total) {
    return 'Pas $step de $total';
  }

  @override
  String get obWelcomeTitle => 'Et donem la benvinguda a Gift Huddle';

  @override
  String get obWelcomeBody =>
      'Apunta qui regala què i a qui. Així ningú repeteix regal i ningú es queda sense el seu.';

  @override
  String get obWelcomePrivacy =>
      'Sense comptes. Si sincronitzeu dos mòbils, la llista viatja xifrada i només els vostres mòbils la poden llegir.';

  @override
  String get obDeviceNameLabel => 'Nom d\'aquest mòbil';

  @override
  String get obDeviceNameHint =>
      'Aquest nom apareixerà a l\'altre mòbil. El pots canviar.';

  @override
  String get obStart => 'Començar';

  @override
  String get obHaveListTitle => 'Ja teniu una llista?';

  @override
  String get obPeopleTitle => 'A qui regaleu?';

  @override
  String get obPeopleBody =>
      'Afegeix les persones a qui regaleu: parella, germans, nebots, nens… En cal almenys una.';

  @override
  String get obPeopleAdd => 'Afegir una persona';

  @override
  String get obPeopleNeedOne => 'Afegeix almenys una persona per continuar.';

  @override
  String obRemove(String name) {
    return 'Treure $name';
  }

  @override
  String get obGiversTitle => 'Qui regala?';

  @override
  String get obGiversBody =>
      '«Nosaltres» ja és a la llista per als regals que pagueu a casa. També hi pots afegir els avis, els oncles…';

  @override
  String get obGiversSuggestions => 'Suggeriments';

  @override
  String get obGiverGrandparents => 'Avis';

  @override
  String get obGiverUncles => 'Oncles';

  @override
  String get obGiverFriends => 'Amics';

  @override
  String obAddNamed(String name) {
    return 'Afegir $name';
  }

  @override
  String get giverNew => 'Afegir qui regala';

  @override
  String get giverEdit => 'Editar qui regala';

  @override
  String get giverNameHint => 'Avis, Tia Nora i Leo…';

  @override
  String get obOccasionsTitle => 'Quan hi ha regals?';

  @override
  String get obOccasionsBody =>
      'Tria quan feu regals. Si indiques la data de naixement d\'algú, n\'apareixerà l\'aniversari.';

  @override
  String get obBirthdaysSection => 'Aniversaris (es creen sols)';

  @override
  String get obNoBirthdays =>
      'Si afegeixes la data de naixement d\'algú, el seu aniversari apareixerà aquí.';

  @override
  String get obOtherOccasions => 'Altres dates';

  @override
  String get obAddOccasion => 'Afegir una altra data';

  @override
  String get obPinTitle => 'Bloqueja l\'app';

  @override
  String get obPinBody =>
      'Crea un PIN perquè ningú vegi els regals si agafa el mòbil. Podràs canviar-lo als Ajustos.';

  @override
  String get obPinCreate => 'Crear un PIN';

  @override
  String get obFinishing => 'Preparant la teva llista…';

  @override
  String get obSaveError => 'No s\'ha pogut desar. Torna-ho a provar.';

  @override
  String get personNew => 'Nova persona';

  @override
  String get personEdit => 'Editar la persona';

  @override
  String get personColor => 'Color';

  @override
  String get personRelation => 'Relació (opcional)';

  @override
  String get personRelationHint => 'Parella, germà, neboda…';

  @override
  String get personBirthday => 'Aniversari (opcional)';

  @override
  String get personBirthdayPick => 'Triar data';

  @override
  String get personBirthdayNone => 'Sense data';

  @override
  String get personBirthdayClear => 'Treure la data';

  @override
  String get personBirthdayNoYear => 'No desar l\'any';

  @override
  String personPendingBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'en falten $count per comprar',
      one: 'en falta $count per comprar',
    );
    return '$_temp0';
  }

  @override
  String get personAllBought => 'tot comprat';

  @override
  String get giftAdd => 'Afegir un regal';

  @override
  String get giftNoOccasion => 'Sense ocasió';

  @override
  String giftsEmptyTitle(String name) {
    return 'Encara no hi ha regals per a $name';
  }

  @override
  String get giftsEmptyMessage =>
      'Apunta una idea, encara que no sàpigues què comprar.';

  @override
  String get giftTagSurprise => 'Sorpresa';

  @override
  String get giftTagRequest => 'Encàrrec';

  @override
  String giftRequestedBy(String name) {
    return 'L\'ha demanat $name';
  }

  @override
  String giftSizeLine(String size) {
    return 'Talla o edat: $size';
  }

  @override
  String giftPriceActualPlanned(String actual, String planned) {
    return '$actual (previst $planned)';
  }

  @override
  String giftStatusChanged(String item, String status) {
    return '$item: $status';
  }

  @override
  String giftStatusPickerTitle(String item) {
    return 'Estat de $item';
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
    return 'Gastat: $spent de $planned';
  }

  @override
  String get filtersButton => 'Filtres';

  @override
  String get filtersSheetTitle => 'Filtrar regals';

  @override
  String get filterAnyOccasion => 'Totes';

  @override
  String get filterAnyGiver => 'Tots';

  @override
  String get filterAnyStatus => 'Tots';

  @override
  String get filterNeedsBuy => 'Falta comprar';

  @override
  String get filterNeedsWrap => 'Falta embolicar';

  @override
  String filterRemove(String name) {
    return 'Treure el filtre $name';
  }

  @override
  String get filterClear => 'Treure els filtres';

  @override
  String get filterNoResults => 'Cap regal coincideix amb els filtres.';

  @override
  String get giftEditorNewTitle => 'Nou regal';

  @override
  String get giftEditorEditTitle => 'Editar el regal';

  @override
  String get giftEditorNoPeople =>
      'Afegeix primer la persona que rebrà el regal.';

  @override
  String get giftRecipientRequired => 'Tria per a qui és el regal.';

  @override
  String giftAddedNotice(String name) {
    return 'Regal afegit a la llista de $name';
  }

  @override
  String get giftAddedView => 'Veure';

  @override
  String get giftFieldTitle => 'Regal';

  @override
  String get giftFieldTitleHint => 'Pijama d\'astronautes, talla 8';

  @override
  String get giftFieldTitleRequired => 'Escriu quin regal és.';

  @override
  String get giftPriceSection => 'Preu';

  @override
  String get giftFieldPlanned => 'Previst';

  @override
  String get giftFieldActual => 'Real';

  @override
  String get giftPriceInvalid => 'Escriu un import, per exemple 12,50.';

  @override
  String get giftFieldStore => 'Botiga';

  @override
  String get giftFieldUrl => 'Enllaç';

  @override
  String get giftLinkOpen => 'Obrir l\'enllaç';

  @override
  String get giftLinkCopied =>
      'No s\'ha pogut obrir el navegador. Enllaç copiat.';

  @override
  String get giftFieldNote => 'Nota';

  @override
  String get giftFieldSize => 'Talla o edat';

  @override
  String get giftRequestSwitch => 'És un encàrrec: l\'ha demanat algú';

  @override
  String get giftRequestedByField => 'Qui l\'ha demanat';

  @override
  String get giftRequestedByOther => 'Una altra persona…';

  @override
  String get giftRequestedByName => 'Nom de qui l\'ha demanat';

  @override
  String get giftRequestNote => 'Nota de l\'encàrrec';

  @override
  String get giftSurpriseSwitch => 'És una sorpresa';

  @override
  String get giftSurpriseHint =>
      'Es marca perquè ningú en parli davant de qui el rep.';

  @override
  String get giftDelete => 'Eliminar el regal';

  @override
  String confirmDeleteTitle(String name) {
    return 'Eliminar «$name»?';
  }

  @override
  String get confirmDeleteBody =>
      'S\'elimina també als mòbils de la teva família.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done de $total comprats';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Tot comprat per a $occasion';
  }

  @override
  String get giftSaveError =>
      'No s\'ha pogut desar el regal. Torna-ho a provar.';

  @override
  String get giftDuplicateTitle => 'Possible duplicat';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return 'Pot ser que aquest regal ja sigui a la llista de $person amb el nom «$title». Qui regala: $giver.';
  }

  @override
  String get giftDuplicateSave => 'Desar igualment';

  @override
  String get giftDuplicateReview => 'Revisar';

  @override
  String get familySubtitle => 'Qui regala què a cada persona';

  @override
  String get familyGiverHeader => 'Regala';

  @override
  String get familyNoPrice => 'Sense preu';

  @override
  String get familyNothingYet => 'Res encara';

  @override
  String get familyLegendAllBought => 'Tot comprat';

  @override
  String get familyLegendPending => 'Alguna cosa pendent';

  @override
  String get familyLegendDuplicate => 'Possible duplicat';

  @override
  String familyCellLabel(
    String giver,
    String person,
    String gifts,
    String price,
    String state,
  ) {
    return '$giver per a $person: $gifts, $price, $state';
  }

  @override
  String familyCellEmptyLabel(String giver, String person) {
    return '$giver per a $person: encara res, afegir un regal';
  }

  @override
  String familyDuplicateBanner(String person, String title) {
    return 'Possible duplicat: «$title» per a $person';
  }

  @override
  String familyDuplicateMore(int count) {
    return 'i $count més';
  }

  @override
  String get occasionNew => 'Nova ocasió';

  @override
  String get occasionEdit => 'Editar l\'ocasió';

  @override
  String get occasionNameHint => 'Comunió, final de curs…';

  @override
  String get occasionDate => 'Data';

  @override
  String get occasionDatePick => 'Triar una data';

  @override
  String get occasionDateRequired => 'Tria una data.';

  @override
  String get occasionRepeats => 'Es repeteix cada any';

  @override
  String get occasionBirthdayDateHint =>
      'La data surt de l\'aniversari de la persona.';

  @override
  String occasionDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Falten $count dies',
      one: 'Falta $count dia',
      zero: 'Avui',
    );
    return '$_temp0';
  }

  @override
  String get occasionPassed => 'Ja ha passat';

  @override
  String get budgetCardTitle => 'Pressupost de la casa';

  @override
  String get budgetCardHint => 'Pressupost, gastat i el que queda';

  @override
  String get occasionPeopleSection => 'Per persona';

  @override
  String get occasionToWrap => 'per embolicar';

  @override
  String get occasionToArrive => 'per arribar';

  @override
  String get occasionNoGifts => 'Encara no hi ha regals per a aquesta ocasió.';

  @override
  String get occasionNoGiftsYet => 'Encara no hi ha regals';

  @override
  String occasionSplitLabel(String name, String parts) {
    return 'Regals per a $name per ocasió: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Pendent de comprar';

  @override
  String get occasionPendingEmpty =>
      'No hi ha compres pendents. Aquí veuràs els regals amb l\'estat «Decidit», agrupats per botiga.';

  @override
  String get occasionStoreNone => 'Sense botiga';

  @override
  String occasionMarkBought(String item) {
    return 'Marcar com a comprat: $item';
  }

  @override
  String get occasionIdeasSection => 'Idees';

  @override
  String get budgetTitle => 'Pressupost';

  @override
  String get budgetSubtitle =>
      'Pots posar un pressupost a cada ocasió. «Gastat» suma els preus reals dels regals que paga la casa. Si ja s\'ha comprat un regal i hi falta el preu real, compta el previst.';

  @override
  String get budgetSubtitleBudgeted =>
      'Pots posar un pressupost a cada ocasió. Les tres xifres només inclouen ocasions amb pressupost. «Gastat» suma els preus reals dels regals que paga la casa. Si ja s\'ha comprat un regal i hi falta el preu real, compta el previst.';

  @override
  String get budgetPlanned => 'Previst';

  @override
  String get budgetSpent => 'Gastat';

  @override
  String get budgetLeft => 'Disponible';

  @override
  String get budgetOver => 'Et passes';

  @override
  String get budgetByPerson => 'Per persona';

  @override
  String get budgetByOccasion => 'Per ocasió';

  @override
  String get budgetNote =>
      'Només suma el que paga la casa. Els regals que paguen altres persones, com ara els avis, queden fora de la despesa de la casa.';

  @override
  String get budgetEmpty =>
      'Encara no hi ha regals que pagui la casa. Activa «Ho paga la casa» a la fitxa de qui regala i posa el preu previst al regal.';

  @override
  String get occasionBudgetField => 'Pressupost (opcional)';

  @override
  String get occasionBudgetHint =>
      'El que vols gastar en aquesta ocasió. Deixa-ho buit si no hi ha pressupost.';

  @override
  String get budgetFigure => 'Pressupost';

  @override
  String get budgetNone => 'Sense pressupost';

  @override
  String get budgetSetAction => 'Posar pressupost';

  @override
  String get budgetEditAction => 'Canviar pressupost';

  @override
  String budgetSetFor(String name) {
    return 'Posar pressupost a $name';
  }

  @override
  String budgetEditFor(String name) {
    return 'Canviar el pressupost de $name';
  }

  @override
  String budgetLeftIfBought(String amount) {
    return 'Si compres el que falta, et quedaràs amb $amount';
  }

  @override
  String budgetSpentOutside(String amount) {
    return 'A més, la casa ha gastat $amount fora de les ocasions amb pressupost.';
  }

  @override
  String budgetOverIfBought(String amount) {
    return 'Si compres el que falta, et passaràs $amount';
  }

  @override
  String budgetSheetTitle(String name) {
    return 'Pressupost de $name';
  }

  @override
  String get budgetSheetHint => 'Deixa-ho buit per treure el pressupost.';

  @override
  String get budgetOpenGifts => 'Veure regals';

  @override
  String get budgetArchivedTag => 'Arxivada · no suma';

  @override
  String get budgetCreateOccasion => 'Crear ocasió';

  @override
  String get settingsGivers => 'Qui regala';

  @override
  String get settingsSecurity => 'Bloqueig';

  @override
  String get settingsShare => 'Mòbils de la família';

  @override
  String get settingsAbout => 'Quant a';

  @override
  String aboutVersion(String version) {
    return 'Versió $version';
  }

  @override
  String get aboutPrivacy =>
      'Sense comptes ni publicitat. La llista només surt del teu mòbil si connectes un altre mòbil o la web, crees un codi de recuperació o envies una còpia. Sempre va xifrada.';

  @override
  String get aboutPrivacyPolicy => 'Política de privadesa';

  @override
  String get aboutPrivacyPolicyHint => 'S\'obre al navegador.';

  @override
  String get aboutPrivacyPolicyCopied =>
      'No s\'ha pogut obrir el navegador. Enllaç copiat.';

  @override
  String get aboutSupport => 'Ajuda i suport';

  @override
  String get aboutSupportHint => 'Escriu-nos des de la teva app de correu.';

  @override
  String aboutSupportCopied(String email) {
    return 'No s\'ha pogut obrir el correu. Adreça copiada: $email';
  }

  @override
  String get manageArchiveHint =>
      'Arxivar treu alguna cosa de les llistes sense eliminar-ne els regals; es recupera a Ajustos › Arxiu. Eliminar ho esborra per sempre.';

  @override
  String manageArchiveLabel(String name) {
    return 'Arxivar $name';
  }

  @override
  String manageRestoreLabel(String name) {
    return 'Recuperar $name';
  }

  @override
  String get securityPinTitle => 'Bloqueig amb PIN';

  @override
  String get securityPinHint => 'Demana el PIN en obrir l\'app.';

  @override
  String get securityChangePin => 'Canviar el PIN';

  @override
  String get securityBiometrics => 'Empremta o rostre';

  @override
  String get securityBiometricsHint => 'Obre l\'app sense teclejar el PIN.';

  @override
  String get securityBiometricsUnavailable =>
      'Aquest mòbil no té empremta ni rostre configurats.';

  @override
  String get securityBiometricsFailed =>
      'No s\'ha pogut activar. Comprova que l\'empremta o el rostre estiguin configurats al mòbil.';

  @override
  String get securityDisableTitle => 'Treure el PIN';

  @override
  String get securityDisablePrompt =>
      'Escriu el teu PIN per treure el bloqueig.';

  @override
  String get securityChangeCurrentPrompt => 'Escriu el teu PIN actual.';

  @override
  String get securityPinEnabled => 'PIN activat.';

  @override
  String get securityPinDisabled => 'Bloqueig desactivat.';

  @override
  String get securityPinChanged => 'PIN canviat.';

  @override
  String get securityNote =>
      'Sense PIN, qualsevol que agafi el mòbil pot veure els regals.';

  @override
  String get shareJoinTitle => 'Escanejar el QR';

  @override
  String get sharePasteEmpty =>
      'No hi ha res per enganxar. Copia abans l\'enllaç o el text que t\'han enviat.';

  @override
  String get shareSendError => 'No s\'ha pogut preparar l\'enviament.';

  @override
  String get showQrIntro =>
      'A l\'altre mòbil obre Gift Huddle, toca «Unir-me a una família», després «Escanejar el QR» i apunta la càmera a aquest codi.';

  @override
  String get showQrWarning =>
      'No facis cap captura ni el comparteixis: aquest codi dona accés a tota la llista. Ensenya\'l només en persona.';

  @override
  String get showQrLabel => 'Codi QR per connectar un altre mòbil';

  @override
  String get joinIntro => 'Apunta la càmera al codi QR de l\'altre mòbil.';

  @override
  String get scannerWaitingPermission => 'Esperant el permís de la càmera…';

  @override
  String get scannerDeniedTitle => 'Cal la càmera';

  @override
  String get scannerDeniedBody =>
      'Només es fa servir per llegir el codi QR; no es desa cap imatge.';

  @override
  String get scannerBlockedTitle => 'La càmera està bloquejada';

  @override
  String get scannerBlockedBody =>
      'El permís de càmera està denegat. Activa\'l als ajustos del mòbil per llegir el codi QR.';

  @override
  String get scannerFailedTitle => 'No s\'ha pogut obrir la càmera';

  @override
  String get scannerFailedBody =>
      'El mòbil no ha respost a la petició del permís. Torna-ho a provar.';

  @override
  String get scannerRetry => 'Reintentar';

  @override
  String get scannerOpenSettings => 'Obrir ajustos';

  @override
  String get joinConflictTitle => 'Aquest mòbil ja té una llista';

  @override
  String get joinConflictBody =>
      'Si t\'uneixes a la llista de l\'altre mòbil, perdràs la llista d\'aquest mòbil i els regals que conté.';

  @override
  String get joinReplace => 'Substituir i unir-m\'hi';

  @override
  String get joinDoneTitle => 'Mòbils connectats';

  @override
  String joinDoneBody(String name) {
    return 'Ja ets a la família de $name. Demana-li que t\'enviï els canvis per veure la llista.';
  }

  @override
  String get incomingTitle => 'Canvis rebuts';

  @override
  String get incomingNothing => 'Ja ho tenies tot al dia.';

  @override
  String get incomingOtherChanges => 'S\'han actualitzat persones o ocasions.';

  @override
  String get incomingFailedTitle => 'No s\'ha pogut obrir l\'enviament';

  @override
  String importAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals nous',
      one: '$count regal nou',
    );
    return '$_temp0';
  }

  @override
  String importChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals modificats',
      one: '$count regal modificat',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals eliminats',
      one: '$count regal eliminat',
    );
    return '$_temp0';
  }

  @override
  String get syncNowTitle => 'Sincronitzar ara';

  @override
  String get syncStopTitle => 'Deixar de sincronitzar';

  @override
  String get syncStopHint => 'Aquest mòbil deixa d\'enviar i rebre canvis.';

  @override
  String get syncStopConfirmTitle => 'Vols deixar de sincronitzar?';

  @override
  String get syncStopConfirmBody =>
      'Aquest mòbil deixarà d\'enviar i rebre canvis. Els altres continuaran sincronitzant-se entre ells. Si cap altre mòbil ni la web tenen accés a la llista, s\'esborrarà la còpia xifrada per sincronitzar. Cada mòbil conservarà les seves dades. Per tornar a sincronitzar, connecta de nou aquest mòbil amb un altre de la família.';

  @override
  String get syncStopDone => 'Sincronització apagada.';

  @override
  String get syncStopError =>
      'No s\'ha pogut contactar amb el servidor. Comprova la connexió i torna-ho a provar.';

  @override
  String get syncPrivacyNote =>
      'El servidor guarda la llista xifrada amb una clau que només tenen els vostres mòbils. No veu noms, regals ni preus, però sí quan i des de quina IP es connecta cada mòbil.';

  @override
  String get syncStatusNotConfigured =>
      'La sincronització no està disponible en aquesta versió.';

  @override
  String get syncStatusNoFamily =>
      'Crea la teva família o uneix-te a una per sincronitzar.';

  @override
  String get syncStatusDisabled => 'Apagada';

  @override
  String get syncStatusIdle => 'Pendent de sincronitzar';

  @override
  String get syncStatusWaitingPeer =>
      'La sincronització començarà quan connectis un altre mòbil.';

  @override
  String get peerConnected => 'S\'ha connectat un altre mòbil';

  @override
  String peerConnectedNamed(String name) {
    return 'S\'ha connectat un altre mòbil: $name';
  }

  @override
  String get syncStatusSyncing => 'Sincronitzant…';

  @override
  String get syncStatusSyncedNow => 'Sincronitzat ara';

  @override
  String syncStatusSyncedMinutes(int minutes) {
    return 'Sincronitzat fa $minutes min';
  }

  @override
  String syncStatusSyncedHours(int hours) {
    return 'Sincronitzat fa $hours h';
  }

  @override
  String syncStatusSyncedDays(int days) {
    return 'Sincronitzat fa $days d';
  }

  @override
  String get syncStatusOffline =>
      'No es pot connectar ara. Els canvis s\'enviaran després.';

  @override
  String get syncStatusError => 'No s\'ha pogut sincronitzar';

  @override
  String get syncIssueAuth =>
      'El servidor no accepta la clau d\'aquesta família.';

  @override
  String get syncIssueClockDrift =>
      'El rellotge d\'un altre mòbil va avançat. Revisa la data i l\'hora d\'aquell mòbil.';

  @override
  String get syncIssueTooLarge => 'La llista és massa gran per sincronitzar.';

  @override
  String get syncIssueServer =>
      'El servidor no respon bé. Es tornarà a provar.';

  @override
  String get syncIssueRateLimited =>
      'Massa peticions seguides. Es tornarà a provar d\'aquí un moment.';

  @override
  String get syncIssueUnreadable =>
      'Les dades del servidor no es poden obrir amb la clau d\'aquesta família.';

  @override
  String get syncIssueUnknown => 'Alguna cosa ha fallat. Es tornarà a provar.';

  @override
  String get inviteRowTitle => 'Convidar algú';

  @override
  String get joinInviteRowTitle => 'Unir-me amb un enllaç';

  @override
  String get inviteIntro =>
      'Crea un enllaç perquè una altra persona s\'uneixi a la teva família des del seu mòbil, encara que no la tinguis al costat.';

  @override
  String get inviteHowItWorks =>
      'L\'enllaç no conté cap clau. Serveix per a una sola persona i caduca al cap de 24 hores. Quan aquesta persona demani entrar, rebràs la seva petició amb un codi de 6 xifres. Tu decideixes si li dones accés.';

  @override
  String get inviteCreate => 'Crear enllaç i convidar';

  @override
  String get inviteNeedSync =>
      'Per convidar a distància, cal connexió a internet i tenir la sincronització encesa.';

  @override
  String get inviteGoToSync => 'Encendre la sincronització';

  @override
  String inviteShareText(String link) {
    return 'Et convido a la meva llista de Gift Huddle. Obre l\'enllaç i demana entrar: $link';
  }

  @override
  String get inviteWaitingTitle => 'Esperant la petició';

  @override
  String get inviteWaitingBody =>
      'Quan l\'altra persona demani entrar, veuràs la seva petició aquí. Pots sortir d\'aquesta pantalla. La invitació continuarà activa fins que caduqui.';

  @override
  String inviteExpires(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'Caduca el $dateString a les $timeString';
  }

  @override
  String get inviteShareAgain => 'Tornar a compartir l\'enllaç';

  @override
  String get inviteCancel => 'Cancel·lar invitació';

  @override
  String inviteRequestTitle(String name) {
    return '$name vol unir-se';
  }

  @override
  String get inviteRequestBody =>
      'Si no esperaves aquesta petició, rebutja-la. Si els dos codis no coincideixen, no donis accés.';

  @override
  String get inviteCodeLabel => 'Codi de verificació';

  @override
  String get inviteAccept => 'Els codis coincideixen, donar accés';

  @override
  String get inviteReject => 'Rebutjar';

  @override
  String get inviteApprovedTitle => 'Invitació acceptada';

  @override
  String inviteApprovedBody(String name) {
    return '$name ja pot entrar: el seu mòbil està recollint la clau.';
  }

  @override
  String get inviteRejectedBody =>
      'S\'ha cancel·lat la invitació. L\'enllaç ja no serveix.';

  @override
  String get inviteExpiredBody => 'La invitació ha caducat.';

  @override
  String get inviteNew => 'Convidar una altra persona';

  @override
  String get inviteErrorNetwork =>
      'No s\'ha pogut connectar amb el servidor. Torna-ho a provar.';

  @override
  String get inviteErrorUnknown =>
      'No s\'ha pogut completar la invitació. Torna-ho a provar.';

  @override
  String get joinInviteIntro =>
      'Enganxa l\'enllaç que t\'han enviat. Qui t\'ha convidat haurà d\'acceptar la teva petició.';

  @override
  String get joinInviteFieldLabel => 'Enllaç d\'invitació';

  @override
  String get joinInvitePaste => 'Enganxar';

  @override
  String get joinInviteAsk => 'Demanar entrada';

  @override
  String get joinInviteBadLink =>
      'Aquest text no és un enllaç d\'invitació de Gift Huddle.';

  @override
  String get joinInviteUnavailable =>
      'Les invitacions a distància no estan disponibles en aquesta versió.';

  @override
  String get joinInviteNetwork =>
      'No s\'ha pogut connectar amb el servidor. Comprova la connexió.';

  @override
  String get joinInviteTampered =>
      'No s\'ha pogut obrir la invitació. Demana un enllaç nou.';

  @override
  String get joinInviteUnknown =>
      'No s\'ha pogut completar la connexió. Torna-ho a provar.';

  @override
  String get joinInviteTaken =>
      'Una altra persona ja ha demanat entrar amb aquest enllaç. Demana un enllaç nou.';

  @override
  String get joinInviteGone => 'La invitació ha caducat o no s\'ha acceptat.';

  @override
  String get joinInviteWaitingTitle => 'Esperant que t\'acceptin';

  @override
  String get joinInviteWaitingBody =>
      'Qui t\'ha convidat ha de veure la teva petició. Quan el seu mòbil respongui, aquí veuràs un codi per comparar. Aquest mòbil espera la confirmació durant un màxim de 10 minuts.';

  @override
  String get joinInviteConfirmTitle => 'Compara el codi';

  @override
  String get joinInviteConfirmBody =>
      'Pregunta a qui t\'ha convidat quin codi veu al seu mòbil. Ha de ser el mateix que aquest. Quan ho confirmi al seu mòbil, entraràs a la família.';

  @override
  String get joinInviteMismatch => 'No coincideix, cancel·lar';

  @override
  String get joinInviteMismatchBody =>
      'Has cancel·lat i no has entrat a la família. Demana a qui t\'ha convidat un enllaç nou.';

  @override
  String joinInviteDoneBody(String name) {
    return 'Ja ets a la família de $name. La llista arribarà d\'aquí a uns segons.';
  }

  @override
  String get joinInviteRestart => 'Tornar a començar';

  @override
  String get syncIssueFirstUpload =>
      'La llista és massa gran per a la primera pujada.';

  @override
  String get inviteCompareNotice =>
      'Compara aquest codi amb el que veu l\'altra persona.';

  @override
  String get joinInviteWaitingForConfirm =>
      'Esperant que ho confirmi al seu mòbil…';

  @override
  String get familyChipAll => 'Totes';

  @override
  String get familyChipBirthdays => 'Aniversaris';

  @override
  String get familyOccasionPickerLabel => 'Ocasió';

  @override
  String get familyForAll => 'Totes les ocasions';

  @override
  String familyForOccasion(String name, String date) {
    return 'Per a $name, $date';
  }

  @override
  String get familyForBirthdays => 'Per als aniversaris';

  @override
  String familyCellOccasions(String names) {
    return 'per a $names';
  }

  @override
  String peopleCarouselPage(int page, int total) {
    return 'Ocasió $page de $total';
  }

  @override
  String peopleCarouselRange(int first, int last, int total) {
    return 'Ocasions $first i $last de $total';
  }

  @override
  String get occasionTypeTitle => 'Tipus d\'ocasió';

  @override
  String get occasionKindChineseNewYear => 'Cap d\'Any Xinès';

  @override
  String get occasionKindWedding => 'Casament';

  @override
  String get occasionKindAnniversary => 'Aniversari de casament';

  @override
  String get occasionKindSantJordi => 'Sant Jordi';

  @override
  String get occasionKindValentine => 'Sant Valentí';

  @override
  String get occasionKindBaptism => 'Bateig o naixement';

  @override
  String get occasionKindCommunion => 'Comunió';

  @override
  String get occasionKindGraduation => 'Graduació o final de curs';

  @override
  String get occasionKindCustom => 'Altra';

  @override
  String get occasionChineseNewYearHint =>
      'La data canvia cada any i es calcula sola.';

  @override
  String get occasionCustomColor => 'Color';

  @override
  String get occasionCustomIcon => 'Icona';

  @override
  String get occasionColorTeal => 'Turquesa';

  @override
  String get occasionColorSlate => 'Pissarra';

  @override
  String get occasionIconStar => 'Estrella';

  @override
  String get occasionIconHeart => 'Cor';

  @override
  String get occasionIconHome => 'Casa';

  @override
  String get occasionIconTrip => 'Viatge';

  @override
  String get occasionIconSchool => 'Escola';

  @override
  String get occasionIconPets => 'Mascota';

  @override
  String get occasionIconBaby => 'Bebè';

  @override
  String get occasionIconWork => 'Feina';

  @override
  String get occasionIconMusic => 'Música';

  @override
  String get occasionIconSport => 'Esport';

  @override
  String get occasionIconFlower => 'Flor';

  @override
  String get occasionIconParty => 'Festa';

  @override
  String get peopleUpcomingTitle => 'Properes ocasions';

  @override
  String todayShort(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Avui, $dateString';
  }

  @override
  String daysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dies',
      one: 'dia',
    );
    return '$_temp0';
  }

  @override
  String occasionGiftsBought(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'regals comprats',
      one: 'regal comprat',
    );
    return '$done de $total $_temp0';
  }

  @override
  String get occasionsGroupCelebrations => 'Festes';

  @override
  String get occasionsGroupBirthdays => 'Aniversaris';

  @override
  String get familyTotalRow => 'Total';

  @override
  String get familyRecipientHeader => 'Qui rep';

  @override
  String get familyLegendNothing => 'Res';

  @override
  String get familyLegendToBuy => 'Per comprar';

  @override
  String familyNoGiverCount(int count) {
    return '$count sense assignar';
  }

  @override
  String repartoSheetNobodyYet(String giver, String person) {
    return 'Encara no hi ha regals de $giver per a $person';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return 'Hi ha regals sense assignar per a $person. Toca «Sense assignar» en un regal per triar qui el regala.';
  }

  @override
  String get repartoSheetStartHint => 'Apunta un regal nou per començar.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · toca un nom per canviar qui regala';
  }

  @override
  String get repartoSheetWho => 'Sense assignar';

  @override
  String get repartoSheetNobody => 'Ningú';

  @override
  String get repartoSheetAddGift => 'Afegir un regal';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'Afegir un regal de $giver';
  }

  @override
  String repartoSheetOpenList(String person) {
    return 'Veure la llista de $person';
  }

  @override
  String get repartoSheetNoGiver => 'Sense assignar';

  @override
  String repartoSheetChipLabel(String giver) {
    return 'Qui regala: $giver. Canviar';
  }

  @override
  String repartoSheetLabel(String giver, String person) {
    return 'Regals de $giver per a $person';
  }

  @override
  String get lockBiometricHint =>
      'Toca el botó de l\'empremta per desbloquejar';

  @override
  String get repartoViewLabel => 'Vista del repartiment';

  @override
  String get repartoViewGrid => 'Quadrícula';

  @override
  String get repartoViewOccasion => 'Per ocasió';

  @override
  String get repartoOccasionPackets => 'Quants paquets obre cadascú';

  @override
  String repartoOccasionToBuy(int count) {
    return '$count per comprar';
  }

  @override
  String repartoOccasionNothingIn(String occasion) {
    return 'Res a $occasion';
  }

  @override
  String get repartoOccasionAddShort => 'Afegir';

  @override
  String repartoOccasionEmptyTitle(String occasion) {
    return 'Encara res a $occasion';
  }

  @override
  String get repartoOccasionEmptyMessage =>
      'Quan apuntis un regal per a aquest dia, aquí veuràs qui el porta i quants paquets obre cadascú.';

  @override
  String repartoPersonSheetLabel(String person) {
    return 'Fitxa de $person';
  }

  @override
  String repartoPersonOpen(String person) {
    return 'Obrir la fitxa de $person';
  }

  @override
  String get repartoSelfTag => 'Jo';

  @override
  String repartoSelfName(String name) {
    return '$name (jo)';
  }

  @override
  String get repartoPersonSheetSub =>
      'Com surt a Repartiment. No s\'elimina cap regal.';

  @override
  String get repartoPersonInReparto => 'Surt al repartiment';

  @override
  String get repartoPersonInRepartoHint =>
      'Si desmarques la casella, passarà a «Fora del repartiment».';

  @override
  String get repartoPersonOccasions => 'Li regaleu per';

  @override
  String familyOutsideTitle(int count) {
    return 'Fora del repartiment · $count';
  }

  @override
  String get familyOutsideNote => 'No surt al repartiment';

  @override
  String get familyIncludeAgain => 'Tornar a incloure';

  @override
  String familyExcludedStrip(String occasion) {
    return 'No li regaleu per $occasion';
  }

  @override
  String familySkipsLabel(String occasions) {
    return 'Sense $occasions';
  }

  @override
  String get familyLegendExcluded => 'No li regaleu';

  @override
  String repartoOccasionNotGiving(String occasion) {
    return 'No els regaleu per $occasion';
  }

  @override
  String get actionEliminate => 'Eliminar';

  @override
  String manageDeleteLabel(String name) {
    return 'Eliminar $name';
  }

  @override
  String get manageLockedThisDevice => 'És la persona d\'aquest mòbil.';

  @override
  String get manageLockedOtherDevice =>
      'És la persona d\'un altre mòbil de la família.';

  @override
  String deletePersonTitle(String name) {
    return 'Eliminar $name?';
  }

  @override
  String deleteOccasionTitle(String name) {
    return 'Eliminar «$name»?';
  }

  @override
  String deletePersonGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'També s\'eliminaran els $count regals que hi ha per a aquesta persona.',
      one: 'També s\'eliminarà el regal que hi ha per a aquesta persona.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo =>
      'El seu aniversari també s\'eliminarà de la llista d\'ocasions.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Els seus $count regals continuaran a la llista sense ningú assignat a «Qui regala».',
      one: 'El seu regal continuarà a la llista sense ningú assignat a «Qui regala».',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String deleteOccasionGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Els seus $count regals es quedaran sense ocasió.',
      one: 'El seu regal es quedarà sense ocasió.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteIrreversible =>
      'No es pot desfer. S\'elimina també als mòbils de la teva família.';

  @override
  String get deleteRequestedByToo =>
      'El seu nom deixarà de sortir als regals que va demanar per a altres persones.';

  @override
  String get deleteGiverBudget =>
      'Els seus imports deixen de comptar al pressupost de la casa.';

  @override
  String get deleteError => 'No s\'ha pogut eliminar. Torna-ho a provar.';

  @override
  String get giftNotSaved =>
      'No s\'ha desat: aquest regal ja no està disponible en aquest mòbil.';

  @override
  String giftDeletedNotice(String name) {
    return '«$name» eliminat';
  }

  @override
  String get settingsSectionFamily => 'Família';

  @override
  String get settingsSectionDevice => 'Aquest mòbil';

  @override
  String get settingsSelf => 'Aquest mòbil és de';

  @override
  String get settingsSelfNobody => 'Ningú';

  @override
  String get settingsSelfSheetTitle => 'De qui és aquest mòbil?';

  @override
  String get settingsSelfSheetHint =>
      'Només val en aquest mòbil; no es comparteix.';

  @override
  String get settingsSelfError => 'No s\'ha pogut desar. Torna-ho a provar.';

  @override
  String get settingsSectionShare => 'Compartir i còpia';

  @override
  String get settingsSectionAbout => 'Quant a';

  @override
  String get settingsArchive => 'Arxiu';

  @override
  String get settingsBackup => 'Còpia de seguretat';

  @override
  String get settingsAboutApp => 'Quant a Gift Huddle';

  @override
  String get eraseAllTitle => 'Esborrar-ho tot';

  @override
  String get eraseAllHint => 'La llista, el PIN i els ajustos d\'aquest mòbil.';

  @override
  String get eraseAllConfirmTitle => 'Vols esborrar-ho tot?';

  @override
  String get eraseAllConfirmBody =>
      'S\'esborren d\'aquest mòbil la llista sencera, el PIN i els ajustos, i l\'app torna a començar de zero. No es pot desfer. Els altres mòbils de la teva família conserven la seva còpia.';

  @override
  String get eraseAllConfirmServer =>
      'Abans, aquest mòbil surt de la sincronització de la família. Si no hi queda cap altre mòbil ni la web connectats, també s\'esborra la còpia xifrada per sincronitzar.';

  @override
  String get eraseAllContinue => 'Continuar';

  @override
  String get eraseAllTypeTitle => 'Últim pas';

  @override
  String eraseAllTypeBody(String word) {
    return 'Escriu $word per confirmar que ho vols esborrar tot.';
  }

  @override
  String get eraseAllWord => 'ESBORRAR';

  @override
  String get eraseAllFieldLabel => 'Confirmació';

  @override
  String get eraseAllWorking => 'Esborrant…';

  @override
  String get eraseAllServerFailedTitle =>
      'No s\'ha pogut contactar amb el servidor';

  @override
  String get eraseAllServerFailedBody =>
      'Comprova la connexió i torna-ho a provar. Si només esborres les dades d\'aquí, aquest mòbil continuarà a «Mòbils de la família» fins que algú el tregui des d\'un altre mòbil. Els altres mòbils i la web que hi tinguin accés podran continuar fent servir la còpia xifrada per sincronitzar. Si ningú no hi torna a accedir, caducarà.';

  @override
  String get eraseAllRetry => 'Reintentar';

  @override
  String get eraseAllLocalOnly => 'Esborrar només en aquest mòbil';

  @override
  String get eraseAllFailed =>
      'No s\'ha pogut esborrar tot. Torna-ho a provar.';

  @override
  String get eraseAllPinPrompt => 'Escriu el teu PIN per continuar.';

  @override
  String get eraseAllBiometricReason => 'Confirma que ho vols esborrar tot';

  @override
  String get settingsLockOff => 'Sense bloqueig';

  @override
  String get settingsLockPin => 'PIN';

  @override
  String get settingsLockPinBiometrics => 'PIN i biometria';

  @override
  String settingsAppearanceValue(String accent, String theme) {
    return '$accent · $theme';
  }

  @override
  String settingsLanguageSystemNow(String language) {
    return 'Ara: $language';
  }

  @override
  String get settingsDevicesOnlyThis => 'Només aquest';

  @override
  String settingsDevicesValue(int count, String status) {
    return '$count · $status';
  }

  @override
  String get syncShortUpToDate => 'al dia';

  @override
  String get syncShortSyncing => 'sincronitzant';

  @override
  String get syncShortPending => 'pendent';

  @override
  String get syncShortOffline => 'sense connectar';

  @override
  String get syncShortError => 'amb error';

  @override
  String get syncShortOff => 'apagada';

  @override
  String get archiveSubtitle =>
      'El que arxives deixa de sortir a les llistes, però conserva els regals.';

  @override
  String get archiveEmpty => 'No hi ha res arxivat.';

  @override
  String get archiveNote =>
      'Arxivar no esborra res. Eliminar sí, i per sempre.';

  @override
  String get devicesSoloTitle => 'Només en aquest mòbil';

  @override
  String get devicesSoloBody =>
      'Connecta\'n un altre per veure la mateixa llista en tots dos.';

  @override
  String get devicesPendingTitle => 'Connectant un altre mòbil';

  @override
  String get devicesPendingBody =>
      'Esperant que l\'altre mòbil acabi de connectar-se.';

  @override
  String get connectWebPasteCode => 'Enganxa el codi del QR';

  @override
  String get personPickerThisPhone => 'Aquest mòbil';

  @override
  String get devicesRecoveryTitle => 'Còpia de recuperació desada';

  @override
  String get devicesRecoveryBody =>
      'Amb el teu codi pots recuperar la llista a partir de la còpia xifrada per sincronitzar. Connecta un altre mòbil per veure la llista en tots dos.';

  @override
  String get devicesManualTitle => 'Connectats per fitxer o QR';

  @override
  String get devicesManualBody =>
      'Sense sincronització automàtica: envia la llista quan canviï.';

  @override
  String get devicesUpToDateTitle => 'Tot al dia';

  @override
  String devicesUpToDateBody(String status) {
    return '$status. Xifrat d\'extrem a extrem.';
  }

  @override
  String get devicesEncrypted => 'Xifrat d\'extrem a extrem.';

  @override
  String get devicesOffTitle => 'Sincronització apagada';

  @override
  String get devicesOffBody => 'Els canvis no surten d\'aquest mòbil.';

  @override
  String get devicesTurnOn => 'Encendre';

  @override
  String get syncTurnedOn => 'Sincronització encesa.';

  @override
  String get devicesOfflineTitle => 'No es pot connectar';

  @override
  String get devicesOfflineBody => 'Els canvis s\'enviaran després.';

  @override
  String get syncBlockedHint =>
      'Si tens internet, potser el teu operador està bloquejant el servei. Prova amb dades mòbils o una altra wifi.';

  @override
  String get devicesConnected => 'Connectats';

  @override
  String get devicesThisPhone => 'Aquest mòbil';

  @override
  String get devicesOtherPhone => 'Un altre mòbil';

  @override
  String get devicesPeerHint => 'Connectat a aquesta família';

  @override
  String get devicesPeerNoPerson =>
      'Sense persona: encara no veu les sorpreses';

  @override
  String get devicesListError => 'No s\'ha pogut llegir la llista de mòbils.';

  @override
  String get devicesConnect => 'Connectar un altre mòbil';

  @override
  String get devicesConnectQuestion => 'On és l\'altre mòbil?';

  @override
  String get devicesHereTitle => 'És aquí';

  @override
  String get devicesHereHint =>
      'Ensenya-li un codi QR. És la manera més ràpida.';

  @override
  String get devicesFarTitle => 'És lluny';

  @override
  String get devicesFarHint => 'Envia-li un enllaç. Tu aproves qui hi entra.';

  @override
  String get devicesSendNow => 'Enviar la llista ara';

  @override
  String get devicesSendNowHint => 'Amb un fitxer .gifthuddle, per on vulguis.';

  @override
  String get devicesMore => 'Més opcions';

  @override
  String get devicesMoreHint =>
      'Unir-me a una altra família, deixar de sincronitzar';

  @override
  String get devicesJoinOther => 'Unir aquest mòbil a una altra família';

  @override
  String get devicesJoinOtherHint => 'Substitueix la llista d\'aquest mòbil.';

  @override
  String get devicesJoinOtherWarning =>
      'Si t\'uneixes a una altra família, la seva llista substituirà la d\'aquest mòbil. En aquest mòbil perdràs els regals de la llista actual.';

  @override
  String get devicesScanTitle => 'Escanejar el seu QR';

  @override
  String get devicesScanHint =>
      'L\'altre mòbil l\'ensenya a «Connectar un altre mòbil».';

  @override
  String get devicesPasteLinkTitle => 'Enganxar un enllaç d\'invitació';

  @override
  String get devicesPasteLinkHint => 'Si te\'l van enviar per missatge.';

  @override
  String get devicesPrivacyTitle => 'Com es protegeix la llista';

  @override
  String get actionUnderstood => 'Entès';

  @override
  String get backupSubtitle =>
      'Un fitxer .gifthuddle xifrat amb tota la llista.';

  @override
  String get backupSaveTitle => 'Desar una còpia';

  @override
  String get backupSaveHint => 'Un fitxer .gifthuddle xifrat, on tu vulguis.';

  @override
  String get backupRestoreTitle => 'Recuperar una còpia';

  @override
  String get backupRestoreHint => 'Des d\'un fitxer o des del porta-retalls.';

  @override
  String get backupRestoreSubtitle =>
      'La còpia es combina amb la llista d\'aquest mòbil. No es perd res.';

  @override
  String get backupPasteTitle => 'Enganxar des del porta-retalls';

  @override
  String get backupPasteHint => 'Si et va arribar com a enllaç o com a text.';

  @override
  String get backupFileNote =>
      'Per obrir un fitxer .gifthuddle, toca\'l a Fitxers o al missatge on et va arribar i tria Gift Huddle.';

  @override
  String get backupNote =>
      'La còpia està xifrada amb la clau de la família. Només la pots obrir en un mòbil que ja formi part d\'aquesta família.';

  @override
  String get pairingV2Preparing => 'Preparant la connexió…';

  @override
  String get pairingV2NoticeExpires =>
      'La invitació caduca al cap de 24 hores i només serveix per demanar entrada. Abans de donar accés, compara el codi que apareix a tots dos mòbils.';

  @override
  String get pairingV2FarTitle => 'Comparteix l\'enllaç';

  @override
  String get pairingV2FarBody =>
      'Envia\'l a qui vulguis connectar. Quan l\'obri i demani entrar, aquí veuràs un codi per comparar-lo.';

  @override
  String get pairingV2Share => 'Compartir l\'enllaç';

  @override
  String get pairingV2WaitingHere =>
      'Esperant que l\'altra persona demani entrar…';

  @override
  String get pairingV2CompareTitle => 'Compara el codi';

  @override
  String get pairingV2HostCompareBody =>
      'L\'altre mòbil mostra un codi. Ha de ser el mateix que aquest. Si ho és, toca «Coincideixen»; si no, «No coincideixen».';

  @override
  String get pairingV2Match => 'Coincideixen';

  @override
  String get pairingV2NoMatch => 'No coincideixen';

  @override
  String get pairingV2Approving => 'Donant accés a l\'altre mòbil…';

  @override
  String get pairingV2HostDone =>
      'Accés enviat. L\'altre mòbil ha de completar la connexió.';

  @override
  String get pairingV2VersionMismatch =>
      'Tots dos mòbils han de tenir l\'última versió de Gift Huddle. Actualitza el que estigui desfasat i torna a començar.';

  @override
  String get pairingV2HostCancelled =>
      'La invitació s\'ha cancel·lat i ja no serveix. Pots tornar a començar.';

  @override
  String get pairingV2HostFailed =>
      'No s\'ha pogut connectar l\'altre mòbil. Torna-ho a provar.';

  @override
  String get pairingV2NotReady =>
      'Per continuar, cal connexió a internet i tenir la sincronització encesa.';

  @override
  String get pairingV2ChooseContinue => 'Continuar';

  @override
  String get pairingV2GuestWaitingCode =>
      'Quan l\'altre mòbil respongui, aquí veuràs un codi per comparar.';

  @override
  String get pairingV2GuestCompareBody =>
      'Compara aquest codi amb el que veu l\'altra persona. Si són iguals, toca «Coincideixen».';

  @override
  String get pairingV2GuestWaitingApproval =>
      'Esperant que l\'altre mòbil doni accés…';

  @override
  String get pairingV2GuestDoneBody =>
      'Ja ets a la família. La llista arribarà d\'aquí a uns segons.';

  @override
  String get pairingV2GuestCancelled =>
      'No has entrat a la família. Demana a qui t\'ha convidat que torni a començar.';

  @override
  String get pairingV2ReconnectTitle =>
      'Torna a connectar els mòbils per a la nova sincronització';

  @override
  String get pairingV2ReconnectBody =>
      'Cada mòbil es torna a connectar amb «Connectar un altre mòbil» i comparant un codi.';

  @override
  String pairingV2ClaimTitle(String name) {
    return 'L\'altre mòbil és de $name?';
  }

  @override
  String get pairingV2ClaimBody =>
      'Confirma-ho només si de debò és el seu mòbil: hi veurà les sorpreses per als altres, mai les seves.';

  @override
  String pairingV2ClaimYes(String name) {
    return 'Sí, és de $name';
  }

  @override
  String get pairingV2ClaimNo => 'No és seu';

  @override
  String get pairingV2MigrateTitle => 'Vols passar a la sincronització nova?';

  @override
  String get pairingV2MigrateBody =>
      'Si continues, aquesta família passa a la sincronització nova, més segura. No es pot desfer. Els mòbils que ja estaven connectats deixen de rebre els canvis d\'aquest fins que els tornis a connectar, un per un, amb «Connectar un altre mòbil». No es perd res.';

  @override
  String get pairingV2MigrateContinue => 'Continuar';

  @override
  String get joinReplacePinPrompt =>
      'Escriu el teu PIN per substituir la llista d\'aquest mòbil.';

  @override
  String get joinReplaceBiometricReason =>
      'Confirma que vols substituir la llista d\'aquest mòbil';

  @override
  String get devicesPeerPending => 'Espera aprovació';

  @override
  String get devicesPeerFrozen => 'Canvis en pausa: espera aprovació';

  @override
  String get devicesPeerReconfirm => 'Confirma de qui és';

  @override
  String get deviceReviewNoticeTitle => 'Hi ha mòbils per revisar';

  @override
  String deviceReviewNoticeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mòbils esperen que els confirmis.',
      one: 'Un mòbil espera que el confirmis.',
    );
    return '$_temp0';
  }

  @override
  String get deviceReviewOpen => 'Revisar mòbils';

  @override
  String deviceReviewProgress(int current, int total) {
    return '$current de $total';
  }

  @override
  String get deviceReviewDoneTitle => 'Tot revisat';

  @override
  String get deviceReviewDoneBody => 'No queda cap mòbil per confirmar.';

  @override
  String get deviceDetailOwner => 'De qui és';

  @override
  String get deviceDetailNoPerson => 'Sense persona';

  @override
  String get deviceDetailStatus => 'Estat';

  @override
  String get deviceStatusActive => 'Connectat';

  @override
  String get deviceStatusNoPerson => 'Connectat, sense persona';

  @override
  String get deviceStatusPending => 'Espera aprovació';

  @override
  String get deviceStatusFrozen => 'Canvis en pausa';

  @override
  String get deviceStatusReconfirm => 'Falta confirmar de qui és';

  @override
  String get deviceDetailSelfNote =>
      'Aquest és el teu mòbil. Per deixar de sincronitzar-lo, fes servir «Deixar de sincronitzar» a «Més opcions».';

  @override
  String get deviceRemoveTitle => 'Treure aquest mòbil';

  @override
  String get deviceRemoveHint => 'Deixarà de rebre els canvis de la llista.';

  @override
  String get deviceRemoveConfirmTitle => 'Vols treure aquest mòbil?';

  @override
  String get deviceRemoveConfirmBody =>
      'Deixa de rebre els canvis nous a l\'instant. El que ja té desat no se li pot esborrar. El que només era en aquell mòbil es pot perdre. No es pot desfer.';

  @override
  String get deviceRemoveConfirmAction => 'Treure mòbil';

  @override
  String get deviceRemoveWaitTitle =>
      'El teu mòbil tornarà a esperar aprovació';

  @override
  String get deviceRemoveWaitBody =>
      'Només el mòbil que vols treure ha aprovat el canvi de persona al teu mòbil. Si el treus, no podràs veure les sorpreses al teu mòbil fins que un altre mòbil de la família aprovi el canvi.';

  @override
  String get deviceRemoveWaitAction => 'Treure igualment';

  @override
  String get deviceRemovedSnack => 'Mòbil tret';

  @override
  String get deviceRemoveError =>
      'No s\'ha pogut treure el mòbil. Torna-ho a provar amb connexió.';

  @override
  String deviceApproveQuestion(String name) {
    return 'Aquest mòbil és de $name?';
  }

  @override
  String get deviceApproveQuestionNoPerson => 'Vols aprovar aquest mòbil?';

  @override
  String deviceApproveYes(String name) {
    return 'Sí, és de $name';
  }

  @override
  String get deviceApproveYesNoPerson => 'Aprovar aquest mòbil';

  @override
  String get deviceApproveLater => 'Després';

  @override
  String get deviceApproveNewcomer =>
      'Comprova-ho en persona abans d\'aprovar-lo: un mòbil aprovat rep la llista de la família.';

  @override
  String get deviceApprovePersonChanged =>
      'Ha canviat de persona. Si l\'aproves, podrà aprovar altres mòbils de la família.';

  @override
  String get deviceApproveOrphan =>
      'Cal tornar a confirmar de qui és. Si l\'aproves, tornarà a veure les sorpreses per als altres.';

  @override
  String get deviceApproveDetached =>
      'Aquest mòbil ja no està connectat a la família, però abans va confirmar el teu mòbil. Aprova\'l només si el reconeixes.';

  @override
  String get deviceApproveFrozen =>
      'Els seus canvis estan en pausa fins que l\'aprovis o el treguis.';

  @override
  String get deviceApprovedSnack => 'Mòbil aprovat';

  @override
  String get deviceApproveError =>
      'No s\'ha pogut aprovar el mòbil. Torna-ho a provar.';

  @override
  String get deviceChangedNotice =>
      'Les dades del mòbil han canviat. Torna-les a revisar.';

  @override
  String get deviceRemovedPendingSnack =>
      'Mòbil tret. Perdrà l\'accés quan hi hagi connexió.';

  @override
  String get deviceApproveCanVouch =>
      'Ha canviat de persona: si l\'aproves, podrà aprovar altres mòbils de la família.';

  @override
  String get webGateConnectTitle => 'Connecta aquest ordinador';

  @override
  String get webGateConnectIntro =>
      'Només cal fer-ho una vegada, amb el teu mòbil. Després hi entraràs amb el PIN o la frase que triïs.';

  @override
  String get webGateStepOpenApp => 'Obre Gift Huddle al teu mòbil.';

  @override
  String get webGateConnectStep2 =>
      'Ves a Ajustos › Mòbils de la família i toca «Connectar la web».';

  @override
  String get webGateConnectStep3 => 'Escaneja aquest codi.';

  @override
  String get webGateConnectWaiting => 'Esperant el mòbil…';

  @override
  String get webGateCompareTitle => 'Compara el codi';

  @override
  String get webGateCompareLabel => 'Codi de verificació';

  @override
  String get webGateCompareBody =>
      'Comprova que al mòbil surt el mateix codi, confirma\'l aquí i aprova\'l també al mòbil.';

  @override
  String get webGateCompareWaiting =>
      'Esperant que toquis «Coincideixen» al mòbil…';

  @override
  String get webGateCompareConfirmed => 'Has confirmat el codi aquí';

  @override
  String get webGateFailedTitle => 'No s\'ha pogut connectar';

  @override
  String get webGateFailedExpired =>
      'El codi ha caducat. Comença de nou per veure\'n un altre.';

  @override
  String get webGateFailedMismatch =>
      'Els codis no coincidien, així que no s\'ha connectat res. Comença de nou.';

  @override
  String get webGateFailedRejected =>
      'El mòbil ha rebutjat la connexió. Si vols connectar aquest ordinador, comença de nou.';

  @override
  String get webGateFailedNetwork =>
      'No hi ha connexió amb el servidor. Comprova la connexió i comença de nou.';

  @override
  String get webGateFailedCancelled =>
      'El mòbil ha cancel·lat la connexió o el codi ja no serveix. Comença de nou i escaneja el codi nou amb el mòbil.';

  @override
  String get webGateStartAgain => 'Començar de nou';

  @override
  String webGateChoosePinTitle(String name) {
    return 'Aquest ordinador és de $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Tria un PIN o una frase per desbloquejar Gift Huddle cada vegada que obris la web en aquest ordinador.';

  @override
  String get webGatePinLabel => 'PIN o frase';

  @override
  String get webGatePinRepeatLabel => 'Repeteix el PIN o la frase';

  @override
  String get webGatePinShow => 'Mostrar';

  @override
  String get webGatePinHide => 'Amagar';

  @override
  String get webGatePinRule =>
      '6 xifres o més, o una frase de 8 caràcters o més.';

  @override
  String get webGatePinSameHint =>
      'Pots fer servir el mateix PIN que al mòbil.';

  @override
  String get webGatePinMismatch => 'No coincideixen. Escriu-los de nou.';

  @override
  String get webGatePinNoRecover =>
      'Si l\'oblides, hauràs de tornar a connectar aquest ordinador des d\'un mòbil.';

  @override
  String get webGateContinue => 'Continuar';

  @override
  String get webGateSaving => 'Desant…';

  @override
  String get webGateUnlockTitle => 'Desbloqueja Gift Huddle';

  @override
  String get webGateUnlockBody =>
      'Escriu el PIN o la frase que vas triar per a Gift Huddle en aquest ordinador.';

  @override
  String get webGateUnlock => 'Desbloquejar';

  @override
  String get webGateUnlocking => 'Desbloquejant…';

  @override
  String get webGateWrongPin => 'PIN o frase incorrectes.';

  @override
  String webGateAttemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Et queden $count intents.',
      one: 'Et queda $count intent.',
    );
    return '$_temp0';
  }

  @override
  String webGateWait(int seconds) {
    return 'Espera $seconds s per tornar-ho a provar.';
  }

  @override
  String get webGateSuspendedTitle => 'Massa intents';

  @override
  String get webGateSuspendedBody =>
      'Per tornar-ho a provar, permet-ho abans des d\'un mòbil. No s\'ha esborrat res.';

  @override
  String get webGateSuspendedStep2 =>
      'Ves a Ajustos › Mòbils de la família i toca «Web».';

  @override
  String get webGateSuspendedStep3 => 'Toca «Permetre més intents de PIN».';

  @override
  String get webGateRetry => 'Reintentar';

  @override
  String get webGateDisconnectedTitle =>
      'Aquest ordinador ja no està connectat';

  @override
  String get webGateDisconnectedBody =>
      'S\'ha tret de la família des d\'un mòbil o la llista ja no existeix.';

  @override
  String webGateDisconnectedUnsent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hi ha $count canvis sense pujar. Estan desats i xifrats en aquest ordinador.',
      one:
          'Hi ha $count canvi sense pujar. Està desat i xifrat en aquest ordinador.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Tornar a connectar';

  @override
  String get webGateErase =>
      'Esborrar les dades de Gift Huddle en aquest ordinador';

  @override
  String get webGateEraseTitle =>
      'Esborrar les dades de Gift Huddle en aquest ordinador?';

  @override
  String get webGateEraseBody =>
      'S\'esborra tot el que Gift Huddle desa aquí. No es pot desfer.';

  @override
  String get webGateEraseBodyUnsent =>
      'S\'esborra tot el que Gift Huddle desa aquí, també els canvis sense pujar. No es pot desfer.';

  @override
  String get webGateDamagedTitle =>
      'Les dades de Gift Huddle en aquest ordinador estan malmeses';

  @override
  String get webGateDamagedBody =>
      'No es poden llegir de manera segura. Per continuar, esborra-les i torna a connectar aquest ordinador des d\'un mòbil. Perdràs els canvis que no s\'hagin pujat.';

  @override
  String get webGateDamagedPhoneHint =>
      'Al mòbil, ves a Ajustos › Mòbils de la família i treu la web anterior.';

  @override
  String get webGateOtherTabTitle =>
      'Gift Huddle està obert en una altra pestanya';

  @override
  String get webGateOtherTabBody =>
      'Només es pot fer servir en una pestanya alhora.';

  @override
  String get webGateUseHere => 'Fer servir aquí';

  @override
  String get webGateLockedLabel => 'Gift Huddle bloquejat';

  @override
  String get webSettingsTitle => 'Aquest ordinador';

  @override
  String get webSettingsChangePin => 'Canviar el PIN';

  @override
  String get webSettingsChangePinHint =>
      'El que obre Gift Huddle en aquest ordinador.';

  @override
  String get webSettingsChangePinTitle => 'Canviar el PIN o la frase';

  @override
  String get webSettingsCurrentPin => 'PIN o frase actual';

  @override
  String get webSettingsNewPin => 'Nou PIN o frase';

  @override
  String get webSettingsNewPinRepeat => 'Repeteix el nou PIN o la frase';

  @override
  String get webSettingsCurrentWrong =>
      'Comprova que has escrit bé el PIN o la frase actual.';

  @override
  String get webSettingsChangeFailed =>
      'No s\'ha pogut canviar. Torna-ho a provar.';

  @override
  String get webSettingsPinChanged => 'S\'ha canviat el PIN o la frase.';

  @override
  String get webSettingsLockNow => 'Bloquejar ara';

  @override
  String get webSettingsForget => 'Oblidar aquest ordinador';

  @override
  String get webSettingsForgetHint =>
      'Sortirà de la família i s\'esborraran les dades que Gift Huddle hi desa.';

  @override
  String get webSettingsForgetTitle => 'Oblidar aquest ordinador?';

  @override
  String get webSettingsForgetBody =>
      'Aquest ordinador sortirà de la família. S\'esborraran les dades que Gift Huddle hi desa, inclosos els canvis sense pujar. Als teus mòbils no canvia res. Per tornar a fer servir Gift Huddle aquí, hauràs de connectar l\'ordinador de nou.';

  @override
  String get webSettingsForgetConfirm => 'Oblidar';

  @override
  String get webSettingsPersistenceDenied =>
      'Si queda poc espai, el navegador podria esborrar les dades que Gift Huddle desa aquí.';

  @override
  String webSetAsideNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hi ha $count canvis que no es poden pujar perquè són per a una persona protegida. Es desen en aquest ordinador.',
      one:
          'Hi ha $count canvi que no es pot pujar perquè és per a una persona protegida. Es desa en aquest ordinador.',
    );
    return '$_temp0';
  }

  @override
  String get webGateChoosePinCheck =>
      'Si els codis no coincidien, no continuïs: prem «Començar de nou».';

  @override
  String get webGateRestartTitle => 'Començar de nou?';

  @override
  String get webGateRestartBody =>
      'Es descartarà aquesta connexió i apareixerà un codi QR nou. El PIN que hagis escrit no es desarà.';

  @override
  String get webGateRestartConfirm => 'Sí, començar de nou';

  @override
  String webFailedAttemptsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hi ha hagut $count intents fallits des de l\'últim desbloqueig de Gift Huddle en aquest ordinador. Si no has estat tu, canvia el PIN.',
      one:
          'Hi ha hagut $count intent fallit des de l\'últim desbloqueig de Gift Huddle en aquest ordinador. Si no has estat tu, canvia el PIN.',
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
  String get devicesWebHint => 'Ordinador connectat a aquesta família';

  @override
  String get devicesConnectWeb => 'Connectar la web';

  @override
  String get devicesConnectWebHint => 'Per apuntar regals des de l\'ordinador.';

  @override
  String get connectWebTitle => 'Connectar la web';

  @override
  String get connectWebIntro =>
      'Per apuntar regals des de l\'ordinador: obre web.gifthuddle.app i escaneja el codi que apareix.';

  @override
  String get connectWebScanInvalid =>
      'Aquest codi no és el de la web de Gift Huddle. Escaneja el que apareix a l\'ordinador.';

  @override
  String get connectWebWaiting => 'Esperant que l\'ordinador respongui…';

  @override
  String get connectWebCompareBody =>
      'L\'ordinador mostra un codi. Ha de ser el mateix que aquest. Si ho és, toca «Coincideixen»; si no, «No coincideixen».';

  @override
  String get connectWebApproving => 'Donant accés a l\'ordinador…';

  @override
  String get connectWebDoneTitle => 'Ordinador connectat';

  @override
  String get connectWebDoneBody =>
      'A l\'ordinador, tria un PIN per obrir Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'Aquest codi ja no val. A l\'ordinador, prem «Començar de nou». Escaneja el codi nou amb el mòbil.';

  @override
  String get connectWebScanAgain => 'Escanejar un altre codi';

  @override
  String get connectWebFailed =>
      'No s\'ha pogut connectar l\'ordinador. Prem «Començar de nou» a l\'ordinador. Escaneja el codi nou amb el mòbil.';

  @override
  String get connectWebCancel => 'Cancel·lar connexió';

  @override
  String get connectWebCancelled =>
      'S\'ha cancel·lat la connexió i el codi ja no serveix. A l\'ordinador, prem «Començar de nou».';

  @override
  String get deviceWebResume => 'Permetre més intents de PIN';

  @override
  String get deviceWebResumeHint =>
      'Si la web ja no accepta el PIN després de massa intents fallits. No s\'esborra res.';

  @override
  String get deviceWebResumeTitle => 'Vols permetre més intents de PIN?';

  @override
  String get deviceWebResumeBody =>
      'Aquest ordinador tornarà a acceptar intents de PIN. Fes-ho només si ha estat el seu propietari qui s\'ha equivocat.';

  @override
  String get deviceWebResumeConfirm => 'Permetre';

  @override
  String get deviceWebResumeDone => 'Fet. La web torna a acceptar el PIN.';

  @override
  String get deviceWebResumeError =>
      'No s\'han pogut permetre més intents de PIN. Comprova la connexió i torna-ho a provar.';

  @override
  String get deviceRemoveWebTitle => 'Treure aquesta web';

  @override
  String get deviceRemoveWebHint =>
      'Aquest ordinador deixarà de rebre els canvis de la llista.';

  @override
  String get deviceRemoveWebConfirmTitle => 'Vols treure aquesta web?';

  @override
  String get deviceRemoveWebConfirmBody =>
      'Aquest ordinador deixarà de tenir accés i de rebre els canvis nous a l\'instant. El que ja té en pantalla no se li pot esborrar. El que només era en aquell ordinador es pot perdre. No es pot desfer.';

  @override
  String get deviceRemoveWebConfirmAction => 'Treure web';

  @override
  String get deviceRemovedWebSnack => 'Web treta';

  @override
  String get deviceRemovedWebPendingSnack =>
      'Web treta. L\'ordinador perdrà l\'accés quan hi hagi connexió.';

  @override
  String get deviceRemoveWebError =>
      'No s\'ha pogut treure la web. Torna-ho a provar amb connexió.';

  @override
  String get webSyncSaved => 'Desat';

  @override
  String get webSyncOffline => 'No es pot connectar';

  @override
  String get webSyncAwaitingConfirm => 'Pendent de confirmació des d\'un mòbil';

  @override
  String get webOperationUnavailable =>
      'Això no es pot fer des de l\'ordinador. Fes-ho des d\'un mòbil.';

  @override
  String get selfChangeConfirmTitle => 'Canviar de qui és aquest mòbil?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'Diràs que aquest mòbil és de $name. Això canvia quins regals i sorpreses hi pots veure.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'Deixaràs aquest mòbil sense cap persona assignada. Això canvia quins regals i sorpreses hi pots veure.';

  @override
  String selfChangeEffectHides(String name) {
    return 'En aquest mòbil deixaran de veure\'s els regals per a $name.';
  }

  @override
  String get selfChangeEffectNobody =>
      'Aquest mòbil es quedarà sense persona assignada i no podrà veure sorpreses mentre continuï així.';

  @override
  String get selfChangeEffectWait =>
      'Fins que s\'aprovi el canvi des d\'un altre mòbil de la família, en aquest no hi veuràs les sorpreses de ningú.';

  @override
  String get selfChangeEffectReconfirm =>
      'Potser hauràs de tornar a confirmar alguns mòbils que vas aprovar des d\'aquest.';

  @override
  String get selfChangeConfirmAction => 'Canviar de persona';

  @override
  String get selfChangePendingTitle =>
      'Esperant l\'aprovació d\'un altre mòbil';

  @override
  String selfChangePendingBody(String name) {
    return 'Aquest mòbil ja és de $name. Un altre mòbil de la família ho ha d\'aprovar; mentrestant, no veuràs les sorpreses de ningú.';
  }

  @override
  String get selfChangePendingBodyNobody =>
      'Aquest mòbil ja no té cap persona assignada i espera l\'aprovació d\'un altre mòbil de la família. Encara que l\'aprovin, no podrà veure sorpreses mentre no tingui una persona assignada.';

  @override
  String get selfChangePendingOrphans =>
      'Alguns mòbils que havies aprovat esperen que els tornis a confirmar.';

  @override
  String get selfChangeExhaustedTitle =>
      'Aquest mòbil ja no pot canviar de persona';

  @override
  String get selfChangeExhaustedBody =>
      'Has arribat al límit de canvis de persona en aquest mòbil. Per triar algú altre, torna\'l a connectar a la família com un mòbil nou. Cal que tinguis a mà un altre mòbil de la família.';

  @override
  String get selfWaitingHint => 'Esperant l\'aprovació d\'un altre mòbil';

  @override
  String get healthRevokedTitle => 'Han tret aquest mòbil de la família';

  @override
  String get healthRevokedBody =>
      'Les teves dades continuen en aquest mòbil. Perquè es torni a sincronitzar, connecta\'l de nou en persona amb un altre mòbil de la família.';

  @override
  String get healthRevokedAction => 'Tornar a connectar';

  @override
  String healthFrozenTitle(String names) {
    return 'Sorpreses en pausa per a $names';
  }

  @override
  String get healthFrozenTitleGeneric => 'Sorpreses en pausa';

  @override
  String get healthFrozenBody =>
      'No s\'ha perdut res. Les sorpreses es tornaran a veure quan s\'hagi triat de qui és aquest mòbil i un altre mòbil de la família l\'aprovi.';

  @override
  String healthNamesAnd(String head, String last) {
    return '$head i $last';
  }

  @override
  String get healthRenewSoon => 'Convé renovar la llista aviat';

  @override
  String get healthResolveSection => 'Per resoldre';

  @override
  String get healthUnbackedTitle => 'Accés sense identificar';

  @override
  String get healthUnbackedBody =>
      'Un accés al servidor no figura a la llista de mòbils de la família. Si no el reconeixes, retira\'l.';

  @override
  String healthUnbackedRef(String ref) {
    return 'Referència: $ref';
  }

  @override
  String get healthUnbackedAction => 'Retirar l\'accés';

  @override
  String get healthUnbackedConfirmTitle => 'Vols retirar aquest accés?';

  @override
  String get healthUnbackedConfirmBody =>
      'Es talla l\'accés d\'aquell mòbil al servidor de la família. Si era un mòbil teu, l\'hauràs de tornar a connectar en persona. No es pot desfer.';

  @override
  String get healthUnbackedDone => 'Accés retirat';

  @override
  String healthDepartedTitle(String name) {
    return 'Baixa a mitges: $name';
  }

  @override
  String get healthDepartedBody =>
      'Ja no té accés al servidor, però falta completar-ne la baixa a la llista de mòbils per actualitzar els permisos i les claus.';

  @override
  String get healthDepartedAction => 'Completar la baixa';

  @override
  String get healthDepartedDone => 'Baixa completada';

  @override
  String get healthResolveBusy => 'Un moment';

  @override
  String get healthResolveError =>
      'No s\'ha pogut completar. Comprova la connexió i torna-ho a provar.';

  @override
  String get healthRetry => 'Reintentar';

  @override
  String get healthUnbackedNotNeeded => 'Ja no cal treure aquest accés.';

  @override
  String get settingsSelfSheetHintV2 =>
      'La persona que triïs determina quins regals i sorpreses pots veure en aquest mòbil. El canvi es comparteix amb els altres mòbils de la família.';

  @override
  String get protectionRowTitle => 'Regals en secret';

  @override
  String protectionRowHint(String name) {
    return 'Que $name no vegi els seus regals al seu mòbil.';
  }

  @override
  String get protectionStatusOff => 'Desactivats';

  @override
  String get protectionStatusRequested => 'Per confirmar';

  @override
  String get protectionStatusActive => 'Actius';

  @override
  String protectionSheetTitle(String name) {
    return 'Regals en secret per a $name';
  }

  @override
  String protectionIntro(String name) {
    return 'Amb la protecció activa, $name no veu al seu mòbil quins regals hi ha per a $name ni quants n\'hi ha.';
  }

  @override
  String get protectionEffectOthers =>
      'Els altres mòbils de la família amb permís continuen veient-los i editant-los.';

  @override
  String protectionEffectKept(String name) {
    return 'La protecció no pot retirar els regals que ja havien arribat al mòbil de $name.';
  }

  @override
  String get protectionEffectConfirm =>
      'Cal un mòbil amb permís que ho confirmi.';

  @override
  String get protectionRequest => 'Demanar protecció';

  @override
  String get protectionRequestedTitle => 'Protecció demanada';

  @override
  String protectionWaitingBody(String name) {
    return 'Esperant un mòbil amb permís que la confirmi. Fins aleshores, els regals de $name no es mostren en cap mòbil.';
  }

  @override
  String protectionConfirmBody(String name) {
    return 'Aquest mòbil té permís per confirmar-la. En activar-la, els regals de $name deixen de mostrar-se al seu mòbil.';
  }

  @override
  String get protectionActivate => 'Activar ara';

  @override
  String get protectionActiveTitle => 'Protecció activa';

  @override
  String protectionActiveBody(String name) {
    return '$name no veu cap dels seus regals al seu mòbil.';
  }

  @override
  String get protectionDeactivate => 'Desactivar protecció';

  @override
  String protectionDeactivateTitle(String name) {
    return 'Desactivar els regals en secret per a $name?';
  }

  @override
  String protectionDeactivateBody(String name) {
    return 'Els regals per a $name que estiguin disponibles en aquest mòbil deixaran d\'estar en secret. S\'hi inclouen els de qualsevol any i els que hi ha pendents en aquest mòbil. Quan se sincronitzin els canvis, $name els podrà veure al seu mòbil.';
  }

  @override
  String get protectionDeactivateConfirm => 'Desactivar';

  @override
  String protectionCannotDeactivate(String name) {
    return 'Aquest mòbil no pot desactivar-la ara: cal permís i la clau actual de $name.';
  }

  @override
  String get protectionOnlyOthersChange =>
      'Només una altra persona de la família ho pot canviar, des del seu mòbil.';

  @override
  String get protectionChangeFailed =>
      'No s\'ha pogut canviar la protecció. No s\'ha modificat res.';

  @override
  String protectionNeedConfirmer(String name) {
    return 'Per protegir els regals de $name cal un mòbil d\'una altra persona de la família. A Ajustos, tria de qui és aquest mòbil a «Aquest mòbil és de». Aprova el canvi des d\'un altre mòbil o connecta un altre mòbil a la família. Si ja ho has fet, sincronitza.';
  }

  @override
  String protectionNeedConfirmerOwn(String name) {
    return 'Des d\'aquest mòbil no es poden protegir els regals de $name. Demana a una altra persona de la família que ho faci des del seu.';
  }

  @override
  String protectionRequesterPending(String name) {
    return 'Cal que algú de la família aprovi des d\'un altre mòbil el canvi a «Aquest mòbil és de». Fins aleshores no pots demanar protecció per als regals de $name.';
  }

  @override
  String protectionRequesterRevoked(String name) {
    return 'Aquest mòbil ja no forma part de la família, així que no pot demanar la protecció dels regals de $name.';
  }

  @override
  String protectionRequesterAmbiguous(String name) {
    return 'No se sap amb seguretat de qui és aquest mòbil, així que no pot demanar la protecció dels regals de $name. Sincronitza i torna-ho a provar.';
  }

  @override
  String protectionRecipientUnavailable(String name) {
    return '$name ja no és a la llista. No es pot demanar protecció per als seus regals.';
  }

  @override
  String get protectionRegistryUnavailable =>
      'Aquest mòbil encara no està al dia amb la família. Sincronitza i torna-ho a provar.';

  @override
  String secretBlockTitle(String name) {
    return 'Regals en secret per a $name';
  }

  @override
  String get secretBlockNote => 'Aquest mòbil no els mostra.';

  @override
  String protectionReason_protectedPerson(String name) {
    return 'Els regals de $name estan en secret i no es poden desar així.';
  }

  @override
  String protectionReason_noEntitlement(String name) {
    return 'Aquest mòbil no té accés als regals en secret per a $name. Demana ajuda a algú de la família que tingui un mòbil amb permís.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'Aquest mòbil és de $name. Aquí no pots crear ni veure regals en secret per a $name.';
  }

  @override
  String protectionReason_missingEpochKey(String name) {
    return 'Falta la clau actual dels regals de $name. Un altre mòbil amb permís t\'ha de donar accés.';
  }

  @override
  String protectionReason_protectionPending(String name) {
    return 'Falta que un mòbil amb permís confirmi la protecció de $name.';
  }

  @override
  String protectionReason_unreadableSlot(String name) {
    return 'No es pot obrir una part dels regals de $name. No s\'ha canviat res: recupera l\'accés abans de continuar.';
  }

  @override
  String protectionReason_blockFull(String name) {
    return 'Has arribat al límit de regals en secret per a $name. Elimina\'n algun per poder-ne afegir més.';
  }

  @override
  String protectionReason_giftTooLarge(String name) {
    return 'Escurça les notes per poder desar aquest regal en secret.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'Aquest mòbil ha arribat al límit de regals en secret que pot desar. Demana a algú que n\'afegeixi més des d\'un altre mòbil amb permís.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'Ara mateix no es poden afegir més regals en secret a la llista de la família.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Els regals en secret necessiten que aquest mòbil estigui connectat a la família amb la versió nova.';
  }

  @override
  String get giftProtectedRejected => 'No s\'ha desat el regal.';

  @override
  String get giftSavedLocally =>
      'Desat només en aquest mòbil. Encara cal afegir-lo a la llista i compartir-lo.';

  @override
  String get giftSavedLocallyAction => 'Veure pendents';

  @override
  String get giftOwnRequestRestricted =>
      'Amb la protecció activa, en aquest mòbil no pots afegir ni veure regals per a tu. Demana a algú altre de la família que apunti el regal.';

  @override
  String get pendingGiftsTitle => 'Regals pendents';

  @override
  String get pendingGiftsIntro =>
      'Aquests regals estan xifrats i només es desen en aquest mòbil. Encara no apareixen a la llista compartida de la família. Si perds el mòbil abans que s\'hi afegeixin, també perdràs aquests regals.';

  @override
  String get pendingGiftsRetry => 'Reintentar';

  @override
  String get pendingGiftsRetrying => 'Reintentant';

  @override
  String get pendingGiftsStill =>
      'Encara no hi ha lloc. Els regals continuen desats només en aquest mòbil.';

  @override
  String get pendingGiftsRetryError =>
      'No s\'ha pogut reintentar. Els regals continuen desats en aquest mòbil.';

  @override
  String get pendingGiftsDoneTitle => 'Tot desat';

  @override
  String get pendingGiftsDoneBody => 'Ja no queda cap regal pendent.';

  @override
  String pendingGiftsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals pendents de desar',
      one: '$count regal pendent de desar',
    );
    return '$_temp0';
  }

  @override
  String get pendingGiftsNoticeAction => 'Veure';

  @override
  String get peopleSummaryTitle => 'Resum';

  @override
  String get giftsEmptyOccasionsHint =>
      'O apunta el primer per a una propera ocasió';

  @override
  String occasionGiftsBoughtShort(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'comprats',
      one: 'comprat',
    );
    return '$done de $total $_temp0';
  }

  @override
  String get boardToday => 'Avui';

  @override
  String get boardNowTitle => 'Què toca ara';

  @override
  String boardSubtitle(String date, int bought, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total regals comprats',
      one: '$total regal comprat',
    );
    return '$date · $bought de $_temp0';
  }

  @override
  String get boardLaneDecide => 'Per decidir';

  @override
  String get boardLaneBuy => 'Per comprar';

  @override
  String get boardLaneArrive => 'Per arribar';

  @override
  String get boardLaneWrap => 'Per embolicar';

  @override
  String get boardLaneReady => 'Llest';

  @override
  String get boardLaneEmpty => 'Res per aquí';

  @override
  String boardMoveTo(String lane) {
    return 'Moure a «$lane»';
  }

  @override
  String boardLaneAdd(String lane) {
    return 'Afegir un regal a «$lane»';
  }

  @override
  String boardGiftMoved(String item, String lane) {
    return '$item: $lane';
  }

  @override
  String get boardOccasionsHint => 'Tria una ocasió per veure\'n el tauler.';

  @override
  String boardSeeAll(int count) {
    return 'Veure-les totes ($count)';
  }

  @override
  String get boardBudgetEmptyTitle => 'Encara no hi ha res previst';

  @override
  String get boardChangeDate => 'Canviar la data';

  @override
  String get boardSettingsIndex => 'Apartats';

  @override
  String get boardEditorLabel => 'Editor de regal';

  @override
  String get boardNoGiftsYet => 'Encara sense regals';

  @override
  String get boardSidebarCollapse => 'Plegar la barra lateral';

  @override
  String get boardSidebarExpand => 'Desplegar la barra lateral';

  @override
  String get boardSearchHint => 'Cercar un regal';

  @override
  String get boardSearchNone => 'Cap regal coincideix';

  @override
  String get boardPersonFilter => 'Persona';

  @override
  String get boardPersonFilterAll => 'Totes les persones';

  @override
  String get searchClear => 'Esborrar la cerca';

  @override
  String get boardColStatus => 'Estat';

  @override
  String get boardColGiver => 'Qui regala';

  @override
  String get boardColSize => 'Talla';

  @override
  String get boardRepartoNoGiver => 'Sense assignar';

  @override
  String get boardRepartoNoGiverNone => 'Tots els regals tenen qui els regali.';

  @override
  String get boardRepartoDuplicates => 'Possibles duplicats';

  @override
  String get boardRepartoDuplicatesNone => 'Cap regal sembla repetit.';

  @override
  String boardRowMore(String name) {
    return 'Més accions de $name';
  }

  @override
  String get tourTitle => 'Com funciona';

  @override
  String get tourSkip => 'Ometre';

  @override
  String tourPageOf(int page, int total) {
    return 'Pàgina $page de $total';
  }

  @override
  String get tour1Title => 'Apunta cada regal';

  @override
  String get tour1Body =>
      'Tria per a qui és el regal, l\'ocasió i qui el regala. Amb una idea n\'hi ha prou.';

  @override
  String get tour2Title => 'Marca\'l com a comprat';

  @override
  String get tour2Body =>
      'Toca la casella i el regal surt de «Pendent de comprar» i passa a «per arribar». Si t\'equivoques, ho desfàs a l\'instant.';

  @override
  String get tour3Title => 'Persones i ocasions';

  @override
  String get tour3Body =>
      'La llista de cada persona agrupa els regals per ocasió, com ara Nadal, Reis o aniversaris. A «Repartiment» veus qui paga cada regal.';

  @override
  String get tour4Title => 'La família comparteix la llista';

  @override
  String get tour4Body =>
      'Connecta un altre mòbil amb un QR, en persona. Tot viatja xifrat i els canvis arriben sols.';

  @override
  String get tour5Title => 'Sorpreses a recer';

  @override
  String get tour5Body =>
      'Al teu mòbil no es mostren els regals que són per a tu. Pots bloquejar l\'app amb PIN o biometria. Sense comptes ni anuncis.';

  @override
  String get tour6Title => 'També a l\'ordinador';

  @override
  String get tour6Body =>
      'Connecta la web una vegada i tindràs la llista en una pantalla gran.';

  @override
  String get tourDemoScooter => 'Patinet';

  @override
  String get tourDemoPuzzle => 'Puzle';

  @override
  String get tourDemoPajamas => 'Pijama';

  @override
  String get tourDemoChristmas => 'Nadal';

  @override
  String get tourDemoBirthday => 'Aniversari';

  @override
  String get tourDemoConnected => 'Connectat';

  @override
  String get tourDemoEncrypted => 'Xifrat';

  @override
  String get tourDemoHidden => 'Regals en secret';

  @override
  String get settingsRecovery => 'Codi de recuperació';

  @override
  String get recoveryValueNone => 'Sense crear';

  @override
  String get recoveryValuePrepared => 'Preparat';

  @override
  String get recoveryValuePending => 'Preparant';

  @override
  String get recoveryValueUnconfirmed => 'Sense comprovar';

  @override
  String get recoveryUnconfirmedTitle => 'Falta comprovar el codi';

  @override
  String get recoveryUnconfirmedBody =>
      'El codi encara no compta com a desat. Si vas desar un fitxer, el pots comprovar. Si no, continua amb les paraules: si ja les has vist, en continuar es crearà un codi nou i l\'anterior deixarà de valer.';

  @override
  String get recoveryValueAttention => 'Revisar';

  @override
  String get recoveryValueTransferred => 'Llista traspassada';

  @override
  String get recoverySubtitle => 'Per recuperar la llista en un mòbil nou.';

  @override
  String get recoveryAbsentTitle =>
      'Prepara un codi per recuperar la llista si perds aquest mòbil';

  @override
  String get recoveryAbsentBody =>
      'Quan crees el codi, l\'app desa una còpia xifrada per sincronitzar, encara que només tinguis aquest mòbil. Amb les 24 paraules podràs recuperar en un altre mòbil la part de la llista que pots veure i que s\'hagi sincronitzat.';

  @override
  String get recoveryAbsentWarn =>
      'Qui tingui les paraules tindrà el mateix accés a la llista que tens en aquest mòbil. Només es pot recuperar el que s\'hagi sincronitzat.';

  @override
  String get recoveryCreate => 'Crear el codi de recuperació';

  @override
  String get recoveryPreparedTitle => 'Codi preparat';

  @override
  String get recoveryPreparedBody =>
      'La còpia xifrada està a punt. Les paraules no es poden tornar a veure: si les perds, canvia el codi.';

  @override
  String get recoveryPendingTitle => 'Preparant la còpia…';

  @override
  String get recoveryPendingBody =>
      'S\'està desant la còpia xifrada. Cal connexió; es completa sola quan n\'hi hagi.';

  @override
  String get recoveryAttentionTitle => 'Cal revisar el codi';

  @override
  String get recoveryChange => 'Canviar el codi';

  @override
  String get recoveryChangeHint =>
      'Els fitxers i les paraules anteriors deixaran de servir.';

  @override
  String get recoveryRemove => 'Esborrar el codi';

  @override
  String get recoveryRemoveHint =>
      'Les paraules deixaran de valer i s\'esborra la còpia.';

  @override
  String get recoveryRemoveTitle => 'Vols esborrar el codi de recuperació?';

  @override
  String get recoveryRemoveBody =>
      'S\'esborra la còpia de recuperació i les 24 paraules deixen de valer. Podràs crear un altre codi quan vulguis.';

  @override
  String get recoveryRemoveSoloNote =>
      'Com que no hi ha cap altre mòbil ni la web connectats, també s\'esborra la còpia xifrada per sincronitzar i la llista torna a ser només en aquest mòbil.';

  @override
  String get recoveryRemoveConfirm => 'Esborrar el codi';

  @override
  String get recoveryRemoved => 'Codi esborrat';

  @override
  String get recoveryRetry => 'Reintentar';

  @override
  String get recoveryIntroTitle => 'Crear el codi';

  @override
  String get recoveryRotateTitle => 'Canviar el codi';

  @override
  String get recoveryIntroBody =>
      'Veuràs 24 paraules. Et serviran per recuperar en un altre mòbil la llista i tot el que veus en aquest.';

  @override
  String get recoveryRotateBody =>
      'Es crearà un codi nou. L\'anterior deixarà de valer quan el nou estigui preparat: els fitxers i les paraules anteriors deixaran de servir.';

  @override
  String get recoveryPoint1 =>
      'Apunta-les en paper o desa-les en un gestor de contrasenyes.';

  @override
  String get recoveryPoint2 =>
      'Qui les tingui tindrà el mateix accés a la llista que tens en aquest mòbil.';

  @override
  String get recoveryPoint3 => 'No recuperen el que mai no es va sincronitzar.';

  @override
  String get recoveryContinue => 'Continuar';

  @override
  String get recoveryAuthTitle => 'Codi de recuperació';

  @override
  String get recoveryAuthMessage => 'Escriu el teu PIN per veure les paraules.';

  @override
  String get recoveryAuthBiometric =>
      'Confirma que ets tu per veure el codi de recuperació';

  @override
  String get recoveryMaking => 'Preparant el codi…';

  @override
  String get recoveryWordsTitle => 'Les teves 24 paraules';

  @override
  String get recoveryWordsBody =>
      'Apunta-les en ordre. Quan surtis d\'aquest procés, no les podràs tornar a veure.';

  @override
  String get recoveryWordsWarn =>
      'Qui tingui aquestes paraules tindrà el mateix accés a la llista que tens en aquest mòbil. No en facis cap captura ni les enviïs per missatge.';

  @override
  String recoveryWordItem(int number, String word) {
    return 'Paraula $number: $word';
  }

  @override
  String get recoveryShowQr => 'Veure el codi QR';

  @override
  String get recoveryShowWords => 'Veure les paraules';

  @override
  String get recoveryQrBody =>
      'Aquest QR permet recuperar la llista igual que les 24 paraules. No en facis cap captura ni l\'enviïs per missatge.';

  @override
  String get recoveryQrLabel => 'Codi QR de recuperació';

  @override
  String get recoveryWordsSaved => 'Ja les he desat';

  @override
  String get recoveryHidden => 'Paraules amagades';

  @override
  String get recoveryHiddenBody => 'Torna a l\'app per veure-les.';

  @override
  String get recoveryLeaveTitle => 'Vols sortir sense desar les paraules?';

  @override
  String get recoveryLeaveBody =>
      'No es tornaran a mostrar. Si surts, hauràs de canviar el codi per veure\'n unes de noves.';

  @override
  String get recoveryLeaveConfirm => 'Sortir';

  @override
  String get recoveryLeaveStay => 'Continuar aquí';

  @override
  String get recoveryCheckTitle => 'Comprova que les has desat';

  @override
  String recoveryCheckBody(int a, int b, int c) {
    return 'Escriu les paraules $a, $b i $c.';
  }

  @override
  String recoveryCheckField(int number) {
    return 'Paraula $number';
  }

  @override
  String get recoveryCheckWrong =>
      'Alguna paraula no coincideix. Torna-les a mirar.';

  @override
  String get recoveryCheckBack => 'Tornar a veure les paraules';

  @override
  String get recoveryCheckButton => 'Comprovar';

  @override
  String get recoveryDonePreparedTitle => 'Codi preparat';

  @override
  String get recoveryDonePreparedBody =>
      'Si perds aquest mòbil, podràs recuperar la llista amb el teu codi de recuperació.';

  @override
  String get recoveryDonePendingBody =>
      'Encara no està a punt: s\'està desant la còpia xifrada. Cal connexió i es completa sola.';

  @override
  String get recoveryDoneButton => 'Fet';

  @override
  String get recoveryCloseLater => 'Tancar i continuar més tard';

  @override
  String get recoveryProblemOfflineTitle => 'Sense connexió';

  @override
  String get recoveryProblemOfflineBody =>
      'No s\'ha pogut arribar al servidor. Comprova la connexió i torna-ho a provar; el que s\'ha fet fins ara es conserva.';

  @override
  String get recoveryProblemWrongTitle => 'Aquest codi no obre cap llista';

  @override
  String get recoveryProblemWrongBody =>
      'Revisa les paraules o prova amb un altre codi. Si el van canviar, fes servir el més recent.';

  @override
  String get recoveryProblemRetiredTitle => 'Aquest codi ja no val';

  @override
  String get recoveryProblemRetiredBody =>
      'Es va canviar o es va esborrar des d\'un altre mòbil. Busca el codi més recent.';

  @override
  String get recoveryProblemRemovedTitle =>
      'Aquest mòbil ja no és a la família';

  @override
  String get recoveryProblemRemovedBody =>
      'Aquest codi és d\'un mòbil que es va treure de la família. Ja no serveix per recuperar la llista.';

  @override
  String get recoveryProblemIncompleteTitle =>
      'La recuperació s\'ha quedat a mitges';

  @override
  String get recoveryProblemIncompleteBody =>
      'Falta una part de la llista. El que s\'ha descarregat es conserva. Torna-ho a provar amb connexió o, si tens un altre mòbil connectat a aquesta família, obre-hi l\'app un moment.';

  @override
  String get recoveryProblemBusyTitle => 'Hi ha una altra operació en curs';

  @override
  String get recoveryProblemBusyBody => 'Espera un moment i torna-ho a provar.';

  @override
  String get recoveryProblemUnsupportedTitle => 'No es pot obrir aquesta còpia';

  @override
  String get recoveryProblemUnsupportedBody =>
      'Pot ser que calgui actualitzar l\'app, o que la còpia estigui malmesa.';

  @override
  String get recoveryProblemUnavailableTitle => 'No disponible ara';

  @override
  String get recoveryProblemUnavailableBody =>
      'La recuperació no està disponible en aquest mòbil.';

  @override
  String get recoveryProblemOtherTitle => 'Alguna cosa no ha anat bé';

  @override
  String get recoveryProblemOtherBody =>
      'No s\'ha pogut acabar. Torna-ho a provar; si continua igual, prova-ho més tard.';

  @override
  String get obHaveRecoveryCode => 'Fer servir el codi de recuperació';

  @override
  String get recoverTitle => 'Recupera la llista';

  @override
  String get recoverBody =>
      'Escriu les 24 paraules en ordre o escaneja el codi QR de recuperació.';

  @override
  String recoverWordField(int number) {
    return 'Paraula $number';
  }

  @override
  String recoverFilled(int count) {
    return '$count de 24 paraules';
  }

  @override
  String get recoverPaste => 'Enganxar les 24 paraules';

  @override
  String get recoverScan => 'Escanejar el QR';

  @override
  String get recoverSubmit => 'Recuperar la llista';

  @override
  String recoverWordUnknown(int number) {
    return 'Revisa com has escrit la paraula $number.';
  }

  @override
  String get recoverChecksum =>
      'Les paraules no formen un codi vàlid. Comprova que siguin les del teu codi i que estiguin en el mateix ordre.';

  @override
  String get recoverPasteEmpty => 'No hi ha res copiat.';

  @override
  String get recoverPasteWrong =>
      'El que has copiat no té 24 paraules. Copia el codi sencer i torna\'l a enganxar.';

  @override
  String get recoverQrWrong => 'Aquest QR no és un codi de recuperació.';

  @override
  String get recoverScanTitle => 'Escaneja el QR del codi';

  @override
  String get recoverScanBody => 'Apunta la càmera al codi QR de recuperació.';

  @override
  String get recoverProgressTitle => 'Recuperant la llista';

  @override
  String get recoverProgressBody => 'No tanquis l\'app. Pot trigar un minut.';

  @override
  String get recoverStepFind => 'Cercant la còpia';

  @override
  String get recoverStepCheck => 'Comprovant el codi';

  @override
  String get recoverStepDownload => 'Descarregant la llista';

  @override
  String get recoverStepInstall => 'Desant la llista en aquest mòbil';

  @override
  String get recoverDoneTitle => 'Llista recuperada';

  @override
  String recoverDoneSelf(String name) {
    return 'Aquest mòbil és de $name.';
  }

  @override
  String get recoverDoneNoSelf =>
      'Falta indicar de qui és aquest mòbil. Ho pots fer a Ajustos.';

  @override
  String recoverDonePeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count persones',
      one: '1 persona',
    );
    return 'La teva llista té $_temp0.';
  }

  @override
  String get recoverEnter => 'Entrar a la llista';

  @override
  String get recoverOtherCode => 'Escriure un altre codi';

  @override
  String get transferredTitle => 'Aquesta llista s\'ha traspassat';

  @override
  String get transferredBody =>
      'Ara tens la llista en un altre mòbil o en una altra app. Aquí la pots consultar, però ja no la pots editar. No s\'ha esborrat res.';

  @override
  String get transferredReadOnly => 'Només lectura';

  @override
  String get recoveryProblemFamilyTitle =>
      'Aquest codi és d\'una altra família';

  @override
  String get recoveryProblemFamilyBody =>
      'Substituiria la llista que tens en aquest mòbil. Si no és el que vols, cancel·la la recuperació.';

  @override
  String get recoveryProblemNotReadyTitle => 'La còpia encara no està a punt';

  @override
  String get recoveryProblemNotReadyBody =>
      'Les 24 paraules encara no estan disponibles. Comprova la connexió i torna-ho a provar.';

  @override
  String get recoverReplaceTitle =>
      'Vols substituir la llista d\'aquest mòbil?';

  @override
  String get recoverReplaceBody =>
      'Aquest codi és d\'una altra família. Si continues, veuràs la seva llista en aquest mòbil. La que fas servir ara hi continuarà desada, però ja no la veuràs.';

  @override
  String get recoverReplaceConfirm => 'Substituir';

  @override
  String get recoverAbandon => 'Cancel·lar la recuperació';

  @override
  String get recoverAbandonTitle => 'Vols cancel·lar la recuperació?';

  @override
  String get recoverAbandonBody =>
      'Si cancel·les, aquest mòbil esborrarà les dades temporals de la recuperació. Si al mòbil anterior ja només podies consultar la llista, continuarà així. Podràs tornar a fer servir el codi.';

  @override
  String get recoverAbandonConfirm => 'Cancel·lar la recuperació';

  @override
  String get recoverAbandonKeep => 'Continuar';

  @override
  String get recoverAbandonFailed =>
      'Alguna cosa no ha anat bé. Torna-ho a provar d\'aquí a un moment.';

  @override
  String get recoverAbandonBodyClaimed =>
      'A l\'altre mòbil ja només pots consultar la llista. Si cancel·les, continuarà així. Per recuperar la llista hauràs de tornar a fer servir aquest codi.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'Aquest mòbil no pot bloquejar les captures de pantalla: no en facis cap.';

  @override
  String get recoverLeaveTitle => 'Vols sortir de la recuperació?';

  @override
  String get recoverLeaveBody =>
      'La recuperació quedarà pendent en aquest mòbil. Més endavant podràs reprendre-la o cancel·lar-la.';

  @override
  String get recoverPendingTitle => 'Recuperació pendent';

  @override
  String get recoverPendingBody =>
      'Es va quedar a mitges en aquest mòbil. Reprèn-la o cancel·la-la abans de crear una família o unir-te a una altra.';

  @override
  String get recoverResume => 'Reprendre';

  @override
  String get recoveryProblemPendingTitle => 'Hi ha una recuperació a mitges';

  @override
  String get recoveryProblemPendingBody =>
      'Reprèn-la o cancel·la-la abans de crear una família o unir-te a una altra.';

  @override
  String get recoveryMaintCancel => 'Cancel·lar la preparació';

  @override
  String get recoveryMaintCancelTitle =>
      'Vols cancel·lar la preparació del codi?';

  @override
  String get recoveryMaintCancelBody =>
      'El codi que ja tinguis continua valent. Es deixa de preparar el que estava en marxa.';

  @override
  String get recoveryMaintCancelConfirm => 'Cancel·lar la preparació';

  @override
  String get recoveryRemoveAuthMessage =>
      'Escriu el teu PIN per esborrar el codi.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirma que vols esborrar el codi de recuperació';

  @override
  String get transferredRecover => 'Recuperar amb el meu codi';

  @override
  String get transferredErase => 'Esborrar les dades d\'aquesta app';

  @override
  String get recoverStepDoneValue => 'fet';

  @override
  String get recoverStepActiveValue => 'en curs';

  @override
  String get recoveryFileAction => 'Desar en un fitxer';

  @override
  String get recoveryFileTitle => 'Desar en un fitxer';

  @override
  String get recoveryFileBody =>
      'També pots desar el codi en un fitxer. Qui el pugui obrir podrà recuperar la llista amb el mateix accés que tens en aquest mòbil.';

  @override
  String get recoveryFilePersonal =>
      'És un fitxer personal: no l\'enviïs a la família. Desa\'l on puguis obrir-lo encara que perdis aquest mòbil.';

  @override
  String get recoveryFileProtect => 'Protegir amb contrasenya';

  @override
  String get recoveryFileProtectOffHint =>
      'Sense contrasenya, el fitxer val tant com les paraules: qui l\'aconsegueixi el pot fer servir.';

  @override
  String get recoveryFileProtectOnHint =>
      'Amb robar el fitxer no n\'hi ha prou: cal la contrasenya.';

  @override
  String get recoveryFilePassword => 'Contrasenya';

  @override
  String get recoveryFilePasswordRepeat => 'Repeteix la contrasenya';

  @override
  String get recoveryFilePasswordShow => 'Veure';

  @override
  String get recoveryFilePasswordHide => 'Amagar';

  @override
  String recoveryFilePasswordHelp(int min) {
    return 'Mínim $min caràcters. Fes servir el gestor de contrasenyes o diverses paraules triades a l\'atzar.';
  }

  @override
  String get recoveryFilePasswordForgot =>
      'Si oblides la contrasenya, no podràs obrir el fitxer. Encara podràs recuperar la llista amb les 24 paraules.';

  @override
  String recoveryFilePwTooShort(int min) {
    return 'És massa curta: mínim $min caràcters.';
  }

  @override
  String recoveryFilePwTooLong(int max) {
    return 'És massa llarga: màxim $max caràcters.';
  }

  @override
  String get recoveryFilePwRepeated => 'Es repeteix un mateix caràcter o bloc.';

  @override
  String get recoveryFilePwDigits => 'No pot ser només números.';

  @override
  String get recoveryFilePwKeyboard => 'Sembla una fila o seqüència de tecles.';

  @override
  String get recoveryFilePwAppName => 'No pot contenir el nom de l\'app.';

  @override
  String get recoveryFilePwCommon => 'És una frase massa comuna.';

  @override
  String get recoveryFilePwMismatch => 'Les dues contrasenyes no coincideixen.';

  @override
  String get recoveryFileSave => 'Desar';

  @override
  String get recoveryFileSaveAgain => 'Desar una altra còpia';

  @override
  String get recoveryFileShare => 'Compartir';

  @override
  String get recoveryFileShareText =>
      'Fitxer de recuperació de Gift Huddle. És personal: no el reenviïs a la família.';

  @override
  String get recoveryFileStem => 'gift-huddle-recuperacio';

  @override
  String get recoveryFileDerivingTitle => 'Processant el fitxer…';

  @override
  String get recoveryFileDerivingBody =>
      'Mantén l\'app oberta. Aquest pas triga uns segons.';

  @override
  String get recoveryFileSavedTitle => 'Fitxer desat';

  @override
  String get recoveryFileSavedBody =>
      'S\'ha tornat a llegir des d\'on l\'has desat i el codi està comprovat. Pots desar-ne una altra còpia.';

  @override
  String get recoveryFileProblemVerifyTitle =>
      'No s\'ha pogut comprovar el que s\'ha desat';

  @override
  String get recoveryFileProblemVerifyBody =>
      'El fitxer no s\'ha desat bé. Torna\'l a desar, potser en un altre lloc.';

  @override
  String get recoveryFileProblemUnreadableTitle =>
      'No s\'ha pogut llegir el fitxer';

  @override
  String get recoveryFileProblemUnreadableBody =>
      'Comprova que el fitxer està disponible en aquest mòbil i torna-ho a provar.';

  @override
  String get recoveryFileProblemUnavailableTitle =>
      'Aquest mòbil no pot obrir el selector de fitxers';

  @override
  String get recoveryFileProblemUnavailableBody =>
      'Prova amb «Compartir» o fes servir les 24 paraules.';

  @override
  String get recoveryFileProblemPickerBusyTitle =>
      'Ja hi ha un selector de fitxers obert';

  @override
  String get recoveryFileProblemPickerBusyBody =>
      'Tanca\'l i torna-ho a provar.';

  @override
  String get recoveryFileProblemNotFileTitle =>
      'No és un fitxer de recuperació';

  @override
  String get recoveryFileProblemNotFileBody =>
      'Tria el fitxer que vas desar en crear el codi. Acaba en .gifthuddle.';

  @override
  String get recoveryFileProblemNewerTitle => 'Fitxer d\'una versió més nova';

  @override
  String get recoveryFileProblemNewerBody =>
      'Actualitza l\'app i torna-ho a provar.';

  @override
  String get recoveryFileProblemPasswordTitle =>
      'Contrasenya incorrecta o fitxer malmès';

  @override
  String get recoveryFileProblemPasswordBody =>
      'Revisa la contrasenya. Si no te\'n recordes, fes servir les 24 paraules.';

  @override
  String get recoveryFileProblemNotCurrentTitle =>
      'Aquest fitxer és d\'un altre codi';

  @override
  String get recoveryFileProblemNotCurrentBody =>
      'Aquest fitxer conté un codi anterior i ja no serveix. Busca un fitxer més recent o canvia el codi.';

  @override
  String get recoveryFileProblemHasFamilyTitle =>
      'Aquest mòbil ja té una llista';

  @override
  String get recoveryFileProblemHasFamilyBody =>
      'El fitxer de recuperació només serveix en un mòbil sense llista. No s\'ha fet servir.';

  @override
  String get recoveryCheckFileAction => 'Comprovar un fitxer';

  @override
  String get recoveryCheckFileTitle => 'Comprovar un fitxer';

  @override
  String get recoveryCheckFileBody =>
      'Tria el fitxer de recuperació que vas desar. L\'app comprovarà si conté el codi d\'aquest mòbil. No es desa ni s\'envia res.';

  @override
  String get recoveryFilePick => 'Triar un fitxer';

  @override
  String get recoveryFilePasswordTitle => 'Contrasenya del fitxer';

  @override
  String get recoveryFilePasswordOpenBody =>
      'Aquest fitxer està protegit. Escriu la contrasenya que vas posar en desar-lo.';

  @override
  String get recoveryFileOpen => 'Obrir el fitxer';

  @override
  String get recoveryFileCheckingTitle => 'Comprovant el fitxer…';

  @override
  String get recoveryFileCheckingBody => 'Un moment.';

  @override
  String get recoveryCheckFileOkTitle => 'Codi comprovat';

  @override
  String get recoveryCheckFileOkBody =>
      'El fitxer conté el codi d\'aquest mòbil. Si perds el mòbil, podràs fer servir el fitxer per recuperar la llista.';

  @override
  String get obRecoverWithFile => 'Fer servir el fitxer de recuperació';

  @override
  String get recoverFileTitle => 'Recupera amb un fitxer';

  @override
  String get recoverFileBody =>
      'Tria el fitxer de recuperació que vas desar en crear el codi. Acaba en .gifthuddle.';

  @override
  String get recoverFileReceived => 'Has obert un fitxer de recuperació.';

  @override
  String get recoverFileConfirmTitle => 'Vols recuperar amb aquest fitxer?';

  @override
  String get recoverFileConfirmBody =>
      'Aquest mòbil recuperarà la llista i ocuparà dins la família el lloc del mòbil que va desar el codi. Continua només si el fitxer és teu.';

  @override
  String get recoverFileOther => 'Triar un altre fitxer';

  @override
  String get recoverFileWaitingTitle => 'Vols canviar de fitxer?';

  @override
  String get recoverFileWaitingBody =>
      'Has rebut un fitxer de recuperació mentre en feies servir un altre.';

  @override
  String get recoverFileWaitingSwitch => 'Triar el nou';

  @override
  String get recoverFileWaitingKeep => 'Continuar amb l\'actual';

  @override
  String get recoveryProblemPersonTitle =>
      'El codi ja no és vàlid per a la persona triada';

  @override
  String get recoveryProblemPersonBody =>
      'Ha canviat la persona triada a «Aquest mòbil és de» o hi ha un canvi pendent. Crea un codi nou i desa\'l.';

  @override
  String get recoveryFileProblemStorageTitle =>
      'No s\'ha pogut llegir la llista d\'aquest mòbil';

  @override
  String get recoveryFileProblemStorageBody =>
      'El fitxer encara està pendent d\'obrir. L\'app ha de comprovar si ja hi ha una llista en aquest mòbil. Torna-ho a provar.';

  @override
  String get cameraRestricted =>
      'La càmera està restringida en aquest dispositiu (per exemple, amb Temps d\'ús). La pots permetre a Configuració > Temps d\'ús > Restriccions de contingut i privadesa.';

  @override
  String get obJoinFamily => 'Unir-me a una família';

  @override
  String get obJoinFamilyHint =>
      'Tria com connectar-te amb el mòbil que ja té la llista.';

  @override
  String get obJoinQrHint =>
      'Si tens l\'altre mòbil a mà, escaneja\'n el codi QR.';

  @override
  String get obJoinLinkHint =>
      'Si l\'altre mòbil és lluny, enganxa l\'enllaç que t\'han enviat.';

  @override
  String get obRestoreBackup => 'Recuperar una còpia';

  @override
  String get obRestoreBackupHint => 'Tria com vols recuperar la llista.';

  @override
  String get obRestoreCodeHint => 'Escriu les 24 paraules que vas desar.';

  @override
  String get obRestoreFileHint =>
      'Obre el fitxer de recuperació que vas desar.';

  @override
  String get giverPeopleSection => 'Persones';

  @override
  String get giverPeopleHintAdd => 'Primer s\'afegeix als qui regalen';

  @override
  String get giverPeopleHintRecover => 'Tornarà a la llista dels qui regalen';

  @override
  String giverPersonAddTitle(String name) {
    return 'Afegir $name a la llista dels qui regalen?';
  }

  @override
  String giverPersonAddBody(String name) {
    return 'Aquest regal és una sorpresa. Primer, afegeix $name a la llista dels qui regalen. Tota la família hi veurà el seu nom, sense cap referència al regal. Després podràs triar $name aquí.';
  }

  @override
  String giverPersonAddConfirm(String name) {
    return 'Afegir $name';
  }

  @override
  String giverPersonAddFailed(String name) {
    return 'No s\'ha pogut afegir $name a la llista dels qui regalen. Torna-ho a provar.';
  }

  @override
  String get giftNoLongerVisible =>
      'Aquest regal ja no es pot veure en aquest mòbil.';

  @override
  String deleteGiverRows(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'S\'eliminen aquests $count noms: $names.',
      one: 'S\'elimina $names.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverGiftTitles(String titles, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: 'Afecta: $titles i $more més.',
      zero: 'Afecta: $titles.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverLinkedNote(String name) {
    return '$name continuarà a «Persones». Només s\'eliminarà de «Qui regala».';
  }

  @override
  String get deleteImpactChanged =>
      'La llista ha canviat. Abans de confirmar, revisa què s\'eliminarà.';

  @override
  String get deletePersonLinkedGiver =>
      'El seu nom continuarà a «Qui regala» als regals que fa a altres persones.';

  @override
  String devicePersonBlockedThisTitle(String name) {
    return 'Aquest mòbil és de $name';
  }

  @override
  String devicePersonBlockedThisBody(String name) {
    return 'Per eliminar o arxivar $name, ves a Ajustos i tria primer una altra persona a «Aquest mòbil és de».';
  }

  @override
  String devicePersonBlockedOtherTitle(String name) {
    return '$name té el seu propi mòbil';
  }

  @override
  String devicePersonBlockedOtherBody(String name) {
    return '$name té el seu propi mòbil a la família, així que no es pot eliminar ni arxivar des d\'aquí.';
  }

  @override
  String get giverLinkedLine =>
      'Enllaçat a una persona: el nom i el color es canvien a Persones.';

  @override
  String giverLinkedNameHint(String name) {
    return 'El nom i el color són els de $name. Canvia\'ls a Persones.';
  }

  @override
  String get giverLinkLabel => 'Enllaçar amb una persona';

  @override
  String get giverLinkHint =>
      'El nom i el color passaran a ser els de la persona.';

  @override
  String get giverLinkExistingHint =>
      'Ja regala. Les dues columnes de Repartiment s\'uniran en una.';

  @override
  String giverLinkConfirmTitle(String name) {
    return 'Enllaçar amb $name?';
  }

  @override
  String giverLinkConfirmBody(String giver, String name) {
    return '«$giver» tindrà el nom i el color de $name. Si els canvies a la fitxa de $name a Persones, també canviaran aquí. Els regals es conservaran.';
  }

  @override
  String get giverLinkConfirm => 'Enllaçar';

  @override
  String get giverUnlinkLabel => 'Desenllaçar de la persona';

  @override
  String giverUnlinkConfirmTitle(String name) {
    return 'Desenllaçar de $name?';
  }

  @override
  String giverUnlinkConfirmBody(String name) {
    return 'Continuarà a la llista dels qui regalen amb el nom, el color i els regals que té ara. Els canvis que facis a la fitxa de $name ja no s\'aplicaran aquí.';
  }

  @override
  String get giverUnlinkConfirm => 'Desenllaçar';

  @override
  String get giverLinkError =>
      'No s\'ha pogut canviar l\'enllaç. Torna-ho a provar.';

  @override
  String get giftWriteGiftUnavailable =>
      'No s\'ha desat: aquest regal ja no està disponible en aquest mòbil.';

  @override
  String get giftWriteRecipientGone =>
      'No s\'ha desat: la persona que havia de rebre el regal ja no és a la llista.';

  @override
  String get giftWriteInvalidPair =>
      'No s\'ha desat: qui regala no pot ser qui rep el regal.';

  @override
  String get giftWriteGiverGone =>
      'No s\'ha desat: qui regala ja no és a la llista.';

  @override
  String get giftWriteGiverArchived =>
      'No s\'ha desat: qui regala està arxivat.';

  @override
  String get giftWritePersonGone =>
      'No s\'ha desat: aquesta persona ja no és a la llista.';

  @override
  String get giftWritePersonArchived =>
      'No s\'ha desat: aquesta persona està arxivada.';

  @override
  String giverUnlinkStale(String name) {
    return 'Ja no estava enllaçat a $name.';
  }

  @override
  String get deleteImpactUnavailable =>
      'No s\'ha pogut comprovar què s\'eliminaria. Torna-ho a provar.';

  @override
  String get deleteImpactChecking => 'Comprovant què s\'elimina…';

  @override
  String get inviteForTitle => 'Per a qui és el mòbil nou?';

  @override
  String get inviteForBody =>
      'Tria la persona que el farà servir. Al seu mòbil no es veurà cap regal per a ella.';

  @override
  String get inviteForNeedsSelf =>
      'Abans de connectar un altre dispositiu, digues de qui és aquest mòbil.';

  @override
  String inviteForSecretNotice(String name) {
    return 'Els regals per a $name passen a estar en secret: deixaran de veure\'s al seu mòbil.';
  }

  @override
  String pairingV2HostCompareFor(String name) {
    return 'Connectaràs el mòbil de $name.';
  }

  @override
  String get pairingV2HostUpdateHint =>
      'Si l\'altre mòbil dona un error, actualitza Gift Huddle en aquell mòbil i torna a començar.';

  @override
  String pairingV2ProtectFailed(String name) {
    return 'No s\'han pogut posar en secret els regals per a $name, així que el mòbil no s\'ha connectat. Aquell mòbil ha quedat tret i potser haurà de tornar a connectar-se. Aquest mòbil continua amagant els regals de la seva persona. Sincronitza i torna-ho a provar.';
  }

  @override
  String get pairingV2GuestAssigned =>
      'Qui et convida ha triat de qui és aquest mòbil. Ho veuràs en entrar.';

  @override
  String pairingV2GuestDoneFor(String name) {
    return 'Ja ets a la família. Aquest mòbil és de $name: aquí no veuràs els regals per a $name.';
  }

  @override
  String ownGiftsHiddenBody(String name) {
    return 'En aquest mòbil no es veuen els regals per a $name. Només una altra persona de la família ho pot canviar, des del seu mòbil.';
  }

  @override
  String protectionAutoReason(String name) {
    return 'Actius perquè $name té un mòbil connectat.';
  }

  @override
  String protectionDeactivateHasDevice(String name) {
    return '$name té un mòbil connectat: s\'hi continuaran sense veure els seus regals. Si els desactives, es veuran als dispositius que no tenen la clau, com el web.';
  }

  @override
  String ownGiftsAloneNotice(String name) {
    return 'Aquest mòbil ja no està connectat a cap altre. Els regals per a $name que estaven en secret no són en aquest mòbil.';
  }

  @override
  String get whoAreYouTitle => 'Qui ets?';

  @override
  String get whoAreYouBody =>
      'Abans de connectar un altre dispositiu, digues de qui és aquest mòbil. Al mòbil no es veurà cap regal per a aquesta persona.';

  @override
  String get whoAreYouNotOnList => 'No soc a la llista';

  @override
  String get whoAreYouNameLabel => 'El teu nom';

  @override
  String get whoAreYouNobody => 'Ningú';

  @override
  String get whoAreYouNobodyHint => 'Per a qui regala i no rep regals.';

  @override
  String get inviteForNotOnList => 'No és a la llista';

  @override
  String get inviteForNobody => 'Ningú: només regala';

  @override
  String get inviteForNameLabel => 'Nom';

  @override
  String get personNoGiftsLabel => 'Només regala';

  @override
  String get joinQrPairingTitle => 'Connectar aquest mòbil';

  @override
  String protectionReason_webUseMobile(String name) {
    return 'Els regals en secret de $name es canvien des del teu mòbil.';
  }

  @override
  String get webSecretsPending => 'Pendent';

  @override
  String get webSecretsReconnect =>
      'Per veure els regals en secret, torna a connectar aquest ordinador des del teu mòbil.';

  @override
  String get webSecretsWaitingPhone =>
      'Obre l\'app al teu mòbil per veure aquí els regals en secret. Si no hi apareixen, actualitza l\'app del mòbil.';

  @override
  String get webSecretsSharedComputer =>
      'Amb els regals en secret a la vista, la web es bloqueja als 5 minuts sense ús. No la deixis oberta en un ordinador que comparteix la família.';

  @override
  String get webForgetPendingSecrets =>
      'Hi ha canvis en regals en secret que el teu mòbil encara no ha recollit. Si oblides aquest ordinador, es perden.';

  @override
  String webSecretsDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'S\'han descartat $count canvis en regals en secret: ja no es poden aplicar (els regals ja no existeixen, han passat a una altra persona o són massa llargs).',
      one:
          'S\'ha descartat $count canvi en un regal en secret: ja no es pot aplicar (el regal ja no existeix, ha passat a una altra persona o és massa llarg).',
    );
    return '$_temp0';
  }

  @override
  String ownGiftsNoticeTitle(String name) {
    return 'Regals per a $name';
  }

  @override
  String get webApproveSecretsNotice =>
      'Aquest ordinador podrà veure i canviar els regals en secret dels altres. Confirma-ho només si el vas connectar tu.';

  @override
  String webSecretsHeld(String names) {
    return 'Els canvis en regals en secret per a $names encara no s\'han pogut enviar. Es torna a provar sol.';
  }

  @override
  String get webSecretsPendingLong => 'Pendent del teu mòbil';

  @override
  String get giftSearchOpen => 'Cerca regals';

  @override
  String get pairingV2GuestOutdated =>
      'L\'altre mòbil necessita actualitzar Gift Huddle per unir-s\'hi.';

  @override
  String get pairingV2ApproveFailed =>
      'No s\'ha pogut donar accés a l\'altre mòbil. Ha quedat tret i potser haurà de tornar a connectar-se. Aquest mòbil continua amagant els regals de la seva persona.';

  @override
  String get secretBlockNoteWeb => 'Aquest ordinador no els mostra.';

  @override
  String ownGiftsHiddenBodyWeb(String name) {
    return 'En aquest ordinador no es veuen els regals per a $name. Només una altra persona de la família ho pot canviar, des del seu mòbil.';
  }

  @override
  String ownGiftsAloneNoticeWeb(String name) {
    return 'Aquest ordinador ja no està connectat a cap mòbil de la família. Els regals per a $name que estaven en secret no són en aquest ordinador.';
  }

  @override
  String get manageLockedThisDeviceWeb => 'És la persona d\'aquest ordinador.';

  @override
  String devicePersonBlockedThisTitleWeb(String name) {
    return 'Aquest ordinador és de $name';
  }

  @override
  String devicePersonBlockedThisBodyWeb(String name) {
    return '$name és la persona d\'aquest ordinador, així que no es pot eliminar ni arxivar des d\'aquí.';
  }

  @override
  String get giftNotSavedWeb =>
      'No s\'ha desat: aquest regal ja no està disponible en aquest ordinador.';

  @override
  String get giftWriteGiftUnavailableWeb =>
      'No s\'ha desat: aquest regal ja no està disponible en aquest ordinador.';

  @override
  String get giftNoLongerVisibleWeb =>
      'Aquest regal ja no es pot veure en aquest ordinador.';

  @override
  String get giftOwnRequestRestrictedWeb =>
      'Amb la protecció activa, en aquest ordinador no pots afegir ni veure regals per a tu. Demana a algú altre de la família que apunti el regal.';

  @override
  String get aboutPrivacyWeb =>
      'Sense comptes ni publicitat. La llista només surt d\'aquest ordinador per sincronitzar-se amb els mòbils de la teva família, i sempre va xifrada.';
}

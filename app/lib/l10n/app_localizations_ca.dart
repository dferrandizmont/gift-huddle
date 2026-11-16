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
  String get emptyFamilyTitle => 'Ningú ha apuntat regals';

  @override
  String get emptyFamilyMessage => 'Aquí veuràs qui regala què a cada persona.';

  @override
  String get emptyOccasionsTitle => 'Sense ocasions';

  @override
  String get emptyOccasionsMessage =>
      'Nadal, aniversaris i altres dates apareixeran aquí amb el compte enrere.';

  @override
  String backTo(String title) {
    return 'Torna a $title';
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
      'La llista d\'una ocasió canvia d\'accent i de capçalera.';

  @override
  String get appearanceHapticsTitle => 'Vibracions';

  @override
  String get appearanceHapticsHint =>
      'Petits tocs en marcar, triar o quan alguna cosa arriba.';

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
    return 'Canvia l\'estat de $item. Estat actual: $status';
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
  String get shareEnvelopeText => 'Canvis de Gift Huddle: obre\'l amb l\'app.';

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
      'L\'altre mòbil té la data i l\'hora mal posades. Corregeix-les i torna a enviar-ho.';

  @override
  String get shareErrorLegacyFile =>
      'Aquest fitxer és d\'una versió anterior de Gift Huddle i ja no s\'obre. Desa\'l i demana que te\'l tornin a enviar des d\'un mòbil actualitzat.';

  @override
  String get shareErrorNotReady =>
      'Aquest mòbil encara no està al dia amb la família. Sincronitza i torna a obrir el fitxer.';

  @override
  String get shareErrorGeneration =>
      'Aquest fitxer és d\'una versió anterior de la llista. Demana que te n\'enviïn un de nou.';

  @override
  String get shareErrorRevokedWriter =>
      'Aquest fitxer el va desar un mòbil que ja no és de la família. No s\'hi ha afegit res.';

  @override
  String get shareErrorMissingKey =>
      'Encara no es pot obrir aquest fitxer. S\'ha desat i s\'obrirà sol quan sincronitzis.';

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
  String get lockUnlock => 'Desbloqueja';

  @override
  String get lockBackspace => 'Esborra';

  @override
  String get lockBiometric => 'Fes servir l\'empremta o el rostre';

  @override
  String get lockBiometricReason => 'Desbloqueja Gift Huddle';

  @override
  String get lockBiometricNotice =>
      'Qualsevol empremta o cara registrada al mòbil podrà obrir l\'app.';

  @override
  String get lockLoadError => 'No s\'ha pogut comprovar el bloqueig.';

  @override
  String get lockRetry => 'Torna-ho a provar';

  @override
  String lockWrongPin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Queden $count intents',
      one: 'Queda $count intent',
    );
    return 'PIN incorrecte. $_temp0 abans de haver d\'esperar.';
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
  String get pinContinue => 'Continua';

  @override
  String get pinSave => 'Desa el PIN';

  @override
  String get pinSkip => 'Ara no';

  @override
  String get pinBiometricOfferTitle => 'Vols activar l\'empremta o el rostre?';

  @override
  String get pinBiometricOfferEnable => 'Activa';

  @override
  String get actionSave => 'Desa';

  @override
  String get actionCancel => 'Cancel·la';

  @override
  String get actionDelete => 'Esborra';

  @override
  String get actionNext => 'Següent';

  @override
  String get actionBack => 'Enrere';

  @override
  String get actionEdit => 'Edita';

  @override
  String get actionClose => 'Tanca';

  @override
  String get actionDone => 'Fet';

  @override
  String get actionArchive => 'Arxiva';

  @override
  String get actionRestore => 'Recupera';

  @override
  String get actionUndo => 'Desfés';

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
      'Si ho paga la casa, compta al pressupost.';

  @override
  String countdownDaysForBirthday(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dies per a l\'aniversari de $name',
      one: 'dia per a l\'aniversari de $name',
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
      'Apunta què regala cadascú a cada persona, perquè ningú repeteixi i a ningú no li falti res.';

  @override
  String get obWelcomePrivacy =>
      'Sense comptes. Si sincronitzeu dos mòbils, la llista viatja xifrada i només els vostres mòbils la poden llegir.';

  @override
  String get obDeviceNameLabel => 'Nom d\'aquest mòbil';

  @override
  String get obDeviceNameHint =>
      'És el nom que veurà l\'altre mòbil. Pots canviar-lo.';

  @override
  String get obStart => 'Comença';

  @override
  String get obHaveListTitle => 'Ja teniu la llista en un altre mòbil?';

  @override
  String get obPeopleTitle => 'A qui regaleu?';

  @override
  String get obPeopleBody =>
      'Afegeix les persones a qui regaleu: parella, germans, nebots, nens… Cal almenys una.';

  @override
  String get obPeopleAdd => 'Afegeix una persona';

  @override
  String get obPeopleNeedOne => 'Afegeix almenys una persona per continuar.';

  @override
  String obRemove(String name) {
    return 'Treu $name';
  }

  @override
  String get obGiversTitle => 'Qui regala?';

  @override
  String get obGiversBody =>
      '«Nosaltres» ja està creat i ho paga la casa. Afegeix els avis, els oncles…';

  @override
  String get obGiversSuggestions => 'Afegeix ràpid';

  @override
  String get obGiverGrandparents => 'Avis';

  @override
  String get obGiverUncles => 'Oncles';

  @override
  String get obGiverFriends => 'Amics';

  @override
  String obAddNamed(String name) {
    return 'Afegeix $name';
  }

  @override
  String get giverNew => 'Afegeix qui regala';

  @override
  String get giverEdit => 'Edita qui regala';

  @override
  String get giverNameHint => 'Avis, Tia Marta i Jordi…';

  @override
  String get obOccasionsTitle => 'Quan hi ha regals?';

  @override
  String get obOccasionsBody =>
      'Tria les dates de sempre. Els aniversaris surten sols de les dates que hagis posat.';

  @override
  String get obBirthdaysSection => 'Aniversaris (es creen sols)';

  @override
  String get obNoBirthdays =>
      'Si afegeixes la data de naixement d\'algú, el seu aniversari apareixerà aquí.';

  @override
  String get obOtherOccasions => 'Altres dates';

  @override
  String get obAddOccasion => 'Afegeix una altra data';

  @override
  String get obPinTitle => 'Protegeix els regals';

  @override
  String get obPinBody =>
      'Crea un PIN perquè ningú vegi els regals si agafa el mòbil. Podràs canviar-lo als Ajustos.';

  @override
  String get obPinCreate => 'Crea un PIN';

  @override
  String get obFinishing => 'Preparant la teva llista…';

  @override
  String get obSaveError => 'No s\'ha pogut desar. Torna-ho a provar.';

  @override
  String get personNew => 'Nova persona';

  @override
  String get personEdit => 'Edita la persona';

  @override
  String get personColor => 'Color';

  @override
  String get personRelation => 'Relació (opcional)';

  @override
  String get personRelationHint => 'Parella, germà, neboda…';

  @override
  String get personBirthday => 'Aniversari (opcional)';

  @override
  String get personBirthdayPick => 'Tria una data';

  @override
  String get personBirthdayNone => 'Sense data';

  @override
  String get personBirthdayClear => 'Treu la data';

  @override
  String get personBirthdayNoYear => 'No desis l\'any';

  @override
  String personPendingBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'falten $count per comprar',
      one: 'falta $count per comprar',
    );
    return '$_temp0';
  }

  @override
  String get personAllBought => 'tot comprat';

  @override
  String get giftAdd => 'Afegeix un regal';

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
    return 'Ho ha demanat $name';
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
  String get filtersSheetTitle => 'Filtra els regals';

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
    return 'Treu el filtre $name';
  }

  @override
  String get filterClear => 'Treu els filtres';

  @override
  String get filterNoResults => 'Cap regal compleix els filtres.';

  @override
  String get giftEditorNewTitle => 'Nou regal';

  @override
  String get giftEditorEditTitle => 'Edita el regal';

  @override
  String get giftEditorNoPeople =>
      'Afegeix primer la persona que rebrà el regal.';

  @override
  String get giftRecipientRequired => 'Tria per a qui és el regal.';

  @override
  String giftAddedNotice(String name) {
    return 'Regal afegit a $name';
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
  String get giftFieldNote => 'Nota';

  @override
  String get giftFieldSize => 'Talla o edat';

  @override
  String get giftRequestSwitch => 'És un encàrrec: ho ha demanat algú';

  @override
  String get giftRequestedByField => 'Qui ho ha demanat';

  @override
  String get giftRequestedByOther => 'Una altra persona…';

  @override
  String get giftRequestedByName => 'Nom de qui ho ha demanat';

  @override
  String get giftRequestNote => 'Nota de l\'encàrrec';

  @override
  String get giftSurpriseSwitch => 'És una sorpresa';

  @override
  String get giftSurpriseHint =>
      'Es marca perquè ningú ho expliqui davant de qui ho rep.';

  @override
  String get giftDelete => 'Esborra el regal';

  @override
  String confirmDeleteTitle(String name) {
    return 'Esborrar «$name»?';
  }

  @override
  String get confirmDeleteBody =>
      'S\'esborra també als mòbils de la teva família.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done de $total comprats';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Tot comprat per a $occasion';
  }

  @override
  String get giftSaveError => 'No s\'ha pogut desar el regal.';

  @override
  String get giftDuplicateTitle => 'Possible duplicat';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return '«$title» s\'assembla a un regal que ja està apuntat per a $person ($giver).';
  }

  @override
  String get giftDuplicateSave => 'Desa igualment';

  @override
  String get giftDuplicateReview => 'Revisa';

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
    return '$giver per a $person: res encara, afegeix un regal';
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
  String get occasionEdit => 'Edita l\'ocasió';

  @override
  String get occasionNameHint => 'Comunió, final de curs…';

  @override
  String get occasionDate => 'Data';

  @override
  String get occasionDatePick => 'Tria una data';

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
  String get budgetCardHint => 'Previst, gastat i el que queda';

  @override
  String get occasionPeopleSection => 'Cada persona';

  @override
  String get occasionToWrap => 'per embolicar';

  @override
  String get occasionToArrive => 'per arribar';

  @override
  String get occasionNoGifts => 'Encara no hi ha regals per a aquesta ocasió.';

  @override
  String get occasionNoGiftsYet => 'Encara sense regals';

  @override
  String occasionSplitLabel(String name, String parts) {
    return 'Repartiment de $name: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Pendent de comprar';

  @override
  String get occasionPendingEmpty =>
      'Encara no hi ha res decidit. Quan una idea passi a Decidit, apareixerà aquí agrupada per botiga.';

  @override
  String get occasionStoreNone => 'Sense botiga';

  @override
  String occasionMarkBought(String item) {
    return 'Marca $item com a comprat';
  }

  @override
  String get occasionIdeasSection => 'Idees';

  @override
  String get budgetTitle => 'Pressupost';

  @override
  String get budgetSubtitle => 'Només el que paga la casa';

  @override
  String get budgetPlanned => 'Previst';

  @override
  String get budgetSpent => 'Gastat';

  @override
  String get budgetLeft => 'Queda';

  @override
  String get budgetOver => 'Et passes';

  @override
  String get budgetByPerson => 'Per persona';

  @override
  String get budgetByOccasion => 'Per ocasió';

  @override
  String get budgetNote =>
      'El que regalen els avis o els oncles compta com a regal, no com a despesa de la casa.';

  @override
  String get budgetEmpty =>
      'Encara no hi ha regals que pagui la casa. Marca «Ho paga la casa» a qui regala i posa un preu previst.';

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
      'Sense comptes ni publicitat. Els teus regals només surten del mòbil, sempre xifrats, si connectes un altre mòbil o la web, crees un codi de recuperació o envies una còpia.';

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
      'Arxivar treu alguna cosa de les llistes sense esborrar els seus regals; es recupera a Ajustos › Arxiu. Eliminar ho esborra per sempre.';

  @override
  String manageArchiveLabel(String name) {
    return 'Arxiva $name';
  }

  @override
  String manageRestoreLabel(String name) {
    return 'Recupera $name';
  }

  @override
  String get securityPinTitle => 'Bloqueig amb PIN';

  @override
  String get securityPinHint => 'Demana el PIN en obrir l\'app.';

  @override
  String get securityChangePin => 'Canvia el PIN';

  @override
  String get securityBiometrics => 'Empremta o rostre';

  @override
  String get securityBiometricsHint => 'Obre l\'app sense teclejar el PIN.';

  @override
  String get securityBiometricsUnavailable =>
      'Aquest mòbil no té empremta ni rostre configurats.';

  @override
  String get securityBiometricsFailed =>
      'No s\'ha pogut activar. Comprova l\'empremta o el rostre del mòbil.';

  @override
  String get securityDisableTitle => 'Treu el PIN';

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
      'A l\'altre mòbil obre Gift Huddle, toca «Escanejar el QR» i apunta la càmera a aquest codi.';

  @override
  String get showQrWarning =>
      'No facis cap captura ni el comparteixis: aquest codi dona accés a tota la llista. Ensenya\'l només en persona.';

  @override
  String get showQrLabel => 'Codi QR per connectar un altre mòbil';

  @override
  String get joinIntro => 'Apunta la càmera al codi QR de l\'altre mòbil.';

  @override
  String get joinCameraError =>
      'No es pot fer servir la càmera. Revisa el permís de càmera als ajustos del mòbil.';

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
  String get scannerRetry => 'Torna-ho a provar';

  @override
  String get scannerOpenSettings => 'Obre els ajustos';

  @override
  String get joinConflictTitle => 'Aquest mòbil ja té una llista';

  @override
  String get joinConflictBody =>
      'Si t\'uneixes a la de l\'altre mòbil, aquesta llista se substitueix i es perden els seus regals. Continuar?';

  @override
  String get joinReplace => 'Substitueix i uneix-me';

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
      other: '$count canviats',
      one: '$count canviat',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count esborrats',
      one: '$count esborrat',
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
      'Aquest mòbil surt de la sincronització de la família i deixa d\'enviar i rebre canvis; els altres mòbils continuen sincronitzant entre ells. Si és l\'últim, també s\'esborra la còpia xifrada del servidor. El que hi ha a cada mòbil es queda tal com està. Per tornar a sincronitzar, connecta\'l de nou amb un altre mòbil de la família.';

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
  String get syncStatusWaitingPeer => 'Començarà quan aparellis un altre mòbil';

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
  String get syncStatusOffline => 'Sense connexió, s\'enviarà després';

  @override
  String get syncStatusError => 'No s\'ha pogut sincronitzar';

  @override
  String get syncIssueAuth =>
      'El servidor no accepta la clau d\'aquesta família.';

  @override
  String get syncIssueClockDrift =>
      'Un altre mòbil té la data i l\'hora mal posades. Corregeix-les en aquell mòbil.';

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
      'Crea un enllaç perquè una altra persona s\'uneixi a la teva família des del seu mòbil, sense ser-hi al davant.';

  @override
  String get inviteHowItWorks =>
      'L\'enllaç no porta cap clau: només serveix per demanar entrada. Rebràs la petició amb un codi de 6 xifres i l\'hauràs d\'acceptar tu. Caduca a les 24 hores i serveix per a una sola persona.';

  @override
  String get inviteCreate => 'Crear enllaç i convidar';

  @override
  String get inviteNeedSync =>
      'Per convidar a distància cal tenir la sincronització encesa i amb connexió.';

  @override
  String get inviteGoToSync => 'Encendre la sincronització';

  @override
  String inviteShareText(String link) {
    return 'Et convido a la meva llista de Gift Huddle. Obre l\'enllaç i demana entrar: $link';
  }

  @override
  String get inviteWaitingTitle => 'Esperant que obrin l\'enllaç';

  @override
  String get inviteWaitingBody =>
      'Quan l\'altra persona l\'obri, aquí veuràs la seva petició. Pots sortir d\'aquesta pantalla: la invitació continua activa fins que caduqui.';

  @override
  String inviteExpires(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'Caduca el $dateString a les $timeString';
  }

  @override
  String get inviteShareAgain => 'Compartir l\'enllaç una altra vegada';

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
      'Has rebutjat la petició. L\'enllaç ja no serveix.';

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
      'No s\'ha pogut completar. Torna-ho a provar.';

  @override
  String get joinInviteTaken =>
      'Aquesta invitació ja l\'ha demanada una altra persona. Demana un enllaç nou.';

  @override
  String get joinInviteGone => 'La invitació ha caducat o no s\'ha acceptat.';

  @override
  String get joinInviteWaitingTitle => 'Esperant que t\'acceptin';

  @override
  String get joinInviteWaitingBody =>
      'Qui t\'ha convidat ha de veure la teva petició. D\'aquí uns segons veuràs aquí un codi per comparar amb aquesta persona. Pots esperar fins a 10 minuts.';

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
    return 'Ja ets a la família de $name. La llista arribarà d\'aquí uns segons.';
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
    return '$count sense qui';
  }

  @override
  String repartoSheetNobodyYet(String giver, String person) {
    return '$giver encara no regala res a $person';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return '$person té regals sense qui els reguli: toca «Qui?» per donar-los.';
  }

  @override
  String get repartoSheetStartHint => 'Apunta un regal nou per començar.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · toca qui regala per canviar-ho';
  }

  @override
  String get repartoSheetWho => 'Qui?';

  @override
  String get repartoSheetNobody => 'Ningú';

  @override
  String get repartoSheetAddGift => 'Afegeix un regal';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'Regal nou de $giver';
  }

  @override
  String repartoSheetOpenList(String person) {
    return 'Veure la llista de $person';
  }

  @override
  String get repartoSheetNoGiver => 'Sense qui regali';

  @override
  String repartoSheetChipLabel(String giver) {
    return 'Qui regala: $giver. Canvia';
  }

  @override
  String repartoSheetLabel(String giver, String person) {
    return 'Regals de $giver per a $person';
  }

  @override
  String get lockBiometricHint => 'Toca l\'empremta per entrar';

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
  String get repartoOccasionAddShort => 'Afegeix';

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
    return 'Obre la fitxa de $person';
  }

  @override
  String get repartoSelfTag => 'Jo';

  @override
  String repartoSelfName(String name) {
    return '$name (jo)';
  }

  @override
  String get repartoPersonSheetSub =>
      'Com surt a Repartiment. No s\'esborra cap regal.';

  @override
  String get repartoPersonInReparto => 'Surt al repartiment';

  @override
  String get repartoPersonInRepartoHint =>
      'Si ho lleves, passa a «Fora del repartiment».';

  @override
  String get repartoPersonOccasions => 'Li regaleu a';

  @override
  String familyOutsideTitle(int count) {
    return 'Fora del repartiment · $count';
  }

  @override
  String get familyOutsideNote => 'No surt al repartiment';

  @override
  String get familyIncludeAgain => 'Torna a incloure';

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
  String get actionEliminate => 'Elimina';

  @override
  String manageDeleteLabel(String name) {
    return 'Elimina $name';
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
      other: 'S\'eliminaran també els seus $count regals.',
      one: 'S\'eliminarà també el seu regal.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo => 'El seu aniversari també desapareix.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Els seus $count regals es quedaran sense qui regala.',
      one: 'El seu regal es quedarà sense qui regala.',
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
      'Als regals que va demanar s\'esborra qui els va demanar.';

  @override
  String get deleteGiverBudget =>
      'Els seus imports deixen de comptar al pressupost de la casa.';

  @override
  String get deleteError => 'No s\'ha pogut eliminar. Torna-ho a provar.';

  @override
  String get giftNotSaved =>
      'No s\'ha desat: aquest regal ja no existeix, l\'ha esborrat un altre mòbil.';

  @override
  String giftDeletedNotice(String name) {
    return '«$name» esborrat';
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
      'Abans, aquest mòbil surt de la sincronització de la família; si és l\'últim, també s\'esborra la còpia xifrada del servidor.';

  @override
  String get eraseAllContinue => 'Continua';

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
      'Comprova la connexió i torna-ho a provar. Si esborres només aquest mòbil, continuarà a la llista de mòbils de la teva família fins que un altre el tregui, i la còpia xifrada es queda al servidor per als altres (o fins que caduqui, si era l\'últim).';

  @override
  String get eraseAllRetry => 'Torna-ho a provar';

  @override
  String get eraseAllLocalOnly => 'Esborra només aquest mòbil';

  @override
  String get eraseAllFailed =>
      'No s\'ha pogut esborrar tot. Torna-ho a provar.';

  @override
  String get eraseAllPinPrompt =>
      'Escriu el teu PIN per continuar amb l\'esborrat.';

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
  String get syncShortOffline => 'sense connexió';

  @override
  String get syncShortError => 'amb error';

  @override
  String get syncShortOff => 'apagada';

  @override
  String get archiveSubtitle =>
      'Fora de les llistes, amb els seus regals guardats.';

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
  String get devicesRecoveryTitle => 'Còpia de recuperació desada';

  @override
  String get devicesRecoveryBody =>
      'La llista té una còpia xifrada que es recupera amb el teu codi. Connecta\'n un altre mòbil per veure-la en tots dos.';

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
  String get devicesOfflineTitle => 'Sense connexió';

  @override
  String get devicesOfflineBody => 'Els canvis s\'enviaran quan torni.';

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
      'Sense persona: encara no obre les sorpreses';

  @override
  String get devicesListError => 'No s\'ha pogut llegir la llista de mòbils.';

  @override
  String get devicesConnect => 'Connectar un altre mòbil';

  @override
  String get devicesConnectQuestion => 'On és l\'altre mòbil?';

  @override
  String get devicesHereTitle => 'És aquí';

  @override
  String get devicesHereHint => 'Ensenya-li un codi QR. És el més ràpid.';

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
      'Si t\'uneixes a una altra família, la llista d\'aquest mòbil se substitueix i se\'n perden els regals.';

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
      'Es fusiona amb el que hi ha: no es perd res.';

  @override
  String get backupPasteTitle => 'Enganxar des del porta-retalls';

  @override
  String get backupPasteHint => 'Si et va arribar com a enllaç o com a text.';

  @override
  String get backupFileNote =>
      'Per obrir un fitxer .gifthuddle, toca\'l a Fitxers o al missatge on et va arribar i tria Gift Huddle.';

  @override
  String get backupNote =>
      'La còpia va xifrada amb la clau de la família: avui només s\'obre en un mòbil que ja estigui connectat.';

  @override
  String get pairingV2Preparing => 'Preparant la connexió…';

  @override
  String get pairingV2NoticeExpires =>
      'El codi caduca a les 24 hores i només serveix per demanar entrada: ningú entra sense que comparis un número amb l\'altre mòbil.';

  @override
  String get pairingV2FarTitle => 'Comparteix l\'enllaç';

  @override
  String get pairingV2FarBody =>
      'Envia\'l a qui vulguis connectar. Quan l\'obri i demani entrar, aquí veuràs un número per comparar-lo.';

  @override
  String get pairingV2Share => 'Compartir l\'enllaç';

  @override
  String get pairingV2WaitingHere =>
      'Esperant que l\'altre mòbil llegeixi el codi…';

  @override
  String get pairingV2CompareTitle => 'Compara el número';

  @override
  String get pairingV2HostCompareBody =>
      'L\'altre mòbil mostra un número. Ha de ser el mateix que aquest. Si ho és, toca «Coincideixen»; si no, «No coincideixen».';

  @override
  String get pairingV2Match => 'Coincideixen';

  @override
  String get pairingV2NoMatch => 'No coincideixen';

  @override
  String get pairingV2NoPersonWarning =>
      'L\'altre mòbil encara no ha dit de qui és. Li pots donar accés igualment: ho podrà triar més endavant i, fins llavors, no obrirà les sorpreses.';

  @override
  String get pairingV2Approving => 'Donant accés a l\'altre mòbil…';

  @override
  String get pairingV2HostDone =>
      'Accés enviat. L\'altre mòbil ha d\'acabar la connexió.';

  @override
  String get pairingV2VersionMismatch =>
      'Tots dos mòbils han de tenir l\'última versió de Gift Huddle. Actualitza el que estigui desfasat i torna a començar.';

  @override
  String get pairingV2HostCancelled =>
      'S\'ha cancel·lat i el codi ja no serveix. Pots tornar a començar.';

  @override
  String get pairingV2HostFailed =>
      'No s\'ha pogut connectar l\'altre mòbil. Torna-ho a provar.';

  @override
  String get pairingV2NotReady =>
      'Per connectar un altre mòbil cal tenir la sincronització encesa i connexió a internet.';

  @override
  String get pairingV2ChooseTitle => 'De qui és aquest mòbil?';

  @override
  String get pairingV2ChooseBody =>
      'El que tens a la mà. Tria qui el fa servir i Gift Huddle sabrà quines sorpreses ha d\'amagar-li.';

  @override
  String pairingV2ChooseBodySelf(String name) {
    return 'Aquest mòbil el tenies assignat a $name. Confirma-ho o tria una altra persona.';
  }

  @override
  String get pairingV2ChooseContinue => 'Continua';

  @override
  String get pairingV2ChooseLaterTitle => 'Triar després';

  @override
  String get pairingV2ChooseLaterBody =>
      'Si no tries ara, aquest mòbil no obrirà les sorpreses fins que triïs la persona i qui t\'ha convidat ho aprovi.';

  @override
  String get pairingV2ChooseNone =>
      'Aquest mòbil encara no coneix ningú d\'aquesta família, així que de moment no es pot triar. Ho podràs fer quan arribi la llista.';

  @override
  String get pairingV2GuestWaitingCode =>
      'Esperant l\'altre mòbil. D\'aquí a uns segons veuràs un número per comparar.';

  @override
  String get pairingV2GuestCompareBody =>
      'Mira el número que mostra l\'altre mòbil. Ha de ser el mateix que aquest. Si ho és, toca «Coincideixen».';

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
      'Cada mòbil es torna a connectar amb «Connectar un altre mòbil» i comparant un número.';

  @override
  String pairingV2ClaimTitle(String name) {
    return 'Aquest mòbil diu que és de $name';
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
      'Per connectar un altre mòbil, aquesta família passa a la sincronització nova, més segura. No es pot desfer: els mòbils que ja estaven connectats deixen de rebre els canvis d\'aquest fins que els tornis a connectar, un a un, amb «Connectar un altre mòbil». No es perd res.';

  @override
  String get pairingV2MigrateContinue => 'Continua';

  @override
  String get joinReplacePinPrompt =>
      'Escriu el teu PIN per substituir la llista d\'aquest mòbil.';

  @override
  String get joinReplaceBiometricReason =>
      'Confirma que vols substituir la llista d\'aquest mòbil';

  @override
  String get devicesPeerPending => 'Espera aprovació';

  @override
  String get devicesPeerFrozen => 'Congelat: espera aprovació';

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
  String get deviceStatusFrozen => 'Congelat';

  @override
  String get deviceStatusReconfirm => 'Falta confirmar de qui és';

  @override
  String get deviceDetailSelfNote =>
      'Aquest és el teu mòbil. Per deixar de sincronitzar-lo, fes servir «Deixar de sincronitzar» a «Més opcions».';

  @override
  String get deviceRemoveTitle => 'Treure aquest mòbil';

  @override
  String get deviceRemoveHint => 'Deixa de rebre la llista nova.';

  @override
  String get deviceRemoveConfirmTitle => 'Vols treure aquest mòbil?';

  @override
  String get deviceRemoveConfirmBody =>
      'Deixa de rebre els canvis nous a l\'instant. El que ja té desat no se li pot esborrar. El que només era en aquell mòbil es pot perdre. No es pot desfer.';

  @override
  String get deviceRemoveConfirmAction => 'Treure mòbil';

  @override
  String get deviceRemoveWaitTitle =>
      'Aquest mòbil tornarà a esperar aprovació';

  @override
  String get deviceRemoveWaitBody =>
      'El mòbil que vas a treure és l\'únic que va aprovar el canvi de persona d\'aquest mòbil. Si el treus, aquest mòbil esperarà l\'aprovació d\'un altre de la família i, fins llavors, no obrirà les sorpreses.';

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
      'Ha canviat de persona. En aprovar-lo, a partir d\'ara podrà avalar altres mòbils de la família.';

  @override
  String get deviceApproveOrphan =>
      'Va deixar d\'estar enllaçat amb aquest mòbil. Si l\'aproves, torna a rebre les sorpreses que li toquen.';

  @override
  String get deviceApproveDetached =>
      'Aquest mòbil ja no està enllaçat amb la família, però et va confirmar a tu. Aprova\'l només si el coneixes.';

  @override
  String get deviceApproveFrozen =>
      'Els seus canvis estan congelats i no es poden netejar els esborrats fins que l\'aprovis o el treguis.';

  @override
  String get deviceApprovedSnack => 'Mòbil aprovat';

  @override
  String get deviceApproveError => 'No s\'ha pogut aprovar el mòbil.';

  @override
  String get deviceChangedNotice =>
      'Aquest mòbil ha canviat: revisa-ho de nou.';

  @override
  String get deviceRemovedPendingSnack =>
      'Tret d\'aquest mòbil. Falta tallar-ne l\'accés: es farà quan hi hagi connexió.';

  @override
  String get deviceApproveCanVouch =>
      'La seva fitxa ha canviat: en aprovar-lo, a partir d\'ara podrà avalar altres mòbils de la família.';

  @override
  String get webGateConnectTitle => 'Connecta aquest ordinador';

  @override
  String get webGateConnectIntro =>
      'S\'aparella una sola vegada amb el teu mòbil. Després només necessitaràs el teu PIN.';

  @override
  String get webGateStepOpenApp => 'Obre Gift Huddle al teu mòbil.';

  @override
  String get webGateConnectStep2 =>
      'Ves a Mòbils de la família i toca Connectar la web.';

  @override
  String get webGateConnectStep3 => 'Escaneja aquest codi.';

  @override
  String get webGateConnectWaiting => 'Esperant el mòbil…';

  @override
  String get webGateCompareTitle => 'Comprova el codi';

  @override
  String get webGateCompareLabel => 'Codi de verificació';

  @override
  String get webGateCompareBody =>
      'Comprova que al mòbil surt el mateix codi, confirma\'l aquí i aprova\'l també al mòbil.';

  @override
  String get webGateCompareWaiting => 'Esperant que el mòbil ho aprovi…';

  @override
  String get webGateCompareConfirmed => 'Has confirmat el codi aquí';

  @override
  String get webGateFailedTitle => 'No s\'ha pogut connectar';

  @override
  String get webGateFailedExpired =>
      'El codi ha caducat. Comença de nou per veure\'n un de nou.';

  @override
  String get webGateFailedMismatch =>
      'Els codis no coincidien, així que no s\'ha connectat res. Comença de nou.';

  @override
  String get webGateFailedRejected =>
      'El mòbil ha rebutjat la connexió. Comença de nou si ho vols tornar a provar.';

  @override
  String get webGateFailedNetwork =>
      'No hi ha connexió amb el servidor. Comprova la connexió i comença de nou.';

  @override
  String get webGateFailedCancelled =>
      'El mòbil ha cancel·lat la connexió o la invitació ja no està disponible. Comença de nou i torna a connectar des del mòbil.';

  @override
  String get webGateStartAgain => 'Començar de nou';

  @override
  String webGateChoosePinTitle(String name) {
    return 'Aquest ordinador és de $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Tria un PIN o una frase per obrir-lo. Te\'l demanarem cada vegada que hi entris.';

  @override
  String get webGatePinLabel => 'PIN o frase';

  @override
  String get webGatePinRepeatLabel => 'Repeteix el PIN o la frase';

  @override
  String get webGatePinShow => 'Mostra';

  @override
  String get webGatePinHide => 'Amaga';

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
  String get webGateContinue => 'Continua';

  @override
  String get webGateSaving => 'Desant…';

  @override
  String get webGateUnlockTitle => 'Desbloqueja Gift Huddle';

  @override
  String get webGateUnlockBody =>
      'Escriu el PIN o la frase d\'aquest ordinador.';

  @override
  String get webGateUnlock => 'Desbloqueja';

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
      'Desbloqueja\'l des d\'un mòbil. No s\'ha esborrat res.';

  @override
  String get webGateSuspendedStep2 => 'Ves a Mòbils de la família i toca Web.';

  @override
  String get webGateSuspendedStep3 => 'Toca Permetre desbloquejar de nou.';

  @override
  String get webGateRetry => 'Torna-ho a provar';

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
          'Hi ha $count canvis sense pujar desats en aquest ordinador, xifrats.',
      one: 'Hi ha $count canvi sense pujar desat en aquest ordinador, xifrat.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Tornar a connectar';

  @override
  String get webGateErase => 'Esborrar les dades d\'aquest ordinador';

  @override
  String get webGateEraseTitle => 'Esborrar les dades d\'aquest ordinador?';

  @override
  String get webGateEraseBody =>
      'S\'esborra tot el que Gift Huddle desa aquí. No es pot desfer.';

  @override
  String get webGateEraseBodyUnsent =>
      'S\'esborra tot el que Gift Huddle desa aquí, també els canvis sense pujar. No es pot desfer.';

  @override
  String get webGateDamagedTitle =>
      'Les dades d\'aquest ordinador estan malmeses';

  @override
  String get webGateDamagedBody =>
      'No es poden llegir de forma segura. Per continuar, esborra-les i torna a connectar aquest ordinador des d\'un mòbil. Els canvis que no s\'haguessin pujat es perdran.';

  @override
  String get webGateDamagedPhoneHint =>
      'Al mòbil, treu la web anterior a Mòbils de la família.';

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
      'El PIN o la frase actual no és correcte.';

  @override
  String get webSettingsChangeFailed =>
      'No s\'ha pogut canviar. Torna-ho a provar.';

  @override
  String get webSettingsPinChanged => 'PIN canviat.';

  @override
  String get webSettingsLockNow => 'Bloquejar ara';

  @override
  String get webSettingsForget => 'Oblidar aquest ordinador';

  @override
  String get webSettingsForgetHint =>
      'Surt de la família i esborra el que hi ha desat.';

  @override
  String get webSettingsForgetTitle => 'Oblidar aquest ordinador?';

  @override
  String get webSettingsForgetBody =>
      'Aquest ordinador sortirà de la família i s\'esborrarà el que Gift Huddle hi desa, també els canvis sense pujar. Als teus mòbils no canvia res. Per tornar-lo a fer servir hauràs de connectar-lo de nou.';

  @override
  String get webSettingsForgetConfirm => 'Oblidar';

  @override
  String get webSettingsPersistenceDenied =>
      'El navegador podria esborrar les dades d\'aquest ordinador si li falta espai.';

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
      'Si el teu mòbil no ha mostrat el mateix codi, no continuïs: toca Començar de nou.';

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
          'Hi va haver $count intents fallits de desbloquejar aquest ordinador des de l\'última vegada. Si no has estat tu, canvia el PIN.',
      one:
          'Hi va haver $count intent fallit de desbloquejar aquest ordinador des de l\'última vegada. Si no has estat tu, canvia el PIN.',
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
  String get connectWebWhoseTitle => 'De qui és aquest ordinador?';

  @override
  String get connectWebWhoseBody =>
      'Tria qui l\'utilitzarà. L\'ordinador es connectarà com a seu.';

  @override
  String get connectWebNoPeople =>
      'Encara no hi ha persones. Afegeix una persona abans de connectar la web.';

  @override
  String get connectWebWaiting => 'Esperant que l\'ordinador respongui…';

  @override
  String get connectWebCompareBody =>
      'L\'ordinador mostra un codi. Ha de ser el mateix que aquest. Si ho és, prem «Coincideixen»; si no, «No coincideixen».';

  @override
  String get connectWebApproving => 'Donant accés a l\'ordinador…';

  @override
  String get connectWebDoneTitle => 'Ordinador connectat';

  @override
  String get connectWebDoneBody =>
      'A l\'ordinador, tria un PIN per obrir Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'Aquest codi ja no val. A l\'ordinador, toca Començar de nou i escaneja el nou.';

  @override
  String get connectWebScanAgain => 'Escanejar un altre codi';

  @override
  String get connectWebFailed =>
      'No s\'ha pogut connectar l\'ordinador. A l\'ordinador, toca Començar de nou i escaneja el nou codi.';

  @override
  String get connectWebCancelled =>
      'S\'ha cancel·lat i el codi ja no serveix. A l\'ordinador, toca Començar de nou.';

  @override
  String get deviceWebResume => 'Permetre desbloquejar una altra vegada';

  @override
  String get deviceWebResumeHint =>
      'Si l\'ordinador es va suspendre per massa intents de PIN. No s\'esborra res.';

  @override
  String get deviceWebResumeTitle => 'Permetre desbloquejar una altra vegada?';

  @override
  String get deviceWebResumeBody =>
      'Aquest ordinador tornarà a acceptar intents de PIN. Fes-ho només si ha estat el seu propietari qui s\'ha equivocat.';

  @override
  String get deviceWebResumeConfirm => 'Permetre';

  @override
  String get deviceWebResumeDone =>
      'Fet. L\'ordinador ja es pot tornar a desbloquejar.';

  @override
  String get deviceWebResumeError =>
      'No s\'ha pogut. Comprova la connexió i torna-ho a provar.';

  @override
  String get deviceRemoveWebTitle => 'Treure aquesta web';

  @override
  String get deviceRemoveWebHint =>
      'Aquest ordinador deixa de rebre la llista nova.';

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
      'Treta d\'aquest mòbil. Falta tallar-ne l\'accés: es farà quan hi hagi connexió.';

  @override
  String get deviceRemoveWebError =>
      'No s\'ha pogut treure la web. Torna-ho a provar amb connexió.';

  @override
  String get webSyncSaved => 'Desat';

  @override
  String get webSyncOffline => 'Sense connexió';

  @override
  String get webSyncAwaitingConfirm =>
      'Aquest ordinador espera que un mòbil el confirmi';

  @override
  String get webOperationUnavailable =>
      'Això no es pot fer des de l\'ordinador. Fes-ho des d\'un mòbil.';

  @override
  String get selfChangeConfirmTitle => 'Vols canviar de qui és aquest mòbil?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'Dius que aquest mòbil és de $name. Això canvia el que pot veure, no només el nom.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'Deixaràs aquest mòbil sense persona. Això canvia el que pot veure, no només el nom.';

  @override
  String selfChangeEffectHides(String name) {
    return 'Aquest mòbil deixarà de veure els regals de $name i les seves sorpreses.';
  }

  @override
  String get selfChangeEffectNobody =>
      'Aquest mòbil es quedarà sense persona assignada i no podrà veure sorpreses mentre continuï així.';

  @override
  String get selfChangeEffectWait =>
      'Fins que un altre mòbil de la família l\'aprovi, aquest mòbil no veurà les sorpreses de ningú.';

  @override
  String get selfChangeEffectReconfirm =>
      'Els mòbils que aquest havia aprovat potser s\'hauran de tornar a confirmar.';

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
      'Aquest mòbil ja no té cap persona assignada i espera l’aprovació d’un altre mòbil de la família. Encara que l’aprovin, no podrà veure sorpreses mentre no tingui una persona assignada.';

  @override
  String get selfChangePendingOrphans =>
      'Alguns mòbils que havies aprovat esperen que els tornis a confirmar.';

  @override
  String get selfChangeExhaustedTitle =>
      'Aquest mòbil ja no pot canviar de persona';

  @override
  String get selfChangeExhaustedBody =>
      'Ha fet servir tots els canvis que permet la llista de mòbils. Pot tornar a connectar-se a la família com un mòbil nou, en persona, des d\'un altre mòbil.';

  @override
  String get selfWaitingHint => 'Esperant l\'aprovació d\'un altre mòbil';

  @override
  String get healthRevokedTitle =>
      'Un altre mòbil de la família ha tret aquest';

  @override
  String get healthRevokedBody =>
      'El que tens desat continua en aquest mòbil, però ja no se sincronitza. Tornar-ho a provar no serveix: l\'has de tornar a connectar amb un altre mòbil de la família, en persona.';

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
      'No s’ha perdut res. Per veure les sorpreses, aquest mòbil ha de tenir una persona de la família assignada i estar aprovat per un altre mòbil de la família.';

  @override
  String healthNamesAnd(String head, String last) {
    return '$head i $last';
  }

  @override
  String get healthRenewSoon => 'Convé renovar la llista aviat';

  @override
  String get healthResolveSection => 'Per resoldre';

  @override
  String get healthUnbackedTitle => 'Accés sense aval';

  @override
  String get healthUnbackedBody =>
      'Un accés al servidor no figura a la llista de mòbils de la família. Si no el reconeixes, retira\'l.';

  @override
  String healthUnbackedRef(String ref) {
    return 'Referència: $ref';
  }

  @override
  String get healthUnbackedAction => 'Retirar l’accés';

  @override
  String get healthUnbackedConfirmTitle => 'Vols retirar aquest accés?';

  @override
  String get healthUnbackedConfirmBody =>
      'Es talla l\'accés d\'aquest mòbil al servidor de la família. Si era un mòbil teu, l\'hauràs de tornar a connectar en persona. No es pot desfer.';

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
  String get healthRetry => 'Torna-ho a provar';

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
  String get protectionStatusOff => 'Desactivat';

  @override
  String get protectionStatusRequested => 'Demanat';

  @override
  String get protectionStatusActive => 'Actiu';

  @override
  String protectionSheetTitle(String name) {
    return 'Regals en secret per a $name';
  }

  @override
  String protectionIntro(String name) {
    return 'Amb això actiu, el mòbil de $name no mostra cap regal per a $name, ni quants n\'hi ha. La resta de la família els continua veient.';
  }

  @override
  String get protectionEffectOthers =>
      'Els altres mòbils de la família amb permís continuen veient-los i editant-los.';

  @override
  String protectionEffectKept(String name) {
    return 'Els regals que el mòbil de $name ja havia rebut abans d\'activar-la no es poden retirar d\'aquest mòbil.';
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
    return 'Desactivar els regals en secret de $name?';
  }

  @override
  String protectionDeactivateBody(String name) {
    return 'Es publicaran tots els regals disponibles de $name, de qualsevol any, també els que són pendents en aquest mòbil. Després $name els veurà al seu mòbil.';
  }

  @override
  String get protectionDeactivateConfirm => 'Desactivar';

  @override
  String protectionCannotDeactivate(String name) {
    return 'Aquest mòbil no pot desactivar-la ara: cal permís i la clau actual de $name.';
  }

  @override
  String get protectionChangeFailed =>
      'No s\'ha pogut canviar la protecció. No s\'ha modificat res.';

  @override
  String secretBlockTitle(String name) {
    return 'Regals en secret per a $name';
  }

  @override
  String get secretBlockNote => 'Aquest mòbil no els mostra.';

  @override
  String protectionReason_protectedPerson(String name) {
    return 'Els regals de $name són en secret i no es poden guardar així.';
  }

  @override
  String protectionReason_noEntitlement(String name) {
    return 'Aquest mòbil no té permís per als regals en secret de $name. Demana ajuda a un altre mòbil de la família amb permís.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'Aquest mòbil és de $name: aquí no es poden crear ni veure els seus regals mentre siguin en secret.';
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
    return 'Els regals en secret de $name han arribat al límit. Esborra\'n algun per poder-ne afegir més.';
  }

  @override
  String protectionReason_giftTooLarge(String name) {
    return 'Aquest regal és massa gran per guardar-lo en secret. Escurça les notes.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'Aquest mòbil ja no té lloc per guardar més regals en secret. Demana a un altre mòbil amb permís que els afegeixi.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'Ara mateix no hi cap res més als regals en secret de la família.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Els regals en secret necessiten que aquest mòbil estigui connectat a la família amb la versió nova.';
  }

  @override
  String get giftProtectedRejected => 'No s\'ha guardat el regal.';

  @override
  String get giftSavedLocally =>
      'Guardat només en aquest mòbil. Queda pendent de guardar i compartir.';

  @override
  String get giftSavedLocallyAction => 'Veure pendents';

  @override
  String get giftOwnRequestRestricted =>
      'Mentre la protecció estigui activa, aquest mòbil no pot crear ni veure regals per a la seva pròpia persona. Demana-ho a una altra persona de la família.';

  @override
  String get pendingGiftsTitle => 'Regals pendents';

  @override
  String get pendingGiftsIntro =>
      'Aquests regals estan guardats xifrats només en aquest mòbil. Fins que es guardin i es comparteixin amb la família, els altres mòbils no els veuen. Si perds aquest mòbil abans, es perden.';

  @override
  String get pendingGiftsRetry => 'Reintentar';

  @override
  String get pendingGiftsRetrying => 'Reintentant';

  @override
  String get pendingGiftsStill =>
      'Encara no hi cap. No s\'ha publicat res i els regals es conserven en aquest mòbil.';

  @override
  String get pendingGiftsRetryError =>
      'No s\'ha pogut reintentar. Els regals continuen guardats en aquest mòbil.';

  @override
  String get pendingGiftsDoneTitle => 'Tot guardat';

  @override
  String get pendingGiftsDoneBody => 'Ja no queda cap regal pendent.';

  @override
  String pendingGiftsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regals pendents de guardar',
      one: '$count regal pendent de guardar',
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
    return '$done de $total comprats';
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
  String get boardOccasionsHint => 'Tria una ocasió per veure el seu tauler.';

  @override
  String get boardChangeDate => 'Canvia la data';

  @override
  String get boardSettingsIndex => 'Apartats';

  @override
  String get boardEditorLabel => 'Editor de regal';

  @override
  String get boardNoGiftsYet => 'Encara sense regals';

  @override
  String get boardSidebarCollapse => 'Plega la barra lateral';

  @override
  String get boardSidebarExpand => 'Desplega la barra lateral';

  @override
  String get boardSearchHint => 'Cerca un regal';

  @override
  String get boardSearchNone => 'Cap regal coincideix';

  @override
  String get boardColStatus => 'Estat';

  @override
  String get boardColGiver => 'Qui regala';

  @override
  String get boardColSize => 'Talla';

  @override
  String get boardRepartoNoGiver => 'Sense qui regali';

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
  String get tourSkip => 'Omet';

  @override
  String tourPageOf(int page, int total) {
    return 'Pàgina $page de $total';
  }

  @override
  String get tour1Title => 'Apunta cada regal';

  @override
  String get tour1Body =>
      'Tria a qui, per a quina ocasió i qui el regala. Amb una idea n\'hi ha prou.';

  @override
  String get tour2Title => 'Marca\'l com a comprat';

  @override
  String get tour2Body =>
      'Toca la casella i el regal surt de «Pendent de comprar» i passa a «per arribar». Si t\'equivoques, ho desfàs a l\'instant.';

  @override
  String get tour3Title => 'Persones i ocasions';

  @override
  String get tour3Body =>
      'Cada persona té la seva llista. Nadal, Reis i aniversaris l\'ordenen, i el repartiment diu qui paga què.';

  @override
  String get tour4Title => 'La família comparteix la llista';

  @override
  String get tour4Body =>
      'Connecta un altre mòbil amb un QR, en persona. Tot viatja xifrat i els canvis arriben sols.';

  @override
  String get tour5Title => 'Sorpreses a recer';

  @override
  String get tour5Body =>
      'El mòbil de cada persona no veu els seus propis regals. Amb PIN o biometria, sense comptes ni anuncis.';

  @override
  String get tour6Title => 'També a l\'ordinador';

  @override
  String get tour6Body =>
      'Connecta el navegador una vegada i tindràs la llista en una pantalla gran.';

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
  String get tourDemoHidden => 'Regals ocults';

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
      'El codi encara no compta com a desat. Continua per comprovar les paraules o comprova un fitxer que ja hagis desat. Si les paraules ja s\'han mostrat, es crearà un codi nou i l\'anterior deixarà de valer.';

  @override
  String get recoveryValueAttention => 'Revisar';

  @override
  String get recoveryValueTransferred => 'Traspassada';

  @override
  String get recoverySubtitle => 'Per recuperar la llista en un mòbil nou.';

  @override
  String get recoveryAbsentTitle =>
      'Prepara un codi per recuperar la llista si perds aquest mòbil';

  @override
  String get recoveryAbsentBody =>
      'Amb 24 paraules pots recuperar la llista i tot el que aquest mòbil pot veure en un altre mòbil. Si només tens aquest mòbil, s\'activa una còpia xifrada al servidor: sense les paraules, ningú no la pot llegir.';

  @override
  String get recoveryAbsentWarn =>
      'Qui tingui les paraules pot entrar com aquest mòbil. No recuperen el que mai no s\'ha arribat a sincronitzar.';

  @override
  String get recoveryCreate => 'Crea el codi de recuperació';

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
  String get recoveryChange => 'Canvia el codi';

  @override
  String get recoveryChangeHint =>
      'Els fitxers i les paraules anteriors deixaran de servir.';

  @override
  String get recoveryRemove => 'Treu el codi';

  @override
  String get recoveryRemoveHint =>
      'Les paraules deixaran de valer i s\'esborra la còpia.';

  @override
  String get recoveryRemoveTitle => 'Vols treure el codi de recuperació?';

  @override
  String get recoveryRemoveBody =>
      'S\'esborra la còpia de recuperació i les 24 paraules deixen de valer. Podràs crear un altre codi quan vulguis.';

  @override
  String get recoveryRemoveSoloNote =>
      'Com que no hi ha cap altre mòbil ni la web connectats, també s\'esborra del servidor la còpia xifrada de la llista i la llista torna a ser només en aquest mòbil.';

  @override
  String get recoveryRemoveConfirm => 'Treu el codi';

  @override
  String get recoveryRemoved => 'Codi tret';

  @override
  String get recoveryRetry => 'Torna-ho a provar';

  @override
  String get recoveryIntroTitle => 'Crea el codi';

  @override
  String get recoveryRotateTitle => 'Canvia el codi';

  @override
  String get recoveryIntroBody =>
      'Veuràs 24 paraules. Amb elles pots recuperar la llista i tot el que aquest mòbil pot veure en un altre mòbil.';

  @override
  String get recoveryRotateBody =>
      'Es crearà un codi nou. L\'anterior deixarà de valer quan el nou estigui preparat: els fitxers i les paraules anteriors deixaran de servir.';

  @override
  String get recoveryPoint1 =>
      'Apunta-les en paper o desa-les en un gestor de contrasenyes.';

  @override
  String get recoveryPoint2 => 'Qui les tingui pot entrar com aquest mòbil.';

  @override
  String get recoveryPoint3 => 'No recuperen el que mai no es va sincronitzar.';

  @override
  String get recoveryContinue => 'Continua';

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
      'Qui tingui aquestes paraules pot entrar com aquest mòbil. No en facis cap captura ni les enviïs per missatge.';

  @override
  String recoveryWordItem(int number, String word) {
    return 'Paraula $number: $word';
  }

  @override
  String get recoveryShowQr => 'Mostra el codi QR';

  @override
  String get recoveryShowWords => 'Mostra les paraules';

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
  String get recoveryLeaveConfirm => 'Surt';

  @override
  String get recoveryLeaveStay => 'Queda\'t aquí';

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
  String get recoveryCheckBack => 'Torna a mostrar les paraules';

  @override
  String get recoveryCheckButton => 'Comprova';

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
  String get recoveryCloseLater => 'Tanca i continua més tard';

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
      'Es va canviar o es va treure des d\'un altre mòbil. Busca el codi més recent.';

  @override
  String get recoveryProblemRemovedTitle =>
      'Aquest mòbil ja no és a la família';

  @override
  String get recoveryProblemRemovedBody =>
      'Aquest mòbil es va treure de la llista, així que no es pot recuperar amb aquest codi.';

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
  String get obHaveRecoveryCode => 'Tinc un codi de recuperació';

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
  String get recoverPaste => 'Enganxa les 24 paraules';

  @override
  String get recoverScan => 'Escaneja el QR';

  @override
  String get recoverSubmit => 'Recupera la llista';

  @override
  String recoverWordUnknown(int number) {
    return 'La paraula $number no és a la llista.';
  }

  @override
  String get recoverChecksum =>
      'Les paraules no formen un codi vàlid. Revisa l\'ordre i que no en falti cap.';

  @override
  String get recoverPasteEmpty => 'No hi ha res copiat.';

  @override
  String get recoverPasteWrong => 'El que has copiat no té 24 paraules.';

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
  String get recoverStepInstall => 'Instal·lant en aquest mòbil';

  @override
  String get recoverDoneTitle => 'Llista recuperada';

  @override
  String recoverDoneSelf(String name) {
    return 'Aquest mòbil és de $name.';
  }

  @override
  String get recoverDoneNoSelf =>
      'Aquest mòbil no té cap persona assignada. La pots triar a Ajustos.';

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
  String get recoverEnter => 'Entra a la llista';

  @override
  String get recoverOtherCode => 'Escriu un altre codi';

  @override
  String get transferredTitle => 'Aquesta llista s\'ha passat a un altre mòbil';

  @override
  String get transferredBody =>
      'La teva llista ara és en un altre mòbil o en una altra app, i ja no es gestiona des d\'aquesta app. El que veus aquí és una còpia de només lectura: no s\'ha esborrat res.';

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
      'No s\'ha pogut deixar la còpia xifrada al servidor, així que no es mostren les paraules. Torna-ho a provar amb connexió.';

  @override
  String get recoverReplaceTitle =>
      'Vols substituir la llista d\'aquest mòbil?';

  @override
  String get recoverReplaceBody =>
      'Aquest codi és d\'una altra família. Si continues, la llista d\'aquella família substituirà la que tens en aquest mòbil. La llista anterior es conserva al mòbil, però deixa de veure\'s.';

  @override
  String get recoverReplaceConfirm => 'Substitueix';

  @override
  String get recoverAbandon => 'Cancel·la la recuperació';

  @override
  String get recoverAbandonTitle => 'Vols cancel·lar la recuperació?';

  @override
  String get recoverAbandonBody =>
      'Es descarten les dades temporals d\'aquesta recuperació en aquest mòbil. Cancel·lar no reactiva el mòbil anterior si ja havia quedat en mode de només lectura. Podràs tornar a introduir el codi.';

  @override
  String get recoverAbandonConfirm => 'Cancel·la la recuperació';

  @override
  String get recoverAbandonKeep => 'Continua';

  @override
  String get recoverAbandonFailed =>
      'No s\'ha pogut cancel·lar. Torna-ho a provar d\'aquí a un moment.';

  @override
  String get recoverAbandonBodyClaimed =>
      'La llista ja s\'ha passat a aquest codi i l\'altre mòbil s\'ha quedat en mode de només lectura; cancel·lar no ho desfà. Per fer-la servir hauràs d\'escriure el codi un altre cop.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'Aquest mòbil no pot bloquejar les captures de pantalla: no en facis cap.';

  @override
  String get recoverLeaveTitle => 'Vols sortir de la recuperació?';

  @override
  String get recoverLeaveBody =>
      'Es queda a mitges en aquest mòbil. Podràs reprendre-la o cancel·lar-la des de la pantalla de benvinguda.';

  @override
  String get recoverPendingTitle => 'Hi ha una recuperació en curs';

  @override
  String get recoverPendingBody =>
      'Es va quedar a mitges en aquest mòbil. Reprèn-la o cancel·la-la abans de crear una família o unir-te a una altra.';

  @override
  String get recoverResume => 'Reprèn';

  @override
  String get recoveryProblemPendingTitle => 'Hi ha una recuperació a mitges';

  @override
  String get recoveryProblemPendingBody =>
      'Reprèn-la o cancel·la-la abans de crear una família o unir-te a una altra.';

  @override
  String get recoveryMaintCancel => 'Cancel·la la preparació';

  @override
  String get recoveryMaintCancelTitle =>
      'Vols cancel·lar la preparació del codi?';

  @override
  String get recoveryMaintCancelBody =>
      'El codi que ja tinguis continua valent. Es deixa de preparar el que estava en marxa.';

  @override
  String get recoveryMaintCancelConfirm => 'Cancel·la la preparació';

  @override
  String get recoveryRemoveAuthMessage =>
      'Escriu el teu PIN per treure el codi.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirma que vols treure el codi de recuperació';

  @override
  String get transferredRecover => 'Recupera amb el meu codi';

  @override
  String get transferredErase => 'Esborra-ho tot d\'aquest mòbil';

  @override
  String get recoverStepDoneValue => 'fet';

  @override
  String get recoverStepActiveValue => 'en curs';

  @override
  String get recoveryFileAction => 'Desa en un fitxer';

  @override
  String get recoveryFileTitle => 'Desa en un fitxer';

  @override
  String get recoveryFileBody =>
      'A més de les paraules, pots desar el codi en un fitxer. Qui tingui el fitxer pot recuperar la llista i entrar com aquest mòbil.';

  @override
  String get recoveryFilePersonal =>
      'És un fitxer personal: no l\'enviïs a la família. Desa\'l on puguis obrir-lo encara que perdis aquest mòbil.';

  @override
  String get recoveryFileProtect => 'Protegeix amb contrasenya';

  @override
  String get recoveryFileProtectOffHint =>
      'Sense contrasenya, el fitxer val tant com les paraules: qui el aconsegueixi el pot fer servir.';

  @override
  String get recoveryFileProtectOnHint =>
      'Robar el fitxer no n\'hi ha prou: cal la contrasenya.';

  @override
  String get recoveryFilePassword => 'Contrasenya';

  @override
  String get recoveryFilePasswordRepeat => 'Repeteix la contrasenya';

  @override
  String get recoveryFilePasswordShow => 'Mostra';

  @override
  String get recoveryFilePasswordHide => 'Amaga';

  @override
  String recoveryFilePasswordHelp(int min) {
    return 'Mínim $min caràcters. Fes servir el gestor de contrasenyes o diverses paraules triades a l\'atzar.';
  }

  @override
  String get recoveryFilePasswordForgot =>
      'Si oblides la contrasenya, el fitxer no serveix de res. Les 24 paraules continuaran valent.';

  @override
  String recoveryFilePwTooShort(int min) {
    return 'És massa curta: mínim $min caràcters.';
  }

  @override
  String recoveryFilePwTooLong(int max) {
    return 'És massa llarga: màxim $max caràcters.';
  }

  @override
  String get recoveryFilePwRepeated => 'Repeteix un mateix caràcter o bloc.';

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
  String get recoveryFileSave => 'Desa';

  @override
  String get recoveryFileSaveAgain => 'Desa\'n una altra còpia';

  @override
  String get recoveryFileShare => 'Comparteix';

  @override
  String get recoveryFileShareText =>
      'Fitxer de recuperació de Gift Huddle. És personal: no el reenviïs a la família.';

  @override
  String get recoveryFileStem => 'gift-huddle-recuperacio';

  @override
  String get recoveryFileDerivingTitle => 'Protegint el fitxer…';

  @override
  String get recoveryFileDerivingBody =>
      'Es prepara la clau de la contrasenya. Triga uns segons; no tanquis l\'app.';

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
      'El que s\'ha llegit de la destinació no coincideix. Torna-ho a desar, potser en un altre lloc.';

  @override
  String get recoveryFileProblemUnreadableTitle =>
      'No s\'ha pogut llegir el fitxer';

  @override
  String get recoveryFileProblemUnreadableBody =>
      'Comprova que el fitxer és disponible en aquest mòbil i torna-ho a provar.';

  @override
  String get recoveryFileProblemUnavailableTitle =>
      'Aquest mòbil no pot obrir el selector de fitxers';

  @override
  String get recoveryFileProblemUnavailableBody =>
      'Prova amb Comparteix o fes servir les 24 paraules.';

  @override
  String get recoveryFileProblemPickerBusyTitle => 'Ja hi ha un selector obert';

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
      'Es va desar amb un codi anterior i ja no val. Busca\'n un de més recent o canvia el codi.';

  @override
  String get recoveryFileProblemHasFamilyTitle =>
      'Aquest mòbil ja té una llista';

  @override
  String get recoveryFileProblemHasFamilyBody =>
      'El fitxer de recuperació serveix per a un mòbil buit. No s\'ha fet servir.';

  @override
  String get recoveryCheckFileAction => 'Comprova un fitxer';

  @override
  String get recoveryCheckFileTitle => 'Comprova un fitxer';

  @override
  String get recoveryCheckFileBody =>
      'Tria el fitxer de recuperació que vas desar. Si obre el codi d\'aquest mòbil, queda comprovat. No es desa ni s\'envia res.';

  @override
  String get recoveryFilePick => 'Tria un fitxer';

  @override
  String get recoveryFilePasswordTitle => 'Contrasenya del fitxer';

  @override
  String get recoveryFilePasswordOpenBody =>
      'Aquest fitxer està protegit. Escriu la contrasenya que vas posar en desar-lo.';

  @override
  String get recoveryFileOpen => 'Obre el fitxer';

  @override
  String get recoveryFileCheckingTitle => 'Comprovant el fitxer…';

  @override
  String get recoveryFileCheckingBody => 'Un moment.';

  @override
  String get recoveryCheckFileOkTitle => 'Codi comprovat';

  @override
  String get recoveryCheckFileOkBody =>
      'El fitxer obre el codi d\'aquest mòbil. Si perds el mòbil, podràs recuperar la llista amb ell.';

  @override
  String get obRecoverWithFile => 'Recupera amb fitxer';

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
      'Aquest mòbil recuperarà la llista i entrarà com el mòbil que va desar el codi. Si no és el teu fitxer, no continuïs.';

  @override
  String get recoverFileOther => 'Tria un altre fitxer';

  @override
  String get recoverFileWaitingTitle => 'Ha arribat un altre fitxer';

  @override
  String get recoverFileWaitingBody =>
      'Estaves amb un altre fitxer de recuperació. Vols canviar a aquest?';

  @override
  String get recoverFileWaitingSwitch => 'Canvia de fitxer';

  @override
  String get recoverFileWaitingKeep => 'Continua amb l\'actual';

  @override
  String get recoveryProblemPersonTitle =>
      'Aquest codi ja no és el de la teva persona actual';

  @override
  String get recoveryProblemPersonBody =>
      'Ha canviat la persona d\'aquest mòbil o hi ha un canvi pendent. Crea un codi nou i desa aquell.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Gift Huddle';

  @override
  String get navMainLabel => 'Main navigation';

  @override
  String get navPeople => 'People';

  @override
  String get navFamily => 'Who gives what';

  @override
  String get navFamilyShort => 'Who gives';

  @override
  String get navOccasions => 'Occasions';

  @override
  String get navSettings => 'Settings';

  @override
  String get emptyPeopleTitle => 'No people yet';

  @override
  String get emptyPeopleMessage =>
      'Add the people you give gifts to and start their gift lists.';

  @override
  String get emptyFamilyTitle => 'No gifts noted yet';

  @override
  String get emptyFamilyMessage =>
      'You will see who gives what to each person here.';

  @override
  String get emptyOccasionsTitle => 'No occasions';

  @override
  String get emptyOccasionsMessage =>
      'Christmas, birthdays and other dates will show up here with a countdown.';

  @override
  String backTo(String title) {
    return 'Back to $title';
  }

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageCatalan => 'Català';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get appearanceColorSection => 'Colour';

  @override
  String get appearanceColorGroup => 'App colour';

  @override
  String get appearanceThemeSection => 'Theme';

  @override
  String get appearanceThemeGroup => 'Light or dark theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get appearanceOccasionTitle =>
      'Occasion themes (Christmas, birthdays)';

  @override
  String get appearanceOccasionHint =>
      'An occasion\'s list changes accent and header.';

  @override
  String get appearanceHapticsTitle => 'Vibrations';

  @override
  String get appearanceHapticsHint =>
      'Small taps when you tick, choose or something arrives.';

  @override
  String get appearancePreview => 'Preview';

  @override
  String get accentLavender => 'Lavender';

  @override
  String get accentSage => 'Sage';

  @override
  String get accentPeach => 'Peach';

  @override
  String get accentSky => 'Sky';

  @override
  String get accentRose => 'Rose';

  @override
  String get accentButter => 'Butter';

  @override
  String get statusIdea => 'Idea';

  @override
  String get statusDecided => 'Decided';

  @override
  String get statusBought => 'Bought';

  @override
  String get statusArrived => 'Arrived';

  @override
  String get statusWrapped => 'Wrapped';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String statusCheckboxLabel(String item, String status) {
    return 'Change status of $item. Current status: $status';
  }

  @override
  String statusReadOnlyLabel(String status) {
    return 'Status: $status';
  }

  @override
  String get giverUnassigned => 'Unassigned';

  @override
  String countdownDaysFor(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days until $name',
      one: 'day until $name',
    );
    return '$_temp0';
  }

  @override
  String todayIs(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Today is $dateString';
  }

  @override
  String get previewGiftName => 'Block fire station';

  @override
  String get previewGiver => 'Us';

  @override
  String get previewOccasion => 'Three Kings\' Day';

  @override
  String get shareEnvelopeText => 'Gift Huddle changes: open it with the app.';

  @override
  String get occasionNameTio => 'Tió';

  @override
  String get occasionNameSanta => 'Christmas';

  @override
  String get occasionNameKings => 'Three Kings';

  @override
  String occasionBirthdayOf(String name) {
    return '$name\'s birthday';
  }

  @override
  String get shareErrorNotEnvelope =>
      'This file or text is not a Gift Huddle package.';

  @override
  String get shareErrorWrongList =>
      'This package is from another family. Connect the phones with the QR code.';

  @override
  String get shareErrorAuth =>
      'This package cannot be opened. It may be damaged or from another family.';

  @override
  String get shareErrorTooLarge => 'This package is too large.';

  @override
  String get shareErrorNoFamily =>
      'First create your family or join one with the QR code.';

  @override
  String get shareErrorClockDrift =>
      'The other phone has the wrong date or time. Fix it and send the package again.';

  @override
  String get shareErrorLegacyFile =>
      'This file is from an older version of Gift Huddle and no longer opens. Keep it and ask for it to be sent again from an updated phone.';

  @override
  String get shareErrorNotReady =>
      'This phone is not up to date with the family yet. Sync and open the file again.';

  @override
  String get shareErrorGeneration =>
      'This file is from an older version of the list. Ask for a new one.';

  @override
  String get shareErrorRevokedWriter =>
      'This file was saved by a phone that is no longer in the family. Nothing was added.';

  @override
  String get shareErrorMissingKey =>
      'This file cannot be opened yet. It has been kept and will open on its own when you sync.';

  @override
  String get shareErrorSyncAndReopen =>
      'This file cannot be opened yet. Sync and open it again.';

  @override
  String get shareErrorNotAllowed =>
      'This phone cannot save copies yet. Another phone in the family has to approve it first.';

  @override
  String get pairErrorInvalidCode => 'This QR code is not from Gift Huddle.';

  @override
  String get lockEnterPin => 'Enter your PIN';

  @override
  String lockPinProgress(int count, int total) {
    return 'PIN: $count of $total digits';
  }

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get lockBackspace => 'Delete';

  @override
  String get lockBiometric => 'Use fingerprint or face';

  @override
  String get lockBiometricReason => 'Unlock Gift Huddle';

  @override
  String get lockBiometricNotice =>
      'Any fingerprint or face registered on the phone can open the app.';

  @override
  String get lockLoadError => 'The lock could not be checked.';

  @override
  String get lockRetry => 'Retry';

  @override
  String lockWrongPin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts',
      one: '$count attempt',
    );
    return 'Wrong PIN. $_temp0 left before you have to wait.';
  }

  @override
  String get lockWrongPinNow => 'Wrong PIN.';

  @override
  String lockWait(String time) {
    return 'Too many attempts. Try again in $time.';
  }

  @override
  String get pinSetupTitle => 'Create a PIN';

  @override
  String get pinSetupMessage =>
      '4 to 6 digits. It protects your list on this phone.';

  @override
  String get pinConfirmTitle => 'Repeat the PIN';

  @override
  String get pinMismatch => 'The PINs do not match. Try again.';

  @override
  String get pinContinue => 'Continue';

  @override
  String get pinSave => 'Save PIN';

  @override
  String get pinSkip => 'Not now';

  @override
  String get pinBiometricOfferTitle => 'Turn on fingerprint or face?';

  @override
  String get pinBiometricOfferEnable => 'Turn on';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionNext => 'Next';

  @override
  String get actionBack => 'Back';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionClose => 'Close';

  @override
  String get actionDone => 'Done';

  @override
  String get actionArchive => 'Archive';

  @override
  String get actionRestore => 'Restore';

  @override
  String get actionUndo => 'Undo';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldNameRequired => 'Enter a name.';

  @override
  String get fieldFor => 'For';

  @override
  String get fieldGiver => 'Who gives it';

  @override
  String get fieldOccasion => 'Occasion';

  @override
  String get fieldStatus => 'Status';

  @override
  String giftCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gifts',
      one: '$count gift',
      zero: 'No gifts',
    );
    return '$_temp0';
  }

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years old',
      one: '$count year old',
    );
    return '$_temp0';
  }

  @override
  String get deviceNameDefault => 'My phone';

  @override
  String get giverUs => 'Us';

  @override
  String get giverHouseholdPays => 'Paid by the household';

  @override
  String get giverHouseholdPaysHint =>
      'If the household pays for it, it counts in the budget.';

  @override
  String countdownDaysForBirthday(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days until $name\'s birthday',
      one: 'day until $name\'s birthday',
    );
    return '$_temp0';
  }

  @override
  String onboardingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get obWelcomeTitle => 'Welcome to Gift Huddle';

  @override
  String get obWelcomeBody =>
      'Note who gives what to each person, so nobody doubles up and nobody is left out.';

  @override
  String get obWelcomePrivacy =>
      'No accounts. If you sync two phones, the list travels encrypted and only your phones can read it.';

  @override
  String get obDeviceNameLabel => 'Name of this phone';

  @override
  String get obDeviceNameHint =>
      'This is the name the other phone will see. You can change it.';

  @override
  String get obStart => 'Get started';

  @override
  String get obHaveListTitle => 'Already have the list on another phone?';

  @override
  String get obPeopleTitle => 'Who do you give gifts to?';

  @override
  String get obPeopleBody =>
      'Add the people you give gifts to: partner, siblings, nephews, kids… At least one is needed.';

  @override
  String get obPeopleAdd => 'Add a person';

  @override
  String get obPeopleNeedOne => 'Add at least one person to continue.';

  @override
  String obRemove(String name) {
    return 'Remove $name';
  }

  @override
  String get obGiversTitle => 'Who gives gifts?';

  @override
  String get obGiversBody =>
      '\"Us\" is already created and paid by the household. Add grandparents, aunts and uncles…';

  @override
  String get obGiversSuggestions => 'Quick add';

  @override
  String get obGiverGrandparents => 'Grandparents';

  @override
  String get obGiverUncles => 'Aunts and uncles';

  @override
  String get obGiverFriends => 'Friends';

  @override
  String obAddNamed(String name) {
    return 'Add $name';
  }

  @override
  String get giverNew => 'Add a giver';

  @override
  String get giverEdit => 'Edit giver';

  @override
  String get giverNameHint => 'Grandparents, Aunt Marta and Jordi…';

  @override
  String get obOccasionsTitle => 'When are the gifts?';

  @override
  String get obOccasionsBody =>
      'Pick the usual dates. Birthdays come from the dates you entered.';

  @override
  String get obBirthdaysSection => 'Birthdays (created automatically)';

  @override
  String get obNoBirthdays =>
      'If you add someone\'s birthday, it will show up here.';

  @override
  String get obOtherOccasions => 'Other dates';

  @override
  String get obAddOccasion => 'Add another date';

  @override
  String get obPinTitle => 'Protect the gifts';

  @override
  String get obPinBody =>
      'Create a PIN so nobody can see the gifts if they pick up the phone. You can change it in Settings.';

  @override
  String get obPinCreate => 'Create a PIN';

  @override
  String get obFinishing => 'Setting up your list…';

  @override
  String get obSaveError => 'Could not save. Please try again.';

  @override
  String get personNew => 'New person';

  @override
  String get personEdit => 'Edit person';

  @override
  String get personColor => 'Colour';

  @override
  String get personRelation => 'Relationship (optional)';

  @override
  String get personRelationHint => 'Partner, brother, niece…';

  @override
  String get personBirthday => 'Birthday (optional)';

  @override
  String get personBirthdayPick => 'Pick a date';

  @override
  String get personBirthdayNone => 'No date';

  @override
  String get personBirthdayClear => 'Remove date';

  @override
  String get personBirthdayNoYear => 'Do not save the year';

  @override
  String personPendingBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count still to buy',
      one: '$count still to buy',
    );
    return '$_temp0';
  }

  @override
  String get personAllBought => 'all bought';

  @override
  String get giftAdd => 'Add gift';

  @override
  String get giftNoOccasion => 'No occasion';

  @override
  String giftsEmptyTitle(String name) {
    return 'No gifts for $name yet';
  }

  @override
  String get giftsEmptyMessage =>
      'Note down an idea, even if you don\'t know what to buy yet.';

  @override
  String get giftTagSurprise => 'Surprise';

  @override
  String get giftTagRequest => 'Request';

  @override
  String giftRequestedBy(String name) {
    return '$name asked for it';
  }

  @override
  String giftSizeLine(String size) {
    return 'Size or age: $size';
  }

  @override
  String giftPriceActualPlanned(String actual, String planned) {
    return '$actual (planned $planned)';
  }

  @override
  String giftStatusChanged(String item, String status) {
    return '$item: $status';
  }

  @override
  String giftStatusPickerTitle(String item) {
    return 'Status of $item';
  }

  @override
  String get budgetOf => 'of';

  @override
  String budgetHouseFor(String name) {
    return 'Household · $name';
  }

  @override
  String get budgetHouseTotal => 'Household · total';

  @override
  String budgetBarLabel(String spent, String planned) {
    return 'Spent: $spent of $planned';
  }

  @override
  String get filtersButton => 'Filters';

  @override
  String get filtersSheetTitle => 'Filter gifts';

  @override
  String get filterAnyOccasion => 'All';

  @override
  String get filterAnyGiver => 'Everyone';

  @override
  String get filterAnyStatus => 'All';

  @override
  String get filterNeedsBuy => 'Still to buy';

  @override
  String get filterNeedsWrap => 'Still to wrap';

  @override
  String filterRemove(String name) {
    return 'Remove filter $name';
  }

  @override
  String get filterClear => 'Clear filters';

  @override
  String get filterNoResults => 'No gifts match the filters.';

  @override
  String get giftEditorNewTitle => 'New gift';

  @override
  String get giftEditorEditTitle => 'Edit gift';

  @override
  String get giftEditorNoPeople =>
      'Add the person who will receive the gift first.';

  @override
  String get giftRecipientRequired => 'Choose who the gift is for.';

  @override
  String giftAddedNotice(String name) {
    return 'Gift added for $name';
  }

  @override
  String get giftAddedView => 'View';

  @override
  String get giftFieldTitle => 'Gift';

  @override
  String get giftFieldTitleHint => 'Astronaut pyjamas, size 8';

  @override
  String get giftFieldTitleRequired => 'Enter what the gift is.';

  @override
  String get giftPriceSection => 'Price';

  @override
  String get giftFieldPlanned => 'Planned';

  @override
  String get giftFieldActual => 'Actual';

  @override
  String get giftPriceInvalid => 'Enter an amount, for example 12.50.';

  @override
  String get giftFieldStore => 'Store';

  @override
  String get giftFieldUrl => 'Link';

  @override
  String get giftLinkOpen => 'Open link';

  @override
  String get giftLinkCopied => 'The browser could not be opened. Link copied.';

  @override
  String get giftFieldNote => 'Note';

  @override
  String get giftFieldSize => 'Size or age';

  @override
  String get giftRequestSwitch => 'It\'s a request: someone asked for it';

  @override
  String get giftRequestedByField => 'Who asked for it';

  @override
  String get giftRequestedByOther => 'Someone else…';

  @override
  String get giftRequestedByName => 'Name of who asked';

  @override
  String get giftRequestNote => 'Request note';

  @override
  String get giftSurpriseSwitch => 'It\'s a surprise';

  @override
  String get giftSurpriseHint =>
      'Marked so nobody mentions it in front of the person who gets it.';

  @override
  String get giftDelete => 'Delete gift';

  @override
  String confirmDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get confirmDeleteBody =>
      'It is also deleted on your family\'s phones.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done of $total bought';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Everything bought for $occasion';
  }

  @override
  String get giftSaveError => 'Could not save the gift.';

  @override
  String get giftDuplicateTitle => 'Possible duplicate';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return '\"$title\" looks like a gift already noted for $person ($giver).';
  }

  @override
  String get giftDuplicateSave => 'Save anyway';

  @override
  String get giftDuplicateReview => 'Review';

  @override
  String get familySubtitle => 'Who gives what to each person';

  @override
  String get familyGiverHeader => 'Gives';

  @override
  String get familyNoPrice => 'No price';

  @override
  String get familyNothingYet => 'Nothing yet';

  @override
  String get familyLegendAllBought => 'All bought';

  @override
  String get familyLegendPending => 'Something pending';

  @override
  String get familyLegendDuplicate => 'Possible duplicate';

  @override
  String familyCellLabel(
    String giver,
    String person,
    String gifts,
    String price,
    String state,
  ) {
    return '$giver for $person: $gifts, $price, $state';
  }

  @override
  String familyCellEmptyLabel(String giver, String person) {
    return '$giver for $person: nothing yet, add a gift';
  }

  @override
  String familyDuplicateBanner(String person, String title) {
    return 'Possible duplicate: “$title” for $person';
  }

  @override
  String familyDuplicateMore(int count) {
    return 'and $count more';
  }

  @override
  String get occasionNew => 'New occasion';

  @override
  String get occasionEdit => 'Edit occasion';

  @override
  String get occasionNameHint => 'Communion, end of school year…';

  @override
  String get occasionDate => 'Date';

  @override
  String get occasionDatePick => 'Pick a date';

  @override
  String get occasionDateRequired => 'Pick a date.';

  @override
  String get occasionRepeats => 'Repeats every year';

  @override
  String get occasionBirthdayDateHint =>
      'The date comes from the person\'s birthday.';

  @override
  String occasionDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days to go',
      one: '$count day to go',
      zero: 'Today',
    );
    return '$_temp0';
  }

  @override
  String get occasionPassed => 'Already passed';

  @override
  String get budgetCardTitle => 'Household budget';

  @override
  String get budgetCardHint => 'Budget, spent and what is left';

  @override
  String get occasionPeopleSection => 'Each person';

  @override
  String get occasionToWrap => 'to wrap';

  @override
  String get occasionToArrive => 'to arrive';

  @override
  String get occasionNoGifts => 'There are no gifts for this occasion yet.';

  @override
  String get occasionNoGiftsYet => 'No gifts yet';

  @override
  String occasionSplitLabel(String name, String parts) {
    return '$name\'s split: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Still to buy';

  @override
  String get occasionPendingEmpty =>
      'Nothing decided yet. When an idea becomes Decided, it will show up here grouped by store.';

  @override
  String get occasionStoreNone => 'No store';

  @override
  String occasionMarkBought(String item) {
    return 'Mark $item as bought';
  }

  @override
  String get occasionIdeasSection => 'Ideas';

  @override
  String get budgetTitle => 'Budget';

  @override
  String get budgetSubtitle =>
      'You set it for each occasion. Spent adds up the actual price of what the household pays; if something is already bought without an actual price, the planned one counts.';

  @override
  String get budgetSubtitleBudgeted =>
      'You set the budget for each occasion. The three figures only include occasions with a budget. \"Spent\" adds up actual prices for gifts the household pays for. If a purchased gift has no actual price recorded, its planned price counts.';

  @override
  String get budgetPlanned => 'Planned';

  @override
  String get budgetSpent => 'Spent';

  @override
  String get budgetLeft => 'Left';

  @override
  String get budgetOver => 'Over by';

  @override
  String get budgetByPerson => 'By person';

  @override
  String get budgetByOccasion => 'By occasion';

  @override
  String get budgetNote =>
      'What grandparents or uncles give counts as a gift, not as a household expense.';

  @override
  String get budgetEmpty =>
      'There are no household-paid gifts yet. Turn on \"Paid by the household\" for a giver and enter a planned price.';

  @override
  String get occasionBudgetField => 'Budget (optional)';

  @override
  String get occasionBudgetHint =>
      'What you want to spend on this occasion. Leave it empty if there is none.';

  @override
  String get budgetFigure => 'Budget';

  @override
  String get budgetNone => 'No budget';

  @override
  String get budgetSetAction => 'Set a budget';

  @override
  String get budgetEditAction => 'Change budget';

  @override
  String budgetSetFor(String name) {
    return 'Set a budget for $name';
  }

  @override
  String budgetEditFor(String name) {
    return 'Change the budget for $name';
  }

  @override
  String budgetLeftIfBought(String amount) {
    return 'If you buy what is left, you will have $amount left';
  }

  @override
  String budgetSpentOutside(String amount) {
    return 'The household spent another $amount outside budgeted occasions.';
  }

  @override
  String budgetOverIfBought(String amount) {
    return 'If you buy what is left, you will go over by $amount';
  }

  @override
  String budgetSheetTitle(String name) {
    return 'Budget for $name';
  }

  @override
  String get budgetSheetHint => 'Leave it empty to remove the budget.';

  @override
  String get budgetOpenGifts => 'View gifts';

  @override
  String get budgetArchivedTag => 'Archived · not counted';

  @override
  String get budgetCreateOccasion => 'Create an occasion';

  @override
  String get settingsGivers => 'Who gives';

  @override
  String get settingsSecurity => 'Lock';

  @override
  String get settingsShare => 'Family phones';

  @override
  String get settingsAbout => 'About';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutPrivacy =>
      'No accounts and no ads. Your gifts only leave the phone, always encrypted, if you connect another phone or the web, create a recovery code or send a copy.';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutPrivacyPolicyHint => 'Opens in your browser.';

  @override
  String get aboutPrivacyPolicyCopied =>
      'The browser could not be opened. Link copied.';

  @override
  String get aboutSupport => 'Help and support';

  @override
  String get aboutSupportHint => 'Write to us from your email app.';

  @override
  String aboutSupportCopied(String email) {
    return 'The email app could not be opened. Address copied: $email';
  }

  @override
  String get manageArchiveHint =>
      'Archiving takes something off the lists without deleting its gifts; bring it back in Settings › Archive. Deleting removes it for good.';

  @override
  String manageArchiveLabel(String name) {
    return 'Archive $name';
  }

  @override
  String manageRestoreLabel(String name) {
    return 'Restore $name';
  }

  @override
  String get securityPinTitle => 'PIN lock';

  @override
  String get securityPinHint => 'Asks for the PIN when the app opens.';

  @override
  String get securityChangePin => 'Change PIN';

  @override
  String get securityBiometrics => 'Fingerprint or face';

  @override
  String get securityBiometricsHint => 'Opens the app without typing the PIN.';

  @override
  String get securityBiometricsUnavailable =>
      'This phone has no fingerprint or face set up.';

  @override
  String get securityBiometricsFailed =>
      'Could not turn it on. Check the phone\'s fingerprint or face.';

  @override
  String get securityDisableTitle => 'Turn off the PIN';

  @override
  String get securityDisablePrompt => 'Enter your PIN to turn off the lock.';

  @override
  String get securityChangeCurrentPrompt => 'Enter your current PIN.';

  @override
  String get securityPinEnabled => 'PIN turned on.';

  @override
  String get securityPinDisabled => 'Lock turned off.';

  @override
  String get securityPinChanged => 'PIN changed.';

  @override
  String get securityNote =>
      'Without a PIN, anyone who picks up the phone can see the gifts.';

  @override
  String get shareJoinTitle => 'Scan the QR code';

  @override
  String get sharePasteEmpty =>
      'Nothing to paste. Copy the link or text you received first.';

  @override
  String get shareSendError => 'Could not prepare the file.';

  @override
  String get showQrIntro =>
      'On the other phone open Gift Huddle, tap \"Join a family\", then \"Scan the QR code\" and point the camera at this code.';

  @override
  String get showQrWarning =>
      'Don\'t take a screenshot or share it: this code gives access to the whole list. Show it in person only.';

  @override
  String get showQrLabel => 'QR code to connect another phone';

  @override
  String get joinIntro => 'Point the camera at the other phone\'s QR code.';

  @override
  String get scannerWaitingPermission => 'Waiting for camera permission…';

  @override
  String get scannerDeniedTitle => 'The camera is needed';

  @override
  String get scannerDeniedBody =>
      'It is only used to read the QR code; no image is saved.';

  @override
  String get scannerBlockedTitle => 'The camera is blocked';

  @override
  String get scannerBlockedBody =>
      'Camera permission is denied. Turn it on in the phone settings to read the QR code.';

  @override
  String get scannerFailedTitle => 'Could not open the camera';

  @override
  String get scannerFailedBody =>
      'The phone did not answer the permission request. Try again.';

  @override
  String get scannerRetry => 'Try again';

  @override
  String get scannerOpenSettings => 'Open settings';

  @override
  String get joinConflictTitle => 'This phone already has a list';

  @override
  String get joinConflictBody =>
      'If you join the other phone\'s list, this one is replaced and its gifts are lost. Continue?';

  @override
  String get joinReplace => 'Replace and join';

  @override
  String get joinDoneTitle => 'Phones connected';

  @override
  String joinDoneBody(String name) {
    return 'You are now in $name\'s family. Ask them to send you the changes to see the list.';
  }

  @override
  String get incomingTitle => 'Changes received';

  @override
  String get incomingNothing => 'You were already up to date.';

  @override
  String get incomingOtherChanges => 'People or occasions were updated.';

  @override
  String get incomingFailedTitle => 'Could not open the file';

  @override
  String importAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new gifts',
      one: '$count new gift',
    );
    return '$_temp0';
  }

  @override
  String importChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changed',
      one: '$count changed',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deleted',
      one: '$count deleted',
    );
    return '$_temp0';
  }

  @override
  String get syncNowTitle => 'Sync now';

  @override
  String get syncStopTitle => 'Stop syncing';

  @override
  String get syncStopHint => 'This phone stops sending and receiving changes.';

  @override
  String get syncStopConfirmTitle => 'Stop syncing?';

  @override
  String get syncStopConfirmBody =>
      'This phone leaves the family\'s sync and stops sending and receiving changes; the other phones keep syncing with each other. If it is the last one, the encrypted copy on the server is deleted too. What is on each phone stays as it is. To sync again, connect it once more with another phone of the family.';

  @override
  String get syncStopDone => 'Sync turned off.';

  @override
  String get syncStopError =>
      'The server could not be reached. Check the connection and try again.';

  @override
  String get syncPrivacyNote =>
      'The server keeps the list encrypted with a key only your phones have. It cannot see names, gifts or prices, but it does see when and from which IP each phone connects.';

  @override
  String get syncStatusNotConfigured =>
      'Sync is not available in this version.';

  @override
  String get syncStatusNoFamily => 'Create your family or join one to sync.';

  @override
  String get syncStatusDisabled => 'Off';

  @override
  String get syncStatusIdle => 'Waiting to sync';

  @override
  String get syncStatusWaitingPeer => 'Starts when you pair another phone';

  @override
  String get peerConnected => 'Another phone has connected';

  @override
  String peerConnectedNamed(String name) {
    return 'Another phone has connected: $name';
  }

  @override
  String get syncStatusSyncing => 'Syncing…';

  @override
  String get syncStatusSyncedNow => 'Synced just now';

  @override
  String syncStatusSyncedMinutes(int minutes) {
    return 'Synced $minutes min ago';
  }

  @override
  String syncStatusSyncedHours(int hours) {
    return 'Synced $hours h ago';
  }

  @override
  String syncStatusSyncedDays(int days) {
    return 'Synced $days d ago';
  }

  @override
  String get syncStatusOffline => 'Offline, it will be sent later';

  @override
  String get syncStatusError => 'Could not sync';

  @override
  String get syncIssueAuth => 'The server does not accept this family\'s key.';

  @override
  String get syncIssueClockDrift =>
      'Another phone has the wrong date and time. Fix them on that phone.';

  @override
  String get syncIssueTooLarge => 'The list is too large to sync.';

  @override
  String get syncIssueServer =>
      'The server is not responding properly. It will try again.';

  @override
  String get syncIssueRateLimited =>
      'Too many requests in a row. It will try again in a moment.';

  @override
  String get syncIssueUnreadable =>
      'The data on the server cannot be opened with this family\'s key.';

  @override
  String get syncIssueUnknown => 'Something went wrong. It will try again.';

  @override
  String get inviteRowTitle => 'Invite someone';

  @override
  String get joinInviteRowTitle => 'Join with a link';

  @override
  String get inviteIntro =>
      'Create a link so another person can join your family from their own phone, without being with you.';

  @override
  String get inviteHowItWorks =>
      'The link carries no key: it only lets someone ask to join. You will get the request with a 6-digit code and you have to accept it. It expires after 24 hours and works for one person.';

  @override
  String get inviteCreate => 'Create link and invite';

  @override
  String get inviteNeedSync =>
      'To invite remotely, sync must be on and connected.';

  @override
  String get inviteGoToSync => 'Turn sync on';

  @override
  String inviteShareText(String link) {
    return 'I am inviting you to my Gift Huddle list. Open the link and ask to join: $link';
  }

  @override
  String get inviteWaitingTitle => 'Waiting for the link to be opened';

  @override
  String get inviteWaitingBody =>
      'When the other person opens it, you will see their request here. You can leave this screen: the invitation stays active until it expires.';

  @override
  String inviteExpires(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.Hm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'Expires $dateString at $timeString';
  }

  @override
  String get inviteShareAgain => 'Share the link again';

  @override
  String get inviteCancel => 'Cancel invitation';

  @override
  String inviteRequestTitle(String name) {
    return '$name wants to join';
  }

  @override
  String get inviteRequestBody =>
      'If you were not expecting this request, reject it. If the two codes do not match, do not give access.';

  @override
  String get inviteCodeLabel => 'Verification code';

  @override
  String get inviteAccept => 'The codes match, give access';

  @override
  String get inviteReject => 'Reject';

  @override
  String get inviteApprovedTitle => 'Invitation accepted';

  @override
  String inviteApprovedBody(String name) {
    return '$name can now join: their phone is picking up the key.';
  }

  @override
  String get inviteRejectedBody =>
      'You rejected the request. The link no longer works.';

  @override
  String get inviteExpiredBody => 'The invitation has expired.';

  @override
  String get inviteNew => 'Invite another person';

  @override
  String get inviteErrorNetwork => 'Could not reach the server. Try again.';

  @override
  String get inviteErrorUnknown =>
      'The invitation could not be completed. Try again.';

  @override
  String get joinInviteIntro =>
      'Paste the link you were sent. The person who invited you will have to accept your request.';

  @override
  String get joinInviteFieldLabel => 'Invitation link';

  @override
  String get joinInvitePaste => 'Paste';

  @override
  String get joinInviteAsk => 'Ask to join';

  @override
  String get joinInviteBadLink =>
      'This text is not a Gift Huddle invitation link.';

  @override
  String get joinInviteUnavailable =>
      'Remote invitations are not available in this version.';

  @override
  String get joinInviteNetwork =>
      'Could not reach the server. Check your connection.';

  @override
  String get joinInviteTampered =>
      'The invitation could not be opened. Ask for a new link.';

  @override
  String get joinInviteUnknown => 'It could not be completed. Try again.';

  @override
  String get joinInviteTaken =>
      'Someone else has already used this invitation. Ask for a new link.';

  @override
  String get joinInviteGone =>
      'The invitation has expired or was not accepted.';

  @override
  String get joinInviteWaitingTitle => 'Waiting to be accepted';

  @override
  String get joinInviteWaitingBody =>
      'The person who invited you has to see your request. In a few seconds you will see a code here to compare with them. You can wait up to 10 minutes.';

  @override
  String get joinInviteConfirmTitle => 'Compare the code';

  @override
  String get joinInviteConfirmBody =>
      'Ask the person who invited you which code they see on their phone. It must be the same as this one. When they confirm on their phone, you will join the family.';

  @override
  String get joinInviteMismatch => 'It does not match, cancel';

  @override
  String get joinInviteMismatchBody =>
      'You cancelled and have not joined the family. Ask the person who invited you for a new link.';

  @override
  String joinInviteDoneBody(String name) {
    return 'You are now in $name\'s family. The list will arrive in a few seconds.';
  }

  @override
  String get joinInviteRestart => 'Start over';

  @override
  String get syncIssueFirstUpload =>
      'The list is too large for the first upload.';

  @override
  String get inviteCompareNotice =>
      'Compare this code with the one the other person sees.';

  @override
  String get joinInviteWaitingForConfirm =>
      'Waiting for them to confirm on their phone…';

  @override
  String get familyChipAll => 'All';

  @override
  String get familyChipBirthdays => 'Birthdays';

  @override
  String get familyOccasionPickerLabel => 'Occasion';

  @override
  String get familyForAll => 'All occasions';

  @override
  String familyForOccasion(String name, String date) {
    return 'For $name, $date';
  }

  @override
  String get familyForBirthdays => 'For birthdays';

  @override
  String familyCellOccasions(String names) {
    return 'for $names';
  }

  @override
  String peopleCarouselPage(int page, int total) {
    return 'Occasion $page of $total';
  }

  @override
  String peopleCarouselRange(int first, int last, int total) {
    return 'Occasions $first and $last of $total';
  }

  @override
  String get occasionTypeTitle => 'Type of occasion';

  @override
  String get occasionKindChineseNewYear => 'Chinese New Year';

  @override
  String get occasionKindWedding => 'Wedding';

  @override
  String get occasionKindAnniversary => 'Anniversary';

  @override
  String get occasionKindSantJordi => 'Sant Jordi';

  @override
  String get occasionKindValentine => 'Valentine\'s Day';

  @override
  String get occasionKindBaptism => 'Baptism or birth';

  @override
  String get occasionKindCommunion => 'First communion';

  @override
  String get occasionKindGraduation => 'Graduation or end of school year';

  @override
  String get occasionKindCustom => 'Other';

  @override
  String get occasionChineseNewYearHint =>
      'The date changes every year and is worked out for you.';

  @override
  String get occasionCustomColor => 'Colour';

  @override
  String get occasionCustomIcon => 'Icon';

  @override
  String get occasionColorTeal => 'Teal';

  @override
  String get occasionColorSlate => 'Slate';

  @override
  String get occasionIconStar => 'Star';

  @override
  String get occasionIconHeart => 'Heart';

  @override
  String get occasionIconHome => 'Home';

  @override
  String get occasionIconTrip => 'Trip';

  @override
  String get occasionIconSchool => 'School';

  @override
  String get occasionIconPets => 'Pet';

  @override
  String get occasionIconBaby => 'Baby';

  @override
  String get occasionIconWork => 'Work';

  @override
  String get occasionIconMusic => 'Music';

  @override
  String get occasionIconSport => 'Sport';

  @override
  String get occasionIconFlower => 'Flower';

  @override
  String get occasionIconParty => 'Party';

  @override
  String get peopleUpcomingTitle => 'Upcoming occasions';

  @override
  String todayShort(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Today, $dateString';
  }

  @override
  String daysUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String occasionGiftsBought(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'gifts bought',
      one: 'gift bought',
    );
    return '$done of $total $_temp0';
  }

  @override
  String get occasionsGroupCelebrations => 'Celebrations';

  @override
  String get occasionsGroupBirthdays => 'Birthdays';

  @override
  String get familyTotalRow => 'Total';

  @override
  String get familyRecipientHeader => 'Receives';

  @override
  String get familyLegendNothing => 'Nothing';

  @override
  String get familyLegendToBuy => 'To buy';

  @override
  String familyNoGiverCount(int count) {
    return '$count unassigned';
  }

  @override
  String repartoSheetNobodyYet(String giver, String person) {
    return '$giver is not giving $person anything yet';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return '$person has gifts with nobody to give them: tap \"Who?\" to assign them.';
  }

  @override
  String get repartoSheetStartHint => 'Add a new gift to start.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · tap who gives it to change it';
  }

  @override
  String get repartoSheetWho => 'Who?';

  @override
  String get repartoSheetNobody => 'Nobody';

  @override
  String get repartoSheetAddGift => 'Add gift';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'New gift from $giver';
  }

  @override
  String repartoSheetOpenList(String person) {
    return 'Open $person\'s list';
  }

  @override
  String get repartoSheetNoGiver => 'No giver yet';

  @override
  String repartoSheetChipLabel(String giver) {
    return 'Giver: $giver. Change';
  }

  @override
  String repartoSheetLabel(String giver, String person) {
    return 'Gifts from $giver for $person';
  }

  @override
  String get lockBiometricHint => 'Tap the fingerprint to sign in';

  @override
  String get repartoViewLabel => 'Who gives what view';

  @override
  String get repartoViewGrid => 'Grid';

  @override
  String get repartoViewOccasion => 'By occasion';

  @override
  String get repartoOccasionPackets => 'How many gifts each one opens';

  @override
  String repartoOccasionToBuy(int count) {
    return '$count to buy';
  }

  @override
  String repartoOccasionNothingIn(String occasion) {
    return 'Nothing for $occasion';
  }

  @override
  String get repartoOccasionAddShort => 'Add';

  @override
  String repartoOccasionEmptyTitle(String occasion) {
    return 'Nothing in $occasion yet';
  }

  @override
  String get repartoOccasionEmptyMessage =>
      'When you add a gift for this day, you will see here who brings it and how many each person opens.';

  @override
  String repartoPersonSheetLabel(String person) {
    return '$person\'s details';
  }

  @override
  String repartoPersonOpen(String person) {
    return 'Open $person\'s details';
  }

  @override
  String get repartoSelfTag => 'Me';

  @override
  String repartoSelfName(String name) {
    return '$name (me)';
  }

  @override
  String get repartoPersonSheetSub =>
      'How they show up in Who gives what. No gift is deleted.';

  @override
  String get repartoPersonInReparto => 'Shown in Who gives what';

  @override
  String get repartoPersonInRepartoHint =>
      'If you turn it off, they move to \"Left out\".';

  @override
  String get repartoPersonOccasions => 'You give them gifts for';

  @override
  String familyOutsideTitle(int count) {
    return 'Left out · $count';
  }

  @override
  String get familyOutsideNote => 'Not in Who gives what';

  @override
  String get familyIncludeAgain => 'Include again';

  @override
  String familyExcludedStrip(String occasion) {
    return 'No gifts for $occasion';
  }

  @override
  String familySkipsLabel(String occasions) {
    return 'Without $occasions';
  }

  @override
  String get familyLegendExcluded => 'No gifts';

  @override
  String repartoOccasionNotGiving(String occasion) {
    return 'No gifts for $occasion';
  }

  @override
  String get actionEliminate => 'Delete';

  @override
  String manageDeleteLabel(String name) {
    return 'Delete $name';
  }

  @override
  String get manageLockedThisDevice => 'This phone belongs to this person.';

  @override
  String get manageLockedOtherDevice =>
      'Another phone in your family belongs to this person.';

  @override
  String deletePersonTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String deleteOccasionTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String deletePersonGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Their $count gifts will be deleted too.',
      one: 'Their gift will be deleted too.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo => 'Their birthday goes too.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Their $count gifts will be left without a giver.',
      one: 'Their gift will be left without a giver.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String deleteOccasionGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count gifts will be left without an occasion.',
      one: 'Its gift will be left without an occasion.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get deleteIrreversible =>
      'This cannot be undone. It is also deleted on your family\'s phones.';

  @override
  String get deleteRequestedByToo =>
      'On the gifts they asked for, who asked is cleared.';

  @override
  String get deleteGiverBudget =>
      'Their amounts stop counting in the household budget.';

  @override
  String get deleteError => 'Could not delete. Try again.';

  @override
  String get giftNotSaved =>
      'Not saved: this gift is no longer available on this phone.';

  @override
  String giftDeletedNotice(String name) {
    return '“$name” deleted';
  }

  @override
  String get settingsSectionFamily => 'Family';

  @override
  String get settingsSectionDevice => 'This phone';

  @override
  String get settingsSelf => 'This phone belongs to';

  @override
  String get settingsSelfNobody => 'No one';

  @override
  String get settingsSelfSheetTitle => 'Whose phone is this?';

  @override
  String get settingsSelfSheetHint =>
      'Only applies to this phone; it is not shared.';

  @override
  String get settingsSelfError => 'Could not save. Try again.';

  @override
  String get settingsSectionShare => 'Sharing and backup';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsArchive => 'Archive';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsAboutApp => 'About Gift Huddle';

  @override
  String get eraseAllTitle => 'Delete everything';

  @override
  String get eraseAllHint =>
      'The list, the PIN and the settings on this phone.';

  @override
  String get eraseAllConfirmTitle => 'Delete everything?';

  @override
  String get eraseAllConfirmBody =>
      'The whole list, the PIN and the settings are deleted from this phone, and the app starts from scratch. This cannot be undone. Your family\'s other phones keep their copy.';

  @override
  String get eraseAllConfirmServer =>
      'First, this phone leaves the family\'s sync; if it is the last one, the encrypted copy on the server is deleted too.';

  @override
  String get eraseAllContinue => 'Continue';

  @override
  String get eraseAllTypeTitle => 'Last step';

  @override
  String eraseAllTypeBody(String word) {
    return 'Type $word to confirm that you want to delete everything.';
  }

  @override
  String get eraseAllWord => 'DELETE';

  @override
  String get eraseAllFieldLabel => 'Confirmation';

  @override
  String get eraseAllWorking => 'Deleting…';

  @override
  String get eraseAllServerFailedTitle => 'The server could not be reached';

  @override
  String get eraseAllServerFailedBody =>
      'Check the connection and try again. If you delete only this phone, it stays in your family\'s list of phones until another phone removes it, and the encrypted copy stays on the server for the others (or until it expires, if it was the last one).';

  @override
  String get eraseAllRetry => 'Retry';

  @override
  String get eraseAllLocalOnly => 'Delete this phone only';

  @override
  String get eraseAllFailed => 'Not everything could be deleted. Try again.';

  @override
  String get eraseAllPinPrompt =>
      'Enter your PIN to continue with the deletion.';

  @override
  String get eraseAllBiometricReason =>
      'Confirm that you want to delete everything';

  @override
  String get settingsLockOff => 'No lock';

  @override
  String get settingsLockPin => 'PIN';

  @override
  String get settingsLockPinBiometrics => 'PIN and biometrics';

  @override
  String settingsAppearanceValue(String accent, String theme) {
    return '$accent · $theme';
  }

  @override
  String settingsLanguageSystemNow(String language) {
    return 'Now: $language';
  }

  @override
  String get settingsDevicesOnlyThis => 'This one only';

  @override
  String settingsDevicesValue(int count, String status) {
    return '$count · $status';
  }

  @override
  String get syncShortUpToDate => 'up to date';

  @override
  String get syncShortSyncing => 'syncing';

  @override
  String get syncShortPending => 'pending';

  @override
  String get syncShortOffline => 'offline';

  @override
  String get syncShortError => 'error';

  @override
  String get syncShortOff => 'off';

  @override
  String get archiveSubtitle => 'Off the lists, with their gifts kept.';

  @override
  String get archiveEmpty => 'Nothing is archived.';

  @override
  String get archiveNote =>
      'Archiving deletes nothing. Deleting does, for good.';

  @override
  String get devicesSoloTitle => 'Only on this phone';

  @override
  String get devicesSoloBody =>
      'Connect another one to see the same list on both.';

  @override
  String get devicesRecoveryTitle => 'Recovery copy saved';

  @override
  String get devicesRecoveryBody =>
      'The list has an encrypted copy you can restore with your code. Connect another phone to see it on both.';

  @override
  String get devicesManualTitle => 'Connected by file or QR';

  @override
  String get devicesManualBody =>
      'No automatic sync: send the list when it changes.';

  @override
  String get devicesUpToDateTitle => 'All up to date';

  @override
  String devicesUpToDateBody(String status) {
    return '$status. End-to-end encrypted.';
  }

  @override
  String get devicesEncrypted => 'End-to-end encrypted.';

  @override
  String get devicesOffTitle => 'Sync is off';

  @override
  String get devicesOffBody => 'Changes stay on this phone.';

  @override
  String get devicesTurnOn => 'Turn on';

  @override
  String get syncTurnedOn => 'Sync turned on.';

  @override
  String get devicesOfflineTitle => 'Offline';

  @override
  String get devicesOfflineBody => 'Changes will be sent when it is back.';

  @override
  String get devicesConnected => 'Connected';

  @override
  String get devicesThisPhone => 'This phone';

  @override
  String get devicesOtherPhone => 'Another phone';

  @override
  String get devicesPeerHint => 'Connected to this family';

  @override
  String get devicesPeerNoPerson => 'No person yet: it does not open surprises';

  @override
  String get devicesListError => 'The list of phones could not be read.';

  @override
  String get devicesConnect => 'Connect another phone';

  @override
  String get devicesConnectQuestion => 'Where is the other phone?';

  @override
  String get devicesHereTitle => 'It is here';

  @override
  String get devicesHereHint => 'Show it a QR code. It is the quickest way.';

  @override
  String get devicesFarTitle => 'It is far away';

  @override
  String get devicesFarHint => 'Send a link. You approve who joins.';

  @override
  String get devicesSendNow => 'Send the list now';

  @override
  String get devicesSendNowHint => 'As a .gifthuddle file, any way you like.';

  @override
  String get devicesMore => 'More options';

  @override
  String get devicesMoreHint => 'Join another family, stop syncing';

  @override
  String get devicesJoinOther => 'Join this phone to another family';

  @override
  String get devicesJoinOtherHint => 'Replaces the list on this phone.';

  @override
  String get devicesJoinOtherWarning =>
      'If you join another family, the list on this phone is replaced and its gifts are lost.';

  @override
  String get devicesScanTitle => 'Scan their QR';

  @override
  String get devicesScanHint =>
      'The other phone shows it under \"Connect another phone\".';

  @override
  String get devicesPasteLinkTitle => 'Paste an invitation link';

  @override
  String get devicesPasteLinkHint => 'If it was sent to you in a message.';

  @override
  String get devicesPrivacyTitle => 'How the list is protected';

  @override
  String get actionUnderstood => 'Got it';

  @override
  String get backupSubtitle =>
      'An encrypted .gifthuddle file with the whole list.';

  @override
  String get backupSaveTitle => 'Save a copy';

  @override
  String get backupSaveHint =>
      'An encrypted .gifthuddle file, wherever you like.';

  @override
  String get backupRestoreTitle => 'Restore a copy';

  @override
  String get backupRestoreHint => 'From a file or from the clipboard.';

  @override
  String get backupRestoreSubtitle =>
      'It is merged with what is there: nothing is lost.';

  @override
  String get backupPasteTitle => 'Paste from the clipboard';

  @override
  String get backupPasteHint => 'If you got it as a link or as text.';

  @override
  String get backupFileNote =>
      'To open a .gifthuddle file, tap it in Files or in the message it came in and choose Gift Huddle.';

  @override
  String get backupNote =>
      'The copy is encrypted with the family key: for now it only opens on a phone that is already connected.';

  @override
  String get pairingV2Preparing => 'Getting the connection ready…';

  @override
  String get pairingV2NoticeExpires =>
      'The code expires after 24 hours and only lets someone ask to join: nobody gets in unless you compare a number with the other phone.';

  @override
  String get pairingV2FarTitle => 'Share the link';

  @override
  String get pairingV2FarBody =>
      'Send it to whoever you want to connect. When they open it and ask to join, you will see a number here to compare.';

  @override
  String get pairingV2Share => 'Share the link';

  @override
  String get pairingV2WaitingHere =>
      'Waiting for the other phone to read the code…';

  @override
  String get pairingV2CompareTitle => 'Compare the number';

  @override
  String get pairingV2HostCompareBody =>
      'The other phone shows a number. It has to be the same as this one. If it is, tap \"They match\"; if not, \"They do not match\".';

  @override
  String get pairingV2Match => 'They match';

  @override
  String get pairingV2NoMatch => 'They do not match';

  @override
  String get pairingV2NoPersonWarning =>
      'The other phone has not said whose it is yet. You can still let it in: it can choose later and, until then, it will not open the surprises.';

  @override
  String get pairingV2Approving => 'Letting the other phone in…';

  @override
  String get pairingV2HostDone =>
      'Access sent. The other phone needs to finish connecting.';

  @override
  String get pairingV2VersionMismatch =>
      'Both phones need the latest version of Gift Huddle. Update whichever is out of date and start again.';

  @override
  String get pairingV2HostCancelled =>
      'It was cancelled and the code no longer works. You can start again.';

  @override
  String get pairingV2HostFailed =>
      'The other phone could not be connected. Try again.';

  @override
  String get pairingV2NotReady =>
      'To connect another phone, sync must be on and you need an internet connection.';

  @override
  String get pairingV2ChooseTitle => 'Whose phone is this?';

  @override
  String get pairingV2ChooseBody =>
      'The one in your hand. Pick who uses it so Gift Huddle knows which surprises to hide from them.';

  @override
  String pairingV2ChooseBodySelf(String name) {
    return 'You had this phone set as $name\'s. Confirm it or pick someone else.';
  }

  @override
  String get pairingV2ChooseContinue => 'Continue';

  @override
  String get pairingV2ChooseLaterTitle => 'Choose later';

  @override
  String get pairingV2ChooseLaterBody =>
      'If you do not choose now, this phone will not open the surprises until you pick the person and whoever invited you approves it.';

  @override
  String get pairingV2ChooseNone =>
      'This phone does not know anyone in this family yet, so you cannot choose for now. You will be able to once the list arrives.';

  @override
  String get pairingV2GuestWaitingCode =>
      'Waiting for the other phone. In a few seconds you will see a number here to compare.';

  @override
  String get pairingV2GuestCompareBody =>
      'Look at the number the other phone shows. It has to be the same as this one. If it is, tap \"They match\".';

  @override
  String get pairingV2GuestWaitingApproval =>
      'Waiting for the other phone to let you in…';

  @override
  String get pairingV2GuestDoneBody =>
      'You are now in the family. The list will arrive in a few seconds.';

  @override
  String get pairingV2GuestCancelled =>
      'You did not join the family. Ask whoever invited you to start again.';

  @override
  String get pairingV2ReconnectTitle =>
      'Reconnect your phones for the new sync';

  @override
  String get pairingV2ReconnectBody =>
      'Each phone connects again with \"Connect another phone\" by comparing a number.';

  @override
  String pairingV2ClaimTitle(String name) {
    return 'This phone says it belongs to $name';
  }

  @override
  String get pairingV2ClaimBody =>
      'Confirm only if it really is their phone: on it they will see the surprises for everyone else, never their own.';

  @override
  String pairingV2ClaimYes(String name) {
    return 'Yes, it belongs to $name';
  }

  @override
  String get pairingV2ClaimNo => 'It is not theirs';

  @override
  String get pairingV2MigrateTitle => 'Switch to the new sync?';

  @override
  String get pairingV2MigrateBody =>
      'To connect another phone, this family switches to the new, safer sync. This cannot be undone: the phones that were already connected stop receiving this phone\'s changes until you connect them again, one by one, with \"Connect another phone\". Nothing is lost.';

  @override
  String get pairingV2MigrateContinue => 'Continue';

  @override
  String get joinReplacePinPrompt =>
      'Enter your PIN to replace the list on this phone.';

  @override
  String get joinReplaceBiometricReason =>
      'Confirm that you want to replace the list on this phone';

  @override
  String get devicesPeerPending => 'Waiting for approval';

  @override
  String get devicesPeerFrozen => 'Frozen: waiting for approval';

  @override
  String get devicesPeerReconfirm => 'Confirm whose it is';

  @override
  String get deviceReviewNoticeTitle => 'Phones to review';

  @override
  String deviceReviewNoticeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count phones are waiting for you to confirm them.',
      one: 'One phone is waiting for you to confirm it.',
    );
    return '$_temp0';
  }

  @override
  String get deviceReviewOpen => 'Review phones';

  @override
  String deviceReviewProgress(int current, int total) {
    return '$current of $total';
  }

  @override
  String get deviceReviewDoneTitle => 'All reviewed';

  @override
  String get deviceReviewDoneBody => 'No phones are left to confirm.';

  @override
  String get deviceDetailOwner => 'Whose it is';

  @override
  String get deviceDetailNoPerson => 'No person';

  @override
  String get deviceDetailStatus => 'Status';

  @override
  String get deviceStatusActive => 'Connected';

  @override
  String get deviceStatusNoPerson => 'Connected, no person';

  @override
  String get deviceStatusPending => 'Waiting for approval';

  @override
  String get deviceStatusFrozen => 'Frozen';

  @override
  String get deviceStatusReconfirm => 'Needs to be confirmed again';

  @override
  String get deviceDetailSelfNote =>
      'This is your phone. To stop syncing it, use “Stop syncing” in “More options”.';

  @override
  String get deviceRemoveTitle => 'Remove this phone';

  @override
  String get deviceRemoveHint => 'It stops receiving the new list.';

  @override
  String get deviceRemoveConfirmTitle => 'Remove this phone?';

  @override
  String get deviceRemoveConfirmBody =>
      'It stops receiving new changes right away. What it already has cannot be erased from it. What only that phone had may be lost. This cannot be undone.';

  @override
  String get deviceRemoveConfirmAction => 'Remove phone';

  @override
  String get deviceRemoveWaitTitle => 'This phone will wait for approval again';

  @override
  String get deviceRemoveWaitBody =>
      'The phone you are about to remove is the only one that approved this phone\'s change of person. If you remove it, this phone will wait for another one in the family to approve it and, until then, it will not open surprises.';

  @override
  String get deviceRemoveWaitAction => 'Remove anyway';

  @override
  String get deviceRemovedSnack => 'Phone removed';

  @override
  String get deviceRemoveError =>
      'The phone could not be removed. Try again when you are online.';

  @override
  String deviceApproveQuestion(String name) {
    return 'Is this phone $name\'s?';
  }

  @override
  String get deviceApproveQuestionNoPerson => 'Approve this phone?';

  @override
  String deviceApproveYes(String name) {
    return 'Yes, it is $name\'s';
  }

  @override
  String get deviceApproveYesNoPerson => 'Approve this phone';

  @override
  String get deviceApproveLater => 'Later';

  @override
  String get deviceApproveNewcomer =>
      'Check in person before approving it: an approved phone receives the family\'s list.';

  @override
  String get deviceApprovePersonChanged =>
      'It changed person. By approving it, it will be able to vouch for other phones in the family from now on.';

  @override
  String get deviceApproveOrphan =>
      'It stopped being linked to this phone. If you approve it, it receives the surprises meant for it again.';

  @override
  String get deviceApproveDetached =>
      'This phone is no longer linked to the family, but it confirmed you. Approve it only if you know it.';

  @override
  String get deviceApproveFrozen =>
      'Its changes are frozen and deleted items cannot be cleaned up until you approve or remove it.';

  @override
  String get deviceApprovedSnack => 'Phone approved';

  @override
  String get deviceApproveError => 'The phone could not be approved.';

  @override
  String get deviceChangedNotice => 'This phone has changed: review it again.';

  @override
  String get deviceRemovedPendingSnack =>
      'Removed from this phone. Its access still has to be cut: this happens as soon as there is a connection.';

  @override
  String get deviceApproveCanVouch =>
      'Its record has changed: by approving it, it will be able to vouch for other phones in the family from now on.';

  @override
  String get webGateConnectTitle => 'Connect this computer';

  @override
  String get webGateConnectIntro =>
      'You pair it with your phone just once. After that you only need your PIN.';

  @override
  String get webGateStepOpenApp => 'Open Gift Huddle on your phone.';

  @override
  String get webGateConnectStep2 =>
      'Go to Family phones and tap Connect the web app.';

  @override
  String get webGateConnectStep3 => 'Scan this code.';

  @override
  String get webGateConnectWaiting => 'Waiting for your phone…';

  @override
  String get webGateCompareTitle => 'Check the code';

  @override
  String get webGateCompareLabel => 'Verification code';

  @override
  String get webGateCompareBody =>
      'Check that your phone shows the same code, confirm it here and approve it on your phone too.';

  @override
  String get webGateCompareWaiting => 'Waiting for your phone to approve…';

  @override
  String get webGateCompareConfirmed => 'You confirmed the code here';

  @override
  String get webGateFailedTitle => 'Could not connect';

  @override
  String get webGateFailedExpired =>
      'The code expired. Start again to get a new one.';

  @override
  String get webGateFailedMismatch =>
      'The codes did not match, so nothing was connected. Start again.';

  @override
  String get webGateFailedRejected =>
      'The phone declined the connection. Start again if you want to retry.';

  @override
  String get webGateFailedNetwork =>
      'Could not reach the server. Check your connection and start again.';

  @override
  String get webGateFailedCancelled =>
      'The phone cancelled the connection or the invitation is no longer available. Start again and reconnect from your phone.';

  @override
  String get webGateStartAgain => 'Start again';

  @override
  String webGateChoosePinTitle(String name) {
    return 'This computer belongs to $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Choose a PIN or passphrase to open it. We will ask for it every time you come in.';

  @override
  String get webGatePinLabel => 'PIN or passphrase';

  @override
  String get webGatePinRepeatLabel => 'Repeat the PIN or passphrase';

  @override
  String get webGatePinShow => 'Show';

  @override
  String get webGatePinHide => 'Hide';

  @override
  String get webGatePinRule =>
      '6 digits or more, or a passphrase of 8 characters or more.';

  @override
  String get webGatePinSameHint => 'You can use the same PIN as on your phone.';

  @override
  String get webGatePinMismatch => 'They do not match. Type them again.';

  @override
  String get webGatePinNoRecover =>
      'If you forget it, you will have to connect this computer again from a phone.';

  @override
  String get webGateContinue => 'Continue';

  @override
  String get webGateSaving => 'Saving…';

  @override
  String get webGateUnlockTitle => 'Unlock Gift Huddle';

  @override
  String get webGateUnlockBody =>
      'Enter the PIN or passphrase for this computer.';

  @override
  String get webGateUnlock => 'Unlock';

  @override
  String get webGateUnlocking => 'Unlocking…';

  @override
  String get webGateWrongPin => 'Wrong PIN or passphrase.';

  @override
  String webGateAttemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts left.',
      one: '$count attempt left.',
    );
    return '$_temp0';
  }

  @override
  String webGateWait(int seconds) {
    return 'Wait $seconds s to try again.';
  }

  @override
  String get webGateSuspendedTitle => 'Too many attempts';

  @override
  String get webGateSuspendedBody =>
      'Unlock it from a phone. Nothing has been deleted.';

  @override
  String get webGateSuspendedStep2 => 'Go to Family phones and tap Web.';

  @override
  String get webGateSuspendedStep3 => 'Tap Allow unlocking again.';

  @override
  String get webGateRetry => 'Try again';

  @override
  String get webGateDisconnectedTitle => 'This computer is no longer connected';

  @override
  String get webGateDisconnectedBody =>
      'It was removed from the family from a phone, or the list no longer exists.';

  @override
  String webGateDisconnectedUnsent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes that were not uploaded are saved on this computer, encrypted.',
      one:
          '$count change that was not uploaded is saved on this computer, encrypted.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Connect again';

  @override
  String get webGateErase => 'Erase this computer\'s data';

  @override
  String get webGateEraseTitle => 'Erase this computer\'s data?';

  @override
  String get webGateEraseBody =>
      'Everything Gift Huddle keeps here is erased. This cannot be undone.';

  @override
  String get webGateEraseBodyUnsent =>
      'Everything Gift Huddle keeps here is erased, including changes that were not uploaded. This cannot be undone.';

  @override
  String get webGateDamagedTitle => 'The data on this computer is damaged';

  @override
  String get webGateDamagedBody =>
      'It cannot be read safely. To continue, erase it and connect this computer again from a phone. Changes that were not uploaded will be lost.';

  @override
  String get webGateDamagedPhoneHint =>
      'On your phone, remove the previous web entry under Family phones.';

  @override
  String get webGateOtherTabTitle => 'Gift Huddle is open in another tab';

  @override
  String get webGateOtherTabBody => 'It can only be used in one tab at a time.';

  @override
  String get webGateUseHere => 'Use it here';

  @override
  String get webGateLockedLabel => 'Gift Huddle locked';

  @override
  String get webSettingsTitle => 'This computer';

  @override
  String get webSettingsChangePin => 'Change PIN';

  @override
  String get webSettingsChangePinHint =>
      'The one that opens Gift Huddle on this computer.';

  @override
  String get webSettingsChangePinTitle => 'Change PIN or passphrase';

  @override
  String get webSettingsCurrentPin => 'Current PIN or passphrase';

  @override
  String get webSettingsNewPin => 'New PIN or passphrase';

  @override
  String get webSettingsNewPinRepeat => 'Repeat the new PIN or passphrase';

  @override
  String get webSettingsCurrentWrong =>
      'The current PIN or passphrase is not correct.';

  @override
  String get webSettingsChangeFailed => 'Could not change it. Try again.';

  @override
  String get webSettingsPinChanged => 'PIN changed.';

  @override
  String get webSettingsLockNow => 'Lock now';

  @override
  String get webSettingsForget => 'Forget this computer';

  @override
  String get webSettingsForgetHint =>
      'It leaves the family and its stored data is erased.';

  @override
  String get webSettingsForgetTitle => 'Forget this computer?';

  @override
  String get webSettingsForgetBody =>
      'This computer will leave the family and everything Gift Huddle keeps on it will be erased, including changes that were not uploaded. Nothing changes on your phones. To use it again you will have to connect it again.';

  @override
  String get webSettingsForgetConfirm => 'Forget';

  @override
  String get webSettingsPersistenceDenied =>
      'The browser could erase this computer\'s data if it runs low on space.';

  @override
  String webSetAsideNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes cannot be uploaded because they are for a protected person. They are kept on this computer.',
      one:
          '$count change cannot be uploaded because it is for a protected person. It is kept on this computer.',
    );
    return '$_temp0';
  }

  @override
  String get webGateChoosePinCheck =>
      'If your phone did not show the same code, do not continue: tap Start again.';

  @override
  String get webGateRestartTitle => 'Start again?';

  @override
  String get webGateRestartBody =>
      'This connection will be discarded and a new QR code will appear. The PIN you typed will not be saved.';

  @override
  String get webGateRestartConfirm => 'Yes, start again';

  @override
  String webFailedAttemptsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'There were $count failed attempts to unlock this computer since the last time. If it was not you, change the PIN.',
      one:
          'There was $count failed attempt to unlock this computer since the last time. If it was not you, change the PIN.',
    );
    return '$_temp0';
  }

  @override
  String devicesWebOf(String name) {
    return 'Web for $name';
  }

  @override
  String get devicesWebTitle => 'Web';

  @override
  String get devicesWebHint => 'Computer connected to this family';

  @override
  String get devicesConnectWeb => 'Connect the web';

  @override
  String get devicesConnectWebHint => 'To add gifts from a computer.';

  @override
  String get connectWebTitle => 'Connect the web';

  @override
  String get connectWebIntro =>
      'To add gifts from a computer: open web.gifthuddle.app and scan the code that appears.';

  @override
  String get connectWebScanInvalid =>
      'That is not the Gift Huddle web code. Scan the one shown on the computer.';

  @override
  String get connectWebWhoseTitle => 'Whose computer is this?';

  @override
  String get connectWebWhoseBody =>
      'Choose who will use it. The computer connects as theirs.';

  @override
  String get connectWebNoPeople =>
      'There are no people yet. Add a person before connecting the web.';

  @override
  String get connectWebWaiting => 'Waiting for the computer to answer…';

  @override
  String get connectWebCompareBody =>
      'The computer shows a code. It must be the same as this one. If it is, tap “They match”; if not, “They do not match”.';

  @override
  String get connectWebApproving => 'Giving the computer access…';

  @override
  String get connectWebDoneTitle => 'Computer connected';

  @override
  String get connectWebDoneBody =>
      'On the computer, choose a PIN to open Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'This code is no longer valid. On the computer, tap Start again and scan the new one.';

  @override
  String get connectWebScanAgain => 'Scan another code';

  @override
  String get connectWebFailed =>
      'The computer could not be connected. On the computer, tap Start again and scan the new code.';

  @override
  String get connectWebCancelled =>
      'It was cancelled and the code no longer works. On the computer, tap Start again.';

  @override
  String get deviceWebResume => 'Allow unlocking again';

  @override
  String get deviceWebResumeHint =>
      'If the computer was suspended after too many PIN attempts. Nothing is deleted.';

  @override
  String get deviceWebResumeTitle => 'Allow unlocking again?';

  @override
  String get deviceWebResumeBody =>
      'This computer will accept PIN attempts again. Do it only if its owner was the one who got it wrong.';

  @override
  String get deviceWebResumeConfirm => 'Allow';

  @override
  String get deviceWebResumeDone => 'Done. The computer can be unlocked again.';

  @override
  String get deviceWebResumeError =>
      'That did not work. Check your connection and try again.';

  @override
  String get deviceRemoveWebTitle => 'Remove this web app';

  @override
  String get deviceRemoveWebHint =>
      'This computer stops receiving the new list.';

  @override
  String get deviceRemoveWebConfirmTitle => 'Remove this web app?';

  @override
  String get deviceRemoveWebConfirmBody =>
      'This computer will lose access and stop receiving new changes right away. What it already has on screen cannot be erased from it. What only that computer had may be lost. This cannot be undone.';

  @override
  String get deviceRemoveWebConfirmAction => 'Remove web app';

  @override
  String get deviceRemovedWebSnack => 'Web app removed';

  @override
  String get deviceRemovedWebPendingSnack =>
      'Removed from this phone. Its access still has to be cut: this happens as soon as there is a connection.';

  @override
  String get deviceRemoveWebError =>
      'The web app could not be removed. Try again when you are online.';

  @override
  String get webSyncSaved => 'Saved';

  @override
  String get webSyncOffline => 'Offline';

  @override
  String get webSyncAwaitingConfirm =>
      'This computer is waiting for a phone to confirm it';

  @override
  String get webOperationUnavailable =>
      'This cannot be done from the computer. Do it from a phone.';

  @override
  String get selfChangeConfirmTitle => 'Change who this phone belongs to?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'You are about to say this phone belongs to $name. That changes what it can see, not just the name.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'You are about to remove the person assigned to this phone. This changes which gifts and surprises you can see on it.';

  @override
  String selfChangeEffectHides(String name) {
    return 'This phone will stop seeing the gifts for $name and their surprises.';
  }

  @override
  String get selfChangeEffectNobody =>
      'This phone will have no person assigned and will not be able to show surprises until someone is assigned to it.';

  @override
  String get selfChangeEffectWait =>
      'Until another phone in the family approves it, this phone will not see anyone\'s surprises.';

  @override
  String get selfChangeEffectReconfirm =>
      'Phones this one had approved may have to be confirmed again.';

  @override
  String get selfChangeConfirmAction => 'Change person';

  @override
  String get selfChangePendingTitle =>
      'Waiting for approval from another phone';

  @override
  String selfChangePendingBody(String name) {
    return 'This phone now belongs to $name. Another phone in the family has to approve it; until then, you will not see anyone\'s surprises.';
  }

  @override
  String get selfChangePendingBodyNobody =>
      'This phone no longer has a person assigned and is waiting for approval from another family phone. Even after approval, it cannot show surprises until someone is assigned to it.';

  @override
  String get selfChangePendingOrphans =>
      'Some phones you had approved are waiting for you to confirm them again.';

  @override
  String get selfChangeExhaustedTitle =>
      'You can no longer change who this phone belongs to';

  @override
  String get selfChangeExhaustedBody =>
      'This phone has reached the limit for changing who it belongs to. To choose someone else, connect it to the family again as a new phone, using another family phone in person.';

  @override
  String get selfWaitingHint => 'Waiting for approval from another phone';

  @override
  String get healthRevokedTitle =>
      'Another phone in the family removed this one';

  @override
  String get healthRevokedBody =>
      'What you have saved is still on this phone, but it no longer syncs. Retrying will not help: it has to be connected again with another phone in the family, in person.';

  @override
  String get healthRevokedAction => 'Connect again';

  @override
  String healthFrozenTitle(String names) {
    return 'Surprises on hold for $names';
  }

  @override
  String get healthFrozenTitleGeneric => 'Surprises on hold';

  @override
  String get healthFrozenBody =>
      'Nothing has been lost. To show surprises, this phone must be assigned to someone in the family and approved by another family phone.';

  @override
  String healthNamesAnd(String head, String last) {
    return '$head and $last';
  }

  @override
  String get healthRenewSoon => 'The list should be renewed soon';

  @override
  String get healthResolveSection => 'To resolve';

  @override
  String get healthUnbackedTitle => 'Access with no backing';

  @override
  String get healthUnbackedBody =>
      'A phone has access to the server but is not in the family\'s phone list. If you do not recognise it, remove its access.';

  @override
  String healthUnbackedRef(String ref) {
    return 'Reference: $ref';
  }

  @override
  String get healthUnbackedAction => 'Remove access';

  @override
  String get healthUnbackedConfirmTitle => 'Remove this access?';

  @override
  String get healthUnbackedConfirmBody =>
      'That phone loses its access to the family server. If it was one of yours, you will have to connect it again in person. This cannot be undone.';

  @override
  String get healthUnbackedDone => 'Access removed';

  @override
  String healthDepartedTitle(String name) {
    return 'Incomplete removal: $name';
  }

  @override
  String get healthDepartedBody =>
      'It no longer has access to the server, but its removal still has to be completed in the phone list to update permissions and keys.';

  @override
  String get healthDepartedAction => 'Complete removal';

  @override
  String get healthDepartedDone => 'Removal completed';

  @override
  String get healthResolveBusy => 'One moment';

  @override
  String get healthResolveError =>
      'Could not complete. Check the connection and try again.';

  @override
  String get healthRetry => 'Retry';

  @override
  String get healthUnbackedNotNeeded =>
      'This access no longer needs to be removed.';

  @override
  String get settingsSelfSheetHintV2 =>
      'The person you choose determines which gifts and surprises you can see on this phone. The change is shared with the other family phones.';

  @override
  String get protectionRowTitle => 'Secret gifts';

  @override
  String protectionRowHint(String name) {
    return 'Keep $name from seeing their gifts on their phone.';
  }

  @override
  String get protectionStatusOff => 'Off';

  @override
  String get protectionStatusRequested => 'Requested';

  @override
  String get protectionStatusActive => 'On';

  @override
  String protectionSheetTitle(String name) {
    return 'Secret gifts for $name';
  }

  @override
  String protectionIntro(String name) {
    return 'With secret gifts on, $name\'s phone shows no gifts for $name, not even how many there are. The rest of the family still sees them.';
  }

  @override
  String get protectionEffectOthers =>
      'Other family phones with permission can still see and edit them.';

  @override
  String protectionEffectKept(String name) {
    return 'Gifts that $name\'s phone already received before this was turned on cannot be removed from it.';
  }

  @override
  String get protectionEffectConfirm =>
      'A phone with permission has to confirm it.';

  @override
  String get protectionRequest => 'Request protection';

  @override
  String get protectionRequestedTitle => 'Protection requested';

  @override
  String protectionWaitingBody(String name) {
    return 'Waiting for a phone with permission to confirm it. Until then, $name\'s gifts are not shown on any phone.';
  }

  @override
  String protectionConfirmBody(String name) {
    return 'This phone has permission to confirm it. Once it is on, $name\'s gifts stop showing on their phone.';
  }

  @override
  String get protectionActivate => 'Turn on now';

  @override
  String get protectionActiveTitle => 'Protection on';

  @override
  String protectionActiveBody(String name) {
    return '$name sees none of their gifts on their phone.';
  }

  @override
  String get protectionDeactivate => 'Turn off protection';

  @override
  String protectionDeactivateTitle(String name) {
    return 'Turn off secret gifts for $name?';
  }

  @override
  String protectionDeactivateBody(String name) {
    return 'All available gifts for $name, from any year, will be published, including those pending on this phone. After that, $name will see them on their phone.';
  }

  @override
  String get protectionDeactivateConfirm => 'Turn off';

  @override
  String protectionCannotDeactivate(String name) {
    return 'This phone cannot turn it off right now: it needs permission and the current key for $name.';
  }

  @override
  String get protectionChangeFailed =>
      'The protection could not be changed. Nothing was modified.';

  @override
  String secretBlockTitle(String name) {
    return 'Secret gifts for $name';
  }

  @override
  String get secretBlockNote => 'This phone does not show them.';

  @override
  String protectionReason_protectedPerson(String name) {
    return '$name\'s gifts are secret and cannot be saved this way.';
  }

  @override
  String protectionReason_noEntitlement(String name) {
    return 'This phone has no permission for $name\'s secret gifts. Ask another family phone that has permission.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'This phone belongs to $name: its gifts cannot be created or seen here while they are secret.';
  }

  @override
  String protectionReason_missingEpochKey(String name) {
    return 'The current key for $name\'s gifts is missing. Another phone with permission has to give you access.';
  }

  @override
  String protectionReason_protectionPending(String name) {
    return 'A phone with permission still has to confirm the protection for $name.';
  }

  @override
  String protectionReason_unreadableSlot(String name) {
    return 'Part of $name\'s gifts cannot be opened. Nothing was changed: recover access before going on.';
  }

  @override
  String protectionReason_blockFull(String name) {
    return '$name\'s secret gifts have reached the limit. Delete some to add more.';
  }

  @override
  String protectionReason_giftTooLarge(String name) {
    return 'This gift is too large to keep secret. Shorten the notes.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'This phone has no room left to store more secret gifts. Ask another phone with permission to add them.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'There is no room right now for more of the family\'s secret gifts.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Secret gifts need this phone to be connected to the family with the new version.';
  }

  @override
  String get giftProtectedRejected => 'The gift was not saved.';

  @override
  String get giftSavedLocally =>
      'Saved on this phone only. It is waiting to be stored and shared.';

  @override
  String get giftSavedLocallyAction => 'See pending';

  @override
  String get giftOwnRequestRestricted =>
      'While protection is on, this phone cannot create or see gifts for its own person. Ask someone else in the family.';

  @override
  String get pendingGiftsTitle => 'Pending gifts';

  @override
  String get pendingGiftsIntro =>
      'These gifts are stored encrypted on this phone only. Until they are stored and shared with the family, other phones do not see them. If you lose this phone first, they are lost.';

  @override
  String get pendingGiftsRetry => 'Try again';

  @override
  String get pendingGiftsRetrying => 'Trying again';

  @override
  String get pendingGiftsStill =>
      'It still does not fit. Nothing was published and the gifts stay on this phone.';

  @override
  String get pendingGiftsRetryError =>
      'The retry failed. The gifts are still stored on this phone.';

  @override
  String get pendingGiftsDoneTitle => 'All stored';

  @override
  String get pendingGiftsDoneBody => 'No gifts are pending any more.';

  @override
  String pendingGiftsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gifts waiting to be stored',
      one: '$count gift waiting to be stored',
    );
    return '$_temp0';
  }

  @override
  String get pendingGiftsNoticeAction => 'View';

  @override
  String get peopleSummaryTitle => 'Summary';

  @override
  String get giftsEmptyOccasionsHint =>
      'Or add the first one for an upcoming occasion';

  @override
  String occasionGiftsBoughtShort(int done, int total) {
    return '$done of $total bought';
  }

  @override
  String get boardToday => 'Today';

  @override
  String get boardNowTitle => 'What\'s next';

  @override
  String boardSubtitle(String date, int bought, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total gifts bought',
      one: '$total gift bought',
    );
    return '$date · $bought of $_temp0';
  }

  @override
  String get boardLaneDecide => 'To decide';

  @override
  String get boardLaneBuy => 'To buy';

  @override
  String get boardLaneArrive => 'To arrive';

  @override
  String get boardLaneWrap => 'To wrap';

  @override
  String get boardLaneReady => 'Ready';

  @override
  String get boardLaneEmpty => 'Nothing here';

  @override
  String boardMoveTo(String lane) {
    return 'Move to $lane';
  }

  @override
  String boardLaneAdd(String lane) {
    return 'Add gift to $lane';
  }

  @override
  String boardGiftMoved(String item, String lane) {
    return '$item: $lane';
  }

  @override
  String get boardOccasionsHint => 'Pick an occasion to see its board.';

  @override
  String boardSeeAll(int count) {
    return 'See all ($count)';
  }

  @override
  String get boardBudgetEmptyTitle => 'Nothing planned yet';

  @override
  String get boardChangeDate => 'Change date';

  @override
  String get boardSettingsIndex => 'Sections';

  @override
  String get boardEditorLabel => 'Gift editor';

  @override
  String get boardNoGiftsYet => 'No gifts yet';

  @override
  String get boardSidebarCollapse => 'Collapse the sidebar';

  @override
  String get boardSidebarExpand => 'Expand the sidebar';

  @override
  String get boardSearchHint => 'Search for a gift';

  @override
  String get boardSearchNone => 'No gift matches';

  @override
  String get boardPersonFilter => 'Person';

  @override
  String get boardPersonFilterAll => 'Everyone';

  @override
  String get searchClear => 'Clear search';

  @override
  String get boardColStatus => 'Status';

  @override
  String get boardColGiver => 'Giver';

  @override
  String get boardColSize => 'Size';

  @override
  String get boardRepartoNoGiver => 'No giver yet';

  @override
  String get boardRepartoNoGiverNone => 'Every gift has someone to give it.';

  @override
  String get boardRepartoDuplicates => 'Possible duplicates';

  @override
  String get boardRepartoDuplicatesNone => 'No gift looks repeated.';

  @override
  String boardRowMore(String name) {
    return 'More actions for $name';
  }

  @override
  String get tourTitle => 'How it works';

  @override
  String get tourSkip => 'Skip';

  @override
  String tourPageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get tour1Title => 'Note down every gift';

  @override
  String get tour1Body =>
      'Pick who it is for, which occasion and who gives it. An idea is enough.';

  @override
  String get tour2Title => 'Mark it as bought';

  @override
  String get tour2Body =>
      'Tap the checkbox and the gift leaves “Still to buy” and moves to “to arrive”. If you get it wrong, undo it right away.';

  @override
  String get tour3Title => 'People and occasions';

  @override
  String get tour3Body =>
      'Each person has their own list. Christmas, Three Kings and birthdays sort it, and the split shows who pays for what.';

  @override
  String get tour4Title => 'The family shares the list';

  @override
  String get tour4Body =>
      'Connect another phone with a QR code, in person. Everything travels encrypted and changes arrive on their own.';

  @override
  String get tour5Title => 'Surprises stay safe';

  @override
  String get tour5Body =>
      'Each person\'s phone cannot see their own gifts. PIN or biometrics, no accounts, no ads.';

  @override
  String get tour6Title => 'On the computer too';

  @override
  String get tour6Body =>
      'Connect the browser once and the list is on a big screen.';

  @override
  String get tourDemoScooter => 'Scooter';

  @override
  String get tourDemoPuzzle => 'Puzzle';

  @override
  String get tourDemoPajamas => 'Pajamas';

  @override
  String get tourDemoChristmas => 'Christmas';

  @override
  String get tourDemoBirthday => 'Birthday';

  @override
  String get tourDemoConnected => 'Connected';

  @override
  String get tourDemoEncrypted => 'Encrypted';

  @override
  String get tourDemoHidden => 'Hidden gifts';

  @override
  String get settingsRecovery => 'Recovery code';

  @override
  String get recoveryValueNone => 'Not created';

  @override
  String get recoveryValuePrepared => 'Ready';

  @override
  String get recoveryValuePending => 'Preparing';

  @override
  String get recoveryValueUnconfirmed => 'Not checked';

  @override
  String get recoveryUnconfirmedTitle => 'Check your code to finish';

  @override
  String get recoveryUnconfirmedBody =>
      'The code does not count as saved yet. Continue to check the words, or check a file you already saved. If the words have already been shown, a new code will be created and the old one will stop working.';

  @override
  String get recoveryValueAttention => 'Check';

  @override
  String get recoveryValueTransferred => 'Moved';

  @override
  String get recoverySubtitle => 'To get the list back on a new phone.';

  @override
  String get recoveryAbsentTitle =>
      'Create a code to recover the list if you lose this phone';

  @override
  String get recoveryAbsentBody =>
      'With 24 words you can get the list, and everything this phone can see, back on another phone. If this is your only phone, an encrypted copy is saved on the server: without the words, nobody can read it.';

  @override
  String get recoveryAbsentWarn =>
      'Anyone with the words can access the list with the same permissions as this phone. They do not bring back what was never synced.';

  @override
  String get recoveryCreate => 'Create recovery code';

  @override
  String get recoveryPreparedTitle => 'Code ready';

  @override
  String get recoveryPreparedBody =>
      'The encrypted copy is ready. The words cannot be shown again: if you lose them, change the code.';

  @override
  String get recoveryPendingTitle => 'Preparing the copy…';

  @override
  String get recoveryPendingBody =>
      'The encrypted copy is being saved. It needs a connection and finishes by itself when there is one.';

  @override
  String get recoveryAttentionTitle => 'Check the recovery code';

  @override
  String get recoveryChange => 'Change the code';

  @override
  String get recoveryChangeHint => 'Earlier files and words will stop working.';

  @override
  String get recoveryRemove => 'Remove the code';

  @override
  String get recoveryRemoveHint =>
      'The words will stop working and the copy is deleted.';

  @override
  String get recoveryRemoveTitle => 'Remove the recovery code?';

  @override
  String get recoveryRemoveBody =>
      'The recovery copy is deleted and the 24 words stop working. You can create another code whenever you like.';

  @override
  String get recoveryRemoveSoloNote =>
      'Since no other phone or web app is connected, the encrypted copy of the list is also deleted from the server and the list is only on this phone again.';

  @override
  String get recoveryRemoveConfirm => 'Remove code';

  @override
  String get recoveryRemoved => 'Code removed';

  @override
  String get recoveryRetry => 'Try again';

  @override
  String get recoveryIntroTitle => 'Create the code';

  @override
  String get recoveryRotateTitle => 'Change the code';

  @override
  String get recoveryIntroBody =>
      'You will see 24 words. With them you can get the list, and everything this phone can see, back on another phone.';

  @override
  String get recoveryRotateBody =>
      'A new code will be created. The old one stops working once the new one is ready: earlier files and words will stop working.';

  @override
  String get recoveryPoint1 =>
      'Write them on paper or keep them in a password manager.';

  @override
  String get recoveryPoint2 =>
      'Whoever has them can access the list with the same permissions as this phone.';

  @override
  String get recoveryPoint3 => 'They do not bring back what was never synced.';

  @override
  String get recoveryContinue => 'Continue';

  @override
  String get recoveryAuthTitle => 'Recovery code';

  @override
  String get recoveryAuthMessage => 'Enter your PIN to see the words.';

  @override
  String get recoveryAuthBiometric =>
      'Confirm it is you to see the recovery code';

  @override
  String get recoveryMaking => 'Preparing the code…';

  @override
  String get recoveryWordsTitle => 'Your 24 words';

  @override
  String get recoveryWordsBody =>
      'Write them down in order. Once you leave this process, you will not be able to see them again.';

  @override
  String get recoveryWordsWarn =>
      'Anyone with these words can access the list with the same permissions as this phone. Do not take a screenshot or send them in a message.';

  @override
  String recoveryWordItem(int number, String word) {
    return 'Word $number: $word';
  }

  @override
  String get recoveryShowQr => 'Show QR code';

  @override
  String get recoveryShowWords => 'Show the words';

  @override
  String get recoveryQrBody =>
      'This QR code lets you recover the list just like the 24 words. Do not take a screenshot or send it in a message.';

  @override
  String get recoveryQrLabel => 'Recovery QR code';

  @override
  String get recoveryWordsSaved => 'I have saved them';

  @override
  String get recoveryHidden => 'Words hidden';

  @override
  String get recoveryHiddenBody => 'Come back to the app to see them.';

  @override
  String get recoveryLeaveTitle => 'Leave without saving the words?';

  @override
  String get recoveryLeaveBody =>
      'They will not be shown again. If you leave, you will have to change the code to see new ones.';

  @override
  String get recoveryLeaveConfirm => 'Leave';

  @override
  String get recoveryLeaveStay => 'Stay here';

  @override
  String get recoveryCheckTitle => 'Check that you saved them';

  @override
  String recoveryCheckBody(int a, int b, int c) {
    return 'Type words $a, $b and $c.';
  }

  @override
  String recoveryCheckField(int number) {
    return 'Word $number';
  }

  @override
  String get recoveryCheckWrong => 'A word does not match. Have another look.';

  @override
  String get recoveryCheckBack => 'Show the words again';

  @override
  String get recoveryCheckButton => 'Check';

  @override
  String get recoveryDonePreparedTitle => 'Code ready';

  @override
  String get recoveryDonePreparedBody =>
      'If you lose this phone, you can get the list back with your recovery code.';

  @override
  String get recoveryDonePendingBody =>
      'It is not ready yet: the encrypted copy is still being saved. It needs a connection and finishes by itself.';

  @override
  String get recoveryDoneButton => 'Done';

  @override
  String get recoveryCloseLater => 'Close and carry on later';

  @override
  String get recoveryProblemOfflineTitle => 'No connection';

  @override
  String get recoveryProblemOfflineBody =>
      'The server could not be reached. Check your connection and try again; what was done so far is kept.';

  @override
  String get recoveryProblemWrongTitle => 'That code does not open any list';

  @override
  String get recoveryProblemWrongBody =>
      'Check the words or try another code. If it was changed, use the latest one.';

  @override
  String get recoveryProblemRetiredTitle => 'That code no longer works';

  @override
  String get recoveryProblemRetiredBody =>
      'It was changed or removed from another phone. Look for the latest code.';

  @override
  String get recoveryProblemRemovedTitle =>
      'This phone is no longer in the family';

  @override
  String get recoveryProblemRemovedBody =>
      'This phone was removed from the list, so it cannot be recovered with this code.';

  @override
  String get recoveryProblemIncompleteTitle => 'The recovery stopped halfway';

  @override
  String get recoveryProblemIncompleteBody =>
      'Part of the list is missing. The downloaded data is kept. Try again with an internet connection or, if you have another phone connected to this family, briefly open the app on it.';

  @override
  String get recoveryProblemBusyTitle => 'Something else is in progress';

  @override
  String get recoveryProblemBusyBody => 'Wait a moment and try again.';

  @override
  String get recoveryProblemUnsupportedTitle => 'This copy cannot be opened';

  @override
  String get recoveryProblemUnsupportedBody =>
      'The app may need an update, or the copy may be damaged.';

  @override
  String get recoveryProblemUnavailableTitle => 'Not available now';

  @override
  String get recoveryProblemUnavailableBody =>
      'Recovery is not available on this phone.';

  @override
  String get recoveryProblemOtherTitle => 'Something went wrong';

  @override
  String get recoveryProblemOtherBody =>
      'It could not be finished. Try again; if it stays the same, try later.';

  @override
  String get obHaveRecoveryCode => 'I have a recovery code';

  @override
  String get recoverTitle => 'Get the list back';

  @override
  String get recoverBody =>
      'Enter the 24 words in order or scan the recovery QR code.';

  @override
  String recoverWordField(int number) {
    return 'Word $number';
  }

  @override
  String recoverFilled(int count) {
    return '$count of 24 words';
  }

  @override
  String get recoverPaste => 'Paste the 24 words';

  @override
  String get recoverScan => 'Scan the QR code';

  @override
  String get recoverSubmit => 'Get the list back';

  @override
  String recoverWordUnknown(int number) {
    return 'Word $number is not on the list.';
  }

  @override
  String get recoverChecksum =>
      'The words do not make a valid code. Check the order and that none is missing.';

  @override
  String get recoverPasteEmpty => 'Nothing is copied.';

  @override
  String get recoverPasteWrong => 'What is copied does not have 24 words.';

  @override
  String get recoverQrWrong => 'That QR is not a recovery code.';

  @override
  String get recoverScanTitle => 'Scan the recovery QR code';

  @override
  String get recoverScanBody => 'Point the camera at the recovery QR code.';

  @override
  String get recoverProgressTitle => 'Getting the list back';

  @override
  String get recoverProgressBody =>
      'Do not close the app. It can take a minute.';

  @override
  String get recoverStepFind => 'Looking for the copy';

  @override
  String get recoverStepCheck => 'Checking the code';

  @override
  String get recoverStepDownload => 'Downloading the list';

  @override
  String get recoverStepInstall => 'Setting up this phone';

  @override
  String get recoverDoneTitle => 'List recovered';

  @override
  String recoverDoneSelf(String name) {
    return 'This phone is $name\'s.';
  }

  @override
  String get recoverDoneNoSelf =>
      'This phone has no person assigned. You can choose one in Settings.';

  @override
  String recoverDonePeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return 'Your list has $_temp0.';
  }

  @override
  String get recoverEnter => 'Open the list';

  @override
  String get recoverOtherCode => 'Enter another code';

  @override
  String get transferredTitle => 'This list has moved to another phone';

  @override
  String get transferredBody =>
      'Your list is now on another phone or in another app, and this app is no longer used for it. What you see here is a read-only copy: nothing has been deleted.';

  @override
  String get transferredReadOnly => 'Read only';

  @override
  String get recoveryProblemFamilyTitle =>
      'This code belongs to another family';

  @override
  String get recoveryProblemFamilyBody =>
      'It would replace the list on this phone. If that is not what you want, cancel the recovery.';

  @override
  String get recoveryProblemNotReadyTitle => 'The copy is not ready yet';

  @override
  String get recoveryProblemNotReadyBody =>
      'The encrypted copy could not be saved on the server, so the words are not shown. Try again with a connection.';

  @override
  String get recoverReplaceTitle => 'Replace the list on this phone?';

  @override
  String get recoverReplaceBody =>
      'This code belongs to another family. If you continue, that family\'s list will replace the list on this phone. The previous list is kept on the phone, but it stops being shown.';

  @override
  String get recoverReplaceConfirm => 'Replace';

  @override
  String get recoverAbandon => 'Cancel the recovery';

  @override
  String get recoverAbandonTitle => 'Cancel the recovery?';

  @override
  String get recoverAbandonBody =>
      'Temporary data from this recovery will be discarded on this phone. Cancelling will not reactivate the previous phone if it has already become read-only. You can enter the code again.';

  @override
  String get recoverAbandonConfirm => 'Cancel recovery';

  @override
  String get recoverAbandonKeep => 'Keep going';

  @override
  String get recoverAbandonFailed =>
      'It could not be cancelled. Try again in a moment.';

  @override
  String get recoverAbandonBodyClaimed =>
      'The list has already moved to this code and the other phone has become read-only; cancelling does not undo that. To use it you will have to enter the code again.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'This phone cannot block screenshots: do not take any.';

  @override
  String get recoverLeaveTitle => 'Leave the recovery?';

  @override
  String get recoverLeaveBody =>
      'It stays half done on this phone. You can resume or cancel it from the welcome screen.';

  @override
  String get recoverPendingTitle => 'A recovery is in progress';

  @override
  String get recoverPendingBody =>
      'It was left half done on this phone. Resume or cancel it before creating a family or joining another.';

  @override
  String get recoverResume => 'Resume';

  @override
  String get recoveryProblemPendingTitle => 'A recovery is half done';

  @override
  String get recoveryProblemPendingBody =>
      'Resume or cancel it before creating a family or joining another.';

  @override
  String get recoveryMaintCancel => 'Cancel the preparation';

  @override
  String get recoveryMaintCancelTitle => 'Cancel the code preparation?';

  @override
  String get recoveryMaintCancelBody =>
      'The code you already have keeps working. What was being prepared is dropped.';

  @override
  String get recoveryMaintCancelConfirm => 'Cancel preparation';

  @override
  String get recoveryRemoveAuthMessage => 'Enter your PIN to remove the code.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirm you want to remove the recovery code';

  @override
  String get transferredRecover => 'Recover with my code';

  @override
  String get transferredErase => 'Erase everything on this phone';

  @override
  String get recoverStepDoneValue => 'done';

  @override
  String get recoverStepActiveValue => 'in progress';

  @override
  String get recoveryFileAction => 'Save to a file';

  @override
  String get recoveryFileTitle => 'Save to a file';

  @override
  String get recoveryFileBody =>
      'As well as the words, you can save the code in a file. Whoever has the file can get the list back and sign in as this phone.';

  @override
  String get recoveryFilePersonal =>
      'This file is personal: do not send it to the family. Keep it somewhere you can open even if you lose this phone.';

  @override
  String get recoveryFileProtect => 'Protect with a password';

  @override
  String get recoveryFileProtectOffHint =>
      'Without a password the file is as good as the words: whoever gets it can use it.';

  @override
  String get recoveryFileProtectOnHint =>
      'Stealing the file is not enough: the password is needed too.';

  @override
  String get recoveryFilePassword => 'Password';

  @override
  String get recoveryFilePasswordRepeat => 'Repeat the password';

  @override
  String get recoveryFilePasswordShow => 'Show';

  @override
  String get recoveryFilePasswordHide => 'Hide';

  @override
  String recoveryFilePasswordHelp(int min) {
    return 'At least $min characters. Use your password manager or several words chosen at random.';
  }

  @override
  String get recoveryFilePasswordForgot =>
      'If you forget the password, the file is useless. The 24 words will still work.';

  @override
  String recoveryFilePwTooShort(int min) {
    return 'Too short: at least $min characters.';
  }

  @override
  String recoveryFilePwTooLong(int max) {
    return 'Too long: at most $max characters.';
  }

  @override
  String get recoveryFilePwRepeated =>
      'It repeats the same character or block.';

  @override
  String get recoveryFilePwDigits => 'It cannot be only digits.';

  @override
  String get recoveryFilePwKeyboard =>
      'It looks like a row or sequence of keys.';

  @override
  String get recoveryFilePwAppName => 'It cannot contain the name of the app.';

  @override
  String get recoveryFilePwCommon => 'It is too common a phrase.';

  @override
  String get recoveryFilePwMismatch => 'The two passwords do not match.';

  @override
  String get recoveryFileSave => 'Save';

  @override
  String get recoveryFileSaveAgain => 'Save another copy';

  @override
  String get recoveryFileShare => 'Share';

  @override
  String get recoveryFileShareText =>
      'Gift Huddle recovery file. It is personal: do not forward it to the family.';

  @override
  String get recoveryFileStem => 'gift-huddle-recovery';

  @override
  String get recoveryFileDerivingTitle => 'Protecting the file…';

  @override
  String get recoveryFileDerivingBody =>
      'The password key is being prepared. It takes a few seconds; do not close the app.';

  @override
  String get recoveryFileSavedTitle => 'File saved';

  @override
  String get recoveryFileSavedBody =>
      'It was read back from where you saved it and the code is checked. You can save another copy.';

  @override
  String get recoveryFileProblemVerifyTitle =>
      'The saved file could not be checked';

  @override
  String get recoveryFileProblemVerifyBody =>
      'What was read back does not match. Save it again, maybe somewhere else.';

  @override
  String get recoveryFileProblemUnreadableTitle => 'The file could not be read';

  @override
  String get recoveryFileProblemUnreadableBody =>
      'Check that the file is available on this phone and try again.';

  @override
  String get recoveryFileProblemUnavailableTitle =>
      'This phone cannot open the file picker';

  @override
  String get recoveryFileProblemUnavailableBody =>
      'Try Share or use the 24 words.';

  @override
  String get recoveryFileProblemPickerBusyTitle => 'A picker is already open';

  @override
  String get recoveryFileProblemPickerBusyBody => 'Close it and try again.';

  @override
  String get recoveryFileProblemNotFileTitle => 'This is not a recovery file';

  @override
  String get recoveryFileProblemNotFileBody =>
      'Choose the file you saved when you created the code. It ends in .gifthuddle.';

  @override
  String get recoveryFileProblemNewerTitle => 'File from a newer version';

  @override
  String get recoveryFileProblemNewerBody => 'Update the app and try again.';

  @override
  String get recoveryFileProblemPasswordTitle =>
      'Wrong password or damaged file';

  @override
  String get recoveryFileProblemPasswordBody =>
      'Check the password. If you cannot remember it, use the 24 words.';

  @override
  String get recoveryFileProblemNotCurrentTitle =>
      'This file is for a different code';

  @override
  String get recoveryFileProblemNotCurrentBody =>
      'It was saved with an earlier code and no longer works. Look for a newer one or change the code.';

  @override
  String get recoveryFileProblemHasFamilyTitle =>
      'This phone already has a list';

  @override
  String get recoveryFileProblemHasFamilyBody =>
      'A recovery file is for an empty phone. It was not used.';

  @override
  String get recoveryCheckFileAction => 'Check a file';

  @override
  String get recoveryCheckFileTitle => 'Check a file';

  @override
  String get recoveryCheckFileBody =>
      'Choose the recovery file you saved. If it opens this phone\'s code, the code is checked. Nothing is saved or sent.';

  @override
  String get recoveryFilePick => 'Choose file';

  @override
  String get recoveryFilePasswordTitle => 'File password';

  @override
  String get recoveryFilePasswordOpenBody =>
      'This file is protected. Type the password you set when you saved it.';

  @override
  String get recoveryFileOpen => 'Open the file';

  @override
  String get recoveryFileCheckingTitle => 'Checking the file…';

  @override
  String get recoveryFileCheckingBody => 'One moment.';

  @override
  String get recoveryCheckFileOkTitle => 'Code checked';

  @override
  String get recoveryCheckFileOkBody =>
      'The file opens this phone\'s code. If you lose the phone, you can get the list back with it.';

  @override
  String get obRecoverWithFile => 'Recover with a file';

  @override
  String get recoverFileTitle => 'Recover with a file';

  @override
  String get recoverFileBody =>
      'Choose the recovery file you saved when you created the code. It ends in .gifthuddle.';

  @override
  String get recoverFileReceived => 'You opened a recovery file.';

  @override
  String get recoverFileConfirmTitle => 'Recover with this file?';

  @override
  String get recoverFileConfirmBody =>
      'This phone will get the list back and sign in as the phone that saved the code. If it is not your file, do not continue.';

  @override
  String get recoverFileOther => 'Choose another file';

  @override
  String get recoverFileWaitingTitle => 'Another file arrived';

  @override
  String get recoverFileWaitingBody =>
      'You were using another recovery file. Switch to this one?';

  @override
  String get recoverFileWaitingSwitch => 'Switch file';

  @override
  String get recoverFileWaitingKeep => 'Keep the current one';

  @override
  String get recoveryProblemPersonTitle =>
      'This code is no longer your current person\'s';

  @override
  String get recoveryProblemPersonBody =>
      'This phone\'s person changed or a change is pending. Create a new code and keep that one.';

  @override
  String get recoveryFileProblemStorageTitle =>
      'Could not read this phone\'s list';

  @override
  String get recoveryFileProblemStorageBody =>
      'The file is still waiting. Try again: before recovering, the app has to check that this phone does not already have a list.';

  @override
  String get cameraRestricted =>
      'The camera is restricted on this device (for example by Screen Time). You can allow it in Settings > Screen Time > Content & Privacy Restrictions.';

  @override
  String get obJoinFamily => 'Join a family';

  @override
  String get obJoinFamilyHint =>
      'Choose how to connect with the phone that already has the list.';

  @override
  String get obJoinQrHint => 'It is with you: scan its code.';

  @override
  String get obJoinLinkHint => 'It is far away: paste the link they sent you.';

  @override
  String get obRestoreBackup => 'Restore a backup';

  @override
  String get obRestoreBackupHint => 'Choose what you recover the list with.';

  @override
  String get obRestoreCodeHint => 'Type the 24 words you saved.';

  @override
  String get obRestoreFileHint => 'Open the recovery file you saved.';

  @override
  String get giverPeopleSection => 'People';

  @override
  String get giverPeopleHintAdd => 'Added as a giver first';

  @override
  String get giverPeopleHintRecover => 'Restored as a giver';

  @override
  String giverPersonAddTitle(String name) {
    return 'Add $name as a giver?';
  }

  @override
  String giverPersonAddBody(String name) {
    return 'This gift is a surprise. To avoid giving it away, $name first has to be added as a giver for the whole family, shown on every phone with no link to this gift. Then you can pick $name here.';
  }

  @override
  String giverPersonAddConfirm(String name) {
    return 'Add $name as a giver';
  }

  @override
  String giverPersonAddFailed(String name) {
    return 'Couldn\'t add $name as a giver.';
  }

  @override
  String get giftNoLongerVisible =>
      'This gift can no longer be seen on this phone.';

  @override
  String deleteGiverRows(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'These $count records will be deleted: $names.',
      one: '$names will be deleted.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverGiftTitles(String titles, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: 'Affects: $titles and $more more.',
      zero: 'Affects: $titles.',
    );
    return '$_temp0';
  }

  @override
  String deleteGiverLinkedNote(String name) {
    return '$name stays in People: only the giver is deleted.';
  }

  @override
  String get deleteImpactChanged =>
      'This changed while the notice was open. This is what would be deleted now:';

  @override
  String get deletePersonLinkedGiver =>
      'Their name will stay on the gifts they gave, as the giver.';

  @override
  String devicePersonBlockedThisTitle(String name) {
    return 'This phone belongs to $name';
  }

  @override
  String devicePersonBlockedThisBody(String name) {
    return '$name is the person of this phone, so they can\'t be deleted or archived from here. To do it, first choose someone else in \"This phone belongs to\" in Settings.';
  }

  @override
  String devicePersonBlockedOtherTitle(String name) {
    return '$name has their own phone';
  }

  @override
  String devicePersonBlockedOtherBody(String name) {
    return '$name has their own phone in the family, so they can\'t be deleted or archived from here.';
  }

  @override
  String get giverLinkedLine =>
      'Linked to a person: change their name and colour in People.';

  @override
  String giverLinkedNameHint(String name) {
    return 'The name and colour are $name\'s. Change them in People.';
  }

  @override
  String get giverLinkLabel => 'Link to a person';

  @override
  String get giverLinkHint => 'Its name and colour will become the person\'s.';

  @override
  String get giverLinkExistingHint =>
      'Already a giver: they merge into one column';

  @override
  String giverLinkConfirmTitle(String name) {
    return 'Link to $name?';
  }

  @override
  String giverLinkConfirmBody(String giver, String name) {
    return '\"$giver\" will be renamed $name, with their colour, and will follow $name\'s changes in People. Its gifts stay as they are.';
  }

  @override
  String get giverLinkConfirm => 'Link';

  @override
  String get giverUnlinkLabel => 'Unlink from the person';

  @override
  String giverUnlinkConfirmTitle(String name) {
    return 'Unlink from $name?';
  }

  @override
  String giverUnlinkConfirmBody(String name) {
    return 'It will stay as a giver with its current name and colour, but will no longer change with $name. Its gifts stay as they are.';
  }

  @override
  String get giverUnlinkConfirm => 'Unlink';

  @override
  String get giverLinkError => 'Couldn\'t change the link. Try again.';

  @override
  String get giftWriteGiftUnavailable =>
      'Not saved: this gift is no longer available on this phone.';

  @override
  String get giftWriteRecipientGone =>
      'Not saved: the person this gift is for no longer exists.';

  @override
  String get giftWriteInvalidPair =>
      'Not saved: the giver can\'t be the person receiving the gift.';

  @override
  String get giftWriteGiverGone => 'Not saved: that giver no longer exists.';

  @override
  String get giftWriteGiverArchived => 'Not saved: that giver is archived.';

  @override
  String get giftWritePersonGone => 'Not saved: that person no longer exists.';

  @override
  String get giftWritePersonArchived => 'Not saved: that person is archived.';

  @override
  String giverUnlinkStale(String name) {
    return 'It was no longer linked to $name.';
  }

  @override
  String get deleteImpactUnavailable =>
      'Couldn\'t check what would be deleted. Open the notice again.';

  @override
  String get deleteImpactChecking => 'Checking what will be deleted…';
}

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
  String get emptyFamilyTitle => 'Add people first';

  @override
  String get emptyFamilyMessage =>
      'To see who gives what, you need someone to give gifts and someone to receive them.';

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
      'The list colour and header change to match the occasion.';

  @override
  String get appearanceHapticsTitle => 'Vibrations';

  @override
  String get appearanceHapticsHint =>
      'Turn this setting off to disable all app vibrations, including those you feel when you tick a box, delete a gift or enter the wrong PIN.';

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
  String get previewGiftName => 'Fire station building set';

  @override
  String get previewGiver => 'Us';

  @override
  String get previewOccasion => 'Three Kings\' Day';

  @override
  String get shareEnvelopeText =>
      'Open the file in Gift Huddle to see the changes to the list.';

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
      'This file is from another family. Connect the phones with the QR code.';

  @override
  String get shareErrorAuth =>
      'This file cannot be opened. It may be damaged or from another family.';

  @override
  String get shareErrorTooLarge => 'This file is too large.';

  @override
  String get shareErrorNoFamily =>
      'First create your family or join one with the QR code.';

  @override
  String get shareErrorClockDrift =>
      'The clock on the other phone is ahead. Check the date and time on that phone, then send the list from it again.';

  @override
  String get shareErrorLegacyFile =>
      'This file is from an older version of Gift Huddle. Keep it and ask the sender to create a new file with the updated app and send it to you.';

  @override
  String get shareErrorNotReady =>
      'This phone is not yet up to date with the family. Sync and try again.';

  @override
  String get shareErrorGeneration =>
      'This file is from an older version of the list. Ask for a new one.';

  @override
  String get shareErrorRevokedWriter =>
      'This file was saved by a phone that is no longer in the family. Nothing was added.';

  @override
  String get shareErrorMissingKey =>
      'This file cannot be opened yet. It has been saved and the app will try again when you sync.';

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
  String lockBiometricNamed(String name) {
    return 'Use $name';
  }

  @override
  String lockBiometricHintNamed(String name) {
    return 'Tap the $name button to unlock the app';
  }

  @override
  String get lockBiometricNoticeFace =>
      'Anyone whose face is registered with Face ID can open the app.';

  @override
  String get lockBiometricNoticeTouch =>
      'Anyone with a fingerprint registered with Touch ID can open the app.';

  @override
  String pinBiometricOfferTitleNamed(String name) {
    return 'Turn on $name?';
  }

  @override
  String get securityBiometricsUnavailableIos =>
      'Neither Face ID nor Touch ID is set up on this phone.';

  @override
  String securityBiometricsFailedNamed(String name) {
    return 'Could not turn it on. Check that $name is set up in the phone\'s Settings.';
  }

  @override
  String get giftDiscardTitle => 'Discard changes?';

  @override
  String get giftDiscardBody => 'You have unsaved changes to this gift.';

  @override
  String get wishDiscardBody => 'You have unsaved changes to this wish.';

  @override
  String get giftMoreDetails => 'More details';

  @override
  String get giftFieldActualPrice => 'Actual price';

  @override
  String get actionDiscard => 'Discard';

  @override
  String get giftKeepEditing => 'Keep editing';

  @override
  String get lockLoadError => 'The lock could not be checked.';

  @override
  String get lockRetry => 'Try again';

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
  String get pinConfirmTitle => 'Re-enter your PIN';

  @override
  String get pinMismatch => 'The PINs do not match. Try again.';

  @override
  String get pinContinue => 'Continue';

  @override
  String get pinSave => 'Save PIN';

  @override
  String get pinSkip => 'Not now';

  @override
  String get pinBiometricOfferTitle => 'Turn on fingerprint or face unlock?';

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
  String get fieldGiver => 'Giver';

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
  String get giverHouseholdPays => 'Counts as household spending';

  @override
  String get giverHouseholdPaysHint => 'Their gifts add to household spending.';

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
      'Keep track of who gives what to whom. That way, nobody gets the same gift twice and nobody is left out.';

  @override
  String get obWelcomePrivacy =>
      'No accounts. When you sync two phones, your list is encrypted so only your phones can read it.';

  @override
  String get obDeviceNameLabel => 'Name of this phone';

  @override
  String get obDeviceNameHint =>
      'This name will appear on the other phone. You can change it.';

  @override
  String get obStart => 'Get started';

  @override
  String get obHaveListTitle => 'Already have a list?';

  @override
  String get obPeopleTitle => 'Who do you give gifts to?';

  @override
  String get obPeopleBody =>
      'Add the people you give gifts to: partner, siblings, nieces and nephews, kids… You need at least one.';

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
      '\"Us\" is already on the list for gifts that count as household spending. You can also add grandparents, aunts and uncles.';

  @override
  String get obGiversSuggestions => 'Suggestions';

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
  String get giverNameHint => 'Grandparents, Aunt Nora and Leo…';

  @override
  String get obOccasionsTitle => 'When do you give gifts?';

  @override
  String get obOccasionsBody =>
      'Choose when you give gifts. Birthdays appear automatically for anyone whose date of birth you entered.';

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
  String get obPinTitle => 'Lock the app';

  @override
  String get obPinBody =>
      'Create a PIN so nobody can see the gifts if they pick up the phone. You can change it in Settings.';

  @override
  String get obPinCreate => 'Create a PIN';

  @override
  String get obFinishing => 'Setting up your list…';

  @override
  String get obSaveError => 'Could not save. Try again.';

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
  String get budgetHouseTotal => 'Household spending · total';

  @override
  String get budgetBought => 'Bought';

  @override
  String budgetBoughtBarLabel(String bought, String total) {
    return 'Bought: $bought of $total';
  }

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
      'First, add the person who will receive the gift.';

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
  String get giftFieldTitleRequired => 'Enter a name for the gift.';

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
  String get giftLinkCopied => 'Could not open the browser. Link copied.';

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
  String get giftRequestedByName => 'Their name';

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
    return 'Delete \"$name\"?';
  }

  @override
  String get confirmDeleteBody =>
      'This will also delete the gift from your family\'s other phones.';

  @override
  String personCompletionProgress(String occasion, int done, int total) {
    return '$occasion · $done of $total bought';
  }

  @override
  String personCompletionDone(String occasion) {
    return 'Everything bought for $occasion';
  }

  @override
  String get giftSaveError => 'Could not save the gift. Try again.';

  @override
  String get giftDuplicateTitle => 'Possible duplicate';

  @override
  String giftDuplicateBody(String title, String person, String giver) {
    return 'This gift may already be on the list for $person as \"$title\". Giver: $giver.';
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
    return 'Possible duplicate: \"$title\" for $person';
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
  String get occasionPeopleSection => 'By person';

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
    return 'Gifts for $name by occasion: $parts';
  }

  @override
  String get occasionPendingBuySection => 'Still to buy';

  @override
  String get occasionPendingEmpty =>
      'Nothing to buy right now. Gifts marked \"Decided\" appear here, grouped by store.';

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
      'You can set a budget for each occasion. \"Spent\" adds up the actual prices of gifts that count as household spending. If a gift has been bought and its actual price is missing, its planned price counts.';

  @override
  String get budgetSubtitleBudgeted =>
      'You set the budget for each occasion. The three figures only include occasions with a budget. \"Spent\" adds up actual prices for gifts that count as household spending. If a purchased gift has no actual price recorded, its planned price counts.';

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
      'The budget only includes gifts that count as household spending. Gifts paid for by someone else, such as a grandparent, are left out.';

  @override
  String get budgetEmpty =>
      'No gifts count towards the household budget yet. Turn on \"Counts as household spending\" for a giver and add a planned price to the gift.';

  @override
  String get occasionBudgetField => 'Budget (optional)';

  @override
  String get occasionBudgetHint =>
      'What you want to spend on this occasion. Leave it empty if there is no budget.';

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
    return 'If you buy the remaining gifts, you will have $amount left';
  }

  @override
  String budgetSpentOutside(String amount) {
    return 'The household spent another $amount outside budgeted occasions.';
  }

  @override
  String budgetOverIfBought(String amount) {
    return 'If you buy the remaining gifts, you will go over by $amount';
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
  String get settingsGivers => 'Givers';

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
      'No accounts or ads. Your list only leaves your phone if you connect another phone or the web, create a recovery code or send a copy. It is always encrypted when it leaves your phone.';

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
      'Could not turn it on. Check that fingerprint or face is set up on the phone.';

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
  String get scannerDeniedTitle => 'Camera access needed';

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
      'If you join the other phone\'s list, you will lose the list on this phone and all the gifts in it.';

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
      other: '$count gifts updated',
      one: '$count gift updated',
    );
    return '$_temp0';
  }

  @override
  String importDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gifts deleted',
      one: '$count gift deleted',
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
      'This phone will stop sending and receiving changes. The other phones will keep syncing with each other. If no other phone or web app has access to the list, the app will delete the encrypted sync copy. Each phone will keep its data. To sync again, reconnect this phone to another phone in the family.';

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
  String get syncStatusWaitingPeer =>
      'Sync starts when you connect another phone.';

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
  String get syncStatusOffline =>
      'Can\'t connect right now. Changes will be sent later.';

  @override
  String get syncStatusError => 'Could not sync';

  @override
  String get syncIssueAuth => 'The server does not accept this family\'s key.';

  @override
  String get syncIssueClockDrift =>
      'The clock on another phone is ahead. Check the date and time on that phone.';

  @override
  String get syncIssueTooLarge => 'The list is too large to sync.';

  @override
  String get syncIssueServer =>
      'The server is not responding properly. The app will try again.';

  @override
  String get syncIssueRateLimited =>
      'Too many sync attempts. The app will try again in a moment.';

  @override
  String get syncIssueUnreadable =>
      'The data on the server cannot be opened with this family\'s key.';

  @override
  String get syncIssueUnknown =>
      'Something went wrong. The app will try again.';

  @override
  String get inviteRowTitle => 'Invite someone';

  @override
  String get joinInviteRowTitle => 'Join with a link';

  @override
  String get inviteIntro =>
      'Create a link so another person can join your family from their own phone, without being with you.';

  @override
  String get inviteHowItWorks =>
      'The link contains no key. It works for one person and expires after 24 hours. When they ask to join, you will receive their request with a 6-digit code. You decide whether to give them access.';

  @override
  String get inviteCreate => 'Create link and invite';

  @override
  String get inviteNeedSync =>
      'To invite someone remotely, you need an internet connection and sync must be on.';

  @override
  String get inviteGoToSync => 'Turn sync on';

  @override
  String inviteShareText(String link) {
    return 'I am inviting you to my Gift Huddle list. Open the link and ask to join: $link';
  }

  @override
  String get inviteWaitingTitle => 'Waiting for a request';

  @override
  String get inviteWaitingBody =>
      'When the other person asks to join, you will see their request here. You can leave this screen. The invitation will stay active until it expires.';

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
      'The invitation has been cancelled. The link no longer works.';

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
  String get joinInviteUnknown => 'Could not finish connecting. Try again.';

  @override
  String get joinInviteTaken =>
      'Someone else has already asked to join using this link. Ask for a new link.';

  @override
  String get joinInviteGone =>
      'The invitation has expired or was not accepted.';

  @override
  String get joinInviteWaitingTitle => 'Waiting to be accepted';

  @override
  String get joinInviteWaitingBody =>
      'The person who invited you has to see your request. When their phone responds, you will see a code here to compare. This phone waits up to 10 minutes for confirmation.';

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
    return 'No gifts from $giver for $person yet';
  }

  @override
  String repartoSheetUnassignedHint(String person) {
    return 'Some gifts for $person are unassigned. Tap \"Unassigned\" on a gift to choose who gives it.';
  }

  @override
  String get repartoSheetStartHint => 'Add a new gift to start.';

  @override
  String repartoSheetSummary(String gifts, String price) {
    return '$gifts · $price · tap a name to change the giver';
  }

  @override
  String get repartoSheetWho => 'Unassigned';

  @override
  String get repartoSheetNobody => 'Nobody';

  @override
  String get repartoSheetAddGift => 'Add gift';

  @override
  String repartoSheetNewGiftFrom(String giver) {
    return 'Add gift from $giver';
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
  String get lockBiometricHint => 'Tap the fingerprint button to unlock';

  @override
  String get repartoViewLabel => 'Who gives what view';

  @override
  String get repartoViewGrid => 'Grid';

  @override
  String get repartoViewOccasion => 'By occasion';

  @override
  String get repartoOccasionPackets => 'Gifts per person';

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
      'Add a gift for this occasion to see who is bringing it and how many gifts each person will open.';

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
    return 'Not receiving gifts for $occasion';
  }

  @override
  String familySkipsLabel(String occasions) {
    return 'Without $occasions';
  }

  @override
  String get familyLegendExcluded => 'Not receiving gifts';

  @override
  String repartoOccasionNotGiving(String occasion) {
    return 'Not receiving gifts for $occasion';
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
      'This person has another device connected to the family.';

  @override
  String deletePersonTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String deleteOccasionTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String deletePersonGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count gifts for this person will also be deleted.',
      one: 'The gift for this person will also be deleted.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String deletePersonWishes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wishes for this person will also be deleted.',
      one: '1 wish for this person will also be deleted.',
    );
    return '$_temp0';
  }

  @override
  String get deleteBirthdayToo =>
      'Their birthday will also be removed from the list of occasions.';

  @override
  String deleteGiverGifts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Their $count gifts will stay on the list without an assigned giver.',
      one: 'Their gift will stay on the list without an assigned giver.',
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
      'Their name will be removed from the gifts they requested for others.';

  @override
  String get deleteGiverBudget =>
      'Their amounts stop counting in the household budget.';

  @override
  String get deleteError => 'Could not delete. Try again.';

  @override
  String get deleteDevicesNeedUpdate =>
      'To delete this, every phone in the family needs the latest version.';

  @override
  String get giftNotSaved =>
      'Not saved: this gift is no longer available on this phone.';

  @override
  String giftDeletedNotice(String name) {
    return '\"$name\" deleted';
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
      'First, this phone leaves the family\'s sync. If no other phone or web app is connected, the encrypted sync copy is deleted too.';

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
      'Check your connection and try again. If you delete the data on this phone only, the phone will stay in \"Family phones\" until someone removes it from another phone. Other phones and the web app can keep using the encrypted sync copy if they still have access. If no one accesses it again, it will expire.';

  @override
  String get eraseAllRetry => 'Try again';

  @override
  String get eraseAllLocalOnly => 'Delete on this phone only';

  @override
  String get eraseAllFailed => 'Not everything could be deleted. Try again.';

  @override
  String get eraseAllPinPrompt => 'Enter your PIN to continue.';

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
  String get syncShortOffline => 'not connected';

  @override
  String get syncShortError => 'error';

  @override
  String get syncShortOff => 'off';

  @override
  String get archiveSubtitle =>
      'Anything you archive comes off the lists but keeps its gifts.';

  @override
  String get archiveEmpty => 'Nothing is archived.';

  @override
  String get archiveNote => 'Archiving deletes nothing. Deleting is permanent.';

  @override
  String get devicesSoloTitle => 'Only on this phone';

  @override
  String get devicesSoloBody =>
      'Connect another one to see the same list on both.';

  @override
  String get devicesPendingTitle => 'Connecting another phone';

  @override
  String get devicesPendingBody =>
      'Waiting for the other phone to finish connecting.';

  @override
  String get connectWebPasteCode => 'Paste the QR code';

  @override
  String get personPickerThisPhone => 'This phone';

  @override
  String get devicesRecoveryTitle => 'Recovery copy saved';

  @override
  String get devicesRecoveryBody =>
      'You can use your code to recover the list from the encrypted sync copy. Connect another phone to see the list on both.';

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
  String get devicesOfflineTitle => 'Can\'t connect';

  @override
  String get devicesOfflineBody => 'Your changes will be sent later.';

  @override
  String get syncBlockedHint =>
      'If you are online, your provider may be blocking the service. Try mobile data or another Wi-Fi network.';

  @override
  String get devicesConnected => 'Connected';

  @override
  String get devicesThisPhone => 'This phone';

  @override
  String get devicesOtherPhone => 'Another phone';

  @override
  String get devicesPeerHint => 'Connected to this family';

  @override
  String get devicesPeerNoPerson => 'No person yet: it cannot see surprises';

  @override
  String get devicesListError => 'The list of phones could not be read.';

  @override
  String get devicesConnect => 'Connect another phone';

  @override
  String get devicesConnectQuestion => 'Where is the other phone?';

  @override
  String get devicesHereTitle => 'It is here';

  @override
  String get devicesHereHint =>
      'Scan a QR code with it. It is the quickest way.';

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
  String get devicesJoinOther => 'Join another family';

  @override
  String get devicesJoinOtherHint => 'Replaces the list on this phone.';

  @override
  String get devicesJoinOtherWarning =>
      'If you join another family, their list will replace the one on this phone. You will lose the gifts from your current list on this phone.';

  @override
  String get devicesScanTitle => 'Scan their QR code';

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
      'The copy is merged with the list on this phone. Nothing is lost.';

  @override
  String get backupPasteTitle => 'Paste from the clipboard';

  @override
  String get backupPasteHint => 'If you got it as a link or as text.';

  @override
  String get backupFileNote =>
      'To open a .gifthuddle file, tap it in Files or in the message it came in and choose Gift Huddle.';

  @override
  String get backupNote =>
      'The copy is encrypted with the family key. You can only open it on a phone that is already part of the family.';

  @override
  String get pairingV2Preparing => 'Getting the connection ready…';

  @override
  String get pairingV2NoticeExpires =>
      'The invitation expires after 24 hours and only lets someone ask to join. Before giving access, compare the codes shown on both phones.';

  @override
  String get pairingV2FarTitle => 'Share the link';

  @override
  String get pairingV2FarBody =>
      'Send it to whoever you want to connect. When they open it and ask to join, you will see a code here to compare.';

  @override
  String get pairingV2Share => 'Share the link';

  @override
  String get pairingV2WaitingHere =>
      'Waiting for the other person to ask to join…';

  @override
  String get pairingV2CompareTitle => 'Compare the code';

  @override
  String get pairingV2HostCompareBody =>
      'The other phone shows a code. It has to be the same as this one. If it is, tap \"They match\"; if not, \"They do not match\".';

  @override
  String get pairingV2Match => 'They match';

  @override
  String get pairingV2NoMatch => 'They do not match';

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
      'The invitation was cancelled and no longer works. You can start again.';

  @override
  String get pairingV2HostFailed =>
      'The other phone could not be connected. Try again.';

  @override
  String get pairingV2NotReady =>
      'To continue, you need an internet connection and sync must be on.';

  @override
  String get pairingV2ChooseContinue => 'Continue';

  @override
  String get pairingV2GuestWaitingCode =>
      'When the other phone responds, you will see a code here to compare.';

  @override
  String get pairingV2GuestCompareBody =>
      'Compare this code with the one the other person sees. If they are the same, tap \"They match\".';

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
      'Each phone connects again with \"Connect another phone\" by comparing a code.';

  @override
  String pairingV2ClaimTitle(String name) {
    return 'Is the other phone $name\'s?';
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
      'If you continue, this family switches to the new, safer sync. This cannot be undone. The phones that were already connected stop receiving this phone\'s changes until you connect them again, one by one, with \"Connect another phone\". Nothing is lost.';

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
  String get devicesPeerFrozen => 'Changes on hold: waiting for approval';

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
  String get deviceDetailOwner => 'Belongs to';

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
  String get deviceStatusFrozen => 'Changes on hold';

  @override
  String get deviceStatusReconfirm => 'Owner to be confirmed';

  @override
  String get deviceDetailSelfNote =>
      'This is your phone. To stop syncing it, use \"Stop syncing\" in \"More options\".';

  @override
  String get deviceRemoveTitle => 'Remove this phone';

  @override
  String get deviceRemoveHint => 'It will stop receiving changes to the list.';

  @override
  String get deviceRemoveConfirmTitle => 'Remove this phone?';

  @override
  String get deviceRemoveConfirmBody =>
      'It stops receiving new changes right away. What it already has cannot be erased from it. What only that phone had may be lost. This cannot be undone.';

  @override
  String get deviceRemoveConfirmAction => 'Remove phone';

  @override
  String get deviceRemoveWaitTitle => 'Your phone will wait for approval again';

  @override
  String get deviceRemoveWaitBody =>
      'Only the phone you are removing approved the change of person on your phone. If you remove it, you will not see surprises on your phone until another phone in the family approves the change.';

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
      'The person assigned to this phone has changed. If you approve it, it will be able to approve other phones in the family.';

  @override
  String get deviceApproveOrphan =>
      'You need to confirm again whose it is. If you approve it, it will see the surprises for everyone else again.';

  @override
  String get deviceApproveDetached =>
      'This phone is no longer connected to the family, but it confirmed your phone earlier. Approve it only if you recognise it.';

  @override
  String get deviceApproveFrozen =>
      'Its changes are on hold until you approve it or remove it.';

  @override
  String get deviceApprovedSnack => 'Phone approved';

  @override
  String get deviceApproveError =>
      'The phone could not be approved. Try again.';

  @override
  String get deviceChangedNotice =>
      'The phone\'s details have changed. Check them again.';

  @override
  String get deviceRemovedPendingSnack =>
      'Phone removed. It will lose access as soon as there is a connection.';

  @override
  String get deviceApproveCanVouch =>
      'The person assigned to it has changed: if you approve it, it will be able to approve other phones in the family.';

  @override
  String get webGateConnectTitle => 'Connect this computer';

  @override
  String get webGateConnectIntro =>
      'You only need to do this once, with your phone. After that, you will only need the PIN or passphrase you choose.';

  @override
  String get webGateStepOpenApp => 'Open Gift Huddle on your phone.';

  @override
  String get webGateConnectStep2 =>
      'Go to Settings › Family phones and tap \"Connect the web\".';

  @override
  String get webGateConnectStep3 => 'Scan this code.';

  @override
  String get webGateConnectWaiting => 'Waiting for your phone…';

  @override
  String get webGateCompareTitle => 'Compare the code';

  @override
  String get webGateCompareLabel => 'Verification code';

  @override
  String get webGateCompareBody =>
      'Check that your phone shows the same code, confirm it here and approve it on your phone too.';

  @override
  String get webGateCompareWaiting =>
      'Waiting for you to tap \"They match\" on your phone…';

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
      'The connection was declined on your phone. To connect this computer, start again.';

  @override
  String get webGateFailedNetwork =>
      'Could not reach the server. Check your connection and start again.';

  @override
  String get webGateFailedCancelled =>
      'The phone cancelled the connection or the code no longer works. Start again and scan the new code with your phone.';

  @override
  String get webGateStartAgain => 'Start again';

  @override
  String webGateChoosePinTitle(String name) {
    return 'This computer belongs to $name';
  }

  @override
  String get webGateChoosePinBody =>
      'Choose a PIN or passphrase. You will need it each time you open Gift Huddle on this computer.';

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
      'Enter the PIN or passphrase you chose for Gift Huddle on this computer.';

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
      'To try again, allow it from a phone first. Nothing has been deleted.';

  @override
  String get webGateSuspendedStep2 =>
      'Go to Settings › Family phones and tap \"Web\".';

  @override
  String get webGateSuspendedStep3 => 'Tap \"Allow more PIN attempts\".';

  @override
  String get webGateRetry => 'Try again';

  @override
  String get webGateDisconnectedTitle => 'This computer is no longer connected';

  @override
  String get webGateDisconnectedBody =>
      'Someone used a phone to remove this computer from the family, or the list no longer exists.';

  @override
  String webGateDisconnectedUnsent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes have not been uploaded. They are stored encrypted on this computer.',
      one:
          '$count change has not been uploaded. It is stored encrypted on this computer.',
    );
    return '$_temp0';
  }

  @override
  String get webGateReconnect => 'Connect again';

  @override
  String get webGateErase => 'Delete Gift Huddle data on this computer';

  @override
  String get webGateEraseTitle => 'Delete Gift Huddle data on this computer?';

  @override
  String get webGateEraseBody =>
      'Everything Gift Huddle keeps on this computer will be deleted. This cannot be undone.';

  @override
  String get webGateEraseBodyUnsent =>
      'Everything Gift Huddle keeps on this computer will be deleted, including changes that have not been uploaded. This cannot be undone.';

  @override
  String get webGateDamagedTitle =>
      'The Gift Huddle data on this computer is damaged';

  @override
  String get webGateDamagedBody =>
      'Gift Huddle cannot read it safely. To continue, delete the data and connect this computer again from a phone. You will lose any changes that have not been uploaded.';

  @override
  String get webGateDamagedPhoneHint =>
      'On your phone, go to Settings › Family phones and remove the old web app.';

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
  String get webSettingsPinChanged => 'PIN or passphrase changed.';

  @override
  String get webSettingsLockNow => 'Lock now';

  @override
  String get webSettingsForget => 'Forget this computer';

  @override
  String get webSettingsForgetHint =>
      'Removes this computer from the family and deletes the Gift Huddle data stored on it.';

  @override
  String get webSettingsForgetTitle => 'Forget this computer?';

  @override
  String get webSettingsForgetBody =>
      'This computer will leave the family. Gift Huddle will delete its data on this computer, including changes that have not been uploaded. Nothing changes on your phones. To use Gift Huddle here again, you will have to reconnect this computer.';

  @override
  String get webSettingsForgetConfirm => 'Forget';

  @override
  String get webSettingsPersistenceDenied =>
      'If space runs low, your browser may delete the data Gift Huddle stores here.';

  @override
  String get webRecipientDeleteRejected =>
      'This person could not be deleted from the web because it affects another person\'s secret gifts. Do it from a phone.';

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
      'If the codes did not match, do not continue: select \"Start again\".';

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
          'There have been $count failed attempts since Gift Huddle was last unlocked on this computer. If that was not you, change your PIN.',
      one:
          'There has been $count failed attempt since Gift Huddle was last unlocked on this computer. If that was not you, change your PIN.',
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
  String get connectWebWaiting => 'Waiting for the computer to answer…';

  @override
  String get connectWebCompareBody =>
      'The computer shows a code. It must be the same as this one. If it is, tap \"They match\"; if not, \"They do not match\".';

  @override
  String get connectWebApproving => 'Giving the computer access…';

  @override
  String get connectWebDoneTitle => 'Computer connected';

  @override
  String get connectWebDoneBody =>
      'On the computer, choose a PIN to open Gift Huddle.';

  @override
  String get connectWebNewQr =>
      'This code is no longer valid. On the computer, select \"Start again\". Scan the new code with your phone.';

  @override
  String get connectWebScanAgain => 'Scan another code';

  @override
  String get connectWebFailed =>
      'The computer could not be connected. Select \"Start again\" on the computer. Scan the new code with your phone.';

  @override
  String get connectWebCancel => 'Cancel connection';

  @override
  String get connectWebCancelled =>
      'The connection was cancelled and the code no longer works. On the computer, select \"Start again\".';

  @override
  String get deviceWebResume => 'Allow more PIN attempts';

  @override
  String get deviceWebResumeHint =>
      'If the web app no longer accepts the PIN after too many failed attempts. Nothing is deleted.';

  @override
  String get deviceWebResumeTitle => 'Allow more PIN attempts?';

  @override
  String get deviceWebResumeBody =>
      'This computer will accept PIN attempts again. Do it only if its owner was the one who got it wrong.';

  @override
  String get deviceWebResumeConfirm => 'Allow';

  @override
  String get deviceWebResumeDone => 'Done. The web app accepts the PIN again.';

  @override
  String get deviceWebResumeError =>
      'Could not allow more PIN attempts. Check your connection and try again.';

  @override
  String get deviceRemoveWebTitle => 'Remove this web app';

  @override
  String get deviceRemoveWebHint =>
      'This computer will stop receiving changes to the list.';

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
      'Web app removed. The computer will lose access as soon as there is a connection.';

  @override
  String get deviceRemoveWebError =>
      'The web app could not be removed. Try again when you are online.';

  @override
  String get webSyncSaved => 'Saved';

  @override
  String get webSyncOffline => 'Can\'t connect';

  @override
  String get webSyncAwaitingConfirm => 'Awaiting confirmation from a phone';

  @override
  String get webOperationUnavailable =>
      'This cannot be done from the computer. Do it from a phone.';

  @override
  String get selfChangeConfirmTitle => 'Change who this phone belongs to?';

  @override
  String selfChangeConfirmIntro(String name) {
    return 'You are about to say this phone belongs to $name. This changes which gifts and surprises you can see on it.';
  }

  @override
  String get selfChangeConfirmIntroNobody =>
      'You are about to remove the person assigned to this phone. This changes which gifts and surprises you can see on it.';

  @override
  String selfChangeEffectHides(String name) {
    return 'This phone will stop showing gifts for $name.';
  }

  @override
  String get selfChangeEffectNobody =>
      'This phone will have no person assigned and will not be able to show surprises until someone is assigned to it.';

  @override
  String get selfChangeEffectWait =>
      'You will not see anyone\'s surprises on this phone until the change is approved from another family phone.';

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
      'You have reached the limit for changing who this phone belongs to. To choose someone else, connect it to the family again as a new phone. You will need another family phone with you.';

  @override
  String get selfWaitingHint => 'Waiting for approval from another phone';

  @override
  String get healthRevokedTitle => 'This phone was removed from the family';

  @override
  String get healthRevokedBody =>
      'Your data is still on this phone. To sync again, reconnect it to another phone in the family in person.';

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
      'Nothing has been lost. The surprises will show again once you have chosen who this phone belongs to and another phone in the family has approved it.';

  @override
  String healthNamesAnd(String head, String last) {
    return '$head and $last';
  }

  @override
  String get healthRenewSoon => 'The list should be renewed soon';

  @override
  String get healthResolveSection => 'To resolve';

  @override
  String get healthUnbackedTitle => 'Unidentified access';

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
  String get healthRetry => 'Try again';

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
    return 'With protection on, $name\'s phone shows no gifts for $name, not even how many there are.';
  }

  @override
  String get protectionEffectOthers =>
      'Other family phones with permission can still see and edit them.';

  @override
  String protectionEffectKept(String name) {
    return 'Protection cannot take back gifts that had already reached $name\'s phone.';
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
    return 'Gifts for $name that are available on this phone will no longer be secret. This includes gifts from any year and those still pending on this phone. Once the changes sync, $name will be able to see them on their phone.';
  }

  @override
  String get protectionDeactivateConfirm => 'Turn off';

  @override
  String protectionCannotDeactivate(String name) {
    return 'This phone cannot turn it off right now: it needs permission and the current key for $name.';
  }

  @override
  String get protectionOnlyOthersChange =>
      'Only another person in the family can change this, from their own phone.';

  @override
  String get protectionChangeFailed =>
      'The protection could not be changed. Nothing was modified.';

  @override
  String protectionNeedConfirmer(String name) {
    return 'To protect the gifts for $name, the family needs a phone that belongs to someone else. In Settings, choose whose phone this is under \"This phone belongs to\". Then approve the change from another phone, or connect another phone to the family. If you have already done that, sync.';
  }

  @override
  String protectionNeedConfirmerOwn(String name) {
    return 'Protection for $name\'s gifts cannot be turned on from this phone. Ask someone else in the family to do it from theirs.';
  }

  @override
  String protectionRequesterPending(String name) {
    return 'Someone in the family still has to approve the change to \"This phone belongs to\" from another phone. Until then, you cannot request protection for $name\'s gifts.';
  }

  @override
  String protectionRequesterRevoked(String name) {
    return 'This phone is no longer part of the family, so it cannot request protection for the gifts for $name.';
  }

  @override
  String protectionRequesterAmbiguous(String name) {
    return 'It is not clear whose phone this is, so it cannot request protection for the gifts for $name. Sync and try again.';
  }

  @override
  String protectionRecipientUnavailable(String name) {
    return '$name is no longer on the list. Protection for their gifts cannot be requested.';
  }

  @override
  String get protectionRegistryUnavailable =>
      'This phone is not yet up to date with the family. Sync and try again.';

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
    return 'This phone cannot access the secret gifts for $name. Ask for help from someone in the family whose phone has permission.';
  }

  @override
  String protectionReason_ownRequestsRestricted(String name) {
    return 'This phone belongs to $name. You cannot create or view secret gifts for $name here.';
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
    return 'Shorten the notes so you can save this as a secret gift.';
  }

  @override
  String protectionReason_writerSlotsFull(String name) {
    return 'This phone has reached its limit for secret gifts. Ask someone to add new gifts from another phone that has permission.';
  }

  @override
  String protectionReason_slotsFull(String name) {
    return 'No more secret gifts can be added to the family\'s list right now.';
  }

  @override
  String protectionReason_requiresV2(String name) {
    return 'Secret gifts need this phone to be connected to the family with the new version.';
  }

  @override
  String get giftProtectedRejected => 'The gift was not saved.';

  @override
  String get giftSavedLocally =>
      'Saved on this phone only. The gift isn\'t on the list yet and hasn\'t been shared.';

  @override
  String get giftSavedLocallyAction => 'See pending gifts';

  @override
  String get giftOwnRequestRestricted =>
      'While protection is on, you cannot add or view gifts for yourself on this phone. Ask someone else in the family to add the gift.';

  @override
  String get pendingGiftsTitle => 'Pending gifts';

  @override
  String get pendingGiftsIntro =>
      'These gifts are encrypted and saved only on this phone. They are not on the shared family list yet. If you lose the phone before they are added to the list, you will lose these gifts too.';

  @override
  String get pendingGiftsRetry => 'Try again';

  @override
  String get pendingGiftsRetrying => 'Trying again';

  @override
  String get pendingGiftsStill =>
      'There is still no room. The gifts are still saved only on this phone.';

  @override
  String get pendingGiftsRetryError =>
      'The retry failed. The gifts are still saved on this phone.';

  @override
  String get pendingGiftsDoneTitle => 'All saved';

  @override
  String get pendingGiftsDoneBody => 'No gifts are pending any more.';

  @override
  String pendingGiftsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gifts waiting to be saved',
      one: '$count gift waiting to be saved',
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
    return 'Move to \"$lane\"';
  }

  @override
  String boardLaneAdd(String lane) {
    return 'Add gift to \"$lane\"';
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
  String get boardRepartoDuplicatesNone => 'No duplicates found.';

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
      'Choose who the gift is for, the occasion and the giver. You can start with just an idea.';

  @override
  String get tour2Title => 'Mark it as bought';

  @override
  String get tour2Body =>
      'Tap the checkbox and the gift leaves \"Still to buy\" and moves to \"to arrive\". If you get it wrong, undo it right away.';

  @override
  String get tour3Title => 'People and occasions';

  @override
  String get tour3Body =>
      'Each person\'s list groups gifts by occasion, such as Christmas, Three Kings Day or birthdays. \"Who gives what\" shows who pays for each gift.';

  @override
  String get tour4Title => 'The family shares the list';

  @override
  String get tour4Body =>
      'Connect another phone in person using a QR code. Changes sync automatically, and everything sent between the phones is encrypted.';

  @override
  String get tour5Title => 'Surprises stay safe';

  @override
  String get tour5Body =>
      'Gifts for you do not appear on your phone. You can lock the app with a PIN or biometrics. No accounts or ads.';

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
  String get tourDemoPajamas => 'Pyjamas';

  @override
  String get tourDemoChristmas => 'Christmas';

  @override
  String get tourDemoBirthday => 'Birthday';

  @override
  String get tourDemoConnected => 'Connected';

  @override
  String get tourDemoEncrypted => 'Encrypted';

  @override
  String get tourDemoHidden => 'Secret gifts';

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
      'The code does not count as saved yet. If you saved a file, you can check it. Otherwise, continue with the words: if you have already seen them, continuing will create a new code and the old one will stop working.';

  @override
  String get recoveryValueAttention => 'Check';

  @override
  String get recoveryValueTransferred => 'List moved';

  @override
  String get recoverySubtitle => 'To get the list back on a new phone.';

  @override
  String get recoveryAbsentTitle =>
      'Create a code to recover the list if you lose this phone';

  @override
  String get recoveryAbsentBody =>
      'When you create the code, the app saves an encrypted sync copy even if this is your only phone. You can use the 24 words on another phone to recover the parts of the list you can see that have been synced.';

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
  String get recoveryRemove => 'Delete the code';

  @override
  String get recoveryRemoveHint =>
      'The words will stop working and the copy is deleted.';

  @override
  String get recoveryRemoveTitle => 'Delete the recovery code?';

  @override
  String get recoveryRemoveBody =>
      'The recovery copy is deleted and the 24 words stop working. You can create another code whenever you like.';

  @override
  String get recoveryRemoveSoloNote =>
      'Since no other phone or web app is connected, the encrypted sync copy is also deleted and the list is only on this phone again.';

  @override
  String get recoveryRemoveConfirm => 'Delete code';

  @override
  String get recoveryRemoved => 'Code deleted';

  @override
  String get recoveryRetry => 'Try again';

  @override
  String get recoveryIntroTitle => 'Create the code';

  @override
  String get recoveryRotateTitle => 'Change the code';

  @override
  String get recoveryIntroBody =>
      'You will see 24 words. You can use them to recover the list on another phone, including everything you can see on this one.';

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
      'The app could not reach the server. Your progress is saved. Check your connection and try again.';

  @override
  String get recoveryProblemWrongTitle => 'That code does not open any list';

  @override
  String get recoveryProblemWrongBody =>
      'Check the words or try another code. If it was changed, use the latest one.';

  @override
  String get recoveryProblemRetiredTitle => 'That code no longer works';

  @override
  String get recoveryProblemRetiredBody =>
      'It was changed or deleted from another phone. Look for the latest code.';

  @override
  String get recoveryProblemRemovedTitle =>
      'This phone is no longer in the family';

  @override
  String get recoveryProblemRemovedBody =>
      'This code is from a phone that was removed from the family. It can no longer be used to recover the list.';

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
      'Try again. If the problem continues, try again later.';

  @override
  String get obHaveRecoveryCode => 'Use a recovery code';

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
    return 'Check the spelling of word $number.';
  }

  @override
  String get recoverChecksum =>
      'These words do not form a valid code. Check that the words and their order match your recovery code.';

  @override
  String get recoverPasteEmpty => 'There is no text to paste.';

  @override
  String get recoverPasteWrong =>
      'The copied text does not have 24 words. Copy the whole code and paste it again.';

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
  String get recoverStepInstall => 'Saving the list on this phone';

  @override
  String get recoverDoneTitle => 'List recovered';

  @override
  String recoverDoneSelf(String name) {
    return 'This phone belongs to $name.';
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
  String get transferredTitle => 'This list has moved';

  @override
  String get transferredBody =>
      'Your list is now on another phone or in another app. You can still view it here, but you can no longer edit it. Nothing has been deleted.';

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
      'The 24 words are not available yet. Check your connection and try again.';

  @override
  String get recoverReplaceTitle => 'Replace the list on this phone?';

  @override
  String get recoverReplaceBody =>
      'This code belongs to another family. If you continue, you will see their list on this phone. Your current list will stay on the phone, but you will no longer see it.';

  @override
  String get recoverReplaceConfirm => 'Replace';

  @override
  String get recoverAbandon => 'Cancel the recovery';

  @override
  String get recoverAbandonTitle => 'Cancel the recovery?';

  @override
  String get recoverAbandonBody =>
      'If you cancel, this phone will delete the temporary recovery data. If the list is already read-only on your previous phone, it will stay that way. You can use the code again.';

  @override
  String get recoverAbandonConfirm => 'Cancel recovery';

  @override
  String get recoverAbandonKeep => 'Keep going';

  @override
  String get recoverAbandonFailed =>
      'Something went wrong. Try again in a moment.';

  @override
  String get recoverAbandonBodyClaimed =>
      'The list is already read-only on the other phone. It will stay that way if you cancel. To recover the list, you will need to use this code again.';

  @override
  String get recoveryWordsWarnNoBlock =>
      'This phone cannot block screenshots: do not take any.';

  @override
  String get recoverLeaveTitle => 'Leave the recovery?';

  @override
  String get recoverLeaveBody =>
      'It stays half done on this phone. You can resume or cancel it from the welcome screen.';

  @override
  String get recoverPendingTitle => 'Recovery paused';

  @override
  String get recoverPendingBody =>
      'You have an unfinished recovery on this phone. Resume or cancel it before creating a family or joining another.';

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
  String get recoveryRemoveAuthMessage => 'Enter your PIN to delete the code.';

  @override
  String get recoveryRemoveBiometric =>
      'Confirm you want to delete the recovery code';

  @override
  String get transferredRecover => 'Recover with my code';

  @override
  String get transferredErase => 'Delete this app\'s data';

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
      'You can also save the code in a file. Anyone who can open it can recover the list with the same access you have on this phone.';

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
      'If you forget the password, you will not be able to open the file. You can still recover the list with the 24 words.';

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
  String get recoveryFileDerivingTitle => 'Processing the file…';

  @override
  String get recoveryFileDerivingBody =>
      'Keep the app open. This step takes a few seconds.';

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
      'The file was not saved correctly. Save it again, maybe somewhere else.';

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
      'Try \"Share\" or use the 24 words.';

  @override
  String get recoveryFileProblemPickerBusyTitle =>
      'A file picker is already open';

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
      'This file contains an old code and no longer works. Look for a newer file or change the code.';

  @override
  String get recoveryFileProblemHasFamilyTitle =>
      'This phone already has a list';

  @override
  String get recoveryFileProblemHasFamilyBody =>
      'A recovery file only works on a phone that has no list yet. The file was not used.';

  @override
  String get recoveryCheckFileAction => 'Check a file';

  @override
  String get recoveryCheckFileTitle => 'Check a file';

  @override
  String get recoveryCheckFileBody =>
      'Choose the recovery file you saved. The app will check whether it contains this phone\'s recovery code. Nothing is saved or sent.';

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
      'The file contains this phone\'s recovery code. If you lose the phone, you can use the file to get the list back.';

  @override
  String get obRecoverWithFile => 'Use a recovery file';

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
      'This phone will recover the list and take the place of the phone that saved the code. Continue only if this is your file.';

  @override
  String get recoverFileOther => 'Choose another file';

  @override
  String get recoverFileWaitingTitle => 'Switch files?';

  @override
  String get recoverFileWaitingBody =>
      'A new recovery file arrived while you were using another one.';

  @override
  String get recoverFileWaitingSwitch => 'Use the new file';

  @override
  String get recoverFileWaitingKeep => 'Keep the current one';

  @override
  String get recoveryProblemPersonTitle =>
      'This code no longer works for the selected person';

  @override
  String get recoveryProblemPersonBody =>
      'The person selected under \"This phone belongs to\" has changed, or a change is pending. Create a new code and save it.';

  @override
  String get recoveryFileProblemStorageTitle =>
      'Could not read this phone\'s list';

  @override
  String get recoveryFileProblemStorageBody =>
      'The file is still waiting to be opened. The app needs to check whether there is already a list on this phone. Try again.';

  @override
  String get cameraRestricted =>
      'Camera access is restricted on this phone. If you use Screen Time, check Settings > Screen Time > Content & Privacy Restrictions.';

  @override
  String get obJoinFamily => 'Join a family';

  @override
  String get obJoinFamilyHint =>
      'Choose how to connect with the phone that already has the list.';

  @override
  String get obJoinQrHint =>
      'If you have the other phone handy, scan its QR code.';

  @override
  String get obJoinLinkHint =>
      'If the other phone is far away, paste the link you received.';

  @override
  String get obRestoreBackup => 'Restore a copy';

  @override
  String get obRestoreBackupHint => 'Choose how to restore your list.';

  @override
  String get obRestoreCodeHint => 'Type the 24 words you saved.';

  @override
  String get obRestoreFileHint => 'Open the recovery file you saved.';

  @override
  String get giverPeopleSection => 'People';

  @override
  String get giverPeopleHintAdd => 'Will be added as a giver first';

  @override
  String get giverPeopleHintRecover => 'Will return to the list of givers';

  @override
  String giverPersonAddTitle(String name) {
    return 'Add $name as a giver?';
  }

  @override
  String giverPersonAddBody(String name) {
    return 'This gift is a surprise. First, add $name to the list of givers. Everyone in the family will see their name on that list, with no mention of the gift. Then you can choose $name here.';
  }

  @override
  String giverPersonAddConfirm(String name) {
    return 'Add $name as a giver';
  }

  @override
  String giverPersonAddFailed(String name) {
    return 'Could not add $name as a giver. Try again.';
  }

  @override
  String get giftNoLongerVisible =>
      'You can no longer view this gift on this phone.';

  @override
  String deleteGiverRows(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'These $count names will be deleted: $names.',
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
    return '$name will stay in \"People\". Only their entry in \"Givers\" will be deleted.';
  }

  @override
  String get deleteImpactChanged =>
      'The list has changed. Before you confirm, check what will be deleted.';

  @override
  String get deletePersonLinkedGiver =>
      'Their name will stay as the giver on the gifts they give to others.';

  @override
  String devicePersonBlockedThisTitle(String name) {
    return 'This phone belongs to $name';
  }

  @override
  String devicePersonBlockedThisBody(String name) {
    return 'To delete or archive $name, go to Settings and choose someone else under \"This phone belongs to\".';
  }

  @override
  String devicePersonBlockedOtherTitle(String name) {
    return '$name has a connected device';
  }

  @override
  String devicePersonBlockedOtherBody(String name) {
    return '$name has a device connected to the family, so they can\'t be deleted or archived from here.';
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
      'Already a giver. The two columns in Who gives what will merge into one.';

  @override
  String giverLinkConfirmTitle(String name) {
    return 'Link to $name?';
  }

  @override
  String giverLinkConfirmBody(String giver, String name) {
    return '\"$giver\" will use $name\'s name and colour. If you change them in People, they will change here too. All gifts will be kept.';
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
    return 'The giver will keep their current name, colour and gifts. Changes you make to $name in People will no longer apply here.';
  }

  @override
  String get giverUnlinkConfirm => 'Unlink';

  @override
  String get giverLinkError => 'Could not change the link. Try again.';

  @override
  String get giftWriteGiftUnavailable =>
      'Not saved: this gift is no longer available on this phone.';

  @override
  String get giftWriteRecipientGone =>
      'Not saved: the person receiving this gift is no longer on the list.';

  @override
  String get giftWriteInvalidPair =>
      'Not saved: the giver can\'t be the person receiving the gift.';

  @override
  String get giftWriteGiverGone =>
      'Not saved: that giver is no longer on the list.';

  @override
  String get giftWriteGiverArchived => 'Not saved: that giver is archived.';

  @override
  String get giftWritePersonGone =>
      'Not saved: that person is no longer on the list.';

  @override
  String get giftWritePersonArchived => 'Not saved: that person is archived.';

  @override
  String giverUnlinkStale(String name) {
    return 'It was no longer linked to $name.';
  }

  @override
  String get deleteImpactUnavailable =>
      'Could not check what would be deleted. Try again.';

  @override
  String get deleteImpactChecking => 'Checking what will be deleted…';

  @override
  String get inviteForTitle => 'Who is the new phone for?';

  @override
  String get inviteForBody =>
      'Choose the person who will use it. Their phone will not show any gifts for them.';

  @override
  String get inviteForNeedsSelf =>
      'Before connecting another device, say whose phone this is.';

  @override
  String inviteForSecretNotice(String name) {
    return 'Gifts for $name become secret: they will no longer show on their phone.';
  }

  @override
  String pairingV2HostCompareFor(String name) {
    return 'You are connecting $name\'s phone.';
  }

  @override
  String get pairingV2HostUpdateHint =>
      'If the other phone shows an error, update Gift Huddle on that phone and start again.';

  @override
  String pairingV2ProtectFailed(String name) {
    return 'Gifts for $name could not be made secret, so the phone was not connected. That phone has been removed and may need to connect again. This phone keeps hiding the gifts for its own person. Sync and try again.';
  }

  @override
  String get pairingV2GuestAssigned =>
      'The person inviting you has chosen whose phone this is. You will see it once you are in.';

  @override
  String pairingV2GuestDoneFor(String name) {
    return 'You are in the family. This phone belongs to $name: gifts for $name are not shown here.';
  }

  @override
  String ownGiftsHiddenBody(String name) {
    return 'This phone does not show gifts for $name. Only another person in the family can change that, from their own phone.';
  }

  @override
  String protectionAutoReason(String name) {
    return 'On because $name has a phone connected.';
  }

  @override
  String protectionDeactivateHasDevice(String name) {
    return '$name has a phone connected: their gifts will still not show on it. If you turn this off, they will show on devices that do not have the key, such as the web.';
  }

  @override
  String ownGiftsAloneNotice(String name) {
    return 'This phone is no longer connected to any other. The gifts for $name that were secret are not on this phone.';
  }

  @override
  String get whoAreYouTitle => 'Who are you?';

  @override
  String get whoAreYouBody =>
      'Before connecting another device, say whose phone this is. It will not show any gifts for that person.';

  @override
  String get whoAreYouNotOnList => 'I am not on the list';

  @override
  String get whoAreYouNameLabel => 'Your name';

  @override
  String get whoAreYouNobody => 'Nobody';

  @override
  String personSameNameTitle(String name) {
    return 'Someone called $name is already on the list';
  }

  @override
  String get personSameNameOther => 'Someone else';

  @override
  String get whoAreYouSameNameBody =>
      'Is that you? If you choose “Someone else”, another person is added with the same name.';

  @override
  String get whoAreYouSameNameYes => 'That\'s me';

  @override
  String get inviteForSameNameBody =>
      'Is that the same person? If you choose “Someone else”, another person is added with the same name.';

  @override
  String get inviteForSameNameYes => 'Same person';

  @override
  String get whoAreYouNobodyHint =>
      'For someone who gives gifts and does not receive any.';

  @override
  String get inviteForNotOnList => 'Not on the list';

  @override
  String get inviteForNobody => 'Nobody: only gives gifts';

  @override
  String get inviteForNameLabel => 'Name';

  @override
  String get personNoGiftsLabel => 'Only gives gifts';

  @override
  String get joinQrPairingTitle => 'Connect this phone';

  @override
  String protectionReason_webUseMobile(String name) {
    return '$name\'s secret gifts are changed from your phone.';
  }

  @override
  String get webSecretsPending => 'Pending';

  @override
  String get webSecretsReconnect =>
      'To see secret gifts, connect this computer again from your phone.';

  @override
  String get webSecretsWaitingPhone =>
      'Open the app on your phone to see secret gifts here. If they don\'t show up, update the app on your phone.';

  @override
  String get webSecretsSharedComputer =>
      'With secret gifts on screen, the web locks after 5 minutes without use. Don\'t leave it open on a computer the family shares.';

  @override
  String get webForgetPendingSecrets =>
      'There are changes to secret gifts that your phone hasn\'t picked up yet. If you forget this computer, they will be lost.';

  @override
  String webSecretsDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes to secret gifts were discarded: they can no longer be applied (the gifts no longer exist, moved to another person or are too long).',
      one:
          '$count change to a secret gift was discarded: it can no longer be applied (the gift no longer exists, moved to another person or is too long).',
    );
    return '$_temp0';
  }

  @override
  String ownGiftsNoticeTitle(String name) {
    return 'Gifts for $name';
  }

  @override
  String get webApproveSecretsNotice =>
      'That computer will be able to see and change everyone else\'s secret gifts. Confirm it only if you connected it yourself.';

  @override
  String webSecretsHeld(String names) {
    return 'Changes to secret gifts for $names could not be sent yet. It will try again by itself.';
  }

  @override
  String get webSecretsPendingLong => 'Waiting for your phone';

  @override
  String get giftSearchOpen => 'Search gifts';

  @override
  String get pairingV2GuestOutdated =>
      'The other phone needs to update Gift Huddle to join.';

  @override
  String get pairingV2ApproveFailed =>
      'Access could not be given to the other phone. It has been removed and may need to connect again. This phone keeps hiding the gifts for its own person.';

  @override
  String get secretBlockNoteWeb => 'This computer does not show them.';

  @override
  String ownGiftsHiddenBodyWeb(String name) {
    return 'This computer does not show gifts for $name. Only another person in the family can change that, from their own phone.';
  }

  @override
  String ownGiftsAloneNoticeWeb(String name) {
    return 'This computer is no longer connected to any phone in the family. The gifts for $name that were secret are not on this computer.';
  }

  @override
  String get manageLockedThisDeviceWeb =>
      'This computer belongs to this person.';

  @override
  String devicePersonBlockedThisTitleWeb(String name) {
    return 'This computer belongs to $name';
  }

  @override
  String devicePersonBlockedThisBodyWeb(String name) {
    return 'You cannot delete or archive $name from this computer because it belongs to them.';
  }

  @override
  String get giftNotSavedWeb =>
      'Not saved: this gift is no longer available on this computer.';

  @override
  String get giftWriteGiftUnavailableWeb =>
      'Not saved: this gift is no longer available on this computer.';

  @override
  String get giftNoLongerVisibleWeb =>
      'You can no longer view this gift on this computer.';

  @override
  String get giftOwnRequestRestrictedWeb =>
      'While protection is on, you cannot add or view gifts for yourself on this computer. Ask someone else in the family to add the gift.';

  @override
  String get aboutPrivacyWeb =>
      'No accounts or ads. Your list only leaves this computer to sync with your family\'s phones, and it is always encrypted.';

  @override
  String get wishTag => 'Wish';

  @override
  String get surprisesTitle => 'Surprises';

  @override
  String wishCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wishes',
      one: '$count wish',
      zero: 'No wishes',
    );
    return '$_temp0';
  }

  @override
  String get wishAdd => 'Add wish';

  @override
  String get wishEditorNewTitle => 'New wish';

  @override
  String get wishEditorEditTitle => 'Edit wish';

  @override
  String get wishFieldDescription => 'Description';

  @override
  String get wishEmptyTitle => 'No wishes yet';

  @override
  String get wishEmptyMessage =>
      'Note down what you\'d like to get. Your family will see it, but you won\'t know who gives it.';

  @override
  String get wishDelete => 'Remove from my list';

  @override
  String wishDeleteTitle(String name) {
    return 'Remove \"$name\" from your list?';
  }

  @override
  String get wishDeleteBody =>
      'It disappears from your list and from what your family sees. This cannot be undone.';

  @override
  String get wishDeleteConfirm => 'Remove';

  @override
  String get wishSavedPending =>
      'Saved on this phone only. It will be shared when there is room.';

  @override
  String get wishClaim => 'I\'ll give this';

  @override
  String wishClaimFor(String title) {
    return 'I\'ll give this: $title';
  }

  @override
  String get wishClaimNeedsFamily =>
      'To take wishes, this phone has to be connected to the family with the new version.';

  @override
  String get wishClaimHowToConnect => 'How to connect it';

  @override
  String get wishAvailableNote => 'Nobody has taken it';

  @override
  String wishClaimedBy(String name) {
    return 'Taken by $name';
  }

  @override
  String get wishClaimedByYou => 'You took it';

  @override
  String get wishConflict =>
      'Two people took it. One of you should release it.';

  @override
  String wishRemovedFromList(String name) {
    return '$name removed it from their list';
  }

  @override
  String get wishPlanTitle => 'Taken wish';

  @override
  String wishPlanNote(String name) {
    return 'The wish is $name\'s. Here you only note your own part.';
  }

  @override
  String wishPlanReadOnly(String name) {
    return 'Only $name can change or release it.';
  }

  @override
  String get wishFieldPurchaseUrl => 'Purchase link';

  @override
  String get wishPurchaseUrlInvalid => 'The purchase link is not valid.';

  @override
  String get wishPlanRelease => 'Release';

  @override
  String wishReleaseTitle(String name) {
    return 'Release \"$name\"?';
  }

  @override
  String get wishReleaseBody =>
      'It becomes available to someone else again. What you noted (giver, prices, store and notes) is lost.';

  @override
  String get wishPlanDelete => 'Delete my claim';

  @override
  String wishPlanDeleteTitle(String name) {
    return 'Delete your claim on \"$name\"?';
  }

  @override
  String get wishPlanDeleteBody =>
      'What you noted is deleted. This cannot be undone.';

  @override
  String get wishPlanConvert => 'Turn into a surprise';

  @override
  String get wishPlanConvertHint =>
      'It becomes a surprise gift, separate from the wish.';

  @override
  String wishConvertTitle(String name) {
    return 'Turn \"$name\" into a surprise?';
  }

  @override
  String get wishConvertBody =>
      'The wish on the list becomes available to other people again.';

  @override
  String get wishConvertConfirm => 'Turn into';

  @override
  String wishClaimedNotice(String name) {
    return 'You took \"$name\"';
  }

  @override
  String get wishReleasedNotice => 'Released';

  @override
  String get wishConvertedNotice => 'Now it\'s a surprise';

  @override
  String get wishPlanDeletedNotice => 'Claim deleted';

  @override
  String giftVisibleSwitch(String name) {
    return 'Visible to $name';
  }

  @override
  String giftVisibleHint(String name) {
    return '$name will see it as one more wish. Only $name can change it.';
  }

  @override
  String giftVisibleNoSurprise(String name) {
    return 'A surprise for $name can\'t be saved from this phone: only a visible wish.';
  }

  @override
  String get wishSuggest => 'Suggest a wish';

  @override
  String get wishProblemCap =>
      'This list already has 200 wishes. Remove one to add another.';

  @override
  String get wishProblemTooLarge =>
      'It is too long. Shorten the title or the description.';

  @override
  String get wishProblemInvalid =>
      'Check what you wrote: the title is missing or a value is not valid.';

  @override
  String get wishProblemNotOwner =>
      'Only the person the wish belongs to can change or remove it.';

  @override
  String get wishProblemGone => 'This wish is no longer on the list.';

  @override
  String get wishProblemClaimed => 'Someone else already took it.';

  @override
  String get wishProblemApproval =>
      'This device is waiting for your family\'s approval. Once it has it, you can add wishes.';

  @override
  String get wishProblemNotAllowed =>
      'This device can\'t add wishes right now.';

  @override
  String wishProblemNoDevice(String name) {
    return '$name has no phone in the family, so they can\'t see wishes.';
  }

  @override
  String wishProblemBlock(String name) {
    return 'The surprises of $name can\'t be opened right now. Sync and try again.';
  }

  @override
  String wishProblemBlockFull(String name) {
    return 'There\'s no more room in $name\'s surprises.';
  }

  @override
  String get wishProblemFailed => 'Could not save. Try again.';

  @override
  String get wishProblemDevicesNeedUpdate =>
      'To take wishes, every phone in the family needs the latest version.';

  @override
  String webPlansHeld(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes to taken wishes are waiting until the other phones in the family are updated.',
      one: 'One change to a taken wish is waiting until the other phones in the family are updated.',
    );
    return '$_temp0';
  }
}

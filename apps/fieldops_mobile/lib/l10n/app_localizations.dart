import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_th.dart';
import 'app_localizations_zh.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('th'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'FieldOps AI'**
  String get appTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to worker app'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required.'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required.'**
  String get passwordRequired;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check your credentials and connection, then try again.'**
  String get signInFailed;

  /// No description provided for @assignedJobs.
  ///
  /// In en, this message translates to:
  /// **'Assigned jobs'**
  String get assignedJobs;

  /// No description provided for @noJobsYet.
  ///
  /// In en, this message translates to:
  /// **'No assigned jobs yet'**
  String get noJobsYet;

  /// No description provided for @pullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh after a supervisor assigns work.'**
  String get pullToRefresh;

  /// No description provided for @clockIn.
  ///
  /// In en, this message translates to:
  /// **'Clock in'**
  String get clockIn;

  /// No description provided for @clockOut.
  ///
  /// In en, this message translates to:
  /// **'Clock out'**
  String get clockOut;

  /// No description provided for @clockedIn.
  ///
  /// In en, this message translates to:
  /// **'Clocked in'**
  String get clockedIn;

  /// No description provided for @readyToClockIn.
  ///
  /// In en, this message translates to:
  /// **'Ready to clock in'**
  String get readyToClockIn;

  /// No description provided for @startBreak.
  ///
  /// In en, this message translates to:
  /// **'Start Break'**
  String get startBreak;

  /// No description provided for @endBreak.
  ///
  /// In en, this message translates to:
  /// **'End Break'**
  String get endBreak;

  /// No description provided for @onBreak.
  ///
  /// In en, this message translates to:
  /// **'On break'**
  String get onBreak;

  /// No description provided for @requestOT.
  ///
  /// In en, this message translates to:
  /// **'Request OT'**
  String get requestOT;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get takePhoto;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String tasks(int count);

  /// No description provided for @taskChecklist.
  ///
  /// In en, this message translates to:
  /// **'Task checklist'**
  String get taskChecklist;

  /// No description provided for @proofPhoto.
  ///
  /// In en, this message translates to:
  /// **'Proof photo'**
  String get proofPhoto;

  /// No description provided for @beforePhoto.
  ///
  /// In en, this message translates to:
  /// **'BEFORE photo'**
  String get beforePhoto;

  /// No description provided for @afterPhoto.
  ///
  /// In en, this message translates to:
  /// **'AFTER photo'**
  String get afterPhoto;

  /// No description provided for @capturing.
  ///
  /// In en, this message translates to:
  /// **'Capturing...'**
  String get capturing;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading proof photo...'**
  String get uploading;

  /// No description provided for @finalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing...'**
  String get finalizing;

  /// No description provided for @photoUploaded.
  ///
  /// In en, this message translates to:
  /// **'Photo uploaded successfully'**
  String get photoUploaded;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @eventsQueued.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event queued} other{{count} events queued}}'**
  String eventsQueued(int count);

  /// No description provided for @submitOTRequest.
  ///
  /// In en, this message translates to:
  /// **'Submit OT Request'**
  String get submitOTRequest;

  /// No description provided for @overtimeAlert.
  ///
  /// In en, this message translates to:
  /// **'You are entering overtime'**
  String get overtimeAlert;

  /// No description provided for @hoursWorked.
  ///
  /// In en, this message translates to:
  /// **'Hours worked so far'**
  String get hoursWorked;

  /// No description provided for @reasonForOvertime.
  ///
  /// In en, this message translates to:
  /// **'Reason for overtime'**
  String get reasonForOvertime;

  /// No description provided for @mySchedule.
  ///
  /// In en, this message translates to:
  /// **'My schedule'**
  String get mySchedule;

  /// No description provided for @upcomingShifts.
  ///
  /// In en, this message translates to:
  /// **'Upcoming shifts'**
  String get upcomingShifts;

  /// No description provided for @scheduleHelp.
  ///
  /// In en, this message translates to:
  /// **'Published shifts for the next two weeks. Pull to refresh if a supervisor updates your schedule.'**
  String get scheduleHelp;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @noScheduledShiftsYet.
  ///
  /// In en, this message translates to:
  /// **'No scheduled shifts yet'**
  String get noScheduledShiftsYet;

  /// No description provided for @scheduleWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Published shifts will appear here when your supervisor sends the schedule.'**
  String get scheduleWillAppear;

  /// No description provided for @scheduleUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Schedule unavailable'**
  String get scheduleUnavailable;
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
      <String>['en', 'es', 'fr', 'th', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'th':
      return AppLocalizationsTh();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

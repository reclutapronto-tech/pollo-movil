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
  /// **'Pollo Móvil'**
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

  /// No description provided for @restaurantClockTitle.
  ///
  /// In en, this message translates to:
  /// **'Time clock'**
  String get restaurantClockTitle;

  /// No description provided for @restaurantClockGpsServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to record attendance.'**
  String get restaurantClockGpsServiceOff;

  /// No description provided for @restaurantClockGpsPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required because this branch enabled it for the time clock.'**
  String get restaurantClockGpsPermissionRequired;

  /// User-facing error when the device cannot obtain a one-time clock location.
  String get restaurantClockGpsLocationUnavailable;

  /// No description provided for @restaurantClockQueued.
  ///
  /// In en, this message translates to:
  /// **'Your record for {branch} is saved on this phone and will sync when the connection returns.'**
  String restaurantClockQueued(String branch);

  /// No description provided for @restaurantClockEntrySaved.
  ///
  /// In en, this message translates to:
  /// **'Clock-in recorded at {branch}.'**
  String restaurantClockEntrySaved(String branch);

  /// No description provided for @restaurantClockExitSaved.
  ///
  /// In en, this message translates to:
  /// **'Clock-out recorded at {branch}.'**
  String restaurantClockExitSaved(String branch);

  /// No description provided for @restaurantClockSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get restaurantClockSaving;

  /// No description provided for @restaurantClockActive.
  ///
  /// In en, this message translates to:
  /// **'You have an active clock-in.'**
  String get restaurantClockActive;

  /// No description provided for @restaurantClockInactive.
  ///
  /// In en, this message translates to:
  /// **'No active clock-in.'**
  String get restaurantClockInactive;

  /// No description provided for @restaurantClockEntryTime.
  ///
  /// In en, this message translates to:
  /// **'Clock-in: {time}'**
  String restaurantClockEntryTime(String time);

  /// No description provided for @restaurantClockPendingSync.
  ///
  /// In en, this message translates to:
  /// **'A time record is saved on this phone and waiting to sync.'**
  String get restaurantClockPendingSync;

  /// No description provided for @restaurantClockActiveEntries.
  ///
  /// In en, this message translates to:
  /// **'Active clock-ins'**
  String get restaurantClockActiveEntries;

  /// No description provided for @restaurantClockNoActiveEntries.
  ///
  /// In en, this message translates to:
  /// **'No team members are currently clocked in.'**
  String get restaurantClockNoActiveEntries;

  /// No description provided for @restaurantClockUnavailableTime.
  ///
  /// In en, this message translates to:
  /// **'Time unavailable'**
  String get restaurantClockUnavailableTime;

  /// No description provided for @restaurantClockTeamMember.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get restaurantClockTeamMember;

  /// No description provided for @restaurantClockEntryAt.
  ///
  /// In en, this message translates to:
  /// **'Clocked in at {time}'**
  String restaurantClockEntryAt(String time);

  /// No description provided for @restaurantClockActivePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only active clock-in status is shown; background location is not used.'**
  String get restaurantClockActivePrivacy;

  /// No description provided for @restaurantClockTodayAttendance.
  ///
  /// In en, this message translates to:
  /// **'Today\'s attendance'**
  String get restaurantClockTodayAttendance;

  /// No description provided for @restaurantClockNoBranchEntries.
  ///
  /// In en, this message translates to:
  /// **'There are no clock-in records for this branch yet today.'**
  String get restaurantClockNoBranchEntries;

  /// No description provided for @restaurantClockEntry.
  ///
  /// In en, this message translates to:
  /// **'Clock-in'**
  String get restaurantClockEntry;

  /// No description provided for @restaurantClockEntryForDate.
  ///
  /// In en, this message translates to:
  /// **'Clock-in ({date})'**
  String restaurantClockEntryForDate(String date);

  /// No description provided for @restaurantClockNoExit.
  ///
  /// In en, this message translates to:
  /// **'no clock-out'**
  String get restaurantClockNoExit;

  /// No description provided for @restaurantClockExitAt.
  ///
  /// In en, this message translates to:
  /// **'clock-out {time}'**
  String restaurantClockExitAt(String time);

  /// No description provided for @restaurantClockSessionSummary.
  ///
  /// In en, this message translates to:
  /// **'{entry} {start} · {exit}'**
  String restaurantClockSessionSummary(String entry, String start, String exit);

  /// No description provided for @restaurantClockAttendancePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only today\'s attendance is shown; this summary does not include locations.'**
  String get restaurantClockAttendancePrivacy;

  /// No description provided for @restaurantClockMyAttendance.
  ///
  /// In en, this message translates to:
  /// **'My records today'**
  String get restaurantClockMyAttendance;

  /// No description provided for @restaurantClockNoMyEntriesToday.
  ///
  /// In en, this message translates to:
  /// **'You do not have any clock-in records today yet.'**
  String get restaurantClockNoMyEntriesToday;

  /// No description provided for @restaurantClockMyPrivacy.
  ///
  /// In en, this message translates to:
  /// **'This summary shows only your time records and does not display locations.'**
  String get restaurantClockMyPrivacy;

  /// No description provided for @restaurantClockToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get restaurantClockToday;

  /// No description provided for @restaurantClockPreviousDate.
  ///
  /// In en, this message translates to:
  /// **'Previous date'**
  String get restaurantClockPreviousDate;

  /// No description provided for @restaurantClockGpsRequired.
  ///
  /// In en, this message translates to:
  /// **'This branch requests location when you clock in or out. The app does not collect location in the background.'**
  String get restaurantClockGpsRequired;

  /// No description provided for @restaurantClockGpsNotRequired.
  ///
  /// In en, this message translates to:
  /// **'The time clock is active without collecting location. Background location is not used.'**
  String get restaurantClockGpsNotRequired;

  /// No description provided for @restaurantClockNoPayroll.
  ///
  /// In en, this message translates to:
  /// **'This record documents operational attendance; it does not calculate payroll.'**
  String get restaurantClockNoPayroll;

  /// No description provided for @restaurantMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get restaurantMoreTitle;

  /// No description provided for @restaurantAccount.
  ///
  /// In en, this message translates to:
  /// **'Pollo Móvil account'**
  String get restaurantAccount;

  /// No description provided for @restaurantAssignedBranchAccess.
  ///
  /// In en, this message translates to:
  /// **'Secure access to your assigned branch'**
  String get restaurantAssignedBranchAccess;

  /// No description provided for @restaurantMoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Pollo Móvil coordinates activities, inspections, incidents, and shift handoffs. Location is not collected in the background.'**
  String get restaurantMoreDescription;

  /// No description provided for @restaurantNotificationsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Notifications on this device'**
  String get restaurantNotificationsThisDevice;

  /// No description provided for @restaurantPushOperationalUpdates.
  ///
  /// In en, this message translates to:
  /// **'Push alerts for activities and operational changes.'**
  String get restaurantPushOperationalUpdates;

  /// No description provided for @restaurantPushRequiresSetup.
  ///
  /// In en, this message translates to:
  /// **'Push notifications are available after Firebase and this platform\'s notification setup are complete.'**
  String get restaurantPushRequiresSetup;

  /// No description provided for @restaurantPushEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enable notifications. Check this phone\'s notification permission and the Firebase mobile configuration.'**
  String get restaurantPushEnableFailed;
  String get restaurantNotificationView;

  /// No description provided for @restaurantSignOutPendingEvents.
  ///
  /// In en, this message translates to:
  /// **'Events queued for synchronization remain on this phone.'**
  String get restaurantSignOutPendingEvents;

  /// No description provided for @restaurantOperationalAppLabel.
  ///
  /// In en, this message translates to:
  /// **'Pollo Móvil · operations app'**
  String get restaurantOperationalAppLabel;

  /// No description provided for @restaurantNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get restaurantNotificationsTitle;

  /// No description provided for @restaurantNotificationsQueuedRead.
  ///
  /// In en, this message translates to:
  /// **'The inbox will refresh when the connection returns.'**
  String get restaurantNotificationsQueuedRead;

  /// No description provided for @restaurantNotificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get restaurantNotificationsMarkAllRead;

  /// No description provided for @restaurantNotificationsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load notifications. {error}'**
  String restaurantNotificationsLoadError(String error);

  /// No description provided for @restaurantNotificationsOfflineEmpty.
  ///
  /// In en, this message translates to:
  /// **'The saved copy has no notifications. Connect to refresh your inbox.'**
  String get restaurantNotificationsOfflineEmpty;

  /// No description provided for @restaurantNotificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any notifications yet.'**
  String get restaurantNotificationsEmpty;

  /// No description provided for @restaurantNotificationsOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox saved offline'**
  String get restaurantNotificationsOfflineTitle;

  /// No description provided for @restaurantNotificationsOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Its state may have changed since the last update.'**
  String get restaurantNotificationsOfflineBody;

  /// No description provided for @restaurantNotificationFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get restaurantNotificationFallbackTitle;

  /// No description provided for @restaurantNotificationReadPending.
  ///
  /// In en, this message translates to:
  /// **'Read status waiting to sync'**
  String get restaurantNotificationReadPending;

  /// No description provided for @restaurantNotificationMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get restaurantNotificationMarkRead;

  /// No description provided for @restaurantInspectionQueued.
  ///
  /// In en, this message translates to:
  /// **'Inspection saved on this phone and will sync when the connection returns.'**
  String get restaurantInspectionQueued;

  /// No description provided for @restaurantInspectionSaved.
  ///
  /// In en, this message translates to:
  /// **'Inspection saved.'**
  String get restaurantInspectionSaved;

  /// No description provided for @restaurantInspectionNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Inspection saved; 1 item needs attention.} other{Inspection saved; {count} items need attention.}}'**
  String restaurantInspectionNeedsAttention(int count);

  /// No description provided for @restaurantInspectionNoActiveCriteria.
  ///
  /// In en, this message translates to:
  /// **'This checklist has no active criteria. Ask an administrator to configure it.'**
  String get restaurantInspectionNoActiveCriteria;

  /// No description provided for @restaurantInspectionInstruction.
  ///
  /// In en, this message translates to:
  /// **'Record the observed status for each criterion configured by this branch.'**
  String get restaurantInspectionInstruction;

  /// No description provided for @restaurantInspectionCriterion.
  ///
  /// In en, this message translates to:
  /// **'Criterion'**
  String get restaurantInspectionCriterion;

  /// No description provided for @restaurantInspectionObservedState.
  ///
  /// In en, this message translates to:
  /// **'Observed status'**
  String get restaurantInspectionObservedState;

  /// No description provided for @restaurantInspectionResultOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get restaurantInspectionResultOk;

  /// No description provided for @restaurantInspectionResultNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get restaurantInspectionResultNeedsAttention;

  /// No description provided for @restaurantInspectionResultNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'Not applicable'**
  String get restaurantInspectionResultNotApplicable;

  /// No description provided for @restaurantInspectionOptionalDetail.
  ///
  /// In en, this message translates to:
  /// **'Optional detail'**
  String get restaurantInspectionOptionalDetail;

  /// No description provided for @restaurantInspectionOptionalGeneralNote.
  ///
  /// In en, this message translates to:
  /// **'General note (optional)'**
  String get restaurantInspectionOptionalGeneralNote;

  /// No description provided for @restaurantInspectionSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get restaurantInspectionSaving;

  /// No description provided for @restaurantInspectionSave.
  ///
  /// In en, this message translates to:
  /// **'Save inspection'**
  String get restaurantInspectionSave;

  /// No description provided for @restaurantInspectionOfflineHelp.
  ///
  /// In en, this message translates to:
  /// **'If you\'re offline, the inspection stays on this phone and will be sent when the connection returns.'**
  String get restaurantInspectionOfflineHelp;

  /// No description provided for @restaurantInspectionDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get restaurantInspectionDefaultTitle;

  /// No description provided for @restaurantShiftScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift schedule'**
  String get restaurantShiftScheduleTitle;

  /// No description provided for @restaurantShiftSaved.
  ///
  /// In en, this message translates to:
  /// **'Shift saved.'**
  String get restaurantShiftSaved;

  /// No description provided for @restaurantShiftUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shift updated.'**
  String get restaurantShiftUpdated;

  /// No description provided for @restaurantShiftSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the shift: {error}'**
  String restaurantShiftSaveError(String error);

  /// No description provided for @restaurantShiftCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel shift'**
  String get restaurantShiftCancelTitle;

  /// No description provided for @restaurantShiftCancelConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Cancel the shift for {employee}?'**
  String restaurantShiftCancelConfirmation(String employee);

  /// No description provided for @restaurantShiftCanceled.
  ///
  /// In en, this message translates to:
  /// **'Shift canceled.'**
  String get restaurantShiftCanceled;

  /// No description provided for @restaurantShiftCancelError.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel the shift: {error}'**
  String restaurantShiftCancelError(String error);

  /// No description provided for @restaurantShiftLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load this week\'s schedule.'**
  String get restaurantShiftLoadError;

  /// No description provided for @restaurantShiftPreviousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get restaurantShiftPreviousWeek;

  /// No description provided for @restaurantShiftNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get restaurantShiftNextWeek;

  /// No description provided for @restaurantShiftOfflineNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing the last saved schedule. Shift editing will be available when the connection returns.'**
  String get restaurantShiftOfflineNotice;

  /// No description provided for @restaurantShiftTimezone.
  ///
  /// In en, this message translates to:
  /// **'Times use the branch\'s local time zone: {timeZone}'**
  String restaurantShiftTimezone(String timeZone);

  /// No description provided for @restaurantShiftAdd.
  ///
  /// In en, this message translates to:
  /// **'Add shift'**
  String get restaurantShiftAdd;

  /// No description provided for @restaurantShiftNoShifts.
  ///
  /// In en, this message translates to:
  /// **'No scheduled shifts.'**
  String get restaurantShiftNoShifts;

  /// No description provided for @restaurantShiftTeamMember.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get restaurantShiftTeamMember;

  /// No description provided for @restaurantShiftPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get restaurantShiftPublished;

  /// No description provided for @restaurantShiftDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get restaurantShiftDraft;

  /// No description provided for @restaurantShiftTimeRange.
  ///
  /// In en, this message translates to:
  /// **'{start}–{end}'**
  String restaurantShiftTimeRange(String start, String end);

  /// No description provided for @restaurantShiftBreaks.
  ///
  /// In en, this message translates to:
  /// **'Break: {breaks}'**
  String restaurantShiftBreaks(String breaks);

  /// No description provided for @restaurantShiftEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get restaurantShiftEdit;

  /// No description provided for @restaurantShiftCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel shift'**
  String get restaurantShiftCancelAction;

  /// No description provided for @restaurantShiftAddDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add shift'**
  String get restaurantShiftAddDialogTitle;

  /// No description provided for @restaurantShiftEditDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit shift'**
  String get restaurantShiftEditDialogTitle;

  /// No description provided for @restaurantShiftEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get restaurantShiftEmployee;

  /// No description provided for @restaurantShiftDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get restaurantShiftDay;

  /// No description provided for @restaurantShiftStartChoose.
  ///
  /// In en, this message translates to:
  /// **'Start: choose'**
  String get restaurantShiftStartChoose;

  /// No description provided for @restaurantShiftEndChoose.
  ///
  /// In en, this message translates to:
  /// **'End: choose'**
  String get restaurantShiftEndChoose;

  /// No description provided for @restaurantShiftStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get restaurantShiftStart;

  /// No description provided for @restaurantShiftEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get restaurantShiftEnd;

  /// No description provided for @restaurantShiftPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish shift'**
  String get restaurantShiftPublish;

  /// No description provided for @restaurantShiftDraftDescription.
  ///
  /// In en, this message translates to:
  /// **'If turned off, the shift is saved as a draft.'**
  String get restaurantShiftDraftDescription;

  /// No description provided for @restaurantShiftBreaksTitle.
  ///
  /// In en, this message translates to:
  /// **'Breaks'**
  String get restaurantShiftBreaksTitle;

  /// No description provided for @restaurantShiftAddBreak.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get restaurantShiftAddBreak;

  /// No description provided for @restaurantShiftRemoveBreak.
  ///
  /// In en, this message translates to:
  /// **'Remove break'**
  String get restaurantShiftRemoveBreak;

  /// No description provided for @restaurantShiftSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get restaurantShiftSave;

  /// No description provided for @restaurantTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Branch team'**
  String get restaurantTeamTitle;

  /// No description provided for @restaurantTeamUpdated.
  ///
  /// In en, this message translates to:
  /// **'Team member information updated.'**
  String get restaurantTeamUpdated;

  /// No description provided for @restaurantTeamSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save all changes: {error}'**
  String restaurantTeamSaveError(String error);

  /// No description provided for @restaurantInviteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite employee'**
  String get restaurantInviteDialogTitle;

  /// No description provided for @restaurantInviteLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation link'**
  String get restaurantInviteLinkTitle;

  /// No description provided for @restaurantInviteAction.
  ///
  /// In en, this message translates to:
  /// **'Invite employee'**
  String get restaurantInviteAction;

  /// No description provided for @restaurantInviteEmailNotSent.
  ///
  /// In en, this message translates to:
  /// **'The email could not be sent automatically. Copy this link and share it with the invited person.'**
  String get restaurantInviteEmailNotSent;

  /// No description provided for @restaurantInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Invitation link copied.'**
  String get restaurantInviteCopied;

  /// No description provided for @restaurantInviteCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get restaurantInviteCopyLink;

  /// No description provided for @restaurantClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get restaurantClose;

  /// No description provided for @restaurantInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent.'**
  String get restaurantInviteSent;

  /// No description provided for @restaurantInviteAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'This person is already a member of this branch.'**
  String get restaurantInviteAlreadyMember;

  /// No description provided for @restaurantInviteAccountAdded.
  ///
  /// In en, this message translates to:
  /// **'Account added to the branch.'**
  String get restaurantInviteAccountAdded;

  /// No description provided for @restaurantInviteError.
  ///
  /// In en, this message translates to:
  /// **'Could not invite this person: {error}'**
  String restaurantInviteError(String error);

  /// No description provided for @restaurantTeamLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the branch team.'**
  String get restaurantTeamLoadError;

  /// No description provided for @restaurantTeamOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Showing the last saved team'**
  String get restaurantTeamOfflineTitle;

  /// No description provided for @restaurantTeamOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'This information is read-only until the connection returns.'**
  String get restaurantTeamOfflineBody;

  /// No description provided for @restaurantTeamEmpty.
  ///
  /// In en, this message translates to:
  /// **'This branch does not have any team members yet.'**
  String get restaurantTeamEmpty;

  /// No description provided for @restaurantTeamMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 team member} other{{count} team members}}'**
  String restaurantTeamMemberCount(int count);

  /// No description provided for @restaurantInviteFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get restaurantInviteFullName;

  /// No description provided for @restaurantInviteEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get restaurantInviteEmail;

  /// No description provided for @restaurantInviteNameValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter the full name.'**
  String get restaurantInviteNameValidation;

  /// No description provided for @restaurantInvitePermissionNote.
  ///
  /// In en, this message translates to:
  /// **'The invitation will be sent to this email address. The new team member will have employee access.'**
  String get restaurantInvitePermissionNote;

  /// No description provided for @restaurantInviteSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send invitation'**
  String get restaurantInviteSubmit;

  /// No description provided for @restaurantRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch role'**
  String get restaurantRoleLabel;

  /// No description provided for @restaurantRoleEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get restaurantRoleEmployee;

  /// No description provided for @restaurantRoleSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get restaurantRoleSupervisor;

  /// No description provided for @restaurantRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get restaurantRoleAdmin;

  /// No description provided for @restaurantMemberActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get restaurantMemberActive;

  /// No description provided for @restaurantMemberInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get restaurantMemberInactive;

  /// No description provided for @restaurantMemberAccess.
  ///
  /// In en, this message translates to:
  /// **'Branch access'**
  String get restaurantMemberAccess;

  /// No description provided for @restaurantMemberDeactivateNote.
  ///
  /// In en, this message translates to:
  /// **'Deactivating access preserves shift and task history.'**
  String get restaurantMemberDeactivateNote;

  /// No description provided for @restaurantMemberPositions.
  ///
  /// In en, this message translates to:
  /// **'Enabled positions'**
  String get restaurantMemberPositions;

  /// No description provided for @restaurantPositionFallback.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get restaurantPositionFallback;

  /// No description provided for @restaurantMemberReactivateToEdit.
  ///
  /// In en, this message translates to:
  /// **'Reactivate branch access to edit enabled positions.'**
  String get restaurantMemberReactivateToEdit;

  /// No description provided for @restaurantMemberConfigurePositions.
  ///
  /// In en, this message translates to:
  /// **'Configure positions before assigning them to the team.'**
  String get restaurantMemberConfigurePositions;

  /// No description provided for @restaurantMemberSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get restaurantMemberSaveChanges;

  /// No description provided for @restaurantAbsenceReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Absence requests'**
  String get restaurantAbsenceReviewTitle;

  /// No description provided for @restaurantAbsenceApproved.
  ///
  /// In en, this message translates to:
  /// **'Request approved.'**
  String get restaurantAbsenceApproved;

  /// No description provided for @restaurantAbsenceRejected.
  ///
  /// In en, this message translates to:
  /// **'Request rejected.'**
  String get restaurantAbsenceRejected;

  /// No description provided for @restaurantAbsenceReviewError.
  ///
  /// In en, this message translates to:
  /// **'Could not review the request: {error}'**
  String restaurantAbsenceReviewError(String error);

  /// No description provided for @restaurantAbsenceLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load pending requests.'**
  String get restaurantAbsenceLoadError;

  /// No description provided for @restaurantAbsenceNone.
  ///
  /// In en, this message translates to:
  /// **'There are no pending requests.'**
  String get restaurantAbsenceNone;

  /// No description provided for @restaurantAbsenceOfflineNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing requests from the last update. Approving or rejecting requires a connection.'**
  String get restaurantAbsenceOfflineNotice;

  /// No description provided for @restaurantAbsenceOfflineEmpty.
  ///
  /// In en, this message translates to:
  /// **'There were no pending requests in the last update.'**
  String get restaurantAbsenceOfflineEmpty;

  /// No description provided for @restaurantAbsenceReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get restaurantAbsenceReject;

  /// No description provided for @restaurantAbsenceApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get restaurantAbsenceApprove;

  /// No description provided for @restaurantCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity calendar'**
  String get restaurantCalendarTitle;

  /// No description provided for @restaurantCalendarRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh calendar'**
  String get restaurantCalendarRefresh;

  /// No description provided for @restaurantCalendarLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the calendar.'**
  String get restaurantCalendarLoadError;

  /// No description provided for @restaurantCalendarRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get restaurantCalendarRetry;

  /// No description provided for @restaurantCalendarPreviousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get restaurantCalendarPreviousWeek;

  /// No description provided for @restaurantCalendarNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get restaurantCalendarNextWeek;

  /// No description provided for @restaurantCalendarManagerHint.
  ///
  /// In en, this message translates to:
  /// **'Only configured activities can be scheduled.'**
  String get restaurantCalendarManagerHint;

  /// No description provided for @restaurantCalendarBranchHint.
  ///
  /// In en, this message translates to:
  /// **'Activities assigned to your branch.'**
  String get restaurantCalendarBranchHint;

  /// No description provided for @restaurantCalendarOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing the last saved week. Scheduling is read-only until you reconnect.'**
  String get restaurantCalendarOffline;

  /// No description provided for @restaurantCalendarRetroactive.
  ///
  /// In en, this message translates to:
  /// **'Activities cannot be scheduled retroactively from the calendar.'**
  String get restaurantCalendarRetroactive;

  /// No description provided for @restaurantCalendarDayScheduled.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new activity} other{{count} new activities}} created from branch rules. Existing activities were not duplicated.'**
  String restaurantCalendarDayScheduled(int count);

  /// No description provided for @restaurantCalendarPastWeek.
  ///
  /// In en, this message translates to:
  /// **'This week has passed; no dates were changed.'**
  String get restaurantCalendarPastWeek;

  /// No description provided for @restaurantCalendarWeekScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {created} activities across {days} dates. Past dates were left unchanged; {pastDays, plural, =0{no past dates were skipped} =1{1 past date was skipped} other{{pastDays} past dates were skipped}}. Existing activities were not duplicated.'**
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays);

  /// No description provided for @restaurantCalendarWeekPartial.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {created} activities across {days} dates. Could not schedule: {dates}. You can retry; existing activities will not be duplicated.'**
  String restaurantCalendarWeekPartial(int created, int days, String dates);

  /// No description provided for @restaurantCalendarPlanWeek.
  ///
  /// In en, this message translates to:
  /// **'Schedule visible week'**
  String get restaurantCalendarPlanWeek;

  /// No description provided for @restaurantCalendarPlanningWeek.
  ///
  /// In en, this message translates to:
  /// **'Scheduling week…'**
  String get restaurantCalendarPlanningWeek;

  /// No description provided for @restaurantCalendarWeekActivities.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 activity this week} other{{count} activities this week}}'**
  String restaurantCalendarWeekActivities(int count);

  /// No description provided for @restaurantCalendarUnassignedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unassigned item} other{{count} unassigned items}}'**
  String restaurantCalendarUnassignedCount(int count);

  /// No description provided for @restaurantCalendarCompletedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 completed} other{{count} completed}}'**
  String restaurantCalendarCompletedCount(int count);

  /// No description provided for @restaurantCalendarActivityCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 activity} other{{count} activities}}'**
  String restaurantCalendarActivityCount(int count);

  /// No description provided for @restaurantCalendarPastDate.
  ///
  /// In en, this message translates to:
  /// **'Past date; activities cannot be scheduled retroactively.'**
  String get restaurantCalendarPastDate;

  /// No description provided for @restaurantCalendarScheduleFromRules.
  ///
  /// In en, this message translates to:
  /// **'Schedule from rules'**
  String get restaurantCalendarScheduleFromRules;

  /// No description provided for @restaurantCalendarScheduling.
  ///
  /// In en, this message translates to:
  /// **'Scheduling…'**
  String get restaurantCalendarScheduling;

  /// No description provided for @restaurantCalendarAssignEligible.
  ///
  /// In en, this message translates to:
  /// **'Assign eligible people'**
  String get restaurantCalendarAssignEligible;

  /// No description provided for @restaurantCalendarAssigning.
  ///
  /// In en, this message translates to:
  /// **'Assigning…'**
  String get restaurantCalendarAssigning;

  /// No description provided for @restaurantCalendarAutoAssignResult.
  ///
  /// In en, this message translates to:
  /// **'{assigned} activities assigned with {planner}; {unassigned} have no eligible employee.'**
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  );

  /// No description provided for @restaurantCalendarLocalPlanner.
  ///
  /// In en, this message translates to:
  /// **'the local planner'**
  String get restaurantCalendarLocalPlanner;

  /// No description provided for @restaurantCalendarNoActivities.
  ///
  /// In en, this message translates to:
  /// **'No activities scheduled.'**
  String get restaurantCalendarNoActivities;

  /// No description provided for @restaurantCalendarFallbackActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get restaurantCalendarFallbackActivity;

  /// No description provided for @restaurantCalendarNoAssignee.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get restaurantCalendarNoAssignee;

  /// No description provided for @restaurantCalendarConfigurationPending.
  ///
  /// In en, this message translates to:
  /// **'Configure branch positions, areas, or requirements before assigning this activity.'**
  String get restaurantCalendarConfigurationPending;

  /// No description provided for @restaurantCalendarAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assignee'**
  String get restaurantCalendarAssignee;

  /// No description provided for @restaurantCalendarFallbackAssignee.
  ///
  /// In en, this message translates to:
  /// **'Current assignee'**
  String get restaurantCalendarFallbackAssignee;

  /// No description provided for @restaurantCalendarInactiveAssignee.
  ///
  /// In en, this message translates to:
  /// **'{name} · inactive'**
  String restaurantCalendarInactiveAssignee(String name);

  /// No description provided for @restaurantCalendarEmployeeFallback.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get restaurantCalendarEmployeeFallback;

  /// No description provided for @restaurantCalendarZoneFallback.
  ///
  /// In en, this message translates to:
  /// **'Part'**
  String get restaurantCalendarZoneFallback;

  /// No description provided for @restaurantCalendarZoneAssignee.
  ///
  /// In en, this message translates to:
  /// **'Assignee for {zone}'**
  String restaurantCalendarZoneAssignee(String zone);

  /// No description provided for @restaurantCalendarStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get restaurantCalendarStatusPending;

  /// No description provided for @restaurantCalendarStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get restaurantCalendarStatusInProgress;

  /// No description provided for @restaurantCalendarStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get restaurantCalendarStatusPaused;

  /// No description provided for @restaurantCalendarStatusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get restaurantCalendarStatusBlocked;

  /// No description provided for @restaurantCalendarStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get restaurantCalendarStatusCompleted;

  /// No description provided for @restaurantCalendarTaskAssigneeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Activity assignee updated.'**
  String get restaurantCalendarTaskAssigneeUpdated;

  /// No description provided for @restaurantCalendarPartAssigneeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Part assignee updated.'**
  String get restaurantCalendarPartAssigneeUpdated;

  /// No description provided for @restaurantStructureTitle.
  ///
  /// In en, this message translates to:
  /// **'Areas and positions'**
  String get restaurantStructureTitle;

  /// No description provided for @restaurantStructureAreas.
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get restaurantStructureAreas;

  /// No description provided for @restaurantStructurePositions.
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get restaurantStructurePositions;

  /// No description provided for @restaurantStructureAdd.
  ///
  /// In en, this message translates to:
  /// **'Add {label}'**
  String restaurantStructureAdd(String label);

  /// No description provided for @restaurantStructureEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit {label}'**
  String restaurantStructureEdit(String label);

  /// No description provided for @restaurantStructureSaved.
  ///
  /// In en, this message translates to:
  /// **'{label} saved.'**
  String restaurantStructureSaved(String label);

  /// No description provided for @restaurantStructureSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save {label}: {error}'**
  String restaurantStructureSaveError(String label, String error);

  /// No description provided for @restaurantStructureReactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {label}'**
  String restaurantStructureReactivateTitle(String label);

  /// No description provided for @restaurantStructureDeactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate {label}'**
  String restaurantStructureDeactivateTitle(String label);

  /// No description provided for @restaurantStructureReactivateDescription.
  ///
  /// In en, this message translates to:
  /// **'It can be selected again for new activities.'**
  String get restaurantStructureReactivateDescription;

  /// No description provided for @restaurantStructureDeactivateDescription.
  ///
  /// In en, this message translates to:
  /// **'It will be hidden from new activities. Existing history will be preserved.'**
  String get restaurantStructureDeactivateDescription;

  /// No description provided for @restaurantStructureBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get restaurantStructureBack;

  /// No description provided for @restaurantStructureReactivateAction.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get restaurantStructureReactivateAction;

  /// No description provided for @restaurantStructureDeactivateAction.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get restaurantStructureDeactivateAction;

  /// No description provided for @restaurantStructureEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items have been configured yet.'**
  String get restaurantStructureEmpty;

  /// No description provided for @restaurantStructureStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Status: active'**
  String get restaurantStructureStatusActive;

  /// No description provided for @restaurantStructureStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Status: inactive'**
  String get restaurantStructureStatusInactive;

  /// No description provided for @restaurantStructureAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add {label}'**
  String restaurantStructureAddTooltip(String label);

  /// No description provided for @restaurantStructureEditName.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get restaurantStructureEditName;

  /// No description provided for @restaurantStructureOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Showing the last saved configuration'**
  String get restaurantStructureOfflineTitle;

  /// No description provided for @restaurantStructureOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Areas, positions, and features are read-only until the connection returns.'**
  String get restaurantStructureOfflineBody;

  /// No description provided for @restaurantStructureKeepHistory.
  ///
  /// In en, this message translates to:
  /// **'Deactivate items instead of deleting them to preserve operational history.'**
  String get restaurantStructureKeepHistory;

  /// No description provided for @restaurantStructureLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load branch configuration.'**
  String get restaurantStructureLoadError;

  /// No description provided for @restaurantStructureRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get restaurantStructureRetry;

  /// No description provided for @restaurantAttendanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Attendance and location'**
  String get restaurantAttendanceTitle;

  /// No description provided for @restaurantAttendanceOptional.
  ///
  /// In en, this message translates to:
  /// **'These features are optional per branch and are off by default.'**
  String get restaurantAttendanceOptional;

  /// No description provided for @restaurantAttendanceEnableClock.
  ///
  /// In en, this message translates to:
  /// **'Enable time clock'**
  String get restaurantAttendanceEnableClock;

  /// No description provided for @restaurantAttendanceClockDescription.
  ///
  /// In en, this message translates to:
  /// **'Records clock-in and clock-out. It does not calculate payroll.'**
  String get restaurantAttendanceClockDescription;

  /// No description provided for @restaurantAttendanceRequestGps.
  ///
  /// In en, this message translates to:
  /// **'Request GPS at each clock event'**
  String get restaurantAttendanceRequestGps;

  /// No description provided for @restaurantAttendanceGpsDescription.
  ///
  /// In en, this message translates to:
  /// **'Location is checked only when clocking in or out; there is no continuous tracking.'**
  String get restaurantAttendanceGpsDescription;

  /// No description provided for @restaurantAttendanceSaveFeatures.
  ///
  /// In en, this message translates to:
  /// **'Save features'**
  String get restaurantAttendanceSaveFeatures;

  /// No description provided for @restaurantAttendanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Attendance features updated.'**
  String get restaurantAttendanceSaved;

  /// No description provided for @restaurantAttendanceSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save configuration: {error}'**
  String restaurantAttendanceSaveError(String error);

  /// No description provided for @restaurantStructureName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get restaurantStructureName;

  /// No description provided for @restaurantStructureSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get restaurantStructureSave;

  /// No description provided for @restaurantEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity evidence'**
  String get restaurantEvidenceTitle;

  /// No description provided for @restaurantEvidenceCameraMissing.
  ///
  /// In en, this message translates to:
  /// **'No camera was found.'**
  String get restaurantEvidenceCameraMissing;

  /// No description provided for @restaurantEvidenceCameraOpenError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the camera.'**
  String get restaurantEvidenceCameraOpenError;

  /// No description provided for @restaurantEvidencePhotoSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the photo. Try again.'**
  String get restaurantEvidencePhotoSaveError;

  /// No description provided for @restaurantEvidenceSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get restaurantEvidenceSaving;

  /// No description provided for @restaurantEvidenceTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get restaurantEvidenceTakePhoto;

  /// No description provided for @restaurantSyncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get restaurantSyncOffline;

  /// No description provided for @restaurantSyncOfflinePending.
  ///
  /// In en, this message translates to:
  /// **'Offline, {count} records pending'**
  String restaurantSyncOfflinePending(int count);

  /// No description provided for @restaurantSyncAttentionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record needs attention} other{{count} records need attention}}'**
  String restaurantSyncAttentionCount(int count);

  /// No description provided for @restaurantSyncPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record pending sync} other{{count} records pending sync}}'**
  String restaurantSyncPendingCount(int count);

  /// No description provided for @restaurantSyncAllDone.
  ///
  /// In en, this message translates to:
  /// **'Everything is synced'**
  String get restaurantSyncAllDone;

  /// No description provided for @restaurantSyncTooltip.
  ///
  /// In en, this message translates to:
  /// **'{status}. Tap to sync now.'**
  String restaurantSyncTooltip(String status);

  /// No description provided for @restaurantSyncStarted.
  ///
  /// In en, this message translates to:
  /// **'Sync of pending records started.'**
  String get restaurantSyncStarted;

  /// No description provided for @restaurantSyncOfflineSaved.
  ///
  /// In en, this message translates to:
  /// **'Offline; records remain saved on this phone.'**
  String get restaurantSyncOfflineSaved;

  /// No description provided for @restaurantSyncFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not sync now. Records remain saved on this phone.'**
  String get restaurantSyncFailure;

  /// No description provided for @restaurantSyncRetryQueued.
  ///
  /// In en, this message translates to:
  /// **'The record was returned to the sync queue.'**
  String get restaurantSyncRetryQueued;

  /// No description provided for @restaurantSyncRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not retry yet. The record remains saved on this phone.'**
  String get restaurantSyncRetryFailed;

  /// No description provided for @restaurantSyncEventClock.
  ///
  /// In en, this message translates to:
  /// **'Time clock: clock-in or clock-out'**
  String get restaurantSyncEventClock;

  /// No description provided for @restaurantSyncEventOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations record'**
  String get restaurantSyncEventOperations;

  /// No description provided for @restaurantSyncEventClockEvent.
  ///
  /// In en, this message translates to:
  /// **'Clock-in or clock-out'**
  String get restaurantSyncEventClockEvent;

  /// No description provided for @restaurantSyncEventEvidence.
  ///
  /// In en, this message translates to:
  /// **'Photo evidence'**
  String get restaurantSyncEventEvidence;

  /// No description provided for @restaurantSyncEventPending.
  ///
  /// In en, this message translates to:
  /// **'Pending record'**
  String get restaurantSyncEventPending;

  /// No description provided for @restaurantSyncAttentionNotice.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record needs attention} other{{count} records need attention}}'**
  String restaurantSyncAttentionNotice(int count);

  /// No description provided for @restaurantSyncAttentionHelp.
  ///
  /// In en, this message translates to:
  /// **'These records are saved on this phone. Retry when connected. If a record belongs to another account, sign in with that account.'**
  String get restaurantSyncAttentionHelp;

  /// No description provided for @restaurantSyncRequiresOriginalAccount.
  ///
  /// In en, this message translates to:
  /// **'Requires the original account'**
  String get restaurantSyncRequiresOriginalAccount;

  /// No description provided for @restaurantSyncRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get restaurantSyncRetry;

  /// No description provided for @restaurantOpsShiftTitle.
  ///
  /// In en, this message translates to:
  /// **'My shift'**
  String get restaurantOpsShiftTitle;

  /// No description provided for @restaurantOpsWasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Waste bin review'**
  String get restaurantOpsWasteTitle;

  /// No description provided for @restaurantOpsIncidentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Incidents'**
  String get restaurantOpsIncidentsTitle;

  /// No description provided for @restaurantOpsHandoffTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift handoff'**
  String get restaurantOpsHandoffTitle;

  /// No description provided for @restaurantOpsBranchesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your branches.'**
  String get restaurantOpsBranchesLoadError;

  /// No description provided for @restaurantOpsShiftLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the shift.'**
  String get restaurantOpsShiftLoadError;

  /// No description provided for @restaurantOpsBranchFallback.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get restaurantOpsBranchFallback;

  /// No description provided for @restaurantOpsOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Showing the last saved operation'**
  String get restaurantOpsOfflineTitle;

  /// No description provided for @restaurantOpsOfflinePendingChanges.
  ///
  /// In en, this message translates to:
  /// **'New changes will stay on this phone until the connection returns.'**
  String get restaurantOpsOfflinePendingChanges;

  /// No description provided for @restaurantOpsOfflineSnapshotAt.
  ///
  /// In en, this message translates to:
  /// **'Snapshot from {time}. New changes will stay on this phone until the connection returns.'**
  String restaurantOpsOfflineSnapshotAt(String time);

  /// No description provided for @restaurantOpsSavedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. It will sync when the connection returns.'**
  String get restaurantOpsSavedOffline;

  /// No description provided for @restaurantOpsSaved.
  ///
  /// In en, this message translates to:
  /// **'Done. Your change was saved.'**
  String get restaurantOpsSaved;

  /// No description provided for @restaurantOpsHandoffDelivered.
  ///
  /// In en, this message translates to:
  /// **'The handoff was saved with the current shift status.'**
  String get restaurantOpsHandoffDelivered;

  /// No description provided for @restaurantOpsSwitchBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch branch'**
  String get restaurantOpsSwitchBranch;

  /// No description provided for @restaurantOpsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get restaurantOpsRefresh;

  /// No description provided for @restaurantOpsPauseTitle.
  ///
  /// In en, this message translates to:
  /// **'Pause activity'**
  String get restaurantOpsPauseTitle;

  /// No description provided for @restaurantOpsPauseOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Optional note for the next shift'**
  String get restaurantOpsPauseOptionalNote;

  /// No description provided for @restaurantOpsPauseContinue.
  ///
  /// In en, this message translates to:
  /// **'Keep working'**
  String get restaurantOpsPauseContinue;

  /// No description provided for @restaurantOpsPauseAction.
  ///
  /// In en, this message translates to:
  /// **'Pause activity'**
  String get restaurantOpsPauseAction;

  /// No description provided for @restaurantOpsPauseHint.
  ///
  /// In en, this message translates to:
  /// **'Operational context for the person who resumes the activity'**
  String get restaurantOpsPauseHint;

  /// No description provided for @restaurantOpsNoUpcomingShifts.
  ///
  /// In en, this message translates to:
  /// **'No shifts have been published for the next two weeks.'**
  String get restaurantOpsNoUpcomingShifts;

  /// No description provided for @restaurantOpsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get restaurantOpsToday;

  /// No description provided for @restaurantOpsTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get restaurantOpsTomorrow;

  /// No description provided for @restaurantOpsCalendarDescription.
  ///
  /// In en, this message translates to:
  /// **'View the branch\'s scheduled activities.'**
  String get restaurantOpsCalendarDescription;

  /// No description provided for @restaurantOpsCustomerService.
  ///
  /// In en, this message translates to:
  /// **'I am serving a customer'**
  String get restaurantOpsCustomerService;

  /// No description provided for @restaurantOpsInterruptibleWait.
  ///
  /// In en, this message translates to:
  /// **'Interruptible tasks will wait.'**
  String get restaurantOpsInterruptibleWait;

  /// No description provided for @restaurantOpsOwnActivities.
  ///
  /// In en, this message translates to:
  /// **'Your activities'**
  String get restaurantOpsOwnActivities;

  /// No description provided for @restaurantOpsNoOwnActivities.
  ///
  /// In en, this message translates to:
  /// **'You have no activities assigned for this shift.'**
  String get restaurantOpsNoOwnActivities;

  /// No description provided for @restaurantOpsBranchStructureDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure this branch\'s operational structure.'**
  String get restaurantOpsBranchStructureDescription;

  /// No description provided for @restaurantOpsTeamDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage branch access, roles, and positions.'**
  String get restaurantOpsTeamDescription;

  /// No description provided for @restaurantOpsShiftAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage shifts, breaks, and team publishing.'**
  String get restaurantOpsShiftAdminDescription;

  /// No description provided for @restaurantOpsPendingAbsences.
  ///
  /// In en, this message translates to:
  /// **'Pending requests'**
  String get restaurantOpsPendingAbsences;

  /// No description provided for @restaurantOpsAbsenceReviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Review, approve, or reject team requests.'**
  String get restaurantOpsAbsenceReviewDescription;

  /// No description provided for @restaurantOpsTaskPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Change saved on this phone; waiting to sync.'**
  String get restaurantOpsTaskPendingSync;

  /// No description provided for @restaurantOpsPauseReason.
  ///
  /// In en, this message translates to:
  /// **'Pause reason: {note}'**
  String restaurantOpsPauseReason(String note);

  /// No description provided for @restaurantOpsAssigneeNamed.
  ///
  /// In en, this message translates to:
  /// **'Assignee: {name}'**
  String restaurantOpsAssigneeNamed(String name);

  /// No description provided for @restaurantOpsZoneFallback.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get restaurantOpsZoneFallback;

  /// No description provided for @restaurantOpsYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get restaurantOpsYou;

  /// No description provided for @restaurantOpsActionClaim.
  ///
  /// In en, this message translates to:
  /// **'Take task'**
  String get restaurantOpsActionClaim;

  /// No description provided for @restaurantOpsActionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get restaurantOpsActionStart;

  /// No description provided for @restaurantOpsActionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get restaurantOpsActionPause;

  /// No description provided for @restaurantOpsActionComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get restaurantOpsActionComplete;

  /// No description provided for @restaurantOpsActionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get restaurantOpsActionResume;

  /// No description provided for @restaurantOpsAbsencePendingNote.
  ///
  /// In en, this message translates to:
  /// **'The request will remain pending until a supervisor reviews it.'**
  String get restaurantOpsAbsencePendingNote;

  /// No description provided for @restaurantOpsDateFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get restaurantOpsDateFrom;

  /// No description provided for @restaurantOpsDateUntil.
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get restaurantOpsDateUntil;

  /// No description provided for @restaurantOpsOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Optional note'**
  String get restaurantOpsOptionalNote;

  /// No description provided for @restaurantOpsAbsenceSend.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get restaurantOpsAbsenceSend;

  /// No description provided for @restaurantOpsAbsenceSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get restaurantOpsAbsenceSending;

  /// No description provided for @restaurantOpsAbsenceOfflineNote.
  ///
  /// In en, this message translates to:
  /// **'Offline, the request is saved to sync later.'**
  String get restaurantOpsAbsenceOfflineNote;

  /// No description provided for @restaurantOpsSavedAbsencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests saved on this phone'**
  String get restaurantOpsSavedAbsencesTitle;

  /// No description provided for @restaurantOpsSyncReviewNeeded.
  ///
  /// In en, this message translates to:
  /// **'Review sync status'**
  String get restaurantOpsSyncReviewNeeded;

  /// No description provided for @restaurantOpsPendingSend.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get restaurantOpsPendingSend;

  /// No description provided for @restaurantOpsUnassignedSection.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get restaurantOpsUnassignedSection;

  /// No description provided for @restaurantOpsAbsenceStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Not approved'**
  String get restaurantOpsAbsenceStatusDenied;

  /// No description provided for @restaurantOpsWasteIntro.
  ///
  /// In en, this message translates to:
  /// **'One check records the declared state of each bin.'**
  String get restaurantOpsWasteIntro;

  /// No description provided for @restaurantOpsWasteNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'A local review needs attention in Sync. Do not submit another until it is resolved.'**
  String get restaurantOpsWasteNeedsAttention;

  /// No description provided for @restaurantOpsWastePendingSync.
  ///
  /// In en, this message translates to:
  /// **'Review saved on this phone; it will sync when the connection returns.'**
  String get restaurantOpsWastePendingSync;

  /// No description provided for @restaurantOpsWasteStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Bin status'**
  String get restaurantOpsWasteStatusTitle;

  /// No description provided for @restaurantOpsBinFallback.
  ///
  /// In en, this message translates to:
  /// **'Bin'**
  String get restaurantOpsBinFallback;

  /// No description provided for @restaurantOpsIntervalConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured interval: {minutes} min'**
  String restaurantOpsIntervalConfigured(String minutes);

  /// No description provided for @restaurantOpsInspectionDue.
  ///
  /// In en, this message translates to:
  /// **'Inspection due based on the configured interval.'**
  String get restaurantOpsInspectionDue;

  /// No description provided for @restaurantOpsWasteNeedsPolicy.
  ///
  /// In en, this message translates to:
  /// **'Configure the resulting task before recording this bin as full.'**
  String get restaurantOpsWasteNeedsPolicy;

  /// No description provided for @restaurantOpsDeclaredState.
  ///
  /// In en, this message translates to:
  /// **'Declared state'**
  String get restaurantOpsDeclaredState;

  /// No description provided for @restaurantOpsSelectState.
  ///
  /// In en, this message translates to:
  /// **'Select a state'**
  String get restaurantOpsSelectState;

  /// No description provided for @restaurantOpsBinLow.
  ///
  /// In en, this message translates to:
  /// **'Empty or low'**
  String get restaurantOpsBinLow;

  /// No description provided for @restaurantOpsBinHalf.
  ///
  /// In en, this message translates to:
  /// **'Half full'**
  String get restaurantOpsBinHalf;

  /// No description provided for @restaurantOpsBinFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get restaurantOpsBinFull;

  /// No description provided for @restaurantOpsCannotSaveFullBin.
  ///
  /// In en, this message translates to:
  /// **'Cannot save the inspection: configure the task name, duration, difficulty, and priority for a full bin.'**
  String get restaurantOpsCannotSaveFullBin;

  /// No description provided for @restaurantOpsWastePendingAction.
  ///
  /// In en, this message translates to:
  /// **'Review waiting to sync'**
  String get restaurantOpsWastePendingAction;

  /// No description provided for @restaurantOpsSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get restaurantOpsSaving;

  /// No description provided for @restaurantOpsWasteSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get restaurantOpsWasteSubmit;

  /// No description provided for @restaurantOpsAreaInspectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inspections for other areas'**
  String get restaurantOpsAreaInspectionsTitle;

  /// No description provided for @restaurantOpsNoInspectionTemplates.
  ///
  /// In en, this message translates to:
  /// **'No inspection checklists are configured for this branch.'**
  String get restaurantOpsNoInspectionTemplates;

  /// No description provided for @restaurantOpsInspectionFallback.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get restaurantOpsInspectionFallback;

  /// No description provided for @restaurantOpsInspectionCriteriaCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 configured criterion} other{{count} configured criteria}}'**
  String restaurantOpsInspectionCriteriaCount(int count);

  /// No description provided for @restaurantOpsInspectionInterval.
  ///
  /// In en, this message translates to:
  /// **'Every {minutes} min'**
  String restaurantOpsInspectionInterval(String minutes);

  /// No description provided for @restaurantOpsInspectionNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'A local inspection needs attention in Sync.'**
  String get restaurantOpsInspectionNeedsAttention;

  /// No description provided for @restaurantOpsInspectionPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Inspection saved on this phone; {count, plural, =1{1 criterion is} other{{count} criteria are}} marked for review.'**
  String restaurantOpsInspectionPendingSync(int count);

  /// No description provided for @restaurantOpsDoInspection.
  ///
  /// In en, this message translates to:
  /// **'Start inspection'**
  String get restaurantOpsDoInspection;

  /// No description provided for @restaurantOpsInspectionPendingAction.
  ///
  /// In en, this message translates to:
  /// **'Inspection waiting to sync'**
  String get restaurantOpsInspectionPendingAction;

  /// No description provided for @restaurantOpsRecentInspections.
  ///
  /// In en, this message translates to:
  /// **'Recent records ({count})'**
  String restaurantOpsRecentInspections(int count);

  /// No description provided for @restaurantOpsTeamFallback.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get restaurantOpsTeamFallback;

  /// No description provided for @restaurantOpsNeedsAttentionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs attention} other{{count} items need attention}}'**
  String restaurantOpsNeedsAttentionCount(int count);

  /// No description provided for @restaurantOpsNoAlerts.
  ///
  /// In en, this message translates to:
  /// **'No alerts'**
  String get restaurantOpsNoAlerts;

  /// No description provided for @restaurantOpsCriterionFallback.
  ///
  /// In en, this message translates to:
  /// **'Criterion'**
  String get restaurantOpsCriterionFallback;

  /// No description provided for @restaurantOpsCriterionNote.
  ///
  /// In en, this message translates to:
  /// **'{label}: {note}'**
  String restaurantOpsCriterionNote(String label, String note);

  /// No description provided for @restaurantOpsIncidentReport.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get restaurantOpsIncidentReport;

  /// No description provided for @restaurantOpsIncidentDescription.
  ///
  /// In en, this message translates to:
  /// **'Brief description'**
  String get restaurantOpsIncidentDescription;

  /// No description provided for @restaurantOpsIncidentAreaOptional.
  ///
  /// In en, this message translates to:
  /// **'Area (optional)'**
  String get restaurantOpsIncidentAreaOptional;

  /// No description provided for @restaurantOpsIncidentNoArea.
  ///
  /// In en, this message translates to:
  /// **'No area'**
  String get restaurantOpsIncidentNoArea;

  /// No description provided for @restaurantOpsUrgency.
  ///
  /// In en, this message translates to:
  /// **'Urgency'**
  String get restaurantOpsUrgency;

  /// No description provided for @restaurantOpsUrgencyLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get restaurantOpsUrgencyLow;

  /// No description provided for @restaurantOpsUrgencyNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get restaurantOpsUrgencyNormal;

  /// No description provided for @restaurantOpsUrgencyHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get restaurantOpsUrgencyHigh;

  /// No description provided for @restaurantOpsUrgencyUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get restaurantOpsUrgencyUrgent;

  /// No description provided for @restaurantOpsIncidentBlocksWork.
  ///
  /// In en, this message translates to:
  /// **'Blocks work'**
  String get restaurantOpsIncidentBlocksWork;

  /// No description provided for @restaurantOpsIncidentSend.
  ///
  /// In en, this message translates to:
  /// **'Send incident'**
  String get restaurantOpsIncidentSend;

  /// No description provided for @restaurantOpsOpenIncidents.
  ///
  /// In en, this message translates to:
  /// **'Open incidents'**
  String get restaurantOpsOpenIncidents;

  /// No description provided for @restaurantOpsNoOpenIncidents.
  ///
  /// In en, this message translates to:
  /// **'There are no open incidents.'**
  String get restaurantOpsNoOpenIncidents;

  /// No description provided for @restaurantOpsSavedIncidentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone'**
  String get restaurantOpsSavedIncidentsTitle;

  /// No description provided for @restaurantOpsIncidentFallback.
  ///
  /// In en, this message translates to:
  /// **'Incident'**
  String get restaurantOpsIncidentFallback;

  /// No description provided for @restaurantOpsIncidentNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Review sync status'**
  String get restaurantOpsIncidentNeedsAttention;

  /// No description provided for @restaurantOpsIncidentPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get restaurantOpsIncidentPendingSync;

  /// No description provided for @restaurantOpsIncidentBlockingUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Reported as blocking; not yet confirmed by the server.'**
  String get restaurantOpsIncidentBlockingUnconfirmed;

  /// No description provided for @restaurantOpsIncidentStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get restaurantOpsIncidentStatusOpen;

  /// No description provided for @restaurantOpsIncidentStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get restaurantOpsIncidentStatusInProgress;

  /// No description provided for @restaurantOpsIncidentStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get restaurantOpsIncidentStatusResolved;

  /// No description provided for @restaurantOpsHandoffSummary.
  ///
  /// In en, this message translates to:
  /// **'Automatic shift summary. No need to rewrite reports.'**
  String get restaurantOpsHandoffSummary;

  /// No description provided for @restaurantOpsHandoffCompletedCount.
  ///
  /// In en, this message translates to:
  /// **'Completed ({count})'**
  String restaurantOpsHandoffCompletedCount(int count);

  /// No description provided for @restaurantOpsHandoffNoCompleted.
  ///
  /// In en, this message translates to:
  /// **'No activities completed today yet.'**
  String get restaurantOpsHandoffNoCompleted;

  /// No description provided for @restaurantOpsHandoffOutstandingCount.
  ///
  /// In en, this message translates to:
  /// **'Pending or paused ({count})'**
  String restaurantOpsHandoffOutstandingCount(int count);

  /// No description provided for @restaurantOpsHandoffNoOutstanding.
  ///
  /// In en, this message translates to:
  /// **'No activities are pending.'**
  String get restaurantOpsHandoffNoOutstanding;

  /// No description provided for @restaurantOpsHandoffIncidentCount.
  ///
  /// In en, this message translates to:
  /// **'Open incidents ({count})'**
  String restaurantOpsHandoffIncidentCount(int count);

  /// No description provided for @restaurantOpsHandoffDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift handoff and receipt'**
  String get restaurantOpsHandoffDeliveryTitle;

  /// No description provided for @restaurantOpsHandoffSnapshotNote.
  ///
  /// In en, this message translates to:
  /// **'A snapshot of pending activities and open incidents will be saved when you hand off the shift.'**
  String get restaurantOpsHandoffSnapshotNote;

  /// No description provided for @restaurantOpsHandoffRecipient.
  ///
  /// In en, this message translates to:
  /// **'Handoff recipient'**
  String get restaurantOpsHandoffRecipient;

  /// No description provided for @restaurantOpsHandoffNoRecipient.
  ///
  /// In en, this message translates to:
  /// **'No specific recipient'**
  String get restaurantOpsHandoffNoRecipient;

  /// No description provided for @restaurantOpsHandoffMemberFallback.
  ///
  /// In en, this message translates to:
  /// **'Branch member'**
  String get restaurantOpsHandoffMemberFallback;

  /// No description provided for @restaurantOpsHandoffNote.
  ///
  /// In en, this message translates to:
  /// **'Handoff note (optional)'**
  String get restaurantOpsHandoffNote;

  /// No description provided for @restaurantOpsHandoffNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Operational details that help continue the shift'**
  String get restaurantOpsHandoffNoteHint;

  /// No description provided for @restaurantOpsHandoffDeliver.
  ///
  /// In en, this message translates to:
  /// **'Deliver handoff'**
  String get restaurantOpsHandoffDeliver;

  /// No description provided for @restaurantOpsHandoffConnectionRequired.
  ///
  /// In en, this message translates to:
  /// **'A connection is required to save the actual shift snapshot.'**
  String get restaurantOpsHandoffConnectionRequired;

  /// No description provided for @restaurantOpsRecentHandoffs.
  ///
  /// In en, this message translates to:
  /// **'Recent handoffs ({count})'**
  String restaurantOpsRecentHandoffs(int count);

  /// No description provided for @restaurantOpsNoHandoffs.
  ///
  /// In en, this message translates to:
  /// **'No handoffs have been recorded yet.'**
  String get restaurantOpsNoHandoffs;

  /// No description provided for @restaurantOpsHandoffReceivedBy.
  ///
  /// In en, this message translates to:
  /// **'Received by {name}'**
  String restaurantOpsHandoffReceivedBy(String name);

  /// No description provided for @restaurantOpsHandoffPendingTeam.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the team to receive'**
  String get restaurantOpsHandoffPendingTeam;

  /// No description provided for @restaurantOpsHandoffPendingRecipient.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name} to receive'**
  String restaurantOpsHandoffPendingRecipient(String name);

  /// No description provided for @restaurantOpsHandoffAckNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Saved confirmation needs attention in Sync.'**
  String get restaurantOpsHandoffAckNeedsAttention;

  /// No description provided for @restaurantOpsHandoffAckPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Confirmation saved on this phone; waiting to sync.'**
  String get restaurantOpsHandoffAckPendingSync;

  /// No description provided for @restaurantOpsHandoffSnapshotSummary.
  ///
  /// In en, this message translates to:
  /// **'At handoff: {tasks} pending activities · {incidents} open incidents'**
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents);

  /// No description provided for @restaurantOpsHandoffPausePrefix.
  ///
  /// In en, this message translates to:
  /// **'Pause: {note}'**
  String restaurantOpsHandoffPausePrefix(String note);

  /// No description provided for @restaurantOpsHandoffIncidentDescription.
  ///
  /// In en, this message translates to:
  /// **'Incident: {description}'**
  String restaurantOpsHandoffIncidentDescription(String description);

  /// No description provided for @restaurantOpsHandoffConfirmReceipt.
  ///
  /// In en, this message translates to:
  /// **'Confirm receipt'**
  String get restaurantOpsHandoffConfirmReceipt;

  /// No description provided for @restaurantOpsNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get restaurantOpsNoDescription;

  /// No description provided for @restaurantOpsIncidentFollowupTitle.
  ///
  /// In en, this message translates to:
  /// **'Incident follow-up'**
  String get restaurantOpsIncidentFollowupTitle;

  /// No description provided for @restaurantOpsIncidentStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get restaurantOpsIncidentStatusLabel;

  /// No description provided for @restaurantOpsIncidentFollowupNote.
  ///
  /// In en, this message translates to:
  /// **'Follow-up note (optional)'**
  String get restaurantOpsIncidentFollowupNote;

  /// No description provided for @restaurantOpsIncidentSaveFollowup.
  ///
  /// In en, this message translates to:
  /// **'Save follow-up'**
  String get restaurantOpsIncidentSaveFollowup;

  /// No description provided for @restaurantOpsBranchNotConfiguredTitle.
  ///
  /// In en, this message translates to:
  /// **'Your branch is not configured yet'**
  String get restaurantOpsBranchNotConfiguredTitle;

  /// No description provided for @restaurantOpsBranchNotConfiguredMessage.
  ///
  /// In en, this message translates to:
  /// **'Ask an administrator to create a branch and add you. If you have administrator access, you can create it here.'**
  String get restaurantOpsBranchNotConfiguredMessage;

  /// No description provided for @restaurantOpsBranchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get restaurantOpsBranchName;

  /// No description provided for @restaurantOpsBranchTimeZone.
  ///
  /// In en, this message translates to:
  /// **'Branch time zone'**
  String get restaurantOpsBranchTimeZone;

  /// No description provided for @restaurantOpsBranchCreate.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get restaurantOpsBranchCreate;

  /// No description provided for @restaurantOpsBranchCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get restaurantOpsBranchCreating;
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

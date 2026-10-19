// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FieldOps AI';

  @override
  String get signIn => 'Sign in to worker app';

  @override
  String get signOut => 'Sign out';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get emailRequired => 'Email is required.';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get passwordRequired => 'Password is required.';

  @override
  String get signInFailed =>
      'Sign-in failed. Check your credentials and connection, then try again.';

  @override
  String get assignedJobs => 'Assigned jobs';

  @override
  String get noJobsYet => 'No assigned jobs yet';

  @override
  String get pullToRefresh =>
      'Pull to refresh after a supervisor assigns work.';

  @override
  String get clockIn => 'Clock in';

  @override
  String get clockOut => 'Clock out';

  @override
  String get clockedIn => 'Clocked in';

  @override
  String get readyToClockIn => 'Ready to clock in';

  @override
  String get startBreak => 'Start Break';

  @override
  String get endBreak => 'End Break';

  @override
  String get onBreak => 'On break';

  @override
  String get requestOT => 'Request OT';

  @override
  String get takePhoto => 'Photo';

  @override
  String tasks(int count) {
    return '$count tasks';
  }

  @override
  String get taskChecklist => 'Task checklist';

  @override
  String get proofPhoto => 'Proof photo';

  @override
  String get beforePhoto => 'BEFORE photo';

  @override
  String get afterPhoto => 'AFTER photo';

  @override
  String get capturing => 'Capturing...';

  @override
  String get uploading => 'Uploading proof photo...';

  @override
  String get finalizing => 'Finalizing...';

  @override
  String get photoUploaded => 'Photo uploaded successfully';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get offline => 'Offline';

  @override
  String eventsQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events queued',
      one: '1 event queued',
    );
    return '$_temp0';
  }

  @override
  String get submitOTRequest => 'Submit OT Request';

  @override
  String get overtimeAlert => 'You are entering overtime';

  @override
  String get hoursWorked => 'Hours worked so far';

  @override
  String get reasonForOvertime => 'Reason for overtime';

  @override
  String get mySchedule => 'My schedule';

  @override
  String get upcomingShifts => 'Upcoming shifts';

  @override
  String get scheduleHelp =>
      'Published shifts for the next two weeks. Pull to refresh if a supervisor updates your schedule.';

  @override
  String get updated => 'Updated';

  @override
  String get noScheduledShiftsYet => 'No scheduled shifts yet';

  @override
  String get scheduleWillAppear =>
      'Published shifts will appear here when your supervisor sends the schedule.';

  @override
  String get scheduleUnavailable => 'Schedule unavailable';
}

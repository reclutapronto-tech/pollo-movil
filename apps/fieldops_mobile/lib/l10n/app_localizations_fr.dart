// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'FieldOps AI';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Déconnexion';

  @override
  String get email => 'Email';

  @override
  String get password => 'Mot de passe';

  @override
  String get emailRequired => 'L\'email est requis.';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get passwordRequired => 'Le mot de passe est requis.';

  @override
  String get signInFailed =>
      'Sign-in failed. Check your credentials and connection, then try again.';

  @override
  String get assignedJobs => 'Missions assignées';

  @override
  String get noJobsYet => 'No assigned jobs yet';

  @override
  String get pullToRefresh =>
      'Pull to refresh after a supervisor assigns work.';

  @override
  String get clockIn => 'Pointer entrée';

  @override
  String get clockOut => 'Pointer sortie';

  @override
  String get clockedIn => 'En service';

  @override
  String get readyToClockIn => 'Prêt à pointer';

  @override
  String get startBreak => 'Début pause';

  @override
  String get endBreak => 'Fin pause';

  @override
  String get onBreak => 'En pause';

  @override
  String get requestOT => 'Demander heures sup.';

  @override
  String get takePhoto => 'Photo';

  @override
  String tasks(int count) {
    return '$count tasks';
  }

  @override
  String get taskChecklist => 'Task checklist';

  @override
  String get proofPhoto => 'Photo preuve';

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
  String get retry => 'Réessayer';

  @override
  String get cancel => 'Annuler';

  @override
  String get offline => 'Hors ligne';

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

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pollo Móvil';

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

  @override
  String get restaurantClockTitle => 'Time clock';

  @override
  String get restaurantClockGpsServiceOff =>
      'Turn on location services to record attendance.';

  @override
  String get restaurantClockGpsPermissionRequired =>
      'Location permission is required because this branch enabled it for the time clock.';

  @override
  String get restaurantClockGpsLocationUnavailable =>
      'Couldn\'t get your location. Check location services and try again.';

  @override
  String restaurantClockQueued(String branch) {
    return 'Your record for $branch is saved on this phone and will sync when the connection returns.';
  }

  @override
  String restaurantClockEntrySaved(String branch) {
    return 'Clock-in recorded at $branch.';
  }

  @override
  String restaurantClockExitSaved(String branch) {
    return 'Clock-out recorded at $branch.';
  }

  @override
  String get restaurantClockSaving => 'Saving…';

  @override
  String get restaurantClockActive => 'You have an active clock-in.';

  @override
  String get restaurantClockInactive => 'No active clock-in.';

  @override
  String restaurantClockEntryTime(String time) {
    return 'Clock-in: $time';
  }

  @override
  String get restaurantClockPendingSync =>
      'A time record is saved on this phone and waiting to sync.';

  @override
  String get restaurantClockActiveEntries => 'Active clock-ins';

  @override
  String get restaurantClockNoActiveEntries =>
      'No team members are currently clocked in.';

  @override
  String get restaurantClockUnavailableTime => 'Time unavailable';

  @override
  String get restaurantClockTeamMember => 'Team member';

  @override
  String restaurantClockEntryAt(String time) {
    return 'Clocked in at $time';
  }

  @override
  String get restaurantClockActivePrivacy =>
      'Only active clock-in status is shown; background location is not used.';

  @override
  String get restaurantClockTodayAttendance => 'Today\'s attendance';

  @override
  String get restaurantClockNoBranchEntries =>
      'There are no clock-in records for this branch yet today.';

  @override
  String get restaurantClockEntry => 'Clock-in';

  @override
  String restaurantClockEntryForDate(String date) {
    return 'Clock-in ($date)';
  }

  @override
  String get restaurantClockNoExit => 'no clock-out';

  @override
  String restaurantClockExitAt(String time) {
    return 'clock-out $time';
  }

  @override
  String restaurantClockSessionSummary(
    String entry,
    String start,
    String exit,
  ) {
    return '$entry $start · $exit';
  }

  @override
  String get restaurantClockAttendancePrivacy =>
      'Only today\'s attendance is shown; this summary does not include locations.';

  @override
  String get restaurantClockMyAttendance => 'My records today';

  @override
  String get restaurantClockNoMyEntriesToday =>
      'You do not have any clock-in records today yet.';

  @override
  String get restaurantClockMyPrivacy =>
      'This summary shows only your time records and does not display locations.';

  @override
  String get restaurantClockToday => 'Today';

  @override
  String get restaurantClockPreviousDate => 'Previous date';

  @override
  String get restaurantClockGpsRequired =>
      'This branch requests location when you clock in or out. The app does not collect location in the background.';

  @override
  String get restaurantClockGpsNotRequired =>
      'The time clock is active without collecting location. Background location is not used.';

  @override
  String get restaurantClockNoPayroll =>
      'This record documents operational attendance; it does not calculate payroll.';

  @override
  String get restaurantMoreTitle => 'More';

  @override
  String get restaurantAccount => 'Pollo Móvil account';

  @override
  String get restaurantAssignedBranchAccess =>
      'Secure access to your assigned branch';

  @override
  String get restaurantMoreDescription =>
      'Pollo Móvil coordinates activities, inspections, incidents, and shift handoffs. Location is not collected in the background.';

  @override
  String get restaurantNotificationsThisDevice =>
      'Notifications on this device';

  @override
  String get restaurantPushOperationalUpdates =>
      'Push alerts for activities and operational changes.';

  @override
  String get restaurantPushRequiresSetup =>
      'Push notifications are available after Firebase and this platform\'s notification setup are complete.';

  @override
  String get restaurantPushEnableFailed =>
      'Could not enable notifications. Check this phone\'s notification permission and the Firebase mobile configuration.';

  @override
  String get restaurantNotificationView => 'View';

  @override
  String get restaurantSignOutPendingEvents =>
      'Events queued for synchronization remain on this phone.';

  @override
  String get restaurantOperationalAppLabel => 'Pollo Móvil · operations app';

  @override
  String get restaurantNotificationsTitle => 'Notifications';

  @override
  String get restaurantNotificationsQueuedRead =>
      'The inbox will refresh when the connection returns.';

  @override
  String get restaurantNotificationsMarkAllRead => 'Mark all read';

  @override
  String restaurantNotificationsLoadError(String error) {
    return 'Could not load notifications. $error';
  }

  @override
  String get restaurantNotificationsOfflineEmpty =>
      'The saved copy has no notifications. Connect to refresh your inbox.';

  @override
  String get restaurantNotificationsEmpty =>
      'You don\'t have any notifications yet.';

  @override
  String get restaurantNotificationsOfflineTitle => 'Inbox saved offline';

  @override
  String get restaurantNotificationsOfflineBody =>
      'Its state may have changed since the last update.';

  @override
  String get restaurantNotificationFallbackTitle => 'Notification';

  @override
  String get restaurantNotificationReadPending => 'Read status waiting to sync';

  @override
  String get restaurantNotificationMarkRead => 'Mark as read';

  @override
  String get restaurantInspectionQueued =>
      'Inspection saved on this phone and will sync when the connection returns.';

  @override
  String get restaurantInspectionSaved => 'Inspection saved.';

  @override
  String restaurantInspectionNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inspection saved; $count items need attention.',
      one: 'Inspection saved; 1 item needs attention.',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInspectionNoActiveCriteria =>
      'This checklist has no active criteria. Ask an administrator to configure it.';

  @override
  String get restaurantInspectionInstruction =>
      'Record the observed status for each criterion configured by this branch.';

  @override
  String get restaurantInspectionCriterion => 'Criterion';

  @override
  String get restaurantInspectionObservedState => 'Observed status';

  @override
  String get restaurantInspectionResultOk => 'OK';

  @override
  String get restaurantInspectionResultNeedsAttention => 'Needs attention';

  @override
  String get restaurantInspectionResultNotApplicable => 'Not applicable';

  @override
  String get restaurantInspectionOptionalDetail => 'Optional detail';

  @override
  String get restaurantInspectionOptionalGeneralNote =>
      'General note (optional)';

  @override
  String get restaurantInspectionSaving => 'Saving…';

  @override
  String get restaurantInspectionSave => 'Save inspection';

  @override
  String get restaurantInspectionOfflineHelp =>
      'If you\'re offline, the inspection stays on this phone and will be sent when the connection returns.';

  @override
  String get restaurantInspectionDefaultTitle => 'Inspection';

  @override
  String get restaurantShiftScheduleTitle => 'Shift schedule';

  @override
  String get restaurantShiftSaved => 'Shift saved.';

  @override
  String get restaurantShiftUpdated => 'Shift updated.';

  @override
  String restaurantShiftSaveError(String error) {
    return 'Could not save the shift: $error';
  }

  @override
  String get restaurantShiftCancelTitle => 'Cancel shift';

  @override
  String restaurantShiftCancelConfirmation(String employee) {
    return 'Cancel the shift for $employee?';
  }

  @override
  String get restaurantShiftCanceled => 'Shift canceled.';

  @override
  String restaurantShiftCancelError(String error) {
    return 'Could not cancel the shift: $error';
  }

  @override
  String get restaurantShiftLoadError =>
      'Could not load this week\'s schedule.';

  @override
  String get restaurantShiftPreviousWeek => 'Previous week';

  @override
  String get restaurantShiftNextWeek => 'Next week';

  @override
  String get restaurantShiftOfflineNotice =>
      'Offline: showing the last saved schedule. Shift editing will be available when the connection returns.';

  @override
  String restaurantShiftTimezone(String timeZone) {
    return 'Times use the branch\'s local time zone: $timeZone';
  }

  @override
  String get restaurantShiftAdd => 'Add shift';

  @override
  String get restaurantShiftNoShifts => 'No scheduled shifts.';

  @override
  String get restaurantShiftTeamMember => 'Team member';

  @override
  String get restaurantShiftPublished => 'Published';

  @override
  String get restaurantShiftDraft => 'Draft';

  @override
  String restaurantShiftTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String restaurantShiftBreaks(String breaks) {
    return 'Break: $breaks';
  }

  @override
  String get restaurantShiftEdit => 'Edit';

  @override
  String get restaurantShiftCancelAction => 'Cancel shift';

  @override
  String get restaurantShiftAddDialogTitle => 'Add shift';

  @override
  String get restaurantShiftEditDialogTitle => 'Edit shift';

  @override
  String get restaurantShiftEmployee => 'Employee';

  @override
  String get restaurantShiftDay => 'Day';

  @override
  String get restaurantShiftStartChoose => 'Start: choose';

  @override
  String get restaurantShiftEndChoose => 'End: choose';

  @override
  String get restaurantShiftStart => 'Start';

  @override
  String get restaurantShiftEnd => 'End';

  @override
  String get restaurantShiftPublish => 'Publish shift';

  @override
  String get restaurantShiftDraftDescription =>
      'If turned off, the shift is saved as a draft.';

  @override
  String get restaurantShiftBreaksTitle => 'Breaks';

  @override
  String get restaurantShiftAddBreak => 'Add';

  @override
  String get restaurantShiftRemoveBreak => 'Remove break';

  @override
  String get restaurantShiftSave => 'Save';

  @override
  String get restaurantTeamTitle => 'Branch team';

  @override
  String get restaurantTeamUpdated => 'Team member information updated.';

  @override
  String restaurantTeamSaveError(String error) {
    return 'Could not save all changes: $error';
  }

  @override
  String get restaurantInviteDialogTitle => 'Invite employee';

  @override
  String get restaurantInviteLinkTitle => 'Invitation link';

  @override
  String get restaurantInviteAction => 'Invite employee';

  @override
  String get restaurantInviteEmailNotSent =>
      'The email could not be sent automatically. Copy this link and share it with the invited person.';

  @override
  String get restaurantInviteCopied => 'Invitation link copied.';

  @override
  String get restaurantInviteCopyLink => 'Copy link';

  @override
  String get restaurantClose => 'Close';

  @override
  String get restaurantInviteSent => 'Invitation sent.';

  @override
  String get restaurantInviteAlreadyMember =>
      'This person is already a member of this branch.';

  @override
  String get restaurantInviteAccountAdded => 'Account added to the branch.';

  @override
  String restaurantInviteError(String error) {
    return 'Could not invite this person: $error';
  }

  @override
  String get restaurantTeamLoadError => 'Could not load the branch team.';

  @override
  String get restaurantTeamOfflineTitle => 'Showing the last saved team';

  @override
  String get restaurantTeamOfflineBody =>
      'This information is read-only until the connection returns.';

  @override
  String get restaurantTeamEmpty =>
      'This branch does not have any team members yet.';

  @override
  String restaurantTeamMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count team members',
      one: '1 team member',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInviteFullName => 'Full name';

  @override
  String get restaurantInviteEmail => 'Email address';

  @override
  String get restaurantInviteNameValidation => 'Enter the full name.';

  @override
  String get restaurantInvitePermissionNote =>
      'The invitation will be sent to this email address. The new team member will have employee access.';

  @override
  String get restaurantInviteSubmit => 'Send invitation';

  @override
  String get restaurantRoleLabel => 'Branch role';

  @override
  String get restaurantRoleEmployee => 'Employee';

  @override
  String get restaurantRoleSupervisor => 'Supervisor';

  @override
  String get restaurantRoleAdmin => 'Administrator';

  @override
  String get restaurantMemberActive => 'Active';

  @override
  String get restaurantMemberInactive => 'Inactive';

  @override
  String get restaurantMemberAccess => 'Branch access';

  @override
  String get restaurantMemberDeactivateNote =>
      'Deactivating access preserves shift and task history.';

  @override
  String get restaurantMemberPositions => 'Enabled positions';

  @override
  String get restaurantPositionFallback => 'Position';

  @override
  String get restaurantMemberReactivateToEdit =>
      'Reactivate branch access to edit enabled positions.';

  @override
  String get restaurantMemberConfigurePositions =>
      'Configure positions before assigning them to the team.';

  @override
  String get restaurantMemberSaveChanges => 'Save changes';

  @override
  String get restaurantAbsenceReviewTitle => 'Absence requests';

  @override
  String get restaurantAbsenceApproved => 'Request approved.';

  @override
  String get restaurantAbsenceRejected => 'Request rejected.';

  @override
  String restaurantAbsenceReviewError(String error) {
    return 'Could not review the request: $error';
  }

  @override
  String get restaurantAbsenceLoadError => 'Could not load pending requests.';

  @override
  String get restaurantAbsenceNone => 'There are no pending requests.';

  @override
  String get restaurantAbsenceOfflineNotice =>
      'Offline: showing requests from the last update. Approving or rejecting requires a connection.';

  @override
  String get restaurantAbsenceOfflineEmpty =>
      'There were no pending requests in the last update.';

  @override
  String get restaurantAbsenceReject => 'Reject';

  @override
  String get restaurantAbsenceApprove => 'Approve';

  @override
  String get restaurantCalendarTitle => 'Activity calendar';

  @override
  String get restaurantCalendarRefresh => 'Refresh calendar';

  @override
  String get restaurantCalendarLoadError => 'Could not load the calendar.';

  @override
  String get restaurantCalendarRetry => 'Retry';

  @override
  String get restaurantCalendarPreviousWeek => 'Previous week';

  @override
  String get restaurantCalendarNextWeek => 'Next week';

  @override
  String get restaurantCalendarManagerHint =>
      'Only configured activities can be scheduled.';

  @override
  String get restaurantCalendarBranchHint =>
      'Activities assigned to your branch.';

  @override
  String get restaurantCalendarOffline =>
      'Offline: showing the last saved week. Scheduling is read-only until you reconnect.';

  @override
  String get restaurantCalendarRetroactive =>
      'Activities cannot be scheduled retroactively from the calendar.';

  @override
  String restaurantCalendarDayScheduled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new activities',
      one: '1 new activity',
    );
    return '$_temp0 created from branch rules. Existing activities were not duplicated.';
  }

  @override
  String get restaurantCalendarPastWeek =>
      'This week has passed; no dates were changed.';

  @override
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays) {
    String _temp0 = intl.Intl.pluralLogic(
      pastDays,
      locale: localeName,
      other: '$pastDays past dates were skipped',
      one: '1 past date was skipped',
      zero: 'no past dates were skipped',
    );
    return 'Scheduled $created activities across $days dates. Past dates were left unchanged; $_temp0. Existing activities were not duplicated.';
  }

  @override
  String restaurantCalendarWeekPartial(int created, int days, String dates) {
    return 'Scheduled $created activities across $days dates. Could not schedule: $dates. You can retry; existing activities will not be duplicated.';
  }

  @override
  String get restaurantCalendarPlanWeek => 'Schedule visible week';

  @override
  String get restaurantCalendarPlanningWeek => 'Scheduling week…';

  @override
  String restaurantCalendarWeekActivities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activities this week',
      one: '1 activity this week',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarUnassignedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unassigned items',
      one: '1 unassigned item',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count completed',
      one: '1 completed',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarActivityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activities',
      one: '1 activity',
    );
    return '$_temp0';
  }

  @override
  String get restaurantCalendarPastDate =>
      'Past date; activities cannot be scheduled retroactively.';

  @override
  String get restaurantCalendarScheduleFromRules => 'Schedule from rules';

  @override
  String get restaurantCalendarScheduling => 'Scheduling…';

  @override
  String get restaurantCalendarAssignEligible => 'Assign eligible people';

  @override
  String get restaurantCalendarAssigning => 'Assigning…';

  @override
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  ) {
    return '$assigned activities assigned with $planner; $unassigned have no eligible employee.';
  }

  @override
  String get restaurantCalendarLocalPlanner => 'the local planner';

  @override
  String get restaurantCalendarNoActivities => 'No activities scheduled.';

  @override
  String get restaurantCalendarFallbackActivity => 'Activity';

  @override
  String get restaurantCalendarNoAssignee => 'Unassigned';

  @override
  String get restaurantCalendarConfigurationPending =>
      'Configure branch positions, areas, or requirements before assigning this activity.';

  @override
  String get restaurantCalendarAssignee => 'Assignee';

  @override
  String get restaurantCalendarFallbackAssignee => 'Current assignee';

  @override
  String restaurantCalendarInactiveAssignee(String name) {
    return '$name · inactive';
  }

  @override
  String get restaurantCalendarEmployeeFallback => 'Employee';

  @override
  String get restaurantCalendarZoneFallback => 'Part';

  @override
  String restaurantCalendarZoneAssignee(String zone) {
    return 'Assignee for $zone';
  }

  @override
  String get restaurantCalendarStatusPending => 'Pending';

  @override
  String get restaurantCalendarStatusInProgress => 'In progress';

  @override
  String get restaurantCalendarStatusPaused => 'Paused';

  @override
  String get restaurantCalendarStatusBlocked => 'Blocked';

  @override
  String get restaurantCalendarStatusCompleted => 'Completed';

  @override
  String get restaurantCalendarTaskAssigneeUpdated =>
      'Activity assignee updated.';

  @override
  String get restaurantCalendarPartAssigneeUpdated => 'Part assignee updated.';

  @override
  String get restaurantStructureTitle => 'Areas and positions';

  @override
  String get restaurantStructureAreas => 'Areas';

  @override
  String get restaurantStructurePositions => 'Positions';

  @override
  String restaurantStructureAdd(String label) {
    return 'Add $label';
  }

  @override
  String restaurantStructureEdit(String label) {
    return 'Edit $label';
  }

  @override
  String restaurantStructureSaved(String label) {
    return '$label saved.';
  }

  @override
  String restaurantStructureSaveError(String label, String error) {
    return 'Could not save $label: $error';
  }

  @override
  String restaurantStructureReactivateTitle(String label) {
    return 'Reactivate $label';
  }

  @override
  String restaurantStructureDeactivateTitle(String label) {
    return 'Deactivate $label';
  }

  @override
  String get restaurantStructureReactivateDescription =>
      'It can be selected again for new activities.';

  @override
  String get restaurantStructureDeactivateDescription =>
      'It will be hidden from new activities. Existing history will be preserved.';

  @override
  String get restaurantStructureBack => 'Back';

  @override
  String get restaurantStructureReactivateAction => 'Reactivate';

  @override
  String get restaurantStructureDeactivateAction => 'Deactivate';

  @override
  String get restaurantStructureEmpty => 'No items have been configured yet.';

  @override
  String get restaurantStructureStatusActive => 'Status: active';

  @override
  String get restaurantStructureStatusInactive => 'Status: inactive';

  @override
  String restaurantStructureAddTooltip(String label) {
    return 'Add $label';
  }

  @override
  String get restaurantStructureEditName => 'Edit name';

  @override
  String get restaurantStructureOfflineTitle =>
      'Showing the last saved configuration';

  @override
  String get restaurantStructureOfflineBody =>
      'Areas, positions, and features are read-only until the connection returns.';

  @override
  String get restaurantStructureKeepHistory =>
      'Deactivate items instead of deleting them to preserve operational history.';

  @override
  String get restaurantStructureLoadError =>
      'Could not load branch configuration.';

  @override
  String get restaurantStructureRetry => 'Retry';

  @override
  String get restaurantAttendanceTitle => 'Attendance and location';

  @override
  String get restaurantAttendanceOptional =>
      'These features are optional per branch and are off by default.';

  @override
  String get restaurantAttendanceEnableClock => 'Enable time clock';

  @override
  String get restaurantAttendanceClockDescription =>
      'Records clock-in and clock-out. It does not calculate payroll.';

  @override
  String get restaurantAttendanceRequestGps =>
      'Request GPS at each clock event';

  @override
  String get restaurantAttendanceGpsDescription =>
      'Location is checked only when clocking in or out; there is no continuous tracking.';

  @override
  String get restaurantAttendanceSaveFeatures => 'Save features';

  @override
  String get restaurantAttendanceSaved => 'Attendance features updated.';

  @override
  String restaurantAttendanceSaveError(String error) {
    return 'Could not save configuration: $error';
  }

  @override
  String get restaurantStructureName => 'Name';

  @override
  String get restaurantStructureSave => 'Save';

  @override
  String get restaurantEvidenceTitle => 'Activity evidence';

  @override
  String get restaurantEvidenceCameraMissing => 'No camera was found.';

  @override
  String get restaurantEvidenceCameraOpenError => 'Could not open the camera.';

  @override
  String get restaurantEvidencePhotoSaveError =>
      'Could not save the photo. Try again.';

  @override
  String get restaurantEvidenceSaving => 'Saving…';

  @override
  String get restaurantEvidenceTakePhoto => 'Take photo';

  @override
  String get restaurantSyncOffline => 'Offline';

  @override
  String restaurantSyncOfflinePending(int count) {
    return 'Offline, $count records pending';
  }

  @override
  String restaurantSyncAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records need attention',
      one: '1 record needs attention',
    );
    return '$_temp0';
  }

  @override
  String restaurantSyncPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records pending sync',
      one: '1 record pending sync',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAllDone => 'Everything is synced';

  @override
  String restaurantSyncTooltip(String status) {
    return '$status. Tap to sync now.';
  }

  @override
  String get restaurantSyncStarted => 'Sync of pending records started.';

  @override
  String get restaurantSyncOfflineSaved =>
      'Offline; records remain saved on this phone.';

  @override
  String get restaurantSyncFailure =>
      'Could not sync now. Records remain saved on this phone.';

  @override
  String get restaurantSyncRetryQueued =>
      'The record was returned to the sync queue.';

  @override
  String get restaurantSyncRetryFailed =>
      'Could not retry yet. The record remains saved on this phone.';

  @override
  String get restaurantSyncEventClock => 'Time clock: clock-in or clock-out';

  @override
  String get restaurantSyncEventOperations => 'Operations record';

  @override
  String get restaurantSyncEventClockEvent => 'Clock-in or clock-out';

  @override
  String get restaurantSyncEventEvidence => 'Photo evidence';

  @override
  String get restaurantSyncEventPending => 'Pending record';

  @override
  String restaurantSyncAttentionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records need attention',
      one: '1 record needs attention',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAttentionHelp =>
      'These records are saved on this phone. Retry when connected. If a record belongs to another account, sign in with that account.';

  @override
  String get restaurantSyncRequiresOriginalAccount =>
      'Requires the original account';

  @override
  String get restaurantSyncRetry => 'Retry';

  @override
  String get restaurantOpsShiftTitle => 'My shift';

  @override
  String get restaurantOpsWasteTitle => 'Waste bin review';

  @override
  String get restaurantOpsIncidentsTitle => 'Incidents';

  @override
  String get restaurantOpsHandoffTitle => 'Shift handoff';

  @override
  String get restaurantOpsBranchesLoadError => 'Could not load your branches.';

  @override
  String get restaurantOpsShiftLoadError => 'Could not load the shift.';

  @override
  String get restaurantOpsBranchFallback => 'Branch';

  @override
  String get restaurantOpsOfflineTitle => 'Showing the last saved operation';

  @override
  String get restaurantOpsOfflinePendingChanges =>
      'New changes will stay on this phone until the connection returns.';

  @override
  String restaurantOpsOfflineSnapshotAt(String time) {
    return 'Snapshot from $time. New changes will stay on this phone until the connection returns.';
  }

  @override
  String get restaurantOpsSavedOffline =>
      'Saved on this phone. It will sync when the connection returns.';

  @override
  String get restaurantOpsSaved => 'Done. Your change was saved.';

  @override
  String get restaurantOpsHandoffDelivered =>
      'The handoff was saved with the current shift status.';

  @override
  String get restaurantOpsSwitchBranch => 'Switch branch';

  @override
  String get restaurantOpsRefresh => 'Refresh';

  @override
  String get restaurantOpsPauseTitle => 'Pause activity';

  @override
  String get restaurantOpsPauseOptionalNote =>
      'Optional note for the next shift';

  @override
  String get restaurantOpsPauseContinue => 'Keep working';

  @override
  String get restaurantOpsPauseAction => 'Pause activity';

  @override
  String get restaurantOpsPauseHint =>
      'Operational context for the person who resumes the activity';

  @override
  String get restaurantOpsNoUpcomingShifts =>
      'No shifts have been published for the next two weeks.';

  @override
  String get restaurantOpsToday => 'Today';

  @override
  String get restaurantOpsTomorrow => 'Tomorrow';

  @override
  String get restaurantOpsCalendarDescription =>
      'View the branch\'s scheduled activities.';

  @override
  String get restaurantOpsCustomerService => 'I am serving a customer';

  @override
  String get restaurantOpsInterruptibleWait => 'Interruptible tasks will wait.';

  @override
  String get restaurantOpsOwnActivities => 'Your activities';

  @override
  String get restaurantOpsNoOwnActivities =>
      'You have no activities assigned for this shift.';

  @override
  String get restaurantOpsBranchStructureDescription =>
      'Configure this branch\'s operational structure.';

  @override
  String get restaurantOpsTeamDescription =>
      'Manage branch access, roles, and positions.';

  @override
  String get restaurantOpsShiftAdminDescription =>
      'Manage shifts, breaks, and team publishing.';

  @override
  String get restaurantOpsPendingAbsences => 'Pending requests';

  @override
  String get restaurantOpsAbsenceReviewDescription =>
      'Review, approve, or reject team requests.';

  @override
  String get restaurantOpsTaskPendingSync =>
      'Change saved on this phone; waiting to sync.';

  @override
  String restaurantOpsPauseReason(String note) {
    return 'Pause reason: $note';
  }

  @override
  String restaurantOpsAssigneeNamed(String name) {
    return 'Assignee: $name';
  }

  @override
  String get restaurantOpsZoneFallback => 'Zone';

  @override
  String get restaurantOpsYou => 'You';

  @override
  String get restaurantOpsActionClaim => 'Take task';

  @override
  String get restaurantOpsActionStart => 'Start';

  @override
  String get restaurantOpsActionPause => 'Pause';

  @override
  String get restaurantOpsActionComplete => 'Complete';

  @override
  String get restaurantOpsActionResume => 'Resume';

  @override
  String get restaurantOpsAbsencePendingNote =>
      'The request will remain pending until a supervisor reviews it.';

  @override
  String get restaurantOpsDateFrom => 'From';

  @override
  String get restaurantOpsDateUntil => 'Until';

  @override
  String get restaurantOpsOptionalNote => 'Optional note';

  @override
  String get restaurantOpsAbsenceSend => 'Send request';

  @override
  String get restaurantOpsAbsenceSending => 'Sending…';

  @override
  String get restaurantOpsAbsenceOfflineNote =>
      'Offline, the request is saved to sync later.';

  @override
  String get restaurantOpsSavedAbsencesTitle => 'Requests saved on this phone';

  @override
  String get restaurantOpsSyncReviewNeeded => 'Review sync status';

  @override
  String get restaurantOpsPendingSend => 'Waiting to send';

  @override
  String get restaurantOpsUnassignedSection => 'Unassigned';

  @override
  String get restaurantOpsAbsenceStatusDenied => 'Not approved';

  @override
  String get restaurantOpsWasteIntro =>
      'One check records the declared state of each bin.';

  @override
  String get restaurantOpsWasteNeedsAttention =>
      'A local review needs attention in Sync. Do not submit another until it is resolved.';

  @override
  String get restaurantOpsWastePendingSync =>
      'Review saved on this phone; it will sync when the connection returns.';

  @override
  String get restaurantOpsWasteStatusTitle => 'Bin status';

  @override
  String get restaurantOpsBinFallback => 'Bin';

  @override
  String restaurantOpsIntervalConfigured(String minutes) {
    return 'Configured interval: $minutes min';
  }

  @override
  String get restaurantOpsInspectionDue =>
      'Inspection due based on the configured interval.';

  @override
  String get restaurantOpsWasteNeedsPolicy =>
      'Configure the resulting task before recording this bin as full.';

  @override
  String get restaurantOpsDeclaredState => 'Declared state';

  @override
  String get restaurantOpsSelectState => 'Select a state';

  @override
  String get restaurantOpsBinLow => 'Empty or low';

  @override
  String get restaurantOpsBinHalf => 'Half full';

  @override
  String get restaurantOpsBinFull => 'Full';

  @override
  String get restaurantOpsCannotSaveFullBin =>
      'Cannot save the inspection: configure the task name, duration, difficulty, and priority for a full bin.';

  @override
  String get restaurantOpsWastePendingAction => 'Review waiting to sync';

  @override
  String get restaurantOpsSaving => 'Saving…';

  @override
  String get restaurantOpsWasteSubmit => 'Submit review';

  @override
  String get restaurantOpsAreaInspectionsTitle => 'Inspections for other areas';

  @override
  String get restaurantOpsNoInspectionTemplates =>
      'No inspection checklists are configured for this branch.';

  @override
  String get restaurantOpsInspectionFallback => 'Inspection';

  @override
  String restaurantOpsInspectionCriteriaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count configured criteria',
      one: '1 configured criterion',
    );
    return '$_temp0';
  }

  @override
  String restaurantOpsInspectionInterval(String minutes) {
    return 'Every $minutes min';
  }

  @override
  String get restaurantOpsInspectionNeedsAttention =>
      'A local inspection needs attention in Sync.';

  @override
  String restaurantOpsInspectionPendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count criteria are',
      one: '1 criterion is',
    );
    return 'Inspection saved on this phone; $_temp0 marked for review.';
  }

  @override
  String get restaurantOpsDoInspection => 'Start inspection';

  @override
  String get restaurantOpsInspectionPendingAction =>
      'Inspection waiting to sync';

  @override
  String restaurantOpsRecentInspections(int count) {
    return 'Recent records ($count)';
  }

  @override
  String get restaurantOpsTeamFallback => 'Team';

  @override
  String restaurantOpsNeedsAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need attention',
      one: '1 item needs attention',
    );
    return '$_temp0';
  }

  @override
  String get restaurantOpsNoAlerts => 'No alerts';

  @override
  String get restaurantOpsCriterionFallback => 'Criterion';

  @override
  String restaurantOpsCriterionNote(String label, String note) {
    return '$label: $note';
  }

  @override
  String get restaurantOpsIncidentReport => 'Report a problem';

  @override
  String get restaurantOpsIncidentDescription => 'Brief description';

  @override
  String get restaurantOpsIncidentAreaOptional => 'Area (optional)';

  @override
  String get restaurantOpsIncidentNoArea => 'No area';

  @override
  String get restaurantOpsUrgency => 'Urgency';

  @override
  String get restaurantOpsUrgencyLow => 'Low';

  @override
  String get restaurantOpsUrgencyNormal => 'Normal';

  @override
  String get restaurantOpsUrgencyHigh => 'High';

  @override
  String get restaurantOpsUrgencyUrgent => 'Urgent';

  @override
  String get restaurantOpsIncidentBlocksWork => 'Blocks work';

  @override
  String get restaurantOpsIncidentSend => 'Send incident';

  @override
  String get restaurantOpsOpenIncidents => 'Open incidents';

  @override
  String get restaurantOpsNoOpenIncidents => 'There are no open incidents.';

  @override
  String get restaurantOpsSavedIncidentsTitle => 'Saved on this phone';

  @override
  String get restaurantOpsIncidentFallback => 'Incident';

  @override
  String get restaurantOpsIncidentNeedsAttention => 'Review sync status';

  @override
  String get restaurantOpsIncidentPendingSync => 'Waiting to sync';

  @override
  String get restaurantOpsIncidentBlockingUnconfirmed =>
      'Reported as blocking; not yet confirmed by the server.';

  @override
  String get restaurantOpsIncidentStatusOpen => 'Open';

  @override
  String get restaurantOpsIncidentStatusInProgress => 'In progress';

  @override
  String get restaurantOpsIncidentStatusResolved => 'Resolved';

  @override
  String get restaurantOpsHandoffSummary =>
      'Automatic shift summary. No need to rewrite reports.';

  @override
  String restaurantOpsHandoffCompletedCount(int count) {
    return 'Completed ($count)';
  }

  @override
  String get restaurantOpsHandoffNoCompleted =>
      'No activities completed today yet.';

  @override
  String restaurantOpsHandoffOutstandingCount(int count) {
    return 'Pending or paused ($count)';
  }

  @override
  String get restaurantOpsHandoffNoOutstanding => 'No activities are pending.';

  @override
  String restaurantOpsHandoffIncidentCount(int count) {
    return 'Open incidents ($count)';
  }

  @override
  String get restaurantOpsHandoffDeliveryTitle => 'Shift handoff and receipt';

  @override
  String get restaurantOpsHandoffSnapshotNote =>
      'A snapshot of pending activities and open incidents will be saved when you hand off the shift.';

  @override
  String get restaurantOpsHandoffRecipient => 'Handoff recipient';

  @override
  String get restaurantOpsHandoffNoRecipient => 'No specific recipient';

  @override
  String get restaurantOpsHandoffMemberFallback => 'Branch member';

  @override
  String get restaurantOpsHandoffNote => 'Handoff note (optional)';

  @override
  String get restaurantOpsHandoffNoteHint =>
      'Operational details that help continue the shift';

  @override
  String get restaurantOpsHandoffDeliver => 'Deliver handoff';

  @override
  String get restaurantOpsHandoffConnectionRequired =>
      'A connection is required to save the actual shift snapshot.';

  @override
  String restaurantOpsRecentHandoffs(int count) {
    return 'Recent handoffs ($count)';
  }

  @override
  String get restaurantOpsNoHandoffs => 'No handoffs have been recorded yet.';

  @override
  String restaurantOpsHandoffReceivedBy(String name) {
    return 'Received by $name';
  }

  @override
  String get restaurantOpsHandoffPendingTeam =>
      'Waiting for the team to receive';

  @override
  String restaurantOpsHandoffPendingRecipient(String name) {
    return 'Waiting for $name to receive';
  }

  @override
  String get restaurantOpsHandoffAckNeedsAttention =>
      'Saved confirmation needs attention in Sync.';

  @override
  String get restaurantOpsHandoffAckPendingSync =>
      'Confirmation saved on this phone; waiting to sync.';

  @override
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents) {
    return 'At handoff: $tasks pending activities · $incidents open incidents';
  }

  @override
  String restaurantOpsHandoffPausePrefix(String note) {
    return 'Pause: $note';
  }

  @override
  String restaurantOpsHandoffIncidentDescription(String description) {
    return 'Incident: $description';
  }

  @override
  String get restaurantOpsHandoffConfirmReceipt => 'Confirm receipt';

  @override
  String get restaurantOpsNoDescription => 'No description';

  @override
  String get restaurantOpsIncidentFollowupTitle => 'Incident follow-up';

  @override
  String get restaurantOpsIncidentStatusLabel => 'Status';

  @override
  String get restaurantOpsIncidentFollowupNote => 'Follow-up note (optional)';

  @override
  String get restaurantOpsIncidentSaveFollowup => 'Save follow-up';

  @override
  String get restaurantOpsBranchNotConfiguredTitle =>
      'Your branch is not configured yet';

  @override
  String get restaurantOpsBranchNotConfiguredMessage =>
      'Ask an administrator to create a branch and add you. If you have administrator access, you can create it here.';

  @override
  String get restaurantOpsBranchName => 'Branch name';

  @override
  String get restaurantOpsBranchTimeZone => 'Branch time zone';

  @override
  String get restaurantOpsBranchCreate => 'Create branch';

  @override
  String get restaurantOpsBranchCreating => 'Creating…';
}

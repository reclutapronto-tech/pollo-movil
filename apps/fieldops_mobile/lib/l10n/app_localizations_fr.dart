// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Pollo Móvil';

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
  String get emailInvalid => 'Saisissez une adresse e-mail valide.';

  @override
  String get passwordRequired => 'Le mot de passe est requis.';

  @override
  String get signInFailed =>
      'Échec de la connexion. Vérifiez vos identifiants et votre connexion, puis réessayez.';

  @override
  String get assignedJobs => 'Missions assignées';

  @override
  String get noJobsYet => 'Aucune tâche attribuée pour le moment';

  @override
  String get pullToRefresh =>
      'Tirez vers le bas pour actualiser après l’attribution du travail par un superviseur.';

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
    return '$count tâches';
  }

  @override
  String get taskChecklist => 'Liste de tâches';

  @override
  String get proofPhoto => 'Photo preuve';

  @override
  String get beforePhoto => 'AVANT la photo';

  @override
  String get afterPhoto => 'APRÈS la photo';

  @override
  String get capturing => 'Capture en cours...';

  @override
  String get uploading => 'Envoi de la photo justificative...';

  @override
  String get finalizing => 'Finalisation...';

  @override
  String get photoUploaded => 'Photo envoyée avec succès';

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
      other: '$count événements en attente',
      one: '1 événement en attente',
      zero: 'Aucun événement en attente',
    );
    return '$_temp0';
  }

  @override
  String get submitOTRequest => 'Envoyer une demande d’heures supplémentaires';

  @override
  String get overtimeAlert => 'Vous entrez dans les heures supplémentaires';

  @override
  String get hoursWorked => 'Heures travaillées jusqu’à présent';

  @override
  String get reasonForOvertime => 'Motif des heures supplémentaires';

  @override
  String get mySchedule => 'Mon planning';

  @override
  String get upcomingShifts => 'Services à venir';

  @override
  String get scheduleHelp =>
      'Services publiés pour les deux prochaines semaines. Tirez pour actualiser si un superviseur modifie votre planning.';

  @override
  String get updated => 'Mis à jour';

  @override
  String get noScheduledShiftsYet => 'Aucun service planifié pour le moment';

  @override
  String get scheduleWillAppear =>
      'Les services publiés apparaîtront ici lorsque votre superviseur aura envoyé le planning.';

  @override
  String get scheduleUnavailable => 'Planning indisponible';

  @override
  String get restaurantClockTitle => 'Pointeuse';

  @override
  String get restaurantClockGpsServiceOff =>
      'Activez les services de localisation pour enregistrer la présence.';

  @override
  String get restaurantClockGpsPermissionRequired =>
      'L’autorisation de localisation est requise, car cette succursale l’a activée pour la pointeuse.';

  @override
  String get restaurantClockGpsLocationUnavailable =>
      'Impossible d’obtenir votre position. Vérifiez les services de localisation et réessayez.';

  @override
  String restaurantClockQueued(String branch) {
    return 'Votre pointage pour $branch est enregistré sur ce téléphone et sera synchronisé au retour de la connexion.';
  }

  @override
  String restaurantClockEntrySaved(String branch) {
    return 'Entrée enregistrée à $branch.';
  }

  @override
  String restaurantClockExitSaved(String branch) {
    return 'Sortie enregistrée à $branch.';
  }

  @override
  String get restaurantClockSaving => 'Enregistrement…';

  @override
  String get restaurantClockActive => 'Votre entrée est active.';

  @override
  String get restaurantClockInactive => 'Aucune entrée active.';

  @override
  String restaurantClockEntryTime(String time) {
    return 'Entrée : $time';
  }

  @override
  String get restaurantClockPendingSync =>
      'Un pointage est enregistré sur ce téléphone et attend la synchronisation.';

  @override
  String get restaurantClockActiveEntries => 'Entrées actives';

  @override
  String get restaurantClockNoActiveEntries =>
      'Aucun membre de l’équipe n’a pointé son entrée.';

  @override
  String get restaurantClockUnavailableTime => 'Heure indisponible';

  @override
  String get restaurantClockTeamMember => 'Membre de l’équipe';

  @override
  String restaurantClockEntryAt(String time) {
    return 'Entrée enregistrée à $time';
  }

  @override
  String get restaurantClockActivePrivacy =>
      'Seul le statut d’entrée active est affiché ; aucune localisation en arrière-plan n’est utilisée.';

  @override
  String get restaurantClockTodayAttendance => 'Présences du jour';

  @override
  String get restaurantClockNoBranchEntries =>
      'Aucun pointage d’entrée n’a encore été enregistré dans cette succursale aujourd’hui.';

  @override
  String get restaurantClockEntry => 'Entrée';

  @override
  String restaurantClockEntryForDate(String date) {
    return 'Entrée ($date)';
  }

  @override
  String get restaurantClockNoExit => 'aucune sortie';

  @override
  String restaurantClockExitAt(String time) {
    return 'sortie $time';
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
      'Seules les présences du jour sont affichées ; ce résumé ne contient aucune localisation.';

  @override
  String get restaurantClockMyAttendance => 'Mes pointages du jour';

  @override
  String get restaurantClockNoMyEntriesToday =>
      'Vous n’avez encore aucun pointage d’entrée aujourd’hui.';

  @override
  String get restaurantClockMyPrivacy =>
      'Ce résumé n’affiche que vos horaires, sans localisation.';

  @override
  String get restaurantClockToday => 'Aujourd’hui';

  @override
  String get restaurantClockPreviousDate => 'Date précédente';

  @override
  String get restaurantClockGpsRequired =>
      'Cette succursale demande la localisation au pointage d’entrée ou de sortie. L’app ne collecte pas la localisation en arrière-plan.';

  @override
  String get restaurantClockGpsNotRequired =>
      'La pointeuse est active sans collecte de localisation. Aucune localisation en arrière-plan n’est utilisée.';

  @override
  String get restaurantClockNoPayroll =>
      'Ce pointage documente la présence opérationnelle ; il ne calcule pas la paie.';

  @override
  String get restaurantMoreTitle => 'Plus';

  @override
  String get restaurantAccount => 'Compte Pollo Móvil';

  @override
  String get restaurantAssignedBranchAccess =>
      'Accès sécurisé à votre succursale attribuée';

  @override
  String get restaurantMoreDescription =>
      'Pollo Móvil coordonne les activités, les inspections, les incidents et les relais de service. La localisation n’est pas collectée en arrière-plan.';

  @override
  String get restaurantNotificationsThisDevice =>
      'Notifications sur cet appareil';

  @override
  String get restaurantPushOperationalUpdates =>
      'Alertes push pour les activités et les changements opérationnels.';

  @override
  String get restaurantPushRequiresSetup =>
      'Les notifications push seront disponibles après la configuration de Firebase et des notifications de cette plateforme.';

  @override
  String get restaurantPushEnableFailed =>
      'Impossible d’activer les notifications. Vérifiez l’autorisation de cet appareil et la configuration Firebase de l’application.';

  @override
  String get restaurantNotificationView => 'Voir';

  @override
  String get restaurantSignOutPendingEvents =>
      'Les événements en attente de synchronisation restent sur ce téléphone.';

  @override
  String get restaurantOperationalAppLabel =>
      'Pollo Móvil · application opérationnelle';

  @override
  String get restaurantNotificationsTitle => 'Notifications';

  @override
  String get restaurantNotificationsQueuedRead =>
      'La boîte de réception sera actualisée lorsque la connexion sera rétablie.';

  @override
  String get restaurantNotificationsMarkAllRead => 'Tout marquer comme lu';

  @override
  String restaurantNotificationsLoadError(String error) {
    return 'Impossible de charger les notifications. $error';
  }

  @override
  String get restaurantNotificationsOfflineEmpty =>
      'La copie enregistrée ne contient aucune notification. Connectez-vous pour actualiser la boîte de réception.';

  @override
  String get restaurantNotificationsEmpty =>
      'Vous n’avez pas encore de notifications.';

  @override
  String get restaurantNotificationsOfflineTitle =>
      'Boîte de réception enregistrée hors ligne';

  @override
  String get restaurantNotificationsOfflineBody =>
      'Son état a peut-être changé depuis la dernière actualisation.';

  @override
  String get restaurantNotificationFallbackTitle => 'Notification';

  @override
  String get restaurantNotificationReadPending =>
      'Lecture en attente de synchronisation';

  @override
  String get restaurantNotificationMarkRead => 'Marquer comme lue';

  @override
  String get restaurantInspectionQueued =>
      'L’inspection est enregistrée sur ce téléphone et sera synchronisée au retour de la connexion.';

  @override
  String get restaurantInspectionSaved => 'Inspection enregistrée.';

  @override
  String restaurantInspectionNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Inspection enregistrée ; $count éléments nécessitent une attention.',
      one: 'Inspection enregistrée ; 1 élément nécessite une attention.',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInspectionNoActiveCriteria =>
      'Cette liste ne contient aucun critère actif. Demandez à un administrateur de la configurer.';

  @override
  String get restaurantInspectionInstruction =>
      'Indiquez l’état observé pour chaque critère configuré par cette succursale.';

  @override
  String get restaurantInspectionCriterion => 'Critère';

  @override
  String get restaurantInspectionObservedState => 'État observé';

  @override
  String get restaurantInspectionResultOk => 'Conforme';

  @override
  String get restaurantInspectionResultNeedsAttention => 'À vérifier';

  @override
  String get restaurantInspectionResultNotApplicable => 'Sans objet';

  @override
  String get restaurantInspectionOptionalDetail => 'Détail facultatif';

  @override
  String get restaurantInspectionOptionalGeneralNote =>
      'Note générale (facultative)';

  @override
  String get restaurantInspectionSaving => 'Enregistrement…';

  @override
  String get restaurantInspectionSave => 'Enregistrer l’inspection';

  @override
  String get restaurantInspectionOfflineHelp =>
      'Hors ligne, l’inspection reste sur ce téléphone et sera envoyée au retour de la connexion.';

  @override
  String get restaurantInspectionDefaultTitle => 'Inspection';

  @override
  String get restaurantShiftScheduleTitle => 'Planning des services';

  @override
  String get restaurantShiftSaved => 'Service enregistré.';

  @override
  String get restaurantShiftUpdated => 'Service mis à jour.';

  @override
  String restaurantShiftSaveError(String error) {
    return 'Impossible d’enregistrer le service : $error';
  }

  @override
  String get restaurantShiftCancelTitle => 'Annuler le service';

  @override
  String restaurantShiftCancelConfirmation(String employee) {
    return 'Annuler le service de $employee ?';
  }

  @override
  String get restaurantShiftCanceled => 'Service annulé.';

  @override
  String restaurantShiftCancelError(String error) {
    return 'Impossible d’annuler le service : $error';
  }

  @override
  String get restaurantShiftLoadError =>
      'Impossible de charger le planning de cette semaine.';

  @override
  String get restaurantShiftPreviousWeek => 'Semaine précédente';

  @override
  String get restaurantShiftNextWeek => 'Semaine suivante';

  @override
  String get restaurantShiftOfflineNotice =>
      'Hors ligne : dernier planning enregistré affiché. La modification des services sera possible au retour de la connexion.';

  @override
  String restaurantShiftTimezone(String timeZone) {
    return 'Les horaires suivent le fuseau local de la succursale : $timeZone';
  }

  @override
  String get restaurantShiftAdd => 'Ajouter un service';

  @override
  String get restaurantShiftNoShifts => 'Aucun service planifié.';

  @override
  String get restaurantShiftTeamMember => 'Membre de l’équipe';

  @override
  String get restaurantShiftPublished => 'Publié';

  @override
  String get restaurantShiftDraft => 'Brouillon';

  @override
  String restaurantShiftTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String restaurantShiftBreaks(String breaks) {
    return 'Pause : $breaks';
  }

  @override
  String get restaurantShiftEdit => 'Modifier';

  @override
  String get restaurantShiftCancelAction => 'Annuler le service';

  @override
  String get restaurantShiftAddDialogTitle => 'Ajouter un service';

  @override
  String get restaurantShiftEditDialogTitle => 'Modifier le service';

  @override
  String get restaurantShiftEmployee => 'Employé';

  @override
  String get restaurantShiftDay => 'Jour';

  @override
  String get restaurantShiftStartChoose => 'Début : choisir';

  @override
  String get restaurantShiftEndChoose => 'Fin : choisir';

  @override
  String get restaurantShiftStart => 'Début';

  @override
  String get restaurantShiftEnd => 'Fin';

  @override
  String get restaurantShiftPublish => 'Publier le service';

  @override
  String get restaurantShiftDraftDescription =>
      'Si l’option est désactivée, le service est enregistré comme brouillon.';

  @override
  String get restaurantShiftBreaksTitle => 'Pauses';

  @override
  String get restaurantShiftAddBreak => 'Ajouter';

  @override
  String get restaurantShiftRemoveBreak => 'Supprimer la pause';

  @override
  String get restaurantShiftSave => 'Enregistrer';

  @override
  String get restaurantTeamTitle => 'Équipe de la succursale';

  @override
  String get restaurantTeamUpdated =>
      'Informations du membre de l’équipe mises à jour.';

  @override
  String restaurantTeamSaveError(String error) {
    return 'Impossible d’enregistrer toutes les modifications : $error';
  }

  @override
  String get restaurantInviteDialogTitle => 'Inviter un employé';

  @override
  String get restaurantInviteLinkTitle => 'Lien d’invitation';

  @override
  String get restaurantInviteAction => 'Inviter un employé';

  @override
  String get restaurantInviteEmailNotSent =>
      'L’e-mail n’a pas pu être envoyé automatiquement. Copiez ce lien et partagez-le avec la personne invitée.';

  @override
  String get restaurantInviteCopied => 'Lien d’invitation copié.';

  @override
  String get restaurantInviteCopyLink => 'Copier le lien';

  @override
  String get restaurantClose => 'Fermer';

  @override
  String get restaurantInviteSent => 'Invitation envoyée.';

  @override
  String get restaurantInviteAlreadyMember =>
      'Cette personne est déjà membre de cette succursale.';

  @override
  String get restaurantInviteAccountAdded => 'Compte ajouté à la succursale.';

  @override
  String restaurantInviteError(String error) {
    return 'Impossible d’inviter cette personne : $error';
  }

  @override
  String get restaurantTeamLoadError =>
      'Impossible de charger l’équipe de la succursale.';

  @override
  String get restaurantTeamOfflineTitle =>
      'Dernière équipe enregistrée affichée';

  @override
  String get restaurantTeamOfflineBody =>
      'Ces informations sont en lecture seule jusqu’au retour de la connexion.';

  @override
  String get restaurantTeamEmpty =>
      'Cette succursale ne compte encore aucun membre.';

  @override
  String restaurantTeamMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInviteFullName => 'Nom complet';

  @override
  String get restaurantInviteEmail => 'Adresse e-mail';

  @override
  String get restaurantInviteNameValidation => 'Saisissez le nom complet.';

  @override
  String get restaurantInvitePermissionNote =>
      'L’invitation sera envoyée à cette adresse e-mail. Le nouveau membre aura un accès employé.';

  @override
  String get restaurantInviteSubmit => 'Envoyer l’invitation';

  @override
  String get restaurantRoleLabel => 'Rôle dans la succursale';

  @override
  String get restaurantRoleEmployee => 'Employé';

  @override
  String get restaurantRoleSupervisor => 'Superviseur';

  @override
  String get restaurantRoleAdmin => 'Administrateur';

  @override
  String get restaurantMemberActive => 'Actif';

  @override
  String get restaurantMemberInactive => 'Inactif';

  @override
  String get restaurantMemberAccess => 'Accès à la succursale';

  @override
  String get restaurantMemberDeactivateNote =>
      'La désactivation conserve l’historique des services et des tâches.';

  @override
  String get restaurantMemberPositions => 'Postes activés';

  @override
  String get restaurantPositionFallback => 'Poste';

  @override
  String get restaurantMemberReactivateToEdit =>
      'Réactivez l’accès pour modifier les postes activés.';

  @override
  String get restaurantMemberConfigurePositions =>
      'Configurez les postes avant de les attribuer à l’équipe.';

  @override
  String get restaurantMemberSaveChanges => 'Enregistrer les modifications';

  @override
  String get restaurantAbsenceReviewTitle => 'Demandes d’absence';

  @override
  String get restaurantAbsenceApproved => 'Demande approuvée.';

  @override
  String get restaurantAbsenceRejected => 'Demande refusée.';

  @override
  String restaurantAbsenceReviewError(String error) {
    return 'Impossible de traiter la demande : $error';
  }

  @override
  String get restaurantAbsenceLoadError =>
      'Impossible de charger les demandes en attente.';

  @override
  String get restaurantAbsenceNone => 'Aucune demande en attente.';

  @override
  String get restaurantAbsenceOfflineNotice =>
      'Hors ligne : demandes de la dernière actualisation affichées. Une connexion est nécessaire pour approuver ou refuser.';

  @override
  String get restaurantAbsenceOfflineEmpty =>
      'Aucune demande en attente lors de la dernière actualisation.';

  @override
  String get restaurantAbsenceReject => 'Refuser';

  @override
  String get restaurantAbsenceApprove => 'Approuver';

  @override
  String get restaurantCalendarTitle => 'Calendrier des activités';

  @override
  String get restaurantCalendarRefresh => 'Actualiser le calendrier';

  @override
  String get restaurantCalendarLoadError =>
      'Impossible de charger le calendrier.';

  @override
  String get restaurantCalendarRetry => 'Réessayer';

  @override
  String get restaurantCalendarPreviousWeek => 'Semaine précédente';

  @override
  String get restaurantCalendarNextWeek => 'Semaine suivante';

  @override
  String get restaurantCalendarManagerHint =>
      'Seules les activités configurées peuvent être planifiées.';

  @override
  String get restaurantCalendarBranchHint =>
      'Activités attribuées à votre succursale.';

  @override
  String get restaurantCalendarOffline =>
      'Hors ligne : dernière semaine enregistrée affichée. La planification est en lecture seule jusqu\'à la reconnexion.';

  @override
  String get restaurantCalendarRetroactive =>
      'Les activités passées ne peuvent pas être planifiées depuis le calendrier.';

  @override
  String restaurantCalendarDayScheduled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouvelles activités créées',
      one: '1 nouvelle activité créée',
    );
    return '$_temp0 selon les règles de la succursale. Les activités existantes ne sont pas dupliquées.';
  }

  @override
  String get restaurantCalendarPastWeek =>
      'Cette semaine est passée ; aucune date n\'a été modifiée.';

  @override
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays) {
    return '$created activités planifiées sur $days dates. Les dates passées sont restées inchangées ; $pastDays dates passées ignorées. Les activités existantes ne sont pas dupliquées.';
  }

  @override
  String restaurantCalendarWeekPartial(int created, int days, String dates) {
    return '$created activités planifiées sur $days dates. Échec pour : $dates. Vous pouvez réessayer ; les activités existantes ne seront pas dupliquées.';
  }

  @override
  String get restaurantCalendarPlanWeek => 'Planifier la semaine affichée';

  @override
  String get restaurantCalendarPlanningWeek => 'Planification de la semaine…';

  @override
  String restaurantCalendarWeekActivities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activités cette semaine',
      one: '1 activité cette semaine',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarUnassignedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tâches sans responsable',
      one: '1 tâche sans responsable',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count terminées',
      one: '1 terminée',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarActivityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activités',
      one: '1 activité',
    );
    return '$_temp0';
  }

  @override
  String get restaurantCalendarPastDate =>
      'Date passée ; aucune activité rétroactive ne sera créée.';

  @override
  String get restaurantCalendarScheduleFromRules =>
      'Planifier selon les règles';

  @override
  String get restaurantCalendarScheduling => 'Planification…';

  @override
  String get restaurantCalendarAssignEligible =>
      'Attribuer aux personnes disponibles';

  @override
  String get restaurantCalendarAssigning => 'Attribution…';

  @override
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  ) {
    return '$assigned activités attribuées avec $planner ; $unassigned sans personne admissible.';
  }

  @override
  String get restaurantCalendarLocalPlanner => 'le planificateur local';

  @override
  String get restaurantCalendarNoActivities => 'Aucune activité planifiée.';

  @override
  String get restaurantCalendarFallbackActivity => 'Activité';

  @override
  String get restaurantCalendarNoAssignee => 'Sans responsable';

  @override
  String get restaurantCalendarConfigurationPending =>
      'Configurez les postes, zones ou exigences de la succursale avant d\'attribuer cette activité.';

  @override
  String get restaurantCalendarAssignee => 'Responsable';

  @override
  String get restaurantCalendarFallbackAssignee => 'Responsable actuel';

  @override
  String restaurantCalendarInactiveAssignee(String name) {
    return '$name · inactif';
  }

  @override
  String get restaurantCalendarEmployeeFallback => 'Employé';

  @override
  String get restaurantCalendarZoneFallback => 'Partie';

  @override
  String restaurantCalendarZoneAssignee(String zone) {
    return 'Responsable de $zone';
  }

  @override
  String get restaurantCalendarStatusPending => 'En attente';

  @override
  String get restaurantCalendarStatusInProgress => 'En cours';

  @override
  String get restaurantCalendarStatusPaused => 'En pause';

  @override
  String get restaurantCalendarStatusBlocked => 'Bloquée';

  @override
  String get restaurantCalendarStatusCompleted => 'Terminée';

  @override
  String get restaurantCalendarTaskAssigneeUpdated =>
      'Responsable de l\'activité mis à jour.';

  @override
  String get restaurantCalendarPartAssigneeUpdated =>
      'Responsable de la partie mis à jour.';

  @override
  String get restaurantStructureTitle => 'Zones et postes';

  @override
  String get restaurantStructureAreas => 'Zones';

  @override
  String get restaurantStructurePositions => 'Postes';

  @override
  String restaurantStructureAdd(String label) {
    return 'Ajouter $label';
  }

  @override
  String restaurantStructureEdit(String label) {
    return 'Modifier $label';
  }

  @override
  String restaurantStructureSaved(String label) {
    return '$label enregistré.';
  }

  @override
  String restaurantStructureSaveError(String label, String error) {
    return 'Impossible d\'enregistrer $label : $error';
  }

  @override
  String restaurantStructureReactivateTitle(String label) {
    return 'Réactiver $label';
  }

  @override
  String restaurantStructureDeactivateTitle(String label) {
    return 'Désactiver $label';
  }

  @override
  String get restaurantStructureReactivateDescription =>
      'Il pourra de nouveau être sélectionné pour les nouvelles activités.';

  @override
  String get restaurantStructureDeactivateDescription =>
      'Il sera masqué des nouvelles activités. L\'historique existant sera conservé.';

  @override
  String get restaurantStructureBack => 'Retour';

  @override
  String get restaurantStructureReactivateAction => 'Réactiver';

  @override
  String get restaurantStructureDeactivateAction => 'Désactiver';

  @override
  String get restaurantStructureEmpty =>
      'Aucun élément n\'est encore configuré.';

  @override
  String get restaurantStructureStatusActive => 'État : actif';

  @override
  String get restaurantStructureStatusInactive => 'État : inactif';

  @override
  String restaurantStructureAddTooltip(String label) {
    return 'Ajouter $label';
  }

  @override
  String get restaurantStructureEditName => 'Modifier le nom';

  @override
  String get restaurantStructureOfflineTitle =>
      'Dernière configuration enregistrée affichée';

  @override
  String get restaurantStructureOfflineBody =>
      'Les zones, postes et options sont en lecture seule jusqu\'au rétablissement de la connexion.';

  @override
  String get restaurantStructureKeepHistory =>
      'Désactivez les éléments au lieu de les supprimer pour conserver l\'historique opérationnel.';

  @override
  String get restaurantStructureLoadError =>
      'Impossible de charger la configuration de la succursale.';

  @override
  String get restaurantStructureRetry => 'Réessayer';

  @override
  String get restaurantAttendanceTitle => 'Présence et localisation';

  @override
  String get restaurantAttendanceOptional =>
      'Ces options sont facultatives par succursale et désactivées par défaut.';

  @override
  String get restaurantAttendanceEnableClock => 'Activer la pointeuse';

  @override
  String get restaurantAttendanceClockDescription =>
      'Enregistre les arrivées et départs. Ne calcule pas la paie.';

  @override
  String get restaurantAttendanceRequestGps =>
      'Demander le GPS à chaque pointage';

  @override
  String get restaurantAttendanceGpsDescription =>
      'La position est vérifiée uniquement au pointage d\'arrivée ou de départ ; aucun suivi continu.';

  @override
  String get restaurantAttendanceSaveFeatures => 'Enregistrer les options';

  @override
  String get restaurantAttendanceSaved => 'Options de présence mises à jour.';

  @override
  String restaurantAttendanceSaveError(String error) {
    return 'Impossible d\'enregistrer la configuration : $error';
  }

  @override
  String get restaurantStructureName => 'Nom';

  @override
  String get restaurantStructureSave => 'Enregistrer';

  @override
  String get restaurantEvidenceTitle => 'Preuve de l\'activité';

  @override
  String get restaurantEvidenceCameraMissing => 'Aucun appareil photo trouvé.';

  @override
  String get restaurantEvidenceCameraOpenError =>
      'Impossible d\'ouvrir l\'appareil photo.';

  @override
  String get restaurantEvidencePhotoSaveError =>
      'Impossible d\'enregistrer la photo. Réessayez.';

  @override
  String get restaurantEvidenceSaving => 'Enregistrement…';

  @override
  String get restaurantEvidenceTakePhoto => 'Prendre une photo';

  @override
  String get restaurantSyncOffline => 'Hors ligne';

  @override
  String restaurantSyncOfflinePending(int count) {
    return 'Hors ligne, $count enregistrements en attente';
  }

  @override
  String restaurantSyncAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrements nécessitent une attention',
      one: '1 enregistrement nécessite une attention',
    );
    return '$_temp0';
  }

  @override
  String restaurantSyncPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrements en attente de synchronisation',
      one: '1 enregistrement en attente de synchronisation',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAllDone => 'Tout est synchronisé';

  @override
  String restaurantSyncTooltip(String status) {
    return '$status. Touchez pour synchroniser maintenant.';
  }

  @override
  String get restaurantSyncStarted =>
      'La synchronisation des enregistrements en attente a démarré.';

  @override
  String get restaurantSyncOfflineSaved =>
      'Hors ligne ; les enregistrements restent sur ce téléphone.';

  @override
  String get restaurantSyncFailure =>
      'Impossible de synchroniser maintenant. Les enregistrements restent sur ce téléphone.';

  @override
  String get restaurantSyncRetryQueued =>
      'L\'enregistrement a été remis dans la file de synchronisation.';

  @override
  String get restaurantSyncRetryFailed =>
      'Nouvelle tentative impossible pour le moment. L\'enregistrement reste sur ce téléphone.';

  @override
  String get restaurantSyncEventClock => 'Pointeuse : arrivée ou départ';

  @override
  String get restaurantSyncEventOperations => 'Enregistrement opérationnel';

  @override
  String get restaurantSyncEventClockEvent => 'Arrivée ou départ';

  @override
  String get restaurantSyncEventEvidence => 'Preuve photographique';

  @override
  String get restaurantSyncEventPending => 'Enregistrement en attente';

  @override
  String restaurantSyncAttentionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrements nécessitent une attention',
      one: '1 enregistrement nécessite une attention',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAttentionHelp =>
      'Ils sont conservés sur ce téléphone. Réessayez une fois connecté. Si un enregistrement appartient à un autre compte, connectez-vous avec ce compte.';

  @override
  String get restaurantSyncRequiresOriginalAccount =>
      'Compte d\'origine requis';

  @override
  String get restaurantSyncRetry => 'Réessayer';

  @override
  String get restaurantOpsShiftTitle => 'Mon service';

  @override
  String get restaurantOpsWasteTitle => 'Contrôle des poubelles';

  @override
  String get restaurantOpsIncidentsTitle => 'Incidents';

  @override
  String get restaurantOpsHandoffTitle => 'Relève de service';

  @override
  String get restaurantOpsBranchesLoadError =>
      'Impossible de charger vos succursales.';

  @override
  String get restaurantOpsShiftLoadError => 'Impossible de charger le service.';

  @override
  String get restaurantOpsBranchFallback => 'Succursale';

  @override
  String get restaurantOpsOfflineTitle =>
      'Dernière opération enregistrée affichée';

  @override
  String get restaurantOpsOfflinePendingChanges =>
      'Les nouvelles modifications resteront sur ce téléphone jusqu\'au rétablissement de la connexion.';

  @override
  String restaurantOpsOfflineSnapshotAt(String time) {
    return 'Copie du $time. Les nouvelles modifications resteront sur ce téléphone jusqu\'au rétablissement de la connexion.';
  }

  @override
  String get restaurantOpsSavedOffline =>
      'Enregistré sur ce téléphone. La synchronisation aura lieu dès le retour de la connexion.';

  @override
  String get restaurantOpsSaved =>
      'Terminé. La modification a été enregistrée.';

  @override
  String get restaurantOpsHandoffDelivered =>
      'La relève a été enregistrée avec l\'état actuel du service.';

  @override
  String get restaurantOpsSwitchBranch => 'Changer de succursale';

  @override
  String get restaurantOpsRefresh => 'Actualiser';

  @override
  String get restaurantOpsPauseTitle => 'Mettre l\'activité en pause';

  @override
  String get restaurantOpsPauseOptionalNote =>
      'Note facultative pour la relève';

  @override
  String get restaurantOpsPauseContinue => 'Continuer à travailler';

  @override
  String get restaurantOpsPauseAction => 'Mettre en pause';

  @override
  String get restaurantOpsPauseHint =>
      'Contexte opérationnel pour la personne qui reprendra l\'activité';

  @override
  String get restaurantOpsNoUpcomingShifts =>
      'Aucun service n\'est publié pour les deux prochaines semaines.';

  @override
  String get restaurantOpsToday => 'Aujourd\'hui';

  @override
  String get restaurantOpsTomorrow => 'Demain';

  @override
  String get restaurantOpsCalendarDescription =>
      'Consultez les activités planifiées de la succursale.';

  @override
  String get restaurantOpsCustomerService => 'Je sers un client';

  @override
  String get restaurantOpsInterruptibleWait =>
      'Les tâches interruptibles attendront.';

  @override
  String get restaurantOpsOwnActivities => 'Vos activités';

  @override
  String get restaurantOpsNoOwnActivities =>
      'Aucune activité ne vous est attribuée pour ce service.';

  @override
  String get restaurantOpsBranchStructureDescription =>
      'Configurez la structure opérationnelle de cette succursale.';

  @override
  String get restaurantOpsTeamDescription =>
      'Gérez les accès, rôles et postes de la succursale.';

  @override
  String get restaurantOpsShiftAdminDescription =>
      'Gérez les services, pauses et publications de l\'équipe.';

  @override
  String get restaurantOpsPendingAbsences => 'Demandes en attente';

  @override
  String get restaurantOpsAbsenceReviewDescription =>
      'Examinez, approuvez ou refusez les demandes de l\'équipe.';

  @override
  String get restaurantOpsTaskPendingSync =>
      'Modification enregistrée sur ce téléphone ; synchronisation en attente.';

  @override
  String restaurantOpsPauseReason(String note) {
    return 'Motif de la pause : $note';
  }

  @override
  String restaurantOpsAssigneeNamed(String name) {
    return 'Responsable : $name';
  }

  @override
  String get restaurantOpsZoneFallback => 'Zone';

  @override
  String get restaurantOpsYou => 'Vous';

  @override
  String get restaurantOpsActionClaim => 'Prendre la tâche';

  @override
  String get restaurantOpsActionStart => 'Démarrer';

  @override
  String get restaurantOpsActionPause => 'Mettre en pause';

  @override
  String get restaurantOpsActionComplete => 'Terminer';

  @override
  String get restaurantOpsActionResume => 'Reprendre';

  @override
  String get restaurantOpsAbsencePendingNote =>
      'La demande restera en attente jusqu\'à son examen par un superviseur.';

  @override
  String get restaurantOpsDateFrom => 'Du';

  @override
  String get restaurantOpsDateUntil => 'Au';

  @override
  String get restaurantOpsOptionalNote => 'Note facultative';

  @override
  String get restaurantOpsAbsenceSend => 'Envoyer la demande';

  @override
  String get restaurantOpsAbsenceSending => 'Envoi…';

  @override
  String get restaurantOpsAbsenceOfflineNote =>
      'Hors ligne, la demande est enregistrée pour être synchronisée plus tard.';

  @override
  String get restaurantOpsSavedAbsencesTitle =>
      'Demandes enregistrées sur ce téléphone';

  @override
  String get restaurantOpsSyncReviewNeeded => 'Vérifier la synchronisation';

  @override
  String get restaurantOpsPendingSend => 'En attente d\'envoi';

  @override
  String get restaurantOpsUnassignedSection => 'Sans responsable';

  @override
  String get restaurantOpsAbsenceStatusDenied => 'Non approuvée';

  @override
  String get restaurantOpsWasteIntro =>
      'Un seul contrôle enregistre l\'état déclaré de chaque poubelle.';

  @override
  String get restaurantOpsWasteNeedsAttention =>
      'Un contrôle local nécessite une action dans Synchronisation. N\'en soumettez pas un autre avant résolution.';

  @override
  String get restaurantOpsWastePendingSync =>
      'Contrôle enregistré sur ce téléphone ; il sera synchronisé au retour de la connexion.';

  @override
  String get restaurantOpsWasteStatusTitle => 'État des poubelles';

  @override
  String get restaurantOpsBinFallback => 'Poubelle';

  @override
  String restaurantOpsIntervalConfigured(String minutes) {
    return 'Intervalle configuré : $minutes min';
  }

  @override
  String get restaurantOpsInspectionDue =>
      'Contrôle dû selon l\'intervalle configuré.';

  @override
  String get restaurantOpsWasteNeedsPolicy =>
      'Configurez la tâche résultante avant de déclarer cette poubelle pleine.';

  @override
  String get restaurantOpsDeclaredState => 'État déclaré';

  @override
  String get restaurantOpsSelectState => 'Sélectionnez un état';

  @override
  String get restaurantOpsBinLow => 'Vide ou peu remplie';

  @override
  String get restaurantOpsBinHalf => 'À moitié pleine';

  @override
  String get restaurantOpsBinFull => 'Pleine';

  @override
  String get restaurantOpsCannotSaveFullBin =>
      'Impossible d\'enregistrer : configurez le nom, la durée, la difficulté et la priorité de la tâche liée à une poubelle pleine.';

  @override
  String get restaurantOpsWastePendingAction =>
      'Contrôle en attente de synchronisation';

  @override
  String get restaurantOpsSaving => 'Enregistrement…';

  @override
  String get restaurantOpsWasteSubmit => 'Enregistrer le contrôle';

  @override
  String get restaurantOpsAreaInspectionsTitle => 'Contrôles des autres zones';

  @override
  String get restaurantOpsNoInspectionTemplates =>
      'Aucune liste de contrôle n\'est configurée pour cette succursale.';

  @override
  String get restaurantOpsInspectionFallback => 'Inspection';

  @override
  String restaurantOpsInspectionCriteriaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count critères configurés',
      one: '1 critère configuré',
    );
    return '$_temp0';
  }

  @override
  String restaurantOpsInspectionInterval(String minutes) {
    return 'Toutes les $minutes min';
  }

  @override
  String get restaurantOpsInspectionNeedsAttention =>
      'Une inspection locale nécessite une action dans Synchronisation.';

  @override
  String restaurantOpsInspectionPendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count critères sont marqués',
      one: '1 critère est marqué',
    );
    return 'Inspection enregistrée sur ce téléphone ; $_temp0 pour révision.';
  }

  @override
  String get restaurantOpsDoInspection => 'Effectuer l\'inspection';

  @override
  String get restaurantOpsInspectionPendingAction =>
      'Inspection en attente de synchronisation';

  @override
  String restaurantOpsRecentInspections(int count) {
    return 'Enregistrements récents ($count)';
  }

  @override
  String get restaurantOpsTeamFallback => 'Équipe';

  @override
  String restaurantOpsNeedsAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments nécessitent une attention',
      one: '1 élément nécessite une attention',
    );
    return '$_temp0';
  }

  @override
  String get restaurantOpsNoAlerts => 'Aucune alerte';

  @override
  String get restaurantOpsCriterionFallback => 'Critère';

  @override
  String restaurantOpsCriterionNote(String label, String note) {
    return '$label : $note';
  }

  @override
  String get restaurantOpsIncidentReport => 'Signaler un problème';

  @override
  String get restaurantOpsIncidentDescription => 'Description succincte';

  @override
  String get restaurantOpsIncidentAreaOptional => 'Zone (facultatif)';

  @override
  String get restaurantOpsIncidentNoArea => 'Aucune zone';

  @override
  String get restaurantOpsUrgency => 'Urgence';

  @override
  String get restaurantOpsUrgencyLow => 'Faible';

  @override
  String get restaurantOpsUrgencyNormal => 'Normale';

  @override
  String get restaurantOpsUrgencyHigh => 'Élevée';

  @override
  String get restaurantOpsUrgencyUrgent => 'Urgente';

  @override
  String get restaurantOpsIncidentBlocksWork => 'Bloque le travail';

  @override
  String get restaurantOpsIncidentSend => 'Envoyer l\'incident';

  @override
  String get restaurantOpsOpenIncidents => 'Incidents ouverts';

  @override
  String get restaurantOpsNoOpenIncidents => 'Aucun incident n\'est ouvert.';

  @override
  String get restaurantOpsSavedIncidentsTitle => 'Enregistré sur ce téléphone';

  @override
  String get restaurantOpsIncidentFallback => 'Incident';

  @override
  String get restaurantOpsIncidentNeedsAttention =>
      'Vérifier la synchronisation';

  @override
  String get restaurantOpsIncidentPendingSync =>
      'En attente de synchronisation';

  @override
  String get restaurantOpsIncidentBlockingUnconfirmed =>
      'Signalé comme bloquant ; pas encore confirmé par le serveur.';

  @override
  String get restaurantOpsIncidentStatusOpen => 'Ouvert';

  @override
  String get restaurantOpsIncidentStatusInProgress => 'En cours';

  @override
  String get restaurantOpsIncidentStatusResolved => 'Résolu';

  @override
  String get restaurantOpsHandoffSummary =>
      'Résumé automatique du service. Inutile de réécrire les rapports.';

  @override
  String restaurantOpsHandoffCompletedCount(int count) {
    return 'Terminées ($count)';
  }

  @override
  String get restaurantOpsHandoffNoCompleted =>
      'Aucune activité terminée aujourd\'hui pour le moment.';

  @override
  String restaurantOpsHandoffOutstandingCount(int count) {
    return 'En attente ou en pause ($count)';
  }

  @override
  String get restaurantOpsHandoffNoOutstanding => 'Aucune activité en attente.';

  @override
  String restaurantOpsHandoffIncidentCount(int count) {
    return 'Incidents ouverts ($count)';
  }

  @override
  String get restaurantOpsHandoffDeliveryTitle =>
      'Remise et réception du service';

  @override
  String get restaurantOpsHandoffSnapshotNote =>
      'Une photo des activités en attente et des incidents ouverts sera enregistrée lors de la remise.';

  @override
  String get restaurantOpsHandoffRecipient => 'Personne qui reçoit la relève';

  @override
  String get restaurantOpsHandoffNoRecipient => 'Aucun destinataire précis';

  @override
  String get restaurantOpsHandoffMemberFallback => 'Membre de la succursale';

  @override
  String get restaurantOpsHandoffNote => 'Note de relève (facultative)';

  @override
  String get restaurantOpsHandoffNoteHint =>
      'Informations opérationnelles pour poursuivre le service';

  @override
  String get restaurantOpsHandoffDeliver => 'Remettre le service';

  @override
  String get restaurantOpsHandoffConnectionRequired =>
      'Une connexion est nécessaire pour enregistrer le véritable état du service.';

  @override
  String restaurantOpsRecentHandoffs(int count) {
    return 'Relèves récentes ($count)';
  }

  @override
  String get restaurantOpsNoHandoffs =>
      'Aucune relève n\'a encore été enregistrée.';

  @override
  String restaurantOpsHandoffReceivedBy(String name) {
    return 'Reçu par $name';
  }

  @override
  String get restaurantOpsHandoffPendingTeam =>
      'En attente de réception par l\'équipe';

  @override
  String restaurantOpsHandoffPendingRecipient(String name) {
    return 'En attente de réception par $name';
  }

  @override
  String get restaurantOpsHandoffAckNeedsAttention =>
      'La confirmation enregistrée nécessite une action dans Synchronisation.';

  @override
  String get restaurantOpsHandoffAckPendingSync =>
      'Confirmation enregistrée sur ce téléphone ; synchronisation en attente.';

  @override
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents) {
    return 'À la remise : $tasks activités en attente · $incidents incidents ouverts';
  }

  @override
  String restaurantOpsHandoffPausePrefix(String note) {
    return 'Pause : $note';
  }

  @override
  String restaurantOpsHandoffIncidentDescription(String description) {
    return 'Incident : $description';
  }

  @override
  String get restaurantOpsHandoffConfirmReceipt => 'Confirmer la réception';

  @override
  String get restaurantOpsNoDescription => 'Sans description';

  @override
  String get restaurantOpsIncidentFollowupTitle => 'Suivi de l\'incident';

  @override
  String get restaurantOpsIncidentStatusLabel => 'État';

  @override
  String get restaurantOpsIncidentFollowupNote => 'Note de suivi (facultative)';

  @override
  String get restaurantOpsIncidentSaveFollowup => 'Enregistrer le suivi';

  @override
  String get restaurantOpsBranchNotConfiguredTitle =>
      'Votre succursale n\'est pas encore configurée';

  @override
  String get restaurantOpsBranchNotConfiguredMessage =>
      'Demandez à un administrateur de créer une succursale et de vous y ajouter. Si vous avez les droits d\'administration, vous pouvez la créer ici.';

  @override
  String get restaurantOpsBranchName => 'Nom de la succursale';

  @override
  String get restaurantOpsBranchTimeZone => 'Fuseau horaire de la succursale';

  @override
  String get restaurantOpsBranchCreate => 'Créer la succursale';

  @override
  String get restaurantOpsBranchCreating => 'Création…';
}

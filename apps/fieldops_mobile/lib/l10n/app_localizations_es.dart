// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Pollo Móvil';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get emailRequired => 'El correo es obligatorio.';

  @override
  String get emailInvalid => 'Ingresa un correo válido.';

  @override
  String get passwordRequired => 'La contraseña es obligatoria.';

  @override
  String get signInFailed =>
      'Error al iniciar sesión. Verifica tus credenciales y conexión.';

  @override
  String get assignedJobs => 'Trabajos asignados';

  @override
  String get noJobsYet => 'Sin trabajos asignados';

  @override
  String get pullToRefresh =>
      'Desliza para actualizar cuando un supervisor asigne trabajo.';

  @override
  String get clockIn => 'Registrar entrada';

  @override
  String get clockOut => 'Registrar salida';

  @override
  String get clockedIn => 'En servicio';

  @override
  String get readyToClockIn => 'Listo para registrar';

  @override
  String get startBreak => 'Iniciar descanso';

  @override
  String get endBreak => 'Terminar descanso';

  @override
  String get onBreak => 'En descanso';

  @override
  String get requestOT => 'Solicitar horas extra';

  @override
  String get takePhoto => 'Foto';

  @override
  String tasks(int count) {
    return '$count tareas';
  }

  @override
  String get taskChecklist => 'Lista de tareas';

  @override
  String get proofPhoto => 'Foto de evidencia';

  @override
  String get beforePhoto => 'Foto ANTES';

  @override
  String get afterPhoto => 'Foto DESPUÉS';

  @override
  String get capturing => 'Capturando...';

  @override
  String get uploading => 'Subiendo foto de evidencia...';

  @override
  String get finalizing => 'Finalizando...';

  @override
  String get photoUploaded => 'Foto subida exitosamente';

  @override
  String get retry => 'Reintentar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get offline => 'Sin conexión';

  @override
  String eventsQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eventos en cola',
      one: '1 evento en cola',
    );
    return '$_temp0';
  }

  @override
  String get submitOTRequest => 'Enviar solicitud de horas extra';

  @override
  String get overtimeAlert => 'Estás entrando en horas extra';

  @override
  String get hoursWorked => 'Horas trabajadas hasta ahora';

  @override
  String get reasonForOvertime => 'Razón de las horas extra';

  @override
  String get mySchedule => 'Mi horario';

  @override
  String get upcomingShifts => 'Próximos turnos';

  @override
  String get scheduleHelp =>
      'Turnos publicados para las próximas dos semanas. Desliza para actualizar si un supervisor cambia tu horario.';

  @override
  String get updated => 'Actualizado';

  @override
  String get noScheduledShiftsYet => 'Todavía no hay turnos programados';

  @override
  String get scheduleWillAppear =>
      'Los turnos publicados aparecerán aquí cuando tu supervisor envíe el horario.';

  @override
  String get scheduleUnavailable => 'Horario no disponible';

  @override
  String get restaurantClockTitle => 'Checador';

  @override
  String get restaurantClockGpsServiceOff =>
      'Activa el servicio de ubicación para registrar la asistencia.';

  @override
  String get restaurantClockGpsPermissionRequired =>
      'Se necesita permiso de ubicación porque esta sucursal lo configuró para el checador.';

  @override
  String get restaurantClockGpsLocationUnavailable =>
      'No se pudo obtener tu ubicación. Revisa los servicios de ubicación e inténtalo de nuevo.';

  @override
  String restaurantClockQueued(String branch) {
    return 'El registro de $branch quedó guardado en el teléfono y se sincronizará al recuperar conexión.';
  }

  @override
  String restaurantClockEntrySaved(String branch) {
    return 'Entrada registrada en $branch.';
  }

  @override
  String restaurantClockExitSaved(String branch) {
    return 'Salida registrada en $branch.';
  }

  @override
  String get restaurantClockSaving => 'Guardando…';

  @override
  String get restaurantClockActive => 'Tienes una entrada activa.';

  @override
  String get restaurantClockInactive => 'Sin entrada activa.';

  @override
  String restaurantClockEntryTime(String time) {
    return 'Entrada: $time';
  }

  @override
  String get restaurantClockPendingSync =>
      'Hay un registro guardado en este teléfono y pendiente de sincronización.';

  @override
  String get restaurantClockActiveEntries => 'Entradas activas';

  @override
  String get restaurantClockNoActiveEntries =>
      'No hay integrantes con entrada activa.';

  @override
  String get restaurantClockUnavailableTime => 'Hora no disponible';

  @override
  String get restaurantClockTeamMember => 'Integrante del equipo';

  @override
  String restaurantClockEntryAt(String time) {
    return 'Entrada registrada a las $time';
  }

  @override
  String get restaurantClockActivePrivacy =>
      'Solo se muestra el estado de entrada activa; no se usa ubicación en segundo plano.';

  @override
  String get restaurantClockTodayAttendance => 'Asistencia de hoy';

  @override
  String get restaurantClockNoBranchEntries =>
      'Aún no hay registros de entrada en esta sucursal.';

  @override
  String get restaurantClockEntry => 'Entrada';

  @override
  String restaurantClockEntryForDate(String date) {
    return 'Entrada ($date)';
  }

  @override
  String get restaurantClockNoExit => 'sin salida';

  @override
  String restaurantClockExitAt(String time) {
    return 'salida $time';
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
      'Solo se muestra la asistencia del día; este resumen no incluye ubicaciones.';

  @override
  String get restaurantClockMyAttendance => 'Mis registros de hoy';

  @override
  String get restaurantClockNoMyEntriesToday =>
      'Todavía no tienes entradas registradas para hoy.';

  @override
  String get restaurantClockMyPrivacy =>
      'Este resumen incluye solo tus horarios y no muestra ubicaciones.';

  @override
  String get restaurantClockToday => 'Hoy';

  @override
  String get restaurantClockPreviousDate => 'Fecha anterior';

  @override
  String get restaurantClockGpsRequired =>
      'Esta sucursal solicita ubicación al registrar entrada y salida. La app no toma ubicaciones en segundo plano.';

  @override
  String get restaurantClockGpsNotRequired =>
      'El checador está activo sin recopilar ubicación. No se usa ubicación en segundo plano.';

  @override
  String get restaurantClockNoPayroll =>
      'Este registro documenta asistencia operativa; no calcula nómina.';

  @override
  String get restaurantMoreTitle => 'Más';

  @override
  String get restaurantAccount => 'Cuenta de Pollo Móvil';

  @override
  String get restaurantAssignedBranchAccess =>
      'Acceso seguro a la sucursal asignada';

  @override
  String get restaurantMoreDescription =>
      'Pollo Móvil coordina actividades, inspecciones, incidencias y relevos. La ubicación no se recopila en segundo plano.';

  @override
  String get restaurantNotificationsThisDevice =>
      'Notificaciones en este teléfono';

  @override
  String get restaurantPushOperationalUpdates =>
      'Avisos push para actividades y cambios operativos.';

  @override
  String get restaurantPushRequiresSetup =>
      'Las notificaciones push estarán disponibles cuando se complete la configuración de Firebase y de esta plataforma.';

  @override
  String get restaurantPushEnableFailed =>
      'No se pudieron activar las notificaciones. Revisa el permiso del teléfono y la configuración móvil de Firebase.';

  @override
  String get restaurantNotificationView => 'Ver';

  @override
  String get restaurantSignOutPendingEvents =>
      'Los eventos guardados para sincronizar permanecen en este teléfono.';

  @override
  String get restaurantOperationalAppLabel => 'Pollo Móvil · app operativa';

  @override
  String get restaurantNotificationsTitle => 'Notificaciones';

  @override
  String get restaurantNotificationsQueuedRead =>
      'Se actualizará la bandeja cuando vuelva la conexión.';

  @override
  String get restaurantNotificationsMarkAllRead => 'Leer todo';

  @override
  String restaurantNotificationsLoadError(String error) {
    return 'No se pudieron cargar las notificaciones. $error';
  }

  @override
  String get restaurantNotificationsOfflineEmpty =>
      'La copia guardada no contiene notificaciones. Conéctate para actualizar la bandeja.';

  @override
  String get restaurantNotificationsEmpty =>
      'No tienes notificaciones todavía.';

  @override
  String get restaurantNotificationsOfflineTitle =>
      'Bandeja guardada sin conexión';

  @override
  String get restaurantNotificationsOfflineBody =>
      'El estado puede haber cambiado desde la última actualización.';

  @override
  String get restaurantNotificationFallbackTitle => 'Notificación';

  @override
  String get restaurantNotificationReadPending =>
      'Lectura pendiente de sincronizar';

  @override
  String get restaurantNotificationMarkRead => 'Marcar como leída';

  @override
  String get restaurantInspectionQueued =>
      'La inspección quedó guardada en este teléfono y se sincronizará al recuperar conexión.';

  @override
  String get restaurantInspectionSaved => 'Inspección guardada.';

  @override
  String restaurantInspectionNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inspección guardada; $count elementos requieren atención.',
      one: 'Inspección guardada; 1 elemento requiere atención.',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInspectionNoActiveCriteria =>
      'Esta lista no tiene criterios activos. Pide a un administrador que la configure.';

  @override
  String get restaurantInspectionInstruction =>
      'Registra el estado observado de cada criterio configurado por la sucursal.';

  @override
  String get restaurantInspectionCriterion => 'Criterio';

  @override
  String get restaurantInspectionObservedState => 'Estado observado';

  @override
  String get restaurantInspectionResultOk => 'Correcto';

  @override
  String get restaurantInspectionResultNeedsAttention => 'Requiere atención';

  @override
  String get restaurantInspectionResultNotApplicable => 'No aplica';

  @override
  String get restaurantInspectionOptionalDetail => 'Detalle opcional';

  @override
  String get restaurantInspectionOptionalGeneralNote =>
      'Nota general (opcional)';

  @override
  String get restaurantInspectionSaving => 'Guardando…';

  @override
  String get restaurantInspectionSave => 'Guardar inspección';

  @override
  String get restaurantInspectionOfflineHelp =>
      'Si no hay conexión, la inspección queda guardada en este teléfono y se enviará al recuperar señal.';

  @override
  String get restaurantInspectionDefaultTitle => 'Inspección';

  @override
  String get restaurantShiftScheduleTitle => 'Programación de turnos';

  @override
  String get restaurantShiftSaved => 'Turno guardado.';

  @override
  String get restaurantShiftUpdated => 'Turno actualizado.';

  @override
  String restaurantShiftSaveError(String error) {
    return 'No se pudo guardar el turno: $error';
  }

  @override
  String get restaurantShiftCancelTitle => 'Cancelar turno';

  @override
  String restaurantShiftCancelConfirmation(String employee) {
    return '¿Cancelar el turno de $employee?';
  }

  @override
  String get restaurantShiftCanceled => 'Turno cancelado.';

  @override
  String restaurantShiftCancelError(String error) {
    return 'No se pudo cancelar el turno: $error';
  }

  @override
  String get restaurantShiftLoadError =>
      'No se pudo cargar la programación de esta semana.';

  @override
  String get restaurantShiftPreviousWeek => 'Semana anterior';

  @override
  String get restaurantShiftNextWeek => 'Semana siguiente';

  @override
  String get restaurantShiftOfflineNotice =>
      'Sin conexión: se muestra la última programación guardada. La edición de turnos se habilita al recuperar conexión.';

  @override
  String restaurantShiftTimezone(String timeZone) {
    return 'Las horas usan la zona local de la sucursal: $timeZone';
  }

  @override
  String get restaurantShiftAdd => 'Agregar turno';

  @override
  String get restaurantShiftNoShifts => 'Sin turnos programados.';

  @override
  String get restaurantShiftTeamMember => 'Integrante del equipo';

  @override
  String get restaurantShiftPublished => 'Publicado';

  @override
  String get restaurantShiftDraft => 'Borrador';

  @override
  String restaurantShiftTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String restaurantShiftBreaks(String breaks) {
    return 'Descanso: $breaks';
  }

  @override
  String get restaurantShiftEdit => 'Editar';

  @override
  String get restaurantShiftCancelAction => 'Cancelar turno';

  @override
  String get restaurantShiftAddDialogTitle => 'Agregar turno';

  @override
  String get restaurantShiftEditDialogTitle => 'Editar turno';

  @override
  String get restaurantShiftEmployee => 'Empleado';

  @override
  String get restaurantShiftDay => 'Día';

  @override
  String get restaurantShiftStartChoose => 'Inicio: seleccionar';

  @override
  String get restaurantShiftEndChoose => 'Fin: seleccionar';

  @override
  String get restaurantShiftStart => 'Inicio';

  @override
  String get restaurantShiftEnd => 'Fin';

  @override
  String get restaurantShiftPublish => 'Publicar turno';

  @override
  String get restaurantShiftDraftDescription =>
      'Si se deja apagado, se guarda como borrador.';

  @override
  String get restaurantShiftBreaksTitle => 'Descansos';

  @override
  String get restaurantShiftAddBreak => 'Agregar';

  @override
  String get restaurantShiftRemoveBreak => 'Quitar descanso';

  @override
  String get restaurantShiftSave => 'Guardar';

  @override
  String get restaurantTeamTitle => 'Equipo de la sucursal';

  @override
  String get restaurantTeamUpdated => 'Información del integrante actualizada.';

  @override
  String restaurantTeamSaveError(String error) {
    return 'No se pudieron guardar todos los cambios: $error';
  }

  @override
  String get restaurantInviteDialogTitle => 'Invitar empleado';

  @override
  String get restaurantInviteLinkTitle => 'Enlace de invitación';

  @override
  String get restaurantInviteAction => 'Invitar empleado';

  @override
  String get restaurantInviteEmailNotSent =>
      'El correo no se pudo enviar automáticamente. Copia este enlace y compártelo con la persona invitada.';

  @override
  String get restaurantInviteCopied => 'Enlace de invitación copiado.';

  @override
  String get restaurantInviteCopyLink => 'Copiar enlace';

  @override
  String get restaurantClose => 'Cerrar';

  @override
  String get restaurantInviteSent => 'Invitación enviada.';

  @override
  String get restaurantInviteAlreadyMember =>
      'La persona ya pertenece a esta sucursal.';

  @override
  String get restaurantInviteAccountAdded => 'Cuenta agregada a la sucursal.';

  @override
  String restaurantInviteError(String error) {
    return 'No se pudo invitar a la persona: $error';
  }

  @override
  String get restaurantTeamLoadError =>
      'No se pudo cargar el equipo de la sucursal.';

  @override
  String get restaurantTeamOfflineTitle =>
      'Mostrando el último equipo guardado';

  @override
  String get restaurantTeamOfflineBody =>
      'La información es de solo lectura hasta recuperar conexión.';

  @override
  String get restaurantTeamEmpty =>
      'Todavía no hay integrantes en esta sucursal.';

  @override
  String restaurantTeamMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count integrantes',
      one: '1 integrante',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInviteFullName => 'Nombre completo';

  @override
  String get restaurantInviteEmail => 'Correo electrónico';

  @override
  String get restaurantInviteNameValidation => 'Escribe el nombre completo.';

  @override
  String get restaurantInvitePermissionNote =>
      'La invitación se enviará al correo indicado. El nuevo integrante tendrá permiso de empleado.';

  @override
  String get restaurantInviteSubmit => 'Enviar invitación';

  @override
  String get restaurantRoleLabel => 'Permiso en la sucursal';

  @override
  String get restaurantRoleEmployee => 'Empleado';

  @override
  String get restaurantRoleSupervisor => 'Supervisor';

  @override
  String get restaurantRoleAdmin => 'Administrador';

  @override
  String get restaurantMemberActive => 'Activo';

  @override
  String get restaurantMemberInactive => 'Inactivo';

  @override
  String get restaurantMemberAccess => 'Acceso a la sucursal';

  @override
  String get restaurantMemberDeactivateNote =>
      'Al desactivar, se conserva el historial de turnos y tareas.';

  @override
  String get restaurantMemberPositions => 'Puestos habilitados';

  @override
  String get restaurantPositionFallback => 'Puesto';

  @override
  String get restaurantMemberReactivateToEdit =>
      'Reactiva el acceso para modificar los puestos habilitados.';

  @override
  String get restaurantMemberConfigurePositions =>
      'Configura puestos antes de asignarlos al equipo.';

  @override
  String get restaurantMemberSaveChanges => 'Guardar cambios';

  @override
  String get restaurantAbsenceReviewTitle => 'Solicitudes de ausencia';

  @override
  String get restaurantAbsenceApproved => 'Solicitud aprobada.';

  @override
  String get restaurantAbsenceRejected => 'Solicitud rechazada.';

  @override
  String restaurantAbsenceReviewError(String error) {
    return 'No se pudo revisar la solicitud: $error';
  }

  @override
  String get restaurantAbsenceLoadError =>
      'No se pudieron cargar las solicitudes pendientes.';

  @override
  String get restaurantAbsenceNone => 'No hay solicitudes pendientes.';

  @override
  String get restaurantAbsenceOfflineNotice =>
      'Sin conexión: se muestran las solicitudes de la última consulta. Aprobar o rechazar requiere conexión.';

  @override
  String get restaurantAbsenceOfflineEmpty =>
      'No había solicitudes pendientes en la última consulta.';

  @override
  String get restaurantAbsenceReject => 'Rechazar';

  @override
  String get restaurantAbsenceApprove => 'Aprobar';

  @override
  String get restaurantCalendarTitle => 'Calendario de actividades';

  @override
  String get restaurantCalendarRefresh => 'Actualizar calendario';

  @override
  String get restaurantCalendarLoadError => 'No se pudo cargar el calendario.';

  @override
  String get restaurantCalendarRetry => 'Reintentar';

  @override
  String get restaurantCalendarPreviousWeek => 'Semana anterior';

  @override
  String get restaurantCalendarNextWeek => 'Semana siguiente';

  @override
  String get restaurantCalendarManagerHint =>
      'Programa únicamente actividades configuradas.';

  @override
  String get restaurantCalendarBranchHint =>
      'Actividades asignadas a tu sucursal.';

  @override
  String get restaurantCalendarOffline =>
      'Sin conexión: se muestra la última semana guardada. La programación queda en modo de consulta hasta reconectar.';

  @override
  String get restaurantCalendarRetroactive =>
      'No se generan actividades retroactivas desde el calendario.';

  @override
  String restaurantCalendarDayScheduled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se crearon $count actividades nuevas',
      one: 'Se creó 1 actividad nueva',
    );
    return '$_temp0 desde las reglas de la sucursal. Las ya programadas no se duplicaron.';
  }

  @override
  String get restaurantCalendarPastWeek =>
      'Esta semana ya pasó; no se modificó ninguna fecha.';

  @override
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays) {
    return 'Se programaron $created actividades en $days fechas. Las fechas pasadas quedaron intactas; se omitieron $pastDays. Las actividades existentes no se duplicaron.';
  }

  @override
  String restaurantCalendarWeekPartial(int created, int days, String dates) {
    return 'Se programaron $created actividades en $days fechas. No se pudieron programar: $dates. Puedes reintentar; las actividades existentes no se duplicarán.';
  }

  @override
  String get restaurantCalendarPlanWeek => 'Programar semana visible';

  @override
  String get restaurantCalendarPlanningWeek => 'Programando semana…';

  @override
  String restaurantCalendarWeekActivities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actividades en la semana',
      one: '1 actividad en la semana',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarUnassignedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count asignaciones sin responsable',
      one: '1 asignación sin responsable',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarCompletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count terminadas',
      one: '1 terminada',
    );
    return '$_temp0';
  }

  @override
  String restaurantCalendarActivityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actividades',
      one: '1 actividad',
    );
    return '$_temp0';
  }

  @override
  String get restaurantCalendarPastDate =>
      'Fecha pasada; no se generan actividades retroactivas.';

  @override
  String get restaurantCalendarScheduleFromRules => 'Programar desde reglas';

  @override
  String get restaurantCalendarScheduling => 'Programando…';

  @override
  String get restaurantCalendarAssignEligible => 'Asignar elegibles';

  @override
  String get restaurantCalendarAssigning => 'Asignando…';

  @override
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  ) {
    return '$assigned actividades asignadas con $planner; $unassigned sin personal elegible.';
  }

  @override
  String get restaurantCalendarLocalPlanner => 'el planificador local';

  @override
  String get restaurantCalendarNoActivities => 'Sin actividades programadas.';

  @override
  String get restaurantCalendarFallbackActivity => 'Actividad';

  @override
  String get restaurantCalendarNoAssignee => 'Sin responsable';

  @override
  String get restaurantCalendarConfigurationPending =>
      'Configura los puestos, zonas o requisitos de la sucursal antes de asignar esta actividad.';

  @override
  String get restaurantCalendarAssignee => 'Responsable';

  @override
  String get restaurantCalendarFallbackAssignee => 'Responsable actual';

  @override
  String restaurantCalendarInactiveAssignee(String name) {
    return '$name · inactivo';
  }

  @override
  String get restaurantCalendarEmployeeFallback => 'Empleado';

  @override
  String get restaurantCalendarZoneFallback => 'Parte';

  @override
  String restaurantCalendarZoneAssignee(String zone) {
    return 'Responsable de $zone';
  }

  @override
  String get restaurantCalendarStatusPending => 'Pendiente';

  @override
  String get restaurantCalendarStatusInProgress => 'En curso';

  @override
  String get restaurantCalendarStatusPaused => 'Pausada';

  @override
  String get restaurantCalendarStatusBlocked => 'Bloqueada';

  @override
  String get restaurantCalendarStatusCompleted => 'Terminada';

  @override
  String get restaurantCalendarTaskAssigneeUpdated =>
      'Responsable de la actividad actualizado.';

  @override
  String get restaurantCalendarPartAssigneeUpdated =>
      'Responsable de la parte actualizado.';

  @override
  String get restaurantStructureTitle => 'Áreas y puestos';

  @override
  String get restaurantStructureAreas => 'Áreas';

  @override
  String get restaurantStructurePositions => 'Puestos';

  @override
  String restaurantStructureAdd(String label) {
    return 'Agregar $label';
  }

  @override
  String restaurantStructureEdit(String label) {
    return 'Editar $label';
  }

  @override
  String restaurantStructureSaved(String label) {
    return '$label guardado.';
  }

  @override
  String restaurantStructureSaveError(String label, String error) {
    return 'No se pudo guardar $label: $error';
  }

  @override
  String restaurantStructureReactivateTitle(String label) {
    return 'Reactivar $label';
  }

  @override
  String restaurantStructureDeactivateTitle(String label) {
    return 'Desactivar $label';
  }

  @override
  String get restaurantStructureReactivateDescription =>
      'Se podrá volver a elegir en nuevas actividades.';

  @override
  String get restaurantStructureDeactivateDescription =>
      'Se ocultará de nuevas actividades. El historial existente se conservará.';

  @override
  String get restaurantStructureBack => 'Volver';

  @override
  String get restaurantStructureReactivateAction => 'Reactivar';

  @override
  String get restaurantStructureDeactivateAction => 'Desactivar';

  @override
  String get restaurantStructureEmpty =>
      'Todavía no hay elementos configurados.';

  @override
  String get restaurantStructureStatusActive => 'Estado: activo';

  @override
  String get restaurantStructureStatusInactive => 'Estado: inactivo';

  @override
  String restaurantStructureAddTooltip(String label) {
    return 'Agregar $label';
  }

  @override
  String get restaurantStructureEditName => 'Editar nombre';

  @override
  String get restaurantStructureOfflineTitle =>
      'Mostrando la última configuración guardada';

  @override
  String get restaurantStructureOfflineBody =>
      'Las áreas, puestos y funciones son de solo lectura hasta recuperar conexión.';

  @override
  String get restaurantStructureKeepHistory =>
      'Desactiva en lugar de borrar para conservar el historial operativo.';

  @override
  String get restaurantStructureLoadError =>
      'No se pudo cargar la configuración de la sucursal.';

  @override
  String get restaurantStructureRetry => 'Reintentar';

  @override
  String get restaurantAttendanceTitle => 'Asistencia y ubicación';

  @override
  String get restaurantAttendanceOptional =>
      'Son opcionales por sucursal y están desactivadas de forma predeterminada.';

  @override
  String get restaurantAttendanceEnableClock => 'Habilitar checador';

  @override
  String get restaurantAttendanceClockDescription =>
      'Registra entrada y salida. No calcula nómina.';

  @override
  String get restaurantAttendanceRequestGps => 'Solicitar GPS en cada registro';

  @override
  String get restaurantAttendanceGpsDescription =>
      'La ubicación solo se consulta al marcar entrada o salida; nunca hay rastreo continuo.';

  @override
  String get restaurantAttendanceSaveFeatures => 'Guardar funciones';

  @override
  String get restaurantAttendanceSaved =>
      'Funciones de asistencia actualizadas.';

  @override
  String restaurantAttendanceSaveError(String error) {
    return 'No se pudo guardar la configuración: $error';
  }

  @override
  String get restaurantStructureName => 'Nombre';

  @override
  String get restaurantStructureSave => 'Guardar';

  @override
  String get restaurantEvidenceTitle => 'Evidencia de la actividad';

  @override
  String get restaurantEvidenceCameraMissing => 'No se encontró una cámara.';

  @override
  String get restaurantEvidenceCameraOpenError => 'No se pudo abrir la cámara.';

  @override
  String get restaurantEvidencePhotoSaveError =>
      'No se pudo guardar la foto. Intenta de nuevo.';

  @override
  String get restaurantEvidenceSaving => 'Guardando…';

  @override
  String get restaurantEvidenceTakePhoto => 'Tomar foto';

  @override
  String get restaurantSyncOffline => 'Sin conexión';

  @override
  String restaurantSyncOfflinePending(int count) {
    return 'Sin conexión, $count registros pendientes';
  }

  @override
  String restaurantSyncAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registros requieren atención',
      one: '1 registro requiere atención',
    );
    return '$_temp0';
  }

  @override
  String restaurantSyncPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registros pendientes de sincronizar',
      one: '1 registro pendiente de sincronizar',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAllDone => 'Todo sincronizado';

  @override
  String restaurantSyncTooltip(String status) {
    return '$status. Toca para sincronizar ahora.';
  }

  @override
  String get restaurantSyncStarted =>
      'Se inició la sincronización de registros pendientes.';

  @override
  String get restaurantSyncOfflineSaved =>
      'Sin conexión; los registros siguen guardados en este teléfono.';

  @override
  String get restaurantSyncFailure =>
      'No se pudo sincronizar ahora. Los registros siguen guardados en este teléfono.';

  @override
  String get restaurantSyncRetryQueued =>
      'El registro volvió a la cola de sincronización.';

  @override
  String get restaurantSyncRetryFailed =>
      'No se pudo reintentar todavía. El registro sigue guardado en este teléfono.';

  @override
  String get restaurantSyncEventClock => 'Checador: entrada o salida';

  @override
  String get restaurantSyncEventOperations => 'Registro operativo';

  @override
  String get restaurantSyncEventClockEvent => 'Entrada o salida';

  @override
  String get restaurantSyncEventEvidence => 'Evidencia fotográfica';

  @override
  String get restaurantSyncEventPending => 'Registro pendiente';

  @override
  String restaurantSyncAttentionNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count registros requieren atención',
      one: '1 registro requiere atención',
    );
    return '$_temp0';
  }

  @override
  String get restaurantSyncAttentionHelp =>
      'Se conservaron en este teléfono. Reintenta cuando haya conexión; si el registro pertenece a otra cuenta, inicia sesión con esa cuenta.';

  @override
  String get restaurantSyncRequiresOriginalAccount =>
      'Requiere la cuenta original';

  @override
  String get restaurantSyncRetry => 'Reintentar';

  @override
  String get restaurantOpsShiftTitle => 'Mi turno';

  @override
  String get restaurantOpsWasteTitle => 'Revisión de botes';

  @override
  String get restaurantOpsIncidentsTitle => 'Incidencias';

  @override
  String get restaurantOpsHandoffTitle => 'Relevo';

  @override
  String get restaurantOpsBranchesLoadError =>
      'No se pudieron cargar tus sucursales.';

  @override
  String get restaurantOpsShiftLoadError => 'No se pudo cargar el turno.';

  @override
  String get restaurantOpsBranchFallback => 'Sucursal';

  @override
  String get restaurantOpsOfflineTitle =>
      'Mostrando la última operación guardada';

  @override
  String get restaurantOpsOfflinePendingChanges =>
      'Los cambios nuevos se conservarán en este teléfono hasta recuperar conexión.';

  @override
  String restaurantOpsOfflineSnapshotAt(String time) {
    return 'Copia del $time. Los cambios nuevos se conservarán en este teléfono hasta recuperar conexión.';
  }

  @override
  String get restaurantOpsSavedOffline =>
      'Guardado en el teléfono. Se sincronizará al recuperar conexión.';

  @override
  String get restaurantOpsSaved => 'Listo. Se guardó el cambio.';

  @override
  String get restaurantOpsHandoffDelivered =>
      'El relevo quedó guardado con el estado actual del turno.';

  @override
  String get restaurantOpsSwitchBranch => 'Cambiar sucursal';

  @override
  String get restaurantOpsRefresh => 'Actualizar';

  @override
  String get restaurantOpsPauseTitle => 'Pausar actividad';

  @override
  String get restaurantOpsPauseOptionalNote => 'Nota opcional para el relevo';

  @override
  String get restaurantOpsPauseContinue => 'Seguir trabajando';

  @override
  String get restaurantOpsPauseAction => 'Pausar actividad';

  @override
  String get restaurantOpsPauseHint =>
      'Contexto operativo para quien retome la actividad';

  @override
  String get restaurantOpsNoUpcomingShifts =>
      'No hay turnos publicados en las próximas dos semanas.';

  @override
  String get restaurantOpsToday => 'Hoy';

  @override
  String get restaurantOpsTomorrow => 'Mañana';

  @override
  String get restaurantOpsCalendarDescription =>
      'Consulta las actividades programadas de la sucursal.';

  @override
  String get restaurantOpsCustomerService => 'Estoy atendiendo a un cliente';

  @override
  String get restaurantOpsInterruptibleWait =>
      'Las tareas interrumpibles esperarán.';

  @override
  String get restaurantOpsOwnActivities => 'Tus actividades';

  @override
  String get restaurantOpsNoOwnActivities =>
      'No tienes actividades asignadas en este turno.';

  @override
  String get restaurantOpsBranchStructureDescription =>
      'Configura la estructura operativa de esta sucursal.';

  @override
  String get restaurantOpsTeamDescription =>
      'Administra permisos, acceso y puestos de la sucursal.';

  @override
  String get restaurantOpsShiftAdminDescription =>
      'Administra turnos, descansos y publicación del equipo.';

  @override
  String get restaurantOpsPendingAbsences => 'Solicitudes pendientes';

  @override
  String get restaurantOpsAbsenceReviewDescription =>
      'Revisa, aprueba o rechaza las solicitudes del equipo.';

  @override
  String get restaurantOpsTaskPendingSync =>
      'Cambio guardado en este teléfono; pendiente de sincronizar.';

  @override
  String restaurantOpsPauseReason(String note) {
    return 'Motivo de pausa: $note';
  }

  @override
  String restaurantOpsAssigneeNamed(String name) {
    return 'Responsable: $name';
  }

  @override
  String get restaurantOpsZoneFallback => 'Zona';

  @override
  String get restaurantOpsYou => 'Tú';

  @override
  String get restaurantOpsActionClaim => 'Tomar';

  @override
  String get restaurantOpsActionStart => 'Iniciar';

  @override
  String get restaurantOpsActionPause => 'Pausar';

  @override
  String get restaurantOpsActionComplete => 'Terminar';

  @override
  String get restaurantOpsActionResume => 'Reanudar';

  @override
  String get restaurantOpsAbsencePendingNote =>
      'La solicitud queda pendiente hasta que la revise un supervisor.';

  @override
  String get restaurantOpsDateFrom => 'Desde';

  @override
  String get restaurantOpsDateUntil => 'Hasta';

  @override
  String get restaurantOpsOptionalNote => 'Nota opcional';

  @override
  String get restaurantOpsAbsenceSend => 'Enviar solicitud';

  @override
  String get restaurantOpsAbsenceSending => 'Enviando…';

  @override
  String get restaurantOpsAbsenceOfflineNote =>
      'Sin conexión, la solicitud se guarda para sincronizarse después.';

  @override
  String get restaurantOpsSavedAbsencesTitle =>
      'Solicitudes guardadas en este teléfono';

  @override
  String get restaurantOpsSyncReviewNeeded => 'Revisar sincronización';

  @override
  String get restaurantOpsPendingSend => 'Pendiente de enviar';

  @override
  String get restaurantOpsUnassignedSection => 'Sin responsable';

  @override
  String get restaurantOpsAbsenceStatusDenied => 'No aprobada';

  @override
  String get restaurantOpsWasteIntro =>
      'Una sola revisión registra el estado declarado de cada bote.';

  @override
  String get restaurantOpsWasteNeedsAttention =>
      'Hay una revisión local que necesita atención en Sincronización. No registres otra hasta resolverla.';

  @override
  String get restaurantOpsWastePendingSync =>
      'Revisión guardada en este teléfono; se sincronizará al recuperar conexión.';

  @override
  String get restaurantOpsWasteStatusTitle => 'Estado de los botes';

  @override
  String get restaurantOpsBinFallback => 'Bote';

  @override
  String restaurantOpsIntervalConfigured(String minutes) {
    return 'Intervalo configurado: $minutes min';
  }

  @override
  String get restaurantOpsInspectionDue =>
      'Revisión pendiente según el intervalo configurado.';

  @override
  String get restaurantOpsWasteNeedsPolicy =>
      'Configura la tarea resultante antes de registrar este contenedor como lleno.';

  @override
  String get restaurantOpsDeclaredState => 'Estado declarado';

  @override
  String get restaurantOpsSelectState => 'Selecciona el estado';

  @override
  String get restaurantOpsBinLow => 'Vacío o poco';

  @override
  String get restaurantOpsBinHalf => 'A medias';

  @override
  String get restaurantOpsBinFull => 'Lleno';

  @override
  String get restaurantOpsCannotSaveFullBin =>
      'No se puede guardar: configura nombre, duración, dificultad y prioridad de la tarea asociada al contenedor lleno.';

  @override
  String get restaurantOpsWastePendingAction =>
      'Revisión pendiente de sincronizar';

  @override
  String get restaurantOpsSaving => 'Guardando…';

  @override
  String get restaurantOpsWasteSubmit => 'Registrar revisión';

  @override
  String get restaurantOpsAreaInspectionsTitle => 'Inspecciones de otras áreas';

  @override
  String get restaurantOpsNoInspectionTemplates =>
      'No hay listas de inspección configuradas para esta sucursal.';

  @override
  String get restaurantOpsInspectionFallback => 'Inspección';

  @override
  String restaurantOpsInspectionCriteriaCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count criterios configurados',
      one: '1 criterio configurado',
    );
    return '$_temp0';
  }

  @override
  String restaurantOpsInspectionInterval(String minutes) {
    return 'Cada $minutes min';
  }

  @override
  String get restaurantOpsInspectionNeedsAttention =>
      'Hay una inspección local que necesita atención en Sincronización.';

  @override
  String restaurantOpsInspectionPendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count criterios marcados',
      one: '1 criterio marcado',
    );
    return 'Inspección guardada en este teléfono; $_temp0 para revisión.';
  }

  @override
  String get restaurantOpsDoInspection => 'Realizar inspección';

  @override
  String get restaurantOpsInspectionPendingAction =>
      'Inspección pendiente de sincronizar';

  @override
  String restaurantOpsRecentInspections(int count) {
    return 'Registros recientes ($count)';
  }

  @override
  String get restaurantOpsTeamFallback => 'Equipo';

  @override
  String restaurantOpsNeedsAttentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count requieren atención',
      one: '1 requiere atención',
    );
    return '$_temp0';
  }

  @override
  String get restaurantOpsNoAlerts => 'Sin alertas';

  @override
  String get restaurantOpsCriterionFallback => 'Criterio';

  @override
  String restaurantOpsCriterionNote(String label, String note) {
    return '$label: $note';
  }

  @override
  String get restaurantOpsIncidentReport => 'Reportar un problema';

  @override
  String get restaurantOpsIncidentDescription => 'Descripción breve';

  @override
  String get restaurantOpsIncidentAreaOptional => 'Área (opcional)';

  @override
  String get restaurantOpsIncidentNoArea => 'Sin área';

  @override
  String get restaurantOpsUrgency => 'Urgencia';

  @override
  String get restaurantOpsUrgencyLow => 'Baja';

  @override
  String get restaurantOpsUrgencyNormal => 'Normal';

  @override
  String get restaurantOpsUrgencyHigh => 'Alta';

  @override
  String get restaurantOpsUrgencyUrgent => 'Urgente';

  @override
  String get restaurantOpsIncidentBlocksWork => 'Bloquea el trabajo';

  @override
  String get restaurantOpsIncidentSend => 'Enviar incidencia';

  @override
  String get restaurantOpsOpenIncidents => 'Incidencias abiertas';

  @override
  String get restaurantOpsNoOpenIncidents => 'No hay incidencias abiertas.';

  @override
  String get restaurantOpsSavedIncidentsTitle => 'Guardadas en este teléfono';

  @override
  String get restaurantOpsIncidentFallback => 'Incidencia';

  @override
  String get restaurantOpsIncidentNeedsAttention => 'Revisar sincronización';

  @override
  String get restaurantOpsIncidentPendingSync => 'Pendiente de sincronizar';

  @override
  String get restaurantOpsIncidentBlockingUnconfirmed =>
      'Reportada como bloqueante; aún no está confirmada por el servidor.';

  @override
  String get restaurantOpsIncidentStatusOpen => 'Abierta';

  @override
  String get restaurantOpsIncidentStatusInProgress => 'En atención';

  @override
  String get restaurantOpsIncidentStatusResolved => 'Resuelta';

  @override
  String get restaurantOpsHandoffSummary =>
      'Resumen automático del turno. No requiere volver a escribir reportes.';

  @override
  String restaurantOpsHandoffCompletedCount(int count) {
    return 'Terminadas ($count)';
  }

  @override
  String get restaurantOpsHandoffNoCompleted =>
      'Aún no hay actividades terminadas hoy.';

  @override
  String restaurantOpsHandoffOutstandingCount(int count) {
    return 'Pendientes o pausadas ($count)';
  }

  @override
  String get restaurantOpsHandoffNoOutstanding =>
      'No hay actividades pendientes.';

  @override
  String restaurantOpsHandoffIncidentCount(int count) {
    return 'Incidencias abiertas ($count)';
  }

  @override
  String get restaurantOpsHandoffDeliveryTitle =>
      'Entrega y recepción del turno';

  @override
  String get restaurantOpsHandoffSnapshotNote =>
      'Al entregar se guardará una fotografía de las actividades pendientes y las incidencias abiertas.';

  @override
  String get restaurantOpsHandoffRecipient => 'Quién recibe el relevo';

  @override
  String get restaurantOpsHandoffNoRecipient => 'Sin destinatario específico';

  @override
  String get restaurantOpsHandoffMemberFallback => 'Miembro de sucursal';

  @override
  String get restaurantOpsHandoffNote => 'Nota de entrega (opcional)';

  @override
  String get restaurantOpsHandoffNoteHint =>
      'Información operativa que ayude a continuar el turno';

  @override
  String get restaurantOpsHandoffDeliver => 'Entregar relevo';

  @override
  String get restaurantOpsHandoffConnectionRequired =>
      'Se requiere conexión para guardar el corte real del turno.';

  @override
  String restaurantOpsRecentHandoffs(int count) {
    return 'Relevos recientes ($count)';
  }

  @override
  String get restaurantOpsNoHandoffs => 'Aún no hay relevos registrados.';

  @override
  String restaurantOpsHandoffReceivedBy(String name) {
    return 'Recibido por $name';
  }

  @override
  String get restaurantOpsHandoffPendingTeam =>
      'Pendiente de recepción por el equipo';

  @override
  String restaurantOpsHandoffPendingRecipient(String name) {
    return 'Pendiente de recepción de $name';
  }

  @override
  String get restaurantOpsHandoffAckNeedsAttention =>
      'La confirmación guardada necesita atención en Sincronización.';

  @override
  String get restaurantOpsHandoffAckPendingSync =>
      'Confirmación guardada en este teléfono; pendiente de sincronizar.';

  @override
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents) {
    return 'Al entregar: $tasks actividades pendientes · $incidents incidencias abiertas';
  }

  @override
  String restaurantOpsHandoffPausePrefix(String note) {
    return 'Pausa: $note';
  }

  @override
  String restaurantOpsHandoffIncidentDescription(String description) {
    return 'Incidencia: $description';
  }

  @override
  String get restaurantOpsHandoffConfirmReceipt => 'Confirmar recepción';

  @override
  String get restaurantOpsNoDescription => 'Sin descripción';

  @override
  String get restaurantOpsIncidentFollowupTitle =>
      'Seguimiento de la incidencia';

  @override
  String get restaurantOpsIncidentStatusLabel => 'Estado';

  @override
  String get restaurantOpsIncidentFollowupNote =>
      'Nota de seguimiento (opcional)';

  @override
  String get restaurantOpsIncidentSaveFollowup => 'Guardar seguimiento';

  @override
  String get restaurantOpsBranchNotConfiguredTitle =>
      'Tu sucursal aún no está configurada';

  @override
  String get restaurantOpsBranchNotConfiguredMessage =>
      'Pide a un administrador que cree la sucursal y te agregue. Si tienes permisos de administración, puedes crearla aquí.';

  @override
  String get restaurantOpsBranchName => 'Nombre de la sucursal';

  @override
  String get restaurantOpsBranchTimeZone => 'Zona horaria de la sucursal';

  @override
  String get restaurantOpsBranchCreate => 'Crear sucursal';

  @override
  String get restaurantOpsBranchCreating => 'Creando…';
}

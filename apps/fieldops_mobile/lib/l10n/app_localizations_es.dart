// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'FieldOps AI';

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
}

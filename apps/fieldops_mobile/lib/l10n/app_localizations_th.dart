// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appTitle => 'FieldOps AI';

  @override
  String get signIn => 'เข้าสู่ระบบ';

  @override
  String get signOut => 'ออกจากระบบ';

  @override
  String get email => 'อีเมล';

  @override
  String get password => 'รหัสผ่าน';

  @override
  String get emailRequired => 'กรุณากรอกอีเมล';

  @override
  String get emailInvalid => 'กรุณากรอกอีเมลที่ถูกต้อง';

  @override
  String get passwordRequired => 'กรุณากรอกรหัสผ่าน';

  @override
  String get signInFailed =>
      'เข้าสู่ระบบไม่สำเร็จ กรุณาตรวจสอบข้อมูลและลองอีกครั้ง';

  @override
  String get assignedJobs => 'งานที่ได้รับมอบหมาย';

  @override
  String get noJobsYet => 'ยังไม่มีงานที่ได้รับมอบหมาย';

  @override
  String get pullToRefresh => 'ดึงลงเพื่อรีเฟรชหลังจากหัวหน้างานมอบหมายงาน';

  @override
  String get clockIn => 'ลงเวลาเข้า';

  @override
  String get clockOut => 'ลงเวลาออก';

  @override
  String get clockedIn => 'กำลังทำงาน';

  @override
  String get readyToClockIn => 'พร้อมลงเวลา';

  @override
  String get startBreak => 'เริ่มพัก';

  @override
  String get endBreak => 'สิ้นสุดการพัก';

  @override
  String get onBreak => 'กำลังพัก';

  @override
  String get requestOT => 'ขอล่วงเวลา';

  @override
  String get takePhoto => 'ถ่ายรูป';

  @override
  String tasks(int count) {
    return '$count tasks';
  }

  @override
  String get taskChecklist => 'รายการงาน';

  @override
  String get proofPhoto => 'รูปถ่ายหลักฐาน';

  @override
  String get beforePhoto => 'รูปก่อน';

  @override
  String get afterPhoto => 'รูปหลัง';

  @override
  String get capturing => 'กำลังถ่าย...';

  @override
  String get uploading => 'กำลังอัปโหลด...';

  @override
  String get finalizing => 'กำลังประมวลผล...';

  @override
  String get photoUploaded => 'อัปโหลดรูปสำเร็จ';

  @override
  String get retry => 'ลองอีกครั้ง';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get offline => 'ออฟไลน์';

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
  String get submitOTRequest => 'ส่งคำขอล่วงเวลา';

  @override
  String get overtimeAlert => 'คุณกำลังเข้าสู่ช่วงล่วงเวลา';

  @override
  String get hoursWorked => 'ชั่วโมงทำงาน';

  @override
  String get reasonForOvertime => 'เหตุผลของการทำล่วงเวลา';

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

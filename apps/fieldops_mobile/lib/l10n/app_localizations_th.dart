// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get appTitle => 'Pollo Móvil';

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
    return '$count งาน';
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
      other: '$count รายการอยู่ในคิว',
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
  String get mySchedule => 'ตารางงานของฉัน';

  @override
  String get upcomingShifts => 'กะที่กำลังจะมาถึง';

  @override
  String get scheduleHelp =>
      'ตารางกะที่ประกาศแล้วสำหรับสองสัปดาห์ข้างหน้า ดึงลงเพื่อรีเฟรชเมื่อหัวหน้างานแก้ไขตาราง';

  @override
  String get updated => 'อัปเดตแล้ว';

  @override
  String get noScheduledShiftsYet => 'ยังไม่มีตารางกะ';

  @override
  String get scheduleWillAppear =>
      'ตารางกะที่ประกาศแล้วจะแสดงที่นี่เมื่อหัวหน้างานส่งตาราง';

  @override
  String get scheduleUnavailable => 'ไม่สามารถแสดงตารางงานได้';

  @override
  String get restaurantClockTitle => 'เครื่องบันทึกเวลา';

  @override
  String get restaurantClockGpsServiceOff =>
      'เปิดบริการระบุตำแหน่งเพื่อบันทึกเวลาเข้างาน';

  @override
  String get restaurantClockGpsPermissionRequired =>
      'สาขานี้กำหนดให้อนุญาตการเข้าถึงตำแหน่งเพื่อบันทึกเวลา';

  @override
  String get restaurantClockGpsLocationUnavailable =>
      'ไม่สามารถรับตำแหน่งได้ โปรดตรวจสอบบริการระบุตำแหน่งแล้วลองอีกครั้ง';

  @override
  String restaurantClockQueued(String branch) {
    return 'บันทึกเวลาของ $branch ไว้ในโทรศัพท์แล้ว และจะซิงค์เมื่อกลับมาเชื่อมต่อ';
  }

  @override
  String restaurantClockEntrySaved(String branch) {
    return 'บันทึกเวลาเข้างานที่ $branch แล้ว';
  }

  @override
  String restaurantClockExitSaved(String branch) {
    return 'บันทึกเวลาออกงานที่ $branch แล้ว';
  }

  @override
  String get restaurantClockSaving => 'กำลังบันทึก…';

  @override
  String get restaurantClockActive => 'คุณลงเวลาเข้างานอยู่';

  @override
  String get restaurantClockInactive => 'ยังไม่มีเวลาเข้างานที่เปิดอยู่';

  @override
  String restaurantClockEntryTime(String time) {
    return 'เวลาเข้างาน: $time';
  }

  @override
  String get restaurantClockPendingSync =>
      'มีบันทึกเวลาอยู่ในโทรศัพท์และกำลังรอซิงค์';

  @override
  String get restaurantClockActiveEntries => 'ผู้ที่ลงเวลาเข้างานอยู่';

  @override
  String get restaurantClockNoActiveEntries =>
      'ยังไม่มีสมาชิกในทีมลงเวลาเข้างาน';

  @override
  String get restaurantClockUnavailableTime => 'ไม่สามารถแสดงเวลาได้';

  @override
  String get restaurantClockTeamMember => 'สมาชิกในทีม';

  @override
  String restaurantClockEntryAt(String time) {
    return 'ลงเวลาเข้างานเมื่อ $time';
  }

  @override
  String get restaurantClockActivePrivacy =>
      'แสดงเฉพาะสถานะการลงเวลาเข้างาน และไม่มีการใช้ตำแหน่งเบื้องหลัง';

  @override
  String get restaurantClockTodayAttendance => 'การลงเวลาวันนี้';

  @override
  String get restaurantClockNoBranchEntries =>
      'วันนี้ยังไม่มีรายการลงเวลาเข้างานของสาขานี้';

  @override
  String get restaurantClockEntry => 'เวลาเข้า';

  @override
  String restaurantClockEntryForDate(String date) {
    return 'เวลาเข้า ($date)';
  }

  @override
  String get restaurantClockNoExit => 'ยังไม่ลงเวลาออก';

  @override
  String restaurantClockExitAt(String time) {
    return 'เวลาออก $time';
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
      'แสดงเฉพาะการลงเวลาของวันนี้ โดยสรุปนี้ไม่มีข้อมูลตำแหน่ง';

  @override
  String get restaurantClockMyAttendance => 'รายการลงเวลาของฉันวันนี้';

  @override
  String get restaurantClockNoMyEntriesToday =>
      'วันนี้คุณยังไม่มีรายการลงเวลาเข้างาน';

  @override
  String get restaurantClockMyPrivacy =>
      'สรุปนี้แสดงเฉพาะเวลาของคุณและไม่แสดงตำแหน่ง';

  @override
  String get restaurantClockToday => 'วันนี้';

  @override
  String get restaurantClockPreviousDate => 'วันก่อนหน้า';

  @override
  String get restaurantClockGpsRequired =>
      'สาขานี้ขอตำแหน่งเมื่อคุณลงเวลาเข้าออก แอปจะไม่เก็บตำแหน่งเบื้องหลัง';

  @override
  String get restaurantClockGpsNotRequired =>
      'เปิดใช้งานเครื่องบันทึกเวลาโดยไม่เก็บตำแหน่ง และไม่มีการใช้ตำแหน่งเบื้องหลัง';

  @override
  String get restaurantClockNoPayroll =>
      'รายการนี้บันทึกการปฏิบัติงานเท่านั้น และไม่ใช้คำนวณเงินเดือน';

  @override
  String get restaurantMoreTitle => 'เพิ่มเติม';

  @override
  String get restaurantAccount => 'บัญชี Pollo Móvil';

  @override
  String get restaurantAssignedBranchAccess =>
      'การเข้าถึงสาขาที่ได้รับมอบหมายอย่างปลอดภัย';

  @override
  String get restaurantMoreDescription =>
      'Pollo Móvil ใช้ประสานงานกิจกรรม การตรวจสอบ เหตุการณ์ และการส่งต่องาน โดยไม่มีการเก็บตำแหน่งเบื้องหลัง';

  @override
  String get restaurantNotificationsThisDevice => 'การแจ้งเตือนบนโทรศัพท์นี้';

  @override
  String get restaurantPushOperationalUpdates =>
      'การแจ้งเตือนแบบพุชเกี่ยวกับกิจกรรมและการเปลี่ยนแปลงการปฏิบัติงาน';

  @override
  String get restaurantPushRequiresSetup =>
      'การแจ้งเตือนแบบพุชจะใช้ได้เมื่อกำหนดค่า Firebase และการแจ้งเตือนของแพลตฟอร์มนี้ครบถ้วน';

  @override
  String get restaurantPushEnableFailed =>
      'เปิดการแจ้งเตือนไม่สำเร็จ โปรดตรวจสอบสิทธิ์การแจ้งเตือนของโทรศัพท์และการตั้งค่า Firebase';

  @override
  String get restaurantNotificationView => 'ดู';

  @override
  String get restaurantSignOutPendingEvents =>
      'เหตุการณ์ที่รอซิงค์ยังคงอยู่ในโทรศัพท์นี้';

  @override
  String get restaurantOperationalAppLabel => 'Pollo Móvil · แอปปฏิบัติงาน';

  @override
  String get restaurantNotificationsTitle => 'การแจ้งเตือน';

  @override
  String get restaurantNotificationsQueuedRead =>
      'กล่องข้อความจะอัปเดตเมื่อกลับมาเชื่อมต่อ';

  @override
  String get restaurantNotificationsMarkAllRead =>
      'ทำเครื่องหมายว่าอ่านแล้วทั้งหมด';

  @override
  String restaurantNotificationsLoadError(String error) {
    return 'โหลดการแจ้งเตือนไม่ได้ $error';
  }

  @override
  String get restaurantNotificationsOfflineEmpty =>
      'สำเนาที่บันทึกไว้ไม่มีการแจ้งเตือน เชื่อมต่ออินเทอร์เน็ตเพื่ออัปเดตกล่องข้อความ';

  @override
  String get restaurantNotificationsEmpty => 'ยังไม่มีการแจ้งเตือน';

  @override
  String get restaurantNotificationsOfflineTitle =>
      'กล่องข้อความที่บันทึกไว้ขณะออฟไลน์';

  @override
  String get restaurantNotificationsOfflineBody =>
      'สถานะอาจเปลี่ยนไปตั้งแต่การอัปเดตครั้งล่าสุด';

  @override
  String get restaurantNotificationFallbackTitle => 'การแจ้งเตือน';

  @override
  String get restaurantNotificationReadPending => 'รอซิงค์สถานะการอ่าน';

  @override
  String get restaurantNotificationMarkRead => 'ทำเครื่องหมายว่าอ่านแล้ว';

  @override
  String get restaurantInspectionQueued =>
      'บันทึกการตรวจไว้ในโทรศัพท์แล้ว และจะซิงค์เมื่อกลับมาเชื่อมต่อ';

  @override
  String get restaurantInspectionSaved => 'บันทึกการตรวจแล้ว';

  @override
  String restaurantInspectionNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'บันทึกการตรวจแล้ว มี $count รายการที่ต้องใส่ใจ',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInspectionNoActiveCriteria =>
      'รายการตรวจนี้ไม่มีเกณฑ์ที่ใช้งานอยู่ โปรดให้ผู้ดูแลกำหนดค่า';

  @override
  String get restaurantInspectionInstruction =>
      'บันทึกสถานะที่ตรวจพบของแต่ละเกณฑ์ที่สาขากำหนด';

  @override
  String get restaurantInspectionCriterion => 'เกณฑ์';

  @override
  String get restaurantInspectionObservedState => 'สถานะที่ตรวจพบ';

  @override
  String get restaurantInspectionResultOk => 'ปกติ';

  @override
  String get restaurantInspectionResultNeedsAttention => 'ต้องใส่ใจ';

  @override
  String get restaurantInspectionResultNotApplicable => 'ไม่เกี่ยวข้อง';

  @override
  String get restaurantInspectionOptionalDetail =>
      'รายละเอียดเพิ่มเติม (ไม่บังคับ)';

  @override
  String get restaurantInspectionOptionalGeneralNote =>
      'หมายเหตุทั่วไป (ไม่บังคับ)';

  @override
  String get restaurantInspectionSaving => 'กำลังบันทึก…';

  @override
  String get restaurantInspectionSave => 'บันทึกการตรวจ';

  @override
  String get restaurantInspectionOfflineHelp =>
      'หากออฟไลน์ การตรวจจะอยู่ในโทรศัพท์และส่งเมื่อกลับมาเชื่อมต่อ';

  @override
  String get restaurantInspectionDefaultTitle => 'การตรวจ';

  @override
  String get restaurantShiftScheduleTitle => 'ตารางกะ';

  @override
  String get restaurantShiftSaved => 'บันทึกกะแล้ว';

  @override
  String get restaurantShiftUpdated => 'อัปเดตกะแล้ว';

  @override
  String restaurantShiftSaveError(String error) {
    return 'บันทึกกะไม่ได้: $error';
  }

  @override
  String get restaurantShiftCancelTitle => 'ยกเลิกกะ';

  @override
  String restaurantShiftCancelConfirmation(String employee) {
    return 'ยกเลิกกะของ $employee หรือไม่';
  }

  @override
  String get restaurantShiftCanceled => 'ยกเลิกกะแล้ว';

  @override
  String restaurantShiftCancelError(String error) {
    return 'ยกเลิกกะไม่ได้: $error';
  }

  @override
  String get restaurantShiftLoadError => 'โหลดตารางกะของสัปดาห์นี้ไม่ได้';

  @override
  String get restaurantShiftPreviousWeek => 'สัปดาห์ก่อนหน้า';

  @override
  String get restaurantShiftNextWeek => 'สัปดาห์ถัดไป';

  @override
  String get restaurantShiftOfflineNotice =>
      'ออฟไลน์: แสดงตารางล่าสุดที่บันทึกไว้ และจะแก้ไขกะได้เมื่อกลับมาเชื่อมต่อ';

  @override
  String restaurantShiftTimezone(String timeZone) {
    return 'เวลาใช้เขตเวลาท้องถิ่นของสาขา: $timeZone';
  }

  @override
  String get restaurantShiftAdd => 'เพิ่มกะ';

  @override
  String get restaurantShiftNoShifts => 'ยังไม่มีกะที่กำหนดไว้';

  @override
  String get restaurantShiftTeamMember => 'สมาชิกในทีม';

  @override
  String get restaurantShiftPublished => 'เผยแพร่แล้ว';

  @override
  String get restaurantShiftDraft => 'ฉบับร่าง';

  @override
  String restaurantShiftTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String restaurantShiftBreaks(String breaks) {
    return 'เวลาพัก: $breaks';
  }

  @override
  String get restaurantShiftEdit => 'แก้ไข';

  @override
  String get restaurantShiftCancelAction => 'ยกเลิกกะ';

  @override
  String get restaurantShiftAddDialogTitle => 'เพิ่มกะ';

  @override
  String get restaurantShiftEditDialogTitle => 'แก้ไขกะ';

  @override
  String get restaurantShiftEmployee => 'พนักงาน';

  @override
  String get restaurantShiftDay => 'วัน';

  @override
  String get restaurantShiftStartChoose => 'เวลาเริ่ม: เลือก';

  @override
  String get restaurantShiftEndChoose => 'เวลาสิ้นสุด: เลือก';

  @override
  String get restaurantShiftStart => 'เริ่ม';

  @override
  String get restaurantShiftEnd => 'สิ้นสุด';

  @override
  String get restaurantShiftPublish => 'เผยแพร่กะ';

  @override
  String get restaurantShiftDraftDescription =>
      'หากปิดไว้ กะนี้จะบันทึกเป็นฉบับร่าง';

  @override
  String get restaurantShiftBreaksTitle => 'เวลาพัก';

  @override
  String get restaurantShiftAddBreak => 'เพิ่ม';

  @override
  String get restaurantShiftRemoveBreak => 'นำเวลาพักออก';

  @override
  String get restaurantShiftSave => 'บันทึก';

  @override
  String get restaurantTeamTitle => 'ทีมของสาขา';

  @override
  String get restaurantTeamUpdated => 'อัปเดตข้อมูลสมาชิกในทีมแล้ว';

  @override
  String restaurantTeamSaveError(String error) {
    return 'บันทึกการเปลี่ยนแปลงทั้งหมดไม่ได้: $error';
  }

  @override
  String get restaurantInviteDialogTitle => 'เชิญพนักงาน';

  @override
  String get restaurantInviteLinkTitle => 'ลิงก์คำเชิญ';

  @override
  String get restaurantInviteAction => 'เชิญพนักงาน';

  @override
  String get restaurantInviteEmailNotSent =>
      'ส่งอีเมลอัตโนมัติไม่ได้ โปรดคัดลอกลิงก์และส่งให้ผู้ได้รับเชิญ';

  @override
  String get restaurantInviteCopied => 'คัดลอกลิงก์คำเชิญแล้ว';

  @override
  String get restaurantInviteCopyLink => 'คัดลอกลิงก์';

  @override
  String get restaurantClose => 'ปิด';

  @override
  String get restaurantInviteSent => 'ส่งคำเชิญแล้ว';

  @override
  String get restaurantInviteAlreadyMember =>
      'บุคคลนี้เป็นสมาชิกของสาขานี้อยู่แล้ว';

  @override
  String get restaurantInviteAccountAdded => 'เพิ่มบัญชีเข้าสาขาแล้ว';

  @override
  String restaurantInviteError(String error) {
    return 'เชิญบุคคลนี้ไม่ได้: $error';
  }

  @override
  String get restaurantTeamLoadError => 'โหลดทีมของสาขาไม่ได้';

  @override
  String get restaurantTeamOfflineTitle => 'กำลังแสดงทีมที่บันทึกล่าสุด';

  @override
  String get restaurantTeamOfflineBody =>
      'ข้อมูลนี้อ่านได้อย่างเดียวจนกว่าจะกลับมาเชื่อมต่อ';

  @override
  String get restaurantTeamEmpty => 'สาขานี้ยังไม่มีสมาชิกในทีม';

  @override
  String restaurantTeamMemberCount(int count) {
    return '$count คนในทีม';
  }

  @override
  String get restaurantInviteFullName => 'ชื่อและนามสกุล';

  @override
  String get restaurantInviteEmail => 'อีเมล';

  @override
  String get restaurantInviteNameValidation => 'โปรดกรอกชื่อและนามสกุล';

  @override
  String get restaurantInvitePermissionNote =>
      'คำเชิญจะส่งไปยังอีเมลนี้ สมาชิกใหม่จะได้รับสิทธิ์พนักงาน';

  @override
  String get restaurantInviteSubmit => 'ส่งคำเชิญ';

  @override
  String get restaurantRoleLabel => 'บทบาทในสาขา';

  @override
  String get restaurantRoleEmployee => 'พนักงาน';

  @override
  String get restaurantRoleSupervisor => 'หัวหน้างาน';

  @override
  String get restaurantRoleAdmin => 'ผู้ดูแลระบบ';

  @override
  String get restaurantMemberActive => 'ใช้งานอยู่';

  @override
  String get restaurantMemberInactive => 'ไม่ได้ใช้งาน';

  @override
  String get restaurantMemberAccess => 'สิทธิ์เข้าถึงสาขา';

  @override
  String get restaurantMemberDeactivateNote =>
      'เมื่อปิดใช้งาน ประวัติกะและงานจะยังคงอยู่';

  @override
  String get restaurantMemberPositions => 'ตำแหน่งที่เปิดใช้งาน';

  @override
  String get restaurantPositionFallback => 'ตำแหน่ง';

  @override
  String get restaurantMemberReactivateToEdit =>
      'เปิดสิทธิ์เข้าสาขาอีกครั้งเพื่อแก้ไขตำแหน่ง';

  @override
  String get restaurantMemberConfigurePositions =>
      'กำหนดตำแหน่งก่อนมอบหมายให้ทีม';

  @override
  String get restaurantMemberSaveChanges => 'บันทึกการเปลี่ยนแปลง';

  @override
  String get restaurantAbsenceReviewTitle => 'คำขอลางาน';

  @override
  String get restaurantAbsenceApproved => 'อนุมัติคำขอแล้ว';

  @override
  String get restaurantAbsenceRejected => 'ปฏิเสธคำขอแล้ว';

  @override
  String restaurantAbsenceReviewError(String error) {
    return 'ตรวจสอบคำขอไม่ได้: $error';
  }

  @override
  String get restaurantAbsenceLoadError => 'โหลดคำขอที่รอดำเนินการไม่ได้';

  @override
  String get restaurantAbsenceNone => 'ไม่มีคำขอที่รอดำเนินการ';

  @override
  String get restaurantAbsenceOfflineNotice =>
      'ออฟไลน์: แสดงคำขอจากการอัปเดตครั้งล่าสุด ต้องเชื่อมต่ออินเทอร์เน็ตเพื่ออนุมัติหรือปฏิเสธ';

  @override
  String get restaurantAbsenceOfflineEmpty =>
      'ไม่มีคำขอที่รอดำเนินการในการอัปเดตครั้งล่าสุด';

  @override
  String get restaurantAbsenceReject => 'ปฏิเสธ';

  @override
  String get restaurantAbsenceApprove => 'อนุมัติ';

  @override
  String get restaurantCalendarTitle => 'ปฏิทินกิจกรรม';

  @override
  String get restaurantCalendarRefresh => 'รีเฟรชปฏิทิน';

  @override
  String get restaurantCalendarLoadError => 'โหลดปฏิทินไม่ได้';

  @override
  String get restaurantCalendarRetry => 'ลองอีกครั้ง';

  @override
  String get restaurantCalendarPreviousWeek => 'สัปดาห์ก่อนหน้า';

  @override
  String get restaurantCalendarNextWeek => 'สัปดาห์ถัดไป';

  @override
  String get restaurantCalendarManagerHint =>
      'กำหนดเวลาได้เฉพาะกิจกรรมที่ตั้งค่าไว้';

  @override
  String get restaurantCalendarBranchHint => 'กิจกรรมที่มอบหมายให้สาขาของคุณ';

  @override
  String get restaurantCalendarOffline =>
      'ออฟไลน์: แสดงสัปดาห์ที่บันทึกไว้ล่าสุด การจัดตารางเป็นแบบอ่านอย่างเดียวจนกว่าจะเชื่อมต่ออีกครั้ง';

  @override
  String get restaurantCalendarRetroactive =>
      'ไม่สามารถกำหนดเวลากิจกรรมย้อนหลังจากปฏิทินได้';

  @override
  String restaurantCalendarDayScheduled(int count) {
    return 'สร้างกิจกรรมใหม่ $count รายการตามกฎของสาขาแล้ว กิจกรรมเดิมจะไม่ซ้ำ';
  }

  @override
  String get restaurantCalendarPastWeek =>
      'สัปดาห์นี้ผ่านไปแล้ว ไม่มีการเปลี่ยนแปลงวันที่';

  @override
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays) {
    return 'กำหนดเวลากิจกรรม $created รายการใน $days วันที่ วันที่ผ่านมาไม่เปลี่ยนแปลง และข้ามวันที่ผ่านมาแล้ว $pastDays วัน กิจกรรมเดิมจะไม่ซ้ำ';
  }

  @override
  String restaurantCalendarWeekPartial(int created, int days, String dates) {
    return 'กำหนดเวลากิจกรรม $created รายการใน $days วันที่ไม่สำเร็จ: $dates ลองใหม่ได้ โดยกิจกรรมเดิมจะไม่ซ้ำ';
  }

  @override
  String get restaurantCalendarPlanWeek => 'จัดตารางสัปดาห์ที่แสดง';

  @override
  String get restaurantCalendarPlanningWeek => 'กำลังจัดตารางสัปดาห์…';

  @override
  String restaurantCalendarWeekActivities(int count) {
    return 'กิจกรรมสัปดาห์นี้ $count รายการ';
  }

  @override
  String restaurantCalendarUnassignedCount(int count) {
    return 'รายการที่ยังไม่มอบหมาย $count รายการ';
  }

  @override
  String restaurantCalendarCompletedCount(int count) {
    return 'เสร็จแล้ว $count รายการ';
  }

  @override
  String restaurantCalendarActivityCount(int count) {
    return 'กิจกรรม $count รายการ';
  }

  @override
  String get restaurantCalendarPastDate =>
      'วันที่ผ่านมาแล้ว ไม่สามารถสร้างกิจกรรมย้อนหลังได้';

  @override
  String get restaurantCalendarScheduleFromRules => 'จัดตารางตามกฎ';

  @override
  String get restaurantCalendarScheduling => 'กำลังจัดตาราง…';

  @override
  String get restaurantCalendarAssignEligible => 'มอบหมายให้ผู้ที่มีสิทธิ์';

  @override
  String get restaurantCalendarAssigning => 'กำลังมอบหมาย…';

  @override
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  ) {
    return 'มอบหมายกิจกรรม $assigned รายการด้วย$planner และไม่มีพนักงานที่มีสิทธิ์ $unassigned รายการ';
  }

  @override
  String get restaurantCalendarLocalPlanner => 'ตัวจัดตารางภายในเครื่อง';

  @override
  String get restaurantCalendarNoActivities => 'ไม่มีกิจกรรมที่กำหนดเวลาไว้';

  @override
  String get restaurantCalendarFallbackActivity => 'กิจกรรม';

  @override
  String get restaurantCalendarNoAssignee => 'ยังไม่มอบหมาย';

  @override
  String get restaurantCalendarConfigurationPending =>
      'ตั้งค่าตำแหน่ง พื้นที่ หรือข้อกำหนดของสาขาก่อนมอบหมายกิจกรรมนี้';

  @override
  String get restaurantCalendarAssignee => 'ผู้รับผิดชอบ';

  @override
  String get restaurantCalendarFallbackAssignee => 'ผู้รับผิดชอบปัจจุบัน';

  @override
  String restaurantCalendarInactiveAssignee(String name) {
    return '$name · ไม่ใช้งาน';
  }

  @override
  String get restaurantCalendarEmployeeFallback => 'พนักงาน';

  @override
  String get restaurantCalendarZoneFallback => 'ส่วนงาน';

  @override
  String restaurantCalendarZoneAssignee(String zone) {
    return 'ผู้รับผิดชอบ$zone';
  }

  @override
  String get restaurantCalendarStatusPending => 'รอดำเนินการ';

  @override
  String get restaurantCalendarStatusInProgress => 'กำลังดำเนินการ';

  @override
  String get restaurantCalendarStatusPaused => 'หยุดชั่วคราว';

  @override
  String get restaurantCalendarStatusBlocked => 'ถูกระงับ';

  @override
  String get restaurantCalendarStatusCompleted => 'เสร็จแล้ว';

  @override
  String get restaurantCalendarTaskAssigneeUpdated =>
      'อัปเดตผู้รับผิดชอบกิจกรรมแล้ว';

  @override
  String get restaurantCalendarPartAssigneeUpdated =>
      'อัปเดตผู้รับผิดชอบส่วนงานแล้ว';

  @override
  String get restaurantStructureTitle => 'พื้นที่และตำแหน่ง';

  @override
  String get restaurantStructureAreas => 'พื้นที่';

  @override
  String get restaurantStructurePositions => 'ตำแหน่ง';

  @override
  String restaurantStructureAdd(String label) {
    return 'เพิ่ม$label';
  }

  @override
  String restaurantStructureEdit(String label) {
    return 'แก้ไข$label';
  }

  @override
  String restaurantStructureSaved(String label) {
    return 'บันทึก$labelแล้ว';
  }

  @override
  String restaurantStructureSaveError(String label, String error) {
    return 'บันทึก$labelไม่ได้: $error';
  }

  @override
  String restaurantStructureReactivateTitle(String label) {
    return 'เปิดใช้งาน$labelอีกครั้ง';
  }

  @override
  String restaurantStructureDeactivateTitle(String label) {
    return 'ปิดใช้งาน$label';
  }

  @override
  String get restaurantStructureReactivateDescription =>
      'เลือกใช้งานกับกิจกรรมใหม่ได้อีกครั้ง';

  @override
  String get restaurantStructureDeactivateDescription =>
      'จะซ่อนจากกิจกรรมใหม่ แต่เก็บประวัติเดิมไว้';

  @override
  String get restaurantStructureBack => 'กลับ';

  @override
  String get restaurantStructureReactivateAction => 'เปิดใช้งานอีกครั้ง';

  @override
  String get restaurantStructureDeactivateAction => 'ปิดใช้งาน';

  @override
  String get restaurantStructureEmpty => 'ยังไม่มีการตั้งค่ารายการ';

  @override
  String get restaurantStructureStatusActive => 'สถานะ: ใช้งาน';

  @override
  String get restaurantStructureStatusInactive => 'สถานะ: ไม่ใช้งาน';

  @override
  String restaurantStructureAddTooltip(String label) {
    return 'เพิ่ม$label';
  }

  @override
  String get restaurantStructureEditName => 'แก้ไขชื่อ';

  @override
  String get restaurantStructureOfflineTitle =>
      'แสดงการตั้งค่าที่บันทึกไว้ล่าสุด';

  @override
  String get restaurantStructureOfflineBody =>
      'พื้นที่ ตำแหน่ง และฟังก์ชันเป็นแบบอ่านอย่างเดียวจนกว่าจะเชื่อมต่ออีกครั้ง';

  @override
  String get restaurantStructureKeepHistory =>
      'ปิดใช้งานแทนการลบเพื่อเก็บประวัติการดำเนินงาน';

  @override
  String get restaurantStructureLoadError => 'โหลดการตั้งค่าสาขาไม่ได้';

  @override
  String get restaurantStructureRetry => 'ลองอีกครั้ง';

  @override
  String get restaurantAttendanceTitle => 'การเข้างานและตำแหน่ง';

  @override
  String get restaurantAttendanceOptional =>
      'แต่ละสาขาเลือกเปิดใช้ได้ และปิดไว้เป็นค่าเริ่มต้น';

  @override
  String get restaurantAttendanceEnableClock => 'เปิดใช้ระบบบันทึกเวลา';

  @override
  String get restaurantAttendanceClockDescription =>
      'บันทึกเวลาเข้าและออก ไม่คำนวณเงินเดือน';

  @override
  String get restaurantAttendanceRequestGps => 'ขอ GPS ในการลงเวลาแต่ละครั้ง';

  @override
  String get restaurantAttendanceGpsDescription =>
      'ตรวจตำแหน่งเฉพาะตอนลงเวลาเข้าและออกเท่านั้น ไม่มีการติดตามต่อเนื่อง';

  @override
  String get restaurantAttendanceSaveFeatures => 'บันทึกฟังก์ชัน';

  @override
  String get restaurantAttendanceSaved => 'อัปเดตฟังก์ชันการเข้างานแล้ว';

  @override
  String restaurantAttendanceSaveError(String error) {
    return 'บันทึกการตั้งค่าไม่ได้: $error';
  }

  @override
  String get restaurantStructureName => 'ชื่อ';

  @override
  String get restaurantStructureSave => 'บันทึก';

  @override
  String get restaurantEvidenceTitle => 'หลักฐานกิจกรรม';

  @override
  String get restaurantEvidenceCameraMissing => 'ไม่พบกล้อง';

  @override
  String get restaurantEvidenceCameraOpenError => 'เปิดกล้องไม่ได้';

  @override
  String get restaurantEvidencePhotoSaveError =>
      'บันทึกรูปภาพไม่ได้ โปรดลองอีกครั้ง';

  @override
  String get restaurantEvidenceSaving => 'กำลังบันทึก…';

  @override
  String get restaurantEvidenceTakePhoto => 'ถ่ายรูป';

  @override
  String get restaurantSyncOffline => 'ออฟไลน์';

  @override
  String restaurantSyncOfflinePending(int count) {
    return 'ออฟไลน์ มีรายการรอ $count รายการ';
  }

  @override
  String restaurantSyncAttentionCount(int count) {
    return 'มีรายการที่ต้องตรวจสอบ $count รายการ';
  }

  @override
  String restaurantSyncPendingCount(int count) {
    return 'มีรายการรอซิงค์ $count รายการ';
  }

  @override
  String get restaurantSyncAllDone => 'ซิงค์ทั้งหมดแล้ว';

  @override
  String restaurantSyncTooltip(String status) {
    return '$status แตะเพื่อซิงค์ตอนนี้';
  }

  @override
  String get restaurantSyncStarted => 'เริ่มซิงค์รายการที่รออยู่แล้ว';

  @override
  String get restaurantSyncOfflineSaved =>
      'ออฟไลน์ รายการยังบันทึกอยู่ในโทรศัพท์นี้';

  @override
  String get restaurantSyncFailure =>
      'ซิงค์ตอนนี้ไม่ได้ รายการยังบันทึกอยู่ในโทรศัพท์นี้';

  @override
  String get restaurantSyncRetryQueued => 'นำรายการกลับเข้าคิวซิงค์แล้ว';

  @override
  String get restaurantSyncRetryFailed =>
      'ยังลองใหม่ไม่ได้ รายการยังบันทึกอยู่ในโทรศัพท์นี้';

  @override
  String get restaurantSyncEventClock => 'บันทึกเวลา: เข้าและออก';

  @override
  String get restaurantSyncEventOperations => 'รายการปฏิบัติงาน';

  @override
  String get restaurantSyncEventClockEvent => 'เวลาเข้าและออก';

  @override
  String get restaurantSyncEventEvidence => 'หลักฐานภาพถ่าย';

  @override
  String get restaurantSyncEventPending => 'รายการที่รอดำเนินการ';

  @override
  String restaurantSyncAttentionNotice(int count) {
    return 'มีรายการที่ต้องตรวจสอบ $count รายการ';
  }

  @override
  String get restaurantSyncAttentionHelp =>
      'เก็บรายการไว้ในโทรศัพท์นี้แล้ว ลองใหม่เมื่อเชื่อมต่อ หากรายการเป็นของบัญชีอื่น ให้เข้าสู่ระบบด้วยบัญชีนั้น';

  @override
  String get restaurantSyncRequiresOriginalAccount => 'ต้องใช้บัญชีเดิม';

  @override
  String get restaurantSyncRetry => 'ลองอีกครั้ง';

  @override
  String get restaurantOpsShiftTitle => 'กะของฉัน';

  @override
  String get restaurantOpsWasteTitle => 'ตรวจถังขยะ';

  @override
  String get restaurantOpsIncidentsTitle => 'เหตุขัดข้อง';

  @override
  String get restaurantOpsHandoffTitle => 'ส่งมอบกะ';

  @override
  String get restaurantOpsBranchesLoadError => 'โหลดสาขาของคุณไม่ได้';

  @override
  String get restaurantOpsShiftLoadError => 'โหลดกะไม่ได้';

  @override
  String get restaurantOpsBranchFallback => 'สาขา';

  @override
  String get restaurantOpsOfflineTitle =>
      'แสดงข้อมูลการดำเนินงานที่บันทึกไว้ล่าสุด';

  @override
  String get restaurantOpsOfflinePendingChanges =>
      'การเปลี่ยนแปลงใหม่จะเก็บไว้ในโทรศัพท์นี้จนกว่าจะเชื่อมต่ออีกครั้ง';

  @override
  String restaurantOpsOfflineSnapshotAt(String time) {
    return 'สำเนาเมื่อ $time การเปลี่ยนแปลงใหม่จะเก็บไว้ในโทรศัพท์นี้จนกว่าจะเชื่อมต่ออีกครั้ง';
  }

  @override
  String get restaurantOpsSavedOffline =>
      'บันทึกไว้ในโทรศัพท์นี้แล้ว จะซิงค์เมื่อเชื่อมต่ออีกครั้ง';

  @override
  String get restaurantOpsSaved => 'เรียบร้อย บันทึกการเปลี่ยนแปลงแล้ว';

  @override
  String get restaurantOpsHandoffDelivered =>
      'บันทึกการส่งมอบพร้อมสถานะกะปัจจุบันแล้ว';

  @override
  String get restaurantOpsSwitchBranch => 'เปลี่ยนสาขา';

  @override
  String get restaurantOpsRefresh => 'รีเฟรช';

  @override
  String get restaurantOpsPauseTitle => 'หยุดกิจกรรมชั่วคราว';

  @override
  String get restaurantOpsPauseOptionalNote =>
      'หมายเหตุสำหรับกะถัดไป (ไม่บังคับ)';

  @override
  String get restaurantOpsPauseContinue => 'ทำงานต่อ';

  @override
  String get restaurantOpsPauseAction => 'หยุดกิจกรรม';

  @override
  String get restaurantOpsPauseHint =>
      'บริบทการทำงานสำหรับผู้ที่จะกลับมาทำกิจกรรมต่อ';

  @override
  String get restaurantOpsNoUpcomingShifts =>
      'ไม่มีการเผยแพร่กะในสองสัปดาห์ข้างหน้า';

  @override
  String get restaurantOpsToday => 'วันนี้';

  @override
  String get restaurantOpsTomorrow => 'พรุ่งนี้';

  @override
  String get restaurantOpsCalendarDescription =>
      'ดูกิจกรรมที่กำหนดเวลาไว้ของสาขา';

  @override
  String get restaurantOpsCustomerService => 'ฉันกำลังให้บริการลูกค้า';

  @override
  String get restaurantOpsInterruptibleWait => 'งานที่หยุดชั่วคราวได้จะรออยู่';

  @override
  String get restaurantOpsOwnActivities => 'กิจกรรมของคุณ';

  @override
  String get restaurantOpsNoOwnActivities =>
      'ไม่มีกิจกรรมที่มอบหมายให้คุณในกะนี้';

  @override
  String get restaurantOpsBranchStructureDescription =>
      'กำหนดโครงสร้างการดำเนินงานของสาขานี้';

  @override
  String get restaurantOpsTeamDescription =>
      'จัดการสิทธิ์ บทบาท และตำแหน่งของสาขา';

  @override
  String get restaurantOpsShiftAdminDescription =>
      'จัดการกะ เวลาพัก และการเผยแพร่ให้ทีม';

  @override
  String get restaurantOpsPendingAbsences => 'คำขอที่รอดำเนินการ';

  @override
  String get restaurantOpsAbsenceReviewDescription =>
      'ตรวจสอบ อนุมัติ หรือปฏิเสธคำขอของทีม';

  @override
  String get restaurantOpsTaskPendingSync =>
      'บันทึกการเปลี่ยนแปลงในโทรศัพท์แล้ว กำลังรอซิงค์';

  @override
  String restaurantOpsPauseReason(String note) {
    return 'เหตุผลที่หยุด: $note';
  }

  @override
  String restaurantOpsAssigneeNamed(String name) {
    return 'ผู้รับผิดชอบ: $name';
  }

  @override
  String get restaurantOpsZoneFallback => 'พื้นที่';

  @override
  String get restaurantOpsYou => 'คุณ';

  @override
  String get restaurantOpsActionClaim => 'รับงาน';

  @override
  String get restaurantOpsActionStart => 'เริ่ม';

  @override
  String get restaurantOpsActionPause => 'หยุดชั่วคราว';

  @override
  String get restaurantOpsActionComplete => 'เสร็จสิ้น';

  @override
  String get restaurantOpsActionResume => 'ทำต่อ';

  @override
  String get restaurantOpsAbsencePendingNote =>
      'คำขอจะรอจนกว่าหัวหน้างานจะตรวจสอบ';

  @override
  String get restaurantOpsDateFrom => 'ตั้งแต่';

  @override
  String get restaurantOpsDateUntil => 'ถึง';

  @override
  String get restaurantOpsOptionalNote => 'หมายเหตุ (ไม่บังคับ)';

  @override
  String get restaurantOpsAbsenceSend => 'ส่งคำขอ';

  @override
  String get restaurantOpsAbsenceSending => 'กำลังส่ง…';

  @override
  String get restaurantOpsAbsenceOfflineNote =>
      'ออฟไลน์ ระบบจะบันทึกคำขอเพื่อซิงค์ภายหลัง';

  @override
  String get restaurantOpsSavedAbsencesTitle => 'คำขอที่บันทึกไว้ในโทรศัพท์นี้';

  @override
  String get restaurantOpsSyncReviewNeeded => 'ตรวจสอบสถานะการซิงค์';

  @override
  String get restaurantOpsPendingSend => 'รอส่ง';

  @override
  String get restaurantOpsUnassignedSection => 'ยังไม่มอบหมาย';

  @override
  String get restaurantOpsAbsenceStatusDenied => 'ไม่ได้รับอนุมัติ';

  @override
  String get restaurantOpsWasteIntro =>
      'การตรวจครั้งเดียวจะบันทึกสถานะที่แจ้งของถังแต่ละใบ';

  @override
  String get restaurantOpsWasteNeedsAttention =>
      'รายการตรวจในเครื่องต้องตรวจสอบในเมนูซิงค์ อย่าบันทึกซ้ำจนกว่าจะแก้ไขแล้ว';

  @override
  String get restaurantOpsWastePendingSync =>
      'บันทึกรายการตรวจในโทรศัพท์แล้ว จะซิงค์เมื่อเชื่อมต่ออีกครั้ง';

  @override
  String get restaurantOpsWasteStatusTitle => 'สถานะถังขยะ';

  @override
  String get restaurantOpsBinFallback => 'ถังขยะ';

  @override
  String restaurantOpsIntervalConfigured(String minutes) {
    return 'ช่วงเวลาที่ตั้งไว้: $minutes นาที';
  }

  @override
  String get restaurantOpsInspectionDue => 'ถึงกำหนดตรวจตามช่วงเวลาที่ตั้งไว้';

  @override
  String get restaurantOpsWasteNeedsPolicy =>
      'ตั้งค่างานที่จะสร้างก่อนระบุว่าถังนี้เต็ม';

  @override
  String get restaurantOpsDeclaredState => 'สถานะที่แจ้ง';

  @override
  String get restaurantOpsSelectState => 'เลือกสถานะ';

  @override
  String get restaurantOpsBinLow => 'ว่างหรือเหลือน้อย';

  @override
  String get restaurantOpsBinHalf => 'ครึ่งถัง';

  @override
  String get restaurantOpsBinFull => 'เต็ม';

  @override
  String get restaurantOpsCannotSaveFullBin =>
      'บันทึกการตรวจไม่ได้: ตั้งค่าชื่องาน ระยะเวลา ความยาก และลำดับความสำคัญสำหรับถังเต็ม';

  @override
  String get restaurantOpsWastePendingAction => 'รายการตรวจรอซิงค์';

  @override
  String get restaurantOpsSaving => 'กำลังบันทึก…';

  @override
  String get restaurantOpsWasteSubmit => 'บันทึกการตรวจ';

  @override
  String get restaurantOpsAreaInspectionsTitle => 'การตรวจพื้นที่อื่น';

  @override
  String get restaurantOpsNoInspectionTemplates =>
      'สาขานี้ยังไม่ได้ตั้งค่ารายการตรวจ';

  @override
  String get restaurantOpsInspectionFallback => 'การตรวจ';

  @override
  String restaurantOpsInspectionCriteriaCount(int count) {
    return 'ตั้งค่าเกณฑ์ไว้ $count ข้อ';
  }

  @override
  String restaurantOpsInspectionInterval(String minutes) {
    return 'ทุก $minutes นาที';
  }

  @override
  String get restaurantOpsInspectionNeedsAttention =>
      'รายการตรวจในเครื่องต้องตรวจสอบในเมนูซิงค์';

  @override
  String restaurantOpsInspectionPendingSync(int count) {
    return 'บันทึกการตรวจในโทรศัพท์แล้ว มีเกณฑ์ที่ต้องตรวจสอบ $count ข้อ';
  }

  @override
  String get restaurantOpsDoInspection => 'เริ่มตรวจพื้นที่';

  @override
  String get restaurantOpsInspectionPendingAction => 'รายการตรวจรอซิงค์';

  @override
  String restaurantOpsRecentInspections(int count) {
    return 'รายการล่าสุด ($count)';
  }

  @override
  String get restaurantOpsTeamFallback => 'ทีม';

  @override
  String restaurantOpsNeedsAttentionCount(int count) {
    return 'มีรายการที่ต้องตรวจสอบ $count รายการ';
  }

  @override
  String get restaurantOpsNoAlerts => 'ไม่มีการแจ้งเตือน';

  @override
  String get restaurantOpsCriterionFallback => 'เกณฑ์';

  @override
  String restaurantOpsCriterionNote(String label, String note) {
    return '$label: $note';
  }

  @override
  String get restaurantOpsIncidentReport => 'รายงานปัญหา';

  @override
  String get restaurantOpsIncidentDescription => 'คำอธิบายโดยย่อ';

  @override
  String get restaurantOpsIncidentAreaOptional => 'พื้นที่ (ไม่บังคับ)';

  @override
  String get restaurantOpsIncidentNoArea => 'ไม่มีพื้นที่';

  @override
  String get restaurantOpsUrgency => 'ความเร่งด่วน';

  @override
  String get restaurantOpsUrgencyLow => 'ต่ำ';

  @override
  String get restaurantOpsUrgencyNormal => 'ปกติ';

  @override
  String get restaurantOpsUrgencyHigh => 'สูง';

  @override
  String get restaurantOpsUrgencyUrgent => 'เร่งด่วน';

  @override
  String get restaurantOpsIncidentBlocksWork => 'ขัดขวางการทำงาน';

  @override
  String get restaurantOpsIncidentSend => 'ส่งรายงานเหตุขัดข้อง';

  @override
  String get restaurantOpsOpenIncidents => 'เหตุขัดข้องที่เปิดอยู่';

  @override
  String get restaurantOpsNoOpenIncidents => 'ไม่มีเหตุขัดข้องที่เปิดอยู่';

  @override
  String get restaurantOpsSavedIncidentsTitle => 'บันทึกไว้ในโทรศัพท์นี้';

  @override
  String get restaurantOpsIncidentFallback => 'เหตุขัดข้อง';

  @override
  String get restaurantOpsIncidentNeedsAttention => 'ตรวจสอบสถานะการซิงค์';

  @override
  String get restaurantOpsIncidentPendingSync => 'รอซิงค์';

  @override
  String get restaurantOpsIncidentBlockingUnconfirmed =>
      'รายงานว่าขัดขวางงาน แต่เซิร์ฟเวอร์ยังไม่ยืนยัน';

  @override
  String get restaurantOpsIncidentStatusOpen => 'เปิดอยู่';

  @override
  String get restaurantOpsIncidentStatusInProgress => 'กำลังดำเนินการ';

  @override
  String get restaurantOpsIncidentStatusResolved => 'แก้ไขแล้ว';

  @override
  String get restaurantOpsHandoffSummary =>
      'สรุปกะอัตโนมัติ ไม่ต้องเขียนรายงานซ้ำ';

  @override
  String restaurantOpsHandoffCompletedCount(int count) {
    return 'เสร็จแล้ว ($count)';
  }

  @override
  String get restaurantOpsHandoffNoCompleted =>
      'วันนี้ยังไม่มีกิจกรรมที่เสร็จสิ้น';

  @override
  String restaurantOpsHandoffOutstandingCount(int count) {
    return 'รอดำเนินการหรือหยุดชั่วคราว ($count)';
  }

  @override
  String get restaurantOpsHandoffNoOutstanding => 'ไม่มีกิจกรรมที่รอดำเนินการ';

  @override
  String restaurantOpsHandoffIncidentCount(int count) {
    return 'เหตุขัดข้องที่เปิดอยู่ ($count)';
  }

  @override
  String get restaurantOpsHandoffDeliveryTitle => 'ส่งมอบและรับกะ';

  @override
  String get restaurantOpsHandoffSnapshotNote =>
      'เมื่อส่งมอบกะ ระบบจะบันทึกภาพรวมกิจกรรมที่ค้างและเหตุขัดข้องที่เปิดอยู่';

  @override
  String get restaurantOpsHandoffRecipient => 'ผู้รับช่วงกะ';

  @override
  String get restaurantOpsHandoffNoRecipient => 'ไม่ระบุผู้รับโดยเฉพาะ';

  @override
  String get restaurantOpsHandoffMemberFallback => 'สมาชิกสาขา';

  @override
  String get restaurantOpsHandoffNote => 'หมายเหตุการส่งมอบ (ไม่บังคับ)';

  @override
  String get restaurantOpsHandoffNoteHint =>
      'ข้อมูลการดำเนินงานที่ช่วยให้ทำงานกะต่อได้';

  @override
  String get restaurantOpsHandoffDeliver => 'ส่งมอบกะ';

  @override
  String get restaurantOpsHandoffConnectionRequired =>
      'ต้องเชื่อมต่อเพื่อบันทึกสถานะกะจริง';

  @override
  String restaurantOpsRecentHandoffs(int count) {
    return 'การส่งมอบล่าสุด ($count)';
  }

  @override
  String get restaurantOpsNoHandoffs => 'ยังไม่มีการบันทึกการส่งมอบ';

  @override
  String restaurantOpsHandoffReceivedBy(String name) {
    return 'รับแล้วโดย $name';
  }

  @override
  String get restaurantOpsHandoffPendingTeam => 'รอทีมรับช่วง';

  @override
  String restaurantOpsHandoffPendingRecipient(String name) {
    return 'รอ $name รับช่วง';
  }

  @override
  String get restaurantOpsHandoffAckNeedsAttention =>
      'การยืนยันที่บันทึกไว้ต้องตรวจสอบในเมนูซิงค์';

  @override
  String get restaurantOpsHandoffAckPendingSync =>
      'บันทึกการยืนยันในโทรศัพท์แล้ว กำลังรอซิงค์';

  @override
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents) {
    return 'ขณะส่งมอบ: กิจกรรมค้าง $tasks รายการ · เหตุขัดข้องเปิดอยู่ $incidents รายการ';
  }

  @override
  String restaurantOpsHandoffPausePrefix(String note) {
    return 'หยุดชั่วคราว: $note';
  }

  @override
  String restaurantOpsHandoffIncidentDescription(String description) {
    return 'เหตุขัดข้อง: $description';
  }

  @override
  String get restaurantOpsHandoffConfirmReceipt => 'ยืนยันการรับช่วง';

  @override
  String get restaurantOpsNoDescription => 'ไม่มีคำอธิบาย';

  @override
  String get restaurantOpsIncidentFollowupTitle => 'ติดตามเหตุขัดข้อง';

  @override
  String get restaurantOpsIncidentStatusLabel => 'สถานะ';

  @override
  String get restaurantOpsIncidentFollowupNote =>
      'หมายเหตุติดตามผล (ไม่บังคับ)';

  @override
  String get restaurantOpsIncidentSaveFollowup => 'บันทึกการติดตามผล';

  @override
  String get restaurantOpsBranchNotConfiguredTitle =>
      'ยังไม่ได้ตั้งค่าสาขาของคุณ';

  @override
  String get restaurantOpsBranchNotConfiguredMessage =>
      'ขอให้ผู้ดูแลสร้างสาขาและเพิ่มคุณ หากคุณมีสิทธิ์ผู้ดูแล คุณสามารถสร้างสาขาที่นี่ได้';

  @override
  String get restaurantOpsBranchName => 'ชื่อสาขา';

  @override
  String get restaurantOpsBranchTimeZone => 'เขตเวลาของสาขา';

  @override
  String get restaurantOpsBranchCreate => 'สร้างสาขา';

  @override
  String get restaurantOpsBranchCreating => 'กำลังสร้าง…';
}

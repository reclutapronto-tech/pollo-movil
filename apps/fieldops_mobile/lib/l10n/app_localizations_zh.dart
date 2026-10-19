// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'FieldOps AI';

  @override
  String get signIn => '登录';

  @override
  String get signOut => '退出登录';

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get emailRequired => '请输入邮箱';

  @override
  String get emailInvalid => '请输入有效的邮箱地址';

  @override
  String get passwordRequired => '请输入密码';

  @override
  String get signInFailed => '登录失败，请检查您的凭据和连接';

  @override
  String get assignedJobs => '已分配的工作';

  @override
  String get noJobsYet => '暂无分配的工作';

  @override
  String get pullToRefresh => '下拉刷新以查看主管分配的工作';

  @override
  String get clockIn => '打卡上班';

  @override
  String get clockOut => '打卡下班';

  @override
  String get clockedIn => '已上班';

  @override
  String get readyToClockIn => '准备打卡';

  @override
  String get startBreak => '开始休息';

  @override
  String get endBreak => '结束休息';

  @override
  String get onBreak => '休息中';

  @override
  String get requestOT => '申请加班';

  @override
  String get takePhoto => '拍照';

  @override
  String tasks(int count) {
    return '$count tasks';
  }

  @override
  String get taskChecklist => '任务清单';

  @override
  String get proofPhoto => '证明照片';

  @override
  String get beforePhoto => '施工前照片';

  @override
  String get afterPhoto => '施工后照片';

  @override
  String get capturing => '拍摄中...';

  @override
  String get uploading => '上传中...';

  @override
  String get finalizing => '处理中...';

  @override
  String get photoUploaded => '照片上传成功';

  @override
  String get retry => '重试';

  @override
  String get cancel => '取消';

  @override
  String get offline => '离线';

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
  String get submitOTRequest => '提交加班申请';

  @override
  String get overtimeAlert => '您即将进入加班时间';

  @override
  String get hoursWorked => '已工作时间';

  @override
  String get reasonForOvertime => '加班原因';

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

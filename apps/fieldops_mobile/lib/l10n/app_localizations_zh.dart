// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Pollo Móvil';

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
    return '$count 项任务';
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
      other: '$count 个事件已排队',
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
  String get mySchedule => '我的排班';

  @override
  String get upcomingShifts => '即将开始的班次';

  @override
  String get scheduleHelp => '未来两周已发布的班次。主管更新排班后，下拉即可刷新。';

  @override
  String get updated => '已更新';

  @override
  String get noScheduledShiftsYet => '暂无已排班次';

  @override
  String get scheduleWillAppear => '主管发布排班后，班次会显示在这里。';

  @override
  String get scheduleUnavailable => '排班暂不可用';

  @override
  String get restaurantClockTitle => '考勤打卡';

  @override
  String get restaurantClockGpsServiceOff => '请开启定位服务以记录考勤。';

  @override
  String get restaurantClockGpsPermissionRequired => '该门店已为考勤打卡启用定位，因此需要位置权限。';

  @override
  String get restaurantClockGpsLocationUnavailable => '无法获取位置。请检查定位服务后重试。';

  @override
  String restaurantClockQueued(String branch) {
    return '$branch 的考勤记录已保存在此手机，网络恢复后会同步。';
  }

  @override
  String restaurantClockEntrySaved(String branch) {
    return '已记录在 $branch 上班打卡。';
  }

  @override
  String restaurantClockExitSaved(String branch) {
    return '已记录在 $branch 下班打卡。';
  }

  @override
  String get restaurantClockSaving => '正在保存…';

  @override
  String get restaurantClockActive => '你当前已打上班卡。';

  @override
  String get restaurantClockInactive => '当前没有上班打卡记录。';

  @override
  String restaurantClockEntryTime(String time) {
    return '上班打卡：$time';
  }

  @override
  String get restaurantClockPendingSync => '考勤记录已保存在此手机，等待同步。';

  @override
  String get restaurantClockActiveEntries => '当前已上班人员';

  @override
  String get restaurantClockNoActiveEntries => '目前没有团队成员打上班卡。';

  @override
  String get restaurantClockUnavailableTime => '时间不可用';

  @override
  String get restaurantClockTeamMember => '团队成员';

  @override
  String restaurantClockEntryAt(String time) {
    return '上班打卡时间 $time';
  }

  @override
  String get restaurantClockActivePrivacy => '这里只显示上班打卡状态；不会在后台使用定位。';

  @override
  String get restaurantClockTodayAttendance => '今日考勤';

  @override
  String get restaurantClockNoBranchEntries => '该门店今天还没有上班打卡记录。';

  @override
  String get restaurantClockEntry => '上班';

  @override
  String restaurantClockEntryForDate(String date) {
    return '上班（$date）';
  }

  @override
  String get restaurantClockNoExit => '尚未下班打卡';

  @override
  String restaurantClockExitAt(String time) {
    return '下班 $time';
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
  String get restaurantClockAttendancePrivacy => '这里只显示当天考勤；此摘要不包含位置信息。';

  @override
  String get restaurantClockMyAttendance => '我的今日记录';

  @override
  String get restaurantClockNoMyEntriesToday => '你今天还没有上班打卡记录。';

  @override
  String get restaurantClockMyPrivacy => '此摘要仅显示你的考勤时间，不显示位置。';

  @override
  String get restaurantClockToday => '今天';

  @override
  String get restaurantClockPreviousDate => '此前日期';

  @override
  String get restaurantClockGpsRequired => '该门店只在上班或下班打卡时请求位置。应用不会在后台收集位置。';

  @override
  String get restaurantClockGpsNotRequired => '考勤打卡已启用，但不会收集位置，也不会在后台使用定位。';

  @override
  String get restaurantClockNoPayroll => '此记录用于记录运营考勤，不用于计算工资。';

  @override
  String get restaurantMoreTitle => '更多';

  @override
  String get restaurantAccount => 'Pollo Móvil 账户';

  @override
  String get restaurantAssignedBranchAccess => '安全访问已分配的门店';

  @override
  String get restaurantMoreDescription =>
      'Pollo Móvil 用于协调活动、检查、事件和交接班。应用不会在后台收集位置。';

  @override
  String get restaurantNotificationsThisDevice => '此设备上的通知';

  @override
  String get restaurantPushOperationalUpdates => '接收活动和运营变更的推送通知。';

  @override
  String get restaurantPushRequiresSetup => '完成 Firebase 和此平台的通知配置后，即可使用推送通知。';

  @override
  String get restaurantPushEnableFailed =>
      '无法启用通知。请检查此手机的通知权限和 Firebase 移动端配置。';

  @override
  String get restaurantNotificationView => '查看';

  @override
  String get restaurantSignOutPendingEvents => '等待同步的事件仍保留在此手机上。';

  @override
  String get restaurantOperationalAppLabel => 'Pollo Móvil · 运营应用';

  @override
  String get restaurantNotificationsTitle => '通知';

  @override
  String get restaurantNotificationsQueuedRead => '网络恢复后，通知收件箱会自动更新。';

  @override
  String get restaurantNotificationsMarkAllRead => '全部标为已读';

  @override
  String restaurantNotificationsLoadError(String error) {
    return '无法加载通知。$error';
  }

  @override
  String get restaurantNotificationsOfflineEmpty => '已保存的副本中没有通知。连接网络以更新收件箱。';

  @override
  String get restaurantNotificationsEmpty => '暂无通知。';

  @override
  String get restaurantNotificationsOfflineTitle => '离线保存的收件箱';

  @override
  String get restaurantNotificationsOfflineBody => '自上次更新后，状态可能已发生变化。';

  @override
  String get restaurantNotificationFallbackTitle => '通知';

  @override
  String get restaurantNotificationReadPending => '已读状态等待同步';

  @override
  String get restaurantNotificationMarkRead => '标为已读';

  @override
  String get restaurantInspectionQueued => '检查记录已保存在此手机，网络恢复后会同步。';

  @override
  String get restaurantInspectionSaved => '检查已保存。';

  @override
  String restaurantInspectionNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '检查已保存；有 $count 项需要处理。',
    );
    return '$_temp0';
  }

  @override
  String get restaurantInspectionNoActiveCriteria => '此检查清单没有启用的标准。请联系管理员进行配置。';

  @override
  String get restaurantInspectionInstruction => '记录此门店配置的每项标准的实际状态。';

  @override
  String get restaurantInspectionCriterion => '检查标准';

  @override
  String get restaurantInspectionObservedState => '观察到的状态';

  @override
  String get restaurantInspectionResultOk => '正常';

  @override
  String get restaurantInspectionResultNeedsAttention => '需要处理';

  @override
  String get restaurantInspectionResultNotApplicable => '不适用';

  @override
  String get restaurantInspectionOptionalDetail => '补充说明（可选）';

  @override
  String get restaurantInspectionOptionalGeneralNote => '备注（可选）';

  @override
  String get restaurantInspectionSaving => '正在保存…';

  @override
  String get restaurantInspectionSave => '保存检查';

  @override
  String get restaurantInspectionOfflineHelp => '离线时，检查记录会保存在此手机，网络恢复后发送。';

  @override
  String get restaurantInspectionDefaultTitle => '检查';

  @override
  String get restaurantShiftScheduleTitle => '班次排班';

  @override
  String get restaurantShiftSaved => '班次已保存。';

  @override
  String get restaurantShiftUpdated => '班次已更新。';

  @override
  String restaurantShiftSaveError(String error) {
    return '无法保存班次：$error';
  }

  @override
  String get restaurantShiftCancelTitle => '取消班次';

  @override
  String restaurantShiftCancelConfirmation(String employee) {
    return '确定取消 $employee 的班次吗？';
  }

  @override
  String get restaurantShiftCanceled => '班次已取消。';

  @override
  String restaurantShiftCancelError(String error) {
    return '无法取消班次：$error';
  }

  @override
  String get restaurantShiftLoadError => '无法加载本周排班。';

  @override
  String get restaurantShiftPreviousWeek => '上一周';

  @override
  String get restaurantShiftNextWeek => '下一周';

  @override
  String get restaurantShiftOfflineNotice => '当前离线：显示最近保存的排班。网络恢复后即可编辑班次。';

  @override
  String restaurantShiftTimezone(String timeZone) {
    return '时间采用门店当地时区：$timeZone';
  }

  @override
  String get restaurantShiftAdd => '添加班次';

  @override
  String get restaurantShiftNoShifts => '暂无已排班次。';

  @override
  String get restaurantShiftTeamMember => '团队成员';

  @override
  String get restaurantShiftPublished => '已发布';

  @override
  String get restaurantShiftDraft => '草稿';

  @override
  String restaurantShiftTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String restaurantShiftBreaks(String breaks) {
    return '休息时间：$breaks';
  }

  @override
  String get restaurantShiftEdit => '编辑';

  @override
  String get restaurantShiftCancelAction => '取消班次';

  @override
  String get restaurantShiftAddDialogTitle => '添加班次';

  @override
  String get restaurantShiftEditDialogTitle => '编辑班次';

  @override
  String get restaurantShiftEmployee => '员工';

  @override
  String get restaurantShiftDay => '日期';

  @override
  String get restaurantShiftStartChoose => '开始时间：选择';

  @override
  String get restaurantShiftEndChoose => '结束时间：选择';

  @override
  String get restaurantShiftStart => '开始';

  @override
  String get restaurantShiftEnd => '结束';

  @override
  String get restaurantShiftPublish => '发布班次';

  @override
  String get restaurantShiftDraftDescription => '关闭后，班次将保存为草稿。';

  @override
  String get restaurantShiftBreaksTitle => '休息时间';

  @override
  String get restaurantShiftAddBreak => '添加';

  @override
  String get restaurantShiftRemoveBreak => '移除休息时间';

  @override
  String get restaurantShiftSave => '保存';

  @override
  String get restaurantTeamTitle => '门店团队';

  @override
  String get restaurantTeamUpdated => '团队成员信息已更新。';

  @override
  String restaurantTeamSaveError(String error) {
    return '无法保存全部更改：$error';
  }

  @override
  String get restaurantInviteDialogTitle => '邀请员工';

  @override
  String get restaurantInviteLinkTitle => '邀请链接';

  @override
  String get restaurantInviteAction => '邀请员工';

  @override
  String get restaurantInviteEmailNotSent => '无法自动发送邮件。请复制此链接并分享给受邀者。';

  @override
  String get restaurantInviteCopied => '邀请链接已复制。';

  @override
  String get restaurantInviteCopyLink => '复制链接';

  @override
  String get restaurantClose => '关闭';

  @override
  String get restaurantInviteSent => '邀请已发送。';

  @override
  String get restaurantInviteAlreadyMember => '此人已经是该门店的成员。';

  @override
  String get restaurantInviteAccountAdded => '账户已添加到门店。';

  @override
  String restaurantInviteError(String error) {
    return '无法邀请此人：$error';
  }

  @override
  String get restaurantTeamLoadError => '无法加载门店团队。';

  @override
  String get restaurantTeamOfflineTitle => '正在显示最近保存的团队信息';

  @override
  String get restaurantTeamOfflineBody => '网络恢复前，此信息为只读。';

  @override
  String get restaurantTeamEmpty => '此门店还没有团队成员。';

  @override
  String restaurantTeamMemberCount(int count) {
    return '$count 位团队成员';
  }

  @override
  String get restaurantInviteFullName => '姓名';

  @override
  String get restaurantInviteEmail => '电子邮箱';

  @override
  String get restaurantInviteNameValidation => '请输入姓名。';

  @override
  String get restaurantInvitePermissionNote => '邀请将发送到此邮箱。新成员将获得员工权限。';

  @override
  String get restaurantInviteSubmit => '发送邀请';

  @override
  String get restaurantRoleLabel => '门店角色';

  @override
  String get restaurantRoleEmployee => '员工';

  @override
  String get restaurantRoleSupervisor => '主管';

  @override
  String get restaurantRoleAdmin => '管理员';

  @override
  String get restaurantMemberActive => '启用';

  @override
  String get restaurantMemberInactive => '停用';

  @override
  String get restaurantMemberAccess => '门店访问权限';

  @override
  String get restaurantMemberDeactivateNote => '停用后，班次和任务历史仍会保留。';

  @override
  String get restaurantMemberPositions => '已启用岗位';

  @override
  String get restaurantPositionFallback => '岗位';

  @override
  String get restaurantMemberReactivateToEdit => '重新启用门店访问权限后，才能修改已启用岗位。';

  @override
  String get restaurantMemberConfigurePositions => '请先配置岗位，再将其分配给团队。';

  @override
  String get restaurantMemberSaveChanges => '保存更改';

  @override
  String get restaurantAbsenceReviewTitle => '请假申请';

  @override
  String get restaurantAbsenceApproved => '申请已批准。';

  @override
  String get restaurantAbsenceRejected => '申请已拒绝。';

  @override
  String restaurantAbsenceReviewError(String error) {
    return '无法处理申请：$error';
  }

  @override
  String get restaurantAbsenceLoadError => '无法加载待处理的申请。';

  @override
  String get restaurantAbsenceNone => '没有待处理的申请。';

  @override
  String get restaurantAbsenceOfflineNotice => '当前离线：显示上次更新的申请。批准或拒绝申请需要网络连接。';

  @override
  String get restaurantAbsenceOfflineEmpty => '上次更新时没有待处理的申请。';

  @override
  String get restaurantAbsenceReject => '拒绝';

  @override
  String get restaurantAbsenceApprove => '批准';

  @override
  String get restaurantCalendarTitle => '活动日历';

  @override
  String get restaurantCalendarRefresh => '刷新日历';

  @override
  String get restaurantCalendarLoadError => '无法加载日历。';

  @override
  String get restaurantCalendarRetry => '重试';

  @override
  String get restaurantCalendarPreviousWeek => '上一周';

  @override
  String get restaurantCalendarNextWeek => '下一周';

  @override
  String get restaurantCalendarManagerHint => '只能安排已配置的活动。';

  @override
  String get restaurantCalendarBranchHint => '分配到您分店的活动。';

  @override
  String get restaurantCalendarOffline => '离线：显示最近保存的一周。重新连接前，排班为只读。';

  @override
  String get restaurantCalendarRetroactive => '无法从日历补排过去的活动。';

  @override
  String restaurantCalendarDayScheduled(int count) {
    return '已根据分店规则创建 $count 项新活动。现有活动不会重复创建。';
  }

  @override
  String get restaurantCalendarPastWeek => '本周已过去；未更改任何日期。';

  @override
  String restaurantCalendarWeekScheduled(int created, int days, int pastDays) {
    return '已在 $days 个日期安排 $created 项活动。过去日期保持不变；跳过 $pastDays 个过去日期。现有活动不会重复创建。';
  }

  @override
  String restaurantCalendarWeekPartial(int created, int days, String dates) {
    return '已在 $days 个日期安排 $created 项活动。以下日期安排失败：$dates。可重试，已创建的活动不会重复。';
  }

  @override
  String get restaurantCalendarPlanWeek => '安排显示的一周';

  @override
  String get restaurantCalendarPlanningWeek => '正在安排本周…';

  @override
  String restaurantCalendarWeekActivities(int count) {
    return '本周 $count 项活动';
  }

  @override
  String restaurantCalendarUnassignedCount(int count) {
    return '$count 项任务未分配';
  }

  @override
  String restaurantCalendarCompletedCount(int count) {
    return '已完成 $count 项';
  }

  @override
  String restaurantCalendarActivityCount(int count) {
    return '$count 项活动';
  }

  @override
  String get restaurantCalendarPastDate => '日期已过；无法补排活动。';

  @override
  String get restaurantCalendarScheduleFromRules => '按规则安排';

  @override
  String get restaurantCalendarScheduling => '正在安排…';

  @override
  String get restaurantCalendarAssignEligible => '分配给符合条件的员工';

  @override
  String get restaurantCalendarAssigning => '正在分配…';

  @override
  String restaurantCalendarAutoAssignResult(
    int assigned,
    String planner,
    int unassigned,
  ) {
    return '使用$planner分配了 $assigned 项活动；$unassigned 项没有符合条件的员工。';
  }

  @override
  String get restaurantCalendarLocalPlanner => '本地计划器';

  @override
  String get restaurantCalendarNoActivities => '没有安排活动。';

  @override
  String get restaurantCalendarFallbackActivity => '活动';

  @override
  String get restaurantCalendarNoAssignee => '未分配负责人';

  @override
  String get restaurantCalendarConfigurationPending => '请先配置分店岗位、区域或要求，再分配此活动。';

  @override
  String get restaurantCalendarAssignee => '负责人';

  @override
  String get restaurantCalendarFallbackAssignee => '当前负责人';

  @override
  String restaurantCalendarInactiveAssignee(String name) {
    return '$name · 已停用';
  }

  @override
  String get restaurantCalendarEmployeeFallback => '员工';

  @override
  String get restaurantCalendarZoneFallback => '部分';

  @override
  String restaurantCalendarZoneAssignee(String zone) {
    return '$zone负责人';
  }

  @override
  String get restaurantCalendarStatusPending => '待处理';

  @override
  String get restaurantCalendarStatusInProgress => '进行中';

  @override
  String get restaurantCalendarStatusPaused => '已暂停';

  @override
  String get restaurantCalendarStatusBlocked => '已阻止';

  @override
  String get restaurantCalendarStatusCompleted => '已完成';

  @override
  String get restaurantCalendarTaskAssigneeUpdated => '活动负责人已更新。';

  @override
  String get restaurantCalendarPartAssigneeUpdated => '部分负责人已更新。';

  @override
  String get restaurantStructureTitle => '区域与岗位';

  @override
  String get restaurantStructureAreas => '区域';

  @override
  String get restaurantStructurePositions => '岗位';

  @override
  String restaurantStructureAdd(String label) {
    return '添加$label';
  }

  @override
  String restaurantStructureEdit(String label) {
    return '编辑$label';
  }

  @override
  String restaurantStructureSaved(String label) {
    return '已保存$label。';
  }

  @override
  String restaurantStructureSaveError(String label, String error) {
    return '无法保存$label：$error';
  }

  @override
  String restaurantStructureReactivateTitle(String label) {
    return '重新启用$label';
  }

  @override
  String restaurantStructureDeactivateTitle(String label) {
    return '停用$label';
  }

  @override
  String get restaurantStructureReactivateDescription => '之后可以再次将其用于新活动。';

  @override
  String get restaurantStructureDeactivateDescription => '它将从新活动中隐藏，现有历史记录会保留。';

  @override
  String get restaurantStructureBack => '返回';

  @override
  String get restaurantStructureReactivateAction => '重新启用';

  @override
  String get restaurantStructureDeactivateAction => '停用';

  @override
  String get restaurantStructureEmpty => '尚未配置任何项目。';

  @override
  String get restaurantStructureStatusActive => '状态：启用';

  @override
  String get restaurantStructureStatusInactive => '状态：停用';

  @override
  String restaurantStructureAddTooltip(String label) {
    return '添加$label';
  }

  @override
  String get restaurantStructureEditName => '编辑名称';

  @override
  String get restaurantStructureOfflineTitle => '显示最近保存的配置';

  @override
  String get restaurantStructureOfflineBody => '重新连接前，区域、岗位和功能只能查看。';

  @override
  String get restaurantStructureKeepHistory => '请停用项目而非删除，以保留运营历史记录。';

  @override
  String get restaurantStructureLoadError => '无法加载分店配置。';

  @override
  String get restaurantStructureRetry => '重试';

  @override
  String get restaurantAttendanceTitle => '考勤与位置';

  @override
  String get restaurantAttendanceOptional => '每个分店可单独选择启用，默认关闭。';

  @override
  String get restaurantAttendanceEnableClock => '启用打卡';

  @override
  String get restaurantAttendanceClockDescription => '记录上下班，不计算工资。';

  @override
  String get restaurantAttendanceRequestGps => '每次打卡时请求 GPS';

  @override
  String get restaurantAttendanceGpsDescription => '仅在上下班打卡时查询位置；不会持续追踪。';

  @override
  String get restaurantAttendanceSaveFeatures => '保存功能设置';

  @override
  String get restaurantAttendanceSaved => '考勤功能已更新。';

  @override
  String restaurantAttendanceSaveError(String error) {
    return '无法保存配置：$error';
  }

  @override
  String get restaurantStructureName => '名称';

  @override
  String get restaurantStructureSave => '保存';

  @override
  String get restaurantEvidenceTitle => '活动凭证';

  @override
  String get restaurantEvidenceCameraMissing => '未找到摄像头。';

  @override
  String get restaurantEvidenceCameraOpenError => '无法打开摄像头。';

  @override
  String get restaurantEvidencePhotoSaveError => '无法保存照片，请重试。';

  @override
  String get restaurantEvidenceSaving => '正在保存…';

  @override
  String get restaurantEvidenceTakePhoto => '拍照';

  @override
  String get restaurantSyncOffline => '离线';

  @override
  String restaurantSyncOfflinePending(int count) {
    return '离线，$count 条记录待同步';
  }

  @override
  String restaurantSyncAttentionCount(int count) {
    return '$count 条记录需要处理';
  }

  @override
  String restaurantSyncPendingCount(int count) {
    return '$count 条记录待同步';
  }

  @override
  String get restaurantSyncAllDone => '全部已同步';

  @override
  String restaurantSyncTooltip(String status) {
    return '$status。点击立即同步。';
  }

  @override
  String get restaurantSyncStarted => '已开始同步待处理记录。';

  @override
  String get restaurantSyncOfflineSaved => '当前离线，记录仍保存在此手机上。';

  @override
  String get restaurantSyncFailure => '暂时无法同步，记录仍保存在此手机上。';

  @override
  String get restaurantSyncRetryQueued => '记录已重新加入同步队列。';

  @override
  String get restaurantSyncRetryFailed => '暂时无法重试，记录仍保存在此手机上。';

  @override
  String get restaurantSyncEventClock => '打卡：上班或下班';

  @override
  String get restaurantSyncEventOperations => '运营记录';

  @override
  String get restaurantSyncEventClockEvent => '上班或下班打卡';

  @override
  String get restaurantSyncEventEvidence => '照片凭证';

  @override
  String get restaurantSyncEventPending => '待处理记录';

  @override
  String restaurantSyncAttentionNotice(int count) {
    return '$count 条记录需要处理';
  }

  @override
  String get restaurantSyncAttentionHelp =>
      '记录已保存在此手机上。联网后重试。如果记录属于其他账户，请使用该账户登录。';

  @override
  String get restaurantSyncRequiresOriginalAccount => '需要原账户';

  @override
  String get restaurantSyncRetry => '重试';

  @override
  String get restaurantOpsShiftTitle => '我的班次';

  @override
  String get restaurantOpsWasteTitle => '垃圾桶检查';

  @override
  String get restaurantOpsIncidentsTitle => '事件';

  @override
  String get restaurantOpsHandoffTitle => '交接班';

  @override
  String get restaurantOpsBranchesLoadError => '无法加载您的分店。';

  @override
  String get restaurantOpsShiftLoadError => '无法加载班次。';

  @override
  String get restaurantOpsBranchFallback => '分店';

  @override
  String get restaurantOpsOfflineTitle => '显示最近保存的运营信息';

  @override
  String get restaurantOpsOfflinePendingChanges => '重新连接前，新更改会保存在此手机上。';

  @override
  String restaurantOpsOfflineSnapshotAt(String time) {
    return '快照时间：$time。重新连接前，新更改会保存在此手机上。';
  }

  @override
  String get restaurantOpsSavedOffline => '已保存在此手机上；恢复连接后会同步。';

  @override
  String get restaurantOpsSaved => '完成，已保存更改。';

  @override
  String get restaurantOpsHandoffDelivered => '已按当前班次状态保存交接信息。';

  @override
  String get restaurantOpsSwitchBranch => '切换分店';

  @override
  String get restaurantOpsRefresh => '刷新';

  @override
  String get restaurantOpsPauseTitle => '暂停活动';

  @override
  String get restaurantOpsPauseOptionalNote => '给下一班次的备注（可选）';

  @override
  String get restaurantOpsPauseContinue => '继续工作';

  @override
  String get restaurantOpsPauseAction => '暂停活动';

  @override
  String get restaurantOpsPauseHint => '供接手此活动的人员了解的运营背景';

  @override
  String get restaurantOpsNoUpcomingShifts => '未来两周没有已发布的班次。';

  @override
  String get restaurantOpsToday => '今天';

  @override
  String get restaurantOpsTomorrow => '明天';

  @override
  String get restaurantOpsCalendarDescription => '查看分店已安排的活动。';

  @override
  String get restaurantOpsCustomerService => '我正在服务客户';

  @override
  String get restaurantOpsInterruptibleWait => '可中断的任务将暂时等待。';

  @override
  String get restaurantOpsOwnActivities => '您的活动';

  @override
  String get restaurantOpsNoOwnActivities => '此班次没有分配给您的活动。';

  @override
  String get restaurantOpsBranchStructureDescription => '配置此分店的运营结构。';

  @override
  String get restaurantOpsTeamDescription => '管理分店权限、角色和岗位。';

  @override
  String get restaurantOpsShiftAdminDescription => '管理班次、休息时间和团队发布。';

  @override
  String get restaurantOpsPendingAbsences => '待处理申请';

  @override
  String get restaurantOpsAbsenceReviewDescription => '审核、批准或拒绝团队申请。';

  @override
  String get restaurantOpsTaskPendingSync => '更改已保存在此手机上，等待同步。';

  @override
  String restaurantOpsPauseReason(String note) {
    return '暂停原因：$note';
  }

  @override
  String restaurantOpsAssigneeNamed(String name) {
    return '负责人：$name';
  }

  @override
  String get restaurantOpsZoneFallback => '区域';

  @override
  String get restaurantOpsYou => '您';

  @override
  String get restaurantOpsActionClaim => '领取任务';

  @override
  String get restaurantOpsActionStart => '开始';

  @override
  String get restaurantOpsActionPause => '暂停';

  @override
  String get restaurantOpsActionComplete => '完成';

  @override
  String get restaurantOpsActionResume => '恢复';

  @override
  String get restaurantOpsAbsencePendingNote => '申请将在主管审核前保持待处理状态。';

  @override
  String get restaurantOpsDateFrom => '开始日期';

  @override
  String get restaurantOpsDateUntil => '结束日期';

  @override
  String get restaurantOpsOptionalNote => '备注（可选）';

  @override
  String get restaurantOpsAbsenceSend => '提交申请';

  @override
  String get restaurantOpsAbsenceSending => '正在提交…';

  @override
  String get restaurantOpsAbsenceOfflineNote => '离线时，申请会先保存在本机，稍后同步。';

  @override
  String get restaurantOpsSavedAbsencesTitle => '保存在此手机上的申请';

  @override
  String get restaurantOpsSyncReviewNeeded => '检查同步状态';

  @override
  String get restaurantOpsPendingSend => '等待发送';

  @override
  String get restaurantOpsUnassignedSection => '未分配负责人';

  @override
  String get restaurantOpsAbsenceStatusDenied => '未获批准';

  @override
  String get restaurantOpsWasteIntro => '一次检查即可记录每个垃圾桶的申报状态。';

  @override
  String get restaurantOpsWasteNeedsAttention => '本地检查需要在同步中处理。解决前请勿重复提交。';

  @override
  String get restaurantOpsWastePendingSync => '检查已保存在此手机上，联网后会同步。';

  @override
  String get restaurantOpsWasteStatusTitle => '垃圾桶状态';

  @override
  String get restaurantOpsBinFallback => '垃圾桶';

  @override
  String restaurantOpsIntervalConfigured(String minutes) {
    return '设置的间隔：$minutes 分钟';
  }

  @override
  String get restaurantOpsInspectionDue => '已达到设置的检查间隔。';

  @override
  String get restaurantOpsWasteNeedsPolicy => '将此垃圾桶标记为已满前，请先配置后续任务。';

  @override
  String get restaurantOpsDeclaredState => '申报状态';

  @override
  String get restaurantOpsSelectState => '选择状态';

  @override
  String get restaurantOpsBinLow => '空或较少';

  @override
  String get restaurantOpsBinHalf => '半满';

  @override
  String get restaurantOpsBinFull => '已满';

  @override
  String get restaurantOpsCannotSaveFullBin => '无法保存检查：请配置满桶任务的名称、时长、难度和优先级。';

  @override
  String get restaurantOpsWastePendingAction => '检查等待同步';

  @override
  String get restaurantOpsSaving => '正在保存…';

  @override
  String get restaurantOpsWasteSubmit => '提交检查';

  @override
  String get restaurantOpsAreaInspectionsTitle => '其他区域检查';

  @override
  String get restaurantOpsNoInspectionTemplates => '此分店尚未配置检查清单。';

  @override
  String get restaurantOpsInspectionFallback => '检查';

  @override
  String restaurantOpsInspectionCriteriaCount(int count) {
    return '已配置 $count 项标准';
  }

  @override
  String restaurantOpsInspectionInterval(String minutes) {
    return '每 $minutes 分钟';
  }

  @override
  String get restaurantOpsInspectionNeedsAttention => '本地检查需要在同步中处理。';

  @override
  String restaurantOpsInspectionPendingSync(int count) {
    return '检查已保存在此手机上；$count 项标准已标记待复核。';
  }

  @override
  String get restaurantOpsDoInspection => '开始检查';

  @override
  String get restaurantOpsInspectionPendingAction => '检查等待同步';

  @override
  String restaurantOpsRecentInspections(int count) {
    return '最近记录（$count）';
  }

  @override
  String get restaurantOpsTeamFallback => '团队';

  @override
  String restaurantOpsNeedsAttentionCount(int count) {
    return '$count 项需要处理';
  }

  @override
  String get restaurantOpsNoAlerts => '无提醒';

  @override
  String get restaurantOpsCriterionFallback => '标准';

  @override
  String restaurantOpsCriterionNote(String label, String note) {
    return '$label：$note';
  }

  @override
  String get restaurantOpsIncidentReport => '报告问题';

  @override
  String get restaurantOpsIncidentDescription => '简要说明';

  @override
  String get restaurantOpsIncidentAreaOptional => '区域（可选）';

  @override
  String get restaurantOpsIncidentNoArea => '无区域';

  @override
  String get restaurantOpsUrgency => '紧急程度';

  @override
  String get restaurantOpsUrgencyLow => '低';

  @override
  String get restaurantOpsUrgencyNormal => '普通';

  @override
  String get restaurantOpsUrgencyHigh => '高';

  @override
  String get restaurantOpsUrgencyUrgent => '紧急';

  @override
  String get restaurantOpsIncidentBlocksWork => '阻碍工作';

  @override
  String get restaurantOpsIncidentSend => '提交事件';

  @override
  String get restaurantOpsOpenIncidents => '未解决事件';

  @override
  String get restaurantOpsNoOpenIncidents => '没有未解决事件。';

  @override
  String get restaurantOpsSavedIncidentsTitle => '已保存在此手机上';

  @override
  String get restaurantOpsIncidentFallback => '事件';

  @override
  String get restaurantOpsIncidentNeedsAttention => '检查同步状态';

  @override
  String get restaurantOpsIncidentPendingSync => '等待同步';

  @override
  String get restaurantOpsIncidentBlockingUnconfirmed => '已报告为阻碍工作，但服务器尚未确认。';

  @override
  String get restaurantOpsIncidentStatusOpen => '未解决';

  @override
  String get restaurantOpsIncidentStatusInProgress => '处理中';

  @override
  String get restaurantOpsIncidentStatusResolved => '已解决';

  @override
  String get restaurantOpsHandoffSummary => '自动生成的班次摘要，无需重复填写报告。';

  @override
  String restaurantOpsHandoffCompletedCount(int count) {
    return '已完成（$count）';
  }

  @override
  String get restaurantOpsHandoffNoCompleted => '今天尚无已完成的活动。';

  @override
  String restaurantOpsHandoffOutstandingCount(int count) {
    return '待处理或已暂停（$count）';
  }

  @override
  String get restaurantOpsHandoffNoOutstanding => '没有待处理活动。';

  @override
  String restaurantOpsHandoffIncidentCount(int count) {
    return '未解决事件（$count）';
  }

  @override
  String get restaurantOpsHandoffDeliveryTitle => '班次交接与接收';

  @override
  String get restaurantOpsHandoffSnapshotNote => '交接时会保存待处理活动和未解决事件的快照。';

  @override
  String get restaurantOpsHandoffRecipient => '接收交接的人';

  @override
  String get restaurantOpsHandoffNoRecipient => '不指定接收人';

  @override
  String get restaurantOpsHandoffMemberFallback => '分店成员';

  @override
  String get restaurantOpsHandoffNote => '交接备注（可选）';

  @override
  String get restaurantOpsHandoffNoteHint => '帮助继续班次工作的运营信息';

  @override
  String get restaurantOpsHandoffDeliver => '交接班次';

  @override
  String get restaurantOpsHandoffConnectionRequired => '需要联网才能保存当前班次的实际快照。';

  @override
  String restaurantOpsRecentHandoffs(int count) {
    return '最近交接（$count）';
  }

  @override
  String get restaurantOpsNoHandoffs => '尚未记录交接。';

  @override
  String restaurantOpsHandoffReceivedBy(String name) {
    return '由$name接收';
  }

  @override
  String get restaurantOpsHandoffPendingTeam => '等待团队接收';

  @override
  String restaurantOpsHandoffPendingRecipient(String name) {
    return '等待$name接收';
  }

  @override
  String get restaurantOpsHandoffAckNeedsAttention => '已保存的确认需要在同步中处理。';

  @override
  String get restaurantOpsHandoffAckPendingSync => '确认已保存在此手机上，等待同步。';

  @override
  String restaurantOpsHandoffSnapshotSummary(int tasks, int incidents) {
    return '交接时：$tasks 项待处理活动 · $incidents 项未解决事件';
  }

  @override
  String restaurantOpsHandoffPausePrefix(String note) {
    return '暂停：$note';
  }

  @override
  String restaurantOpsHandoffIncidentDescription(String description) {
    return '事件：$description';
  }

  @override
  String get restaurantOpsHandoffConfirmReceipt => '确认接收';

  @override
  String get restaurantOpsNoDescription => '无说明';

  @override
  String get restaurantOpsIncidentFollowupTitle => '事件跟进';

  @override
  String get restaurantOpsIncidentStatusLabel => '状态';

  @override
  String get restaurantOpsIncidentFollowupNote => '跟进备注（可选）';

  @override
  String get restaurantOpsIncidentSaveFollowup => '保存跟进';

  @override
  String get restaurantOpsBranchNotConfiguredTitle => '您的分店尚未配置';

  @override
  String get restaurantOpsBranchNotConfiguredMessage =>
      '请管理员创建分店并将您添加进去。如果您有管理员权限，也可以在此创建分店。';

  @override
  String get restaurantOpsBranchName => '分店名称';

  @override
  String get restaurantOpsBranchTimeZone => '分店时区';

  @override
  String get restaurantOpsBranchCreate => '创建分店';

  @override
  String get restaurantOpsBranchCreating => '正在创建…';
}

import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantShiftCoverageScreen extends ConsumerStatefulWidget {
  const RestaurantShiftCoverageScreen({
    super.key,
    required this.branchId,
  });

  final String branchId;

  @override
  ConsumerState<RestaurantShiftCoverageScreen> createState() =>
      _RestaurantShiftCoverageScreenState();
}

class _RestaurantShiftCoverageScreenState
    extends ConsumerState<RestaurantShiftCoverageScreen> {
  final _noteController = TextEditingController();
  final Map<String, String> _replacementByRequest = {};
  String? _selectedShiftId;
  String? _busyId;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest(String shiftId) async {
    if (_busyId != null) return;
    setState(() => _busyId = 'new');
    try {
      final result = await ref.read(restaurantOpsRepositoryProvider).requestShiftCover(
            branchId: widget.branchId,
            shiftId: shiftId,
            note: _noteController.text,
          );
      if (!mounted) return;
      _noteController.clear();
      ref.invalidate(restaurantShiftCoverRequestsProvider(widget.branchId));
      ref.invalidate(restaurantNotificationsProvider(widget.branchId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['queued'] == true
            ? _copy(context, 'Solicitud guardada para sincronizar.', 'Request saved for sync.', 'Demande enregistrée pour synchronisation.', 'บันทึกคำขอเพื่อซิงก์แล้ว', '已保存请求，等待同步')
            : _copy(context, 'Solicitud enviada al gerente.', 'Request sent to the manager.', 'Demande envoyée au responsable.', 'ส่งคำขอให้ผู้จัดการแล้ว', '已将请求发送给经理'))),
      );
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    if (_busyId != null) return;
    setState(() => _busyId = requestId);
    try {
      final result = await ref.read(restaurantOpsRepositoryProvider).cancelShiftCoverRequest(
            branchId: widget.branchId,
            requestId: requestId,
          );
      ref.invalidate(restaurantShiftCoverRequestsProvider(widget.branchId));
      ref.invalidate(restaurantNotificationsProvider(widget.branchId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['queued'] == true
              ? _copy(context, 'Cancelación guardada para sincronizar.', 'Cancellation saved for sync.', 'Annulation enregistrée pour synchronisation.', 'บันทึกการยกเลิกเพื่อซิงก์แล้ว', '已保存取消操作，等待同步')
              : _copy(context, 'Solicitud cancelada.', 'Request cancelled.', 'Demande annulée.', 'ยกเลิกคำขอแล้ว', '请求已取消')),
        ));
      }
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reviewRequest(
    String requestId,
    String decision, {
    String? replacementEmployeeId,
  }) async {
    if (_busyId != null) return;
    if (decision == 'approved' && replacementEmployeeId == null) {
      _showError(_copy(context, 'Selecciona a quien cubrirá el turno.', 'Choose who will cover the shift.', 'Choisissez la personne qui couvrira le service.', 'เลือกผู้ที่จะมาทำงานแทน', '请选择代班人员'));
      return;
    }
    setState(() => _busyId = requestId);
    try {
      await ref.read(restaurantOpsRepositoryProvider).reviewShiftCoverRequest(
            branchId: widget.branchId,
            requestId: requestId,
            decision: decision,
            replacementEmployeeId: replacementEmployeeId,
          );
      ref.invalidate(restaurantShiftCoverRequestsProvider(widget.branchId));
      ref.invalidate(restaurantNotificationsProvider(widget.branchId));
      ref.invalidate(restaurantDashboardProvider(widget.branchId));
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      _,
      next,
    ) {
      if (next.hasValue) {
        ref.invalidate(restaurantShiftCoverRequestsProvider(widget.branchId));
      }
    });
    ref.listen(restaurantOutboxEventsProvider(widget.branchId), (_, next) {
      if (next.hasValue) {
        ref.invalidate(restaurantShiftCoverRequestsProvider(widget.branchId));
      }
    });
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final requestsState = ref.watch(
      restaurantShiftCoverRequestsProvider(widget.branchId),
    );
    final events = ref
        .watch(restaurantOutboxEventsProvider(widget.branchId))
        .maybeWhen(data: (rows) => rows, orElse: () => const <PendingEvent>[]);

    return Scaffold(
      appBar: AppBar(title: Text(_copy(context, 'Cobertura de turnos', 'Shift coverage', 'Remplacement de service', 'การหาคนแทนกะ', '班次代班'))),
      body: requestsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _message(
          context,
          _copy(context, 'No se pudieron cargar las solicitudes.', 'Could not load requests.', 'Impossible de charger les demandes.', 'โหลดคำขอไม่สำเร็จ', '无法加载请求'),
          onRetry: () => ref.invalidate(
            restaurantShiftCoverRequestsProvider(widget.branchId),
          ),
        ),
        data: (data) {
          final offlineSnapshot = data['_offline_snapshot'] == true;
          final availableShifts = _maps(data['available_shifts']);
          final candidates = _maps(data['replacement_candidates']);
          final serverRequests = _maps(data['requests']);
          final localRequests = currentUserId == null
              ? const <OpsJson>[]
              : pendingRestaurantShiftCoverRequests(
                  events: events,
                  branchId: widget.branchId,
                  actorId: currentUserId,
                );
          final requests = <OpsJson>[];
          for (final local in localRequests) {
            OpsJson? matchingServer;
            for (final request in serverRequests) {
              if (local['id'] == request['id'] ||
                  (local['client_event_id'] != null &&
                      local['client_event_id'] == request['client_event_id'])) {
                matchingServer = request;
                break;
              }
            }
            requests.add({...?matchingServer, ...local});
          }
          requests.addAll(serverRequests.where((request) => !localRequests.any(
                (local) => local['id'] == request['id'] ||
                    (local['client_event_id'] != null &&
                        local['client_event_id'] == request['client_event_id']),
              )));
          final canManage = data['can_manage'] == true;
          final selectedShiftId = availableShifts.any(
            (shift) => shift['id'] == _selectedShiftId,
          )
              ? _selectedShiftId
              : (availableShifts.isEmpty ? null : availableShifts.first['id'] as String?);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(
              restaurantShiftCoverRequestsProvider(widget.branchId),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (offlineSnapshot)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_rounded),
                      title: Text(_copy(context, 'Última información guardada', 'Showing saved information', 'Dernières informations enregistrées', 'แสดงข้อมูลที่บันทึกไว้', '正在显示已保存的信息')),
                      subtitle: Text(_copy(context, 'Las aprobaciones requieren conexión. Las solicitudes nuevas se pueden guardar para sincronizar.', 'Approvals require a connection. New requests can be queued for sync.', 'Les validations nécessitent une connexion. Les nouvelles demandes peuvent être mises en attente.', 'การอนุมัติต้องเชื่อมต่ออินเทอร์เน็ต คำขอใหม่จะถูกจัดคิวเพื่อซิงก์', '审批需要联网。新请求可排队等待同步。')),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_copy(context, 'Solicitar cobertura', 'Request coverage', 'Demander un remplacement', 'ขอคนมาทำงานแทน', '申请代班'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(_copy(context, 'Tu turno no cambia hasta que un gerente apruebe la solicitud y asigne a otra persona.', 'Your shift stays unchanged until a manager approves and assigns another employee.', 'Votre service reste inchangé jusqu’à l’approbation et à l’affectation d’un remplaçant.', 'กะของคุณจะไม่เปลี่ยนจนกว่าผู้จัดการจะอนุมัติและมอบหมายคนแทน', '经理批准并指派他人之前，你的班次不会改变。')),
                        const SizedBox(height: 12),
                        if (availableShifts.isEmpty)
                          Text(_copy(context, 'No tienes turnos publicados futuros disponibles.', 'You have no upcoming published shifts available.', 'Aucun service publié à venir n’est disponible.', 'ไม่มีตารางกะที่ประกาศแล้วในอนาคต', '没有可申请代班的已发布未来班次。'))
                        else ...[
                          DropdownButtonFormField<String>(
                            value: selectedShiftId,
                            decoration: InputDecoration(labelText: _copy(context, 'Turno publicado', 'Published shift', 'Service publié', 'กะที่ประกาศแล้ว', '已发布班次')),
                            items: availableShifts.map((shift) => DropdownMenuItem(
                              value: shift['id'] as String,
                              child: Text(_formatShift(context, shift)),
                            )).toList(growable: false),
                            onChanged: _busyId == null
                                ? (value) => setState(() => _selectedShiftId = value)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _noteController,
                            maxLength: 1000,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: _copy(context, 'Nota opcional', 'Optional note', 'Note facultative', 'หมายเหตุเพิ่มเติม', '备注（可选）'),
                              alignLabelWithHint: true,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _busyId != null || selectedShiftId == null
                                  ? null
                                  : () => _submitRequest(selectedShiftId),
                              icon: _busyId == 'new'
                                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.send_rounded),
                              label: Text(_copy(context, 'Enviar solicitud', 'Send request', 'Envoyer la demande', 'ส่งคำขอ', '发送请求')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  canManage
                      ? _copy(context, 'Solicitudes de la sucursal', 'Branch requests', 'Demandes de la succursale', 'คำขอของสาขา', '门店请求')
                      : _copy(context, 'Mis solicitudes', 'My requests', 'Mes demandes', 'คำขอของฉัน', '我的请求'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (requests.isEmpty)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_copy(context, 'No hay solicitudes de cobertura.', 'There are no coverage requests.', 'Aucune demande de remplacement.', 'ไม่มีคำขอหาคนแทน', '暂无代班请求。')),
                  ))
                else
                  ...requests.map((request) => _requestCard(
                        context: context,
                        request: request,
                        candidates: candidates,
                        canManage: canManage && !offlineSnapshot,
                        currentUserId: currentUserId,
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _requestCard({
    required BuildContext context,
    required OpsJson request,
    required List<OpsJson> candidates,
    required bool canManage,
    required String? currentUserId,
  }) {
    final requestId = request['id']?.toString() ?? '';
    final localOutbox = request['_local_outbox'] == true;
    final status = request['status']?.toString() ?? 'pending';
    final shift = request['shift'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(request['shift'] as Map)
        : <String, dynamic>{};
    final selectedReplacement = _replacementByRequest[requestId];
    final canCancel = request['requester_id'] == currentUserId &&
        (status == 'pending' || (localOutbox && status == 'pending_sync'));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request['requester_name'] ?? _copy(context, 'Integrante', 'Team member', 'Membre de l’équipe', 'สมาชิกทีม', '团队成员')} · ${shift.isEmpty ? _copy(context, 'Turno actualizado', 'Shift updated', 'Service mis à jour', 'อัปเดตกะแล้ว', '班次已更新') : _formatShift(context, shift)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (request['note'] is String && (request['note'] as String).isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(request['note'] as String),
            ],
            const SizedBox(height: 6),
            Text(_statusText(context, status, request['needs_attention'] == true)),
            if (request['replacement_employee_name'] is String) ...[
              const SizedBox(height: 5),
              Text('${_copy(context, 'Cubre:', 'Covering:', 'Remplacement :', 'ผู้แทน:', '代班人：')} ${request['replacement_employee_name']}'),
            ],
            if (request['decision_note'] is String && (request['decision_note'] as String).isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('${_copy(context, 'Nota:', 'Note:', 'Note :', 'หมายเหตุ:', '备注：')} ${request['decision_note']}'),
            ],
            if (canManage && status == 'pending' && !localOutbox) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedReplacement,
                decoration: InputDecoration(labelText: _copy(context, 'Persona que cubrirá', 'Covering employee', 'Personne remplaçante', 'ผู้มาทำงานแทน', '代班员工')),
                items: candidates.map((candidate) => DropdownMenuItem(
                  value: candidate['id'] as String,
                  child: Text(candidate['full_name'] as String? ?? candidate['id'] as String),
                )).toList(growable: false),
                onChanged: _busyId == null
                    ? (value) => setState(() {
                          if (value == null) {
                            _replacementByRequest.remove(requestId);
                          } else {
                            _replacementByRequest[requestId] = value;
                          }
                        })
                    : null,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busyId != null || selectedReplacement == null
                        ? null
                        : () => _reviewRequest(requestId, 'approved', replacementEmployeeId: selectedReplacement),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_copy(context, 'Aprobar y asignar', 'Approve and assign', 'Approuver et affecter', 'อนุมัติและมอบหมาย', '批准并分配')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busyId == null
                        ? () => _reviewRequest(requestId, 'denied')
                        : null,
                    icon: const Icon(Icons.close_rounded),
                    label: Text(_copy(context, 'Rechazar', 'Decline', 'Refuser', 'ปฏิเสธ', '拒绝')),
                  ),
                ],
              ),
            ] else if (canCancel) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busyId == null ? () => _cancelRequest(requestId) : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(_copy(context, 'Cancelar solicitud', 'Cancel request', 'Annuler la demande', 'ยกเลิกคำขอ', '取消请求')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<OpsJson> _maps(Object? value) => (value as List<dynamic>? ?? const [])
    .whereType<Map<String, dynamic>>()
    .toList(growable: false);

String _formatShift(BuildContext context, Map<String, dynamic> shift) {
  final rawDate = shift['shift_date'] as String? ?? '';
  final date = DateTime.tryParse(rawDate);
  final dateLabel = date == null
      ? rawDate
      : MaterialLocalizations.of(context).formatMediumDate(date);
  final start = shift['start_time']?.toString() ?? '--:--';
  final end = shift['end_time']?.toString() ?? '--:--';
  return '$dateLabel · ${start.length >= 5 ? start.substring(0, 5) : start}–${end.length >= 5 ? end.substring(0, 5) : end}';
}

String _statusText(BuildContext context, String status, bool needsAttention) {
  final text = switch (status) {
    'approved' => _copy(context, 'Aprobada', 'Approved', 'Approuvée', 'อนุมัติแล้ว', '已批准'),
    'denied' => _copy(context, 'No aprobada', 'Declined', 'Refusée', 'ไม่อนุมัติ', '未批准'),
    'cancelled' => _copy(context, 'Cancelada', 'Cancelled', 'Annulée', 'ยกเลิกแล้ว', '已取消'),
    'pending_sync' => _copy(context, 'Pendiente de sincronizar', 'Waiting to sync', 'En attente de synchronisation', 'รอซิงก์', '等待同步'),
    'cancel_pending_sync' => _copy(context, 'Cancelación pendiente de sincronizar', 'Cancellation waiting to sync', 'Annulation en attente de synchronisation', 'รอซิงก์การยกเลิก', '取消操作等待同步'),
    'sync_attention' => _copy(context, 'Requiere atención: no se pudo sincronizar', 'Needs attention: sync failed', 'Attention requise : échec de synchronisation', 'ต้องตรวจสอบ: ซิงก์ไม่สำเร็จ', '需要处理：同步失败'),
    _ => _copy(context, 'Pendiente', 'Pending', 'En attente', 'รอดำเนินการ', '待处理'),
  };
  return '${_copy(context, 'Estado:', 'Status:', 'Statut :', 'สถานะ:', '状态：')} $text${needsAttention ? ' · !' : ''}';
}

Widget _message(BuildContext context, String message, {required VoidCallback onRetry}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_copy(context, 'Reintentar', 'Retry', 'Réessayer', 'ลองอีกครั้ง', '重试')),
            ),
          ],
        ),
      ),
    );

String _language(BuildContext context) => Localizations.localeOf(context).languageCode;

String _copy(BuildContext context, String es, String en, String fr, String th, String zh) =>
    switch (_language(context)) {
      'en' => en,
      'fr' => fr,
      'th' => th,
      'zh' => zh,
      _ => es,
    };

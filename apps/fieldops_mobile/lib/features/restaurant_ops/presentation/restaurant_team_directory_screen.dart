import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class RestaurantTeamDirectoryScreen extends ConsumerStatefulWidget {
  const RestaurantTeamDirectoryScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<RestaurantTeamDirectoryScreen> createState() =>
      _RestaurantTeamDirectoryScreenState();
}

class _RestaurantTeamDirectoryScreenState
    extends ConsumerState<RestaurantTeamDirectoryScreen> {
  late Future<OpsJson> _directory;
  String? _busyId;
  bool _offlineSnapshot = false;
  bool _directoryLoaded = false;

  @override
  void initState() {
    super.initState();
    _directory = _fetch();
  }

  Future<OpsJson> _fetch() async {
    final data = await ref
        .read(restaurantOpsRepositoryProvider)
        .fetchTeamDirectory(widget.branchId);
    final offline = data['_offline_snapshot'] == true;
    if (mounted && (_offlineSnapshot != offline || !_directoryLoaded)) {
      setState(() {
        _offlineSnapshot = offline;
        _directoryLoaded = true;
      });
    }
    return data;
  }

  Future<void> _refresh() async {
    final request = _fetch();
    setState(() => _directory = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the request failure and offers a retry.
    }
  }

  Future<void> _saveMember(
    Map<String, dynamic> original,
    String role,
    bool active,
    Set<String> positionIds,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final userId = original['user_id'] as String;
    if (_busyId != null) return;
    setState(() => _busyId = userId);
    try {
      final repository = ref.read(restaurantOpsRepositoryProvider);
      final wasActive = original['is_active'] == true;
      if (active && !wasActive) {
        await repository.setMemberActive(
          branchId: widget.branchId,
          userId: userId,
          isActive: true,
        );
      }
      if (role != original['access_role']) {
        await repository.saveMemberRole(
          branchId: widget.branchId,
          userId: userId,
          accessRole: role,
        );
      }
      final originalPositions =
          (original['position_ids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
      if (positionIds.length != originalPositions.length ||
          !positionIds.containsAll(originalPositions)) {
        await repository.saveMemberPositions(
          branchId: widget.branchId,
          userId: userId,
          positionIds: positionIds.toList(growable: false),
        );
      }
      if (!active && wasActive) {
        await repository.setMemberActive(
          branchId: widget.branchId,
          userId: userId,
          isActive: false,
        );
      }
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _directory = _fetch();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.restaurantTeamUpdated)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _directory = _fetch();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantTeamSaveError(error.toString()))),
      );
    }
  }

  Future<void> _inviteMember() async {
    final l10n = AppLocalizations.of(context)!;
    final draft = await showDialog<_InviteDraft>(
      context: context,
      builder: (_) => const _InviteMemberDialog(),
    );
    if (draft == null || !mounted || _busyId != null) return;
    setState(() => _busyId = 'invite');
    try {
      final result = await ref
          .read(restaurantOpsRepositoryProvider)
          .inviteMember(
            branchId: widget.branchId,
            fullName: draft.fullName,
            email: draft.email,
          );
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _directory = _fetch();
      });
      final inviteLink = result['invite_link'] as String?;
      if (inviteLink != null && inviteLink.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.restaurantInviteLinkTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.restaurantInviteEmailNotSent),
                const SizedBox(height: 12),
                SelectableText(inviteLink),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inviteLink));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(l10n.restaurantInviteCopied)),
                    );
                  }
                },
                child: Text(l10n.restaurantInviteCopyLink),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.restaurantClose),
              ),
            ],
          ),
        );
      } else {
        final message = result['already_member'] == true
            ? l10n.restaurantInviteAlreadyMember
            : result['email_sent'] == true
            ? l10n.restaurantInviteSent
            : l10n.restaurantInviteAccountAdded;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.restaurantInviteError(error.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      _,
      next,
    ) {
      if (next.hasValue && _busyId == null) _refresh();
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.restaurantTeamTitle),
        actions: [
          IconButton(
            tooltip: l10n.restaurantInviteAction,
            onPressed: _busyId == null && _directoryLoaded && !_offlineSnapshot
                ? _inviteMember
                : null,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: FutureBuilder<OpsJson>(
        future: _directory,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.restaurantTeamLoadError),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _directory = _fetch()),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final offlineSnapshot = data['_offline_snapshot'] == true;
          final members = (data['members'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final positions = (data['positions'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (offlineSnapshot)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_rounded),
                      title: Text(l10n.restaurantTeamOfflineTitle),
                      subtitle: Text(l10n.restaurantTeamOfflineBody),
                    ),
                  ),
                if (members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(l10n.restaurantTeamEmpty)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    l10n.restaurantTeamMemberCount(members.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ...members.map(
                  (member) => _TeamMemberEditor(
                    key: ValueKey(member['user_id']),
                    member: member,
                    positions: positions,
                    busy: _busyId != null || offlineSnapshot,
                    saving: _busyId == member['user_id'],
                    onSave: (role, active, positionIds) =>
                        _saveMember(member, role, active, positionIds),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InviteDraft {
  const _InviteDraft(this.fullName, this.email);

  final String fullName;
  final String email;
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog();

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _InviteDraft(
        _nameController.text.trim(),
        _emailController.text.trim().toLowerCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.restaurantInviteDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.restaurantInviteFullName,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? l10n.restaurantInviteNameValidation
                  : null,
            ),
            TextFormField(
              controller: _emailController,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.restaurantInviteEmail,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                    ? null
                    : l10n.emailInvalid;
              },
            ),
            const SizedBox(height: 4),
            Text(l10n.restaurantInvitePermissionNote),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.restaurantInviteSubmit),
        ),
      ],
    );
  }
}

class _TeamMemberEditor extends StatefulWidget {
  const _TeamMemberEditor({
    super.key,
    required this.member,
    required this.positions,
    required this.busy,
    required this.saving,
    required this.onSave,
  });

  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> positions;
  final bool busy;
  final bool saving;
  final void Function(String role, bool active, Set<String> positionIds) onSave;

  @override
  State<_TeamMemberEditor> createState() => _TeamMemberEditorState();
}

class _TeamMemberEditorState extends State<_TeamMemberEditor> {
  late String _role;
  late bool _active;
  late Set<String> _positionIds;

  @override
  void initState() {
    super.initState();
    _loadMember();
  }

  @override
  void didUpdateWidget(covariant _TeamMemberEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member != widget.member) _loadMember();
  }

  void _loadMember() {
    _role = widget.member['access_role'] as String? ?? 'employee';
    _active = widget.member['is_active'] == true;
    _positionIds = (widget.member['position_ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        widget.member['full_name'] as String? ?? l10n.restaurantShiftTeamMember;
    final roleLabel = switch (_role) {
      'admin' => l10n.restaurantRoleAdmin,
      'supervisor' => l10n.restaurantRoleSupervisor,
      _ => l10n.restaurantRoleEmployee,
    };
    final wasActive = widget.member['is_active'] == true;
    final originalRole = widget.member['access_role'] as String? ?? 'employee';
    final originalPositions =
        (widget.member['position_ids'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet();
    final dirty =
        _role != originalRole ||
        _active != wasActive ||
        _positionIds.length != originalPositions.length ||
        !_positionIds.containsAll(originalPositions);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase()),
        ),
        title: Text(name),
        subtitle: Text(
          '$roleLabel · ${wasActive ? l10n.restaurantMemberActive : l10n.restaurantMemberInactive}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          DropdownButtonFormField<String>(
            value: _role,
            decoration: InputDecoration(labelText: l10n.restaurantRoleLabel),
            items: [
              DropdownMenuItem(
                value: 'employee',
                child: Text(l10n.restaurantRoleEmployee),
              ),
              DropdownMenuItem(
                value: 'supervisor',
                child: Text(l10n.restaurantRoleSupervisor),
              ),
              DropdownMenuItem(
                value: 'admin',
                child: Text(l10n.restaurantRoleAdmin),
              ),
            ],
            onChanged: widget.busy
                ? null
                : (value) {
                    if (value != null) setState(() => _role = value);
                  },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.restaurantMemberAccess),
            subtitle: Text(l10n.restaurantMemberDeactivateNote),
            value: _active,
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _active = value),
          ),
          if (widget.positions.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.restaurantMemberPositions,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.positions
                  .map((position) {
                    final id = position['id'] as String;
                    return FilterChip(
                      label: Text(
                        position['name'] as String? ??
                            l10n.restaurantPositionFallback,
                      ),
                      selected: _positionIds.contains(id),
                      onSelected: widget.busy || !_active
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _positionIds.add(id);
                              } else {
                                _positionIds.remove(id);
                              }
                            }),
                    );
                  })
                  .toList(growable: false),
            ),
            if (!_active)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.restaurantMemberReactivateToEdit),
                ),
              ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.restaurantMemberConfigurePositions),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: !dirty || widget.busy
                  ? null
                  : () => widget.onSave(_role, _active, _positionIds),
              icon: widget.saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.restaurantMemberSaveChanges),
            ),
          ),
        ],
      ),
    );
  }
}

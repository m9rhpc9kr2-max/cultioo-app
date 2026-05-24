import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';
import 'chat_modal.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

class GroupsModal extends StatefulWidget {
  final bool isDark;
  final String? currentUsername;
  final VoidCallback? onGroupsChanged;

  const GroupsModal({
    super.key,
    required this.isDark,
    this.currentUsername,
    this.onGroupsChanged,
  });

  @override
  State<GroupsModal> createState() => _GroupsModalState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _GroupsModalState extends State<GroupsModal> {
  // ── STATIC cache — survives modal close/reopen ────────────────────────────
  // All mutations go through _setGroup() / _clearGroup() which keep both
  // the static cache and the instance state in sync.
  static Map<String, dynamic>? _sGroup;
  static List<Map<String, dynamic>> _sApprovals = [];
  static bool _sBgOp = false;              // background POST/DELETE in flight
  static bool _sLoaded = false;            // loaded at least once
  static DateTime? _sLastMutation;         // timestamp of last create/delete
  static const Duration _kGrace = Duration(seconds: 120); // 2-min safety window

  // True while we must not let _load() override optimistic state
  static bool get _inGracePeriod =>
      _sBgOp ||
      (_sLastMutation != null &&
          DateTime.now().difference(_sLastMutation!) < _kGrace);

  // ── instance state (mirrors static) ──────────────────────────────────────
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _approvals = [];
  bool _loading = true;
  String? _error;

  // ── helpers that keep static + instance in sync ───────────────────────────
  void _setGroup(Map<String, dynamic>? g, List<Map<String, dynamic>> a) {
    _sGroup = g;
    _sApprovals = a;
    if (mounted) setState(() { _group = g; _approvals = a; });
  }

  // ── form ──────────────────────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool _creating = false;
  bool _joining  = false;

  @override
  void initState() {
    super.initState();
    // Always show cached state immediately — no blank screen on reopen.
    _group     = _sGroup;
    _approvals = _sApprovals;
    if (_inGracePeriod) {
      // A mutation just happened (or bg op is running).
      // Trust the cache completely — DO NOT touch the network.
      _loading = false;
    } else if (_sLoaded) {
      // We have cached data — show it immediately, then silently refresh.
      _loading = false;
      _load(); // silent background refresh, no spinner
    } else {
      // Very first open — fetch with spinner.
      _loading = true;
      _load();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── networking ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    // Never override optimistic/cached state during grace period.
    if (_inGracePeriod) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    // Show spinner only on first-ever load; otherwise silent background refresh.
    if (!_sLoaded) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.getGroups(),
        ApiService.getPendingApprovals(),
      ]);
      if (!mounted) return;
      // A mutation happened while we were waiting — discard stale result.
      if (_inGracePeriod) return;

      final res  = results[0];
      final aRes = results[1];

      if (res['success'] == true) {
        final list = List<Map<String, dynamic>>.from(res['groups'] ?? []);
        final g = list.isNotEmpty ? list.first : null;
        List<Map<String, dynamic>> a = [];
        if (g != null && g['my_role'] == 'admin' && aRes['success'] == true) {
          a = List<Map<String, dynamic>>.from(aRes['approvals'] ?? []);
        }
        _sLoaded = true;
        _setGroup(g, a);
      } else {
        // Only show error if we have nothing cached to fall back on.
        if (!_sLoaded && mounted) {
          setState(() => _error = res['message'] ?? AppLocalizations.of(context)!.errorLoadingData);
        }
      }
    } catch (e) {
      if (!_sLoaded && mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    if (name.isEmpty) {
      _notify(AppLocalizations.of(context)!.pleaseEnterAGroupName, error: true);
      return;
    }

    // ── Instant optimistic UI — show the group immediately, no spinner ──────
    _nameCtrl.clear();
    _descCtrl.clear();
    final optimisticGroup = <String, dynamic>{
      'id':                        -1, // placeholder until server responds
      'name':                      name,
      'description':               desc,
      'invite_code':               '--------',
      'owner_username':            widget.currentUsername ?? '',
      'my_role':                   'admin',
      'member_count':              1,
      'pending_approvals':         0,
      'created_at':                DateTime.now().toIso8601String(),
      'i_require_approval':        0,
      'i_can_approve':             1,
      'require_approval_for_all':  0,
      'approval_threshold':        null,
    };
    _sBgOp = true;
    _sLoaded = true;
    _sLastMutation = DateTime.now();
    _setGroup(optimisticGroup, []);
    setState(() => _creating = true);
    widget.onGroupsChanged?.call();
    _notify(AppLocalizations.of(context)!.groupCreatedSuccessfully);

    // ── POST in background — update with real data when done ─────────────────
    try {
      final res = await ApiService.createGroup(name: name, description: desc);
      if (!mounted) return;
      if (res['success'] == true) {
        // Replace placeholder with real server data (real id, real invite_code)
        final g = Map<String, dynamic>.from(
          (res['group'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        g['my_role']                  = 'admin';
        g['member_count']             = 1;
        g['pending_approvals']        = 0;
        g['created_at']               = optimisticGroup['created_at'];
        g['i_require_approval']       = 0;
        g['i_can_approve']            = 1;
        g['require_approval_for_all'] = 0;
        g['approval_threshold']       = null;
        _setGroup(g, []);
      } else {
        // Server rejected — undo optimistic update
        _setGroup(null, []);
        _notify(res['message'] ?? AppLocalizations.of(context)!.errorCreatingGroup, error: true);
      }
    } catch (e) {
      // Keep optimistic group — server may have succeeded despite timeout.
      // Pull-to-refresh will get the real invite code.
    } finally {
      _sBgOp = false;
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinGroup() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _notify(AppLocalizations.of(context)!.pleaseEnterAnInviteCode, error: true);
      return;
    }
    setState(() => _joining = true);
    try {
      final res = await ApiService.joinGroupByCode(code);
      if (!mounted) return;
      if (res['success'] == true) {
        _codeCtrl.clear();
        _notify(AppLocalizations.of(context)!.successfullyJoined);
        widget.onGroupsChanged?.call();
        await _load();
      } else {
        _notify(res['message'] ?? AppLocalizations.of(context)!.invalidCode, error: true);
      }
    } catch (e) {
      if (mounted) _notify(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _deleteOrLeave() async {
    if (_group == null) return;
    final isAdmin = _group!['my_role'] == 'admin';
    final groupId = _group!['id'] as int;

    // ── Confirm ──────────────────────────────────────────────────────────────
    final ok = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Builder(builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.textColor(context).withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAdmin ? CupertinoIcons.trash : CupertinoIcons.square_arrow_right,
                  color: TradeRepublicTheme.textColor(context),
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isAdmin
                    ? AppLocalizations.of(context)!.deleteGroup1
                    : AppLocalizations.of(context)!.leaveGroup1,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                isAdmin
                    ? AppLocalizations.of(context)!.thisWillPermanentlyDeleteTheGroupForAllMem
                    : AppLocalizations.of(context)!.youWillBeRemovedFromThisGroup,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: TradeRepublicTheme.hintColor(context, opacity: 0.7),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: TradeRepublicButton(
                  label: isAdmin
                      ? AppLocalizations.of(context)!.deleteGroup
                      : AppLocalizations.of(context)!.leaveGroup,
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: Icon(
                    isAdmin ? CupertinoIcons.trash : CupertinoIcons.square_arrow_right,
                    size: 18,
                  ),
                  isSecondary: true,
                  showShadow: false,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.cancel,
                  onPressed: () => Navigator.pop(ctx, false),
                  isSecondary: true,
                  showShadow: false,
                ),
              ),
            ],
          ),
        );
      }),
    );

    if (ok != true || !mounted) return;

    // Instant optimistic update — show "No Groups" immediately, no spinner.
    _sBgOp = true;
    _sLoaded = true;
    _sLastMutation = DateTime.now();
    _setGroup(null, []);
    widget.onGroupsChanged?.call();
    _notify(
      isAdmin
          ? AppLocalizations.of(context)!.groupDeletedSuccessfully
          : AppLocalizations.of(context)!.leftGroupSuccessfully,
    );

    // Fire the DELETE in the background — never block the UI.
    unawaited(() async {
      try {
        await (isAdmin
            ? ApiService.deleteGroup(groupId)
            : ApiService.leaveGroup(groupId));
      } catch (_) {
        // Silently ignore.
      } finally {
        _sBgOp = false;
      }
    }());
  }

  Future<void> _approveOrReject(Map<String, dynamic> approval, String status) async {
    final approvalId = approval['id'];
    // Optimistic: remove from list immediately
    final newApprovals = _approvals.where((a) => a['id'] != approvalId).toList();
    final newGroup = _group != null ? Map<String, dynamic>.from(_group!) : null;
    if (newGroup != null) {
      final cur = (newGroup['pending_approvals'] as num? ?? 0).toInt();
      newGroup['pending_approvals'] = (cur - 1).clamp(0, 9999);
    }
    _setGroup(newGroup, newApprovals);
    try {
      final res = await ApiService.processPurchaseApproval(
        approval['group_id'],
        approvalId,
        status,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _notify(status == 'approved'
            ? AppLocalizations.of(context)!.approved
            : AppLocalizations.of(context)!.rejected);
      } else {
        // Rollback: reload from DB
        _notify(
          res['message'] ?? AppLocalizations.of(context)!.anErrorOccurred,
          error: true,
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        _notify(e.toString(), error: true);
        await _load(); // Rollback on error
      }
    }
  }

  void _notify(String msg, {bool error = false}) {
    if (!mounted) return;
    if (error) {
      TopNotification.error(context, msg);
    } else {
      TopNotification.success(context, msg);
    }
  }

  void _openGroupMessages() {
    if (_group == null) return;

    final groupIdRaw = _group!['id'];
    final groupId = int.tryParse(groupIdRaw.toString());
    if (groupId == null || groupId <= 0) {
      _notify('Invalid group', error: true);
      return;
    }

    final partnerId = 'group:$groupId';
    final partnerName = (_group!['name']?.toString().trim().isNotEmpty == true)
        ? _group!['name'].toString()
        : AppLocalizations.of(context)!.groups;

    final profileImage = _group!['image_url']?.toString() ?? '';

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.94,
      child: ChatModal(
        partnerId: partnerId,
        partnerName: partnerName,
        isDark: widget.isDark,
        initialProfileImage: profileImage,
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          _Header(onRefresh: _load),
          const TradeRepublicDivider(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CultiooLoadingIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_group != null) {
      return _GroupView(
        group: _group!,
        approvals: _approvals,
        currentUsername: widget.currentUsername,
        isDark: widget.isDark,
        creating: _creating,
        onRefresh: _load,
        onOpenGroupMessages: _openGroupMessages,
        onDeleteOrLeave: _deleteOrLeave,
        onApproveOrReject: _approveOrReject,
      );
    }
    return _NoGroupView(
      nameCtrl:  _nameCtrl,
      descCtrl:  _descCtrl,
      codeCtrl:  _codeCtrl,
      creating:  _creating,
      joining:   _joining,
      onCreate:  _createGroup,
      onJoin:    _joinGroup,
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  const _Header({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.groups.toUpperCase(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: TradeRepublicTheme.textColor(context),
                    letterSpacing: -0.8,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)!.createYourFirstTeam,
                  style: TradeRepublicTheme.bodySmall(context),
                ),
              ],
            ),
          ),
          TradeRepublicButton(
            width: 40,
            height: 40,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(12),
            isSecondary: true,
            showShadow: false,
            icon: Icon(
              CupertinoIcons.refresh,
              size: 18,
              color: TradeRepublicTheme.textColor(context),
            ),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.exclamationmark_circle,
                size: 52, color: TradeRepublicTheme.hintColor(context)),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TradeRepublicTheme.bodyMedium(context)),
            const SizedBox(height: 20),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.retry,
              onPressed: onRetry,
              icon: const Icon(CupertinoIcons.refresh, size: 16),
              showShadow: false,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── No-group view ────────────────────────────────────────────────────────────

class _NoGroupView extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController codeCtrl;
  final bool creating;
  final bool joining;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  const _NoGroupView({
    required this.nameCtrl,
    required this.descCtrl,
    required this.codeCtrl,
    required this.creating,
    required this.joining,
    required this.onCreate,
    required this.onJoin,
  });

  @override
  State<_NoGroupView> createState() => _NoGroupViewState();
}

class _NoGroupViewState extends State<_NoGroupView> {
  int _tab = 0; // 0 = Create, 1 = Join

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero illustration ────────────────────────────────────────
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 96,
                height: 96,
                child: Icon(
                  CupertinoIcons.person_2_fill,
                  size: 42,
                  color: TradeRepublicTheme.textColor(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              AppLocalizations.of(context)!.noGroupsYet.toUpperCase(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: TradeRepublicTheme.textColor(context),
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              AppLocalizations.of(context)!.createYourFirstTeam,
              style: TradeRepublicTheme.bodySmall(context),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),

          // ── Segmented control ────────────────────────────────────────
          TradeRepublicSlider(
            labels: [
              AppLocalizations.of(context)!.createGroup,
              AppLocalizations.of(context)!.joinGroup,
            ],
            selectedIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
            height: 48,
          ),
          const SizedBox(height: 20),

          // ── Create tab ───────────────────────────────────────────────
          if (_tab == 0) ...[
            TradeRepublicCard(
              boxShadow: const [],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TradeRepublicListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.person_2_fill,
                        size: 17,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    title: AppLocalizations.of(context)!.createGroup.toUpperCase(),
                    subtitle: AppLocalizations.of(context)!.descriptionOptional,
                  ),
                  const TradeRepublicDivider(),
                  const SizedBox(height: 10),
                  TradeRepublicTextField(
                    controller: widget.nameCtrl,
                    hintText: AppLocalizations.of(context)!.groupName,
                    prefixIcon: Icon(CupertinoIcons.at,
                        size: 17,
                        color: TradeRepublicTheme.hintColor(context)),
                  ),
                  const SizedBox(height: 10),
                  TradeRepublicTextField(
                    controller: widget.descCtrl,
                    maxLines: 2,
                    hintText: AppLocalizations.of(context)!.descriptionOptional,
                    prefixIcon: Icon(CupertinoIcons.doc_plaintext,
                        size: 17,
                        color: TradeRepublicTheme.hintColor(context)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.createGroup,
                      onPressed: widget.creating ? null : widget.onCreate,
                      isLoading: widget.creating,
                      icon: const Icon(CupertinoIcons.sparkles, size: 17),
                      showShadow: false,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Join tab ─────────────────────────────────────────────────
          if (_tab == 1) ...[
            TradeRepublicCard(
              boxShadow: const [],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TradeRepublicListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.arrow_right_circle_fill,
                        size: 17,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    title: AppLocalizations.of(context)!.joinGroup.toUpperCase(),
                    subtitle: AppLocalizations.of(context)!.inviteCode,
                  ),
                  const TradeRepublicDivider(),
                  const SizedBox(height: 10),
                  TradeRepublicTextField(
                    controller: widget.codeCtrl,
                    hintText: AppLocalizations.of(context)!.enterCode,
                    textCapitalization: TextCapitalization.characters,
                    prefixIcon: Icon(CupertinoIcons.ticket_fill,
                        size: 17,
                        color: TradeRepublicTheme.hintColor(context)),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      fontSize: 18,
                      color: TradeRepublicTheme.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.joinGroup,
                      onPressed: widget.joining ? null : widget.onJoin,
                      isLoading: widget.joining,
                      icon: const Icon(CupertinoIcons.arrow_right_square_fill,
                          size: 17),
                      showShadow: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Group view ───────────────────────────────────────────────────────────────

class _GroupView extends StatelessWidget {
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> approvals;
  final String? currentUsername;
  final bool isDark;
  final bool creating;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenGroupMessages;
  final Future<void> Function() onDeleteOrLeave;
  final Future<void> Function(Map<String, dynamic>, String) onApproveOrReject;

  const _GroupView({
    required this.group,
    required this.approvals,
    required this.currentUsername,
    required this.isDark,
    required this.creating,
    required this.onRefresh,
    required this.onOpenGroupMessages,
    required this.onDeleteOrLeave,
    required this.onApproveOrReject,
  });

  bool get _isAdmin => group['my_role'] == 'admin';

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CultiooSliverRefreshControl(onRefresh: onRefresh),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero card ────────────────────────────────────────────
                _HeroCard(
                  group: group,
                  isAdmin: _isAdmin,
                  isDark: isDark,
                ),
                const SizedBox(height: 20),

                // ── Invite code (admin) ──────────────────────────────────
                if (_isAdmin) ...[                  
                  creating
                      ? _InviteCodeCard(
                          inviteCode: '· · · · · · · ·',
                          loading: true,
                        )
                      : _InviteCodeCard(
                          inviteCode: group['invite_code']?.toString() ?? '',
                          loading: false,
                        ),
                  const SizedBox(height: 14),
                ],

                TradeRepublicCard(
                  boxShadow: const [],
                  child: SizedBox(
                    width: double.infinity,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.messages,
                      icon: const Icon(CupertinoIcons.chat_bubble_2_fill, size: 17),
                      onPressed: onOpenGroupMessages,
                      showShadow: false,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Pending approvals (admin) ────────────────────────────
                if (_isAdmin && approvals.isNotEmpty) ...[
                  TradeRepublicSectionHeader(
                    title: AppLocalizations.of(context)!.pending.toUpperCase(),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${approvals.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: TradeRepublicTheme.textColor(context),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(bottom: 12),
                  ),
                  TradeRepublicCard(
                    boxShadow: const [],
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (int i = 0; i < approvals.length; i++) ...[
                          if (i > 0) const TradeRepublicDivider(),
                          _ApprovalRow(
                            approval: approvals[i],
                            onApprove: () =>
                                onApproveOrReject(approvals[i], 'approved'),
                            onReject: () =>
                                onApproveOrReject(approvals[i], 'rejected'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Delete / Leave ───────────────────────────────────────
                TradeRepublicCard(
                  boxShadow: const [],
                  padding: EdgeInsets.zero,
                  child: TradeRepublicListTile(
                    title: _isAdmin
                        ? AppLocalizations.of(context)!.deleteGroup.toUpperCase()
                        : AppLocalizations.of(context)!.leaveGroup.toUpperCase(),
                    subtitle: _isAdmin
                        ? AppLocalizations.of(context)!
                            .thisWillPermanentlyDeleteTheGroupForAllMem
                        : AppLocalizations.of(context)!
                            .youWillBeRemovedFromThisGroup,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _isAdmin
                            ? CupertinoIcons.trash
                            : CupertinoIcons.square_arrow_right,
                        size: 17,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    onTap: onDeleteOrLeave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Hero card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isAdmin;
  final bool isDark;

  const _HeroCard({
    required this.group,
    required this.isAdmin,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textCol = TradeRepublicTheme.textColor(context);
    final memberCount =
        int.tryParse(group['member_count']?.toString() ?? '') ?? 1;
    final pendingCount =
        int.tryParse(group['pending_approvals']?.toString() ?? '') ?? 0;
    final createdAt = group['created_at']?.toString().split('T').first ?? '';

    return TradeRepublicCard(
      boxShadow: const [],
      padding: EdgeInsets.zero,
      borderRadius: TradeRepublicTheme.borderRadiusLarge,
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: BoxDecoration(
              color: TradeRepublicTheme.fillColor(context, opacity: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: TradeRepublicListTile(
              padding: EdgeInsets.zero,
              leading: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: textCol,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    (group['name'] ?? 'G').substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              title: (group['name'] ?? '').toUpperCase(),
              subtitle: (group['description'] != null &&
                      (group['description'] as String).isNotEmpty)
                  ? group['description']
                  : (createdAt.isNotEmpty
                      ? '${AppLocalizations.of(context)!.accountCreated}: $createdAt'
                      : null),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAdmin
                      ? AppLocalizations.of(context)!.admin.toUpperCase()
                      : AppLocalizations.of(context)!.member.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                ),
              ),
            ),
          ),

          // ── Stats row ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                _StatChip(
                  icon: CupertinoIcons.person_2_fill,
                  value: memberCount.toString(),
                  label: AppLocalizations.of(context)!.member,
                  color: textCol,
                ),
                if (isAdmin && pendingCount > 0) ...[
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: CupertinoIcons.clock_fill,
                    value: pendingCount.toString(),
                    label: AppLocalizations.of(context)!.pending,
                    color: textCol,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Invite code card ─────────────────────────────────────────────────────────

class _InviteCodeCard extends StatelessWidget {
  final String inviteCode;
  final bool loading;
  const _InviteCodeCard({required this.inviteCode, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final textCol = TradeRepublicTheme.textColor(context);
    return TradeRepublicCard(
      boxShadow: const [],
      padding: EdgeInsets.zero,
      child: Opacity(
        opacity: loading ? 0.5 : 1.0,
        child: Column(
        children: [
          // Label row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(CupertinoIcons.link,
                    size: 15,
                    color: TradeRepublicTheme.hintColor(context, opacity: 0.5)),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.inviteCode,
                  style: TradeRepublicTheme.bodySmall(context),
                ),
                const Spacer(),
                TradeRepublicButton(
                  width: 36,
                  height: 36,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: textCol.withOpacity(0.10),
                  foregroundColor: textCol,
                  showShadow: false,
                  icon: const Icon(CupertinoIcons.doc_on_doc, size: 15),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: inviteCode));
                    TopNotification.success(
                      context,
                      AppLocalizations.of(context)!.codeCopied,
                    );
                  },
                ),
              ],
            ),
          ),
          // Code display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: textCol.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20)),
            ),
            child: Center(
              child: Text(
                inviteCode.split('').join('  '),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: TradeRepublicTheme.textColor(context),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ─── Approval row ─────────────────────────────────────────────────────────────

class _ApprovalRow extends StatelessWidget {
  final Map<String, dynamic> approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalRow({
    required this.approval,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final name = [
      approval['requester_firstname'],
      approval['requester_lastname'],
    ].where((v) => v != null && (v as String).isNotEmpty).join(' ');
    final amount = approval['total_amount']?.toString() ?? '–';
    final cartItems = approval['cart_items'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Person + amount + buttons
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: TradeRepublicTheme.fillColor(context, opacity: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: TradeRepublicTheme.textColor(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty
                          ? name
                          : approval['requester_username'] ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                    Text(
                      '{currencySymbol} $amount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: TradeRepublicTheme.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Approve / Reject
              Row(
                children: [
                  _ActionBtn(
                    icon: CupertinoIcons.check_mark,
                    color: TradeRepublicTheme.textColor(context),
                    onTap: onApprove,
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    icon: CupertinoIcons.xmark,
                    color: TradeRepublicTheme.textColor(context),
                    onTap: onReject,
                  ),
                ],
              ),
            ],
          ),
          // Cart items
          if (cartItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: cartItems.take(4).map((item) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.fillColor(context, opacity: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item['product_name'] ?? ''} ×${item['quantity'] ?? 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: TradeRepublicTheme.hintColor(context,
                          opacity: 0.65),
                    ),
                  ),
                );
              }).toList()
                ..addAll(cartItems.length > 4
                    ? [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: TradeRepublicTheme.fillColor(context,
                                opacity: 0.07),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${cartItems.length - 4}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: TradeRepublicTheme.hintColor(context,
                                  opacity: 0.65),
                            ),
                          ),
                        ),
                      ]
                    : []),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TradeRepublicButton(
      width: 38,
      height: 38,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(10),
      backgroundColor: color.withOpacity(0.12),
      foregroundColor: color,
      showShadow: false,
      icon: Icon(icon, size: 16),
      onPressed: onTap,
    );
  }
}

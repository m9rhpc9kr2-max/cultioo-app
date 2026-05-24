import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/number_formatters.dart';
import '../services/api_service.dart';
import '../services/trade_republic_widgets.dart';
import 'credit_card_widget.dart';

// iOS-specific imports
import '../services/app_localizations.dart';
import '../services/cultioo_spinner.dart';

class PaymentMethodsModal extends StatefulWidget {
  final String accessToken;
  final VoidCallback? onShowAddPaymentMethod;

  const PaymentMethodsModal({
    super.key,
    required this.accessToken,
    this.onShowAddPaymentMethod,
  });

  @override
  State<PaymentMethodsModal> createState() => _PaymentMethodsModalState();
}

class _PaymentMethodsModalState extends State<PaymentMethodsModal> {
  List<Map<String, dynamic>> _paymentMethods = [];
  Map<String, dynamic>? _paymentTermsStatus;
  bool _isLoading = true;
  String? _errorMessage;

  // Monioo Wallet state
  double _walletBalance = 0;
  List<Map<String, dynamic>> _walletTransactions = [];
  bool _walletLoaded = false;

  // Payment defaults
  String _defaultProduct = 'card';
  String _defaultShipping = 'card';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _fetchWalletBalance();

    try {
      print('💳 Loading payment methods...');
      final results = await Future.wait([
        ApiService.getUserPaymentMethods(),
        ApiService.getPaymentTermsStatus(),
        ApiService.getPaymentDefaults(),
      ]);

      final methods = results[0] as List<Map<String, dynamic>>;
      final termsStatus = results[1] as Map<String, dynamic>;
      final defaults = results[2] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _paymentTermsStatus = termsStatus;
        _defaultProduct =
            defaults['default_payment_product']?.toString() ?? 'card';
        _defaultShipping =
            defaults['default_payment_shipping']?.toString() ?? 'card';
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading payment methods: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    }
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final walletData = await ApiService.getWallet();
      print('💰 Wallet response: success=${walletData["success"]}, balance=${walletData["wallet"]?["balance"]}');
      if (!mounted) return;
      if (walletData['success'] == true && walletData['wallet'] != null) {
        final raw = walletData['wallet']['balance'];
        final balance = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '0') ?? 0.0;
        setState(() {
          _walletBalance = balance;
          _walletTransactions = List<Map<String, dynamic>>.from(
            walletData['transactions'] ?? [],
          );
          _walletLoaded = true;
        });
        print('💰 Wallet balance set to \$$_walletBalance');
      } else {
        print('⚠️ Wallet load failed: ${walletData["error"] ?? walletData["message"]}');
      }
    } catch (e) {
      print('❌ Error loading wallet balance: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        children: [
          // ─── Header ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.paymentMethods,
                    style: TradeRepublicTheme.titleLarge(
                      context,
                    ).copyWith(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                TradeRepublicButton(
                  icon: const Icon(CupertinoIcons.plus, size: 18),
                  width: 40,
                  height: 40,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(12),
                  showShadow: false,
                  onPressed: () {
                    if (widget.onShowAddPaymentMethod != null) {
                      Navigator.pop(context);
                      widget.onShowAddPaymentMethod!();
                    } else {
                      _showAddPaymentMethodSheet();
                    }
                  },
                ),
              ],
            ),
          ),

          // ─── Content ───────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CultiooLoadingIndicator())
                : _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage!,
                      style: TradeRepublicTheme.bodySmall(context),
                    ),
                  )
                : _paymentMethods.isEmpty && !_walletLoaded
                ? _buildEmptyState(isDark)
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildWalletCard(isDark),
                      const SizedBox(height: 20),
                      _buildPaymentDefaultsSection(isDark),
                      if (_paymentTermsStatus?['enabled'] == true) ...[
                        const SizedBox(height: 20),
                        _buildNet3060Card(isDark),
                      ],
                      if (_paymentMethods.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        TradeRepublicSectionHeader(
                          title: l10n.savedPaymentMethods,
                          padding: const EdgeInsets.only(bottom: 12),
                        ),
                        ..._paymentMethods.map(
                          (method) => _buildPaymentMethodCard(method, isDark),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
          ),

          // ─── Bottom Button ─────────────────────────────────
          SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: TradeRepublicButton(
                label: l10n.addPaymentMethod,
                showShadow: false,
                onPressed: () {
                  if (widget.onShowAddPaymentMethod != null) {
                    Navigator.pop(context);
                    widget.onShowAddPaymentMethod!();
                  } else {
                    _showAddPaymentMethodSheet();
                  }
                },
                width: double.infinity,
                height: 50,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MONIOO WALLET CARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildWalletCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);

    return TradeRepublicCard(
      boxShadow: const [],
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ──
          TradeRepublicSectionHeader(
            title: l10n.moniooWallet,
            subtitle: l10n.walletBalance,
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: textCol.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                CupertinoIcons.money_dollar_circle_fill,
                color: textCol,
                size: 24,
              ),
            ),
            trailing: TradeRepublicButton(
              label: l10n.topUp,
              onPressed: () => _showTopUpSheet(isDark),
              height: 38,
              isSecondary: true,
              showShadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.only(bottom: 12),
          ),
          const SizedBox(height: 20),

          // ── Balance ──
          Text(
            formatCurrencyUsd(_walletBalance),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              color: textCol,
            ),
          ),

          // ── Balance chart ──
          if (_walletTransactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: TradeRepublicBarChart(
                data: _walletTransactions.reversed
                    .map((tx) => ((tx['amount'] as num?)?.abs().toDouble() ?? 0.0))
                    .where((v) => v > 0)
                    .toList(),
                isLight: !isDark,
                valueFormatter: formatCurrencyUsd,
              ),
            ),
          ],

          // ── Recent transactions ──
          if (_walletTransactions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const TradeRepublicDivider(),
            const SizedBox(height: 12),
            TradeRepublicSectionHeader(
              title: l10n.recentTransactions,
              trailing: TradeRepublicButton(
                label: l10n.viewAll,
                isSecondary: true,
                showShadow: false,
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _showAllTransactionsSheet(isDark),
              ),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            ..._walletTransactions.take(5).map((tx) {
              final isPositive =
                  (tx['type'] == 'topup' ||
                  tx['type'] == 'refund' ||
                  tx['type'] == 'bonus');
              final txId = tx['id'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color:
                            textCol.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isPositive
                            ? CupertinoIcons.arrow_down_left
                            : CupertinoIcons.arrow_up_right,
                        size: 13,
                        color: textCol.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tx['description']?.toString() ??
                            _txTypeLabel(tx['type']?.toString() ?? ''),
                        style: TradeRepublicTheme.titleSmall(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${isPositive ? "+" : ""}${formatCurrencyUsd((tx['amount'] as num).abs().toDouble())}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textCol,
                      ),
                    ),
                    if (txId != null) ...[
                      const SizedBox(width: 6),
                      TradeRepublicButton(
                        icon: const Icon(CupertinoIcons.doc_text, size: 13),
                        onPressed: () => _downloadReceipt(txId),
                        isSecondary: true,
                        showShadow: false,
                        width: 28,
                        height: 28,
                        padding: EdgeInsets.zero,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _txTypeLabel(String type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case 'topup':
        return l10n.walletTopup;
      case 'payment':
        return l10n.walletPayment;
      case 'refund':
        return l10n.walletRefund;
      case 'bonus':
        return l10n.walletBonus;
      default:
        return type;
    }
  }

  void _showAllTransactionsSheet(bool isDark) {
    final textCol = TradeRepublicTheme.textColor(context);
    final l10n = AppLocalizations.of(context)!;
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.transactionHistory,
                    style: TradeRepublicTheme.titleLarge(
                      context,
                    ).copyWith(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  l10n.walletEntriesCount(_walletTransactions.length),
                  style: TradeRepublicTheme.bodySmall(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _walletTransactions.length,
              separatorBuilder: (_, _) => const TradeRepublicDivider(),
              itemBuilder: (_, i) {
                final tx = _walletTransactions[i];
                final isPositive =
                    (tx['type'] == 'topup' ||
                    tx['type'] == 'refund' ||
                    tx['type'] == 'bonus');
                final txId = tx['id'];
                final date = tx['created_at'] != null
                    ? DateTime.tryParse(tx['created_at'].toString())
                    : null;
                final dateStr = date != null
                    ? '${date.day}.${date.month}.${date.year}'
                    : '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              textCol.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isPositive
                              ? CupertinoIcons.arrow_down_left
                              : CupertinoIcons.arrow_up_right,
                          size: 15,
                          color: textCol.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx['description']?.toString() ??
                                  _txTypeLabel(tx['type']?.toString() ?? ''),
                              style: TradeRepublicTheme.titleSmall(context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dateStr.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: TradeRepublicTheme.bodySmall(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isPositive ? "+" : "-"}${formatCurrencyUsd((tx['amount'] as num).abs().toDouble())}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textCol,
                            ),
                          ),
                          if (txId != null) ...[
                            const SizedBox(height: 4),
                            TradeRepublicButton(
                              label: l10n.receiptVoucher,
                              isSecondary: true,
                              showShadow: false,
                              height: 26,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              icon: Icon(
                                CupertinoIcons.doc_text,
                                size: 11,
                                color: textCol.withOpacity(0.75),
                              ),
                              onPressed: () => _downloadReceipt(txId),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _downloadReceipt(dynamic txId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      _showSnackBar(l10n.preparingReceipt);
      final token = await ApiService.getToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/wallet/receipt/$txId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      // Validate we actually got a PDF, not a JSON error
      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 || !contentType.contains('pdf')) {
        final body = json.decode(response.body);
        throw Exception(
          body['error'] ?? body['message'] ?? 'Receipt not available yet',
        );
      }

      // Save and open
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File('${docsDir.path}/wallet_receipt_$txId.pdf');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      if (result.type != ResultType.done) {
        _showSnackBar('${l10n.receiptSaved}: wallet_receipt_$txId.pdf');
      }
    } catch (e) {
      _showSnackBar('${l10n.receiptError}: $e');
    }
  }

  /// Shows a bottom sheet after a successful top-up offering to download the receipt
  void _showReceiptAvailableSheet(dynamic txId, double amount) {
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                color: Color(0xFF34C759),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.topUpSuccess,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textCol,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatCurrencyUsd(amount)} ${l10n.walletTopup}',
              style: TextStyle(
                fontSize: 15,
                color: textCol.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            TradeRepublicButton(
              label: l10n.receiptVoucher,
              icon: const Icon(CupertinoIcons.arrow_down_doc_fill, size: 16),
              width: double.infinity,
              onPressed: () {
                Navigator.pop(context);
                _downloadReceipt(txId);
              },
            ),
            const SizedBox(height: 8),
            TradeRepublicButton(
              label: l10n.close,
              isSecondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PAYMENT DEFAULTS SECTION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPaymentDefaultsSection(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: l10n.paymentDefaults,
          subtitle: l10n.paymentDefaultsDescription,
          padding: const EdgeInsets.only(bottom: 12),
        ),
        TradeRepublicListTile.navigation(
          title: l10n.defaultForProducts,
          subtitle: _resolveDefaultLabel(_defaultProduct),
          leading: Icon(
            CupertinoIcons.bag_fill,
            size: 18,
            color: textCol.withOpacity(0.8),
          ),
          onTap: () => _showDefaultPicker(
            isDark,
            _defaultProduct,
            _buildMethodOptions(),
            (val) async {
              setState(() => _defaultProduct = val);
              await ApiService.setPaymentDefaults(defaultProduct: val);
              _showSnackBar(l10n.defaultUpdated);
            },
          ),
        ),
        const TradeRepublicDivider(),
        TradeRepublicListTile.navigation(
          title: l10n.defaultForShipping,
          subtitle: _resolveDefaultLabel(_defaultShipping),
          leading: Icon(
            CupertinoIcons.car_fill,
            size: 18,
            color: textCol.withOpacity(0.6),
          ),
          onTap: () => _showDefaultPicker(
            isDark,
            _defaultShipping,
            _buildMethodOptions(),
            (val) async {
              setState(() => _defaultShipping = val);
              await ApiService.setPaymentDefaults(defaultShipping: val);
              _showSnackBar(l10n.defaultUpdated);
            },
          ),
        ),
      ],
    );
  }

  /// Builds picker options from the user's actual saved payment methods.
  /// Keys are method IDs (e.g. 'pm_xxx', '42', 'wallet').
  Map<String, String> _buildMethodOptions() {
    final l10n = AppLocalizations.of(context)!;
    final options = <String, String>{};
    options['wallet'] = l10n.walletPayment1;
    for (final m in _paymentMethods) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      options[id] = _getMethodShortLabel(m);
    }
    return options;
  }

  /// Resolves a stored default key (method ID or legacy type string) to a display label.
  String _resolveDefaultLabel(String key) {
    final l10n = AppLocalizations.of(context)!;
    if (key == 'wallet') return l10n.walletPayment1;
    for (final m in _paymentMethods) {
      if (m['id']?.toString() == key) return _getMethodShortLabel(m);
    }
    // Legacy fallback for old type-string values stored in DB
    switch (key) {
      case 'card':
        return l10n.cardPayment1;
      case 'sepa':
        return l10n.sepaTransfer;
      case 'ach':
        return l10n.achTransfer1;
      case 'wire':
        return l10n.wireTransfer1;
      default:
        return key;
    }
  }

  void _showDefaultPicker(
    bool isDark,
    String currentValue,
    Map<String, String> options,
    Function(String) onChanged,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...options.entries.map((entry) {
            final isSelected = entry.key == currentValue;
            final fg = TradeRepublicTheme.selectionContainerForeground(context);
            return TradeRepublicListTile(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              title: entry.value,
              backgroundColor: isSelected
                  ? TradeRepublicTheme.selectionContainerBackground(context)
                  : null,
              titleColor: isSelected ? fg : null,
              trailing: isSelected
                  ? Icon(
                      CupertinoIcons.checkmark_alt,
                      color: fg,
                      size: 18,
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                onChanged(entry.key);
              },
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  NET 30/60 CREDIT CARD
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNet3060Card(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);
    final used = (_paymentTermsStatus?['used'] ?? 0).toDouble();
    final limit = (_paymentTermsStatus?['limit'] ?? 75000).toDouble();
    final available = (_paymentTermsStatus?['available'] ?? 0);
    final daysUntilDue = _paymentTermsStatus?['daysUntilDue'];
    final percent = (used / limit).clamp(0.0, 1.0);

    return TradeRepublicCard(
      boxShadow: const [],
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: textCol.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  CupertinoIcons.building_2_fill,
                  color: textCol,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  l10n.net3060Credit,
                  style: TradeRepublicTheme.titleMedium(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Progress bar ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.creditUtilization,
                style: TradeRepublicTheme.titleSmall(context),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: TradeRepublicTheme.titleSmall(
                  context,
                ).copyWith(color: textCol),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: 8,
                    color: textCol.withOpacity(0.08),
                  ),
                  Container(
                    width: constraints.maxWidth * percent.clamp(0.0, 1.0),
                    height: 8,
                    color: textCol,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Stats row ──
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  l10n.available,
                  '\$${formatNumberUS(available.toDouble(), fractionDigits: 0)}',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  l10n.usedLabel,
                  '\$${formatNumberUS(used, fractionDigits: 0)}',
                ),
              ),
              if (daysUntilDue != null)
                Expanded(child: _buildStatItem(l10n.daysLeft, '$daysUntilDue')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TradeRepublicTheme.bodySmall(context)),
        const SizedBox(height: 4),
        Text(value, style: TradeRepublicTheme.titleMedium(context)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TOP-UP SHEET
  // ═══════════════════════════════════════════════════════════════════════════
  void _showTopUpSheet(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    bool isLoading = false;
    final topUpMethods = _paymentMethods
        .where((m) => m['type']?.toString() == 'card')
        .toList();
    Map<String, dynamic>? selectedMethod = topUpMethods.isNotEmpty
        ? topUpMethods.first
        : null;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final textCol = TradeRepublicTheme.textColor(ctx);
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.topUpWallet,
                    style: TradeRepublicTheme.titleLarge(
                      ctx,
                    ).copyWith(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.currentBalanceAmount(
                      formatNumberUS(_walletBalance),
                    ),
                    style: TradeRepublicTheme.titleSmall(ctx),
                  ),
                  const SizedBox(height: 20),

                  // ── Payment method picker ──────────────────────────────────
                  Text(
                    '${l10n.paymentMethods} · Stripe',
                    style: TradeRepublicTheme.titleSmall(ctx),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.topUpViaCard,
                    style: TradeRepublicTheme.bodySmall(ctx),
                  ),
                  const SizedBox(height: 10),
                  if (topUpMethods.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: textCol.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.info_circle,
                            color: textCol.withOpacity(0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.addCardFirstTopUp,
                              style: TradeRepublicTheme.bodySmall(ctx),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: topUpMethods.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final m = topUpMethods[i];
                          final isSelected =
                              selectedMethod != null &&
                              selectedMethod!['id']?.toString() ==
                                  m['id']?.toString();
                          return TradeRepublicCard(
                            onTap: () =>
                                setSheetState(() => selectedMethod = m),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            boxShadow: const [],
                            backgroundColor: isSelected
                                ? TradeRepublicTheme.selectionContainerBackground(
                                    context,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            border: null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getMethodIconForTopUp(m['type']?.toString()),
                                  size: 16,
                                  color: isSelected
                                      ? TradeRepublicTheme
                                          .selectionContainerForeground(context)
                                      : textCol.withOpacity(0.6),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getMethodShortLabel(m),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? TradeRepublicTheme
                                            .selectionContainerForeground(context)
                                        : textCol,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Quick amounts ──────────────────────────────────────────
                  Row(
                    children: [25.0, 50.0, 100.0, 500.0].map((amt) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: TradeRepublicButton(
                            label: '\$${formatNumberUS(amt, fractionDigits: 0)}',
                            isSecondary: true,
                            showShadow: false,
                            height: 40,
                            borderRadius: BorderRadius.circular(10),
                            onPressed: () {
                              final cents = (amt * 100).round();
                              final formatted = _CurrencyInputFormatter()
                                  .formatEditUpdate(
                                    const TextEditingValue(text: ''),
                                    TextEditingValue(text: cents.toString()),
                                  )
                                  .text;
                              controller.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Custom amount ──────────────────────────────────────────
                  TradeRepublicTextField.withLabel(
                    label: l10n.topUpAmount,
                    controller: controller,
                    hintText: '0.00',
                    prefixIcon: const Icon(
                      CupertinoIcons.money_dollar,
                      size: 20,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [_CurrencyInputFormatter()],
                  ),
                  const SizedBox(height: 20),

                  // ── Confirm button ─────────────────────────────────────────
                  TradeRepublicButton(
                    label: l10n.topUp,
                    isLoading: isLoading,
                    showShadow: false,
                    width: double.infinity,
                    height: 50,
                    onPressed: (selectedMethod == null || isLoading)
                        ? null
                        : () async {
                            final rawText = controller.text.replaceAll(',', '');
                            final amount = double.tryParse(rawText);
                            if (amount == null || amount < 1) return;
                            setSheetState(() => isLoading = true);
                            try {
                              final result = await ApiService.topUpWallet(
                                amount,
                                paymentMethodId: selectedMethod!['id']
                                    ?.toString(),
                              );
                              if (result['success'] == true) {
                                final rawBal = result['balance'];
                                final newBal = rawBal is num
                                    ? rawBal.toDouble()
                                    : double.tryParse(
                                            rawBal?.toString() ?? '') ??
                                        _walletBalance;
                                setState(() {
                                  _walletBalance = newBal;
                                });
                                Navigator.pop(ctx);
                                _showSnackBar(
                                  '${l10n.topUpSuccess} +${formatCurrencyUsd(amount)}',
                                );
                                _fetchWalletBalance();

                                // If we have a transaction ID, offer to download the receipt
                                final txId = result['transaction_id'];
                                if (txId != null) {
                                  Future.delayed(
                                    const Duration(milliseconds: 800),
                                    () {
                                      if (context.mounted) {
                                        _showReceiptAvailableSheet(
                                          txId,
                                          amount,
                                        );
                                      }
                                    },
                                  );
                                }

                                _loadData();
                              } else {
                                setSheetState(() => isLoading = false);
                                _showSnackBar(
                                  result['message'] ??
                                      result['error'] ??
                                      l10n.errorTitle,
                                );
                              }
                            } catch (e) {
                              setSheetState(() => isLoading = false);
                              _showSnackBar(e.toString());
                            }
                          },
                  ),
                  const SizedBox(height: 12),

                  // ── Security note ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.lock_shield_fill,
                        size: 13,
                        color: textCol.withOpacity(0.35),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        l10n.chargedViaStripe,
                        style: TextStyle(
                          fontSize: 12,
                          color: textCol.withOpacity(0.35),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getMethodIconForTopUp(String? type) {
    switch (type) {
      case 'card':
        return CupertinoIcons.creditcard_fill;
      case 'sepa':
        return CupertinoIcons.building_2_fill;
      case 'ach':
        return CupertinoIcons.building_2_fill;
      case 'wire':
        return CupertinoIcons.arrow_up_right_circle;
      case 'wise':
        return CupertinoIcons.paperplane_fill;
      default:
        return CupertinoIcons.creditcard;
    }
  }

  String _getMethodShortLabel(Map<String, dynamic> method) {
    final type = method['type']?.toString() ?? '';
    switch (type) {
      case 'card':
        final brand = (method['card']?['brand'] ?? method['card_brand'] ?? '')
            .toString()
            .toUpperCase();
        final last4 =
            method['card']?['last4'] ?? method['card_last4'] ?? '????';
        return '$brand ••$last4';
      case 'sepa':
        return 'IBAN ••${method['iban_last4'] ?? '??'}';
      case 'ach':
        return 'ACH ••${method['account_number_last4'] ?? '??'}';
      case 'wire':
        return 'Wire ••${method['account_number_last4'] ?? '??'}';
      case 'wise':
        return 'Wise ••${method['account_number_last4'] ?? '??'}';
      default:
        return type.toUpperCase();
    }
  }

  Widget _buildEmptyState(bool isDark) {
    final textCol = TradeRepublicTheme.textColor(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: textCol.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.creditcard,
              size: 64,
              color: textCol.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            AppLocalizations.of(context)!.noPaymentMethods,
            style: TradeRepublicTheme.titleLarge(
              context,
            ).copyWith(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context)!.addAPaymentMethodToGetStarted,
            style: TradeRepublicTheme.bodySmall(context),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard(Map<String, dynamic> method, bool isDark) {
    final type = method['type'] ?? '';
    final isTransferMethod = ['sepa', 'ach', 'wire', 'wise'].contains(type);
    final isDefault = method['is_default'] == true || method['is_default'] == 1;
    final dynamic id = method['id'];
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);

    print('🔍 Building payment method card: type=$type, method=$method');

    // ── Visual credit / debit card ────────────────────────────────────────────
    if (type == 'card') {
      final brand = method['card']?['brand'] ?? method['card_brand'] ?? 'card';
      final last4 = method['card']?['last4'] ?? method['card_last4'] ?? '****';
      final expMonth = method['card']?['exp_month'] ?? method['card_exp_month'] ?? '**';
      final expYear = method['card']?['exp_year'] ?? method['card_exp_year'] ?? '**';
      final holder = method['cardholder_name']?.toString() ?? '';
      return _buildVisualCardTile(
        id: id,
        isDefault: isDefault,
        visual: CreditCardWidget(
          brand: brand.toString(),
          last4: last4.toString(),
          expMonth: expMonth.toString(),
          expYear: expYear.toString(),
          isDefault: isDefault,
          cardholderName: holder,
        ),
      );
    }

    // ── Visual bank account card (ACH / SEPA / Wire) ──────────────────────────
    if (['sepa', 'ach', 'wire'].contains(type)) {
      final last4 = (type == 'sepa'
              ? method['iban_last4']
              : method['account_number_last4'])
          ?.toString() ?? '????';
      final holder = method['account_holder_name']?.toString() ?? '';
      final routing = type == 'ach'
          ? method['routing_number']?.toString()
          : type == 'wire'
              ? method['swift_bic']?.toString() ?? method['routing_number']?.toString()
              : null;
      return _buildVisualCardTile(
        id: id,
        isDefault: isDefault,
        visual: BankAccountWidget(
          type: type,
          maskedNumber: last4,
          accountHolderName: holder,
          routingOrSwift: routing,
          isDefault: isDefault,
        ),
      );
    }

    IconData icon;
    String title;
    String subtitle;
    Color accentColor;

    switch (type) {
      case 'wire':
        icon = CupertinoIcons.arrow_up_right_circle;
        title = l10n.wireEndingIn(method['account_number_last4'].toString());
        subtitle = method['account_holder_name'] ?? '';
        accentColor = textCol;
        break;
      case 'wise':
        icon = CupertinoIcons.paperplane_fill;
        title = l10n.wiseEndingIn(method['account_number_last4'].toString());
        subtitle = method['account_holder_name'] ?? '';
        accentColor = textCol;
        break;
      default:
        icon = CupertinoIcons.money_dollar_circle_fill;
        title = l10n.paymentMethod;
        subtitle = '';
        accentColor = textCol;
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    return TradeRepublicSwipeAction(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 20,
      foregroundColor: isLight ? Colors.white : Colors.black,
      trailing: TradeRepublicSwipeSpec(
        icon: isTransferMethod
            ? CupertinoIcons.arrow_down_doc_fill
            : CupertinoIcons.trash,
        label: isTransferMethod ? 'Invoice' : 'Delete',
        onActivate: isTransferMethod
            ? () => _downloadInvoiceForTransferMethod(method)
            : () => _deletePaymentMethod(id),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TradeRepublicCard(
          boxShadow: const [],
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TradeRepublicTheme.bodyMedium(context)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TradeRepublicTheme.bodySmall(context),
                      ),
                    ],
                  ],
                ),
              ),
              // Default badge
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: textCol.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 11,
                        color: textCol,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.defaultBadge,
                        style: TextStyle(
                          color: textCol,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared card-style tile with default + delete action row ─────────────────
  Widget _buildVisualCardTile({
    required dynamic id,
    required bool isDefault,
    required Widget visual,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final textCol = TradeRepublicTheme.textColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          visual,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _setDefaultPaymentMethod(id),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: textCol.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDefault
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 14,
                          color: textCol.withValues(alpha: isDefault ? 1.0 : 0.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isDefault ? l10n.defaultBadge : l10n.setAsDefault,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textCol.withValues(alpha: isDefault ? 1.0 : 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _deletePaymentMethod(id),
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.destructiveRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 16,
                    color: TradeRepublicTheme.destructiveRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadInvoiceForTransferMethod(
    Map<String, dynamic> method,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    int? parseOrderId(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    final orderId =
        parseOrderId(method['order_id']) ??
        parseOrderId(method['invoice_order_id']) ??
        parseOrderId(method['latest_order_id']) ??
        parseOrderId(method['related_order_id']);

    if (orderId == null) {
      _showSnackBar(l10n.errorDownloadingInvoice);
      return;
    }

    try {
      final pdfBytes = await ApiService.downloadInvoicePdf(orderId);
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/Invoice_$orderId.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes, flush: true);

      final result = await OpenFilex.open(filePath);
      if (result.type == ResultType.noAppToOpen) {
        TopNotification.info(context, l10n.invoiceSavedNoAppToOpenPdfFiles);
      } else if (result.type != ResultType.done) {
        TopNotification.info(context, l10n.invoiceSavedTo(filePath));
      } else {
        TopNotification.success(context, l10n.downloadInvoice);
      }
    } catch (e) {
      TopNotification.error(
        context,
        '${l10n.errorDownloadingInvoice}: ${e.toString().replaceAll('Exception: ', '')}',
      );
    }
  }

  Future<void> _deletePaymentMethod(dynamic id) async {
    try {
      // TODO: Implement Stripe payment method deletion
      print('🗑️ Delete payment method: $id (${id.runtimeType})');
      _showSnackBar(
        AppLocalizations.of(context)!.paymentMethodDeletionNotYetImplemented,
      );
      // final result = await ApiService.deletePaymentMethod(id);
      // if (result['success'] == true) {
      //   _showSnackBar('Payment method deleted');
      //   _loadData();
      // }
    } catch (e) {
      _showSnackBar(AppLocalizations.of(context)!.errorDeletingPaymentMethod);
    }
  }

  Future<void> _setDefaultPaymentMethod(dynamic id) async {
    try {
      // TODO: Implement Stripe default payment method setting
      print('⭐ Set default payment method: $id (${id.runtimeType})');
      _showSnackBar(AppLocalizations.of(context)!.setDefaultNotYetImplemented);
      // final result = await ApiService.setDefaultPaymentMethod(id);
      // if (result['success'] == true) {
      //   _showSnackBar('Default payment method updated');
      //   _loadData();
      // }
    } catch (e) {
      _showSnackBar(AppLocalizations.of(context)!.errorUpdatingDefault);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    if (message.contains(AppLocalizations.of(context)!.errorTitle) ||
        message.contains('Failed')) {
      TopNotification.error(context, message);
    } else {
      TopNotification.success(context, message);
    }
  }

  void _showAddPaymentMethodSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: AddPaymentMethodSheet(
        isDark: isDark,
        onAdded: () {
          // Reload data when payment method is added
          _loadData();
        },
      ),
    );
  }
}

class AddPaymentMethodSheet extends StatefulWidget {
  final bool isDark;
  final VoidCallback onAdded;

  const AddPaymentMethodSheet({
    super.key,
    required this.isDark,
    required this.onAdded,
  });

  @override
  State<AddPaymentMethodSheet> createState() => _AddPaymentMethodSheetState();
}

class _AddPaymentMethodSheetState extends State<AddPaymentMethodSheet> {
  String _selectedType = 'card'; // 'card', 'sepa', 'ach'
  bool _isLoading = false;

  // Card fields
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cardNameController = TextEditingController();

  // SEPA fields
  final _ibanController = TextEditingController();
  final _sepaNameController = TextEditingController();
  final _bankNameController = TextEditingController();

  // ACH fields
  final _routingController = TextEditingController();
  final _accountController = TextEditingController();
  final _achNameController = TextEditingController();

  // Wise fields
  final _wiseEmailController = TextEditingController();
  final _wiseNameController = TextEditingController();

  void _onControllerChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    for (final c in [
      _cardNumberController, _expiryController, _cardNameController,
      _ibanController, _sepaNameController,
      _routingController, _accountController, _achNameController,
    ]) {
      c.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _cardNumberController, _expiryController, _cardNameController,
      _ibanController, _sepaNameController,
      _routingController, _accountController, _achNameController,
    ]) {
      c.removeListener(_onControllerChanged);
    }
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardNameController.dispose();
    _ibanController.dispose();
    _sepaNameController.dispose();
    _bankNameController.dispose();
    _routingController.dispose();
    _accountController.dispose();
    _achNameController.dispose();
    _wiseEmailController.dispose();
    _wiseNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.addPaymentMethod,
                    style: TradeRepublicTheme.titleLarge(
                      context,
                    ).copyWith(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),

                  // Type selector
                  TradeRepublicSliderExpanded(
                    labels: [
                      AppLocalizations.of(context)!.cardTab,
                      AppLocalizations.of(context)!.sepaTab,
                      AppLocalizations.of(context)!.achTab,
                      AppLocalizations.of(context)!.wireTab,
                    ],
                    selectedIndex: [
                      'card',
                      'sepa',
                      'ach',
                      'wire',
                    ].indexOf(_selectedType),
                    onChanged: (index) {
                      setState(() {
                        _selectedType = ['card', 'sepa', 'ach', 'wire'][index];
                      });
                    },
                    horizontalPadding: 0,
                  ),

                  const SizedBox(height: 24),

                  // Live card preview
                  _buildPreview(),

                  const SizedBox(height: 24),

                  // Form based on selected type
                  if (_selectedType == 'card') _buildCardForm(),
                  if (_selectedType == 'sepa') _buildSepaForm(),
                  if (_selectedType == 'ach') _buildAchForm(),
                  if (_selectedType == 'wire') _buildWireForm(),

                  const SizedBox(height: 20),

                  // Save button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)!.savePaymentMethod,
                    onPressed: _isLoading ? null : _savePaymentMethod,
                    isLoading: _isLoading,
                    showShadow: false,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_selectedType == 'card') {
      // Parse last4 from typed card number
      final raw = _cardNumberController.text.replaceAll(' ', '');
      final last4 = raw.length >= 4 ? raw.substring(raw.length - 4) : '••••';
      // Parse expiry
      final expParts = _expiryController.text.split('/');
      final expM = expParts.isNotEmpty ? expParts[0] : '••';
      final expY = expParts.length > 1 ? expParts[1] : '••';
      // Detect brand from first digit
      String brand = 'card';
      if (raw.startsWith('4')) {
        brand = 'visa';
      } else if (raw.startsWith('5') || raw.startsWith('2')) brand = 'mastercard';
      else if (raw.startsWith('3')) brand = 'amex';
      else if (raw.startsWith('6')) brand = 'discover';
      return CreditCardWidget(
        brand: brand,
        last4: last4,
        expMonth: expM,
        expYear: expY,
        cardholderName: _cardNameController.text.trim(),
      );
    }

    if (_selectedType == 'sepa') {
      final iban = _ibanController.text.replaceAll(' ', '');
      final last4 = iban.length >= 4 ? iban.substring(iban.length - 4) : '••••';
      return BankAccountWidget(
        type: 'sepa',
        maskedNumber: last4,
        accountHolderName: _sepaNameController.text.trim().isEmpty
            ? 'ACCOUNT HOLDER'
            : _sepaNameController.text.trim(),
      );
    }

    if (_selectedType == 'ach') {
      final acc = _accountController.text.trim();
      final last4 = acc.length >= 4 ? acc.substring(acc.length - 4) : '••••';
      return BankAccountWidget(
        type: 'ach',
        maskedNumber: last4,
        accountHolderName: _achNameController.text.trim().isEmpty
            ? 'ACCOUNT HOLDER'
            : _achNameController.text.trim(),
        routingOrSwift: _routingController.text.trim().isEmpty
            ? null
            : _routingController.text.trim(),
      );
    }

    // wire
    final acc = _accountController.text.trim();
    final last4 = acc.length >= 4 ? acc.substring(acc.length - 4) : '••••';
    return BankAccountWidget(
      type: 'wire',
      maskedNumber: last4,
      accountHolderName: _achNameController.text.trim().isEmpty
          ? 'ACCOUNT HOLDER'
          : _achNameController.text.trim(),
      routingOrSwift: _routingController.text.trim().isEmpty
          ? null
          : _routingController.text.trim().toUpperCase(),
    );
  }

  Widget _buildCardForm() {
    return Column(
      children: [
        _buildTextField(
          controller: _cardNumberController,
          label: AppLocalizations.of(context)!.cardNumber,
          hint: '1234 5678 9012 3456',
          keyboardType: TextInputType.number,
          icon: CupertinoIcons.creditcard_fill,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
            _CardNumberFormatter(),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _expiryController,
                label: AppLocalizations.of(context)!.expiry,
                hint: 'MM/YY',
                keyboardType: TextInputType.number,
                icon: CupertinoIcons.calendar,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  _ExpiryDateFormatter(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _cvvController,
                label: AppLocalizations.of(context)!.cvv,
                hint: '123',
                keyboardType: TextInputType.number,
                icon: CupertinoIcons.lock,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _cardNameController,
          label: AppLocalizations.of(context)!.cardholderName1,
          hint: AppLocalizations.of(context)!.johnDoe,
          icon: CupertinoIcons.person,
        ),
      ],
    );
  }

  Widget _buildSepaForm() {
    return Column(
      children: [
        _buildTextField(
          controller: _ibanController,
          label: AppLocalizations.of(context)!.iban,
          hint: AppLocalizations.of(context)!.de89370400440532013000,
          icon: CupertinoIcons.building_2_fill,
          keyboardType: TextInputType.text,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(34),
            _IbanFormatter(),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _sepaNameController,
          label: AppLocalizations.of(context)!.accountHolderName,
          hint: AppLocalizations.of(context)!.johnDoe,
          icon: CupertinoIcons.person,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _bankNameController,
          label: AppLocalizations.of(context)!.bankNameOptional,
          hint: AppLocalizations.of(context)!.deutscheBank,
          icon: CupertinoIcons.building_2_fill,
        ),
      ],
    );
  }

  Widget _buildAchForm() {
    return Column(
      children: [
        _buildTextField(
          controller: _routingController,
          label: AppLocalizations.of(context)!.routingNumber,
          hint: '123456789',
          keyboardType: TextInputType.number,
          icon: CupertinoIcons.creditcard_fill,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _accountController,
          label: AppLocalizations.of(context)!.accountNumber,
          hint: '000123456789',
          keyboardType: TextInputType.number,
          icon: CupertinoIcons.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(17),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _achNameController,
          label: AppLocalizations.of(context)!.accountHolderName,
          hint: AppLocalizations.of(context)!.johnDoe,
          icon: CupertinoIcons.person,
        ),
      ],
    );
  }

  Widget _buildWireForm() {
    return Column(
      children: [
        _buildTextField(
          controller: _routingController,
          label: AppLocalizations.of(context)!.routingNumberSwiftbic,
          hint: 'CHASUS33XXX',
          keyboardType: TextInputType.text,
          icon: CupertinoIcons.arrow_up_right_circle,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(11),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _accountController,
          label: AppLocalizations.of(context)!.accountNumber,
          hint: '000123456789',
          keyboardType: TextInputType.text,
          icon: CupertinoIcons.number,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _achNameController,
          label: AppLocalizations.of(context)!.accountHolderName,
          hint: AppLocalizations.of(context)!.johnDoe,
          icon: CupertinoIcons.person,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                color: TradeRepublicTheme.textColor(context).withOpacity(0.6),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.wireTransferForLargePaymentsOnlyProcessingM,
                  style: TradeRepublicTheme.bodySmall(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TradeRepublicTextField.withLabel(
      label: label,
      controller: controller,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: TradeRepublicTheme.textColor(context).withOpacity(0.4),
        size: 20,
      ),
      keyboardType: keyboardType,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
    );
  }

  Future<void> _savePaymentMethod() async {
    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> result;

      if (_selectedType == 'card') {
        // Parse expiry date
        final expiry = _expiryController.text.replaceAll('/', '').trim();
        if (expiry.length != 4) {
          throw Exception(AppLocalizations.of(context)!.validExpiryDate);
        }

        final month = int.tryParse(expiry.substring(0, 2));
        final year = int.tryParse(expiry.substring(2, 4));

        if (month == null || year == null || month < 1 || month > 12) {
          throw Exception(AppLocalizations.of(context)!.invalidExpiryDate);
        }

        final cardNumber = _cardNumberController.text.replaceAll(' ', '');
        if (cardNumber.length < 13 || cardNumber.length > 19) {
          throw Exception(AppLocalizations.of(context)!.validCardNumber);
        }

        if (_cvvController.text.length < 3) {
          throw Exception(AppLocalizations.of(context)!.validCvv);
        }

        if (_cardNameController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterCardholderName);
        }

        result = await ApiService.saveCard(
          cardNumber: cardNumber,
          expiryMonth: month,
          expiryYear: 2000 + year,
          cvv: _cvvController.text,
          cardholderName: _cardNameController.text.trim(),
          setAsDefault: false,
        );
      } else if (_selectedType == 'sepa') {
        final iban = _ibanController.text.replaceAll(' ', '');
        if (iban.length < 15) {
          throw Exception(AppLocalizations.of(context)!.validIban);
        }

        if (_sepaNameController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountHolder);
        }

        result = await ApiService.saveSepaAccount(
          iban: iban,
          accountHolderName: _sepaNameController.text.trim(),
          bankName: _bankNameController.text.trim().isNotEmpty
              ? _bankNameController.text.trim()
              : null,
          setAsDefault: false,
        );
      } else if (_selectedType == 'ach') {
        if (_routingController.text.length != 9) {
          throw Exception(AppLocalizations.of(context)!.routingMust9Digits);
        }

        if (_accountController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountNumber);
        }

        if (_achNameController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountHolder);
        }

        result = await ApiService.saveAchAccount(
          routingNumber: _routingController.text,
          accountNumber: _accountController.text,
          accountHolderName: _achNameController.text.trim(),
          setAsDefault: false,
        );
      } else if (_selectedType == 'wire') {
        if (_routingController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterRoutingSwift);
        }

        if (_accountController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountNumber);
        }

        if (_achNameController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountHolder);
        }

        // Wire Transfer uses same structure as ACH but with SWIFT/BIC code
        result = await ApiService.saveAchAccount(
          routingNumber: _routingController.text.trim().toUpperCase(),
          accountNumber: _accountController.text.trim(),
          accountHolderName: _achNameController.text.trim(),
          setAsDefault: false,
          paymentType: 'wire',
        );
      } else {
        // Wise
        if (_wiseEmailController.text.trim().isEmpty ||
            !_wiseEmailController.text.contains('@')) {
          throw Exception(AppLocalizations.of(context)!.validEmailAddress);
        }

        if (_wiseNameController.text.trim().isEmpty) {
          throw Exception(AppLocalizations.of(context)!.enterAccountHolder);
        }

        result = await ApiService.saveWiseAccount(
          email: _wiseEmailController.text.trim(),
          accountHolderName: _wiseNameController.text.trim(),
          setAsDefault: false,
        );
      }

      if (result['success'] == true) {
        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)!.paymentMethodSaved,
          );
          widget.onAdded();
          Navigator.pop(context);
        }
      } else {
        throw Exception(
          result['message'] ?? AppLocalizations.of(context)!.failedSavePayment,
        );
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// Card Number Formatter - adds space every 4 digits
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i + 1) % 4 == 0 && i + 1 != text.length) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Expiry Date Formatter - adds / after MM
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');

    if (text.isEmpty) {
      return newValue;
    }

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i == 2) {
        buffer.write('/');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Currency Formatter - auto-inserts decimal: typing 123456 → 1,234.56
class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final cents = int.tryParse(digits) ?? 0;
    final dollars = cents ~/ 100;
    final centsRem = cents % 100;
    final dollarsStr = dollars.toString();
    final buf = StringBuffer();
    for (int i = 0; i < dollarsStr.length; i++) {
      if (i > 0 && (dollarsStr.length - i) % 3 == 0) buf.write(',');
      buf.write(dollarsStr[i]);
    }
    final formatted = '$buf.${centsRem.toString().padLeft(2, '0')}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// IBAN Formatter - adds space every 4 characters
class _IbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '').toUpperCase();
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i + 1) % 4 == 0 && i + 1 != text.length) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}


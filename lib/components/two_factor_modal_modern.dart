import '../services/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/trade_republic_widgets.dart';

class ModernTwoFactorModal extends StatefulWidget {
  final Function(String) onSubmit;
  final VoidCallback onCancel;
  final VoidCallback? onDisable2FA;
  final VoidCallback? onGenerateNew; // NEW: Generate new 2FA code
  final String? twoFactorCode;
  final bool showDisableOption;
  final bool showGenerateOption; // NEW: Show generate new option
  final bool autoSubmit; // Control auto-submit behavior

  const ModernTwoFactorModal({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.onDisable2FA,
    this.onGenerateNew, // NEW: Generate new 2FA callback
    this.twoFactorCode,
    this.showDisableOption = true,
    this.showGenerateOption = true, // NEW: Show generate option by default
    this.autoSubmit = false, // Default: don't auto-submit
  });

  @override
  State<ModernTwoFactorModal> createState() => _ModernTwoFactorModalState();
}

class _ModernTwoFactorModalState extends State<ModernTwoFactorModal> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.twoFactorCode != null) {
      _codeController.text = widget.twoFactorCode!;
      // Only auto-submit if explicitly requested (for login scenarios)
      if (widget.autoSubmit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleSubmit();
        });
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (_codeController.text.trim().length != 8) return;

    setState(() {
      _isLoading = true;
    });

    widget.onSubmit(_codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF000000).withOpacity(0.95)
            : const Color(0xFFFFFFFF).withOpacity(0.98),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Text(
            '2FA Verification',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 20),

          // Icon with gradient effect
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withOpacity(isDark ? 0.08 : 0.06),
                  Colors.blue.withOpacity(isDark ? 0.04 : 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.blue.withOpacity(0.2), width: 1),
            ),
            child: Icon(
              CupertinoIcons.lock_shield,
              size: 48,
              color: Colors.blue,
            ),
          ),

          const SizedBox(height: 24),

          // Description
          Text(
            AppLocalizations.of(context)!.enterEightDigitCode,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Code input
          TradeRepublicTextField.code(
            controller: _codeController,
            hintText: '12345678',
            maxLength: 8,
            onChanged: null,
          ),

          const SizedBox(height: 32),

          // Submit button
          TradeRepublicButton(
            label: AppLocalizations.of(context)!.verify,
            onPressed: _isLoading ? null : _handleSubmit,
            isLoading: _isLoading,
            width: double.infinity,
            height: 56,
          ),

          // Generate New & Disable 2FA options
          if (widget.showGenerateOption && widget.onGenerateNew != null) ...[
            const SizedBox(height: 16),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.generateNewCode,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onGenerateNew?.call();
              },
              isSecondary: true,
              width: double.infinity,
              height: 56,
            ),
          ],

          // Disable 2FA option
          if (widget.showDisableOption && widget.onDisable2FA != null) ...[
            const SizedBox(height: 16),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.disable2FA,
              onPressed: _showDisable2FAConfirmation,
              isDestructive: true,
            ),
          ],

          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
        ],
      ),
    );
  }

  void _showDisable2FAConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Builder(
        builder: (BuildContext context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.disable2FA,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(
                  context,
                )!.areYouSureYouWantToDisableTwofactorAuthent,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.7,
                  ),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                      isSecondary: true,
                      height: 52,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)!.disable,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDisable2FA?.call();
                      },
                      isDestructive: true,
                      height: 52,
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
            ],
          );
        },
      ),
    );
  }
}

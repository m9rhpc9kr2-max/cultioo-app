import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/app_localizations.dart';
import '../services/trade_republic_widgets.dart';

class SecurityVerificationModal extends StatefulWidget {
  final Function(String) onSubmit;
  final VoidCallback onCancel;
  final String? expectedCode;
  final bool isAutoLogin;

  const SecurityVerificationModal({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.expectedCode,
    this.isAutoLogin = false,
  });

  @override
  State<SecurityVerificationModal> createState() =>
      _SecurityVerificationModalState();
}

class _SecurityVerificationModalState extends State<SecurityVerificationModal>
    with TickerProviderStateMixin {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimations();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startAnimations() {
    _slideController.forward();
    _fadeController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (_codeController.text.isEmpty || _codeController.text.length != 8) {
      _showError(AppLocalizations.of(context)!.pleaseEnterAValid8digitCode);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      widget.onSubmit(_codeController.text);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError(AppLocalizations.of(context)!.verificationFailed);
    }
  }

  void _showError(String message) {
    HapticFeedback.lightImpact();
    TopNotification.error(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with animated security icon - kompakter
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                children: [
                  // Animated Security Icon - kleiner
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Icon(
                            CupertinoIcons.lock_shield_fill,
                            size: 30,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  Text(
                    AppLocalizations.of(context)!.securityVerification,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Poppins',
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    widget.isAutoLogin
                        ? AppLocalizations.of(
                            context,
                          )!.enterYour2faCodeToContinue
                        : AppLocalizations.of(
                            context,
                          )!.pleaseVerifyYourIdentityWithYour2faCode,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontFamily: 'Poppins',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2FA Code Input
            TradeRepublicTextField.code(
              controller: _codeController,
              hintText: '12345678',
              maxLength: 8,
              onChanged: null,
            ),

            const SizedBox(height: 20),

            // Verify Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.verify,
              onPressed: _isLoading ? null : _handleSubmit,
              isLoading: _isLoading,
              width: double.infinity,
            ),

            const SizedBox(height: 12),

            // Cancel Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.cancel,
              onPressed: widget.onCancel,
              isSecondary: true,
              width: double.infinity,
            ),

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/api_service.dart';
import '../services/app_localizations.dart';
import '../services/trade_republic_widgets.dart';

class ChangePasswordModal extends StatefulWidget {
  final String accessToken;

  const ChangePasswordModal({super.key, required this.accessToken});

  @override
  State<ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<ChangePasswordModal> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ApiService.changePassword(
        widget.accessToken,
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (result['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop();
          _showSuccessMessage(AppLocalizations.of(context)!.passwordChangedSuccessfully);
        }
      } else {
        String errorMessage = result['message'] ?? AppLocalizations.of(context)!.errorChangingPassword;
        _showErrorMessage(errorMessage);
      }
    } catch (e) {
      String errorMessage = AppLocalizations.of(context)!.anErrorOccurred;

      if (e.toString().contains('current password is incorrect')) {
        errorMessage = AppLocalizations.of(context)!.currentPasswordIsIncorrect;
      } else if (e.toString().contains('password too weak')) {
        errorMessage =
            AppLocalizations.of(context)!.passwordIsTooWeakPleaseChooseAStrongerPass;
      } else if (e.toString().contains('network')) {
        errorMessage = AppLocalizations.of(context)!.networkErrorPleaseCheckYourInternetConnectio;
      }

      _showErrorMessage(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      TopNotification.success(context, message);
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      TopNotification.error(context, message);
    }
  }

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.currentPasswordRequired;
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.newPasswordRequired;
    }
    if (value.length < 6) {
      return AppLocalizations.of(context)!.passwordMustBeAtLeast6CharactersLong;
    }
    if (value == _currentPasswordController.text) {
      return AppLocalizations.of(context)!.newPasswordMustBeDifferentFromCurrentPasswo;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.pleaseConfirmYourNewPassword;
    }
    if (value != _newPasswordController.text) {
      return AppLocalizations.of(context)!.passwordsDoNotMatch;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
          // Header
          Row(
            children: [
              Icon(
                CupertinoIcons.lock_fill,
                color: isDark ? Colors.white : Colors.black,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.changePassword,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Minimal Security Notice
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.black.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.info_circle,
                            size: 18,
                            color: isDark 
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.4),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.chooseAStrongPasswordWithAtLeast6Character,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark 
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Current Password Field
                    _buildPasswordField(
                      controller: _currentPasswordController,
                      label: AppLocalizations.of(context)!.currentPassword,
                      isVisible: _isCurrentPasswordVisible,
                      onToggleVisibility: () {
                        _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
                        setState(() {});
                      },
                      validator: _validateCurrentPassword,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // New Password Field
                    _buildPasswordField(
                      controller: _newPasswordController,
                      label: AppLocalizations.of(context)!.newPassword,
                      isVisible: _isNewPasswordVisible,
                      onToggleVisibility: () {
                        _isNewPasswordVisible = !_isNewPasswordVisible;
                        setState(() {});
                      },
                      validator: _validateNewPassword,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password Field
                    _buildPasswordField(
                      controller: _confirmPasswordController,
                      label: AppLocalizations.of(context)!.confirmNewPassword,
                      isVisible: _isConfirmPasswordVisible,
                      onToggleVisibility: () {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                        setState(() {});
                      },
                      validator: _validateConfirmPassword,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 28),

                    // Change Password Button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.changePassword,
                      onPressed: _isLoading ? null : _changePassword,
                      isLoading: _isLoading,
                      width: double.infinity,
                      height: 52,
                    ),
                    const SizedBox(height: 12),

                    // Cancel Button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)!.cancel,
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      isSecondary: true,
                      width: double.infinity,
                      height: 52,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    required bool isDark,
  }) {
    return TradeRepublicTextField(
      controller: controller,
      hintText: label,
      labelText: label,
      obscureText: !isVisible,
      validator: validator,
      useFormField: true,
      prefixIcon: Icon(
        CupertinoIcons.lock,
        color: isDark 
            ? Colors.white.withOpacity(0.5)
            : Colors.black.withOpacity(0.5),
        size: 20,
      ),
      suffixIcon: IconButton(
        onPressed: onToggleVisibility,
        icon: Icon(
          isVisible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          color: isDark 
              ? Colors.white.withOpacity(0.5)
              : Colors.black.withOpacity(0.5),
          size: 20,
        ),
      ),
    );
  }
}

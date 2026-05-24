import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/app_localizations.dart';
import '../services/trade_republic_widgets.dart';

class AuthModal extends StatefulWidget {
  final Function(String email, String name) onLoginSuccess;

  const AuthModal({super.key, required this.onLoginSuccess});

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> with TickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
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

    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
    // Felder leeren beim Wechsel
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        // Login - verwende Username
        final result = await ApiService.login(
          _usernameController.text.trim(),
          _passwordController.text,
        );

        if (result['success'] && result['user'] != null) {
          // Einstellungen nach erfolgreicher Anmeldung synchronisieren
          await SettingsService.syncAfterLogin();

          widget.onLoginSuccess(
            result['user']['email'], // Verwende immer die E-Mail als Identifier
            result['user']['name'],
          );

          if (mounted) {
            Navigator.of(context).pop();
            _showSuccessMessage(AppLocalizations.of(context)!.successfullyLoggedIn);
          }
        } else {
          _showErrorMessage(AppLocalizations.of(context)!.loginFailed);
        }
      } else {
        // Registration
        final result = await ApiService.register(
          name: _emailController.text
              .trim(), // Use email as name for registration
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (result['success'] && result['user'] != null) {
          // Auto-login after registration
          final loginResult = await ApiService.login(
            _emailController.text.trim(), // Use email as username
            _passwordController.text,
          );

          if (loginResult['success'] && loginResult['user'] != null) {
            // Sync settings
            await SettingsService.syncAfterLogin();

            widget.onLoginSuccess(
              loginResult['user']['email'],
              loginResult['user']['name'],
            );

            if (mounted) {
              Navigator.of(context).pop();
              _showSuccessMessage(
                AppLocalizations.of(context)!.accountSuccessfullyCreatedAndLoggedIn,
              );
            }
          }
        } else {
          _showErrorMessage(AppLocalizations.of(context)!.registrationFailed);
        }
      }
    } catch (e) {
      String errorMessage = AppLocalizations.of(context)!.anErrorOccurred;

      if (e.toString().contains('email already exists')) {
        errorMessage = AppLocalizations.of(context)!.thisEmailAddressIsAlreadyRegistered;
      } else if (e.toString().contains('invalid credentials')) {
        errorMessage = AppLocalizations.of(context)!.invalidEmailOrPassword;
      } else if (e.toString().contains('weak password')) {
        errorMessage = AppLocalizations.of(context)!.passwordIsTooWeak;
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

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.emailIsRequired;
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return AppLocalizations.of(context)!.invalidEmailAddress;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.passwordIsRequired;
    }
    if (value.length < 3) {
      return AppLocalizations.of(context)!.passwordMustBeAtLeast3CharactersLong;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.confirmPasswordIsRequired;
    }
    if (value != _passwordController.text) {
      return AppLocalizations.of(context)!.passwordsDoNotMatch;
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.usernameIsRequired;
    }
    if (value.length < 2) {
      return AppLocalizations.of(context)!.usernameMustBeAtLeast2CharactersLong;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5)),
        child: SlideTransition(
          position: _slideAnimation,
          child: isDesktop
            // Desktop: Centered dialog-style layout
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  Colors.white.withOpacity(0.12),
                                  Colors.white.withOpacity(0.04),
                                ]
                              : [
                                  Colors.black.withOpacity(0.06),
                                  Colors.black.withOpacity(0.01),
                                ],
                        ),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.18)
                              : Colors.black.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: SingleChildScrollView(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withOpacity(0.4)
                                      : Colors.white.withOpacity(0.8),
                                ),
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Form(
                                  key: _formKey,
                                  child: _buildFormContent(isDark),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            // Mobile: Draggable bottom sheet
            : DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            Colors.white.withOpacity(0.12),
                            Colors.white.withOpacity(0.04),
                          ]
                        : [
                            Colors.black.withOpacity(0.06),
                            Colors.black.withOpacity(0.01),
                          ],
                  ),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.18)
                        : Colors.black.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withOpacity(0.4)
                              : Colors.white.withOpacity(0.8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Form(
                            key: _formKey,
                            child: _buildFormContent(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),

        // Title
        Text(
          _isLogin ? AppLocalizations.of(context)!.signIn : AppLocalizations.of(context)!.createAccount,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            letterSpacing: -0.8,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          _isLogin
              ? AppLocalizations.of(context)!.welcomeBackSignInToContinue
              : AppLocalizations.of(context)!.createYourCultiooAccountAndGetStarted,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6D6D80),
            height: 1.5,
            letterSpacing: -0.1,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Username Field (during login) or Email Field (during registration)
        if (_isLogin) ...[
          _buildTextField(
            controller: _usernameController,
            label: AppLocalizations.of(context)!.username,
            icon: CupertinoIcons.person,
            validator: _validateUsername,
            textInputAction: TextInputAction.next,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
        ] else ...[
          _buildTextField(
            controller: _emailController,
            label: AppLocalizations.of(context)!.emailAddress,
            icon: CupertinoIcons.mail,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            textInputAction: TextInputAction.next,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
        ],

        // Password Field
        _buildTextField(
          controller: _passwordController,
          label: AppLocalizations.of(context)!.password,
          icon: CupertinoIcons.lock,
          obscureText: _obscurePassword,
          validator: _validatePassword,
          textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
          isDark: isDark,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              color: const Color(0xFF8E8E93),
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password Field (only during registration)
        if (!_isLogin) ...[
          _buildTextField(
            controller: _confirmPasswordController,
            label: AppLocalizations.of(context)!.confirmPassword,
            icon: CupertinoIcons.lock,
            obscureText: _obscureConfirmPassword,
            validator: _validateConfirmPassword,
            textInputAction: TextInputAction.done,
            isDark: isDark,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                color: const Color(0xFF8E8E93),
              ),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Forgot Password (only during login)
        if (_isLogin) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)!.forgotPassword,
              onPressed: () {
                _showErrorMessage(AppLocalizations.of(context)!.passwordResetWillBeAvailableSoon);
              },
              isSecondary: true,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Submit Button
        TradeRepublicButton(
          label: _isLogin ? AppLocalizations.of(context)!.signIn : AppLocalizations.of(context)!.createAccount,
          onPressed: _isLoading ? null : _submit,
          isLoading: _isLoading,
          width: double.infinity,
          height: 56,
        ),
        const SizedBox(height: 24),

        // Toggle Button
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _isLogin
                    ? AppLocalizations.of(context)!.dontHaveAnAccount
                    : AppLocalizations.of(context)!.alreadyHaveAnAccount,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6D6D80),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            TradeRepublicButton(
              label: _isLogin ? AppLocalizations.of(context)!.createAccount : AppLocalizations.of(context)!.signIn,
              onPressed: _isLoading ? null : _toggleMode,
              isSecondary: true,
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TradeRepublicTextField(
      controller: controller,
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6D6D80),
      ),
      suffixIcon: suffixIcon,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      useFormField: true,
      onSubmitted: textInputAction == TextInputAction.done
          ? (_) => _submit()
          : null,
    );
  }
}

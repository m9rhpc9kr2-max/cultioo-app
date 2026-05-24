import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'cultioo_desktop_layout.dart';
import 'pointer_safe.dart';
import 'trade_republic_theme.dart';
import 'trade_republic_button.dart';

/// Trade Republic styled text field — normalized, borderless, dark/light mode
///
/// Variants:
/// - `TradeRepublicTextField(...)` — standard text field
/// - `TradeRepublicTextField.withLabel(...)` — text field with external label above
/// - `TradeRepublicTextField.search(...)` — search field with search icon
/// - `TradeRepublicTextField.password(...)` — password field with visibility toggle
/// - `TradeRepublicTextField.multiline(...)` — multiline / message field
/// - `TradeRepublicTextField.currency(...)` — large currency input
/// - `TradeRepublicTextField.code(...)` — verification code input (centered, spaced)
class TradeRepublicTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool showVisibilityToggle;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final bool filled;
  final Color? fillColor;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final EdgeInsets? contentPadding;
  final bool isDense;
  final String? counterText;
  final bool useFormField;
  final String? initialValue;
  final String? prefixText;
  final TextStyle? prefixStyle;
  final String? suffixText;
  final TextStyle? suffixStyle;

  const TradeRepublicTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.showVisibilityToggle = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.focusNode,
    this.filled = true,
    this.fillColor,
    this.style,
    this.hintStyle,
    this.contentPadding,
    this.isDense = false,
    this.counterText,
    this.useFormField = false,
    this.initialValue,
    this.prefixText,
    this.prefixStyle,
    this.suffixText,
    this.suffixStyle,
  });

  /// Text field with a label displayed above
  factory TradeRepublicTextField.withLabel({
    Key? key,
    required String label,
    TextEditingController? controller,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    bool showVisibilityToggle = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLines = 1,
    int? maxLength,
    bool autofocus = false,
    bool enabled = true,
    bool readOnly = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    FormFieldValidator<String>? validator,
    FocusNode? focusNode,
    Color? fillColor,
    bool useFormField = false,
  }) {
    return _TradeRepublicLabeledTextField(
      key: key,
      label: label,
      controller: controller,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      obscureText: obscureText,
      showVisibilityToggle: showVisibilityToggle,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      maxLength: maxLength,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      validator: validator,
      focusNode: focusNode,
      fillColor: fillColor,
      useFormField: useFormField,
    );
  }

  /// Search field with search icon prefix
  factory TradeRepublicTextField.search({
    Key? key,
    TextEditingController? controller,
    String hintText = 'Search...',
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    return TradeRepublicTextField(
      key: key,
      controller: controller,
      hintText: hintText,
      onChanged: onChanged,
      focusNode: focusNode,
      autofocus: autofocus,
      prefixIcon: const Icon(CupertinoIcons.search),
      textInputAction: TextInputAction.search,
    );
  }

  /// Password field with visibility toggle
  factory TradeRepublicTextField.password({
    Key? key,
    TextEditingController? controller,
    String hintText = 'Password',
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
    bool autofocus = false,
    FormFieldValidator<String>? validator,
    Widget? prefixIcon,
    bool useFormField = false,
  }) {
    return TradeRepublicTextField(
      key: key,
      controller: controller,
      hintText: hintText,
      obscureText: true,
      showVisibilityToggle: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      validator: validator,
      prefixIcon: prefixIcon,
      useFormField: useFormField,
    );
  }

  /// Multiline / message input field
  factory TradeRepublicTextField.multiline({
    Key? key,
    TextEditingController? controller,
    String? hintText,
    int? maxLines,
    int? minLines,
    int? maxLength,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return TradeRepublicTextField(
      key: key,
      controller: controller,
      hintText: hintText,
      maxLines: maxLines,
      minLines: minLines ?? 3,
      maxLength: maxLength,
      onChanged: onChanged,
      focusNode: focusNode,
      textCapitalization: textCapitalization,
      contentPadding: const EdgeInsets.all(18),
    );
  }

  /// Large currency / price input
  factory TradeRepublicTextField.currency({
    Key? key,
    TextEditingController? controller,
    String hintText = '0,00',
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
    FocusNode? focusNode,
    bool autofocus = false,
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TradeRepublicTextField(
      key: key,
      controller: controller,
      hintText: hintText,
      onChanged: onChanged,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: inputFormatters,
      textAlign: TextAlign.center,
      suffixIcon: suffixIcon,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      hintStyle: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
      filled: false,
    );
  }

  /// Verification code input (centered, letter-spaced)
  factory TradeRepublicTextField.code({
    Key? key,
    TextEditingController? controller,
    String hintText = '• • • • • •',
    int maxLength = 8,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
    bool autofocus = true,
  }) {
    return TradeRepublicTextField(
      key: key,
      controller: controller,
      hintText: hintText,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      counterText: '',
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 8,
      ),
      hintStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 8,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
    );
  }

  @override
  State<TradeRepublicTextField> createState() => _TradeRepublicTextFieldState();
}

class _TradeRepublicTextFieldState extends State<TradeRepublicTextField>
    with SingleTickerProviderStateMixin {
  late bool _obscureText;
  FocusNode? _internalFocusNode;
  AnimationController? _focusController;
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    
    // Only create internal focus node if one isn't provided
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }
    
    // Initialize animations - minimalistic, no scale
    _focusController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Listen to focus changes
    (widget.focusNode ?? _internalFocusNode)?.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final focusNode = widget.focusNode ?? _internalFocusNode;
    if (focusNode == null) return;
    
    setState(() {
      _isFocused = focusNode.hasFocus;
      if (_isFocused) {
        _focusController?.forward();
      } else {
        _focusController?.reverse();
      }
    });
  }

  @override
  void didUpdateWidget(TradeRepublicTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync internal obscure state when parent changes the prop
    if (oldWidget.obscureText != widget.obscureText) {
      _obscureText = widget.obscureText;
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _internalFocusNode)?.removeListener(_onFocusChange);
    _internalFocusNode?.dispose();
    _focusController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = TradeRepublicTheme.isLight(context);
    final defaultTextColor =
        isLight ? Colors.black : Colors.white;
    final defaultFillColor = widget.fillColor ??
        (isLight ? defaultTextColor.withValues(alpha: 0.05) : Colors.transparent);
    final defaultIconColor = defaultTextColor.withValues(alpha: 0.5);

    TextStyle effectiveStyle =
        widget.style ?? TradeRepublicTheme.inputStyle(context);
    TextStyle effectiveHintStyle = widget.hintStyle ??
        TradeRepublicTheme.inputHintStyle(context).copyWith(
          fontSize: effectiveStyle.fontSize,
          fontWeight: effectiveStyle.fontWeight,
          letterSpacing: effectiveStyle.letterSpacing,
        );

    if (CultiooDesktopLayout.isDesktopPlatform) {
      final fs = effectiveStyle.fontSize;
      if (fs != null && fs >= 22) {
        effectiveStyle = effectiveStyle.copyWith(
          fontSize: (fs * 0.72).clamp(18.0, 26.0),
        );
      }
      final hf = effectiveHintStyle.fontSize;
      if (hf != null && hf >= 22) {
        effectiveHintStyle = effectiveHintStyle.copyWith(
          fontSize: (hf * 0.72).clamp(18.0, 26.0),
        );
      }
    }

    const multilinePad = EdgeInsets.all(18);
    const currencyPad = EdgeInsets.symmetric(vertical: 20);

    EdgeInsets effectivePadding = widget.contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 14.0,
        );
    if (CultiooDesktopLayout.isDesktopPlatform &&
        widget.contentPadding == multilinePad) {
      effectivePadding = const EdgeInsets.all(12);
    } else if (CultiooDesktopLayout.isDesktopPlatform &&
        widget.contentPadding == currencyPad) {
      effectivePadding = const EdgeInsets.symmetric(vertical: 14);
    }

    // Build suffix icon (may include visibility toggle)
    Widget? effectiveSuffix = widget.suffixIcon;
    final iconBtnSize = 20.0;
    if (widget.showVisibilityToggle) {
      effectiveSuffix = TradeRepublicButton.icon(
        size: (iconBtnSize + 16).clamp(32.0, 40.0),
        isSecondary: true,
        foregroundColor: defaultIconColor,
        icon: Icon(
          _obscureText ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill,
          size: iconBtnSize,
        ),
        onPressed: () => setState(() => _obscureText = !_obscureText),
      );
    }

    // Style prefix icon with correct color
    Widget? effectivePrefix = widget.prefixIcon;
    if (effectivePrefix != null && effectivePrefix is Icon) {
      effectivePrefix = Icon(
        (effectivePrefix).icon,
        size: (effectivePrefix).size ?? 20.0,
        color: (effectivePrefix).color ?? defaultIconColor,
      );
    }

    // Let icons share the full input height so they stay vertically centered
    // with the text at any font size / field height.
    final iconSlotConstraints = BoxConstraints(
      minWidth: 40.0,
      minHeight: 0,
      maxHeight: double.infinity,
    );
    // Icons should not be wrapped in Center() for proper alignment
    // InputDecoration handles icon positioning via prefixIcon/suffixIcon

    final decoration = InputDecoration(
      hintText: widget.hintText,
      hintStyle: effectiveHintStyle,
      filled: widget.filled,
      fillColor: defaultFillColor,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: effectivePadding,
      isDense: widget.isDense ||
          (CultiooDesktopLayout.isDesktopPlatform &&
              widget.contentPadding == null),
      counterText: widget.counterText,
      prefixIcon: effectivePrefix,
      prefixIconConstraints: iconSlotConstraints,
      prefixIconColor: defaultIconColor,
      prefixText: widget.prefixText,
      prefixStyle: widget.prefixStyle,
      suffixIcon: effectiveSuffix,
      suffixIconConstraints: iconSlotConstraints,
      suffixIconColor: defaultIconColor,
      suffixText: widget.suffixText,
      suffixStyle: widget.suffixStyle,
    );

    // Minimal animated container - only border transitions, no shadows
    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.filled
            ? defaultFillColor
            : Colors.transparent,
        borderRadius: TradeRepublicTheme.inputSurfaceBorderRadius,
        border: Border.all(
          color: _isFocused
              ? (isLight ? Colors.black : Colors.white).withValues(alpha: 0.4)
              : _isHovered
                  ? (isLight ? Colors.black : Colors.white).withValues(alpha: 0.2)
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: _buildTextField(decoration, effectiveStyle, _obscureText),
    );
    // Only use MouseRegion on desktop platforms
    if (CultiooDesktopLayout.isDesktopPlatform) {
      return MouseRegion(
        cursor: widget.enabled && !widget.readOnly
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onEnter: (_) {
          scheduleAfterPointerUpdate(() {
            if (!mounted || _isHovered) return;
            setState(() => _isHovered = true);
          });
        },
        onExit: (_) {
          scheduleAfterPointerUpdate(() {
            if (!mounted || !_isHovered) return;
            setState(() => _isHovered = false);
          });
        },
        child: field,
      );
    }
    return field;
  }

  Widget _buildTextField(
    InputDecoration decoration,
    TextStyle effectiveStyle,
    bool obscureText,
  ) {
    final focusNode = widget.focusNode ?? _internalFocusNode;

    final singleLine = (widget.obscureText ? 1 : (widget.maxLines ?? 1)) == 1 &&
        (widget.minLines ?? 1) <= 1;
    // Always center text vertically for consistency across platforms
    final resolvedTextAlignVertical = widget.textAlignVertical ??
        (singleLine ? TextAlignVertical.center : TextAlignVertical.top);

    // Default: single-line fields AND numeric/phone keyboards get the blue done (✓)
    // button on iOS. Multiline text fields keep the newline key.
    // Numeric keyboard types (number, phone, datetime) are always effectively
    // single-line and get done, regardless of maxLines.
    final isNumericKeyboard = const [2, 3, 4] // number, phone, datetime
        .contains(widget.keyboardType?.index);
    final effectiveAction = widget.textInputAction ??
        ((widget.maxLines == 1 || isNumericKeyboard)
            ? TextInputAction.done
            : TextInputAction.newline);

    return widget.useFormField
        ? TextFormField(
            controller: widget.controller,
            initialValue: widget.controller == null ? widget.initialValue : null,
            obscureText: obscureText,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            textAlign: widget.textAlign,
            textAlignVertical: resolvedTextAlignVertical,
            textInputAction: effectiveAction,
            textCapitalization: widget.textCapitalization,
            focusNode: focusNode,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onSubmitted,
            validator: widget.validator,
            style: effectiveStyle,
            decoration: decoration.copyWith(
              filled: false,
              fillColor: Colors.transparent,
            ),
          )
        : TextField(
            controller: widget.controller,
            obscureText: obscureText,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            textAlign: widget.textAlign,
            textAlignVertical: resolvedTextAlignVertical,
            textInputAction: effectiveAction,
            textCapitalization: widget.textCapitalization,
            focusNode: focusNode,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: effectiveStyle,
            decoration: decoration.copyWith(
              filled: false,
              fillColor: Colors.transparent,
            ),
          );
  }
}

/// Internal: Text field with a label above
class _TradeRepublicLabeledTextField extends TradeRepublicTextField {
  final String label;

  const _TradeRepublicLabeledTextField({
    super.key,
    required this.label,
    super.controller,
    super.hintText,
    super.prefixIcon,
    super.suffixIcon,
    super.obscureText,
    super.showVisibilityToggle,
    super.keyboardType,
    super.inputFormatters,
    super.maxLines,
    super.maxLength,
    super.autofocus,
    super.enabled,
    super.readOnly,
    super.textInputAction,
    super.onChanged,
    super.onSubmitted,
    super.validator,
    super.focusNode,
    super.fillColor,
    super.useFormField,
  });

  @override
  State<TradeRepublicTextField> createState() =>
      _TradeRepublicLabeledTextFieldState();
}

class _TradeRepublicLabeledTextFieldState
    extends _TradeRepublicTextFieldState {
  @override
  Widget build(BuildContext context) {
    final label = (widget as _TradeRepublicLabeledTextField).label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 4,
            bottom: CultiooDesktopLayout.isDesktopPlatform ? 6 : 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: CultiooDesktopLayout.isDesktopPlatform ? 11 : 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: TradeRepublicTheme.hintColor(context, opacity: 0.6),
            ),
          ),
        ),
        super.build(context),
      ],
    );
  }
}

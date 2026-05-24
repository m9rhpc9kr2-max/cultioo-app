import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared card shell – ISO/IEC 7810 ID-1 aspect ratio, matte black
// ─────────────────────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  final Widget child;
  final CustomPainter patternPainter;
  final bool isDark;

  const _CardShell({
    required this.child,
    required this.patternPainter,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.7 : 0.35),
              blurRadius: 30,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.0),
              blurRadius: 0,
              spreadRadius: 0,
              offset: Offset.zero,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Subtle texture / pattern ───────────────────────────────────
              CustomPaint(painter: patternPainter),

              // ── Top-left corner radial glow ────────────────────────────────
              Positioned(
                left: -60,
                top: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // ── Diagonal shimmer band ──────────────────────────────────────
              CustomPaint(painter: _ShimmerBandPainter()),

              // ── Content ────────────────────────────────────────────────────
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Credit / Debit card
// ─────────────────────────────────────────────────────────────────────────────

class CreditCardWidget extends StatelessWidget {
  final String brand;
  final String last4;
  final String expMonth;
  final String expYear;
  final bool isDefault;
  final String cardholderName;

  const CreditCardWidget({
    super.key,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    this.isDefault = false,
    this.cardholderName = '',
  });

  String get _brandLabel {
    switch (brand.toLowerCase()) {
      case 'visa':               return 'VISA';
      case 'mastercard':         return 'MASTERCARD';
      case 'amex':
      case 'american_express':   return 'AMEX';
      case 'discover':           return 'DISCOVER';
      case 'unionpay':           return 'UNIONPAY';
      case 'jcb':                return 'JCB';
      case 'diners':
      case 'diners_club':        return 'DINERS';
      default:                   return brand.isEmpty ? 'CARD' : brand.toUpperCase();
    }
  }

  String get _expiry {
    final mm = expMonth.toString().padLeft(2, '0');
    final raw = expYear.toString();
    final yy = raw.length > 2 ? raw.substring(raw.length - 2) : raw.padLeft(2, '0');
    return '$mm/$yy';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _CardShell(
      isDark: isDark,
      patternPainter: _CrosshatchPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: chip + default badge ─────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ChipWidget(),
                if (isDefault)
                  _CardBadge(label: 'DEFAULT')
                else
                  const SizedBox.shrink(),
              ],
            ),

            const Spacer(),

            // ── Card number ───────────────────────────────────────────────
            _CardNumber(last4: last4),

            const SizedBox(height: 16),

            // ── Bottom row ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (cardholderName.isNotEmpty) ...[
                  Expanded(
                    child: _LabeledValue(
                      label: 'CARDHOLDER',
                      value: cardholderName.toUpperCase(),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _LabeledValue(label: 'EXPIRES', value: _expiry),
                ] else ...[
                  _LabeledValue(label: 'EXPIRES', value: _expiry),
                  const Spacer(),
                ],
                const SizedBox(width: 16),
                Text(
                  _brandLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bank account card – ACH / SEPA / Wire
// ─────────────────────────────────────────────────────────────────────────────

class BankAccountWidget extends StatelessWidget {
  final String type; // 'ach' | 'sepa' | 'wire'
  final String maskedNumber;
  final String accountHolderName;
  final String? routingOrSwift;
  final bool isDefault;

  const BankAccountWidget({
    super.key,
    required this.type,
    required this.maskedNumber,
    required this.accountHolderName,
    this.routingOrSwift,
    this.isDefault = false,
  });

  String get _typeLabel {
    switch (type.toLowerCase()) {
      case 'sepa':  return 'SEPA';
      case 'ach':   return 'ACH';
      case 'wire':  return 'WIRE TRANSFER';
      default:      return type.toUpperCase();
    }
  }

  String get _routingLabel {
    return type.toLowerCase() == 'wire' ? 'SWIFT / BIC' : 'ROUTING';
  }

  IconData get _icon {
    switch (type.toLowerCase()) {
      case 'sepa':  return CupertinoIcons.building_2_fill;
      case 'wire':  return CupertinoIcons.arrow_right_arrow_left_circle_fill;
      default:      return CupertinoIcons.creditcard_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _CardShell(
      isDark: isDark,
      patternPainter: _DotGridPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: bank icon + type + default ───────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bank icon (instead of chip)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    _icon,
                    color: Colors.white.withValues(alpha: 0.55),
                    size: 16,
                  ),
                ),
                Row(
                  children: [
                    if (isDefault) ...[
                      _CardBadge(label: 'DEFAULT'),
                      const SizedBox(width: 6),
                    ],
                    _CardBadge(label: _typeLabel, filled: true),
                  ],
                ),
              ],
            ),

            const Spacer(),

            // ── Masked account number ─────────────────────────────────────
            _CardNumber(last4: maskedNumber),

            const SizedBox(height: 16),

            // ── Bottom row ────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _LabeledValue(
                    label: 'ACCOUNT HOLDER',
                    value: accountHolderName.isEmpty
                        ? '–'
                        : accountHolderName.toUpperCase(),
                    maxLines: 1,
                  ),
                ),
                if (routingOrSwift != null && routingOrSwift!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _LabeledValue(
                    label: _routingLabel,
                    value: routingOrSwift!,
                    align: TextAlign.right,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared card sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CardNumber extends StatelessWidget {
  final String last4;
  const _CardNumber({required this.last4});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          height: 1,
        ),
        children: [
          TextSpan(
            text: '••••  ••••  ••••  ',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w300,
              letterSpacing: 3.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          TextSpan(
            text: last4.isEmpty ? '••••' : last4,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 3.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;
  final TextAlign align;

  const _LabeledValue({
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: align,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: align,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _CardBadge extends StatelessWidget {
  final String label;
  final bool filled;
  const _CardBadge({required this.label, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: filled
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: filled
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.5,
              ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: filled ? 0.75 : 0.50),
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          height: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gold EMV chip
// ─────────────────────────────────────────────────────────────────────────────

class _ChipWidget extends StatelessWidget {
  const _ChipWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD4AF37), Color(0xFFEECC60), Color(0xFFB8962E)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(painter: _ChipLinePainter()),
    );
  }
}

class _ChipLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFB8962E).withValues(alpha: 0.6)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), p);
    canvas.drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h), p);
    canvas.drawLine(Offset(0, h * 0.28), Offset(w * 0.35, h * 0.28), p);
    canvas.drawLine(Offset(0, h * 0.72), Offset(w * 0.35, h * 0.72), p);
    canvas.drawLine(Offset(w * 0.65, h * 0.28), Offset(w, h * 0.28), p);
    canvas.drawLine(Offset(w * 0.65, h * 0.72), Offset(w, h * 0.72), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pattern painters
// ─────────────────────────────────────────────────────────────────────────────

/// Fine crosshatch (45° + 135°) — used on credit cards
class _CrosshatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    const spacing = 14.0;
    final extent = size.width + size.height;

    // 45° lines
    for (double i = -size.height; i < extent; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), p);
    }
    // 135° lines
    for (double i = 0; i < extent; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i - size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

/// Dot grid — used on bank account cards
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    const spacing = 18.0;
    const radius = 1.0;

    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

/// Diagonal shimmer band — shared
class _ShimmerBandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shader = LinearGradient(
      begin: const Alignment(-1.0, -1.0),
      end: const Alignment(1.0, 1.0),
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.05),
        Colors.white.withValues(alpha: 0.0),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.50, 0.65, 1.0],
    ).createShader(rect);

    canvas.drawRect(
      rect,
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Trade Republic style monochrome segmented period selector.
///
/// Pure widgets — a rounded track with one solid pill marking the active
/// option. Auto-shortens human-readable period names ("7 Days" → "7d").
class TradeRepublicPeriodSegmented extends StatelessWidget {
  final bool isLight;
  final String selected;
  final List<String> options;
  final ValueChanged<String> onSelect;

  const TradeRepublicPeriodSegmented({
    super.key,
    required this.isLight,
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  String _shortLabel(String input) {
    return input
        .replaceAll(RegExp(r'\s*(Hours|Stunden)$'), 'h')
        .replaceAll(RegExp(r'\s*(Days|Tage)$'), 'd')
        .replaceAll(RegExp(r'\s*(Months|Monate)$'), 'm')
        .replaceAll(RegExp(r'\s*(Month|Monat)$'), 'm')
        .replaceAll(RegExp(r'\s*(Years|Jahre)$'), 'y')
        .replaceAll(RegExp(r'\s*(Year|Jahr)$'), 'y');
  }

  @override
  Widget build(BuildContext context) {
    final accent = isLight ? Colors.black : Colors.white;
    final inverse = isLight ? Colors.white : Colors.black;
    final track = accent.withOpacity(0.06);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(opt);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _shortLabel(opt),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isSelected ? inverse : accent.withOpacity(0.55),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Minimalist widget-only bar chart, Trade Republic style.
///
/// - Pure Flutter widgets (Row + AnimatedContainer), no CustomPainter
/// - Monochrome accent that follows the active theme
/// - Tap any bar to highlight it and reveal its value above the chart
/// - Densifies bar count automatically: shows up to ~50 bars and aggregates
///   anything bigger so 1-year (365 points) still renders clearly
/// - Robust against data length changes (selection auto-clears when dataset
///   shrinks, so switching periods never throws RangeError)
class TradeRepublicBarChart extends StatefulWidget {
  final List<double> data;
  final bool isLight;
  final int maxBars;

  /// Optional value formatter for the readout (e.g. currency formatter).
  final String Function(double)? valueFormatter;

  /// When true the latest bar is highlighted with full accent, the others
  /// are dimmed. When false all bars share the same accent.
  final bool highlightLatest;

  const TradeRepublicBarChart({
    super.key,
    required this.data,
    required this.isLight,
    this.maxBars = 50,
    this.valueFormatter,
    this.highlightLatest = true,
  });

  @override
  State<TradeRepublicBarChart> createState() => _TradeRepublicBarChartState();
}

class _TradeRepublicBarChartState extends State<TradeRepublicBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant TradeRepublicBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset highlight when the dataset changes shape so the readout is never
    // out-of-sync with the visible bars.
    if (oldWidget.data.length != widget.data.length) {
      _selected = null;
    }
  }

  /// Down-sample [src] into at most [target] buckets by averaging.
  List<double> _aggregate(List<double> src, int target) {
    if (src.length <= target) return src;
    final bucket = src.length / target;
    final out = <double>[];
    for (int i = 0; i < target; i++) {
      final start = (i * bucket).floor();
      final end = ((i + 1) * bucket).floor().clamp(start + 1, src.length);
      double sum = 0;
      for (int j = start; j < end; j++) {
        sum += src[j];
      }
      out.add(sum / (end - start));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isLight ? Colors.black : Colors.white;
    final dim = accent.withOpacity(0.18);

    if (widget.data.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(color: accent.withOpacity(0.4), fontSize: 13),
        ),
      );
    }

    final bars = _aggregate(widget.data, widget.maxBars);
    final maxVal = bars.reduce((a, b) => a > b ? a : b);
    // Defensive clamp: the dataset can change length between builds.
    final selectedIdx =
        (_selected != null && _selected! < bars.length) ? _selected : null;
    final selectedValue =
        selectedIdx != null ? bars[selectedIdx] : bars.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Value readout: latest by default, selected bar value when tapped.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.valueFormatter != null
                  ? widget.valueFormatter!(selectedValue)
                  : selectedValue.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: accent,
              ),
            ),
            if (selectedIdx != null)
              GestureDetector(
                onTap: () => setState(() => _selected = null),
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 16,
                  color: dim,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Bars area.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Subtle baseline rule.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 0.5,
                      color: accent.withOpacity(0.08),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(bars.length, (i) {
                      final isSelected = i == selectedIdx;
                      final isLatest = i == bars.length - 1;
                      final factor =
                          (maxVal == 0 ? 0.0 : bars[i] / maxVal)
                              .clamp(0.04, 1.0);
                      final color = isSelected
                          ? accent
                          : (widget.highlightLatest && isLatest
                              ? accent
                              : dim);
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = i);
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 1.5),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                height: constraints.maxHeight * factor,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

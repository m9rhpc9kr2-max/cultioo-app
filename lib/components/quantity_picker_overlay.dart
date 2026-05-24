import 'package:flutter/material.dart';
import 'dart:ui';

import '../services/trade_republic_widgets.dart';

Widget buildQuantityPickerOverlay({
  required BuildContext context,
  required Offset position,
  required Size buttonSize,
  required bool isVisible,
  required ScrollController scrollController,
  required int quantity,
  required Function(int) onQuantityChanged,
  required VoidCallback onHide,
}) {
  final overlayHeight = 200.0;
  final overlayWidth = 80.0;
  
  // Position the overlay to slide up from the quantity selector
  final overlayLeft = position.dx + (buttonSize.width / 2) - (overlayWidth / 2);
  final overlayBottom = MediaQuery.of(context).size.height - position.dy - buttonSize.height;
  
  return AnimatedPositioned(
    duration: Duration(milliseconds: isVisible ? 500 : 300),
    curve: isVisible ? Curves.easeOutCubic : Curves.easeInCubic,
    left: overlayLeft,
    bottom: overlayBottom + (isVisible ? 0 : -(overlayHeight + 50)),
    child: Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        duration: Duration(milliseconds: isVisible ? 500 : 300),
        tween: Tween(begin: 0.0, end: isVisible ? 1.0 : 0.0),
        curve: isVisible ? Curves.easeOutCubic : Curves.easeInCubic,
        builder: (context, value, child) {
          final opacityValue = value.clamp(0.0, 1.0);
          
          return Opacity(
            opacity: opacityValue,
            child: Container(
              width: overlayWidth,
              height: overlayHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.01)
                          : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Stack(
                      children: [
                        // Top gradient
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Theme.of(context).brightness == Brightness.dark
                                      ? Colors.black.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.2),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Bottom gradient
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Theme.of(context).brightness == Brightness.dark
                                      ? Colors.black.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.2),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Center indicator line
                        Positioned(
                          top: overlayHeight / 2 - 1,
                          left: 8,
                          right: 8,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                        ),
                        // Quantity selector list
                        GestureDetector(
                          onPanUpdate: (details) {
                            final scrollDelta = details.delta.dy * -2.0;
                            final newOffset = (scrollController.offset + scrollDelta).clamp(
                              0.0,
                              scrollController.position.maxScrollExtent,
                            );
                            scrollController.jumpTo(newOffset);
                          },
                          onPanEnd: (details) {
                            final velocity = details.velocity.pixelsPerSecond.dy;
                            final itemHeight = 50.0;
                            
                            if (velocity.abs() > 100) {
                              final momentumDistance = velocity * -0.3;
                              var targetOffset = (scrollController.offset + momentumDistance).clamp(
                                0.0,
                                scrollController.position.maxScrollExtent,
                              );
                              
                              final nearestItemIndex = (targetOffset / itemHeight).round();
                              targetOffset = nearestItemIndex * itemHeight;
                              targetOffset = targetOffset.clamp(0.0, scrollController.position.maxScrollExtent);
                              
                              scrollController.animateTo(
                                targetOffset,
                                duration: Duration(milliseconds: (velocity.abs() / 10).clamp(300, 800).round()),
                                curve: Curves.decelerate,
                              );
                            } else {
                              final nearestItemIndex = (scrollController.offset / itemHeight).round();
                              final targetOffset = (nearestItemIndex * itemHeight).clamp(
                                0.0,
                                scrollController.position.maxScrollExtent,
                              );
                              
                              scrollController.animateTo(
                                targetOffset,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: 100,
                            itemExtent: 50.0,
                            physics: const NeverScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            itemBuilder: (context, index) {
                              final itemQuantity = index + 1;
                              final isSelected = itemQuantity == quantity;
                              
                              return GestureDetector(
                                onTap: () {
                                  onQuantityChanged(itemQuantity);
                                  onHide();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? TradeRepublicTheme
                                            .selectionContainerBackground(context)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Center(
                                    child: Text(
                                      itemQuantity.toString(),
                                      style: TextStyle(
                                        fontSize: isSelected ? 22 : 18,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? TradeRepublicTheme
                                                .selectionContainerForeground(context)
                                            : (Theme.of(context).brightness == Brightness.dark
                                                ? Colors.white.withOpacity(0.85)
                                                : Colors.black.withOpacity(0.85)),
                                        shadows: const [],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

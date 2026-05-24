import 'package:flutter/material.dart';

import 'trade_republic_bottom_sheet.dart';

/// Desktop right column: stacked bottom sheets with a tab strip when several are open.
class CultiooDesktopSheetNavigator {
  CultiooDesktopSheetNavigator._();

  static Widget buildPanelHost({
    required double width,
    required bool isDark,
  }) =>
      TradeRepublicBottomSheet.buildDesktopPanelHost(
        width: width,
        isDark: isDark,
      );
}

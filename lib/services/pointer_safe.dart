import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Defers work until after the current pointer/mouse-tracker batch.
///
/// Synchronous `setState` from [MouseRegion.onEnter]/[MouseRegion.onExit] can
/// trip `!_debugDuringDeviceUpdate` in `mouse_tracker.dart` on desktop.
void scheduleAfterPointerUpdate(void Function() fn) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    scheduleMicrotask(fn);
  });
}

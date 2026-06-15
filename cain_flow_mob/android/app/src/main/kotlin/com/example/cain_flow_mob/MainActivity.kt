package com.example.cain_flow_mob

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Future platform-channel wiring can delegate to these helpers.
    internal fun startCainFlowForegroundService() {
        CainFlowForegroundService.start(this)
    }

    internal fun stopCainFlowForegroundService() {
        CainFlowForegroundService.stop(this)
    }
}

package com.invitationstudio.invitation_studio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        VideoExportPlugin(applicationContext).attach(
            MethodChannel(messenger, VideoExportPlugin.CHANNEL),
        )
        VideoMediaPlugin(applicationContext).attach(
            MethodChannel(messenger, VideoMediaPlugin.CHANNEL),
        )
    }
}

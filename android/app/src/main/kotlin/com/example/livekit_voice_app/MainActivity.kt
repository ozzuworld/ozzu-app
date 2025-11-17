package com.example.livekit_voice_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tailscale.ipn.App as TailscaleApp
import com.tailscale.ipn.IPNActivity

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.livekitvoiceapp/tailscale"
    private var tailscaleApp: TailscaleApp? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val loginServer = call.argument<String>("loginServer")
                    val authKey = call.argument<String>("authKey")

                    if (loginServer != null && authKey != null) {
                        connectTailscale(loginServer, authKey, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing loginServer or authKey", null)
                    }
                }
                "disconnect" -> {
                    disconnectTailscale(result)
                }
                "getStatus" -> {
                    getTailscaleStatus(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun connectTailscale(loginServer: String, authKey: String, result: MethodChannel.Result) {
        try {
            // Initialize Tailscale app context if needed
            if (tailscaleApp == null) {
                tailscaleApp = TailscaleApp.get()
            }

            // Start Tailscale with custom control server (Headscale) and auth key
            val intent = Intent(this, IPNActivity::class.java).apply {
                putExtra("login-server", loginServer)
                putExtra("authkey", authKey)
            }
            startActivity(intent)

            result.success(mapOf(
                "status" to "connecting",
                "message" to "Tailscale connecting to $loginServer"
            ))
        } catch (e: Exception) {
            result.error("CONNECTION_ERROR", e.message, null)
        }
    }

    private fun disconnectTailscale(result: MethodChannel.Result) {
        try {
            tailscaleApp?.let { app ->
                // Disconnect logic here
                result.success(mapOf("status" to "disconnected"))
            } ?: result.error("NOT_INITIALIZED", "Tailscale not initialized", null)
        } catch (e: Exception) {
            result.error("DISCONNECTION_ERROR", e.message, null)
        }
    }

    private fun getTailscaleStatus(result: MethodChannel.Result) {
        try {
            // Get current Tailscale status
            result.success(mapOf(
                "connected" to false,
                "ipAddress" to ""
            ))
        } catch (e: Exception) {
            result.error("STATUS_ERROR", e.message, null)
        }
    }
}

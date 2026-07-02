package com.nevark.foodapp

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val reassertEdgeToEdge = Runnable { applyEdgeToEdge() }

    // The window nav bar color stays fully transparent — the visible gradient
    // scrim is drawn by Flutter (MaterialApp.builder in lib/main.dart), which
    // OEM ROMs cannot override. Dart still pushes this via the settings
    // channel so a style change re-triggers the edge-to-edge re-assert.
    private var navBarScrim: Int = Color.TRANSPARENT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge()
    }

    override fun onPostResume() {
        super.onPostResume()
        // Runs after Flutter's PlatformPlugin.updateSystemUiOverlays(), which
        // resets the decor flags to Flutter's default (not edge-to-edge).
        scheduleEdgeToEdgeReassert()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) scheduleEdgeToEdgeReassert()
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        scheduleEdgeToEdgeReassert()
    }

    // ColorOS (and other OEM ROMs) force an opaque black nav bar once shortly
    // after launch for apps not on the OEM's own adaptation list, clobbering
    // both the theme attributes and Flutter's SystemChrome styling. The forced
    // state is not re-applied afterwards, so re-asserting after each of these
    // lifecycle moments (plus a delayed backup pass) wins permanently.
    private fun scheduleEdgeToEdgeReassert() {
        if (Build.VERSION.SDK_INT >= 35) return
        val decor = window.decorView
        decor.removeCallbacks(reassertEdgeToEdge)
        decor.post(reassertEdgeToEdge)
        decor.postDelayed(reassertEdgeToEdge, 500)
        decor.postDelayed(reassertEdgeToEdge, 1500)
    }

    private fun applyEdgeToEdge() {
        // Android 15+ enforces edge-to-edge itself (targetSdk 35+) and
        // deprecates the window color setters, so only run this on older
        // versions.
        if (Build.VERSION.SDK_INT >= 35) return
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // The legacy layout flags are what actually keep the content laid out
        // behind the nav bar here — WindowCompat alone was not honored on
        // ColorOS (verified on OnePlus / Android 14).
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            window.decorView.systemUiVisibility or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = navBarScrim
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nevark_foods/settings"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "setNavBarScrim" -> {
                    navBarScrim = (call.arguments as Number).toLong().toInt()
                    // A style change (theme toggle) re-triggers ColorOS's
                    // forced-black nav bar, and no lifecycle event follows —
                    // use the delayed re-assert schedule, not a single apply.
                    scheduleEdgeToEdgeReassert()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }

        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

package com.securemessenger.app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secure_messenger/screen_privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setProtected") {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "secure_messenger/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAutoStartSettings" -> result.success(openAutoStartSettings())
                    "openAppInfo" -> result.success(openAppInfo())
                    "isHibernationExempt" -> result.success(isHibernationExempt())
                    "setHibernationExempt" -> result.success(setHibernationExempt())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens the vendor autostart manager so background work (keep-alive
     * service, WorkManager) survives after the app is swiped away. Falls
     * back to the app-details settings page.
     */
    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            // Xiaomi (MIUI / HyperOS)
            Intent("miui.intent.action.OP_AUTO_START"),
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            ),
            // Huawei (EMUI / HarmonyOS)
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
                )
            ),
            // Oppo / Realme (ColorOS)
            Intent().setComponent(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity"
                )
            ),
            // Vivo (Funtouch / OriginOS)
            Intent().setComponent(
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
            ),
            // OnePlus (OxygenOS)
            Intent().setComponent(
                ComponentName(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                )
            ),
            // Samsung
            Intent().setComponent(
                ComponentName(
                    "com.samsung.android.sm_cn",
                    "com.samsung.android.sm.ui.ram.AutoRunActivity"
                )
            ),
            // Asus
            Intent().setComponent(
                ComponentName(
                    "com.asus.mobilemanager",
                    "com.asus.mobilemanager.powersaver.PowerSaverSettings"
                )
            ),
            // Nokia (evenwell)
            Intent().setComponent(
                ComponentName(
                    "com.evenwell.powersaving.g3",
                    "com.evenwell.powersaving.g3.exception.PowerSaverExceptionActivity"
                )
            )
        )
        for (intent in candidates) {
            try {
                intent.addCategory(Intent.CATEGORY_DEFAULT)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        // Fall back to the app-details page (hosts the autostart-adjacent toggles
        // on ROMs without a dedicated manager).
        return openAppInfo()
    }

    private fun openAppInfo(): Boolean {
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * True when Android's "Pause app activity if unused" is OFF for us, i.e.
     * the system may not hibernate the app (which would freeze the keep-alive
     * service and cancel background work). Below Android 11 the feature does
     * not exist, so there is nothing to exempt.
     */
    private fun isHibernationExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
        return try {
            packageManager.isAutoRevokeWhitelisted(packageName)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Best-effort self-exemption from app hibernation. Returns the resulting
     * state: some ROMs refuse programmatic changes (SecurityException) and
     * the user must flip the toggle in App Info manually.
     */
    private fun setHibernationExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
        try {
            packageManager.setAutoRevokeWhitelisted(packageName, true)
        } catch (_: Exception) {
            // Refused: the UI falls back to guiding the user to App Info.
        }
        return isHibernationExempt()
    }
}

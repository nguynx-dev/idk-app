package com.example.app_manager

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "app_manager/native"
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val pkg = call.argument<String>("package")
                when (call.method) {
                    "getApps" -> runAsync(result) { getApps() }
                    "getIcon" -> {
                        if (pkg == null) result.error("ARG", "missing package", null)
                        else runAsync(result) { getIcon(pkg) }
                    }
                    "openApp" -> {
                        if (pkg == null) result.error("ARG", "missing package", null)
                        else result.success(openApp(pkg))
                    }
                    "uninstall" -> {
                        if (pkg == null) result.error("ARG", "missing package", null)
                        else result.success(uninstall(pkg))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runAsync(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(intent, 0)

        val seen = HashSet<String>()
        val list = ArrayList<Map<String, Any>>()

        for (ri in resolved) {
            val ai = ri.activityInfo.applicationInfo
            val pkg = ai.packageName
            if (!seen.add(pkg)) continue

            var size = File(ai.sourceDir).length()
            ai.splitSourceDirs?.forEach { size += File(it).length() }

            list.add(
                mapOf(
                    "name" to ai.loadLabel(pm).toString(),
                    "package" to pkg,
                    "size" to size,
                    "isSystem" to ((ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0)
                )
            )
        }
        return list
    }

    private fun getIcon(pkg: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(pkg)
            val px = 96
            val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, px, px)
            drawable.draw(canvas)
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            bmp.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    private fun openApp(pkg: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun uninstall(pkg: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}

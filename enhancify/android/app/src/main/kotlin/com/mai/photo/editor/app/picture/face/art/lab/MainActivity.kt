package com.mai.photo.editor.app.picture.face.art.lab

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Share to a specific app (Instagram, WhatsApp, …) or the system sheet.
        MethodChannel(messenger, "enhancify/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> {
                    val pkg = call.argument<String>("package")
                    result.success(pkg != null && isInstalled(pkg))
                }
                "shareToApp" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime") ?: "image/*"
                    val pkg = call.argument<String>("package")
                    val text = call.argument<String>("text")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.enhancify.fileprovider", shareableFile(File(path))
                        )
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = mime
                            putExtra(Intent.EXTRA_STREAM, uri)
                            if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (pkg != null) setPackage(pkg)
                        }
                        if (pkg == null) {
                            val chooser = Intent.createChooser(send, "Share")
                            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(chooser)
                        } else {
                            startActivity(send)
                        }
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    } catch (e: Throwable) {
                        result.error("share", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * FileProvider only serves files under the roots in enhancify_file_paths.xml
     * (cache, files, external cache). Dart's Directory.systemTemp on Android is
     * code_cache, which is outside them, so copy such files into cache/share.
     */
    private fun shareableFile(src: File): File {
        val target = src.canonicalPath
        val roots = listOfNotNull(cacheDir, filesDir, externalCacheDir)
            .map { it.canonicalPath + File.separator }
        if (roots.any { target.startsWith(it) }) return src
        val dir = File(cacheDir, "share").apply { mkdirs() }
        val out = File(dir, src.name)
        src.copyTo(out, overwrite = true)
        return out
    }

    @Suppress("DEPRECATION")
    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}

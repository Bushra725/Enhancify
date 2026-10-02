package com.mai.photo.editor.app.picture.face.art.lab

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import org.opencv.photo.Photo
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ---------------------------------------------------------- inpaint
        MethodChannel(messenger, "enhancify/inpaint").setMethodCallHandler { call, result ->
            if (call.method == "grabCut") {
                val photo = call.argument<ByteArray>("photo")
                if (photo == null) {
                    result.error("bad_args", "Photo is required.", null)
                    return@setMethodCallHandler
                }
                thread(name = "grabcut") {
                    try {
                        if (!OpenCVLoader.initLocal()) {
                            runOnUiThread { result.error("opencv", "OpenCV failed to load.", null) }
                            return@thread
                        }
                        val png = grabCut(photo)
                        runOnUiThread { result.success(png) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("grabcut", e.message, null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method != "removeObject") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val photo = call.argument<ByteArray>("photo")
            val mask = call.argument<ByteArray>("mask")
            val telea = call.argument<Boolean>("telea") ?: true
            val radius = call.argument<Double>("radius") ?: 4.0
            if (photo == null || mask == null) {
                result.error("bad_args", "Photo and mask are required.", null)
                return@setMethodCallHandler
            }
            thread(name = "inpaint") {
                try {
                    if (!OpenCVLoader.initLocal()) {
                        runOnUiThread { result.error("opencv", "OpenCV failed to load.", null) }
                        return@thread
                    }
                    val jpeg = inpaint(photo, mask, telea, radius)
                    runOnUiThread { result.success(jpeg) }
                } catch (e: Throwable) {
                    runOnUiThread { result.error("inpaint", e.message, null) }
                }
            }
        }

        // ------------------------------------------------------------ share
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

    /**
     * Background removal for objects (no person found): GrabCut seeded with
     * a centered rectangle, cleaned up, largest blob kept. Returns a PNG
     * mask (white = keep) at the photo's size.
     */
    private fun grabCut(photo: ByteArray): ByteArray {
        val bmp = BitmapFactory.decodeByteArray(photo, 0, photo.size)
            ?: throw IllegalArgumentException("Could not read the photo.")
        val src = Mat()
        val small = Mat()
        val mask = Mat()
        val bg = Mat()
        val fg = Mat()
        val bin = Mat()
        val full = Mat()
        try {
            Utils.bitmapToMat(bmp, src)
            Imgproc.cvtColor(src, src, Imgproc.COLOR_RGBA2RGB)
            val scale = min(1.0, 640.0 / max(src.cols(), src.rows()))
            Imgproc.resize(src, small, Size(src.cols() * scale, src.rows() * scale), 0.0, 0.0, Imgproc.INTER_AREA)
            val mx = (small.cols() * 0.04).roundToInt().coerceAtLeast(2)
            val my = (small.rows() * 0.04).roundToInt().coerceAtLeast(2)
            val rect = org.opencv.core.Rect(mx, my, small.cols() - 2 * mx, small.rows() - 2 * my)
            Imgproc.grabCut(small, mask, rect, bg, fg, 5, Imgproc.GC_INIT_WITH_RECT)
            // Foreground = definite or probable foreground.
            val fgd = Mat()
            val pfg = Mat()
            Core.compare(mask, org.opencv.core.Scalar(Imgproc.GC_FGD.toDouble()), fgd, Core.CMP_EQ)
            Core.compare(mask, org.opencv.core.Scalar(Imgproc.GC_PR_FGD.toDouble()), pfg, Core.CMP_EQ)
            Core.bitwise_or(fgd, pfg, bin)
            fgd.release(); pfg.release()
            val k = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(5.0, 5.0))
            Imgproc.morphologyEx(bin, bin, Imgproc.MORPH_OPEN, k)
            Imgproc.morphologyEx(bin, bin, Imgproc.MORPH_CLOSE, k)
            k.release()
            // Keep the biggest blob, filled.
            val contours = ArrayList<org.opencv.core.MatOfPoint>()
            val hier = Mat()
            val work = bin.clone()
            Imgproc.findContours(work, contours, hier, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
            work.release()
            hier.release()
            if (contours.isNotEmpty()) {
                val biggest = contours.maxByOrNull { Imgproc.contourArea(it) }!!
                val keep = Mat.zeros(bin.size(), bin.type())
                Imgproc.drawContours(keep, listOf(biggest), -1, org.opencv.core.Scalar(255.0), -1)
                // Keep inner holes that GrabCut found as background (e.g. mug handle).
                Core.bitwise_and(keep, bin, bin)
                keep.release()
            }
            Imgproc.resize(bin, full, src.size(), 0.0, 0.0, Imgproc.INTER_LINEAR)
            Imgproc.GaussianBlur(full, full, Size(0.0, 0.0), max(1.0, 1.2 / scale))
            val out = Bitmap.createBitmap(full.cols(), full.rows(), Bitmap.Config.ARGB_8888)
            val rgba = Mat()
            Imgproc.cvtColor(full, rgba, Imgproc.COLOR_GRAY2RGBA)
            Utils.matToBitmap(rgba, out)
            rgba.release()
            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.PNG, 100, stream)
            out.recycle()
            return stream.toByteArray()
        } finally {
            src.release(); small.release(); mask.release(); bg.release(); fg.release()
            bin.release(); full.release(); bmp.recycle()
        }
    }

    /**
     * Object removal. Small areas: classic inpainting. Large areas: fill a
     * quarter-size copy first (smooth, no streaks), paste it in, then
     * inpaint a thin seam at full size so the edge blends.
     */
    private fun inpaint(photo: ByteArray, mask: ByteArray, telea: Boolean, radius: Double): ByteArray {
        val srcBitmap = BitmapFactory.decodeByteArray(photo, 0, photo.size)
            ?: throw IllegalArgumentException("Could not read the photo.")
        val maskBitmap = BitmapFactory.decodeByteArray(mask, 0, mask.size)
            ?: throw IllegalArgumentException("Could not read the mask.")
        val src = Mat()
        val maskMat = Mat()
        val dst = Mat()
        val kernels = mutableListOf<Mat>()
        try {
            Utils.bitmapToMat(srcBitmap, src)
            Imgproc.cvtColor(src, src, Imgproc.COLOR_RGBA2RGB)
            Utils.bitmapToMat(maskBitmap, maskMat)
            Imgproc.cvtColor(maskMat, maskMat, Imgproc.COLOR_RGBA2GRAY)
            if (maskMat.size() != src.size()) {
                Imgproc.resize(maskMat, maskMat, src.size(), 0.0, 0.0, Imgproc.INTER_NEAREST)
            }
            Imgproc.threshold(maskMat, maskMat, 127.0, 255.0, Imgproc.THRESH_BINARY)

            // Grow the mask a little so edges and soft shadows go too.
            val grow = max(3, (min(src.cols(), src.rows()) * 0.006).roundToInt())
            val growK = Imgproc.getStructuringElement(
                Imgproc.MORPH_ELLIPSE, Size(grow * 2.0 + 1, grow * 2.0 + 1)
            )
            kernels.add(growK)
            Imgproc.dilate(maskMat, maskMat, growK)

            val flag = if (telea) Photo.INPAINT_TELEA else Photo.INPAINT_NS
            val area = Core.countNonZero(maskMat).toDouble()
            val total = src.cols().toDouble() * src.rows().toDouble()
            val r = max(radius, min(src.cols(), src.rows()) * 0.006)

            if (area > total * 0.008) {
                val smallSize = Size(src.cols() / 4.0, src.rows() / 4.0)
                val small = Mat()
                val smallMask = Mat()
                val smallOut = Mat()
                val up = Mat()
                val eroded = Mat()
                val ring = Mat()
                try {
                    Imgproc.resize(src, small, smallSize, 0.0, 0.0, Imgproc.INTER_AREA)
                    Imgproc.resize(maskMat, smallMask, smallSize, 0.0, 0.0, Imgproc.INTER_AREA)
                    Imgproc.threshold(smallMask, smallMask, 1.0, 255.0, Imgproc.THRESH_BINARY)
                    Photo.inpaint(small, smallMask, smallOut, 5.0, flag)
                    Imgproc.resize(smallOut, up, src.size(), 0.0, 0.0, Imgproc.INTER_CUBIC)
                    up.copyTo(src, maskMat)
                    // Seam: a thin band along the mask edge.
                    val band = max(3, grow)
                    val bandK = Imgproc.getStructuringElement(
                        Imgproc.MORPH_ELLIPSE, Size(band * 2.0 + 1, band * 2.0 + 1)
                    )
                    kernels.add(bandK)
                    Imgproc.erode(maskMat, eroded, bandK)
                    Core.subtract(maskMat, eroded, ring)
                    Photo.inpaint(src, ring, dst, r, flag)
                } finally {
                    small.release(); smallMask.release(); smallOut.release()
                    up.release(); eroded.release(); ring.release()
                }
            } else {
                Photo.inpaint(src, maskMat, dst, r, flag)
            }

            val rgba = Mat()
            Imgproc.cvtColor(dst, rgba, Imgproc.COLOR_RGB2RGBA)
            val out = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(rgba, out)
            rgba.release()
            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.JPEG, 94, stream)
            out.recycle()
            return stream.toByteArray()
        } finally {
            src.release()
            maskMat.release()
            dst.release()
            kernels.forEach { it.release() }
            srcBitmap.recycle()
            maskBitmap.recycle()
        }
    }
}

package com.theoccess.enhancify

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import org.opencv.photo.Photo
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "enhancify/inpaint")
            .setMethodCallHandler { call, result ->
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
                            runOnUiThread {
                                result.error("opencv", "OpenCV failed to load.", null)
                            }
                            return@thread
                        }
                        val jpeg = inpaint(photo, mask, telea, radius)
                        runOnUiThread { result.success(jpeg) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("inpaint", e.message, null)
                        }
                    }
                }
            }
    }

    private fun inpaint(photo: ByteArray, mask: ByteArray, telea: Boolean, radius: Double): ByteArray {
        val srcBitmap = BitmapFactory.decodeByteArray(photo, 0, photo.size)
            ?: throw IllegalArgumentException("Could not read the photo.")
        val maskBitmap = BitmapFactory.decodeByteArray(mask, 0, mask.size)
            ?: throw IllegalArgumentException("Could not read the mask.")
        val src = Mat()
        val maskMat = Mat()
        val dst = Mat()
        try {
            Utils.bitmapToMat(srcBitmap, src)
            Imgproc.cvtColor(src, src, Imgproc.COLOR_RGBA2RGB)
            Utils.bitmapToMat(maskBitmap, maskMat)
            Imgproc.cvtColor(maskMat, maskMat, Imgproc.COLOR_RGBA2GRAY)
            val flag = if (telea) Photo.INPAINT_TELEA else Photo.INPAINT_NS
            Photo.inpaint(src, maskMat, dst, radius, flag)
            val rgba = Mat()
            Imgproc.cvtColor(dst, rgba, Imgproc.COLOR_RGB2RGBA)
            val out = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(rgba, out)
            rgba.release()
            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.JPEG, 92, stream)
            return stream.toByteArray()
        } finally {
            src.release()
            maskMat.release()
            dst.release()
            srcBitmap.recycle()
            maskBitmap.recycle()
        }
    }
}

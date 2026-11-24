package com.inou.inou_app

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.inou.inou_app/native_media"
        private const val REQ_CAMERA_PERM = 4001
        private const val REQ_CAMERA = 4002
        private const val REQ_GALLERY = 4003
        private const val REQ_PICK_FILE = 4004
        private const val REQ_SAVE_FILE = 4005
        private const val MAX_IMAGE_DIM = 2048
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getWorkspaceDir" -> {
                        val dir = File(filesDir, "inou_workspace").apply { mkdirs() }
                        result.success(dir.absolutePath)
                    }
                    "capturePhoto" -> handleCapturePhoto(result)
                    "pickGalleryImage" -> handlePickGallery(result)
                    "pickFile" -> handlePickFile(call, result)
                    "saveFile" -> handleSaveFile(call, result)
                    "shareFile" -> handleShareFile(call, result)
                    "rotateImage90" -> handleRotateImage90(call, result)
                    "getDisplayCutoutInsets" -> handleGetDisplayCutoutInsets(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleGetDisplayCutoutInsets(result: MethodChannel.Result) {
        val rootInsets = window.decorView.rootWindowInsets
        if (rootInsets == null) {
            result.success(
                mapOf("left" to 0.0, "top" to 0.0, "right" to 0.0, "bottom" to 0.0),
            )
            return
        }
        val compat = WindowInsetsCompat.toWindowInsetsCompat(rootInsets, window.decorView)
        val cutout = compat.getInsets(WindowInsetsCompat.Type.displayCutout())
        val density = resources.displayMetrics.density.coerceAtLeast(1f).toDouble()
        result.success(
            mapOf(
                "left" to cutout.left / density,
                "top" to cutout.top / density,
                "right" to cutout.right / density,
                "bottom" to cutout.bottom / density,
            ),
        )
    }

    private fun claimPendingResult(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("BUSY", "上一个系统操作尚未完成", null)
            return false
        }
        pendingResult = result
        return true
    }

    private fun handleCapturePhoto(result: MethodChannel.Result) {
        if (!claimPendingResult(result)) return
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA_PERM)
            return
        }
        launchCameraIntent()
    }

    private fun launchCameraIntent() {
        val res = pendingResult ?: return
        try {
            val captureDir = File(cacheDir, "captures").apply { mkdirs() }
            val photoFile = File(captureDir, "exam_${System.currentTimeMillis()}.jpg")
            pendingCameraFile = photoFile
            val photoUri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                photoFile,
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                clipData = ClipData.newRawUri("capture", photoUri)
                addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_CAMERA)
        } catch (_: ActivityNotFoundException) {
            pendingResult = null
            pendingCameraFile = null
            res.error("NO_CAMERA", "未检测到可用的系统相机应用", null)
        } catch (e: Exception) {
            pendingResult = null
            pendingCameraFile = null
            res.error("CAMERA_ERROR", e.localizedMessage ?: "启动相机失败", null)
        }
    }

    private fun handlePickGallery(result: MethodChannel.Result) {
        if (!claimPendingResult(result)) return
        try {
            val intent = if (Build.VERSION.SDK_INT >= 33) {
                Intent(MediaStore.ACTION_PICK_IMAGES)
            } else {
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_GALLERY)
        } catch (_: ActivityNotFoundException) {
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
                @Suppress("DEPRECATION")
                startActivityForResult(fallback, REQ_GALLERY)
            } catch (e: Exception) {
                pendingResult = null
                result.error("NO_GALLERY", e.localizedMessage ?: "无法打开系统相册", null)
            }
        }
    }

    private fun handlePickFile(call: MethodCall, result: MethodChannel.Result) {
        if (!claimPendingResult(result)) return
        val mime = call.argument<String>("mimeType") ?: "*/*"
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_PICK_FILE)
        } catch (e: Exception) {
            pendingResult = null
            result.error("FILE_PICK_ERROR", e.localizedMessage ?: "无法打开文件选择器", null)
        }
    }

    private fun handleSaveFile(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val filename = call.argument<String>("filename") ?: "backup.inou"
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (bytes == null) {
            result.error("INVALID_ARGS", "Missing file bytes", null)
            return
        }
        if (!claimPendingResult(result)) return
        pendingSaveBytes = bytes
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, filename)
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_SAVE_FILE)
        } catch (e: Exception) {
            pendingResult = null
            pendingSaveBytes = null
            result.error("FILE_SAVE_ERROR", e.localizedMessage ?: "无法打开系统保存对话框", null)
        }
    }

    private fun handleShareFile(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val filename = call.argument<String>("filename") ?: "backup.inou"
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (bytes == null) {
            result.error("INVALID_ARGS", "Missing file bytes", null)
            return
        }
        Thread {
            try {
                val dir = File(cacheDir, "shared").apply { mkdirs() }
                val outFile = File(dir, filename)
                outFile.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    outFile,
                )
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = mime
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri(filename, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                runOnUiThread {
                    startActivity(Intent.createChooser(sendIntent, "导出并分享文件"))
                    result.success(true)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SHARE_ERROR", e.localizedMessage ?: "分享失败", null)
                }
            }
        }.start()
    }

    private fun handleRotateImage90(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<ByteArray>("bytes")
        if (raw == null) {
            result.error("INVALID_ARGS", "Missing image bytes", null)
            return
        }
        Thread {
            try {
                val bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size)
                if (bmp == null) {
                    runOnUiThread { result.error("DECODE_ERROR", "图片解码失败", null) }
                    return@Thread
                }
                val matrix = Matrix().apply { postRotate(90f) }
                val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                if (rotated != bmp) bmp.recycle()
                val out = ByteArrayOutputStream()
                rotated.compress(Bitmap.CompressFormat.JPEG, 88, out)
                rotated.recycle()
                val resBytes = out.toByteArray()
                runOnUiThread { result.success(resBytes) }
            } catch (e: Exception) {
                runOnUiThread { result.error("ROTATE_ERROR", e.localizedMessage, null) }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA_PERM) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchCameraIntent()
            } else {
                val res = pendingResult
                pendingResult = null
                res?.error("CAMERA_PERMISSION_DENIED", "需要授予相机权限才能拍照录题", null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in listOf(REQ_CAMERA, REQ_GALLERY, REQ_PICK_FILE, REQ_SAVE_FILE)) {
            return
        }
        val res = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK) {
            pendingCameraFile?.delete()
            pendingCameraFile = null
            pendingSaveBytes = null
            res.success(null)
            return
        }

        when (requestCode) {
            REQ_CAMERA -> {
                val file = pendingCameraFile
                pendingCameraFile = null
                if (file == null || !file.exists()) {
                    res.error("CAPTURE_MISSING", "未能读取拍摄的照片", null)
                    return
                }
                Thread {
                    try {
                        val normalized = decodeAndNormalizeFile(file)
                        val name = file.name
                        file.delete()
                        runOnUiThread {
                            res.success(
                                mapOf(
                                    "bytes" to normalized,
                                    "name" to name,
                                    "mimeType" to "image/jpeg",
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        file.delete()
                        runOnUiThread {
                            res.error("IMAGE_DECODE", e.localizedMessage ?: "图像处理失败", null)
                        }
                    }
                }.start()
            }
            REQ_GALLERY -> {
                val uri = data?.data
                if (uri == null) {
                    res.success(null)
                    return
                }
                Thread {
                    try {
                        val normalized = decodeAndNormalizeUri(uri)
                        val name = queryDisplayName(uri) ?: "gallery_${System.currentTimeMillis()}.jpg"
                        runOnUiThread {
                            res.success(
                                mapOf(
                                    "bytes" to normalized,
                                    "name" to name,
                                    "mimeType" to "image/jpeg",
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            res.error("GALLERY_DECODE", e.localizedMessage ?: "读取相册图片失败", null)
                        }
                    }
                }.start()
            }
            REQ_PICK_FILE -> {
                val uri = data?.data
                if (uri == null) {
                    res.success(null)
                    return
                }
                Thread {
                    try {
                        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        val name = queryDisplayName(uri) ?: "imported_file"
                        runOnUiThread {
                            if (bytes == null) {
                                res.error("FILE_READ", "无法读取所选文件", null)
                            } else {
                                res.success(mapOf("bytes" to bytes, "name" to name))
                            }
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            res.error("FILE_READ", e.localizedMessage ?: "文件读取失败", null)
                        }
                    }
                }.start()
            }
            REQ_SAVE_FILE -> {
                val uri = data?.data
                val bytes = pendingSaveBytes
                pendingSaveBytes = null
                if (uri == null || bytes == null) {
                    res.success(false)
                    return
                }
                Thread {
                    try {
                        contentResolver.openOutputStream(uri)?.use { out ->
                            out.write(bytes)
                            out.flush()
                        }
                        runOnUiThread { res.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            res.error("FILE_WRITE", e.localizedMessage ?: "保存文件失败", null)
                        }
                    }
                }.start()
            }
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) return cursor.getString(idx)
            }
        }
        return uri.lastPathSegment
    }

    private fun decodeAndNormalizeFile(file: File): ByteArray {
        val raw = FileInputStream(file).use { it.readBytes() }
        return normalizeImageBytes(raw)
    }

    private fun decodeAndNormalizeUri(uri: Uri): ByteArray {
        val raw = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("Empty image stream")
        return normalizeImageBytes(raw)
    }

    private fun normalizeImageBytes(raw: ByteArray): ByteArray {
        val orientation = ByteArrayInputStream(raw).use { stream ->
            ExifInterface(stream).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        val maxSrc = max(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (maxSrc / sample > MAX_IMAGE_DIM * 2) {
            sample *= 2
        }

        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size, opts)
            ?: throw IllegalStateException("Unable to decode image bitmap")

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
        }
        if (!matrix.isIdentity) {
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (rotated != bmp) bmp.recycle()
            bmp = rotated
        }

        val largest = max(bmp.width, bmp.height)
        if (largest > MAX_IMAGE_DIM) {
            val scale = MAX_IMAGE_DIM.toFloat() / largest.toFloat()
            val targetW = max(1, (bmp.width * scale).toInt())
            val targetH = max(1, (bmp.height * scale).toInt())
            val scaled = Bitmap.createScaledBitmap(bmp, targetW, targetH, true)
            if (scaled != bmp) bmp.recycle()
            bmp = scaled
        }

        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 88, out)
        bmp.recycle()
        return out.toByteArray()
    }
}

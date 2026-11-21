package io.github.hahahemmm.biology

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // v2.5 拍题识别：ACTION_OPEN_DOCUMENT 选图（SAF，无需存储权限），
    // 返回 {bytes: ByteArray, name: String}；取消返回 null。
    private val channelName = "biology/image_pick"
    private val pickRequestCode = 9021
    private var pendingResult: MethodChannel.Result? = null

    // v2.13 R3 W1（P0 修复）：应用专属目录。Android 无 USERPROFILE/HOME
    // 环境变量，userAppDir() 之前回退 '.' → cwd=/ → EACCES → 全盘持久化
    // 静默失效。经本 channel 暴露 Context.getFilesDir()
    //（= /data/data/<pkg>/files 或 /data/user/0/<pkg>/files），零插件约束，
    // 与 image_pick / json_pick 同模式。
    private val appDirChannelName = "biology/app_dir"

    // v2.13 R4-2（P1-2 EACCES 修复配套）：导出文件分享到系统分享面板。
    // Android 主力路径：学生错题 JSON → 微信/QQ；老师板书 PNG → 微信群。
    // 文件在应用专属目录（getFilesDir），分享目标看不到私有目录 → 必须
    // 经 FileProvider 暴露为 content:// URI（Uri.fromFile 在 targetSdk 35
    // 下抛 FileUriExposedException），Intent.ACTION_SEND 拉起分享面板。
    private val shareChannelName = "biology/share_file"

    // v2.13 R4-1 P1 + R4f P0-1（四轮重审回归修复）：错题本「从文件选
    // .json」/ 导入。R4-1（e667ba2）注册过 biology/json_pick handler，
    // 但 R4-2（7bde761，加 share channel 重写 MainActivity.kt 时基于旧
    // 基线）把该块整块删除 → Android 端 MissingPluginException 被 Dart
    // catch 吞掉 → 导入按钮静默死。本段自 e667ba2 原样重放，与
    // image_pick / app_dir / share_file 三个 channel 共存：
    //   - 结果码规划：9021 image_pick / 9022 share_file（share 经
    //     Intent.createChooser 直接拉起，不经 onActivityResult，9022 为
    //     预留位）/ 9023 json_pick
    //   - pickJson → SAF ACTION_OPEN_DOCUMENT（系统文档选择器，无需存储
    //     权限）：不用 getFilesDir 应用内浏览——用户要导的是微信/下载
    //     目录的 .json 备份，应用内浏览看不到跨设备导入反而断裂。
    //   - MIME：*/* + EXTRA_MIME_TYPES=[application/json, text/plain]，
    //     文件管理器常把 .json 标成 text/plain / octet-stream。
    //   - 返回 {content: String, name: String}（与 json_pick_stub.dart 的
    //     PickedJson(content, name) 契约一致）；取消返回 null。
    private val jsonPickChannelName = "biology/json_pick"
    private val jsonPickRequestCode = 9023
    private var pendingJsonResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> {
                        if (pendingResult != null) {
                            result.error("busy", "已有选图请求进行中", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "image/*"
                        }
                        startActivityForResult(intent, pickRequestCode)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appDirChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFilesDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFile" -> shareFile(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, jsonPickChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJson" -> {
                        if (pendingJsonResult != null) {
                            result.error("busy", "已有选 JSON 请求进行中", null)
                            return@setMethodCallHandler
                        }
                        pendingJsonResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf("application/json", "text/plain")
                            )
                        }
                        startActivityForResult(intent, jsonPickRequestCode)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val mime = call.argument<String>("mimeType") ?: "*/*"
        if (path.isNullOrEmpty()) {
            result.error("bad_arg", "path 为空", null)
            return
        }
        val f = File(path)
        if (!f.exists()) {
            result.error("not_found", "文件不存在", null)
            return
        }
        // authority 与 AndroidManifest 里 FileProvider 的
        // android:authorities="${applicationId}.fileprovider" 一致。
        // R7-P2: getUriForFile 抛 IllegalArgumentException（如 authority 未
        // 配 / 路径越出 paths 配置）会 crash app；包到 try 内与 startActivity
        // 共用错误通路，返回 bad_uri 错误。
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
        } catch (e: Exception) {
            android.util.Log.e(
                "MainActivity",
                "getUriForFile 失败 path=$path authority=${packageName}.fileprovider",
                e,
            )
            result.error("bad_uri", e.message ?: "FileProvider 解析失败", null)
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setClipData(ClipData.newRawUri(null, uri))
        }
        try {
            startActivity(Intent.createChooser(intent, "分享到"))
            result.success(null)
        } catch (e: Exception) {
            result.error("no_handler", e.message ?: "无可用分享目标", null)
        }
    }

    @Deprecated("FlutterActivity 结果流仍走 onActivityResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            pickRequestCode -> handleImagePickResult(resultCode, data)
            jsonPickRequestCode -> handleJsonPickResult(resultCode, data)
        }
    }

    /// image_pick 结果：读字节 + 文件名 → {bytes, name}。
    ///（v2.13 R4f P0-1 重放时从单块 onActivityResult 拆出，逻辑原样）
    private fun handleImagePickResult(resultCode: Int, data: Intent?) {
        val r = pendingResult
        pendingResult = null
        if (r == null) return
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            r.success(null)
            return
        }
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) {
                r.success(null)
                return
            }
            var name = "image.jpg"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx)?.let { name = it }
            }
            r.success(mapOf("bytes" to bytes, "name" to name))
        } catch (e: Exception) {
            r.error("read_fail", e.message, null)
        }
    }

    /// json_pick 结果：读全文（UTF-8）+ 文件名 → {content, name}。
    /// 与 Dart 侧 json_pick_stub.dart 的 PickedJson(content, name) 契约一致。
    private fun handleJsonPickResult(resultCode: Int, data: Intent?) {
        val r = pendingJsonResult
        pendingJsonResult = null
        if (r == null) return
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            r.success(null)
            return
        }
        try {
            val content = contentResolver.openInputStream(uri)
                ?.bufferedReader()?.use { it.readText() }
            if (content == null) {
                r.success(null)
                return
            }
            var name = "import.json"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx)?.let { name = it }
            }
            r.success(mapOf("content" to content, "name" to name))
        } catch (e: Exception) {
            r.error("read_fail", e.message, null)
        }
    }
}
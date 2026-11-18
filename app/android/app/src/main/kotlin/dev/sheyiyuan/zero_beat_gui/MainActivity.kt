package dev.sheyiyuan.zero_beat_gui

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.CancellationSignal
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

class MainActivity : AudioServiceActivity() {
    companion object {
        private val executor = Executors.newFixedThreadPool(2)
        private val scanExecutor = Executors.newSingleThreadExecutor()
        private val scans = ConcurrentHashMap<String, CancellationSignal>()
        private data class Handle(val descriptor: ParcelFileDescriptor, val staged: File?)
        private val handles = mutableMapOf<Int, Handle>()
        private var resourceCache: ResourceCache? = null
    }
    private var picker: MethodChannel.Result? = null
    private var exportPath: String? = null
    private val permissions = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "zero_beat/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    if (picker != null) { result.error("busy", "请先完成当前文件选择", null); return@setMethodCallHandler }
                    picker = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(permissions or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION), 7401)
                }
                "export" -> {
                    val path = call.argument<String>("path")!!
                    if (Build.VERSION.SDK_INT >= 29 && call.argument<Boolean>("save_as") != true) background(result) { exportMusic(path); true }
                    else {
                        if (picker != null) { result.error("busy", "请先完成当前文件选择", null); return@setMethodCallHandler }
                        picker = result; exportPath = path
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).setType("audio/*").putExtra(Intent.EXTRA_TITLE, File(path).name).addCategory(Intent.CATEGORY_OPENABLE), 7402)
                    }
                }
                "grants" -> result.success(contentResolver.persistedUriPermissions.map { it.uri.toString() })
                "cancelScan" -> { scans[call.argument<String>("scan")]?.cancel(); result.success(null) }
                "enumerate" -> {
                    val key = call.argument<String>("scan")!!
                    val signal = CancellationSignal()
                    scans[key] = signal
                    scanExecutor.execute {
                        try { val value = enumerate(Uri.parse(call.argument<String>("uri")), signal); runOnUiThread { result.success(value) } }
                        catch (e: Exception) { runOnUiThread { result.error(if(signal.isCanceled) "cancelled" else "storage", e.message, null) } }
                        finally { scans.remove(key, signal) }
                    }
                }
                "duration" -> background(result) {
                    val retriever = MediaMetadataRetriever()
                    try { retriever.setDataSource(this, Uri.parse(call.argument<String>("uri"))); (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.div(1000) ?: 0).toInt() }
                    catch (_: Exception) { 0 } finally { retriever.release() }
                }
                "open" -> background(result) {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    require(uri.scheme == "content") { "文件授权无效" }
                    val source = contentResolver.openFileDescriptor(uri, "r") ?: error("文件不可读，请重新授权")
                    // A SAF grant permits reading the supplied descriptor, but
                    // does not guarantee that native libraries can reopen its
                    // /proc/self/fd path. Use a private, seekable cache file for
                    // core tag/hash inspection and player access.
                    var staged: File? = null
                    try {
                        val cache = synchronized(handles) {
                            resourceCache ?: ResourceCache(File(cacheDir, "resource-handles")).also { resourceCache = it }
                        }
                        val file = cache.stage(ParcelFileDescriptor.AutoCloseInputStream(source))
                        staged = file
                        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        synchronized(handles) { handles[fd.fd] = Handle(fd, file) }
                        fd.fd
                    } catch (e: Exception) {
                        try { source.close() } catch (_: Exception) {}
                        staged?.delete()
                        throw e
                    }
                }
                "close" -> background(result) {
                    val handle = synchronized(handles) { handles.remove(call.argument<Int>("fd")) }
                    try { handle?.descriptor?.close() }
                    finally { handle?.staged?.delete() }
                    null
                }
                "release" -> background(result) {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val grant = contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri }
                    if (grant != null) {
                        val flags = (if (grant.isReadPermission) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
                            (if (grant.isWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
                        contentResolver.releasePersistableUriPermission(uri, flags)
                    }
                    null
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try { val value=work(); runOnUiThread { result.success(value) } }
            catch (e: Exception) { runOnUiThread { result.error("storage", e.message ?: "文件操作失败", null) } }
        }
    }
    @Deprecated("Activity API used for Flutter activity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7401 && requestCode != 7402) return
        val result = picker ?: return
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { exportPath=null; result.success(null); return }
        if (requestCode == 7401) {
            try { contentResolver.takePersistableUriPermission(uri, data.flags and permissions); result.success(uri.toString()) }
            catch (e: Exception) { result.error("grant", "无法保存目录授权：${e.message}", null) }
        } else {
            val path=exportPath;exportPath=null
            background(result) {
                try { copyTo(File(path!!), uri); true }
                catch (e: Exception) {
                    // ACTION_CREATE_DOCUMENT created a new file for this export.
                    // A failed copy must not leave a broken download visible.
                    try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) {}
                    throw e
                }
            }
        }
    }
    private fun enumerate(tree: Uri, signal: CancellationSignal): Map<String, Any> {
        val id = DocumentsContract.getTreeDocumentId(tree)
        val files = mutableListOf<Pair<String, Uri>>()
        val lyrics = mutableMapOf<String, String>()
        var subdirs = 0
        fun list(parent: String, prefix: String) {
            signal.throwIfCanceled()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            val lyricDirs = mutableListOf<String>()
            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null, signal)?.use { cursor ->
                while(cursor.moveToNext()) {
                    signal.throwIfCanceled()
                    val name = cursor.getString(1)
                    val child = cursor.getString(0)
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (prefix.isEmpty()) { if (name.equals("lyrics", true)) lyricDirs.add(child) else subdirs++ }
                        continue
                    }
                    if (name.startsWith(".")) continue
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, child)
                    if (prefix.isEmpty()) files.add(name to uri)
                    if (name.endsWith(".lrc", true)) lyrics[prefix + name] = uri.toString()
                }
            } ?: error("文件夹不可读，请重新授权")
            for (child in lyricDirs) list(child, "lyrics/")
        }
        list(id, "")
        val audio = setOf("mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "ape", "wv", "aiff", "aif", "wma")
        val result = files.filter { it.first.substringAfterLast('.').lowercase() in audio }.map { (name, uri) -> mapOf("name" to name, "uri" to uri.toString()) }
        return mapOf("title" to id.substringAfterLast(':'), "files" to result, "lyrics" to lyrics, "subdirs" to subdirs)
    }
    private fun copyTo(file:File, uri:Uri) {
        val input=file.canonicalFile
        require(input.exists()&&input.isFile) { "下载文件不存在" }
        contentResolver.openOutputStream(uri,"w")?.use { output -> input.inputStream().use { it.copyTo(output) } } ?: error("无法写入导出文件")
    }
    private fun exportMusic(path:String) {
        val file=File(path)
        val values=ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME,file.name)
            put(MediaStore.Audio.Media.MIME_TYPE,when(file.extension.lowercase()){ "flac"->"audio/flac";"mp3"->"audio/mpeg";"ogg","opus"->"audio/ogg";else->"audio/mp4" })
            put(MediaStore.Audio.Media.RELATIVE_PATH,Environment.DIRECTORY_MUSIC+"/零拍")
            put(MediaStore.Audio.Media.IS_PENDING,1)
        }
        val uri=contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,values) ?: error("无法创建系统音乐文件")
        try { copyTo(file,uri);values.clear();values.put(MediaStore.Audio.Media.IS_PENDING,0);contentResolver.update(uri,values,null,null) }
        catch(e:Exception) {contentResolver.delete(uri,null,null);throw e}
    }
    override fun onDestroy() {
        picker?.success(null);picker=null
        // Descriptor ownership is the player, not this activity: background audio
        // can outlive an activity recreation. Dart closes each explicit handle.
        super.onDestroy()
    }
}

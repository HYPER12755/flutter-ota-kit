package com.flutter_patcher.flutter_patcher

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.StandardMessageCodec
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.Collections
import java.util.zip.ZipException
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

internal typealias ProgressCallback = (phase: String, received: Long, total: Long) -> Unit

internal object Phase {
    const val DOWNLOADING = "downloading"
    const val VERIFYING = "verifying"
    const val FINALIZING = "finalizing"
}

internal data class ValidPatch(
    val soPath: String,
    val assetsPath: String?,
    val assetsArchivePath: String?,
    val assetsBundlePath: String?
)

internal data class HistoryEntry(
    val version: String,
    val md5: String,
    val path: String,
    val assetsRef: Int,
    val installedAt: Long
)

internal enum class RollbackResult {
    SUCCESS,
    FALLBACK_TO_BASE,
    SKIPPED_BLACKLISTED
}

private class PatchInstallException(
    val code: String,
    message: String,
    cause: Throwable? = null
) : RuntimeException(message, cause)

internal fun codecBufferToByteArray(buffer: ByteBuffer): ByteArray {
    buffer.rewind()
    val bytes = ByteArray(buffer.remaining())
    buffer.get(bytes)
    return bytes
}

internal class PatchManager(
    private val context: Context,
    private val progress: ProgressCallback? = null
) {
    companion object {
        private const val TAG = "FlutterPatcher/Mgr"

        private const val CONNECT_TIMEOUT_MS = 10_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val MAX_RETRIES = 3
        private const val PROGRESS_EMIT_INTERVAL_MS = 200L

        private const val MODE_FULL = "full"
        private const val FLUTTER_ASSETS_PREFIX = "assets/flutter_assets/"
        private const val ASSET_MANIFEST = "AssetManifest.bin"
        private const val STAGING_DIR = "staging"
        private const val ASSET_DIR = "flutter_assets"
        private const val ASSET_ARCHIVE = "flutter_assets.apk"
        private const val PATCH_ASSET_BUNDLE = "flutter_patcher_assets"
        private const val PATCH_ASSETS_PREFIX = "assets/$PATCH_ASSET_BUNDLE/"
        private const val MIN_FREE_SPACE_BUFFER = 10L * 1024L * 1024L
        private val MD5_HEX = Regex("^[0-9a-fA-F]{32}$")

        private val APPLY_LOCK = Any()

        internal fun validatePatchArgs(
            version: String,
            url: String,
            md5: String,
            mode: String,
            targetVersionCode: Long?,
            currentVersionCode: Long
        ): ApplyResult? {
            if (version.isBlank() || url.isBlank()) {
                return ApplyResult.failure(ApplyErrorCode.INVALID_ARGS, "missing version/url")
            }
            if (md5.isNotBlank() && !MD5_HEX.matches(md5)) {
                return ApplyResult.failure(
                    ApplyErrorCode.INVALID_ARGS,
                    "md5 must be 32 hex chars or empty"
                )
            }
            if (mode != MODE_FULL) {
                return ApplyResult.failure(
                    ApplyErrorCode.INVALID_ARGS,
                    "unsupported mode: $mode; only full patches are supported"
                )
            }
            if (targetVersionCode != null) {
                if (currentVersionCode == PatcherConfig.INVALID_VERSION_CODE) {
                    return ApplyResult.failure(
                        ApplyErrorCode.IO_ERROR,
                        "cannot resolve current app versionCode"
                    )
                }
                if (targetVersionCode != currentVersionCode) {
                    return ApplyResult.failure(
                        ApplyErrorCode.INVALID_ARGS,
                        "targetVersionCode=$targetVersionCode does not match current=$currentVersionCode"
                    )
                }
            }
            return null
        }

        internal fun isSameInstalledPatch(
            currentMeta: Pair<String, String>?,
            version: String,
            md5: String
        ): Boolean {
            if (currentMeta == null) return false
            if (md5.isBlank()) return currentMeta.first == version
            return currentMeta.first == version &&
                currentMeta.second.equals(md5, ignoreCase = true)
        }

        internal fun isZipPayload(file: File): Boolean {
            if (!file.exists() || file.length() < 4) return false
            val header = ByteArray(4)
            file.inputStream().use { input ->
                if (input.read(header) != 4) return false
            }
            return header[0] == 0x50.toByte() &&
                header[1] == 0x4b.toByte() &&
                header[2] == 0x03.toByte() &&
                header[3] == 0x04.toByte()
        }

        internal fun isSafeZipPath(path: String): Boolean {
            if (path.isEmpty()) return false
            if (path.startsWith("/") || path.startsWith("\\")) return false
            if (path.contains('\u0000')) return false
            return path.split('/').none { it == ".." }
        }

        internal fun selectPackageAbi(lib: JSONObject, supportedAbis: Array<String>): String? {
            for (abi in supportedAbis) {
                if (lib.has(abi)) return abi
            }
            return null
        }

        // A patch.zip is "Dart-only" when the inner manifest carries no overlay
        // asset list. Both the missing `assets` block and the explicit empty
        // `files: []` form are treated as Dart-only so the runtime can skip the
        // asset overlay copy/repack and behave like a code-only patch.
        internal fun isDartOnlyAssets(assets: JSONObject?): Boolean {
            if (assets == null) return true
            val files = assets.optJSONArray("files") ?: return true
            return files.length() == 0
        }
    }

    private val patchDir = File(context.filesDir, PatcherConfig.PATCH_DIR)
    private val patchFile = File(patchDir, PatcherConfig.PATCH_FILENAME)
    private val assetsDir = File(patchDir, ASSET_DIR)
    private val assetsArchive = File(patchDir, ASSET_ARCHIVE)
    private val metaFile = File(patchDir, PatcherConfig.META_FILENAME)
    private val installMarkerFile = File(patchDir, "installing")
    private val stagingDir = File(patchDir, STAGING_DIR)
    private val pendingSo = File(patchDir, "${PatcherConfig.PATCH_FILENAME}.pending")
    private val pendingMeta = File(patchDir, "${PatcherConfig.META_FILENAME}.pending")
    private val pendingAssets = File(patchDir, "$ASSET_DIR.pending")
    private val pendingAssetsArchive = File(patchDir, "$ASSET_ARCHIVE.pending")
    private val previousSo = File(patchDir, "${PatcherConfig.PATCH_FILENAME}.previous")
    private val previousMeta = File(patchDir, "${PatcherConfig.META_FILENAME}.previous")
    private val previousAssets = File(patchDir, "$ASSET_DIR.previous")
    private val previousAssetsArchive = File(patchDir, "$ASSET_ARCHIVE.previous")

    // Patch history directories
    private val historyDir = File(patchDir, "history")
    private val historyIndexFile = File(historyDir, "index.json")
    private val assetsHistoryDir = File(patchDir, "assets")
    private val baseAssetsArchive = File(assetsHistoryDir, "0/flutter_assets.apk")

    fun getValidPatchPath(
        onDrop: ((status: String, version: String?, extras: Map<String, Any?>) -> Unit)? = null
    ): String? = getValidPatch(onDrop)?.soPath

    fun getValidPatch(
        onDrop: ((status: String, version: String?, extras: Map<String, Any?>) -> Unit)? = null
    ): ValidPatch? {
        if (installMarkerFile.exists()) {
            Log.w(TAG, "previous patch install was interrupted, recover prepared artifacts")
            recoverInterruptedInstall()
        }
        if (!patchFile.exists() || !metaFile.exists()) return null

        val meta = readMeta()
        if (meta == null) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_META_CORRUPTED,
                null,
                mapOf("message" to "meta.json missing or unparseable")
            )
            deletePatch()
            return null
        }

        val version = meta.optString("version", "").ifEmpty { null }
        val patchVc = meta.optLong(
            PatcherConfig.META_KEY_TARGET_VERSION_CODE,
            PatcherConfig.INVALID_VERSION_CODE
        )
        val currentVc = PatcherConfig.currentVersionCode(context)
        if (patchVc == PatcherConfig.INVALID_VERSION_CODE ||
            currentVc == PatcherConfig.INVALID_VERSION_CODE ||
            patchVc != currentVc
        ) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_VERSION_CODE_MISMATCH,
                version,
                mapOf(
                    "patchTargetVersionCode" to patchVc,
                    "appVersionCode" to currentVc,
                    "message" to "patch built for vc=$patchVc, app is vc=$currentVc"
                )
            )
            deletePatch()
            return null
        }

        val expectedMd5 = meta.optString("effectiveMd5", "")
        val signature = meta.optString("signature", "")
        val publicKey = PatcherConfig.publicKey(context)
        val strictSignature = PatcherConfig.strictSignature(context)

        if (expectedMd5.isEmpty()) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_META_CORRUPTED,
                version,
                mapOf("message" to "meta.effectiveMd5 missing")
            )
            deletePatch()
            return null
        }

        val verifyResult = SignatureVerifier.verifyDetailed(
            patchFile, expectedMd5, signature, publicKey, strictSignature
        )
        if (verifyResult != SignatureVerifier.VerifyResult.OK) {
            val status = when (verifyResult) {
                SignatureVerifier.VerifyResult.MD5_MISMATCH ->
                    BootDiagnosticStore.DROPPED_MD5_MISMATCH
                SignatureVerifier.VerifyResult.SIGNATURE_INVALID ->
                    BootDiagnosticStore.DROPPED_SIGNATURE_INVALID
                SignatureVerifier.VerifyResult.OK -> error("unreachable")
            }
            onDrop?.invoke(
                status,
                version,
                mapOf(
                    "blacklistMd5" to meta.optString("downloadMd5", expectedMd5),
                    "message" to "SignatureVerifier returned $verifyResult",
                )
            )
            deletePatch()
            return null
        }

        val hasAssets = meta.optBoolean("hasAssets", false)
        if (hasAssets && (!assetsDir.exists() || !assetsDir.isDirectory)) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_META_CORRUPTED,
                version,
                mapOf("message" to "patch meta requires assets but flutter_assets is missing")
            )
            deletePatch()
            return null
        }
        if (hasAssets && !File(assetsDir, ASSET_MANIFEST).exists()) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_META_CORRUPTED,
                version,
                mapOf("message" to "patch flutter_assets missing AssetManifest.bin")
            )
            deletePatch()
            return null
        }
        if (hasAssets && (!assetsArchive.exists() || !assetsArchive.isFile)) {
            onDrop?.invoke(
                BootDiagnosticStore.DROPPED_META_CORRUPTED,
                version,
                mapOf("message" to "patch asset archive missing")
            )
            deletePatch()
            return null
        }

        if (!patchFile.canRead()) patchFile.setReadable(true, false)
        if (hasAssets && !assetsArchive.canRead()) assetsArchive.setReadable(true, false)
        return ValidPatch(
            patchFile.absolutePath,
            if (hasAssets) assetsDir.absolutePath else null,
            if (hasAssets) assetsArchive.absolutePath else null,
            if (hasAssets) PATCH_ASSET_BUNDLE else null
        )
    }

    fun currentVersion(): String = readMeta()?.optString("version", "") ?: ""

    fun currentMeta(): Pair<String, String>? {
        val meta = readMeta() ?: return null
        val version = meta.optString("version", "")
        val md5 = meta.optString("downloadMd5", meta.optString("effectiveMd5", ""))
        if (version.isEmpty() || md5.isEmpty()) return null
        return version to md5
    }

    fun applyPatch(info: Map<String, Any?>): ApplyResult = synchronized(APPLY_LOCK) {
        val version = (info["version"] as? String).orEmpty()
        val url = (info["patchUrl"] as? String).orEmpty()
        val md5 = (info["md5"] as? String).orEmpty()
        val signature = (info["signature"] as? String).orEmpty()
        val mode = ((info["mode"] as? String) ?: MODE_FULL).lowercase()
        val hasTargetVersionCode = info.containsKey("targetVersionCode")
        val serverTargetVc = (info["targetVersionCode"] as? Number)?.toLong()
        if (hasTargetVersionCode && serverTargetVc == null) {
            return ApplyResult.failure(
                ApplyErrorCode.INVALID_ARGS,
                "targetVersionCode must be a number"
            )
        }

        val currentVc = PatcherConfig.currentVersionCode(context)
        validatePatchArgs(
            version = version,
            url = url,
            md5 = md5,
            mode = mode,
            targetVersionCode = serverTargetVc,
            currentVersionCode = currentVc
        )?.let { return it }
        if (serverTargetVc == null && currentVc == PatcherConfig.INVALID_VERSION_CODE) {
            return ApplyResult.failure(
                ApplyErrorCode.IO_ERROR,
                "cannot resolve current app versionCode"
            )
        }

        val blacklistHit = if (md5.isBlank()) {
            BlacklistStore.containsByVersion(context, version)
        } else {
            BlacklistStore.contains(context, version, md5)
        }
        if (blacklistHit) {
            return ApplyResult.failure(
                ApplyErrorCode.BLACKLISTED,
                "patch (version=$version, md5=$md5) was previously blacklisted"
            )
        }
        if (isSameInstalledPatch(currentMeta(), version, md5)) {
            Log.d(TAG, "patch $version with md5=$md5 already installed")
            return ApplyResult.SUCCESS
        }

        patchDir.mkdirs()
        val downloaded = File(patchDir, "temp_download.bin")
        var lastNetworkError: String? = null
        var actualMd5: String? = null

        for (attempt in 1..MAX_RETRIES) {
            try {
                progress?.invoke(Phase.DOWNLOADING, 0L, -1L)
                downloadTo(url, downloaded) { received, total ->
                    progress?.invoke(Phase.DOWNLOADING, received, total)
                }
                progress?.invoke(Phase.VERIFYING, 0L, 0L)
                val verifiedMd5 = SignatureVerifier.md5(downloaded)
                if (md5.isNotBlank()) {
                    if (!verifiedMd5.equals(md5, ignoreCase = true)) {
                        downloaded.delete()
                        return ApplyResult.failure(
                            ApplyErrorCode.MD5_MISMATCH,
                            "expected=$md5 actual=$verifiedMd5"
                        )
                    }
                    val publicKey = PatcherConfig.publicKey(context)
                    val strictSignature = PatcherConfig.strictSignature(context)
                    if (!SignatureVerifier.verifySignatureOnly(
                            verifiedMd5.lowercase(), signature, publicKey, strictSignature
                        )
                    ) {
                        downloaded.delete()
                        return ApplyResult.failure(
                            ApplyErrorCode.SIGNATURE_INVALID,
                            "ed25519 signature verify failed"
                        )
                    }
                } else {
                    Log.w(TAG, "expected md5 empty, skip md5 & signature verify")
                }
                actualMd5 = verifiedMd5.lowercase()
                break
            } catch (e: Exception) {
                Log.w(TAG, "attempt=$attempt failed: ${e.message}", e)
                lastNetworkError = e.message
                downloaded.delete()
                stagingDir.deleteRecursively()
                if (attempt < MAX_RETRIES) {
                    val backoff = 2000L * (1L shl (attempt - 1))
                    try {
                        Thread.sleep(backoff)
                    } catch (_: InterruptedException) {
                        return ApplyResult.failure(
                            ApplyErrorCode.NETWORK,
                            "interrupted during backoff"
                        )
                    }
                }
            }
        }

        val verifiedMd5 = actualMd5 ?: return ApplyResult.failure(
            ApplyErrorCode.NETWORK,
            "download failed after $MAX_RETRIES attempts: $lastNetworkError"
        )

        progress?.invoke(Phase.FINALIZING, 0L, 0L)
        val targetVersionCode = serverTargetVc ?: currentVc
        val result = try {
            if (isZipPayload(downloaded)) {
                installPackagePatch(
                    payload = downloaded,
                    version = version,
                    downloadMd5 = md5,
                    effectiveMd5 = verifiedMd5,
                    signature = signature,
                    targetVersionCode = targetVersionCode,
                )
            } else {
                installLegacyPatch(
                    downloaded = downloaded,
                    version = version,
                    downloadMd5 = md5,
                    effectiveMd5 = verifiedMd5,
                    signature = signature,
                    targetVersionCode = targetVersionCode,
                )
            }
        } catch (e: IOException) {
            ApplyResult.failure(ApplyErrorCode.IO_ERROR, e.message ?: e.javaClass.simpleName)
        } catch (e: Exception) {
            ApplyResult.failure(ApplyErrorCode.UNKNOWN, e.message ?: e.javaClass.simpleName)
        }
        downloaded.delete()
        stagingDir.deleteRecursively()
        if (result != null) return result

        CrashGuard(context).reset()
        Log.d(TAG, "patch $version ready, takes effect on next cold start")
        return ApplyResult.SUCCESS
    }

    // ========== Patch History Management ==========

    private fun ensureHistoryDirs() {
        historyDir.mkdirs()
        assetsHistoryDir.mkdirs()
    }

    private fun readHistoryIndex(): List<HistoryEntry> {
        if (!historyIndexFile.exists()) return emptyList()
        return try {
            val json = JSONObject(historyIndexFile.readText())
            val arr = json.optJSONArray("history") ?: return emptyList()
            (0 until arr.length()).mapNotNull { i ->
                val obj = arr.optJSONObject(i) ?: return@mapNotNull null
                HistoryEntry(
                    version = obj.optString("version", ""),
                    md5 = obj.optString("md5", ""),
                    path = obj.optString("path", ""),
                    assetsRef = obj.optInt("assetsRef", 0),
                    installedAt = obj.optLong("installedAt", 0)
                ).takeIf { it.version.isNotEmpty() && it.md5.isNotEmpty() && it.path.isNotEmpty() }
            }
        } catch (e: Exception) {
            Log.w(TAG, "failed to read history index", e)
            emptyList()
        }
    }

    private fun writeHistoryIndex(entries: List<HistoryEntry>) {
        ensureHistoryDirs()
        val json = JSONObject().put("history", JSONArray().apply {
            entries.forEach { entry ->
                put(JSONObject().apply {
                    put("version", entry.version)
                    put("md5", entry.md5)
                    put("path", entry.path)
                    put("assetsRef", entry.assetsRef)
                    put("installedAt", entry.installedAt)
                })
            }
        })
        writeTextSync(historyIndexFile, json.toString())
    }

    private fun archiveCurrentPatchToHistory(meta: JSONObject): Int {
        ensureHistoryDirs()

        val history = readHistoryIndex()
        val maxHistory = PatcherConfig.maxPatchHistory(context)

        // Determine next history slot (1-based, newest at front)
        val nextSlot = if (history.isEmpty()) 1 else history.first().path.split("/").last().toIntOrNull()?.plus(1) ?: history.size + 1
        val historyPath = "history/$nextSlot"
        val historyEntryDir = File(patchDir, historyPath)
        historyEntryDir.mkdirs()

        // Move current patch to history
        val currentVersion = meta.optString("version", "")
        val currentMd5 = meta.optString("effectiveMd5", meta.optString("downloadMd5", ""))
        val currentAssetsRef = meta.optInt("assetsRef", 0)

        if (patchFile.exists()) {
            patchFile.renameTo(File(historyEntryDir, "libapp_patch.so"))
        }
        if (metaFile.exists()) {
            metaFile.renameTo(File(historyEntryDir, "patch_meta.json"))
        }
        if (assetsDir.exists()) {
            assetsDir.renameTo(File(historyEntryDir, ASSET_DIR))
        }
        if (assetsArchive.exists()) {
            assetsArchive.renameTo(File(historyEntryDir, ASSET_ARCHIVE))
        }

        // Add to history index (newest first)
        val newEntry = HistoryEntry(
            version = currentVersion,
            md5 = currentMd5,
            path = historyPath,
            assetsRef = currentAssetsRef,
            installedAt = meta.optLong("installed_at", System.currentTimeMillis())
        )
        val updatedHistory = (listOf(newEntry) + history).take(maxHistory)
        writeHistoryIndex(updatedHistory)

        // Prune old history directories
        pruneOldHistoryDirectories(updatedHistory)

        return newEntry.assetsRef
    }

    private fun pruneOldHistoryDirectories(validEntries: List<HistoryEntry>) {
        val validPaths = validEntries.map { it.path }.toSet()
        historyDir.listFiles()?.forEach { dir ->
            if (dir.isDirectory && !validPaths.contains(dir.name)) {
                dir.deleteRecursively()
            }
        }
    }

    private fun extractBaseAssetsIfNeeded(): Int {
        // Extract base APK assets to assets/0/ if not already done
        if (!baseAssetsArchive.exists()) {
            baseAssetsArchive.parentFile?.mkdirs()
            try {
                copyInstalledFlutterAssets(File(assetsHistoryDir, "0"))
                writeFlutterAssetsArchive(File(assetsHistoryDir, "0"), baseAssetsArchive)
            } catch (e: Exception) {
                Log.w(TAG, "failed to extract base assets", e)
            }
        }
        return 0
    }

    private fun assetsChanged(newAssetsDir: File): Boolean {
        if (!assetsDir.exists()) return true
        if (!newAssetsDir.exists()) return false
        try {
            // Compare AssetManifest.bin to detect asset changes
            val oldManifest = File(assetsDir, ASSET_MANIFEST)
            val newManifest = File(newAssetsDir, ASSET_MANIFEST)
            if (!oldManifest.exists() || !newManifest.exists()) return true
            return !filesContentEqual(oldManifest, newManifest)
        } catch (e: Exception) {
            return true
        }
    }

    private fun filesContentEqual(f1: File, f2: File): Boolean {
        if (f1.length() != f2.length()) return false
        f1.inputStream().use { in1 ->
            f2.inputStream().use { in2 ->
                val buf1 = ByteArray(8192)
                val buf2 = ByteArray(8192)
                while (true) {
                    val n1 = in1.read(buf1)
                    val n2 = in2.read(buf2)
                    if (n1 != n2) return false
                    if (n1 == -1) return true
                    // Manual comparison since ByteArray.contentEquals doesn't support offset/length
                    var i = 0
                    while (i < n1) {
                        if (buf1[i] != buf2[i]) return false
                        i++
                    }
                }
            }
        }
    }

    private fun saveNewAssetsArchive(newAssetsDir: File, nextAssetsRef: Int): File {
        val assetsArchiveDir = File(assetsHistoryDir, nextAssetsRef.toString())
        assetsArchiveDir.mkdirs()
        val newArchive = File(assetsArchiveDir, ASSET_ARCHIVE)
        writeFlutterAssetsArchive(newAssetsDir, newArchive)
        return newArchive
    }

    fun rollbackToPrevious(): RollbackResult {
        val history = readHistoryIndex()
        if (history.isEmpty()) {
            Log.i(TAG, "no history available, falling back to base APK")
            deletePatch()
            CrashGuard(context).reset()
            return RollbackResult.FALLBACK_TO_BASE
        }

        for (entry in history) {
            // Skip blacklisted entries
            if (BlacklistStore.contains(context, entry.version, entry.md5)) {
                Log.w(TAG, "skipping blacklisted history entry: ${entry.version}")
                continue
            }

            val entryDir = File(patchDir, entry.path)
            val entrySo = File(entryDir, "libapp_patch.so")
            val entryMeta = File(entryDir, "patch_meta.json")
            val entryAssets = File(entryDir, ASSET_DIR)
            val entryAssetsArchive = File(entryDir, ASSET_ARCHIVE)

            if (!entrySo.exists() || !entryMeta.exists()) {
                Log.w(TAG, "history entry incomplete, skipping: ${entry.version}")
                continue
            }

            // Restore this entry as active patch
            if (patchFile.exists()) patchFile.delete()
            if (metaFile.exists()) metaFile.delete()
            if (assetsDir.exists()) assetsDir.deleteRecursively()
            if (assetsArchive.exists()) assetsArchive.delete()

            entrySo.renameTo(patchFile)
            entryMeta.renameTo(metaFile)

            val assetsArchiveRef = File(assetsHistoryDir, "${entry.assetsRef}/$ASSET_ARCHIVE")
            if (assetsArchiveRef.exists()) {
                assetsArchiveRef.copyTo(assetsArchive, overwrite = true)
            }
            if (entryAssets.exists()) {
                entryAssets.renameTo(assetsDir)
            } else if (assetsArchive.exists()) {
                // Extract assets from archive if directory missing
                try {
                    ZipFile(assetsArchive).use { zip ->
                        assetsDir.mkdirs()
                        val entries = zip.entries()
                        while (entries.hasMoreElements()) {
                            val ze = entries.nextElement()
                            if (!ze.isDirectory && ze.name.startsWith(PATCH_ASSETS_PREFIX)) {
                                val relative = ze.name.removePrefix(PATCH_ASSETS_PREFIX)
                                if (isSafeZipPath(relative)) {
                                    extractZipEntry(zip, ze, File(assetsDir, relative))
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "failed to extract assets from archive", e)
                }
            }

            // Remove from history
            val updatedHistory = history.filterNot { it.path == entry.path }
            writeHistoryIndex(updatedHistory)
            entryDir.deleteRecursively()

            // Prune unused asset archives
            pruneUnusedAssetArchives(updatedHistory)

            CrashGuard(context).reset()
            Log.i(TAG, "rolled back to previous patch: ${entry.version}")
            return RollbackResult.SUCCESS
        }

        // All history entries blacklisted
        Log.i(TAG, "all history entries blacklisted, falling back to base APK")
        deletePatch()
        CrashGuard(context).reset()
        return RollbackResult.FALLBACK_TO_BASE
    }

    private fun pruneUnusedAssetArchives(validEntries: List<HistoryEntry>) {
        val usedRefs = validEntries.map { it.assetsRef }.toSet()
        assetsHistoryDir.listFiles()?.forEach { dir ->
            if (dir.isDirectory && dir.name != "0") {
                val ref = dir.name.toIntOrNull()
                if (ref != null && ref !in usedRefs) {
                    dir.deleteRecursively()
                }
            }
        }
    }

    fun rollback() {
        deletePatch()
        CrashGuard(context).reset()
        Log.d(TAG, "rolled back to built-in version")
    }

    private fun installLegacyPatch(
        downloaded: File,
        version: String,
        downloadMd5: String,
        effectiveMd5: String,
        signature: String,
        targetVersionCode: Long,
    ): ApplyResult? {
        val meta = JSONObject().apply {
            put("version", version)
            put("downloadMd5", downloadMd5)
            put("effectiveMd5", effectiveMd5)
            put("signature", signature)
            put(PatcherConfig.META_KEY_TARGET_VERSION_CODE, targetVersionCode)
            put("hasAssets", false)
            put("installed_at", System.currentTimeMillis())
        }
        return finalizePatch(downloaded, null, null, meta)
    }

    private fun installPackagePatch(
        payload: File,
        version: String,
        downloadMd5: String,
        effectiveMd5: String,
        signature: String,
        targetVersionCode: Long,
    ): ApplyResult? {
        return try {
            ZipFile(payload).use { zip ->
            val packageManifest = readZipJson(zip, "manifest.json")
                ?: return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "patch.zip missing manifest.json"
                )
            if (packageManifest.optInt("schemaVersion", -1) != 2) {
                return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "unsupported package schemaVersion=${packageManifest.opt("schemaVersion")}"
                )
            }
            val packageTargetVc = packageManifest.optLong(
                "targetVersionCode",
                PatcherConfig.INVALID_VERSION_CODE
            )
            if (packageTargetVc != targetVersionCode) {
                return ApplyResult.failure(
                    ApplyErrorCode.INVALID_ARGS,
                    "package targetVersionCode=$packageTargetVc does not match current=$targetVersionCode"
                )
            }

            val lib = packageManifest.optJSONObject("lib")
                ?: return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "patch.zip manifest missing lib map"
                )
            val abi = selectPackageAbi(lib, Build.SUPPORTED_ABIS)
                ?: return ApplyResult.failure(
                    ApplyErrorCode.UNSUPPORTED_ABI,
                    "no libapp.so for device ABI ${Build.SUPPORTED_ABIS.joinToString(",")}"
                )
            val libInfo = lib.optJSONObject(abi)
                ?: return ApplyResult.failure(
                    ApplyErrorCode.UNSUPPORTED_ABI,
                    "lib info missing for $abi"
                )
            val libPath = libInfo.optString("path")
            if (!isSafeZipPath(libPath)) {
                return ApplyResult.failure(ApplyErrorCode.ASSET_PACKAGE_INVALID, "bad lib path")
            }
            val libEntry = zip.getEntry(libPath)
                ?: return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "missing $libPath"
                )
            val stagedSo = File(stagingDir, "libapp_patch.so")
            resetStaging()
            extractZipEntry(zip, libEntry, stagedSo)
            val installedLibMd5 = SignatureVerifier.md5(stagedSo)
            val expectedLibMd5 = libInfo.optString("md5")
            if (expectedLibMd5.isNotEmpty() &&
                !installedLibMd5.equals(expectedLibMd5, ignoreCase = true)
            ) {
                return ApplyResult.failure(
                    ApplyErrorCode.MD5_MISMATCH,
                    "lib md5 mismatch for $libPath"
                )
            }

            val assets = packageManifest.optJSONObject("assets")
            if (isDartOnlyAssets(assets)) {
                val meta = JSONObject().apply {
                    put("version", version)
                    put("downloadMd5", downloadMd5)
                    put("effectiveMd5", installedLibMd5)
                    put("signature", "")
                    put("payloadMd5", effectiveMd5)
                    put("payloadSignature", signature)
                    put(PatcherConfig.META_KEY_TARGET_VERSION_CODE, targetVersionCode)
                    put("hasAssets", false)
                    put("installed_at", System.currentTimeMillis())
                }
                return finalizePatch(stagedSo, null, null, meta)
            }
            if (assets!!.optString("mode") != "overlay") {
                return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "unsupported assets.mode=${assets.optString("mode")}"
                )
            }

            val stagingAssets = File(stagingDir, ASSET_DIR)
            val installedAssetBytes = installedFlutterAssetsSize()
            val requiredBytes = installedAssetBytes + payload.length() + MIN_FREE_SPACE_BUFFER
            if (patchDir.usableSpace < requiredBytes) {
                return ApplyResult.failure(
                    ApplyErrorCode.IO_ERROR,
                    "not enough free space for asset patch"
                )
            }

            copyInstalledFlutterAssets(stagingAssets)
            overlayPatchAssets(zip, assets, stagingAssets)
            applyManifestPatch(zip, assets, stagingAssets)
            verifyOverlayFiles(assets, stagingAssets)?.let { return it }
            val stagedAssetsArchive = File(stagingDir, ASSET_ARCHIVE)
            writeFlutterAssetsArchive(stagingAssets, stagedAssetsArchive)

            val meta = JSONObject().apply {
                put("version", version)
                put("downloadMd5", downloadMd5)
                put("effectiveMd5", installedLibMd5)
                put("signature", "")
                put("payloadMd5", effectiveMd5)
                put("payloadSignature", signature)
                put(PatcherConfig.META_KEY_TARGET_VERSION_CODE, targetVersionCode)
                put("hasAssets", true)
                put("assetMode", "overlay")
                put("installed_at", System.currentTimeMillis())
            }
            return finalizePatch(stagedSo, stagingAssets, stagedAssetsArchive, meta)
            }
        } catch (e: PatchInstallException) {
            ApplyResult.failure(e.code, e.message)
        } catch (e: ZipException) {
            ApplyResult.failure(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                e.message ?: "invalid patch.zip"
            )
        } catch (e: JSONException) {
            ApplyResult.failure(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                e.message ?: "invalid patch package json"
            )
        } catch (e: IOException) {
            ApplyResult.failure(
                ApplyErrorCode.IO_ERROR,
                e.message ?: e.javaClass.simpleName
            )
        } catch (e: ClassCastException) {
            ApplyResult.failure(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                e.message ?: "invalid manifest patch type"
            )
        } catch (e: IllegalArgumentException) {
            ApplyResult.failure(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                e.message ?: "invalid patch package"
            )
        }
    }

    private fun resetStaging() {
        stagingDir.deleteRecursively()
        stagingDir.mkdirs()
    }

    private fun finalizePatch(
        finalSo: File,
        finalAssets: File?,
        finalAssetsArchive: File?,
        meta: JSONObject
    ): ApplyResult? {
        var committed = false
        var backedSo = false
        var backedMeta = false
        var backedAssets = false
        var backedAssetsArchive = false
        var promotedSo = false
        var promotedMeta = false
        var promotedAssets = false
        var promotedAssetsArchive = false
        return try {
            cleanupPreparedArtifacts(includePrevious = true)
            installMarkerFile.delete()

            // Archive current patch to history BEFORE committing new one
            var assetsRef = 0
            if (patchFile.exists() && metaFile.exists()) {
                // Read current meta to get its assetsRef
                val currentMeta = readMeta()
                val currentAssetsRef = currentMeta?.optInt("assetsRef", 0) ?: 0

                // Check if new assets are different from current
                val newAssetsChanged = finalAssets != null && assetsChanged(finalAssets)

                if (newAssetsChanged) {
                    // Save new assets to history and get new ref
                    val history = readHistoryIndex()
                    val nextAssetsRef = if (history.isEmpty()) 1 else (history.map { it.assetsRef }.maxOrNull() ?: 0) + 1
                    val maxAssetHistory = PatcherConfig.maxAssetHistory(context)
                    if (nextAssetsRef <= maxAssetHistory) {
                        saveNewAssetsArchive(finalAssets, nextAssetsRef)
                        assetsRef = nextAssetsRef
                    } else {
                        assetsRef = currentAssetsRef // reuse if at limit
                    }
                } else {
                    // Reuse current assets reference
                    assetsRef = currentAssetsRef
                }

                // Archive current patch to history
                meta.put("assetsRef", assetsRef)
                archiveCurrentPatchToHistory(meta)
            } else {
                // First patch ever - extract base assets
                assetsRef = extractBaseAssetsIfNeeded()
                meta.put("assetsRef", assetsRef)
            }

            if (!finalSo.renameTo(pendingSo)) {
                copyFile(finalSo, pendingSo)
                finalSo.delete()
            }
            if (finalAssets != null) {
                if (!finalAssets.renameTo(pendingAssets)) {
                    copyDirectory(finalAssets, pendingAssets)
                    finalAssets.deleteRecursively()
                }
            }
            if (finalAssetsArchive != null) {
                if (!finalAssetsArchive.renameTo(pendingAssetsArchive)) {
                    copyFile(finalAssetsArchive, pendingAssetsArchive)
                    finalAssetsArchive.delete()
                }
            }

            writeTextSync(pendingMeta, meta.toString())
            writeTextSync(installMarkerFile, "installing")

            // No need to backup to .previous anymore since we archived to history
            // Just clean up any existing .previous files
            previousSo.delete()
            previousMeta.delete()
            previousAssets.deleteRecursively()
            previousAssetsArchive.delete()

            if (!pendingSo.renameTo(patchFile)) {
                throw PatchInstallException(
                    ApplyErrorCode.IO_ERROR,
                    "rename to ${patchFile.absolutePath} failed"
                )
            }
            promotedSo = true

            if (finalAssets != null) {
                if (!pendingAssets.renameTo(assetsDir)) {
                    throw PatchInstallException(
                        ApplyErrorCode.IO_ERROR,
                        "rename to ${assetsDir.absolutePath} failed"
                    )
                }
                promotedAssets = true
            }
            if (finalAssetsArchive != null) {
                if (!pendingAssetsArchive.renameTo(assetsArchive)) {
                    throw PatchInstallException(
                        ApplyErrorCode.IO_ERROR,
                        "rename to ${assetsArchive.absolutePath} failed"
                    )
                }
                promotedAssetsArchive = true
            }

            if (!pendingMeta.renameTo(metaFile)) {
                throw PatchInstallException(
                    ApplyErrorCode.IO_ERROR,
                    "rename to ${metaFile.absolutePath} failed"
                )
            }
            promotedMeta = true

            committed = true
            cleanupPreparedArtifacts(includePrevious = true)
            null
        } catch (e: PatchInstallException) {
            Log.e(TAG, "finalize patch failed", e)
            rollbackPreparedCommit(
                promotedSo = promotedSo,
                promotedMeta = promotedMeta,
                promotedAssets = promotedAssets,
                promotedAssetsArchive = promotedAssetsArchive,
                backedSo = backedSo,
                backedMeta = backedMeta,
                backedAssets = backedAssets,
                backedAssetsArchive = backedAssetsArchive,
            )
            ApplyResult.failure(e.code, e.message)
        } catch (e: Exception) {
            Log.e(TAG, "finalize patch failed", e)
            rollbackPreparedCommit(
                promotedSo = promotedSo,
                promotedMeta = promotedMeta,
                promotedAssets = promotedAssets,
                promotedAssetsArchive = promotedAssetsArchive,
                backedSo = backedSo,
                backedMeta = backedMeta,
                backedAssets = backedAssets,
                backedAssetsArchive = backedAssetsArchive,
            )
            ApplyResult.failure(ApplyErrorCode.IO_ERROR, e.message ?: e.javaClass.simpleName)
        } finally {
            cleanupPreparedArtifacts(includePrevious = committed)
            stagingDir.deleteRecursively()
            installMarkerFile.delete()
        }
    }

    private fun readZipJson(zip: ZipFile, path: String): JSONObject? {
        val entry = zip.getEntry(path) ?: return null
        return JSONObject(zip.getInputStream(entry).bufferedReader(Charsets.UTF_8).readText())
    }

    private fun extractZipEntry(zip: ZipFile, entry: java.util.zip.ZipEntry, dest: File) {
        if (!isSafeZipPath(entry.name)) {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "unsafe zip path: ${entry.name}"
            )
        }
        dest.parentFile?.mkdirs()
        zip.getInputStream(entry).use { input ->
            FileOutputStream(dest).use { output ->
                input.copyTo(output)
                output.fd.sync()
            }
        }
    }

    private fun copyInstalledFlutterAssets(dest: File) {
        try {
            dest.deleteRecursively()
            dest.mkdirs()
            for (apkPath in installedApkPaths()) {
                ZipFile(apkPath).use { zip ->
                    val entries = zip.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        if (entry.isDirectory) continue
                        if (!entry.name.startsWith(FLUTTER_ASSETS_PREFIX)) continue
                        val relative = entry.name.removePrefix(FLUTTER_ASSETS_PREFIX)
                        if (!isSafeZipPath(relative)) continue
                        extractZipEntry(zip, entry, File(dest, relative))
                    }
                }
            }
        } catch (e: IOException) {
            throw PatchInstallException(
                ApplyErrorCode.IO_ERROR,
                e.message ?: "copy installed flutter_assets failed",
                e
            )
        }
    }

    private fun installedFlutterAssetsSize(): Long {
        try {
            var total = 0L
            for (apkPath in installedApkPaths()) {
                ZipFile(apkPath).use { zip ->
                    val entries = zip.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        if (!entry.isDirectory && entry.name.startsWith(FLUTTER_ASSETS_PREFIX)) {
                            total += entry.size.coerceAtLeast(0L)
                        }
                    }
                }
            }
            return total
        } catch (e: IOException) {
            throw PatchInstallException(
                ApplyErrorCode.IO_ERROR,
                e.message ?: "scan installed flutter_assets failed",
                e
            )
        }
    }

    private fun installedApkPaths(): List<String> {
        val info = context.applicationInfo
        val paths = mutableListOf<String>()
        paths.add(info.sourceDir)
        info.splitSourceDirs?.forEach { paths.add(it) }
        return paths.filter { it.isNotBlank() }
    }

    private fun overlayPatchAssets(zip: ZipFile, assets: JSONObject, stagingAssets: File) {
        val prefix = assets.optString("prefix", "assets/")
        if (!isSafeZipPath(prefix.trimEnd('/'))) {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "unsafe assets prefix: $prefix"
            )
        }
        val files = assets.optJSONArray("files") ?: JSONArray()
        for (i in 0 until files.length()) {
            val file = files.getJSONObject(i)
            val path = file.optString("path")
            if (!isSafeZipPath(path)) {
                throw PatchInstallException(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "unsafe asset path: $path"
                )
            }
            val entryName = "$prefix$path"
            val entry = zip.getEntry(entryName)
                ?: throw PatchInstallException(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "missing asset entry: $entryName"
                )
            extractZipEntry(zip, entry, File(stagingAssets, path))
        }
    }

    private fun verifyOverlayFiles(assets: JSONObject, stagingAssets: File): ApplyResult? {
        val files = assets.optJSONArray("files") ?: JSONArray()
        for (i in 0 until files.length()) {
            val file = files.getJSONObject(i)
            val path = file.optString("path")
            val expectedMd5 = file.optString("md5")
            if (expectedMd5.isEmpty()) continue
            val actualFile = File(stagingAssets, path)
            if (!actualFile.exists()) {
                return ApplyResult.failure(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "asset missing after overlay: $path"
                )
            }
            val actualMd5 = SignatureVerifier.md5(actualFile)
            if (!actualMd5.equals(expectedMd5, ignoreCase = true)) {
                return ApplyResult.failure(
                    ApplyErrorCode.MD5_MISMATCH,
                    "asset md5 mismatch for $path"
                )
            }
        }
        return null
    }

    private fun applyManifestPatch(zip: ZipFile, assets: JSONObject, stagingAssets: File) {
        val patchPath = assets.optString("manifestPatch", "manifest_patch.json")
        if (!isSafeZipPath(patchPath)) {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "unsafe manifest patch path"
            )
        }
        val patch = readZipJson(zip, patchPath)
            ?: throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "missing manifest patch: $patchPath"
            )
        if (patch.optInt("schemaVersion", -1) != 1) {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "unsupported manifest_patch schemaVersion"
            )
        }
        if (patch.optString("manifestFormat") != "bin") {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "unsupported manifest format"
            )
        }

        val manifestFile = File(stagingAssets, ASSET_MANIFEST)
        if (!manifestFile.exists()) {
            throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "AssetManifest.bin missing"
            )
        }
        val expectedSize = patch.optLong("baseManifestSize", -1)
        if (expectedSize >= 0 && expectedSize != manifestFile.length()) {
            Log.w(TAG, "baseManifestSize mismatch: patch=$expectedSize actual=${manifestFile.length()}")
        }

        val decoded = StandardMessageCodec.INSTANCE.decodeMessage(
            ByteBuffer.wrap(manifestFile.readBytes())
        )
        @Suppress("UNCHECKED_CAST")
        val manifest = LinkedHashMap<String, Any?>(
            decoded as? Map<String, Any?> ?: throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "AssetManifest.bin is not a map"
            )
        )
        val operations = patch.optJSONArray("operations")
            ?: throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "manifest patch operations missing"
            )
        for (i in 0 until operations.length()) {
            val op = operations.getJSONObject(i)
            when (op.optString("op")) {
                "upsert" -> {
                    val key = op.optString("key")
                    if (!isSafeZipPath(key)) {
                        throw PatchInstallException(
                            ApplyErrorCode.ASSET_PACKAGE_INVALID,
                            "unsafe manifest key: $key"
                        )
                    }
                    manifest[key] = jsonArrayToList(op.getJSONArray("variants"))
                }
                else -> throw PatchInstallException(
                    ApplyErrorCode.ASSET_PACKAGE_INVALID,
                    "unsupported manifest patch op: ${op.optString("op")}"
                )
            }
        }
        val encoded = StandardMessageCodec.INSTANCE.encodeMessage(manifest)
            ?: throw PatchInstallException(
                ApplyErrorCode.ASSET_PACKAGE_INVALID,
                "failed to encode AssetManifest.bin"
            )
        val bytes = codecBufferToByteArray(encoded)
        FileOutputStream(manifestFile).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
    }

    private fun jsonArrayToList(array: JSONArray): List<Any?> {
        val list = ArrayList<Any?>(array.length())
        for (i in 0 until array.length()) {
            list.add(jsonToPlain(array.get(i)))
        }
        return list
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = jsonToPlain(json.get(key))
        }
        return map
    }

    private fun jsonToPlain(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }
    }

    private fun writeTextSync(file: File, text: String) {
        FileOutputStream(file).use { output ->
            output.write(text.toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
    }

    private fun downloadTo(
        url: String,
        dest: File,
        onBytes: ((received: Long, total: Long) -> Unit)? = null
    ) {
        val parsed = URL(url)
        when (parsed.protocol?.lowercase()) {
            "http", "https" -> downloadHttp(parsed, dest, onBytes)
            "file" -> copyFromFile(parsed, dest, onBytes)
            else -> throw RuntimeException("unsupported URL scheme: ${parsed.protocol}")
        }
    }

    private fun downloadHttp(
        url: URL,
        dest: File,
        onBytes: ((received: Long, total: Long) -> Unit)?
    ) {
        val conn = url.openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = CONNECT_TIMEOUT_MS
            conn.readTimeout = READ_TIMEOUT_MS
            conn.requestMethod = "GET"
            val code = conn.responseCode
            if (code !in 200..299) throw RuntimeException("HTTP $code")
            streamToFile(conn.inputStream, dest, conn.contentLengthLong, onBytes)
        } finally {
            conn.disconnect()
        }
    }

    private fun copyFromFile(
        url: URL,
        dest: File,
        onBytes: ((received: Long, total: Long) -> Unit)?
    ) {
        val src = File(url.path)
        if (!src.exists()) throw RuntimeException("file not found: ${src.absolutePath}")
        if (!src.canRead()) throw RuntimeException("file not readable: ${src.absolutePath}")
        streamToFile(src.inputStream(), dest, src.length(), onBytes)
    }

    private fun streamToFile(
        input: java.io.InputStream,
        dest: File,
        total: Long,
        onBytes: ((received: Long, total: Long) -> Unit)?
    ) {
        var received = 0L
        var lastEmit = 0L
        input.use { ins ->
            FileOutputStream(dest).use { output ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = ins.read(buf)
                    if (n <= 0) break
                    output.write(buf, 0, n)
                    received += n
                    if (onBytes != null) {
                        val now = SystemClock.uptimeMillis()
                        if (now - lastEmit >= PROGRESS_EMIT_INTERVAL_MS) {
                            onBytes(received, total)
                            lastEmit = now
                        }
                    }
                }
                output.fd.sync()
            }
        }
        onBytes?.invoke(received, total)
    }

    private fun copyFile(src: File, dest: File) {
        dest.parentFile?.mkdirs()
        src.inputStream().use { input ->
            FileOutputStream(dest).use { output ->
                input.copyTo(output)
                output.fd.sync()
            }
        }
    }

    private fun copyDirectory(src: File, dest: File) {
        src.walkTopDown().forEach { file ->
            val relative = file.relativeTo(src).path
            val target = File(dest, relative)
            if (file.isDirectory) {
                target.mkdirs()
            } else {
                copyFile(file, target)
            }
        }
    }

    private fun writeFlutterAssetsArchive(src: File, dest: File) {
        dest.parentFile?.mkdirs()
        ZipOutputStream(FileOutputStream(dest)).use { zip ->
            src.walkTopDown().forEach { file ->
                if (!file.isFile) return@forEach
                val relative = file.relativeTo(src).invariantSeparatorsPath
                if (!isSafeZipPath(relative)) {
                    throw PatchInstallException(
                        ApplyErrorCode.ASSET_PACKAGE_INVALID,
                        "unsafe staged asset path: $relative"
                    )
                }
                val entry = ZipEntry("$PATCH_ASSETS_PREFIX$relative")
                zip.putNextEntry(entry)
                file.inputStream().use { input -> input.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    private fun cleanupPreparedArtifacts(includePrevious: Boolean) {
        pendingSo.delete()
        pendingMeta.delete()
        pendingAssets.deleteRecursively()
        pendingAssetsArchive.delete()
        if (includePrevious) {
            previousSo.delete()
            previousMeta.delete()
            previousAssets.deleteRecursively()
            previousAssetsArchive.delete()
        }
    }

    private fun recoverInterruptedInstall() {
        val backedSo = previousSo.exists()
        val backedMeta = previousMeta.exists()
        val backedAssets = previousAssets.exists()
        val backedAssetsArchive = previousAssetsArchive.exists()
        if (backedSo || backedMeta || backedAssets || backedAssetsArchive) {
            rollbackPreparedCommit(
                promotedSo = backedSo,
                promotedMeta = backedMeta,
                promotedAssets = backedAssets,
                promotedAssetsArchive = backedAssetsArchive,
                backedSo = backedSo,
                backedMeta = backedMeta,
                backedAssets = backedAssets,
                backedAssetsArchive = backedAssetsArchive,
            )
        } else {
            cleanupPreparedArtifacts(includePrevious = false)
            if (!patchFile.exists() || !metaFile.exists()) {
                patchFile.delete()
                metaFile.delete()
                assetsDir.deleteRecursively()
                assetsArchive.delete()
            }
        }
        installMarkerFile.delete()
    }

    private fun rollbackPreparedCommit(
        promotedSo: Boolean,
        promotedMeta: Boolean,
        promotedAssets: Boolean,
        promotedAssetsArchive: Boolean,
        backedSo: Boolean,
        backedMeta: Boolean,
        backedAssets: Boolean,
        backedAssetsArchive: Boolean,
    ) {
        if (promotedSo) patchFile.delete()
        if (backedSo && previousSo.exists()) previousSo.renameTo(patchFile)

        if (promotedAssets) assetsDir.deleteRecursively()
        if (backedAssets && previousAssets.exists()) previousAssets.renameTo(assetsDir)

        if (promotedAssetsArchive) assetsArchive.delete()
        if (backedAssetsArchive && previousAssetsArchive.exists()) {
            previousAssetsArchive.renameTo(assetsArchive)
        }

        if (promotedMeta) metaFile.delete()
        if (backedMeta && previousMeta.exists()) previousMeta.renameTo(metaFile)

        cleanupPreparedArtifacts(includePrevious = true)
    }

    private fun deletePatch() {
        if (patchDir.exists()) patchDir.deleteRecursively()
    }

    private fun readMeta(): JSONObject? {
        if (!metaFile.exists()) return null
        return try {
            JSONObject(metaFile.readText())
        } catch (_: Exception) {
            null
        }
    }
}

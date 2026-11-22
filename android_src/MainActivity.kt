package com.woustore.woustore

import android.Manifest
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.Executors

/**
 * Tout ce qui doit continuer même quand WouStore est fermé :
 * téléchargement (par le gestionnaire de téléchargements d'Android),
 * installation (Shizuku ou installateur Android) et notifications.
 */
object Installer {
    const val NOTIF_CHANNEL = "woustore"
    const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    /** Le lien avec l'écran de WouStore, quand il est ouvert. */
    var channel: MethodChannel? = null
    var resumed = false

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var notifId = 100

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("woustore", Context.MODE_PRIVATE)

    private fun apkFile(ctx: Context, pkg: String) =
        File(ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "$pkg.apk")

    // ---------- Téléchargement ----------

    fun startDownload(ctx: Context, url: String, pkg: String, name: String): Long {
        val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val old = prefs(ctx).all.entries.firstOrNull { it.key.startsWith("dl_") && (it.value as? String)?.startsWith("$pkg|") == true }
        if (old != null) {
            dm.remove(old.key.removePrefix("dl_").toLong())
            prefs(ctx).edit().remove(old.key).apply()
        }
        apkFile(ctx, pkg).delete()
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(name)
            .setDescription("Téléchargement par WouStore")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(ctx, Environment.DIRECTORY_DOWNLOADS, "$pkg.apk")
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .addRequestHeader("User-Agent", "WouStore")
        val id = dm.enqueue(request)
        prefs(ctx).edit().putString("dl_$id", "$pkg|$name").apply()
        return id
    }

    fun status(ctx: Context, id: Long): Map<String, Any?> {
        val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        dm.query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (!c.moveToFirst()) return mapOf("status" to "gone")
            val st = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val got = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val reason = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val text = when (st) {
                DownloadManager.STATUS_SUCCESSFUL -> "done"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_PENDING -> "pending"
                else -> "running"
            }
            return mapOf("status" to text, "received" to got, "total" to total, "reason" to reason)
        }
    }

    fun cancel(ctx: Context, id: Long) {
        val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        dm.remove(id)
        prefs(ctx).edit().remove("dl_$id").apply()
    }

    /** Les téléchargements en cours : id → paquet. */
    fun pending(ctx: Context): List<Map<String, Any>> =
        prefs(ctx).all.entries.filter { it.key.startsWith("dl_") }.map {
            mapOf("id" to it.key.removePrefix("dl_").toLong(), "package" to (it.value as String).substringBefore("|"))
        }

    /** Appelé par Android quand un téléchargement se termine, même si WouStore est fermé. */
    fun onDownloadComplete(ctx: Context, id: Long, finished: () -> Unit) {
        val info = prefs(ctx).getString("dl_$id", null)
        if (info == null) {
            finished()
            return
        }
        prefs(ctx).edit().remove("dl_$id").apply()
        val pkg = info.substringBefore("|")
        val name = info.substringAfter("|")
        val st = status(ctx, id)
        if (st["status"] != "done") {
            done(ctx, pkg, name, false, "Le téléchargement a échoué. Vérifie ta connexion et réessaie.")
            finished()
            return
        }
        install(ctx, apkFile(ctx, pkg), pkg, name, finished)
    }

    // ---------- Installation ----------

    private fun install(ctx: Context, file: File, pkg: String, name: String, finished: () -> Unit) {
        io.execute {
            try {
                if (waitForShizuku(ctx) == "ready") {
                    val out = runShizuku(arrayOf("pm", "install", "-r", "-S", file.length().toString()), file)
                    if (out.contains("Success")) {
                        done(ctx, pkg, name, true, null)
                    } else {
                        done(ctx, pkg, name, false, "Shizuku n'a pas pu installer : " + out.trim().take(200))
                    }
                } else {
                    installWithSession(ctx, file, pkg, name)
                }
            } catch (e: Throwable) {
                done(ctx, pkg, name, false, "L'installation a échoué : ${e.message}")
            } finally {
                finished()
            }
        }
    }

    private fun installWithSession(ctx: Context, file: File, pkg: String, name: String) {
        val installer = ctx.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("app.apk", 0, file.length()).use { out ->
                file.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(ctx, InstallResultReceiver::class.java)
                .putExtra("woustore_pkg", pkg)
                .putExtra("woustore_name", name)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
            val sender = PendingIntent.getBroadcast(ctx, sessionId, intent, flags)
            session.commit(sender.intentSender)
        }
    }

    fun onInstallResult(ctx: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val pkg = intent.getStringExtra("woustore_pkg") ?: ""
        val name = intent.getStringExtra("woustore_name") ?: "L'appli"
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (resumed) {
                    ctx.startActivity(confirm)
                } else {
                    notify(ctx, "$name est prêt à installer", "Touche ici pour terminer l'installation.", confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> done(ctx, pkg, name, true, null)
            PackageInstaller.STATUS_FAILURE_ABORTED -> done(ctx, pkg, name, false, "Installation annulée.")
            PackageInstaller.STATUS_FAILURE_CONFLICT ->
                done(ctx, pkg, name, false, "Une autre version de $name est déjà installée. Désinstalle-la d'abord.")
            PackageInstaller.STATUS_FAILURE_STORAGE -> done(ctx, pkg, name, false, "Pas assez d'espace sur le téléphone.")
            else -> done(ctx, pkg, name, false,
                "L'installation a échoué. " + (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""))
        }
    }

    private fun done(ctx: Context, pkg: String, name: String, ok: Boolean, message: String?) {
        main.post {
            channel?.invokeMethod("installResult", mapOf("package" to pkg, "ok" to ok, "message" to message))
            if (!resumed) {
                if (ok) {
                    notify(ctx, "$name est installé", "Touche ici pour l'ouvrir.",
                        ctx.packageManager.getLaunchIntentForPackage(pkg))
                } else {
                    notify(ctx, "Échec pour $name", message ?: "", null)
                }
            }
        }
        if (ok) apkFile(ctx, pkg).delete()
    }

    // ---------- Shizuku ----------

    fun shizukuStatus(ctx: Context): String {
        if (versionOf(ctx, SHIZUKU_PACKAGE) == null) return "absent"
        return try {
            when {
                !Shizuku.pingBinder() -> "off"
                Shizuku.isPreV11() -> "old"
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> "ready"
                Shizuku.shouldShowRequestPermissionRationale() -> "denied"
                else -> "ask"
            }
        } catch (e: Throwable) {
            "off"
        }
    }

    /** Quand WouStore vient d'être réveillé, Shizuku met un instant à répondre. */
    private fun waitForShizuku(ctx: Context): String {
        var st = shizukuStatus(ctx)
        var tries = 0
        while (st == "off" && tries < 15) {
            Thread.sleep(300)
            st = shizukuStatus(ctx)
            tries++
        }
        return st
    }

    /** Lance une commande avec les droits ADB de Shizuku ; [input] est envoyé sur son entrée. */
    fun runShizuku(cmd: Array<String>, input: File?): String {
        // newProcess est privé depuis Shizuku 13 : on l'appelle par réflexion.
        val method = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java
        )
        method.isAccessible = true
        val process = method.invoke(null, cmd, null, null) as Process
        process.outputStream.use { out ->
            input?.inputStream()?.use { it.copyTo(out) }
        }
        val text = process.inputStream.bufferedReader().readText()
        val err = process.errorStream.bufferedReader().readText()
        process.waitFor()
        return text + err
    }

    // ---------- Divers ----------

    fun versionOf(ctx: Context, pkg: String): String? {
        return try {
            ctx.packageManager.getPackageInfo(pkg, 0).versionName ?: ""
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    fun createChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(NOTIF_CHANNEL, "Installations", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }

    fun notify(ctx: Context, title: String, text: String, target: Intent?) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        createChannel(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
        if (target != null) {
            target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pi = PendingIntent.getActivity(
                ctx, notifId, target,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setContentIntent(pi)
        }
        nm.notify(notifId++, builder.build())
    }
}

/** Android prévient ici quand un téléchargement est fini, même WouStore fermé. */
class DownloadDoneReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (id < 0) return
        val pending = goAsync()
        Installer.onDownloadComplete(ctx.applicationContext, id) { pending.finish() }
    }
}

/** Résultat de l'installateur Android. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Installer.onInstallResult(ctx.applicationContext, intent)
    }
}

class MainActivity : FlutterActivity() {
    private val channelName = "woustore/installer"
    private val shizukuCode = 241

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val shizukuPermissionListener = Shizuku.OnRequestPermissionResultListener { _, _ -> shizukuChanged() }
    private val shizukuBinderListener = Shizuku.OnBinderReceivedListener { shizukuChanged() }
    private val shizukuDeadListener = Shizuku.OnBinderDeadListener { shizukuChanged() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Installer.createChannel(this)
        try {
            Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
            Shizuku.addBinderReceivedListenerSticky(shizukuBinderListener)
            Shizuku.addBinderDeadListener(shizukuDeadListener)
        } catch (e: Throwable) {
        }
    }

    override fun onDestroy() {
        try {
            Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
            Shizuku.removeBinderReceivedListener(shizukuBinderListener)
            Shizuku.removeBinderDeadListener(shizukuDeadListener)
        } catch (e: Throwable) {
        }
        Installer.channel = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        Installer.resumed = true
    }

    override fun onPause() {
        Installer.resumed = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        Installer.channel = ch
        ch.setMethodCallHandler { call, result ->
            val pkgArg = call.argument<String>("package") ?: ""
            when (call.method) {
                "download" -> {
                    try {
                        result.success(
                            Installer.startDownload(this, call.argument<String>("url") ?: "", pkgArg,
                                call.argument<String>("name") ?: "L'appli")
                        )
                    } catch (e: Throwable) {
                        result.error("DOWNLOAD", "Le téléchargement n'a pas pu démarrer : ${e.message}", null)
                    }
                }
                "downloadStatus" -> result.success(Installer.status(this, (call.argument<Number>("id") ?: -1).toLong()))
                "cancelDownload" -> {
                    Installer.cancel(this, (call.argument<Number>("id") ?: -1).toLong())
                    result.success(null)
                }
                "pendingDownloads" -> result.success(Installer.pending(this))
                "installedVersion" -> result.success(Installer.versionOf(this, pkgArg))
                "installedInfo" -> result.success(infoOf(pkgArg))
                "selfPackage" -> result.success(packageName)
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "uninstall" -> {
                    val useShizuku = call.argument<Boolean>("shizuku") ?: false
                    if (useShizuku && Installer.shizukuStatus(this) == "ready") {
                        io.execute {
                            val out = try {
                                Installer.runShizuku(arrayOf("pm", "uninstall", pkgArg), null)
                            } catch (e: Throwable) {
                                e.message ?: ""
                            }
                            main.post {
                                result.success(null)
                                Installer.channel?.invokeMethod(
                                    "uninstallResult", mapOf("package" to pkgArg, "ok" to out.contains("Success"))
                                )
                            }
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        val intent = Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkgArg"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                }
                "open" -> {
                    val launch = packageManager.getLaunchIntentForPackage(pkgArg)
                    if (launch != null) startActivity(launch)
                    result.success(launch != null)
                }
                "icon" -> result.success(iconOf(pkgArg))
                "askNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                "shizukuStatus" -> result.success(Installer.shizukuStatus(this))
                "shizukuRequest" -> {
                    try {
                        Shizuku.requestPermission(shizukuCode)
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "openShizuku" -> {
                    val launch = packageManager.getLaunchIntentForPackage(Installer.SHIZUKU_PACKAGE)
                    if (launch != null) startActivity(launch)
                    result.success(launch != null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun shizukuChanged() {
        main.post { Installer.channel?.invokeMethod("shizukuChanged", null) }
    }

    private fun infoOf(pkg: String): Map<String, Any?>? {
        return try {
            val info = packageManager.getPackageInfo(pkg, 0)
            val code = if (Build.VERSION.SDK_INT >= 28) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            mapOf(
                "versionName" to (info.versionName ?: ""),
                "versionCode" to code,
                "updatedAt" to info.lastUpdateTime
            )
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    /** L'icône de l'appli installée, telle que le téléphone l'affiche, en PNG. */
    private fun iconOf(pkg: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(pkg)
            val size = 192
            val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        } catch (e: Throwable) {
            null
        }
    }
}

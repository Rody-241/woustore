package com.woustore.woustore

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.Executors

/**
 * Partie Android de WouStore : installation des applis.
 *  - Téléphone normal : installateur Android (fenêtre « Installer cette appli ? »).
 *  - Shizuku actif et autorisé : installation directe avec « pm install ».
 */
class MainActivity : FlutterActivity() {
    private val channelName = "woustore/installer"
    private val actionResult = "com.woustore.INSTALL_RESULT"
    private val shizukuPackage = "moe.shizuku.privileged.api"
    private val shizukuCode = 241
    private val notifChannel = "woustore"

    private var channel: MethodChannel? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var resumed = false
    private var notifId = 100

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            val pkg = intent.getStringExtra("woustore_pkg") ?: ""
            val name = intent.getStringExtra("woustore_name") ?: "L'appli"
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (resumed) {
                        startActivity(confirm)
                    } else {
                        notify("$name est prêt à installer", "Touche ici pour terminer l'installation.", confirm)
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> done(pkg, name, true, null)
                PackageInstaller.STATUS_FAILURE_ABORTED -> done(pkg, name, false, "Installation annulée.")
                PackageInstaller.STATUS_FAILURE_CONFLICT ->
                    done(pkg, name, false, "Une autre version de $name est déjà installée. Désinstalle-la d'abord.")
                PackageInstaller.STATUS_FAILURE_STORAGE -> done(pkg, name, false, "Pas assez d'espace sur le téléphone.")
                else -> done(pkg, name, false,
                    "L'installation a échoué. " + (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""))
            }
        }
    }

    private val shizukuPermissionListener = Shizuku.OnRequestPermissionResultListener { _, _ -> shizukuChanged() }
    private val shizukuBinderListener = Shizuku.OnBinderReceivedListener { shizukuChanged() }
    private val shizukuDeadListener = Shizuku.OnBinderDeadListener { shizukuChanged() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(actionResult)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(notifChannel, "Installations", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        try {
            Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
            Shizuku.addBinderReceivedListenerSticky(shizukuBinderListener)
            Shizuku.addBinderDeadListener(shizukuDeadListener)
        } catch (e: Throwable) {
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(receiver)
        } catch (e: Throwable) {
        }
        try {
            Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
            Shizuku.removeBinderReceivedListener(shizukuBinderListener)
            Shizuku.removeBinderDeadListener(shizukuDeadListener)
        } catch (e: Throwable) {
        }
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheDir" -> result.success(cacheDir.absolutePath)
                "installedVersion" -> result.success(versionOf(call.argument<String>("package") ?: ""))
                "installedInfo" -> result.success(infoOf(call.argument<String>("package") ?: ""))
                "selfPackage" -> result.success(packageName)
                "uninstall" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    val useShizuku = call.argument<Boolean>("shizuku") ?: false
                    if (useShizuku && shizukuStatus() == "ready") {
                        io.execute {
                            val out = try { runShizuku(arrayOf("pm", "uninstall", pkg), null) } catch (e: Throwable) { e.message ?: "" }
                            main.post {
                                result.success(null)
                                channel?.invokeMethod("uninstallResult", mapOf("package" to pkg, "ok" to out.contains("Success")))
                            }
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        val intent = Intent(Intent.ACTION_DELETE, android.net.Uri.parse("package:$pkg"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                }
                "open" -> {
                    val launch = packageManager.getLaunchIntentForPackage(call.argument<String>("package") ?: "")
                    if (launch != null) {
                        startActivity(launch)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "icon" -> result.success(iconOf(call.argument<String>("package") ?: ""))
                "askNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                "shizukuStatus" -> result.success(shizukuStatus())
                "shizukuRequest" -> {
                    try {
                        Shizuku.requestPermission(shizukuCode)
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "openShizuku" -> {
                    val launch = packageManager.getLaunchIntentForPackage(shizukuPackage)
                    if (launch != null) startActivity(launch)
                    result.success(launch != null)
                }
                "install" -> {
                    val path = call.argument<String>("path") ?: ""
                    val pkg = call.argument<String>("package") ?: ""
                    val name = call.argument<String>("name") ?: "L'appli"
                    val useShizuku = call.argument<Boolean>("shizuku") ?: false
                    io.execute {
                        try {
                            val file = File(path)
                            if (useShizuku && shizukuStatus() == "ready") {
                                val out = installWithShizuku(file)
                                main.post { result.success(null) }
                                if (out.contains("Success")) {
                                    done(pkg, name, true, null)
                                } else {
                                    done(pkg, name, false, "Shizuku n'a pas pu installer : " + out.trim().take(200))
                                }
                            } else {
                                installWithSession(file, pkg, name)
                                main.post { result.success(null) }
                            }
                        } catch (e: Throwable) {
                            main.post { result.error("INSTALL", "L'installation a échoué : ${e.message}", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- Installation ----------

    private fun installWithSession(file: File, pkg: String, name: String) {
        val installer = packageManager.packageInstaller
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
            val intent = Intent(actionResult)
                .setPackage(packageName)
                .putExtra("woustore_pkg", pkg)
                .putExtra("woustore_name", name)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
            val sender = PendingIntent.getBroadcast(this, sessionId, intent, flags)
            session.commit(sender.intentSender)
        }
    }

    /** Lance une commande avec les droits ADB de Shizuku ; [input] est envoyé sur son entrée. */
    private fun runShizuku(cmd: Array<String>, input: File?): String {
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

    /** Envoie l'APK à « pm install » par Shizuku. */
    private fun installWithShizuku(file: File): String =
        runShizuku(arrayOf("pm", "install", "-r", "-S", file.length().toString()), file)

    private fun done(pkg: String, name: String, ok: Boolean, message: String?) {
        main.post {
            channel?.invokeMethod(
                "installResult",
                mapOf("package" to pkg, "ok" to ok, "message" to message)
            )
            if (!resumed) {
                if (ok) {
                    notify("$name est installé", "Touche ici pour l'ouvrir.",
                        packageManager.getLaunchIntentForPackage(pkg))
                } else {
                    notify("Échec de l'installation de $name", message ?: "", null)
                }
            }
        }
        try {
            File(cacheDir, "$pkg.apk").delete()
        } catch (e: Throwable) {
        }
    }

    // ---------- Shizuku ----------

    private fun shizukuStatus(): String {
        if (versionOf(shizukuPackage) == null) return "absent"
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

    private fun shizukuChanged() {
        main.post { channel?.invokeMethod("shizukuChanged", null) }
    }

    // ---------- Divers ----------

    private fun infoOf(pkg: String): Map<String, Any?>? {
        return try {
            val info = packageManager.getPackageInfo(pkg, 0)
            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
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

    private fun versionOf(pkg: String): String? {
        return try {
            packageManager.getPackageInfo(pkg, 0).versionName ?: ""
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

    private fun notify(title: String, text: String, target: Intent?) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, notifChannel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
        if (target != null) {
            target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pi = PendingIntent.getActivity(
                this, notifId, target,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.setContentIntent(pi)
        }
        nm.notify(notifId++, builder.build())
    }
}

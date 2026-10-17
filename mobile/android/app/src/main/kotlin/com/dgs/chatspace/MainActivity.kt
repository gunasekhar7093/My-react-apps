package com.dgs.chatspace

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NOTIFICATION_CHANNEL = "com.dgs.chatspace/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (notificationManager == null) {
                result.success(false)
                return@setMethodCallHandler
            }

            when (call.method) {
                "cancelNotification" -> {
                    val tag = call.argument<String>("tag")
                    val id = call.argument<Int>("id") ?: 0

                    // 1. On Android 6.0+ (M+), inspect active notifications to find and cancel any matching tag or id
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val activeNotifications = notificationManager.activeNotifications
                            if (activeNotifications != null) {
                                for (sbn in activeNotifications) {
                                    val sbnTag = sbn.tag
                                    val sbnId = sbn.id
                                    var shouldCancel = false

                                    if (tag != null && tag.isNotEmpty()) {
                                        if (sbnTag == tag || sbnTag?.contains(tag) == true) {
                                            shouldCancel = true
                                        }
                                        val extras = sbn.notification?.extras
                                        if (extras != null) {
                                            val extraSenderId = extras.getString("senderId")
                                            if (extraSenderId == tag) {
                                                shouldCancel = true
                                            }
                                        }
                                    }

                                    if (id != 0 && sbnId == id) {
                                        shouldCancel = true
                                    }

                                    if (shouldCancel) {
                                        notificationManager.cancel(sbnTag, sbnId)
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            // Fallback to direct cancels below
                        }
                    }

                    // 2. Direct cancel fallbacks
                    if (tag != null && tag.isNotEmpty()) {
                        notificationManager.cancel(tag, 0)
                        if (id != 0) {
                            notificationManager.cancel(tag, id)
                        }
                    }
                    if (id != 0) {
                        notificationManager.cancel(id)
                    }

                    result.success(true)
                }
                "cancelAll" -> {
                    notificationManager.cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

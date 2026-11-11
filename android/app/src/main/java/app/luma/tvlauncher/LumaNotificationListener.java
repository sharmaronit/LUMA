package app.luma.tvlauncher;

import android.app.Notification;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.provider.Settings;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Collects the TV's notifications for Luma's notification centre. Only active
 * once the user grants "Notification access" to Luma in Android settings.
 */
public class LumaNotificationListener extends NotificationListenerService {
    private static volatile LumaNotificationListener instance;
    /** Set by MainActivity; called on any change so Luma can refresh. */
    static volatile Runnable onChange;

    @Override
    public void onListenerConnected() {
        instance = this;
        changed();
    }

    @Override
    public void onListenerDisconnected() {
        instance = null;
        changed();
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        changed();
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        changed();
    }

    private static void changed() {
        Runnable callback = onChange;
        if (callback != null) callback.run();
    }

    static boolean isGranted(Context context) {
        String enabled = Settings.Secure.getString(
                context.getContentResolver(), "enabled_notification_listeners");
        if (enabled == null) return false;
        ComponentName self = new ComponentName(context, LumaNotificationListener.class);
        for (String entry : enabled.split(":")) {
            ComponentName name = ComponentName.unflattenFromString(entry);
            if (self.equals(name)) return true;
        }
        return false;
    }

    /** Newest first. Skips ongoing/foreground-service and group-summary entries. */
    static List<Map<String, Object>> list(Context context) {
        List<Map<String, Object>> result = new ArrayList<>();
        LumaNotificationListener service = instance;
        if (service == null) return result;
        StatusBarNotification[] active;
        try {
            active = service.getActiveNotifications();
        } catch (Exception error) {
            return result;
        }
        if (active == null) return result;
        PackageManager pm = context.getPackageManager();
        for (StatusBarNotification sbn : active) {
            Notification n = sbn.getNotification();
            if (n == null || sbn.getPackageName().equals(context.getPackageName())) continue;
            if ((n.flags & (Notification.FLAG_ONGOING_EVENT | Notification.FLAG_FOREGROUND_SERVICE)) != 0) continue;
            if ((n.flags & Notification.FLAG_GROUP_SUMMARY) != 0) continue;
            Bundle extras = n.extras;
            CharSequence title = extras == null ? null : extras.getCharSequence(Notification.EXTRA_TITLE);
            CharSequence text = extras == null ? null : extras.getCharSequence(Notification.EXTRA_TEXT);
            if (extras != null && text == null)
                text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);
            if (title == null && text == null) continue;
            String appName = sbn.getPackageName();
            try {
                ApplicationInfo info = pm.getApplicationInfo(sbn.getPackageName(), 0);
                appName = pm.getApplicationLabel(info).toString();
            } catch (PackageManager.NameNotFoundException ignored) {
            }
            Map<String, Object> item = new HashMap<>();
            item.put("key", sbn.getKey());
            item.put("packageName", sbn.getPackageName());
            item.put("appName", appName);
            item.put("title", title == null ? "" : title.toString());
            item.put("text", text == null ? "" : text.toString());
            item.put("postTime", sbn.getPostTime());
            item.put("clearable", sbn.isClearable());
            item.put("openable", n.contentIntent != null);
            result.add(item);
        }
        result.sort((a, b) -> Long.compare((long) b.get("postTime"), (long) a.get("postTime")));
        return result;
    }

    static boolean open(String key) {
        StatusBarNotification sbn = find(key);
        if (sbn == null || sbn.getNotification().contentIntent == null) return false;
        try {
            sbn.getNotification().contentIntent.send();
            if ((sbn.getNotification().flags & Notification.FLAG_AUTO_CANCEL) != 0)
                dismiss(key);
            return true;
        } catch (PendingIntent.CanceledException error) {
            return false;
        }
    }

    static boolean dismiss(String key) {
        LumaNotificationListener service = instance;
        if (service == null) return false;
        try {
            service.cancelNotification(key);
            return true;
        } catch (Exception error) {
            return false;
        }
    }

    static int dismissAll() {
        LumaNotificationListener service = instance;
        if (service == null) return 0;
        int count = 0;
        try {
            for (StatusBarNotification sbn : service.getActiveNotifications()) {
                if (!sbn.isClearable()) continue;
                service.cancelNotification(sbn.getKey());
                count++;
            }
        } catch (Exception ignored) {
        }
        return count;
    }

    private static StatusBarNotification find(String key) {
        LumaNotificationListener service = instance;
        if (service == null || key == null) return null;
        try {
            for (StatusBarNotification sbn : service.getActiveNotifications())
                if (key.equals(sbn.getKey())) return sbn;
        } catch (Exception ignored) {
        }
        return null;
    }
}

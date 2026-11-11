package app.luma.tvlauncher;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.net.Uri;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Sleep timer and TV input switching for Luma's quick settings. */
final class TvControls {
    private TvControls() {}

    private static final String PREFS = "luma_tv_controls";
    private static final String SLEEP_END = "sleep_end";

    // ------------------------------------------------------------ inputs

    /** HDMI / component / composite inputs. Empty on streaming boxes. */
    static List<Map<String, Object>> inputs(Context context) {
        List<Map<String, Object>> result = new ArrayList<>();
        TvInputManager manager = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
        if (manager == null) return result;
        try {
            for (TvInputInfo info : manager.getTvInputList()) {
                if (!info.isPassthroughInput() || info.isHidden(context)) continue;
                Map<String, Object> item = new HashMap<>();
                item.put("id", info.getId());
                CharSequence custom = info.loadCustomLabel(context);
                item.put("label", (custom != null ? custom : info.loadLabel(context)).toString());
                item.put("type", info.getType());
                result.add(item);
            }
        } catch (Exception ignored) {
        }
        return result;
    }

    static boolean switchInput(Activity activity, String inputId) {
        try {
            Uri uri = TvContract.buildChannelUriForPassthroughInput(inputId);
            activity.startActivity(new Intent(Intent.ACTION_VIEW, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (Exception error) {
            return false;
        }
    }

    // ------------------------------------------------------------ sleep timer

    static ComponentName admin(Context context) {
        return new ComponentName(context, LumaDeviceAdmin.class);
    }

    static boolean canTurnOff(Context context) {
        DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        return dpm != null && dpm.isAdminActive(admin(context));
    }

    /** Shows Android's own consent screen for "turn the screen off". */
    static boolean requestTurnOff(Activity activity) {
        Intent intent = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin(activity))
                .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        "Lets Luma's sleep timer turn the TV off. Luma uses nothing else.");
        // No resolveActivity() pre-check: since Android 11 it returns null for
        // activities the app has not declared in <queries>.
        try {
            activity.startActivity(intent);
            return true;
        } catch (Exception error) {
            return false;
        }
    }

    /** Epoch millis when the timer ends, or 0 when it is off. */
    static long sleepEnd(Context context) {
        long end = prefs(context).getLong(SLEEP_END, 0);
        return end > System.currentTimeMillis() ? end : 0;
    }

    static long setSleep(Context context, int minutes) {
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pending = alarmIntent(context);
        alarms.cancel(pending);
        if (minutes <= 0) {
            prefs(context).edit().remove(SLEEP_END).apply();
            return 0;
        }
        long end = System.currentTimeMillis() + minutes * 60_000L;
        prefs(context).edit().putLong(SLEEP_END, end).apply();
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pending);
        return end;
    }

    private static PendingIntent alarmIntent(Context context) {
        return PendingIntent.getBroadcast(context, 7310,
                new Intent(context, SleepReceiver.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Fires when the sleep timer ends, even while another app is open. */
    public static class SleepReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            prefs(context).edit().remove(SLEEP_END).apply();
            if (canTurnOff(context)) {
                DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
                try {
                    dpm.lockNow();
                    return;
                } catch (SecurityException ignored) {
                }
            }
            // Without permission: start the screensaver; Android's own sleep
            // setting then turns the TV off.
            try {
                Intent dream = new Intent(Intent.ACTION_MAIN)
                        .setClassName("com.android.systemui", "com.android.systemui.Somnambulator")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(dream);
            } catch (Exception ignored) {
            }
        }
    }

    /** Only the "force lock" policy (screen off). See res/xml/luma_device_admin.xml. */
    public static class LumaDeviceAdmin extends DeviceAdminReceiver {
    }
}

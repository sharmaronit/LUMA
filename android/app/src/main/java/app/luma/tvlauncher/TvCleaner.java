/*
 * Luma
 * Copyright (C) 2026 Ronit Sharma
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */
package app.luma.tvlauncher;

import android.content.Context;
import android.content.Intent;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/** Runs the cleaner's package-manager commands through the TV's own ADB service. */
final class TvCleaner {
    private TvCleaner() { }

    private static final int PORT = 5555;
    // The cleaner never needs a general shell, so nothing else is accepted.
    private static final Pattern[] ALLOWED = {
            Pattern.compile("pm list packages( -[ed])?"),
            Pattern.compile("pm (disable-user --user 0|enable) [A-Za-z0-9._]+"),
            Pattern.compile("cmd package set-home-activity [A-Za-z0-9._]+/[A-Za-z0-9._$]+"),
            Pattern.compile("getprop [a-z0-9._]+"),
            Pattern.compile("am force-stop [A-Za-z0-9._]+"),
    };

    static boolean allowed(String command) {
        for (Pattern pattern : ALLOWED) if (pattern.matcher(command).matches()) return true;
        return false;
    }

    /** Blocks; call it off the main thread. */
    static Map<String, Object> run(Context context, List<String> commands, int approvalMs) {
        Map<String, Object> result = new HashMap<>();
        List<String> outputs = new ArrayList<>();
        result.put("outputs", outputs);
        for (String command : commands) {
            if (!allowed(command)) {
                result.put("status", "error");
                result.put("message", "Command not allowed");
                return result;
            }
        }
        try (AdbClient client = AdbClient.connect(context.getApplicationContext(), PORT, approvalMs)) {
            for (String command : commands) outputs.add(client.shell(command));
            result.put("status", "ok");
        } catch (AdbClient.Unreachable e) {
            result.put("status", "unreachable");
        } catch (AdbClient.Unauthorized e) {
            result.put("status", "unauthorized");
        } catch (Exception e) {
            result.put("status", "error");
            result.put("message", String.valueOf(e.getMessage()));
        }
        return result;
    }

    /**
     * Closes an app from the Recent apps panel. With the debugging permission
     * the app is stopped completely ("stopped"); without it Android is only
     * asked to free the app's background memory ("freed"). Blocks.
     */
    static String closeApp(Context context, String packageName) {
        if (packageName == null || !packageName.matches("[A-Za-z0-9._]+")
                || packageName.equals(context.getPackageName())) {
            return "refused";
        }
        // Only when the TV has already approved Luma for Clean my TV: closing
        // an app must never raise a debugging prompt.
        try (AdbClient client = AdbClient.connect(context.getApplicationContext(), PORT, 1200, false)) {
            client.shell("am force-stop " + packageName);
            return "stopped";
        } catch (Exception ignored) {
            // Fall through to the weaker, permission-free way.
        }
        try {
            android.app.ActivityManager manager =
                    (android.app.ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
            manager.killBackgroundProcesses(packageName);
            return "freed";
        } catch (Exception e) {
            return "refused";
        }
    }

    /** Memory in use on the TV, for the Recent apps panel. */
    static Map<String, Object> memory(Context context) {
        android.app.ActivityManager manager =
                (android.app.ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        android.app.ActivityManager.MemoryInfo info = new android.app.ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        Map<String, Object> result = new HashMap<>();
        result.put("total", info.totalMem);
        result.put("available", info.availMem);
        return result;
    }

    static boolean openDeveloperOptions(Context context) {
        String[] actions = {
                Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS,
                Settings.ACTION_DEVICE_INFO_SETTINGS,
                Settings.ACTION_SETTINGS,
        };
        for (String action : actions) {
            try {
                context.startActivity(new Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                return true;
            } catch (Exception ignored) {
                // Try the next screen.
            }
        }
        return false;
    }
}

/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package app.luma.tvlauncher;

import android.content.Context;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import java.nio.charset.StandardCharsets;
import java.io.InputStream;
import java.io.OutputStream;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.*;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Pair;
import android.media.tv.TvContract;
import android.database.Cursor;
import android.Manifest;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.FileProvider;
import androidx.annotation.RequiresApi;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.io.ByteArrayOutputStream;
import java.io.File;
import android.app.usage.NetworkStats;
import android.app.usage.NetworkStatsManager;
import android.app.AppOpsManager;
import android.os.RemoteException;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

import java.io.ByteArrayOutputStream;
import java.io.Serializable;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletionService;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorCompletionService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class MainActivity extends FlutterActivity {
    private android.media.SoundPool navigationSounds;
    private final Map<String, Integer> navigationSoundIds = new HashMap<>();
    private final java.util.Set<Integer> readyNavigationSounds = new java.util.HashSet<>();
    private long lastNavigationSoundAt = 0;
    private int navigationStream = 0;
    private boolean navigationSoundEnabled = false;
    private double navigationSoundVolume = .35;
    private String lastNavigationSound = "";

    private void prepareNavigationSounds() {
        if (navigationSounds != null) return;
        navigationSounds = new android.media.SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(new android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build())
            .build();
        navigationSounds.setOnLoadCompleteListener((pool, id, status) -> {
            if (status == 0) readyNavigationSounds.add(id);
        });
        navigationSoundIds.put("move", navigationSounds.load(this, R.raw.luma_move, 1));
        navigationSoundIds.put("select", navigationSounds.load(this, R.raw.luma_select, 1));
        navigationSoundIds.put("back", navigationSounds.load(this, R.raw.luma_back, 1));
    }

    private void playNavigationSound(String name, double volume) {
        Integer id = navigationSoundIds.get(name);
        if (!navigationSoundEnabled || navigationSounds == null || id == null || !readyNavigationSounds.contains(id)
                || !Double.isFinite(volume) || volume <= 0 || !hasWindowFocus()) return;
        long now = android.os.SystemClock.uptimeMillis();
        if ("move".equals(name) && now - lastNavigationSoundAt < 100) return;
        if (name.equals(lastNavigationSound) && now - lastNavigationSoundAt < 100) return;
        lastNavigationSoundAt = now;
        lastNavigationSound = name;
        float gain = (float) Math.max(0, Math.min(1, volume));
        // No audio focus request: a UI tick must not pause or duck playback.
        // Let the short chime tails finish; cutting them at each key creates
        // clicks. Three bounded voices cover the rate-limited navigation.
        navigationStream = navigationSounds.play(id, gain, gain, 1, 0, 1f);
    }

    @Override
    public void onBackPressed() {
        // Android can deliver Back through the navigation channel instead of a
        // Flutter key event. Use the same saved settings for that path too.
        playNavigationSound("back", navigationSoundVolume);
        super.onBackPressed();
    }
    private MethodChannel launcherChannel;
    private final ExecutorService artworkExecutor = Executors.newFixedThreadPool(2);
    private android.speech.SpeechRecognizer voiceRecognizer;
    private boolean voiceRequested;
    private long voiceGeneration;
    private MethodChannel.Result backupResult;
    private String backupJson;
    private boolean backupWriting;
    private MethodChannel.Result bluetoothPermissionResult;
    private MethodChannel.Result mediaPermissionResult;
    private static final int BACKUP_READ = 9410, BACKUP_WRITE = 9411, BLUETOOTH_PERMISSION = 9412;
    private static final int VOICE_PERMISSION_REQUEST = 9102;
    private static final int SETUP_PERMISSION_REQUEST = 9413;
    private MethodChannel.Result setupPermissionResult;
    private final String METHOD_CHANNEL = "app.luma.tvlauncher/method";
    private final String APPS_EVENT_CHANNEL = "app.luma.tvlauncher/event_apps";
    private final String NETWORK_EVENT_CHANNEL = "app.luma.tvlauncher/event_network";
    private static final String PERMISSION_READ_TV_LISTINGS = "android.permission.READ_TV_LISTINGS";
    private static final int REQUEST_CODE_READ_TV_LISTINGS = 1001;
    private static final String COLUMN_ASPECT_RATIO = "aspect_ratio";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        prepareNavigationSounds();

        BinaryMessenger messenger = flutterEngine.getDartExecutor().getBinaryMessenger();

        launcherChannel = new MethodChannel(messenger, METHOD_CHANNEL);
        LumaNotificationListener.onChange = () -> runOnUiThread(() -> {
            if (launcherChannel != null) launcherChannel.invokeMethod("notificationsChanged", null);
        });
        launcherChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "setNavigationSoundSettings" -> {
                    navigationSoundEnabled = Boolean.TRUE.equals(call.argument("enabled"));
                    Number volume = call.argument("volume");
                    navigationSoundVolume = volume == null ? .35 : volume.doubleValue();
                    result.success(null);
                }
                case "playNavigationSound" -> {
                    String sound = call.argument("sound");
                    Number volume = call.argument("volume");
                    playNavigationSound(sound, volume == null ? .35 : volume.doubleValue());
                    result.success(null);
                }
                case "getAppActions" -> result.success(getAppActions((String) call.arguments));
                case "launchAppAction" -> {
                    try {
                        String pkg = call.argument("package");
                        String id = call.argument("id");
                        boolean found = false;
                        for (Map<String, String> action : getAppActions(pkg)) {
                            if (action.get("id").equals(id)) { found = true; break; }
                        }
                        if (!found) throw new IllegalArgumentException("Shortcut is no longer available");
                        if (id.startsWith("shortcut:")) {
                            getSystemService(LauncherApps.class).startShortcut(pkg, id.substring(9), null, null, android.os.Process.myUserHandle());
                        } else if (id.equals("info")) {
                            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + pkg)));
                        } else {
                            Intent intent = new Intent(id.equals("search") ? Intent.ACTION_SEARCH : Intent.ACTION_APPLICATION_PREFERENCES).setPackage(pkg);
                            ResolveInfo target = getPackageManager().resolveActivity(intent, 0);
                            if (target == null || target.activityInfo == null) throw new IllegalArgumentException("Action unavailable");
                            intent.setClassName(pkg, target.activityInfo.name);
                            if (id.equals("search")) {
                                String query = call.argument("query");
                                if (query == null || query.trim().isEmpty() || query.length() > 200) throw new IllegalArgumentException("Search needs a query");
                                android.app.SearchManager search = getSystemService(android.app.SearchManager.class);
                                android.app.SearchableInfo info = search == null ? null : search.getSearchableInfo(intent.getComponent());
                                if (info == null || !pkg.equals(info.getSearchActivity().getPackageName())) throw new IllegalArgumentException("Search unavailable");
                                intent.setComponent(info.getSearchActivity());
                                intent.putExtra(android.app.SearchManager.QUERY, query.trim());
                            }
                            startActivity(intent);
                        }
                        result.success(null);
                    } catch (Exception error) {
                        result.error("unavailable", "This app action is no longer available", null);
                    }
                }
                case "getSetupStatus" -> result.success(setupStatus());
                case "requestSetupPermission" -> requestSetupPermission((String) call.arguments, result);
                case "startVoiceSearch" -> {
                    stopVoiceSearch();
                    voiceRequested = true;
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        voiceEvent("permission", "", "Allow microphone access to use voice search.", 0);
                        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.RECORD_AUDIO}, VOICE_PERMISSION_REQUEST);
                    } else startVoiceRecognizer();
                    result.success(null);
                }
                case "stopVoiceSearch" -> { stopVoiceSearch(); result.success(null); }
                case "getConnectionStatus" -> result.success(connectionStatus());
                case "requestBluetoothStatus" -> {
                    if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                        if (bluetoothPermissionResult != null) { result.error("busy", "Permission request already open", null); break; }
                        bluetoothPermissionResult = result;
                        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.BLUETOOTH_CONNECT}, BLUETOOTH_PERMISSION);
                    } else result.success(null);
                }
                case "saveLocalBackup" -> localBackup(result, (String) call.arguments);
                case "readLocalBackup" -> localBackup(result, null);
                case "exportBackup" -> chooseBackupFile(result, (String) call.arguments);
                case "importBackup" -> chooseBackupFile(result, null);
                case "getApplications" -> artworkExecutor.execute(() -> {
                    try {
                        List<Map<String, Serializable>> apps = getApplications();
                        runOnUiThread(() -> result.success(apps));
                    } catch (Exception error) {
                        runOnUiThread(() -> result.error("APPS_UNAVAILABLE", "Could not load installed apps", null));
                    }
                });
                case "getApplicationBanner" -> queueArtwork(result, call.arguments(), true);
                case "getApplicationIcon" -> queueArtwork(result, call.arguments(), false);
                case "applicationExists" -> result.success(applicationExists(call.arguments()));
                case "launchActivityFromAction" -> result.success(launchActivityFromAction(call.arguments()));
                case "launchApp" -> result.success(launchApp(call.arguments()));
                case "openHomeSettings" -> {
                    try {
                        startActivity(new android.content.Intent(android.provider.Settings.ACTION_HOME_SETTINGS));
                        result.success(true);
                    } catch (android.content.ActivityNotFoundException exception) {
                        result.success(openSettings());
                    }
                }
                case "openQuickSettings" -> result.success(openQuickSettings((String) call.arguments));
                case "openSettings" -> result.success(openSettings());
                case "installApk" -> result.success(installApk(call.arguments()));
                case "requestInstallUnknownAppsPermission" -> {
                    requestInstallUnknownAppsPermission();
                    result.success(null);
                }
                case "openScreensaverSettings" -> result.success(openScreensaverSettings());
                case "openAppInfo" -> result.success(openAppInfo(call.arguments()));
                case "uninstallApp" -> result.success(uninstallApp(call.arguments()));
                case "isDefaultLauncher" -> result.success(isDefaultLauncher());
                case "getDeviceProfile" -> result.success(getDeviceProfile());
                case "getTvInputs" -> result.success(TvControls.inputs(this));
                case "switchTvInput" -> result.success(TvControls.switchInput(this, (String) call.arguments));
                case "getSleepTimer" -> result.success(TvControls.sleepEnd(this));
                case "setSleepTimer" -> result.success(TvControls.setSleep(this, ((Number) call.arguments).intValue()));
                case "canTurnOffTv" -> result.success(TvControls.canTurnOff(this));
                case "requestTurnOffPermission" -> result.success(TvControls.requestTurnOff(this));
                case "cleanerRun" -> {
                    java.util.List<String> commands = call.argument("commands");
                    Number approval = call.argument("approvalMs");
                    // Its own thread: this can wait a minute for the debugging prompt.
                    new Thread(() -> {
                        Map<String, Object> value = TvCleaner.run(this, commands, approval == null ? 8000 : approval.intValue());
                        runOnUiThread(() -> result.success(value));
                    }, "luma-cleaner").start();
                }
                case "openDeveloperOptions" -> result.success(TvCleaner.openDeveloperOptions(this));
                case "getMemoryInfo" -> result.success(TvCleaner.memory(this));
                case "setKeepScreenOn" -> {
                    // Only while Luma is on screen: the flag belongs to this
                    // window, so other apps keep the TV's own sleep setting.
                    if (Boolean.TRUE.equals(call.arguments)) {
                        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    } else {
                        getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    }
                    result.success(true);
                }
                case "closeApp" -> {
                    String target = (String) call.arguments;
                    new Thread(() -> {
                        String outcome = TvCleaner.closeApp(this, target);
                        runOnUiThread(() -> result.success(outcome));
                    }, "luma-close-app").start();
                }
                case "notificationAccess" -> result.success(LumaNotificationListener.isGranted(this));
                case "getNotifications" -> result.success(LumaNotificationListener.list(this));
                case "openNotification" -> result.success(LumaNotificationListener.open((String) call.arguments));
                case "dismissNotification" -> result.success(LumaNotificationListener.dismiss((String) call.arguments));
                case "dismissAllNotifications" -> result.success(LumaNotificationListener.dismissAll());
                case "openNotificationAccessSettings" -> result.success(openNotificationAccessSettings());
                case "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability());
                case "startAmbientMode" -> result.success(startAmbientMode());
                case "getActiveNetworkInformation" -> result.success(getActiveNetworkInformation());
                case "getDailyWifiUsage" -> {
                    long usage = getDailyWifiUsage();
                    if (usage == -1) {
                        result.error("PERMISSION_DENIED", "Usage stats permission not granted", null);
                    } else {
                        result.success(usage);
                    }
                }
                case "getWeeklyWifiUsage" -> {
                    long usage = getWeeklyWifiUsage();
                    if (usage == -1) {
                        result.error("PERMISSION_DENIED", "Usage stats permission not granted", null);
                    } else {
                        result.success(usage);
                    }
                }
                case "getMonthlyWifiUsage" -> {
                    long usage = getMonthlyWifiUsage();
                    if (usage == -1) {
                        result.error("PERMISSION_DENIED", "Usage stats permission not granted", null);
                    } else {
                        result.success(usage);
                    }
                }
                case "checkUsageStatsPermission" -> result.success(checkUsageStatsPermission());
                case "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission();
                    result.success(null);
                }
                case "checkWriteSettingsPermission" -> result.success(checkWriteSettingsPermission());
                case "requestWriteSettingsPermission" -> {
                    requestWriteSettingsPermission();
                    result.success(null);
                }
                case "setSystemBrightness" -> {
                    int brightness = call.argument("brightness");
                    result.success(setSystemBrightness(brightness));
                }
                case "openWifiSettings" -> result.success(openWifiSettings());
                case "getMediaStoreImages", "getMediaStoreVideos" -> artworkExecutor.execute(() -> {
                    try {
                        List<Map<String, Object>> items = call.method.equals("getMediaStoreImages")
                            ? getMediaStoreImages() : getMediaStoreVideos();
                        runOnUiThread(() -> result.success(items));
                    } catch (Exception error) {
                        runOnUiThread(() -> result.error("MEDIA_UNAVAILABLE", "Could not load media. Please try again.", null));
                    }
                });
                case "getMediaStoreImageThumbnail" -> artworkExecutor.execute(() -> {
                    byte[] bytes = getMediaStoreImageThumbnail((String) call.arguments);
                    runOnUiThread(() -> result.success(bytes));
                });
                case "copyContentUriToFile" -> artworkExecutor.execute(() -> {
                    try {
                        Uri uri = Uri.parse(call.argument("uri"));
                        File target = new File((String) call.argument("destination"));
                        String root = new File(getApplicationInfo().dataDir).getCanonicalPath() + File.separator;
                        if (!"content".equals(uri.getScheme()) || !target.getCanonicalPath().startsWith(root)) {
                            throw new IllegalArgumentException("Invalid media destination");
                        }
                        try (java.io.InputStream input = getContentResolver().openInputStream(uri);
                             java.io.OutputStream output = new java.io.BufferedOutputStream(new java.io.FileOutputStream(target))) {
                            if (input == null) throw new java.io.IOException("Selected media is unavailable");
                            byte[] buffer = new byte[65536];
                            int count;
                            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                        }
                        runOnUiThread(() -> result.success(null));
                    } catch (Exception error) {
                        runOnUiThread(() -> result.error("MEDIA_UNAVAILABLE", "Could not copy selected media", null));
                    }
                });
                case "getMediaStoreVideoThumbnail" -> {
                    Number id = call.argument("id");
                    String path = call.argument("path");
                    artworkExecutor.execute(() -> {
                        byte[] bytes = getMediaStoreVideoThumbnail(id != null ? id.longValue() : -1, path);
                        runOnUiThread(() -> result.success(bytes));
                    });
                }
                case "checkMediaPermissions" -> result.success(checkMediaPermissions((String) call.arguments));
                case "requestMediaPermissions" -> {
                    if (mediaPermissionResult != null) { result.error("busy", "Media permission request already open", null); break; }
                    mediaPermissionResult = result;
                    try { requestMediaPermissions((String) call.arguments); }
                    catch (Exception error) { mediaPermissionResult = null; result.error("MEDIA_UNAVAILABLE", "Could not request media access", null); }
                }
                case "checkWatchNextPermission" -> result.success(checkWatchNextPermission());
                case "requestWatchNextPermission" -> {
                    requestWatchNextPermission();
                    result.success(null);
                }
                case "getWatchNextItems" -> {
                    int limit = call.arguments() != null ? (int) call.arguments() : 10;
                    artworkExecutor.execute(() -> {
                        try {
                            List<Map<String, Object>> items = getWatchNextItems(Math.max(1, Math.min(limit, 100)));
                            runOnUiThread(() -> result.success(items));
                        } catch (Exception error) {
                            runOnUiThread(() -> result.error("PROGRAMMES_UNAVAILABLE", "Could not load programme cards", null));
                        }
                    });
                }
                case "launchWatchNextItem" -> {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> args = (Map<String, Object>) call.arguments();
                    if (args != null) {
                        String packageName = (String) args.get("packageName");
                        String contentId = (String) args.get("contentId");
                        String action = (String) args.get("action");
                        result.success(launchWatchNextItem(packageName, contentId, action));
                    } else {
                        result.success(false);
                    }
                }
                case "loadContentUriImage" -> {
                    String contentUri = (String) call.arguments();
                    if (contentUri != null) {
                        artworkExecutor.execute(() -> {
                            byte[] bytes = loadContentUriImage(contentUri);
                            runOnUiThread(() -> result.success(bytes));
                        });
                    } else {
                        result.success(new byte[0]);
                    }
                }
                default -> throw new IllegalArgumentException("Unknown method: " + call.method);
            }
        });

        new EventChannel(messenger, APPS_EVENT_CHANNEL).setStreamHandler(
                new LauncherAppsEventStreamHandler(this));

        new EventChannel(messenger, NETWORK_EVENT_CHANNEL).setStreamHandler(
                new NetworkEventStreamHandler(this));
    }

    @Override
    public void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        if (Intent.ACTION_MAIN.equals(intent.getAction()) && intent.hasCategory(Intent.CATEGORY_HOME) && launcherChannel != null) {
            // True when Home was pressed while Luma was already on screen,
            // as opposed to Home bringing Luma back from another app.
            boolean alreadyHome = startedAt > 0
                    && android.os.SystemClock.uptimeMillis() - startedAt > 1000;
            launcherChannel.invokeMethod("homePressed", alreadyHome);
        }
    }

    private List<Map<String, Serializable>> getApplications() {
        ExecutorService executor = Executors.newFixedThreadPool(4);
        CompletionService<Pair<Boolean, List<ResolveInfo>>> queryIntentActivitiesCompletionService = new ExecutorCompletionService<>(
                executor);
        queryIntentActivitiesCompletionService.submit(() -> Pair.create(false, queryIntentActivities(false)));
        queryIntentActivitiesCompletionService.submit(() -> Pair.create(true, queryIntentActivities(true)));
        List<ResolveInfo> tvActivitiesInfo = null;
        List<ResolveInfo> nonTvActivitiesInfo = null;

        int completed = 0;
        while (completed < 2) {
            try {
                var activitiesInfo = queryIntentActivitiesCompletionService.take().get();

                if (!activitiesInfo.first) {
                    tvActivitiesInfo = activitiesInfo.second;
                } else {
                    nonTvActivitiesInfo = activitiesInfo.second;
                }
            } catch (InterruptedException | ExecutionException ignored) {
            } finally {
                completed += 1;
            }
        }

        CompletionService<Map<String, Serializable>> completionService = new ExecutorCompletionService<>(executor);

        List<Map<String, Serializable>> applications = new ArrayList<>(
                tvActivitiesInfo.size() + nonTvActivitiesInfo.size());

        boolean settingsPresent = false;
        int appCount = 0;
        for (ResolveInfo tvActivityInfo : tvActivitiesInfo) {
            if (tvActivityInfo.activityInfo.packageName.equals(getPackageName())) continue;
            if (!settingsPresent) {
                settingsPresent = tvActivityInfo.activityInfo.packageName.equals("com.android.tv.settings");
            }

            completionService.submit(() -> buildAppMap(tvActivityInfo.activityInfo, false, null));
            appCount += 1;
        }

        for (ResolveInfo nonTvActivityInfo : nonTvActivitiesInfo) {
            if (nonTvActivityInfo.activityInfo.packageName.equals(getPackageName())) continue;
            boolean nonDuplicate = true;

            if (!settingsPresent) {
                settingsPresent = nonTvActivityInfo.activityInfo.packageName.equals("com.android.settings");
            }

            for (ResolveInfo tvActivityInfo : tvActivitiesInfo) {
                if (tvActivityInfo.activityInfo.packageName.equals(nonTvActivityInfo.activityInfo.packageName)) {
                    nonDuplicate = false;
                    break;
                }
            }

            if (nonDuplicate) {
                appCount += 1;
                completionService.submit(() -> buildAppMap(nonTvActivityInfo.activityInfo, true, null));
            }
        }

        while (appCount > 0) {
            try {
                Future<Map<String, Serializable>> appMap = completionService.take();
                applications.add(appMap.get());
            } catch (InterruptedException | ExecutionException ignored) {
            } finally {
                appCount -= 1;
            }
        }

        executor.shutdown();

        if (!settingsPresent) {
            PackageManager packageManager = getPackageManager();
            Intent settingsIntent = new Intent(Settings.ACTION_SETTINGS);
            ActivityInfo activityInfo = settingsIntent.resolveActivityInfo(packageManager, 0);

            if (activityInfo != null) {
                applications.add(buildAppMap(activityInfo, false, Settings.ACTION_SETTINGS));
            }
        }

        return applications;
    }

    public Map<String, Serializable> getApplication(String packageName) {
        Map<String, Serializable> map = CompatMap.of();
        PackageManager packageManager = getPackageManager();
        Intent intent = packageManager.getLeanbackLaunchIntentForPackage(packageName);

        if (intent == null) {
            intent = packageManager.getLaunchIntentForPackage(packageName);
        }

        if (intent != null) {
            ActivityInfo activityInfo = intent.resolveActivityInfo(getPackageManager(), 0);

            if (activityInfo != null) {
                map = buildAppMap(activityInfo, false, null);
            }
        }

        return map;
    }

    private void queueArtwork(MethodChannel.Result result, String packageName, boolean banner) {
        artworkExecutor.execute(() -> {
            try {
                byte[] bytes = banner ? getApplicationBanner(packageName) : getApplicationIcon(packageName);
                runOnUiThread(() -> result.success(bytes));
            } catch (Exception error) {
                runOnUiThread(() -> result.error("ARTWORK_UNAVAILABLE", "Could not load app artwork", null));
            }
        });
    }

    private byte[] getApplicationBanner(String packageName) {
        byte[] imageBytes = new byte[0];

        PackageManager packageManager = getPackageManager();
        try {
            ApplicationInfo info = packageManager.getApplicationInfo(packageName, 0);
            Intent launcherIntent = packageManager.getLeanbackLaunchIntentForPackage(packageName);
            if (launcherIntent == null) launcherIntent = packageManager.getLaunchIntentForPackage(packageName);
            ActivityInfo activity = launcherIntent == null ? null : launcherIntent.resolveActivityInfo(packageManager, 0);
            Drawable drawable = activity == null ? null : activity.loadBanner(packageManager);
            if (drawable == null) drawable = info.loadBanner(packageManager);

            if (drawable != null) {
                imageBytes = drawableToByteArray(drawable, 640, 360);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
        }

        return imageBytes;
    }

    private byte[] getApplicationIcon(String packageName) {
        byte[] imageBytes = new byte[0];

        PackageManager packageManager = getPackageManager();
        try {
            ApplicationInfo info = packageManager.getApplicationInfo(packageName, 0);
            Drawable drawable = info.loadIcon(packageManager);

            if (drawable != null) {
                imageBytes = drawableToByteArray(drawable, 256, 256, true);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
        }

        return imageBytes;
    }

    private boolean applicationExists(String packageName) {
        int flags;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            flags = PackageManager.MATCH_UNINSTALLED_PACKAGES;
        } else {
            flags = PackageManager.GET_UNINSTALLED_PACKAGES;
        }

        try {
            getPackageManager().getApplicationInfo(packageName, flags);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) {
            return false;
        }
    }

    private List<ResolveInfo> queryIntentActivities(boolean sideloaded) {
        String category;
        if (sideloaded) {
            category = Intent.CATEGORY_LAUNCHER;
        } else {
            category = Intent.CATEGORY_LEANBACK_LAUNCHER;
        }

        // NOTE: Would be nice to query the applications that match *either* of the
        // above categories
        // but from the addCategory function documentation, it says that it will "use
        // activities
        // that provide *all* the requested categories"
        Intent intent = new Intent(Intent.ACTION_MAIN)
                .addCategory(category);

        return getPackageManager()
                .queryIntentActivities(intent, 0);
    }

    private Map<String, Serializable> buildAppMap(ActivityInfo activityInfo, boolean sideloaded, String action) {
        PackageManager packageManager = getPackageManager();

        String applicationName = activityInfo.loadLabel(packageManager).toString(),
                applicationVersionName = "";
        try {
            applicationVersionName = packageManager.getPackageInfo(activityInfo.packageName, 0).versionName;
        } catch (PackageManager.NameNotFoundException ignored) {
        }

        Map<String, Serializable> appMap = new HashMap<>();
        appMap.put("name", applicationName);
        appMap.put("packageName", activityInfo.packageName);
        appMap.put("version", applicationVersionName);
        try {
            appMap.put("installedAt", packageManager.getPackageInfo(activityInfo.packageName, 0).firstInstallTime);
        } catch (PackageManager.NameNotFoundException ignored) { }
        appMap.put("sideloaded", sideloaded);
        int appCategory = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O
                ? activityInfo.applicationInfo.category : -1;
        appMap.put("appCategory", appCategory);
        appMap.put("isGame", appCategory == 0 ||
                (activityInfo.applicationInfo.flags & android.content.pm.ApplicationInfo.FLAG_IS_GAME) != 0);

        if (action != null) {
            appMap.put("action", action);
        }
        return appMap;
    }

    private boolean launchActivityFromAction(String action) {
        return tryStartActivity(new Intent(action));
    }

    private boolean launchApp(String packageName) {
        PackageManager packageManager = getPackageManager();
        Intent intent = packageManager.getLeanbackLaunchIntentForPackage(packageName);

        if (intent == null) {
            intent = packageManager.getLaunchIntentForPackage(packageName);
        }

        return tryStartActivity(intent);
    }

    private boolean openSettings() {
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean installApk(String apkPath) {
        File apkFile = new File(apkPath);
        if (!apkFile.exists()) {
            return false;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !getPackageManager().canRequestPackageInstalls()) {
            return false;
        }

        Uri apkUri = FileProvider.getUriForFile(
                this,
                getPackageName() + ".fileprovider",
                apkFile
        );

        Intent installIntent = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(apkUri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        return tryStartActivity(installIntent);
    }

    private void requestInstallUnknownAppsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:" + getPackageName()));
            tryStartActivity(intent);
        }
    }

    private boolean openAppInfo(String packageName) {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null));

        return tryStartActivity(intent);
    }

    private boolean uninstallApp(String packageName) {
        Intent intent = new Intent(Intent.ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null));

        return tryStartActivity(intent);
    }

    private boolean checkForGetContentAvailability() {
        List<ResolveInfo> intentActivities = getPackageManager().queryIntentActivities(
                new Intent(Intent.ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"),
                0);

        return !intentActivities.isEmpty();
    }

    private boolean isDefaultLauncher() {
        Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
        ResolveInfo defaultLauncher = getPackageManager().resolveActivity(intent, 0);

        if (defaultLauncher != null && defaultLauncher.activityInfo != null) {
            return defaultLauncher.activityInfo.packageName.equals(getPackageName());
        }

        return false;
    }

    private boolean startAmbientMode() {
        Intent intent = new Intent(Intent.ACTION_MAIN)
                .setClassName("com.android.systemui", "com.android.systemui.Somnambulator");

        return tryStartActivity(intent);
    }

    private Map<String, Object> getActiveNetworkInformation() {
        ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return NetworkUtils.getNetworkInformation(this, connectivityManager.getActiveNetwork());
        } else {
            // noinspection deprecation
            return NetworkUtils.getNetworkInformation(this, connectivityManager.getActiveNetworkInfo());
        }
    }

    private boolean tryStartActivity(Intent intent) {
        boolean success = true;

        try {
            startActivity(intent);
        } catch (Exception ignored) {
            success = false;
        }

        return success;
    }

    private byte[] drawableToByteArray(Drawable drawable, int maxWidth, int maxHeight) {
        return drawableToByteArray(drawable, maxWidth, maxHeight, false);
    }

    private byte[] drawableToByteArray(Drawable drawable, int maxWidth, int maxHeight, boolean trim) {
        int width = drawable.getIntrinsicWidth(), height = drawable.getIntrinsicHeight();
        if (width <= 0 || height <= 0) return new byte[0];
        float scale = Math.min(1f, Math.min(maxWidth / (float) width, maxHeight / (float) height));
        int targetWidth = Math.max(1, Math.round(width * scale));
        int targetHeight = Math.max(1, Math.round(height * scale));
        Bitmap bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888);
        try {
            drawable.setBounds(0, 0, targetWidth, targetHeight);
            drawable.draw(new Canvas(bitmap));
            ByteArrayOutputStream stream = new ByteArrayOutputStream();
            Bitmap output = bitmap;
            if (trim) {
                // This runs on the existing bounded artwork executor, once per cached icon.
                int[] pixels = new int[targetWidth * targetHeight];
                bitmap.getPixels(pixels, 0, targetWidth, 0, 0, targetWidth, targetHeight);
                int left = targetWidth, top = targetHeight, right = -1, bottom = -1;
                for (int y = 0; y < targetHeight; y++) {
                    for (int x = 0; x < targetWidth; x++) {
                        if ((pixels[y * targetWidth + x] >>> 24) > 8) {
                            left = Math.min(left, x); right = Math.max(right, x);
                            top = Math.min(top, y); bottom = Math.max(bottom, y);
                        }
                    }
                }
                if (right >= left && bottom >= top && (left > 0 || top > 0 || right < targetWidth - 1 || bottom < targetHeight - 1)) {
                    output = Bitmap.createBitmap(bitmap, left, top, right - left + 1, bottom - top + 1);
                }
            }
            try { output.compress(Bitmap.CompressFormat.PNG, 100, stream); }
            finally { if (output != bitmap) output.recycle(); }
            return stream.toByteArray();
        } finally { bitmap.recycle(); }
    }

    Bitmap drawableToBitmap(Drawable drawable) {
        Bitmap bitmap = Bitmap.createBitmap(
                drawable.getIntrinsicWidth(),
                drawable.getIntrinsicHeight(),
                Bitmap.Config.ARGB_8888);

        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, canvas.getWidth(), canvas.getHeight());
        drawable.draw(canvas);
        return bitmap;
    }

    private long getDailyWifiUsage() {
        if (!checkUsageStatsPermission()) {
            return -1;
        }

        NetworkStatsManager networkStatsManager = (NetworkStatsManager) getSystemService(Context.NETWORK_STATS_SERVICE);
        if (networkStatsManager == null)
            return 0;

        java.util.Calendar calendar = java.util.Calendar.getInstance();
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0);
        calendar.set(java.util.Calendar.MINUTE, 0);
        calendar.set(java.util.Calendar.SECOND, 0);
        calendar.set(java.util.Calendar.MILLISECOND, 0);
        long startTime = calendar.getTimeInMillis();
        long endTime = System.currentTimeMillis();

        long totalBytes = 0;
        try {
            NetworkStats.Bucket bucket = networkStatsManager.querySummaryForDevice(
                    NetworkCapabilities.TRANSPORT_WIFI,
                    "",
                    startTime,
                    endTime);
            totalBytes = bucket.getRxBytes() + bucket.getTxBytes();
        } catch (RemoteException e) {
            e.printStackTrace();
        }

        return totalBytes;
    }

    private long getWeeklyWifiUsage() {
        if (!checkUsageStatsPermission()) {
            return -1;
        }

        NetworkStatsManager networkStatsManager = (NetworkStatsManager) getSystemService(Context.NETWORK_STATS_SERVICE);
        if (networkStatsManager == null)
            return 0;

        java.util.Calendar calendar = java.util.Calendar.getInstance();
        calendar.set(java.util.Calendar.DAY_OF_WEEK, calendar.getFirstDayOfWeek());
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0);
        calendar.set(java.util.Calendar.MINUTE, 0);
        calendar.set(java.util.Calendar.SECOND, 0);
        calendar.set(java.util.Calendar.MILLISECOND, 0);
        long startTime = calendar.getTimeInMillis();
        long endTime = System.currentTimeMillis();

        long totalBytes = 0;
        try {
            NetworkStats.Bucket bucket = networkStatsManager.querySummaryForDevice(
                    NetworkCapabilities.TRANSPORT_WIFI,
                    "",
                    startTime,
                    endTime);
            totalBytes = bucket.getRxBytes() + bucket.getTxBytes();
        } catch (RemoteException e) {
            e.printStackTrace();
        }

        return totalBytes;
    }

    private long getMonthlyWifiUsage() {
        if (!checkUsageStatsPermission()) {
            return -1;
        }

        NetworkStatsManager networkStatsManager = (NetworkStatsManager) getSystemService(Context.NETWORK_STATS_SERVICE);
        if (networkStatsManager == null)
            return 0;

        java.util.Calendar calendar = java.util.Calendar.getInstance();
        calendar.set(java.util.Calendar.DAY_OF_MONTH, 1);
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0);
        calendar.set(java.util.Calendar.MINUTE, 0);
        calendar.set(java.util.Calendar.SECOND, 0);
        calendar.set(java.util.Calendar.MILLISECOND, 0);
        long startTime = calendar.getTimeInMillis();
        long endTime = System.currentTimeMillis();

        long totalBytes = 0;
        try {
            NetworkStats.Bucket bucket = networkStatsManager.querySummaryForDevice(
                    NetworkCapabilities.TRANSPORT_WIFI,
                    "",
                    startTime,
                    endTime);
            totalBytes = bucket.getRxBytes() + bucket.getTxBytes();
        } catch (RemoteException e) {
            e.printStackTrace();
        }

        return totalBytes;
    }

    private boolean checkUsageStatsPermission() {
        AppOpsManager appOps = (AppOpsManager) getSystemService(Context.APP_OPS_SERVICE);
        int mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), getPackageName());
        return mode == AppOpsManager.MODE_ALLOWED;
    }

    private void requestUsageStatsPermission() {
        Intent intent = new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS);
        tryStartActivity(intent);
    }

    private boolean checkWriteSettingsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.System.canWrite(this);
        }
        return true;
    }

    private void requestWriteSettingsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            tryStartActivity(intent);
        }
    }

    private boolean setSystemBrightness(int brightness) {
        if (checkWriteSettingsPermission()) {
            try {
                android.content.ContentResolver resolver = getContentResolver();
                // 1. Standard Android brightness
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, brightness);
                
                // 2. Try common TV "Backlight" keys (Vendor specific)
                Settings.System.putInt(resolver, "backlight", brightness);
                Settings.System.putInt(resolver, "backlight_level", brightness);
                
                return true;
            } catch (Exception e) {
                // Ignore errors on specific keys as they may not exist
                return true;
            }
        }
        return false;
    }

    private void voiceEvent(String phase, String text, String message, double level) {
        if (launcherChannel == null) return;
        Map<String, Object> event = new HashMap<>();
        event.put("phase", phase); event.put("text", text);
        event.put("message", message); event.put("level", level);
        launcherChannel.invokeMethod("voiceEvent", event);
    }

    private void stopVoiceSearch() {
        voiceRequested = false;
        voiceGeneration++;
        if (voiceRecognizer != null) {
            voiceRecognizer.setRecognitionListener(null);
            voiceRecognizer.cancel();
            voiceRecognizer.destroy();
            voiceRecognizer = null;
        }
    }

    private void startVoiceRecognizer() {
        if (!voiceRequested) return;
        if (!android.speech.SpeechRecognizer.isRecognitionAvailable(this)) {
            voiceEvent("error", "", "Voice recognition is unavailable on this TV. Use keyboard search instead.", 0);
            stopVoiceSearch(); return;
        }
        try {
            final long generation = voiceGeneration;
            voiceRecognizer = android.speech.SpeechRecognizer.createSpeechRecognizer(this);
            voiceRecognizer.setRecognitionListener(new android.speech.RecognitionListener() {
                private boolean current() { return voiceRequested && generation == voiceGeneration; }
                public void onReadyForSpeech(android.os.Bundle params) { if (current()) voiceEvent("listening", "", "", 0); }
                public void onBeginningOfSpeech() { if (current()) voiceEvent("listening", "", "", .2); }
                public void onRmsChanged(float rms) { if (current()) voiceEvent("level", "", "", Math.max(0, Math.min(1, (rms + 2) / 12.0))); }
                public void onBufferReceived(byte[] buffer) {}
                public void onEndOfSpeech() { if (current()) voiceEvent("processing", "", "", 0); }
                public void onError(int error) {
                    if (!current()) return;
                    String message = switch (error) {
                        case android.speech.SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone access was denied. Allow it in Android app settings, or use keyboard search.";
                        case android.speech.SpeechRecognizer.ERROR_NO_MATCH, android.speech.SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech recognised. Try again or use keyboard search.";
                        case android.speech.SpeechRecognizer.ERROR_NETWORK, android.speech.SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "The speech service could not connect. Check your network or use keyboard search.";
                        case android.speech.SpeechRecognizer.ERROR_AUDIO -> "The TV microphone could not be opened. Check your remote or use keyboard search.";
                        default -> "Voice search could not finish. Try again or use keyboard search.";
                    };
                    voiceEvent("error", "", message, 0);
                    stopVoiceSearch();
                }
                private String transcript(android.os.Bundle results) {
                    ArrayList<String> words = results.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION);
                    return words == null || words.isEmpty() ? "" : words.get(0);
                }
                public void onResults(android.os.Bundle results) {
                    if (!current()) return;
                    String text = transcript(results);
                    voiceEvent(text.isEmpty() ? "error" : "result", text, text.isEmpty() ? "No speech recognised. Try again." : "", 0);
                    stopVoiceSearch();
                }
                public void onPartialResults(android.os.Bundle results) { if (current()) voiceEvent("partial", transcript(results), "", 0); }
                public void onEvent(int type, android.os.Bundle params) {}
            });
            Intent intent = new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            voiceEvent("starting", "", "", 0);
            voiceRecognizer.startListening(intent);
        } catch (Exception error) {
            voiceEvent("error", "", "Voice recognition could not start. Use keyboard search instead.", 0);
            stopVoiceSearch();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode == MEDIA_PERMISSION_REQUEST_CODE && mediaPermissionResult != null) {
            mediaPermissionResult.success(null); mediaPermissionResult = null;
        }
        if (requestCode == SETUP_PERMISSION_REQUEST && setupPermissionResult != null) {
            setupPermissionResult.success(null);
            setupPermissionResult = null;
        }
        if (requestCode == BLUETOOTH_PERMISSION && bluetoothPermissionResult != null) {
            bluetoothPermissionResult.success(null); bluetoothPermissionResult = null;
        }
        if (requestCode == VOICE_PERMISSION_REQUEST && voiceRequested) {
            if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) startVoiceRecognizer();
            else { voiceEvent("error", "", "Microphone access was denied. Use keyboard search or allow access in Android app settings.", 0); stopVoiceSearch(); }
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        startedAt = android.os.SystemClock.uptimeMillis();
    }

    /** When the activity last became visible; 0 while it is not. */
    private long startedAt = 0;

    @Override
    protected void onStop() {
        startedAt = 0;
        if (voiceRecognizer != null) {
            voiceEvent("error", "", "Voice search paused. Try again when you return.", 0);
            stopVoiceSearch();
        }
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        if (navigationSounds != null) {
            navigationSounds.release();
            navigationSounds = null;
            navigationSoundIds.clear();
            readyNavigationSounds.clear();
        }
        if (setupPermissionResult != null) { setupPermissionResult.success(null); setupPermissionResult = null; }
        if (backupResult != null) {backupResult.error("cancelled", "Activity closed", null); backupResult = null;}
        if (bluetoothPermissionResult != null) {bluetoothPermissionResult.success(null); bluetoothPermissionResult = null;}
        if (mediaPermissionResult != null) {mediaPermissionResult.success(null); mediaPermissionResult = null;}
        LumaNotificationListener.onChange = null;
        stopVoiceSearch(); artworkExecutor.shutdownNow(); super.onDestroy(); }

    /** Android TV often hides this screen; returns false when no settings app handles it. */
    private boolean openNotificationAccessSettings() {
        String[] actions = {
            "android.settings.NOTIFICATION_LISTENER_DETAIL_SETTINGS",
            Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,
        };
        for (String action : actions) {
            Intent intent = new Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (action.endsWith("DETAIL_SETTINGS")) {
                if (Build.VERSION.SDK_INT < 30) continue;
                intent.putExtra("android.provider.extra.NOTIFICATION_LISTENER_COMPONENT_NAME",
                        new ComponentName(this, LumaNotificationListener.class).flattenToString());
            }
            try {
                startActivity(intent);
                return true;
            } catch (Exception ignored) {
                // Not on this TV; try the next screen.
            }
        }
        return false;
    }

    /** Memory class of the device, used by Luma's automatic Lite mode. */
    private Map<String, Object> getDeviceProfile() {
        Map<String, Object> data = new HashMap<>();
        android.app.ActivityManager am = (android.app.ActivityManager) getSystemService(ACTIVITY_SERVICE);
        android.app.ActivityManager.MemoryInfo info = new android.app.ActivityManager.MemoryInfo();
        am.getMemoryInfo(info);
        data.put("isLowRamDevice", am.isLowRamDevice());
        data.put("totalMemBytes", info.totalMem);
        data.put("memoryClassMb", am.getMemoryClass());
        data.put("sdkInt", Build.VERSION.SDK_INT);
        data.put("model", Build.MODEL);
        return data;
    }

    private Map<String, Object> connectionStatus() {
        Map<String, Object> data = new HashMap<>();
        try {
            Map<String, Object> info = getActiveNetworkInformation();
            int type = ((Number) info.get("networkType")).intValue();
            String name = switch(type) {case 0 -> "Mobile"; case 1 -> "Wi-Fi"; case 2 -> "VPN"; case 3 -> "Ethernet"; default -> "Disconnected";};
            data.put("network", name + (Boolean.TRUE.equals(info.get("internetAccess")) ? " · Internet available" : " · No validated Internet"));
        } catch (Exception error) { data.put("network", "Connection status unavailable"); }
        boolean permitted = Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
        data.put("bluetoothPermission", permitted);
        try {
            BluetoothManager manager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
            BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
            data.put("bluetoothSupported", adapter != null);
            if (adapter == null) data.put("bluetooth", "Bluetooth not available");
            else if (!permitted) data.put("bluetooth", "Allow accessory status in Luma Settings");
            else data.put("bluetooth", adapter.isEnabled() ? "On · " + adapter.getBondedDevices().size() + " paired accessories" : "Bluetooth off");
        } catch (Exception error) { data.put("bluetooth", "Accessory status unavailable"); }
        data.put("defaultHome", isDefaultLauncher());
        return data;
    }

    private void localBackup(MethodChannel.Result result, String json) {
        artworkExecutor.execute(() -> {
            try {
                File dir = new File(getFilesDir(), "backups");
                if (!dir.exists() && !dir.mkdirs()) throw new java.io.IOException("Cannot create backup directory");
                File target = new File(dir, "Luma-latest.json");
                Object response;
                if (json != null) {
                    byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
                    if (bytes.length > 1024 * 1024) throw new java.io.IOException("Backup exceeds 1 MB");
                    android.util.AtomicFile atomic = new android.util.AtomicFile(target);
                    java.io.FileOutputStream output = null;
                    try {output = atomic.startWrite(); output.write(bytes); atomic.finishWrite(output);}
                    catch (Exception error) {if (output != null) atomic.failWrite(output); throw error;}
                    response = "Local backup saved on this device. Use Export file to keep a copy outside Luma. Uninstalling Luma deletes local backups.";
                } else {
                    if (target.length() > 1024 * 1024) throw new java.io.IOException("Backup exceeds 1 MB");
                    android.util.AtomicFile atomic = new android.util.AtomicFile(target);
                    try {response = new String(atomic.readFully(), StandardCharsets.UTF_8);}
                    catch (java.io.FileNotFoundException error) {throw new java.io.IOException("No local backup has been saved yet");}
                }
                Object answer = response; runOnUiThread(() -> result.success(answer));
            } catch (Exception error) {runOnUiThread(() -> result.error("backup", error.getMessage(), null));}
        });
    }

    private void chooseBackupFile(MethodChannel.Result result, String json) {
        if (backupResult != null) {result.error("busy", "A backup picker is already open", null); return;}
        if (json != null && json.getBytes(StandardCharsets.UTF_8).length > 1024 * 1024) {result.error("size", "Backup exceeds 1 MB", null); return;}
        boolean writing = json != null;
        Intent intent = new Intent(writing ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(writing ? "application/json" : "*/*");
        if (writing) intent.putExtra(Intent.EXTRA_TITLE, "Luma-backup.json");
        ResolveInfo handler = getPackageManager().resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY);
        if (handler == null || handler.activityInfo == null ||
                "com.android.tv.frameworkpackagestubs".equals(handler.activityInfo.packageName)) {
            if (writing && Build.VERSION.SDK_INT >= 29) {
                saveBackupToDownloads(result, json);
            } else {
                result.error("picker", "This TV has no file picker. Use Load local backup or Enter backup JSON instead.", null);
            }
            return;
        }
        try {
            backupWriting = writing; backupJson = json; backupResult = result;
            startActivityForResult(intent, writing ? BACKUP_WRITE : BACKUP_READ);
        } catch (Exception error) {
            backupResult = null; backupJson = null;
            result.error("picker", "No file picker is available. Use Copy backup / JSON instead.", null);
        }
    }

    private void saveBackupToDownloads(MethodChannel.Result result, String json) {
        artworkExecutor.execute(() -> {
            Uri target = null;
            try {
                android.content.ContentValues values = new android.content.ContentValues();
                values.put(MediaStore.Downloads.DISPLAY_NAME, "Luma-backup-" + System.currentTimeMillis() + ".json");
                values.put(MediaStore.Downloads.MIME_TYPE, "application/json");
                values.put(MediaStore.Downloads.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS);
                values.put(MediaStore.Downloads.IS_PENDING, 1);
                target = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (target == null) throw new java.io.IOException("Cannot create backup in Downloads");
                try (OutputStream output = getContentResolver().openOutputStream(target, "wt")) {
                    if (output == null) throw new java.io.IOException("Cannot open backup destination");
                    output.write(json.getBytes(StandardCharsets.UTF_8));
                }
                values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0);
                getContentResolver().update(target, values, null, null);
                runOnUiThread(() -> result.success(true));
            } catch (Exception error) {
                if (target != null) getContentResolver().delete(target, null, null);
                runOnUiThread(() -> result.error("backup", "Could not save to Downloads. Use Copy backup instead.", null));
            }
        });
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if ((requestCode != BACKUP_READ && requestCode != BACKUP_WRITE) || backupResult == null) return;
        MethodChannel.Result result = backupResult;
        String json = backupJson; boolean writing = backupWriting;
        backupResult = null; backupJson = null;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {result.success(writing ? false : null); return;}
        Uri uri = data.getData();
        artworkExecutor.execute(() -> {
            try {
                Object response;
                if (writing) {
                    try (OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
                        if (output == null) throw new java.io.IOException("Cannot open backup destination");
                        output.write(json.getBytes(StandardCharsets.UTF_8)); output.flush();
                    }
                    response = true;
                } else {
                    try (InputStream input = getContentResolver().openInputStream(uri); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                        if (input == null) throw new java.io.IOException("Cannot open backup");
                        byte[] buffer = new byte[8192]; int count;
                        while ((count = input.read(buffer)) != -1) {
                            if (output.size() + count > 1024 * 1024) throw new java.io.IOException("Backup exceeds 1 MB");
                            output.write(buffer, 0, count);
                        }
                        response = new String(output.toByteArray(), StandardCharsets.UTF_8);
                    }
                }
                Object answer = response; runOnUiThread(() -> result.success(answer));
            } catch (Exception error) { runOnUiThread(() -> result.error("backup", error.getMessage(), null)); }
        });
    }

    private boolean openQuickSettings(String section) {
        String action = switch (section == null ? "all" : section) {
            case "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS;
            case "sound" -> Settings.ACTION_SOUND_SETTINGS;
            case "display" -> Settings.ACTION_DISPLAY_SETTINGS;
            default -> Settings.ACTION_SETTINGS;
        };
        if (tryStartActivity(new Intent(action))) return true;
        // Mi Box exposes picture and audio in a combined DisplaySound activity,
        // but does not advertise DISPLAY_SETTINGS. Use that combined module
        // before falling back to the general settings page.
        if ("display".equals(section)) {
            Intent combined = new Intent(Settings.ACTION_SOUND_SETTINGS);
            ResolveInfo handler = getPackageManager().resolveActivity(combined, 0);
            if (handler != null && handler.activityInfo != null &&
                    handler.activityInfo.name.toLowerCase(java.util.Locale.ROOT).contains("displaysound") &&
                    tryStartActivity(combined)) return true;
        }
        // Some Android TV firmware has no BLUETOOTH_SETTINGS handler, but
        // exposes the system accessory pairing screen instead.
        if ("bluetooth".equals(section)) {
            Intent accessories = new Intent(Intent.ACTION_MAIN);
            accessories.setClassName("com.android.tv.settings",
                    "com.android.tv.settings.accessories.AddAccessoryActivity");
            if (tryStartActivity(accessories)) return true;
        }
        // TV firmware may expose only its top-level settings activity.
        return tryStartActivity(new Intent(Settings.ACTION_SETTINGS));
    }

    private boolean openWifiSettings() {
        // 1. Try Android Q+ WiFi panel
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent panelIntent = new Intent(Settings.Panel.ACTION_WIFI);
            if (tryStartActivity(panelIntent)) {
                return true;
            }
        }

        // 2. Try standard WiFi settings
        Intent wifiIntent = new Intent(Settings.ACTION_WIFI_SETTINGS);
        if (tryStartActivity(wifiIntent)) {
            return true;
        }

        // 3. Fallback to general wireless settings
        Intent wirelessIntent = new Intent(Settings.ACTION_WIRELESS_SETTINGS);
        if (tryStartActivity(wirelessIntent)) {
            return true;
        }

        // 4. Final fallback - open main settings
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean openScreensaverSettings() {
        // 1. Try Android TV specific screensaver settings (DaydreamActivity - from
        // Aerial Views)
        Intent tvIntent = new Intent(Intent.ACTION_MAIN);
        tvIntent.setClassName("com.android.tv.settings",
                "com.android.tv.settings.device.display.daydream.DaydreamActivity");
        if (tryStartActivity(tvIntent)) {
            return true;
        }

        // 2. Try standard Android screensaver/dream settings
        Intent dreamIntent = new Intent(Settings.ACTION_DREAM_SETTINGS);
        if (tryStartActivity(dreamIntent)) {
            return true;
        }

        // 3. FALLBACK: Try Display Settings (often contains screensaver on newer
        // Android TV/Google TV)
        Intent displayIntent = new Intent(Settings.ACTION_DISPLAY_SETTINGS);
        if (tryStartActivity(displayIntent)) {
            return true;
        }

        // 4. Final fallback - open main settings
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean checkWatchNextPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        return checkSelfPermission(PERMISSION_READ_TV_LISTINGS) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestWatchNextPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return;
        }
        if (checkWatchNextPermission()) {
            return;
        }
        ActivityCompat.requestPermissions(
                this,
                new String[]{PERMISSION_READ_TV_LISTINGS},
                REQUEST_CODE_READ_TV_LISTINGS);
    }

    private List<Map<String, Object>> getWatchNextItems(int limit) {
        List<Map<String, Object>> items = new ArrayList<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return items;

        if (!checkWatchNextPermission()) {
            android.util.Log.w("MainActivity", "READ_TV_LISTINGS permission not granted");
            return items;
        }

        try {
            String[] projection = {
                TvContract.WatchNextPrograms._ID,
                TvContract.WatchNextPrograms.COLUMN_TITLE,
                TvContract.WatchNextPrograms.COLUMN_SHORT_DESCRIPTION,
                TvContract.WatchNextPrograms.COLUMN_POSTER_ART_URI,
                TvContract.WatchNextPrograms.COLUMN_PACKAGE_NAME,
                TvContract.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID,
                TvContract.WatchNextPrograms.COLUMN_DURATION_MILLIS,
                TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS,
                TvContract.WatchNextPrograms.COLUMN_INTENT_URI,
                TvContract.WatchNextPrograms.COLUMN_WATCH_NEXT_TYPE
            };

            String sortOrder = TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS + " DESC";

            try (Cursor cursor = getContentResolver().query(
                    TvContract.WatchNextPrograms.CONTENT_URI,
                    projection,
                    null,
                    null,
                    sortOrder)) {

                if (cursor != null && cursor.moveToFirst()) {
                    int count = 0;
                    int fetchLimit = Math.max(limit * 3, 30);

                    do {
                        try {
                            Map<String, Object> item = new HashMap<>();

                            int idIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms._ID);
                            int titleIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_TITLE);
                            int descIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_SHORT_DESCRIPTION);
                            int posterIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_POSTER_ART_URI);
                            int pkgIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_PACKAGE_NAME);
                            int contentIdIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_INTERNAL_PROVIDER_ID);
                            int durationIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_DURATION_MILLIS);
                            int lastEngIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS);
                            int intentUriIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_INTENT_URI);
                            int watchTypeIndex = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_WATCH_NEXT_TYPE);
                            int aspectRatioIndex = cursor.getColumnIndex(COLUMN_ASPECT_RATIO);

                            String title = (titleIndex >= 0 && !cursor.isNull(titleIndex))
                                ? cursor.getString(titleIndex) : null;
                            if (title == null || title.isEmpty()) {
                                continue;
                            }

                            item.put("id", idIndex >= 0 ? cursor.getLong(idIndex) : 0);
                            item.put("title", title);
                            item.put("description", (descIndex >= 0 && !cursor.isNull(descIndex))
                                ? cursor.getString(descIndex) : null);
                            item.put("posterUri", (posterIndex >= 0 && !cursor.isNull(posterIndex))
                                ? cursor.getString(posterIndex) : null);
                            item.put("packageName", (pkgIndex >= 0 && !cursor.isNull(pkgIndex))
                                ? cursor.getString(pkgIndex) : null);
                            item.put("contentId", (contentIdIndex >= 0 && !cursor.isNull(contentIdIndex))
                                ? cursor.getString(contentIdIndex) : null);
                            item.put("duration", (durationIndex >= 0 && !cursor.isNull(durationIndex))
                                ? cursor.getInt(durationIndex) : null);

                            item.put("intentUri", (intentUriIndex >= 0 && !cursor.isNull(intentUriIndex))
                                ? cursor.getString(intentUriIndex) : null);

                            item.put("watchNextType", (watchTypeIndex >= 0 && !cursor.isNull(watchTypeIndex))
                                ? cursor.getInt(watchTypeIndex) : 0);

                            item.put("aspectRatio", (aspectRatioIndex >= 0 && !cursor.isNull(aspectRatioIndex))
                                ? cursor.getString(aspectRatioIndex) : null);

                            if (lastEngIndex >= 0 && !cursor.isNull(lastEngIndex)) {
                                item.put("lastEngagementDate", cursor.getLong(lastEngIndex));
                            }

                            item.put("progressPercent", 0);

                            items.add(item);
                            count++;
                        } catch (Exception rowEx) {
                            android.util.Log.w("MainActivity", "Error parsing Watch Next row", rowEx);
                        }
                    } while (cursor.moveToNext() && count < fetchLimit);
                }
            }
        } catch (SecurityException e) {
            android.util.Log.w("MainActivity", "SecurityException when querying Watch Next: " + e.getMessage());
            throw e;
        } catch (Exception e) {
            android.util.Log.e("MainActivity", "Error querying Watch Next", e);
            throw new IllegalStateException("Programme provider unavailable", e);
        }

        return items.subList(0, Math.min(items.size(), limit));
    }

    private boolean launchWatchNextItem(String packageName, String contentId, String action) {
        android.util.Log.d("MainActivity", "launchWatchNextItem: packageName=" + packageName + ", contentId=" + contentId + ", action=" + action);

        // Try to use the intent action/uri from arguments first
        if (action != null && !action.isEmpty()) {
            try {
                Intent intent;
                if (action.startsWith("intent://")) {
                    android.util.Log.d("MainActivity", "Parsing intent URI: " + action);
                    intent = Intent.parseUri(action, Intent.URI_INTENT_SCHEME);
                } else if (action.startsWith("content://") || action.startsWith("http://") || action.startsWith("https://")) {
                    android.util.Log.d("MainActivity", "Creating VIEW intent for URI: " + action);
                    intent = new Intent(Intent.ACTION_VIEW, Uri.parse(action));
                } else if (action.contains(":")) {
                    try {
                        android.util.Log.d("MainActivity", "Trying to parse as intent URI: " + action);
                        intent = Intent.parseUri(action, Intent.URI_INTENT_SCHEME);
                    } catch (Exception e) {
                        android.util.Log.w("MainActivity", "Failed to parse as intent URI, treating as action: " + action);
                        intent = new Intent(action);
                    }
                } else {
                    android.util.Log.d("MainActivity", "Creating intent with action: " + action);
                    intent = new Intent(action);
                }

                if (packageName != null) {
                    intent.setPackage(packageName);
                    android.util.Log.d("MainActivity", "Set package to: " + packageName);
                }
                if (contentId != null) {
                    intent.putExtra("contentId", contentId);
                    android.util.Log.d("MainActivity", "Added contentId extra: " + contentId);
                }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                android.util.Log.d("MainActivity", "Starting activity with intent: " + intent.toUri(0));
                return tryStartActivity(intent);
            } catch (Exception e) {
                android.util.Log.e("MainActivity", "Failed to launch with action/uri: " + action, e);
            }
        }

        // Fallback to package name
        if (packageName == null) {
            android.util.Log.w("MainActivity", "No package name or action available, cannot launch");
            return false;
        }

        try {
            android.util.Log.d("MainActivity", "Falling back to package launch: " + packageName);
            PackageManager pm = getPackageManager();
            Intent intent = pm.getLeanbackLaunchIntentForPackage(packageName);
            if (intent == null) {
                intent = pm.getLaunchIntentForPackage(packageName);
            }

            if (intent != null) {
                if (contentId != null) {
                    intent.putExtra("contentId", contentId);
                }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                return tryStartActivity(intent);
            } else {
                android.util.Log.w("MainActivity", "No launch intent found for package: " + packageName);
            }
        } catch (Exception e) {
            android.util.Log.e("MainActivity", "Error launching Watch Next item for package: " + packageName, e);
        }

        return false;
    }

    /**
     * Load image bytes from a content:// URI
     */
    private byte[] loadContentUriImage(String contentUri) {
        android.util.Log.d("MainActivity", "Loading content URI image: " + contentUri);
        try {
            android.net.Uri uri = android.net.Uri.parse(contentUri);
            android.util.Log.d("MainActivity", "Parsed URI: " + uri);

            try (java.io.InputStream inputStream = getContentResolver().openInputStream(uri)) {
                if (inputStream != null) {
                    java.io.ByteArrayOutputStream byteArrayOutputStream = new java.io.ByteArrayOutputStream();
                    byte[] buffer = new byte[8192];  // Increased buffer size
                    int length;
                    while ((length = inputStream.read(buffer)) != -1) {
                        if (byteArrayOutputStream.size() + length > 8 * 1024 * 1024) {
                            throw new java.io.IOException("Image exceeds 8 MB");
                        }
                        byteArrayOutputStream.write(buffer, 0, length);
                    }
                    byte[] result = byteArrayOutputStream.toByteArray();
                    android.util.Log.d("MainActivity", "Loaded " + result.length + " bytes from content URI");
                    return result;
                } else {
                    android.util.Log.w("MainActivity", "openInputStream returned null for: " + contentUri);
                }
            }
        } catch (SecurityException e) {
            android.util.Log.w("MainActivity", "SecurityException loading content URI: " + e.getMessage());
        } catch (Exception e) {
            android.util.Log.e("MainActivity", "Error loading content URI image: " + contentUri, e);
        }
        android.util.Log.w("MainActivity", "Returning empty byte array for: " + contentUri);
        return new byte[0];
    }

    private static final int MEDIA_PERMISSION_REQUEST_CODE = 9001;

    private List<Map<String, String>> getAppActions(String pkg) {
        List<Map<String, String>> actions = new ArrayList<>();
        if (pkg == null || pkg.isEmpty()) return actions;
        try {
            getPackageManager().getApplicationInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException missing) { return actions; }
        if (Build.VERSION.SDK_INT >= 25) {
            try {
                LauncherApps launcher = getSystemService(LauncherApps.class);
                if (launcher != null && launcher.hasShortcutHostPermission()) {
                    LauncherApps.ShortcutQuery query = new LauncherApps.ShortcutQuery()
                        .setPackage(pkg).setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST |
                            LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC | LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED);
                    List<ShortcutInfo> shortcuts = launcher.getShortcuts(query, android.os.Process.myUserHandle());
                    if (shortcuts != null) {
                        shortcuts.sort(java.util.Comparator.comparingInt(ShortcutInfo::getRank));
                        java.util.Set<String> seen = new java.util.HashSet<>();
                        for (ShortcutInfo shortcut : shortcuts) {
                            if (!shortcut.isEnabled() || shortcut.getShortLabel() == null || !seen.add(shortcut.getId())) continue;
                            addAppAction(actions, "shortcut:" + shortcut.getId(), shortcut.getShortLabel().toString());
                            if (actions.size() == 4) break;
                        }
                    }
                }
            } catch (RuntimeException ignored) { /* Some TVs do not grant shortcut host access. */ }
        }
        for (String action : new String[]{Intent.ACTION_SEARCH, Intent.ACTION_APPLICATION_PREFERENCES}) {
            Intent intent = new Intent(action).setPackage(pkg);
            ResolveInfo target = getPackageManager().resolveActivity(intent, 0);
            if (target != null && target.activityInfo != null && target.activityInfo.exported &&
                pkg.equals(target.activityInfo.packageName) &&
                (target.activityInfo.permission == null || checkSelfPermission(target.activityInfo.permission) == PackageManager.PERMISSION_GRANTED)) {
                if (action.equals(Intent.ACTION_SEARCH)) {
                    // Mi Box PatchWall advertises SEARCH/searchable metadata but
                    // its HomeIntentActivity finishes without handling the query.
                    // Keep its working App info action instead of a dead shortcut.
                    if (pkg.equals("com.mitv.tvhome.atv")) continue;
                    android.app.SearchManager search = getSystemService(android.app.SearchManager.class);
                    android.content.ComponentName component = new android.content.ComponentName(pkg, target.activityInfo.name);
                    android.app.SearchableInfo info = search == null ? null : search.getSearchableInfo(component);
                    if (info == null || !pkg.equals(info.getSearchActivity().getPackageName())) continue;
                    try {
                        ActivityInfo handler = getPackageManager().getActivityInfo(info.getSearchActivity(), 0);
                        if (!handler.exported || (handler.permission != null &&
                            checkSelfPermission(handler.permission) != PackageManager.PERMISSION_GRANTED)) continue;
                    } catch (PackageManager.NameNotFoundException missing) { continue; }
                }
                addAppAction(actions, action.equals(Intent.ACTION_SEARCH) ? "search" : "preferences",
                    action.equals(Intent.ACTION_SEARCH) ? "Search in app" : "App settings");
            }
        }
        addAppAction(actions, "info", "App info");
        return actions;
    }

    private void addAppAction(List<Map<String, String>> actions, String id, String label) {
        Map<String, String> action = new HashMap<>();
        action.put("id", id);
        action.put("label", label);
        actions.add(action);
    }

    private Map<String, Object> setupStatus() {
        Map<String, Object> status = new HashMap<>();
        status.put("microphone", checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED);
        status.put("media", checkMediaPermissions());
        status.put("bluetooth", Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED);
        status.put("watchNext", checkWatchNextPermission());
        status.put("home", isDefaultLauncher());
        status.put("usage", checkUsageStatsPermission());
        status.put("brightness", checkWriteSettingsPermission());
        return status;
    }

    private void requestSetupPermission(String key, MethodChannel.Result result) {
        try {
            String[] permissions = null;
            switch (key) {
                case "microphone" -> permissions = new String[]{Manifest.permission.RECORD_AUDIO};
                case "media" -> permissions = Build.VERSION.SDK_INT >= 33
                    ? new String[]{Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO}
                    : new String[]{Manifest.permission.READ_EXTERNAL_STORAGE};
                case "bluetooth" -> {
                    if (Build.VERSION.SDK_INT >= 31) permissions = new String[]{Manifest.permission.BLUETOOTH_CONNECT};
                }
                case "watchNext" -> permissions = new String[]{PERMISSION_READ_TV_LISTINGS};
                case "home" -> {
                    if (Build.VERSION.SDK_INT >= 29) {
                        android.app.role.RoleManager roles = getSystemService(android.app.role.RoleManager.class);
                        if (roles != null && roles.isRoleAvailable(android.app.role.RoleManager.ROLE_HOME)
                                && !roles.isRoleHeld(android.app.role.RoleManager.ROLE_HOME)) {
                            startActivityForResult(roles.createRequestRoleIntent(android.app.role.RoleManager.ROLE_HOME), 9414);
                            result.success(null);
                            return;
                        }
                    }
                    startActivity(new Intent(Settings.ACTION_HOME_SETTINGS));
                }
                case "usage" -> requestUsageStatsPermission();
                case "brightness" -> requestWriteSettingsPermission();
                case "appSettings" -> startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    android.net.Uri.parse("package:" + getPackageName())));
                default -> { result.error("unknown", "Unknown setup option", null); return; }
            }
            if (permissions == null) { result.success(null); return; }
            List<String> missing = new ArrayList<>();
            for (String permission : permissions) {
                if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) missing.add(permission);
            }
            if (missing.isEmpty()) { result.success(null); return; }
            if (setupPermissionResult != null) { result.error("busy", "A permission request is already open", null); return; }
            setupPermissionResult = result;
            ActivityCompat.requestPermissions(this, missing.toArray(new String[0]), SETUP_PERMISSION_REQUEST);
        } catch (Exception error) {
            setupPermissionResult = null;
            result.error("unavailable", "This TV does not expose this setting", null);
        }
    }

    private boolean checkMediaPermissions() {
        return checkMediaPermissions(null);
    }

    private boolean checkMediaPermissions(String type) {
        if (Build.VERSION.SDK_INT >= 34 && checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED) return true;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            boolean images = checkSelfPermission(Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED;
            boolean videos = checkSelfPermission(Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED;
            return "image".equals(type) ? images : "video".equals(type) ? videos : images && videos;
        }
        return checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestMediaPermissions(String type) {
        String[] permissions;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            List<String> requested = new ArrayList<>();
            if (!"video".equals(type)) requested.add(Manifest.permission.READ_MEDIA_IMAGES);
            if (!"image".equals(type)) requested.add(Manifest.permission.READ_MEDIA_VIDEO);
            if (Build.VERSION.SDK_INT >= 34) requested.add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED);
            permissions = requested.toArray(new String[0]);
        } else {
            permissions = new String[]{Manifest.permission.READ_EXTERNAL_STORAGE};
        }
        ActivityCompat.requestPermissions(this, permissions, MEDIA_PERMISSION_REQUEST_CODE);
    }

    private List<Map<String, Object>> getMediaStoreImages() {
        List<Map<String, Object>> images = new ArrayList<>();
        String[] projection = {
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED
        };
        String sortOrder = MediaStore.Images.Media.DATE_ADDED + " DESC";

        try (Cursor cursor = getContentResolver().query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection, null, null, sortOrder)) {
            if (cursor != null) {
                int idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID);
                int nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME);
                int dataCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA);
                while (cursor.moveToNext()) {
                    long id = cursor.getLong(idCol);
                    Uri contentUri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, String.valueOf(id));
                    Map<String, Object> item = new HashMap<>();
                    item.put("id", id);
                    item.put("name", cursor.getString(nameCol));
                    item.put("path", cursor.getString(dataCol));
                    item.put("uri", contentUri.toString());
                    images.add(item);
                }
            }
        } catch (Exception error) {
            throw new IllegalStateException("Media library unavailable", error);
        }
        return images;
    }

    private List<Map<String, Object>> getMediaStoreVideos() {
        List<Map<String, Object>> videos = new ArrayList<>();
        String[] projection = {
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DATE_ADDED
        };
        String sortOrder = MediaStore.Video.Media.DATE_ADDED + " DESC";

        try (Cursor cursor = getContentResolver().query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection, null, null, sortOrder)) {
            if (cursor != null) {
                int idCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID);
                int nameCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME);
                int dataCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA);
                while (cursor.moveToNext()) {
                    long id = cursor.getLong(idCol);
                    Uri contentUri = Uri.withAppendedPath(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, String.valueOf(id));
                    Map<String, Object> item = new HashMap<>();
                    item.put("id", id);
                    item.put("name", cursor.getString(nameCol));
                    item.put("path", cursor.getString(dataCol));
                    item.put("uri", contentUri.toString());
                    videos.add(item);
                }
            }
        } catch (Exception error) {
            throw new IllegalStateException("Media library unavailable", error);
        }
        return videos;
    }

    private byte[] getMediaStoreImageThumbnail(String source) {
        Bitmap bitmap = null;
        try {
            Uri uri = Uri.parse(source);
            if (Build.VERSION.SDK_INT >= 29) {
                bitmap = getContentResolver().loadThumbnail(uri, new android.util.Size(320, 180), null);
            } else {
                android.graphics.BitmapFactory.Options options = new android.graphics.BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                try (java.io.InputStream input = getContentResolver().openInputStream(uri)) {
                    android.graphics.BitmapFactory.decodeStream(input, null, options);
                }
                options.inSampleSize = 1;
                while (options.outWidth / options.inSampleSize > 640 || options.outHeight / options.inSampleSize > 360) {
                    options.inSampleSize *= 2;
                }
                options.inJustDecodeBounds = false;
                try (java.io.InputStream input = getContentResolver().openInputStream(uri)) {
                    bitmap = android.graphics.BitmapFactory.decodeStream(input, null, options);
                }
            }
            if (bitmap != null) {
                java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output);
                return output.toByteArray();
            }
        } catch (Exception error) {
            android.util.Log.w("MainActivity", "Image thumbnail unavailable", error);
        } finally {
            if (bitmap != null) bitmap.recycle();
        }
        return new byte[0];
    }

    private byte[] getMediaStoreVideoThumbnail(long id, String path) {
        Bitmap bitmap = null;
        try {
            if (id >= 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Uri uri = android.content.ContentUris.withAppendedId(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id);
                bitmap = getContentResolver().loadThumbnail(
                    uri, new android.util.Size(256, 256), null);
            }
        } catch (Exception ignored) {
        }

        if (bitmap == null && path != null && !path.isEmpty()) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    bitmap = android.media.ThumbnailUtils.createVideoThumbnail(
                        new File(path), new android.util.Size(256, 256), null);
                } else {
                    bitmap = android.media.ThumbnailUtils.createVideoThumbnail(
                        path, MediaStore.Images.Thumbnails.MINI_KIND);
                }
            } catch (Exception ignored) {
            }
        }

        if (bitmap == null && path != null && !path.isEmpty()) {
            android.media.MediaMetadataRetriever retriever = null;
            try {
                retriever = new android.media.MediaMetadataRetriever();
                retriever.setDataSource(path);
                bitmap = retriever.getFrameAtTime(0);
            } catch (Exception ignored) {
            } finally {
                try {
                    if (retriever != null) retriever.release();
                } catch (Exception ignored) {
                }
            }
        }

        if (bitmap == null) return null;
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream);
        bitmap.recycle();
        return stream.toByteArray();
    }

}

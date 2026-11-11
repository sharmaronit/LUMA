import 'dart:convert';
import 'dart:io';

import 'package:luma/luma_channel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

class UpdateResult {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String? apkUrl;
  final String? apkName;

  const UpdateResult({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    this.apkUrl,
    this.apkName,
  });
}

class DownloadedApk {
  final String path;
  final String version;

  const DownloadedApk({required this.path, required this.version});
}

/// ABI-split APKs are named like `luma-1.0.5-arm64-v8a.apk`.
/// Universal builds omit the ABI suffix (`luma-1.0.5.apk`).
bool isAbiSplitApk(String name) {
  return RegExp(
    r"(?:^|[-_])(arm64-v8a|armeabi-v7a|armeabi|x86_64|x86)(?=[-_.]|$)",
    caseSensitive: false,
  ).hasMatch(name);
}

/// A universal APK is safe across TV architectures. Never guess a split ABI.
({String name, String url})? pickReleaseApk(List<dynamic> assets) {
  for (final asset in assets) {
    if (asset is! Map) {
      continue;
    }

    final name = asset["name"];
    final downloadUrl = asset["browser_download_url"];
    if (name is! String || downloadUrl is! String) {
      continue;
    }
    if (!name.toLowerCase().endsWith(".apk")) {
      continue;
    }

    if (isAbiSplitApk(name)) {
      continue;
    }

    return (name: name, url: downloadUrl);
  }

  return null;
}

int compareAppVersions(String left, String right) =>
    Version.parse(
      left.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first,
    ).compareTo(
      Version.parse(
        right.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first,
      ),
    );

class UpdateService {
  static const String _owner = "sharmaronit";
  static const String _repo = "LUMA";
  static const _requestTimeout = Duration(seconds: 15);
  final LumaChannel _lumaChannel;

  UpdateService({LumaChannel? lumaChannel})
    : _lumaChannel = lumaChannel ?? LumaChannel();

  Future<UpdateResult> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final release = await _fetchLatestStableRelease();
    if (release == null) {
      return UpdateResult(
        updateAvailable: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
      );
    }

    final latestVersion = _normalizeVersion(release.tagName);
    final updateAvailable =
        compareAppVersions(latestVersion, currentVersion) > 0;

    return UpdateResult(
      updateAvailable: updateAvailable,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: release.body,
      apkUrl: release.apkDownloadUrl,
      apkName: release.apkName,
    );
  }

  Future<DownloadedApk> downloadApk(UpdateResult update) async {
    if (!update.updateAvailable || update.apkUrl == null) {
      throw StateError("No update APK available to download.");
    }

    final uri = Uri.parse(update.apkUrl!);
    if (uri.scheme != 'https')
      throw const FormatException('Update URL must use HTTPS.');
    final fileName = update.apkName ?? 'luma-${update.latestVersion}.apk';
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*\.apk$').hasMatch(fileName)) {
      throw const FormatException('Invalid APK filename.');
    }
    final httpClient = HttpClient()..connectionTimeout = _requestTimeout;
    File? partial;
    try {
      final request = await httpClient.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, "application/octet-stream");
      request.headers.set(HttpHeaders.userAgentHeader, "Luma-Updater");
      final response = await request.close().timeout(_requestTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          "APK download failed with status ${response.statusCode}",
          uri: uri,
        );
      }

      final directory = await getApplicationSupportDirectory();
      final updatesDirectory = Directory("${directory.path}/updates");
      if (!await updatesDirectory.exists()) {
        await updatesDirectory.create(recursive: true);
      }

      final file = File("${updatesDirectory.path}/$fileName");
      partial = File('${file.path}.part');
      const maximumBytes = 150 * 1024 * 1024;
      var received = 0;
      if (response.contentLength > maximumBytes)
        throw const FormatException('APK exceeds 150 MB.');
      final stream = response.map((chunk) {
        received += chunk.length;
        if (received > maximumBytes)
          throw const FormatException('APK exceeds 150 MB.');
        return chunk;
      });
      final transfer = stream.pipe(partial.openWrite());
      try {
        await transfer.timeout(const Duration(minutes: 3));
      } catch (_) {
        httpClient.close(force: true);
        try {
          await transfer;
        } catch (_) {
          /* Close the file before cleanup. */
        }
        rethrow;
      }
      if (received == 0 ||
          (response.contentLength >= 0 && received != response.contentLength)) {
        throw const FormatException('Incomplete APK download.');
      }
      await partial.rename(file.path);
      return DownloadedApk(path: file.path, version: update.latestVersion);
    } finally {
      httpClient.close(force: true);
      if (partial != null && await partial.exists()) await partial.delete();
    }
  }

  Future<bool> installApk(String apkPath) {
    return _lumaChannel.installApk(apkPath);
  }

  Future<void> requestInstallUnknownAppsPermission() {
    return _lumaChannel.requestInstallUnknownAppsPermission();
  }

  Future<_GitHubRelease?> _fetchLatestStableRelease() async {
    final uri = Uri.parse(
      "https://api.github.com/repos/$_owner/$_repo/releases",
    );
    final httpClient = HttpClient()..connectionTimeout = _requestTimeout;

    try {
      final request = await httpClient.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        "application/vnd.github+json",
      );
      request.headers.set(HttpHeaders.userAgentHeader, "Luma-Updater");

      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          "GitHub release check failed with status ${response.statusCode}",
          uri: uri,
        );
      }

      final body = await utf8.decodeStream(response).timeout(_requestTimeout);
      final parsed = jsonDecode(body);
      if (parsed is! List) {
        throw const FormatException("Unexpected releases response format.");
      }

      for (final releaseData in parsed) {
        if (releaseData is! Map<String, dynamic>) {
          continue;
        }
        if ((releaseData["draft"] as bool?) ?? false) {
          continue;
        }
        if ((releaseData["prerelease"] as bool?) ?? false) {
          continue;
        }

        final tagName = releaseData["tag_name"] as String?;
        final releaseBody = releaseData["body"] as String?;
        final assets = releaseData["assets"];
        if (tagName == null || assets is! List) {
          continue;
        }

        final apk = pickReleaseApk(assets);
        if (apk == null) {
          continue;
        }

        return _GitHubRelease(
          tagName: tagName,
          body: releaseBody,
          apkName: apk.name,
          apkDownloadUrl: apk.url,
        );
      }

      return null;
    } finally {
      httpClient.close(force: true);
    }
  }

  String _normalizeVersion(String version) {
    var normalized = version.trim();
    if (normalized.startsWith("v") || normalized.startsWith("V")) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }
}

class _GitHubRelease {
  final String tagName;
  final String? body;
  final String apkName;
  final String apkDownloadUrl;

  const _GitHubRelease({
    required this.tagName,
    required this.body,
    required this.apkName,
    required this.apkDownloadUrl,
  });
}

import 'package:luma/providers/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'semantic versions ignore build metadata and rank stable above prerelease',
    () {
      expect(compareAppVersions('1.0.11', '1.0.11-cinema.39'), greaterThan(0));
      expect(compareAppVersions('v1.0.11+5000', '1.0.11+4120'), 0);
      expect(compareAppVersions('1.0.12', '1.0.11-cinema.99'), greaterThan(0));
      expect(
        compareAppVersions('1.0.11-cinema.9', '1.0.11-cinema.10'),
        lessThan(0),
      );
    },
  );
  test('Luma prefix ABI APKs are split builds', () {
    expect(isAbiSplitApk('luma-arm64-v8a-release.apk'), true);
    expect(isAbiSplitApk('luma-armeabi-v7a-release.apk'), true);
    expect(isAbiSplitApk('luma-universal-release.apk'), false);
    expect(
      pickReleaseApk([
        {
          'name': 'luma-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.com/arm.apk',
        },
        {
          'name': 'luma-universal-release.apk',
          'browser_download_url': 'https://example.com/all.apk',
        },
      ])?.name,
      'luma-universal-release.apk',
    );
  });
  group("isAbiSplitApk", () {
    test("detects ABI-split release assets", () {
      expect(isAbiSplitApk("luma-1.0.5-arm64-v8a.apk"), isTrue);
      expect(isAbiSplitApk("luma-1.0.5-armeabi-v7a.apk"), isTrue);
      expect(isAbiSplitApk("luma-1.0.5-x86_64.apk"), isTrue);
      expect(isAbiSplitApk("luma-1.0.5-x86.apk"), isTrue);
    });

    test("treats universal assets as non-split", () {
      expect(isAbiSplitApk("luma-1.0.5.apk"), isFalse);
      expect(isAbiSplitApk("luma.apk"), isFalse);
      expect(isAbiSplitApk("arc-launcher-universal-release.apk"), isFalse);
    });
  });

  group("pickReleaseApk", () {
    test("prefers universal APK over ABI splits", () {
      final picked = pickReleaseApk([
        {
          "name": "luma-1.0.5-arm64-v8a.apk",
          "browser_download_url": "https://example.com/arm64.apk",
        },
        {
          "name": "luma-1.0.5-armeabi-v7a.apk",
          "browser_download_url": "https://example.com/armeabi.apk",
        },
        {
          "name": "luma-1.0.5.apk",
          "browser_download_url": "https://example.com/universal.apk",
        },
      ]);

      expect(picked?.name, "luma-1.0.5.apk");
      expect(picked?.url, "https://example.com/universal.apk");
    });

    // The release workflow publishes the universal APK twice: version-stamped
    // (`luma-<tag>.apk`) and as the stable `luma.apk` alias for
    // TV box Downloader codes. The GitHub API returns assets in ASCII name
    // order, where '-' (0x2D) sorts before '.' (0x2E). That puts the ABI
    // splits ahead of the version-stamped universal, and the version-stamped
    // universal ahead of the alias. The fixture below mirrors that real
    // response order; the version-stamped universal is what we must keep
    // resolving so self-updates keep a versioned filename.
    test("prefers the version-stamped universal over the stable alias", () {
      final picked = pickReleaseApk([
        {
          "name": "luma-1.0.10-arm64-v8a.apk",
          "browser_download_url": "https://example.com/arm64.apk",
        },
        {
          "name": "luma-1.0.10-armeabi-v7a.apk",
          "browser_download_url": "https://example.com/armeabi.apk",
        },
        {
          "name": "luma-1.0.10.apk",
          "browser_download_url": "https://example.com/versioned.apk",
        },
        {
          "name": "luma.apk",
          "browser_download_url": "https://example.com/alias.apk",
        },
      ]);

      expect(picked?.name, "luma-1.0.10.apk");
      expect(picked?.url, "https://example.com/versioned.apk");
    });

    // If the API ever stops sorting by name, the alias is picked instead. It is
    // byte-identical to the version-stamped universal, so the update still
    // installs; this pins that we degrade to a working APK rather than a split.
    test("still resolves a valid universal if the alias sorts first", () {
      final picked = pickReleaseApk([
        {
          "name": "luma.apk",
          "browser_download_url": "https://example.com/alias.apk",
        },
        {
          "name": "luma-1.0.10-arm64-v8a.apk",
          "browser_download_url": "https://example.com/arm64.apk",
        },
        {
          "name": "luma-1.0.10-armeabi-v7a.apk",
          "browser_download_url": "https://example.com/armeabi.apk",
        },
        {
          "name": "luma-1.0.10.apk",
          "browser_download_url": "https://example.com/versioned.apk",
        },
      ]);

      expect(picked?.name, "luma.apk");
      expect(isAbiSplitApk(picked!.name), isFalse);
    });

    test("does not offer an arbitrary ABI when no universal exists", () {
      final picked = pickReleaseApk([
        {
          "name": "luma-1.0.5-arm64-v8a.apk",
          "browser_download_url": "https://example.com/arm64.apk",
        },
        {
          "name": "luma-1.0.5-armeabi-v7a.apk",
          "browser_download_url": "https://example.com/armeabi.apk",
        },
      ]);

      expect(picked, isNull);
    });
  });
}

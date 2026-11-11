/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:luma/luma_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test("getApplications", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "getApplications") {
        return [
          {'packageName': 'app.luma.tvlauncher'}
        ];
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    final apps = await lumaChannel.getApplications();

    expect(apps, [
      {'packageName': 'app.luma.tvlauncher'}
    ]);
  });

  test("launchApp", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    String? packageName;
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "launchApp") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    await lumaChannel.launchApp("app.luma.tvlauncher");

    expect(packageName, "app.luma.tvlauncher");
  });

  test("openSettings", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    bool called = false;
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "openSettings") {
        called = true;
        return;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    await lumaChannel.openSettings();

    expect(called, isTrue);
  });

  test("openAppInfo", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    String? packageName;
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "openAppInfo") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    await lumaChannel.openAppInfo("app.luma.tvlauncher");

    expect(packageName, "app.luma.tvlauncher");
  });

  test("uninstallApp", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    String? packageName;
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "uninstallApp") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    await lumaChannel.uninstallApp("app.luma.tvlauncher");

    expect(packageName, "app.luma.tvlauncher");
  });

  test("isDefaultLauncher", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "isDefaultLauncher") {
        return true;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    final isDefaultLauncher = await lumaChannel.isDefaultLauncher();

    expect(isDefaultLauncher, isTrue);
  });

  test("checkForGetContentAvailability", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "checkForGetContentAvailability") {
        return true;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    final getContentAvailable = await lumaChannel.checkForGetContentAvailability();

    expect(getContentAvailable, isTrue);
  });

  test("startAmbientMode", () async {
    final channel = MethodChannel('app.luma.tvlauncher/method');
    bool called = false;
    channel.setMockMethodCallHandler((call) async {
      if (call.method == "startAmbientMode") {
        called = true;
        return;
      }
      fail("Unhandled method name");
    });
    final lumaChannel = LumaChannel();

    await lumaChannel.startAmbientMode();

    expect(called, isTrue);
  });
}

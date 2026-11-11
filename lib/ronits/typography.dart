import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerLumaFontLicense() {
  for (final name in [
    'Antonio',
    'Nunito',
    'Manrope',
    'Lora',
    'Figtree',
    'PlusJakartaSans',
    'Outfit',
    'DMSans',
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        [name],
        await rootBundle.loadString(
          'assets/fonts/${name.toUpperCase()}-OFL.txt',
        ),
      );
    });
  }
  // The GPL requires the notices of the projects Luma builds on to stay
  // reachable from the app.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Luma'], '''
Luma. Copyright (C) 2026 Ronit Sharma.

Luma includes code from FLauncher, Copyright (C) 2021 Étienne Fesser and contributors (Oscar Rojas and others), LTvLauncher, Copyright (C) 2024 LeanBitLab, and Arc Launcher by Badis Meddouri.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It comes with NO WARRANTY. See https://www.gnu.org/licenses/gpl-3.0.html''');
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Minimal Android TV Icons',
    ], await rootBundle.loadString('assets/tv-icons/LICENSE'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
  });
}

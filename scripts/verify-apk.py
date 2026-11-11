"""Check profile APK entry points and ARM runtime payloads before handover."""
from pathlib import Path
from zipfile import ZipFile
import sys

apk = Path(sys.argv[1])
with ZipFile(apk) as archive:
    dex = [archive.read(name) for name in archive.namelist()
           if name.startswith('classes') and name.endswith('.dex')]
    for name in ('MainActivity', 'ClockScreensaverService'):
        descriptor = f'Lapp/luma/tvlauncher/{name};'.encode()
        if not any(descriptor in data for data in dex):
            raise SystemExit(f'Invalid APK: missing native entry point {name}')
    for abi in ('armeabi-v7a', 'arm64-v8a'):
        for library in ('libflutter.so', 'libapp.so'):
            if f'lib/{abi}/{library}' not in archive.namelist():
                raise SystemExit(f'Invalid APK: missing {abi}/{library}')
print('APK entry points and both ARM Flutter runtimes verified.')

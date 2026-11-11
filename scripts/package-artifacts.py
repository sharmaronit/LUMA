"""Refresh local APKs, source archive, checksums, and optional validation logs."""
from pathlib import Path
import hashlib
import os
import shutil
import tarfile

repo = Path(__file__).resolve().parents[1]
workspace = repo.parent
artifacts = workspace / 'artifacts'
artifacts.mkdir(exist_ok=True)
for variant in ('profile', 'debug'):
    shutil.copy2(repo / f'build/app/outputs/flutter-apk/app-github-{variant}.apk',
                 artifacts / f'Luma-{variant}.apk')

excluded = {'.git', 'build', '.dart_tool', '.gradle', '.idea', '.vscode',
            'node_modules', 'Pods', '__pycache__', '.aws', '.codex', '.agents'}
with tarfile.open(artifacts / 'Luma-source.tar.gz', 'w:gz') as archive:
    for folder in (repo, workspace / 'browser-preview'):
        if not folder.exists():
            continue
        for directory, dirs, files in os.walk(folder):
            dirs[:] = [name for name in dirs if name not in excluded]
            for name in sorted(files):
                item = Path(directory) / name
                if (item.is_symlink() or name in {'.DS_Store', 'local.properties'}
                        or name.startswith(('.env', '.flutter-plugins'))
                        or item.suffix in {'.jks', '.keystore'}):
                    continue
                archive.add(item, arcname=item.relative_to(workspace), recursive=False)
    for item in sorted(workspace.glob('*.md')):
        archive.add(item, arcname=item.name, recursive=False)

with (artifacts / 'SHA256SUMS').open('w') as output:
    for name in ('Luma-profile.apk', 'Luma-debug.apk', 'Luma-source.tar.gz'):
        digest = hashlib.sha256((artifacts / name).read_bytes()).hexdigest()
        output.write(f'{digest}  {name}\n')
validation = artifacts / 'validation'
validation.mkdir(exist_ok=True)
for log in Path('/private/tmp').glob('luma-clean-*.log'):
    shutil.copy2(log, validation / log.name)
print('Updated APKs, source archive, validation logs, and checksums.')

import argparse
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report-only', action='store_true')
    parser.add_argument('--source', action='append', default=[])
    options = parser.parse_args()
    version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE).group(1)
    package = root / 'dist/windows' / f'zhenguojian-{version}-windows-x64.zip'
    if not package.is_file():
        raise SystemExit('Windows package is missing')
    report = root / 'build/source-playback.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix='zgj-source-probe-') as temporary:
        directory = Path(temporary)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(directory)
        result = subprocess.run([str(directory / 'zhenguojian.exe'), '--source-smoke', str(report), *options.source],
                                cwd=directory, timeout=1000, check=False)
    evidence = json.loads(report.read_text(encoding='utf-8')) if report.exists() else {'ok': False, 'error': 'No report'}
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
    if not options.report_only and (result.returncode != 0 or evidence.get('ok') is not True):
        raise SystemExit('Live source playback verification failed')


if __name__ == '__main__':
    main()

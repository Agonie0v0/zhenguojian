import argparse
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report-only', action='store_true')
    options = parser.parse_args()
    packages = sorted((root / 'dist/windows').glob('zhenguojian-*-windows-x64.zip'))
    if not packages:
        raise SystemExit('Windows package is missing')
    report = root / 'build/source-playback.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zgj-source-probe-') as temporary:
        directory = Path(temporary)
        with zipfile.ZipFile(packages[-1]) as archive:
            archive.extractall(directory)
        result = subprocess.run([str(directory / 'zhenguojian.exe'), '--source-smoke', str(report)],
                                cwd=directory, timeout=1000, check=False)
    evidence = json.loads(report.read_text(encoding='utf-8')) if report.exists() else {'ok': False, 'error': 'No report'}
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
    if not options.report_only and (result.returncode != 0 or evidence.get('ok') is not True):
        raise SystemExit('Live source playback verification failed')


if __name__ == '__main__':
    main()

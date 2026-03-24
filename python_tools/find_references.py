#!/usr/bin/env python3
import json
import sys
from pathlib import Path

TEXT_SUFFIXES = {'.py', '.sh', '.bash', '.zsh', '.js', '.jsx', '.ts', '.tsx', '.md', '.json', '.toml', '.yml', '.yaml'}


def load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({'error': f'invalid input: {exc}'}))
        raise SystemExit(1)


def find_repo_root(start: Path) -> Path:
    current = start if start.is_dir() else start.parent
    for candidate in [current, *current.parents]:
        if (candidate / '.git').exists():
            return candidate
        if (candidate / 'bashclaw').exists() and (candidate / 'lib').is_dir():
            return candidate
    return current


def iter_files(target: Path):
    if target.is_file():
        target = find_repo_root(target)
    for path in sorted(target.rglob('*')):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES or path.name == 'bashclaw':
            yield path


def main() -> int:
    payload = load_payload()
    symbol = str(payload.get('symbol') or '')
    if not symbol:
        print(json.dumps({'error': 'symbol parameter is required'}))
        return 1

    path_value = payload.get('path') or '.'
    target = Path(path_value).expanduser().resolve()
    if not target.exists():
        print(json.dumps({'error': 'path not found', 'path': str(target)}))
        return 1

    max_matches = int(payload.get('maxMatches') or 50)
    max_matches = max(1, min(max_matches, 200))
    matches = []

    for file_path in iter_files(target):
        try:
            text = file_path.read_text(encoding='utf-8', errors='replace')
        except Exception:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            if symbol not in line:
                continue
            matches.append({'path': str(file_path), 'line': lineno, 'text': line.strip()[:200]})
            if len(matches) >= max_matches:
                print(json.dumps({'symbol': symbol, 'matches': matches, 'count': len(matches)}, ensure_ascii=True))
                return 0

    print(json.dumps({'symbol': symbol, 'matches': matches, 'count': len(matches)}, ensure_ascii=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

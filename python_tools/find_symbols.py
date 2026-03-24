#!/usr/bin/env python3
import ast
import json
import re
import sys
from pathlib import Path

TEXT_SUFFIXES = {'.py', '.sh', '.bash', '.zsh', '.js', '.jsx', '.ts', '.tsx'}


def load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({'error': f'invalid input: {exc}'}))
        raise SystemExit(1)


def detect_language(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == '.py':
        return 'python'
    if suffix in {'.sh', '.bash', '.zsh'}:
        return 'bash'
    if suffix in {'.js', '.jsx'}:
        return 'javascript'
    if suffix in {'.ts', '.tsx'}:
        return 'typescript'
    return 'unknown'


def parse_python(path: Path, text: str) -> list[dict]:
    tree = ast.parse(text)
    symbols = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            symbols.append({'name': node.name, 'type': 'function', 'line': node.lineno, 'path': str(path)})
        elif isinstance(node, ast.ClassDef):
            symbols.append({'name': node.name, 'type': 'class', 'line': node.lineno, 'path': str(path)})
    return symbols


def parse_bash(path: Path, text: str) -> list[dict]:
    symbols = []
    pattern = re.compile(r'^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', re.MULTILINE)
    for match in pattern.finditer(text):
        line = text[:match.start()].count('\n') + 1
        symbols.append({'name': match.group(1), 'type': 'function', 'line': line, 'path': str(path)})
    return symbols


def parse_js_like(path: Path, text: str) -> list[dict]:
    symbols = []
    patterns = [
        (re.compile(r'^(?:export\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)', re.MULTILINE), 'function'),
        (re.compile(r'^(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)', re.MULTILINE), 'class'),
        (re.compile(r'^(?:export\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?\(', re.MULTILINE), 'const'),
    ]
    for pattern, symbol_type in patterns:
        for match in pattern.finditer(text):
            line = text[:match.start()].count('\n') + 1
            symbols.append({'name': match.group(1), 'type': symbol_type, 'line': line, 'path': str(path)})
    return symbols


def extract_symbols(path: Path) -> list[dict]:
    text = path.read_text(encoding='utf-8', errors='replace')
    language = detect_language(path)
    if language == 'python':
        return parse_python(path, text)
    if language == 'bash':
        return parse_bash(path, text)
    if language in {'javascript', 'typescript'}:
        return parse_js_like(path, text)
    return []


def iter_files(target: Path):
    if target.is_file():
        yield target
        return
    for path in sorted(target.rglob('*')):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
            yield path


def main() -> int:
    payload = load_payload()
    path_value = payload.get('path')
    if not path_value:
        print(json.dumps({'error': 'path parameter is required'}))
        return 1

    target = Path(path_value).expanduser().resolve()
    if not target.exists():
        print(json.dumps({'error': 'path not found', 'path': str(target)}))
        return 1

    query = str(payload.get('query') or '').lower()
    max_items = int(payload.get('maxItems') or 50)
    max_items = max(1, min(max_items, 200))

    results = []
    for file_path in iter_files(target):
        try:
            symbols = extract_symbols(file_path)
        except SyntaxError:
            continue
        for symbol in symbols:
            if query and query not in symbol['name'].lower():
                continue
            results.append(symbol)
            if len(results) >= max_items:
                print(json.dumps({'path': str(target), 'symbols': results, 'count': len(results)}, ensure_ascii=True))
                return 0

    print(json.dumps({'path': str(target), 'symbols': results, 'count': len(results)}, ensure_ascii=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

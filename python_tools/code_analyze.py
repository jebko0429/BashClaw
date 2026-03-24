#!/usr/bin/env python3
import ast
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

TEXT_EXTENSIONS = {
    ".py": "python",
    ".pyi": "python",
    ".js": "javascript",
    ".jsx": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".sh": "bash",
    ".bash": "bash",
    ".zsh": "bash",
    ".md": "markdown",
    ".json": "json",
    ".yml": "yaml",
    ".yaml": "yaml",
    ".toml": "toml",
    ".go": "go",
    ".rs": "rust",
    ".java": "java",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
}

KEY_FILES = {
    "pyproject.toml",
    "requirements.txt",
    "package.json",
    "tsconfig.json",
    "Cargo.toml",
    "go.mod",
    "Makefile",
    "README.md",
    "bashclaw",
}


def detect_language(path: Path, explicit: str = "") -> str:
    if explicit:
        return explicit.lower()
    if path.is_dir():
        return "directory"
    if path.suffix.lower() in TEXT_EXTENSIONS:
        return TEXT_EXTENSIONS[path.suffix.lower()]
    if path.name == "Dockerfile":
        return "dockerfile"
    return "unknown"


def count_lines(text: str) -> int:
    if not text:
        return 0
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def analyze_python_file(path: Path, text: str, max_items: int) -> dict:
    tree = ast.parse(text)
    imports = []
    functions = []
    classes = []
    has_main_guard = False

    for node in tree.body:
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom):
            mod = node.module or ""
            imports.append(mod)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.append(
                {
                    "name": node.name,
                    "line": node.lineno,
                    "async": isinstance(node, ast.AsyncFunctionDef),
                }
            )
        elif isinstance(node, ast.ClassDef):
            methods = []
            for child in node.body:
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    methods.append(child.name)
            classes.append(
                {
                    "name": node.name,
                    "line": node.lineno,
                    "methods": methods[:max_items],
                }
            )
        elif isinstance(node, ast.If):
            test = ast.unparse(node.test) if hasattr(ast, "unparse") else ""
            if "__name__" in test and "__main__" in test:
                has_main_guard = True

    docstring = ast.get_docstring(tree)
    return {
        "docstring": docstring or "",
        "imports": sorted({item for item in imports if item})[:max_items],
        "functions": functions[:max_items],
        "classes": classes[:max_items],
        "has_main_guard": has_main_guard,
    }


def analyze_text_file(path: Path, text: str, language: str, max_items: int) -> dict:
    lines = text.splitlines()
    todos = []
    for idx, line in enumerate(lines, start=1):
        if "TODO" in line or "FIXME" in line:
            todos.append({"line": idx, "text": line.strip()[:160]})
            if len(todos) >= max_items:
                break

    imports = []
    if language in {"javascript", "typescript"}:
        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("import ") or stripped.startswith("export "):
                imports.append({"line": idx, "text": stripped[:160]})
                if len(imports) >= max_items:
                    break

    shebang = lines[0].strip() if lines and lines[0].startswith("#!") else ""
    return {
        "shebang": shebang,
        "todos": todos,
        "imports": imports,
    }


def analyze_file(path: Path, explicit_language: str, max_items: int) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    language = detect_language(path, explicit_language)
    result = {
        "path": str(path),
        "kind": "file",
        "language": language,
        "size_bytes": path.stat().st_size,
        "line_count": count_lines(text),
    }

    if language == "python":
        result["analysis"] = analyze_python_file(path, text, max_items)
    else:
        result["analysis"] = analyze_text_file(path, text, language, max_items)

    return result


def analyze_directory(path: Path, max_items: int) -> dict:
    language_counts = Counter()
    key_files = []
    sample_files = []
    total_files = 0

    for child in sorted(path.rglob("*")):
        if child.is_dir():
            continue
        total_files += 1
        language = detect_language(child)
        language_counts[language] += 1
        rel = str(child.relative_to(path))
        if child.name in KEY_FILES and len(key_files) < max_items:
            key_files.append(rel)
        if len(sample_files) < max_items:
            sample_files.append({"path": rel, "language": language})

    return {
        "path": str(path),
        "kind": "directory",
        "language": "directory",
        "file_count": total_files,
        "languages": dict(language_counts.most_common(max_items)),
        "key_files": key_files,
        "sample_files": sample_files,
    }


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({"error": f"invalid input: {exc}"}))
        return 1

    path_value = payload.get("path")
    if not path_value:
        print(json.dumps({"error": "path parameter is required"}))
        return 1

    path = Path(path_value).expanduser().resolve()
    if not path.exists():
        print(json.dumps({"error": "path not found", "path": str(path)}))
        return 1

    max_items = int(payload.get("maxItems") or 25)
    max_items = max(1, min(max_items, 100))
    explicit_language = str(payload.get("language") or "")

    try:
        if path.is_dir():
            result = analyze_directory(path, max_items)
        else:
            result = analyze_file(path, explicit_language, max_items)
    except SyntaxError as exc:
        result = {
            "path": str(path),
            "kind": "file",
            "language": detect_language(path, explicit_language),
            "error": "syntax_error",
            "message": str(exc),
            "line": getattr(exc, "lineno", None),
        }
    except Exception as exc:
        print(json.dumps({"error": str(exc), "path": str(path)}))
        return 1

    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

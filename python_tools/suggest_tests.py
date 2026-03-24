#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

TEST_FILE_PATTERNS = [
    "tests/test_{stem}.sh",
    "tests/test_{stem}.py",
    "tests/{stem}_test.py",
    "tests/{stem}.test.js",
    "tests/{stem}.spec.js",
    "tests/{stem}.test.ts",
    "tests/{stem}.spec.ts",
    "test_{stem}.py",
    "{stem}_test.py",
]


def load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({"error": f"invalid input: {exc}"}))
        raise SystemExit(1)


def normalize_paths(payload: dict) -> list[str]:
    values = []
    if payload.get("path"):
        values.append(payload["path"])
    if isinstance(payload.get("paths"), list):
        values.extend([item for item in payload["paths"] if item])
    return values


def find_repo_root(start: Path) -> Path:
    current = start if start.is_dir() else start.parent
    for candidate in [current, *current.parents]:
        if (candidate / ".git").exists():
            return candidate
        if (candidate / "bashclaw").exists() and (candidate / "lib").is_dir():
            return candidate
    return current


def stem_for_source(path: Path) -> str:
    name = path.stem
    if name == "__init__":
        name = path.parent.name
    return name.replace("-", "_")


def candidate_paths(repo_root: Path, source: Path) -> list[tuple[Path, str, int]]:
    rel = source.relative_to(repo_root) if source.is_absolute() and repo_root in source.parents else source
    stem = stem_for_source(source)
    candidates = []

    if source.name == "bashclaw":
        candidates.append((repo_root / "tests/test_cli.sh", "cli entrypoint heuristic", 95))

    if rel.parts[:1] == ("lib",):
        candidates.append((repo_root / f"tests/test_{stem}.sh", "lib shell module heuristic", 95))
    elif rel.parts[:1] == ("python_tools",):
        candidates.append((repo_root / "tests/test_tools.sh", "python helper tool heuristic", 75))
    elif rel.parts[:1] == ("channels",):
        candidates.append((repo_root / "tests/test_channels.sh", "channel integration heuristic", 90))

    for pattern in TEST_FILE_PATTERNS:
        candidates.append((repo_root / pattern.format(stem=stem), "name-based heuristic", 70))

    if source.parent != repo_root:
        candidates.append((source.parent / f"test_{stem}{source.suffix}", "same-directory heuristic", 60))
        candidates.append((source.parent / f"{stem}_test{source.suffix}", "same-directory heuristic", 60))

    deduped = []
    seen = set()
    for path_obj, reason, confidence in candidates:
        key = str(path_obj)
        if key in seen:
            continue
        seen.add(key)
        deduped.append((path_obj, reason, confidence))
    return deduped


def analyze_source(raw_path: str) -> dict:
    source = Path(raw_path).expanduser().resolve()
    repo_root = find_repo_root(source)
    suggestions = []

    if not source.exists():
        return {
            "source": str(source),
            "error": "path not found",
            "candidates": [],
        }

    if source.name.startswith("test_") or source.name.endswith("_test.py") or "/tests/" in f"/{source.as_posix()}/":
        return {
            "source": str(source),
            "repo_root": str(repo_root),
            "recommended": str(source),
            "candidates": [
                {
                    "path": str(source),
                    "exists": True,
                    "confidence": 100,
                    "reason": "source is already a test file",
                }
            ],
        }

    for candidate, reason, confidence in candidate_paths(repo_root, source):
        suggestions.append(
            {
                "path": str(candidate),
                "exists": candidate.exists(),
                "confidence": confidence,
                "reason": reason,
            }
        )

    suggestions.sort(key=lambda item: (not item["exists"], -item["confidence"], item["path"]))
    recommended = next((item["path"] for item in suggestions if item["exists"]), suggestions[0]["path"] if suggestions else "")

    return {
        "source": str(source),
        "repo_root": str(repo_root),
        "recommended": recommended,
        "candidates": suggestions[:10],
    }


def main() -> int:
    payload = load_payload()
    raw_paths = normalize_paths(payload)
    if not raw_paths:
        print(json.dumps({"error": "path or paths parameter is required"}))
        return 1

    results = [analyze_source(raw_path) for raw_path in raw_paths]
    print(json.dumps({"results": results}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

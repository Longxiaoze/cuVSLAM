# AGENTS.md — cuVSLAM

AI agent guidance for working in this repository. See `README.md` for general project documentation and `DEVELOPMENT.md` for developer setup.

## Project Overview

cuVSLAM is a CUDA-accelerated Visual Odometry and SLAM library by NVIDIA. It exposes a C++ API (`libs/cuvslam/cuvslam2.h`) and a Python wrapper (`python/`) via nanobind bindings. Current version: see `VERSION`.

Tracking modes: Stereo, Mono, Mono-Depth (RGB-D), Stereo-Inertial, Multi-camera, Multisensor (any-mix RGB / RGB-D, optional IMU; requires cuNLS-enabled build). SLAM capabilities: loop closure, localization against saved maps.

## Repository Layout

```text
libs/            # 24 modular C++ libraries (camera, slam, odometry, cuda_modules, …)
python/          # PyCuVSLAM: nanobind bindings + high-level Tracker wrapper
examples/        # Runnable Python examples per dataset/camera (kitti, euroc, tum, realsense, zed, …)
tools/           # C++ analysis and visualization tools (tracker, reporter, visualizer)
test_data/       # Small reference datasets (edex, sof, navsim)
cmake/ext/       # FetchContent dependency configs (Eigen, GTest, spdlog, yaml-cpp, …)
docker/          # Dockerfile for containerized builds
cuvslam-skills/  # Claude Code skills (cuvslam-onboard, cuvslam-troubleshoot)
```

Key files:
- `libs/cuvslam/cuvslam2.h` — primary C++ public API (the only public header)
- `python/tracker.py` — high-level Python `Tracker` class
- `python/cuvslam2.cpp` — nanobind Python bindings (must stay in sync with `cuvslam2.h`)
- `CMakeLists.txt` — root CMake build definition
- `build_release.sh` — convenience script for build + tests
- `pyproject.toml` — Python package metadata (scikit-build-core + nanobind)
- `.clang-format` — C++ formatting rules (Google style, 120-char limit)
- `.pre-commit-config.yaml` — hooks for formatting, copyright headers, style

## Build

### C++ (CMake)

```bash
# Build everything (from repo root)
cmake -S . -B build && cmake --build build --parallel $(nproc)

# Or use the convenience script (set env vars or edit SRC/DST in the script)
export CUVSLAM_SRC_DIR=<path-to-src>
export CUVSLAM_DST_DIR=<path-to-build>
./build_release.sh
```

Notable CMake options (all have defaults; override with `-DFLAG=VALUE`):

| Flag | Default | Purpose |
|------|---------|---------|
| `USE_CUDA` | ON | CUDA acceleration |
| `USE_LMDB` | ON | LMDB map database |
| `USE_RERUN` | OFF | Rerun SDK visualization |
| `USE_NVTX` | OFF | NVIDIA NVTX profiling |
| `TREAT_WARNINGS_AS_ERRORS` | OFF | Strict warning policy |

Build types: `Release` (default), `Debug`, `RelWithDebInfo`, `MinSizeRel`. Do not mix types in the same build directory.

### Python bindings (requires completed C++ build)

```bash
CUVSLAM_BUILD_DIR=<build-dir> pip install -e python/
```

## Testing

### C++ unit tests (GTest + ctest)

```bash
cd <build-dir>
GTEST_FILTER=-*SpeedUp* ctest --output-on-failure
```

Test sources live in `libs/*/test/` directories. Each library has its own test CMakeLists.

### Python API tests

```bash
python3 -m unittest discover -v -s ./python/test --locals
```

Key test files: `python/test/test_api.py`, `test_bindings.py`, `test_tracking.py`, `test_map.py`, `test_image_format.py`.

### All-in-one (build + both test suites)

```bash
./build_release.sh --modules_test --api_test
```

## Code Style

**C++**: Google C++ Style with two project-specific exceptions:
1. Line limit is **120 characters** (not 80)
2. No indentation before `public` / `private` / `protected`

```bash
# Format a single file (fast, safe to run)
clang-format -i path/to/file.cpp

# Format all C++ files recursively
find . -iname '*.h' -o -iname '*.cpp' | xargs clang-format -i
```

**Pre-commit hooks** run on every `git commit` and automatically handle formatting, copyright headers, and basic hygiene. Install once per clone:

```bash
pipx install pre-commit   # or: pip install pre-commit
pre-commit install
```

On Ubuntu 22.04, if pre-commit fails on install, add `export SETUPTOOLS_USE_DISTUTILS=stdlib` to `~/.bashrc`.

## Design Concepts

Before making code changes or designing new features, read **[DESIGN_CONCEPTS.md](DESIGN_CONCEPTS.md)**. It documents the architectural decisions that govern how cuVSLAM is structured.

## Dos and Don'ts

**Do:**
- Before making changes in any folder, read the `README.md` in that folder if one exists — these are written for humans and contain context that is not derivable from the code alone
- Keep each library in `libs/` self-contained with its own `CMakeLists.txt` and `test/` subdirectory
- Use `spdlog` (via `libs/log/`) for all logging — no `printf` or `std::cout` in library code
- Use `Eigen` for linear algebra; it is already a FetchContent dependency
- Use the `Pose` type from `cuvslam2.h` for all SE(3) transforms (quaternion + translation)
- Add new external dependencies as FetchContent entries in `cmake/ext/`
- Write a corresponding `libs/*/test/` when adding new public API functions
- When generating C++ code, always include `{}` braces for `if` statements, even for single-line bodies. This prevents accidental behavior changes when new statements are added later and keeps control flow explicit and consistent.

**Don't:**
- Don't edit `libs/cuvslam/cuvslam2.h` without updating `python/cuvslam2.cpp` — they must stay in sync
- Don't put implementation details in `cuvslam2.h`; it is the public C++ API boundary
- Don't use non-ABI-stable types (`std::string`, `std::map`, etc.) in `cuvslam2.h`; `std::vector` is the explicit exception. Otherwise, use `std::string_view`, raw pointers with a count, or plain structs of primitive types only
- Don't mix different `CMAKE_BUILD_TYPE` values in the same `CUVSLAM_DST_DIR`
- Don't commit directly to `master` — the pre-commit hook blocks it
- Don't skip pre-commit with `--no-verify` except to unblock a known false positive

## Merge Request (MR) Policies

**Title prefixes** — each MR title should start with exactly one of:

- `[fix]` — bug fixes
- `[clean]` — code cleanup, added comments, renames for clarity
- `[refactor]` — interface or structural changes that set up a later feature
- `[feat]` — new functionality
- `[test]` — test-only changes, new or updated tests
- `[infra]` — infrastructure not tied to product source code (for example `AGENTS.md`, repo configs, `.gitignore`)

**Unit tests:** `[fix]` and `[feat]` MRs must include unit tests (C++ in `libs/*/test/` and/or Python under `python/test/` as appropriate).

**Scope:** Do not mix several unrelated changes in one MR. Keep each MR as small as is reasonable; every change in the MR should clearly relate to its stated topic.

## Key Patterns and Examples

Refer to these files when implementing new features or tests:

| What | Where |
|------|-------|
| Stereo VO example | `examples/kitti/track_kitti.py` |
| Stereo-inertial (IMU) example | `examples/euroc/track_euroc.py` |
| Monocular-depth example | `examples/tum/track_tum.py` |
| Multi-camera example | `examples/realsense/` |
| High-level Python Tracker | `python/tracker.py` |
| nanobind binding pattern | `python/cuvslam2.cpp` (see `nb::class_<>` usage) |
| GTest unit test pattern | `libs/common/test/common_test.cpp` |
| CMake library definition | any `libs/*/CMakeLists.txt` |

## Agent Permissions

### Git Branch Naming

When creating a git branch, use `<user-name>/<branch-name>`, with `<branch-name>` in lowercase kebab-case.

**Safe to run without asking:**
- Reading source files, headers, CMake files, or config files
- Running `clang-format -i` on individual files
- Running `ctest` or `python3 -m unittest` against existing test data in `test_data/`
- Running `cmake -S . -B build` (configure only, no compilation)
- Running `pre-commit run --files <file>` on specific files

**Ask the user before running:**
- `cmake --build ... --parallel` full builds (can take 10+ minutes, high CPU/GPU load)
- `pip install` or `pip install -e` (modifies the Python environment)
- Any `git commit`, `git push`, or branch operations
- Deleting or overwriting build artifacts or test data
- Changing versions of FetchContent dependencies in `cmake/ext/`

## Claude Code Skills

Two project-specific skills in `cuvslam-skills/` provide deep cuVSLAM knowledge:

- `/cuvslam-onboard` — build from source, install wheels, run examples, prepare KITTI/EuRoC/TUM datasets, live camera setup (RealSense, ZED, OAK-D, Orbbec)
- `/cuvslam-troubleshoot` — diagnose tracking failures, pose drift, calibration issues, IMU integration problems, build errors, Isaac ROS integration

Install into Claude Code:
```bash
cp -r cuvslam-skills/cuvslam-onboard ~/.claude/skills/
cp -r cuvslam-skills/cuvslam-troubleshoot ~/.claude/skills/
```

## AGENTS.md Convention

> **Note: the rules in this section are for Claude Code only and are ignored by Codex.**

### Codex-only constructs Claude Code does not support

| Pattern | Why it's Codex-only |
|---|---|
| `<SYSTEM>…</SYSTEM>` blocks | Codex injects this as a system prompt; Claude reads it as plain text |
| `<CONTEXT>…</CONTEXT>` blocks | Same — Codex-specific XML framing |
| `approval_policy:` key | Codex sandbox approval setting; no equivalent in Claude Code |
| `sandboxed: true/false` | Codex sandbox flag; ignored by Claude Code |
| `tools:` YAML list at top level | Codex tool-allowlist format; Claude Code uses `settings.json` instead |
| References to `codex run` / `codex search` CLI | Codex CLI commands; not available in Claude Code |
| OpenAI model names (`gpt-4o`, `o1`, `o3`, `o4-mini`, …) | Model pinning for Codex; use Claude model names here instead |
| `CODEX_*` environment variables | Codex runtime variables; not set by Claude Code |
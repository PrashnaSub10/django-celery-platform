"""
path_utils.py — Cross-platform path helpers.

Provides safe, traversal-resistant path resolution for log, data, and
temporary directories.  All public functions are pure (no side effects);
directory creation is explicit via ``ensure_dir``.

Requires Python 3.13+.

Example::

    from config.path_utils import get_log_path, ensure_dir

    log_dir = get_log_path("celery")
    ensure_dir(log_dir)
"""

import logging
import os
from pathlib import Path

__all__ = [
    "get_log_path",
    "get_data_path",
    "get_temp_path",
    "get_project_root",
    "get_relative_path",
    "ensure_dir",
]

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Base directories — resolved once, never mutated
# ---------------------------------------------------------------------------

if os.name == "nt":  # Windows
    _BASE_LOG: Path = Path(os.environ.get("APP_LOG_DIR", "C:/Logs"))
    _BASE_DATA: Path = Path(os.environ.get("APP_DATA_DIR", "C:/Data"))
    _BASE_TEMP: Path = Path(os.environ.get("APP_TEMP_DIR", "C:/Temp"))
else:  # Linux / Unix
    _BASE_LOG: Path = Path(os.environ.get("APP_LOG_DIR", "/var/log/app"))
    _BASE_DATA: Path = Path(os.environ.get("APP_DATA_DIR", "/var/data/app"))
    _BASE_TEMP: Path = Path(os.environ.get("APP_TEMP_DIR", "/tmp/app"))


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _safe_join(base: Path, subpath: str) -> Path:
    """Join *base* with *subpath* and reject traversal outside *base*.

    Defends against CWE-22 at two layers:

    1. **Pre-join sanitisation** — rejects absolute subpaths before the
       join.  ``Path.__truediv__`` silently discards the left operand when
       the right operand is absolute (e.g. ``Path("/var/log") / "/etc/passwd"``
       yields ``Path("/etc/passwd")``), so the absolute check must happen
       *before* the join, not after.

    2. **Post-join containment check** — resolves both paths lexically
       (``strict=False`` so the directory need not exist yet) and confirms
       the result is still inside *base*.

    Args:
        base: Absolute base directory (need not exist yet).
        subpath: Relative sub-path to append.  Must not be absolute.

    Returns:
        Absolute ``Path`` guaranteed to be inside *base*.

    Raises:
        ValueError: If *subpath* is absolute or the resolved path escapes *base*.
    """
    subpath_obj = Path(subpath)

    if subpath_obj.is_absolute():
        raise ValueError(
            f"Absolute subpath rejected: '{subpath}'. "
            "Only relative sub-paths are permitted."
        )

    resolved_base = base.resolve(strict=False)
    resolved = (resolved_base / subpath_obj).resolve(strict=False)

    if not resolved.is_relative_to(resolved_base):
        raise ValueError(
            f"Path traversal detected: '{resolved}' escapes base '{resolved_base}'."
        )
    return resolved


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_log_path(log_type: str = "general") -> Path:
    """Return the platform log directory for *log_type*.

    Args:
        log_type: Sub-directory name (e.g. ``"celery"``, ``"django"``).

    Returns:
        Absolute ``Path`` inside the platform log base directory.

    Raises:
        ValueError: On path traversal attempt.
    """
    return _safe_join(_BASE_LOG, log_type)


def get_data_path(data_type: str = "general") -> Path:
    """Return the platform data directory for *data_type*.

    Args:
        data_type: Sub-directory name (e.g. ``"uploads"``, ``"reports"``).

    Returns:
        Absolute ``Path`` inside the platform data base directory.

    Raises:
        ValueError: On path traversal attempt.
    """
    return _safe_join(_BASE_DATA, data_type)


def get_temp_path(temp_type: str = "general") -> Path:
    """Return the platform temp directory for *temp_type*.

    Args:
        temp_type: Sub-directory name (e.g. ``"cache"``, ``"processing"``).

    Returns:
        Absolute ``Path`` inside the platform temp base directory.

    Raises:
        ValueError: On path traversal attempt.
    """
    return _safe_join(_BASE_TEMP, temp_type)


def get_project_root() -> Path:
    """Return the absolute path of the directory containing this file.

    Returns:
        Resolved ``Path`` of the project root.
    """
    return Path(__file__).resolve().parent


def get_relative_path(*parts: str) -> Path:
    """Return a path relative to the project root, rejecting traversal.

    Args:
        *parts: Path components joined relative to the project root.

    Returns:
        Absolute ``Path`` guaranteed to be inside the project root.

    Raises:
        ValueError: If the resolved path escapes the project root.
    """
    root = get_project_root()
    resolved = root.joinpath(*parts).resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(
            f"Path traversal detected: '{resolved}' escapes project root '{root}'."
        )
    return resolved


def ensure_dir(path: Path | str) -> Path:
    """Create *path* and all parents if they do not exist.

    Args:
        path: Directory to create.

    Returns:
        The ``Path`` that was created (or already existed).
    """
    resolved = Path(path)
    resolved.mkdir(parents=True, exist_ok=True)
    logger.debug("Directory ensured: %s", resolved)
    return resolved

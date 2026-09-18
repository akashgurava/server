"""Utility functions for the media manager package."""

import logging
import os
import re
import unicodedata
from pathlib import Path
from typing import List, Optional, Tuple, TypeVar

from media_manager.errors import (
    FileParsingError,
    FolderValidationError,
    NullValueError,
    ValidationError,
)

T = TypeVar("T")

# Create logger for this module
LOGGER = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = [".flac", ".mp3", ".m4a", ".wav", ".aac", ".ogg", ".wma"]


def normalize_name(name: str) -> str:
    """Normalize a name by converting to lowercase, removing special characters, and standardizing whitespace.
    
    This function handles the common case where quotes in track names are replaced with underscores
    in file names, ensuring proper matching between Tidal API data and local files.

    Args:
        name: The name to normalize

    Returns:
        return normalized
    """
    name = name.lower()
    name = unicodedata.normalize("NFKD", name).encode("ASCII", "ignore").decode("utf-8")
    
    # Replace quotes with underscores first to match file naming conventions
    # This handles cases like 'Tum Tum (From "Enemy - Tamil")' -> 'Tum Tum (From _Enemy - Tamil_)'
    name = name.replace('"', '_').replace("'", '_')
    
    name = re.sub(
        r"[^\w\s\-\(\)]", "", name
    )  # Keep alphanum, whitespace, dash, parentheses
    name = name.replace("_", " ")  # Replace underscores with spaces
    name = re.sub(r"\s+", " ", name)  # Collapse multiple spaces
    return name.strip()


def extract_artist_and_track(filepath: Path) -> Tuple[str, str]:
    """Extract artist and track name from a file path.

    Expected format: "Artist - Track.ext" or "001. Artist - Track.ext"

    Args:
        filepath: Path to the audio file

    Returns:
        Tuple of (artist, track) names, both normalized.

    Raises:
        FileParsingError: If the filename doesn't match the expected format.
    """
    # Remove leading number prefixes like "001. " or "01 - "
    name = filepath.name
    name = re.sub(r"^\d+\s*[\.\-]\s*", "", name)
    name = os.path.splitext(name)[0]
    parts = name.split(" - ", 1)
    if len(parts) != 2:
        raise FileParsingError(filepath, "Expected format: 'Artist - Track'")
    artist = normalize_name(parts[0])
    track = normalize_name(parts[1])
    if not artist or not track:
        raise FileParsingError(
            filepath, "Empty artist or track name after normalization"
        )
    return artist, track


def check_null(field: str, value: Optional[T]) -> T:
    if value is None:
        raise NullValueError(field, value)
    return value


def validate_input_folders(input_folders: List[Path]) -> None:
    """Validate that input folders exist, are directories, and are readable.

    Args:
        input_folders: List of Path objects to validate

    Raises:
        FolderValidationError: If any folders fail validation
    """
    missing_folders = []
    permission_errors = []
    not_directories = []

    for folder_path in input_folders:
        # Check if path exists
        if not folder_path.exists():
            missing_folders.append(str(folder_path))
            continue

        # Check if it's a directory
        if not folder_path.is_dir():
            not_directories.append(str(folder_path))
            continue

        # Check read permissions (Unix-style)
        try:
            # Try to list directory contents to test read permission
            list(folder_path.iterdir())
        except PermissionError:
            permission_errors.append(str(folder_path))
        except OSError as e:
            # Handle other OS-level errors (like network issues, etc.)
            permission_errors.append(f"{folder_path} (OS Error: {e})")

    # Raise error if any validation issues found
    if missing_folders or permission_errors or not_directories:
        raise FolderValidationError(
            missing_folders=missing_folders,
            permission_errors=permission_errors,
            not_directories=not_directories,
        )
    LOGGER.debug(f"Input folders validated: {input_folders}")


def collect_audio_files(folders: List[Path]) -> List[Path]:
    """Collect all audio files from the given folders in order.

    Args:
        folders: List of folder paths to search for audio files

    Returns:
        List of audio file paths sorted by folder order and filename

    Raises:
        ValidationError: If no valid folders are provided or no audio files found.
    """
    if not folders:
        raise ValidationError(
            "input_folders", "empty list", "No input folders provided"
        )

    files: List[Path] = []
    valid_folders = 0

    for folder in folders:
        valid_folders += 1
        # Collect all files with allowed extensions
        folder_files = [
            f
            for f in sorted(folder.iterdir())
            if f.suffix.lower() in SUPPORTED_EXTENSIONS and f.is_file()
        ]
        files.extend(folder_files)

    if valid_folders == 0:
        raise ValidationError("input_folders", str(folders), "No valid folders found")

    if not files:
        raise ValidationError(
            "audio_files",
            f"{valid_folders} folder(s)",
            f"No audio files found. Supported extensions: {', '.join(SUPPORTED_EXTENSIONS)}",
        )

    return files


def sanitize_filename(name: str) -> str:
    """Sanitize a string to be safe for filesystem use.

    Args:
        name: The string to sanitize

    Returns:
        Sanitized string safe for filesystem use
    """
    # Replace problematic characters with safe alternatives
    replacements = {
        ":": "-",
        "/": "-",
        "\\": "-",
        "<": "(",
        ">": ")",
        '"': "'",
        "|": "-",
        "?": "",
        "*": "",
        "\0": "",
    }

    sanitized = name
    for bad_char, replacement in replacements.items():
        sanitized = sanitized.replace(bad_char, replacement)

    # Remove leading/trailing dots and spaces
    sanitized = sanitized.strip(". ")

    # Collapse multiple spaces
    sanitized = re.sub(r"\s+", " ", sanitized)

    return sanitized

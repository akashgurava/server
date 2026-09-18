"""Media Manager Package

A modular media file management system with Tidal playlist integration.
"""

from media_manager.errors import (
    MediaManagerError,
    FileParsingError,
    TidalAPIError,
    FileOperationError,
    ValidationError,
    NullValueError,
    PlaylistVerificationError,
    FolderValidationError,
)
from media_manager.tidal_client import TidalClient
from media_manager.utils import validate_input_folders

__version__ = "1.0.0"
__all__ = [
    "MediaManagerError",
    "FileParsingError",
    "TidalAPIError",
    "FileOperationError",
    "ValidationError",
    "NullValueError",
    "PlaylistVerificationError",
    "FolderValidationError",
    "TidalClient",
    "validate_input_folders",
]

"""Custom exception classes for the media manager package."""

from typing import Any, List
from pathlib import Path


class MediaManagerError(Exception):
    """Base exception for media manager errors."""

    def __init__(self, message: str) -> None:
        """Initialize with error message."""
        super().__init__(message)
        self.message = message

    def __str__(self) -> str:
        """Return the error message."""
        return self.message


class FileParsingError(MediaManagerError):
    """Exception raised when file parsing fails."""

    def __init__(self, filepath: Path, reason: str) -> None:
        """Initialize with filepath and reason for parsing failure.

        Args:
            filepath: The file that failed to parse
            reason: The reason for parsing failure
        """
        self.filepath = filepath
        self.reason = reason
        message = f"Could not parse file '{filepath.name}': {reason}"
        super().__init__(message)

    def __str__(self) -> str:
        """Return formatted error message."""
        return f"Could not parse file '{self.filepath.name}': {self.reason}"


class TidalAPIError(MediaManagerError):
    """Exception raised when Tidal API operations fail."""

    def __init__(self, operation: str, details: str) -> None:
        """Initialize with operation and error details.

        Args:
            operation: The Tidal operation that failed
            details: Details about the failure
        """
        self.operation = operation
        self.details = details
        message = f"Tidal API error during {operation}: {details}"
        super().__init__(message)

    def __str__(self) -> str:
        """Return formatted error message."""
        return f"Tidal API error during {self.operation}: {self.details}"


class FileOperationError(MediaManagerError):
    """Exception raised when file operations fail."""

    def __init__(self, operation: str, filepath: Path, details: str) -> None:
        """Initialize with operation, filepath, and error details.

        Args:
            operation: The file operation that failed (e.g., 'copy', 'move', 'create')
            filepath: The file/path involved in the operation
            details: Details about the failure
        """
        self.operation = operation
        self.filepath = filepath
        self.details = details
        message = f"File operation '{operation}' failed for '{filepath}': {details}"
        super().__init__(message)

    def __str__(self) -> str:
        """Return formatted error message."""
        return f"File operation '{self.operation}' failed for '{self.filepath}': {self.details}"


class ValidationError(MediaManagerError):
    """Exception raised when validation fails."""

    def __init__(self, field: str, value: str, reason: str) -> None:
        """Initialize with field, value, and validation reason.

        Args:
            field: The field that failed validation
            value: The value that was invalid
            reason: The reason for validation failure
        """
        self.field = field
        self.value = value
        self.reason = reason
        message = f"Validation failed for {field} '{value}': {reason}"
        super().__init__(message)

    def __str__(self) -> str:
        """Return formatted error message."""
        return f"Validation failed for {self.field} '{self.value}': {self.reason}"


class NullValueError(MediaManagerError):
    """Exception raised when a required value is None/null."""

    def __init__(self, field: str, value: Any = None) -> None:
        """Initialize with field name that has null value.

        Args:
            field: The field name that is null/None
            value: The actual value (should be None)
        """
        self.field = field
        self.value = value
        message = f"Value is None for field '{field}'. Value: {value}"
        super().__init__(message)

    def __str__(self) -> str:
        """Return formatted error message."""
        return f"Value is None for field '{self.field}'. Value: {self.value}"


class PlaylistVerificationError(MediaManagerError):
    """Exception raised when playlist verification fails."""

    def __init__(
        self, 
        parsing_errors: List[str] = None,
        artist_mismatches: List[str] = None, 
        missing_from_playlist: List[str] = None
    ) -> None:
        """Initialize with verification failure details.

        Args:
            parsing_errors: List of file parsing error messages
            artist_mismatches: List of artist mismatch error messages
            missing_from_playlist: List of tracks missing from playlist
        """
        self.parsing_errors = parsing_errors or []
        self.artist_mismatches = artist_mismatches or []
        self.missing_from_playlist = missing_from_playlist or []
        
        # Build comprehensive error message
        error_parts = []
        if self.parsing_errors:
            error_parts.append(f"Parsing errors: {len(self.parsing_errors)} files failed to parse")
        if self.artist_mismatches:
            error_parts.append(f"Artist mismatches: {len(self.artist_mismatches)} tracks have incorrect artists")
        if self.missing_from_playlist:
            error_parts.append(f"Missing from playlist: {len(self.missing_from_playlist)} tracks not found in playlist")
            
        message = "Playlist verification failed - " + ", ".join(error_parts)
        super().__init__(message)
    
    def __str__(self) -> str:
        """Return formatted error message with details."""
        lines = ["Playlist verification failed:"]
        
        if self.parsing_errors:
            lines.append(f"\nParsing errors ({len(self.parsing_errors)}):")
            for error in self.parsing_errors:
                lines.append(f"  - {error}")
                
        if self.artist_mismatches:
            lines.append(f"\nArtist mismatches ({len(self.artist_mismatches)}):")
            for mismatch in self.artist_mismatches:
                lines.append(f"  - {mismatch}")
                
        if self.missing_from_playlist:
            lines.append(f"\nTracks missing from playlist ({len(self.missing_from_playlist)}):")
            for track in self.missing_from_playlist:
                lines.append(f"  - {track}")
                
        return "\n".join(lines)


class FolderValidationError(MediaManagerError):
    """Exception raised when input folder validation fails."""
    
    def __init__(
        self,
        missing_folders: List[str] = None,
        permission_errors: List[str] = None,
        not_directories: List[str] = None
    ) -> None:
        """Initialize with folder validation failure details.
        
        Args:
            missing_folders: List of folders that don't exist
            permission_errors: List of folders with permission issues
            not_directories: List of paths that exist but are not directories
        """
        self.missing_folders = missing_folders or []
        self.permission_errors = permission_errors or []
        self.not_directories = not_directories or []
        
        # Build comprehensive error message
        error_parts = []
        if self.missing_folders:
            error_parts.append(f"{len(self.missing_folders)} folders don't exist")
        if self.permission_errors:
            error_parts.append(f"{len(self.permission_errors)} folders have permission issues")
        if self.not_directories:
            error_parts.append(f"{len(self.not_directories)} paths are not directories")
            
        message = "Folder validation failed - " + ", ".join(error_parts)
        super().__init__(message)
    
    def __str__(self) -> str:
        """Return formatted error message with details."""
        lines = ["Folder validation failed:"]
        
        if self.missing_folders:
            lines.append(f"\nMissing folders ({len(self.missing_folders)}):")
            for folder in self.missing_folders:
                lines.append(f"  - {folder}")
                
        if self.permission_errors:
            lines.append(f"\nPermission errors ({len(self.permission_errors)}):")
            for folder in self.permission_errors:
                lines.append(f"  - {folder}")
                
        if self.not_directories:
            lines.append(f"\nNot directories ({len(self.not_directories)}):")
            for path in self.not_directories:
                lines.append(f"  - {path}")
                
        return "\n".join(lines)

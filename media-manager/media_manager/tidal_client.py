"""Tidal API client for playlist and track management."""

from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union
from datetime import datetime
from collections import Counter

import tidalapi
import shutil
from mutagen import File as MutagenFile

from media_manager.errors import (
    MediaManagerError,
    TidalAPIError,
    PlaylistVerificationError,
    FileOperationError,
)
from media_manager.utils import (
    check_null,
    normalize_name,
    extract_artist_and_track,
    LOGGER,
    collect_audio_files,
    sanitize_filename,
)


class Track:
    """Wrapper for Tidal track with normalized artist names and position."""

    def __init__(self, position: int, track: tidalapi.Track) -> None:
        """Initialize track wrapper.

        Args:
            position: Position of track in playlist (0-indexed)
            track: The inner tidalapi.Track object
        """
        self._inner = track

        self.position = position
        self.album = check_null("album", track.album)
        self.album_name = check_null(
            f"album_name for {self.album.name}", self.album.name
        )
        self.album_artist = check_null(
            f"album_artist for {self.album_name}", self.album.artist
        )

        self.name = track.full_name
        self.artists = [artist.name for artist in track.artists]
        self.track_num = track.track_num
        self.volume_num = track.volume_num

    @property
    def normalized_name(self) -> str:
        """Normalized track name for comparison."""
        return normalize_name(self.name)

    @property
    def normalized_artists(self) -> List[str]:
        """Normalized artist names for comparison."""
        return [normalize_name(artist) for artist in self.artists]

    def __str__(self) -> str:
        return f"Track(position={self.position}, name={self.name}, artists={self.artists}, album={self.album})"

    def __repr__(self) -> str:
        return self.__str__()

class PlaylistMatch:
    """Represents a match between a playlist track and a local file."""

    def __init__(self, track: "Track", local_file: Path, consolidated_album_artist: str) -> None:
        """Initialize playlist match.

        Args:
            track: The Track object from the playlist
            local_file: Path to the matching local file
            consolidated_album_artist: Pre-calculated consolidated album artist for this album
        """
        self.track = track
        self.local_file = local_file
        self.consolidated_album_artist = consolidated_album_artist

    def move_or_copy(
        self,
        base_destination: Path,
        copy: bool = False,
        move: bool = False,
        dry_run: bool = False,
    ) -> None:
        """Move or copy the local file to structured destination path.

        Args:
            base_destination: Base destination directory
            copy: If True, copy file instead of moving
            move: If True, move file instead of copying
            dry_run: If True, only simulate the operation

        Raises:
            FileOperationError: If file operation fails
        """
        if not copy and not move:
            return

        # We will only use `move` from this point forward for decisions
        # copy = not move

        if not self.local_file.exists():
            raise FileOperationError(
                "validate source", self.local_file, "Source file does not exist"
            )

        # Generate structured destination path
        destination = self._generate_destination_path(base_destination)

        if destination.exists() and not dry_run:
            LOGGER.info(
                f"Destination file already exists: {destination}. Skipping playlist position {self.track.position + 1}: {self.local_file} -> {destination}"
            )
            return

        if dry_run:
            LOGGER.info(
                f"Would {'move' if move else 'copy'} playlist position {self.track.position + 1}: {self.local_file} -> {destination}"
            )
        else:
            try:
                destination.parent.mkdir(parents=True, exist_ok=True)
                if move:
                    shutil.move(str(self.local_file), str(destination))
                else:
                    shutil.copy2(str(self.local_file), str(destination))
                LOGGER.debug(
                    f"{'Moved' if move else 'Copied'} playlist position {self.track.position + 1}: {self.local_file} -> {destination}"
                )
            except Exception as e:
                raise FileOperationError(
                    "move" if move else "copy",
                    self.local_file,
                    f"Failed to {'move' if move else 'copy'} to {destination}: {e}",
                )

    def _generate_destination_path(self, base_destination: Path) -> Path:
        """Generate structured destination path based on track metadata.

        Format: destination/album_artist/album/{padded_track_num} - {artists} - {track_name}.ext

        Args:
            base_destination: Base destination directory

        Returns:
            Full destination path with proper structure
        """
        # Get file extension from original file
        file_ext = self.local_file.suffix

        # Use the pre-calculated consolidated album artist
        album_artist = sanitize_filename(self.consolidated_album_artist)
        album_name = sanitize_filename(self.track.album_name)
        track_name = sanitize_filename(self.track.name)
        artists_str = sanitize_filename(", ".join(self.track.artists))

        # Build filename: {padded_track_num} - {artists} - {track_name}.ext
        filename = (
            f"{self.track.track_num:02d} - {artists_str} - {track_name}{file_ext}"
        )

        # Build full path: destination/album_artist/album/filename
        return base_destination / album_artist / album_name / filename



class Playlist:
    """
    Subset of tidalapi.Playlist for convinience.
    """

    id: str
    """Playlist ID"""

    name: str
    """Playlist name"""
    description: str
    """Playlist description"""
    duration: int
    """Duration of the playlist in seconds"""

    creator: Union[tidalapi.Artist, tidalapi.User]
    """Creator of the playlist"""
    created: datetime
    """Created timestamp"""
    last_updated: datetime
    """Last updated timestamp"""
    last_item_added_at: datetime
    """Last item added timestamp"""

    tracks: List[Track]
    """Tracks in the playlist"""

    popularity: Optional[int]
    """Popularity of the playlist"""
    promoted_artists: Optional[List[tidalapi.Artist]]
    """Promoted artists of the playlist"""

    _inner: tidalapi.Playlist
    """Inner tidalapi.Playlist object"""

    def __init__(self, playlist: tidalapi.Playlist) -> None:
        self._inner = playlist

        self.id = check_null("id", playlist.id)
        self.name = check_null("name", playlist.name)
        self.description = check_null("description", playlist.description)
        self.duration = check_null("duration", playlist.duration)
        self.creator = check_null("creator", playlist.creator)
        self.created = check_null("created", playlist.created)
        self.last_updated = check_null("last_updated", playlist.last_updated)
        self.last_item_added_at = check_null(
            "last_item_added_at", playlist.last_item_added_at
        )
        # Wrap tracks with position information
        raw_tracks = playlist.tracks()
        self.tracks = [
            Track(position, track) for position, track in enumerate(raw_tracks)
        ]

        self.popularity = playlist.popularity
        self.promoted_artists = playlist.promoted_artists
        
        # Build consolidated album artist mapping
        self._album_artist_map = self._build_album_artist_map()

    def __str__(self) -> str:
        return f"Playlist(id={self.id}, name={self.name}, tracks={len(self.tracks)})"

    def __repr__(self) -> str:
        return self.__str__()

    def _build_album_artist_map(self) -> Dict[str, str]:
        """Build a mapping of album_id -> consolidated_album_artist using frequency analysis.
        
        Returns:
            Dictionary mapping album IDs to their consolidated album artist names
        """
        # Group tracks by album ID
        album_tracks: Dict[str, List[Track]] = {}
        for track in self.tracks:
            album_id = track.album.id
            if album_id not in album_tracks:
                album_tracks[album_id] = []
            album_tracks[album_id].append(track)
        
        album_artist_map = {}
        
        for album_id, tracks in album_tracks.items():
            consolidated_artist = self._get_consolidated_album_artist(tracks)
            album_artist_map[album_id] = consolidated_artist
            
            # Log when we have multiple artists for visibility
            unique_artists = set()
            for track in tracks:
                unique_artists.update(track.artists)
            
            if len(unique_artists) > 1:
                LOGGER.info(f"Album '{tracks[0].album_name}' has {len(unique_artists)} unique artists, using '{consolidated_artist}' as folder name")
        
        return album_artist_map
    
    def _get_consolidated_album_artist(self, tracks: List[Track]) -> str:
        """Determine the best album artist for a group of tracks from the same album.
        
        Args:
            tracks: List of tracks from the same album
            
        Returns:
            Consolidated album artist name
        """
        if not tracks:
            return "Unknown Artist"
        
        # Count frequency of each artist across all tracks in the album
        artist_counter = Counter()
        for track in tracks:
            for artist in track.artists:
                artist_counter[artist] += 1
        
        # Get the most frequent artist(s)
        if artist_counter:
            most_common = artist_counter.most_common()
            max_count = most_common[0][1]
            
            # Get all artists with the maximum frequency
            top_artists = [artist for artist, count in most_common if count == max_count]
            
            if len(top_artists) == 1:
                return top_artists[0]
            else:
                # Multiple artists tied for most frequent
                # Check if we should use "Various Artists"
                if len(top_artists) > 2:
                    return "Various Artists"
                else:
                    # For 2 tied artists, combine with &
                    return " & ".join(sorted(top_artists))
        
        # Fallback to first track's album artist from Tidal
        return tracks[0].album_artist.name

    def get_track_artist_map(self) -> Dict[str, Track]:
        """Get a mapping of track names to Track objects from the playlist."""
        track_map: Dict[str, Track] = {}

        for track in self.tracks:
            # Use the normalized track name as key
            track_map[track.name] = track

        LOGGER.info(f"Fetched {len(track_map)} unique tracks from Tidal.")
        return track_map

    def verify_playlist(self, local_folders: List[Path]) -> List[PlaylistMatch]:
        """Verify that all tracks from the Tidal playlist are available locally.

        Args:
            local_folders: List folders expected to contain playlist tracks

        Returns:
            List of PlaylistMatch objects for successfully matched tracks

        Raises:
            PlaylistVerificationError: If verification fails
        """
        # Collect local files and build local track map with file paths
        local_files = collect_audio_files(local_folders)
        local_track_map: Dict[str, List[Tuple[str, Path]]] = {}
        parsing_errors = []

        for file_path in local_files:
            try:
                artist, track = extract_artist_and_track(file_path)
                if track not in local_track_map:
                    local_track_map[track] = []
                local_track_map[track].append((artist, file_path))
            except Exception as e:
                parsing_errors.append(f"{file_path}: {e}")

        # Check each playlist track exists locally
        artist_mismatches = []
        missing_from_local = []
        matches = []

        for track in self.tracks:
            track_name = track.normalized_name

            # Check if track exists locally
            local_entries = local_track_map.get(track_name)
            if not local_entries:
                missing_from_local.append(
                    f"Position {track.position + 1}: '{track.name}' by {', '.join(track.artists)}"
                )
                continue

            # Check if any playlist artist matches local artists
            matched_file = None
            for playlist_artist in track.normalized_artists:
                for local_artist, file_path in local_entries:
                    if playlist_artist == local_artist:
                        matched_file = file_path
                        break
                if matched_file:
                    break

            if matched_file:
                # Get consolidated album artist for this track's album
                consolidated_album_artist = self._album_artist_map.get(track.album.id, track.album_artist.name)
                # Create PlaylistMatch for successful match
                matches.append(PlaylistMatch(track, matched_file, consolidated_album_artist))
            else:
                local_artists = [artist for artist, _ in local_entries]
                artist_mismatches.append(
                    f"Position {track.position + 1}: Track '{track.name}' found locally with artists {local_artists} but playlist expects {track.artists}"
                )

        # Calculate summary statistics
        total_playlist_tracks = len(self.tracks)
        total_local_matches = len(matches)

        # Count unique albums and artists from playlist
        unique_albums = set()
        unique_artists = set()

        for track in self.tracks:
            unique_albums.add(track.album_name)
            unique_artists.update(track.artists)

        # Convert duration to human readable format (self.duration is already in seconds)
        total_duration_seconds = self.duration
        hours = total_duration_seconds // 3600
        minutes = (total_duration_seconds % 3600) // 60
        seconds = total_duration_seconds % 60

        if hours > 0:
            duration_str = f"{hours}h {minutes}m {seconds}s"
        else:
            duration_str = f"{minutes}m {seconds}s"

        # Log summary statistics
        LOGGER.info("=" * 60)
        LOGGER.info("PLAYLIST VERIFICATION SUMMARY")
        LOGGER.info("=" * 60)
        LOGGER.info(f"Playlist: {self.name}")
        LOGGER.info(f"Total tracks in playlist: {total_playlist_tracks}")
        LOGGER.info(f"Tracks available locally: {total_local_matches}")
        LOGGER.info(f"Missing tracks: {total_playlist_tracks - total_local_matches}")
        LOGGER.info(f"Unique albums: {len(unique_albums)}")
        LOGGER.info(f"Unique artists: {len(unique_artists)}")
        LOGGER.info(f"Total duration: {duration_str}")
        LOGGER.info(
            f"Match rate: {(total_local_matches / total_playlist_tracks * 100):.1f}%"
        )
        LOGGER.info("=" * 60)

        # Raise error if any validation issues found
        if parsing_errors or artist_mismatches or missing_from_local:
            raise PlaylistVerificationError(
                parsing_errors=parsing_errors,
                artist_mismatches=artist_mismatches,
                missing_from_playlist=missing_from_local,
            )

        return matches

    def move_or_copy(
        self,
        local_folders: List[Path],
        destination: Path,
        copy: bool = False,
        move: bool = False,
        dry_run: bool = False,
    ) -> None:
        """Move or copy the local files to destination with playlist ordering.

        Args:
            local_folders: List of local folders expected to contain playlist tracks
            destination: Destination folder path
            copy: If True, copy files
            move: If True, move files
            dry_run: If True, only simulate the operation

        Raises:
            FileOperationError: If file operations fail
        """
        matches = self.verify_playlist(local_folders)
        for match in matches:
            match.move_or_copy(destination, copy=copy, move=move, dry_run=dry_run)


class TidalClient:
    """Client for interacting with Tidal API."""

    def __init__(self, session_file: Path) -> None:
        """Initialize Tidal client with session file.

        Args:
            session_file: Path to the Tidal session OAuth file
        """
        self.session_file = session_file
        self.session: tidalapi.Session = tidalapi.Session()
        self.is_login = False

    def login(self) -> None:
        """Login to Tidal using the session file.

        Raises:
            TidalAPIError: If login fails.
        """
        LOGGER.debug("Logging into Tidal.")
        try:
            self.session.login_session_file(self.session_file)
            self.is_login = True
        except Exception as e:
            raise TidalAPIError("login", str(e))

    def get_playlist(self, playlist_id: str) -> Playlist:
        """Get a Playlist object from a Tidal playlist id.

        Args:
            playlist_id: The Tidal playlist ID

        Returns:
            Playlist object
        """
        if not self.is_login:
            self.login()

        try:
            LOGGER.debug("Fetching playlist with ID {}.", playlist_id)
            playlist = Playlist(self.session.playlist(playlist_id))
            if not playlist:
                raise TidalAPIError(
                    "fetch playlist", f"Playlist with ID {playlist_id} not found"
                )

            return playlist
        except Exception as e:
            if isinstance(e, MediaManagerError):
                raise
            raise TidalAPIError(
                "fetch playlist", f"Failed to fetch playlist {playlist_id}: {e}"
            )

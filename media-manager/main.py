"""Media Manager - Main entry point for the application."""

import argparse
import logging
from pathlib import Path

from media_manager import TidalClient, validate_input_folders


def start() -> None:
    """Start the media manager application with command line arguments."""
    parser = argparse.ArgumentParser(
        description="Merge audio files from multiple folders in order with Tidal playlist verification."
    )
    parser.add_argument(
        "input_folders", help="Comma separated list of folders in order"
    )
    parser.add_argument("--out", required=True, help="Output folder path")
    # Create mutually exclusive group for copy/move operations
    action_group = parser.add_mutually_exclusive_group()
    action_group.add_argument(
        "--copy", action="store_true", help="Copy files to destination"
    )
    action_group.add_argument(
        "--move", action="store_true", help="Move files to destination"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not actually copy/move, just simulate",
    )
    parser.add_argument(
        "--tidal-playlist-id", help="Tidal playlist ID for verification"
    )
    parser.add_argument(
        "--tidal-session-file",
        type=Path,
        default=Path("tidal-session-oauth.json"),
        help="Tidal session file path (default: tidal-session-oauth.json)",
    )
    args = parser.parse_args()

    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

    # Parse input folders
    input_folders = [Path(f.strip()) for f in args.input_folders.split(",")]
    output_folder = Path(args.out.strip())
    copy_files = bool(args.copy)
    move_files = bool(args.move)
    dry_run = bool(args.dry_run)
    tidal_playlist_id = str(args.tidal_playlist_id) if args.tidal_playlist_id else None
    tidal_session_file = Path(args.tidal_session_file)

    # Validate input folders before proceeding
    validate_input_folders(input_folders)

    # Initialize Tidal client if needed
    tidal_client = None
    if tidal_playlist_id:
        tidal_client = TidalClient(tidal_session_file)
        playlist = tidal_client.get_playlist(tidal_playlist_id)
        playlist.move_or_copy(
            input_folders,
            output_folder,
            copy=copy_files,
            move=move_files,
            dry_run=dry_run,
        )


if __name__ == "__main__":
    start()

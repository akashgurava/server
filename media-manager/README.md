# Media Manager

A powerful Python tool for organizing audio files based on Tidal playlists. It validates local music collections against Tidal playlists and creates structured directory hierarchies with proper metadata organization.

## Features

- **Tidal Integration**: Verify local music collections against Tidal playlists
- **Smart Matching**: Normalized track and artist name matching for reliable verification
- **Structured Organization**: Creates clean directory structure: `Artist/Album/TrackNum - Artists - Track Name.ext`
- **Comprehensive Statistics**: Shows playlist summary with track counts, unique albums/artists, and duration
- **Safe Operations**: Explicit `--copy` or `--move` flags required, with mutually exclusive validation
- **Dry Run Support**: Preview operations without making changes
- **Robust Error Handling**: Detailed error reporting for missing tracks, parsing issues, and mismatches
- **File Validation**: Pre-flight checks for folder existence, permissions, and readability
- **Case Preservation**: Maintains original track name capitalization while normalizing for comparison
- **Filesystem Safety**: Sanitizes filenames to remove problematic characters

## Installation

### Prerequisites

- Python 3.8+
- [uv](https://docs.astral.sh/uv/) package manager

### Setup with uv

1. **Install uv** (if not already installed):
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd media-manager
   ```

3. **Install dependencies**:
   ```bash
   uv sync
   ```

4. **Set up Tidal authentication**:
   - Create a `tidal-session-oauth.json` file in the project root
   - Follow Tidal API authentication process to populate the session file

## Usage

### Basic Syntax

```bash
uv run python main.py "folder1,folder2,folder3" --out /output/path [OPTIONS]
```

### Command Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `input_folders` | Comma-separated list of input folders | Yes |
| `--out` | Output directory path | Yes |
| `--copy` | Copy files to destination | No* |
| `--move` | Move files to destination | No* |
| `--dry-run` | Simulate operations without making changes | No |
| `--tidal-playlist-id` | Tidal playlist ID for verification | No |
| `--tidal-session-file` | Path to Tidal session file (default: `tidal-session-oauth.json`) | No |

*Note: Either `--copy` or `--move` is required for file operations. Without either flag, only validation and statistics are shown.

### Examples

#### 1. Validation Only (Default)
```bash
uv run python main.py "/music/part1,/music/part2" --out /organized --tidal-playlist-id abc123
```
Shows playlist statistics and validation results without moving files.

#### 2. Copy Files with Playlist Verification
```bash
uv run python main.py "/music/part1,/music/part2" --out /organized --tidal-playlist-id abc123 --copy
```

#### 3. Move Files (Dry Run)
```bash
uv run python main.py "/music/part1,/music/part2" --out /organized --tidal-playlist-id abc123 --move --dry-run
```

#### 4. Copy Without Tidal Verification
```bash
uv run python main.py "/music/part1,/music/part2" --out /organized --copy
```

## Output Structure

The tool creates a hierarchical directory structure based on album metadata:

```
/output/
├── Artist Name/
│   ├── Album Name/
│   │   ├── 01 - Artist Name - Track Name.flac
│   │   ├── 02 - Artist Name, Collaborator - Track Name.flac
│   │   └── ...
│   └── Another Album/
│       └── ...
└── Another Artist/
    └── ...
```

### Filename Format
```
{TrackNumber} - {Artists} - {TrackName}.{Extension}
```

- **Track Number**: Zero-padded based on album size (01, 02, etc.)
- **Artists**: Comma-separated list of all track artists
- **Track Name**: Original case preserved
- **Extension**: Preserved from source file

## Sample Output

```
============================================================
PLAYLIST VERIFICATION SUMMARY
============================================================
Playlist: My Awesome Playlist
Total tracks in playlist: 214
Tracks available locally: 214
Missing tracks: 0
Unique albums: 163
Unique artists: 225
Total duration: 12h 34m 48s
Match rate: 100.0%
============================================================
```

## Project Structure

```
media-manager/
├── media_manager/
│   ├── __init__.py          # Package initialization and exports
│   ├── errors.py            # Custom exception classes
│   ├── file_operations.py   # File handling utilities (legacy)
│   ├── tidal_client.py      # Tidal API integration and core logic
│   └── utils.py             # Utility functions and validation
├── main.py                  # CLI entry point
├── pyproject.toml          # Project configuration and dependencies
├── uv.lock                 # Dependency lock file
├── tidal-session-oauth.json # Tidal authentication (not in repo)
└── README.md               # This file
```

## Architecture

### Core Components

1. **Track Class**: Wraps Tidal track data with normalized comparison properties
2. **PlaylistMatch Class**: Links playlist tracks to local files with structured copy/move operations
3. **Playlist Class**: Manages playlist verification and batch operations
4. **TidalClient Class**: Handles Tidal API authentication and playlist fetching

### Key Features

- **Normalized Matching**: Uses `normalize_name()` for reliable track/artist comparison
- **Filesystem Safety**: `sanitize_filename()` removes problematic characters
- **Error Handling**: Comprehensive exception hierarchy with detailed error messages
- **Validation Pipeline**: Multi-stage validation from folders to playlist verification

## Error Handling

The tool provides detailed error reporting for common issues:

- **Missing Folders**: Reports non-existent input directories
- **Permission Errors**: Identifies unreadable directories
- **Parsing Errors**: Shows files that don't match expected naming format
- **Artist Mismatches**: Reports tracks found locally but with different artists
- **Missing Tracks**: Lists playlist tracks not found in local collection

## Development

### Running Tests
```bash
uv run pytest
```

### Code Formatting
```bash
uv run ruff format
```

### Type Checking
```bash
uv run mypy media_manager/
```

## Dependencies

- **tidalapi**: Tidal streaming service API integration
- **pathlib**: Modern path handling (built-in)
- **argparse**: Command-line argument parsing (built-in)
- **logging**: Comprehensive logging support (built-in)
- **shutil**: File operations (built-in)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

[Add your license information here]

## Troubleshooting

### Common Issues

1. **"No action specified"**: Use `--copy` or `--move` flag for file operations
2. **Tidal authentication errors**: Ensure `tidal-session-oauth.json` is properly configured
3. **Permission denied**: Check read permissions on input folders and write permissions on output folder
4. **Track not found**: Verify local files follow the expected naming format: `Artist - Track.ext`

### Getting Help

- Check the error messages for specific guidance
- Use `--dry-run` to preview operations
- Verify input folder structure and file naming conventions

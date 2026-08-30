# OmaPlex Music

An unofficial native Omarchy bar widget for browsing and playing music from a
Plex Media Server. Click the bar item to open a compact library browser and
player. OmaPlex Music is not affiliated with or endorsed by Plex, Inc.

## Features

- Recently added albums and full-library search
- Album track lists with continuous album playback
- Cover art, track progress, seek, volume, play/pause, previous, and next
- Native Omarchy/Quickshell styling with top, bottom, and vertical bar support
- Keyboard and mouse navigation
- No Python packages: the helper uses only Python's standard library
- Plex token stored outside the plugin in a mode-`0600` config file
- mpv IPC playback keeps the Plex token out of the process list

## Requirements

- Omarchy 4.0 or newer with the plugin-based shell
- Python 3.10 or newer
- mpv (`omarchy pkg add mpv`)
- A reachable Plex Media Server with a music library
- A Plex authentication token

## Install

After this repository has been published on GitHub:

```bash
omarchy plugin add https://github.com/flathack/omarchy-omaplex-music.git --enable
```

The manifest suggests the center of the bar. Move it at any time with:

```bash
omarchy bar move flathack.omaplex-music --section center
```

## Configure

Right-click the bar widget, or run the bundled setup command:

```bash
~/.config/omarchy/plugins/flathack.omaplex-music/bin/omarchy-omaplex-music configure
```

Enter the base URL of the Plex server, for example
`http://192.168.1.20:32400`, and paste a Plex access token when prompted. Token
input is hidden. If the server has several music libraries, setup asks which
one to use.

Plex documents how to find an authentication token in its support article:
[Finding an authentication token / X-Plex-Token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/).

Connection details are stored in:

```text
${XDG_CONFIG_HOME:-~/.config}/omarchy-omaplex-music/config.json
```

## Usage

- Left-click the bar item to open the player.
- Right-click it to reconfigure the Plex connection.
- Middle-click it to play or pause.
- Scroll over it to move to the previous or next track.
- Type in the panel to search Plex.
- Click an album to open its tracks; click a track to start playback.
- Use Up/Down and Enter while the search field is focused.

The CLI is also useful for troubleshooting:

```bash
PLAYER="$HOME/.config/omarchy/plugins/flathack.omaplex-music/bin/omarchy-omaplex-music"
"$PLAYER" doctor
"$PLAYER" status
"$PLAYER" recent --limit 5
```

## Configuration

The number of recent albums defaults to 20 and is exposed through Omarchy's
plugin settings schema:

```bash
omarchy bar set flathack.omaplex-music recentAlbumCount 30
```

## Updates and removal

```bash
omarchy plugin update flathack.omaplex-music
omarchy plugin remove flathack.omaplex-music
```

Removing the plugin intentionally leaves the connection settings and artwork
cache in place. To remove them too, move these folders to the desktop trash:

```bash
gio trash "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-omaplex-music"
gio trash "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-omaplex-music"
```

## Development

Run the tests and the same manifest validation used during installation:

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

For local development, symlink the checkout and enable it:

```bash
ln -s "$PWD" "$HOME/.config/omarchy/plugins/flathack.omaplex-music"
omarchy plugin enable flathack.omaplex-music --section center
```

Files below the plugin folder hot-reload in the Omarchy shell.

## Privacy and limitations

Library requests, cover downloads, and audio streams go directly to the Plex
server configured by the user. No third-party service is involved. See
[SECURITY.md](SECURITY.md) for credential handling details.

- Playback is local to this computer; this version does not remote-control a
  Plexamp client on another device.
- Plex transcoding decisions remain under the Plex server's control.
- The plugin implements the Plex server endpoints used by current Plex music
  libraries. Plex does not publish these endpoints as a stable public SDK.

## License

MIT

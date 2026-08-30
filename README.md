# OmaPlex Music

An unofficial native Omarchy bar widget for browsing and playing music from a
Plex Media Server. Click the bar item to open a compact library browser and
player. OmaPlex Music is not affiliated with or endorsed by Plex, Inc.

![OmaPlex Music player preview](preview.png)

## Features

- Plex browser sign-in — no token copying required
- Home, artists, albums, playlists, history, favorites, queue, and search
- Artist → album → track and playlist → track navigation
- Album/playlist play and shuffle actions
- Manageable queue with play, reorder, remove, and clear-upcoming actions
- Cover art, progress, seek, 0–130% volume, play/pause, previous, and next
- Shuffle, repeat-all, and repeat-one
- MPRIS integration for hardware media keys and desktop media controls
- Actionable offline, authentication, DNS, library, and server error states
- Concurrent artwork loading, bounded private cache, and offline last-good data
- Native Omarchy/Quickshell styling with top, bottom, and vertical bar support
- Keyboard and mouse navigation
- Credential-free demo mode with fictional music
- No Python packages: the helper uses only Python's standard library
- Plex access stored outside the plugin in a mode-`0600` config file
- mpv IPC playback keeps the Plex token out of the process list

## Requirements

- Omarchy 4.0 or newer with the plugin-based shell
- Python 3.10 or newer
- mpv (`omarchy pkg add mpv`)
- mpv-mpris (`omarchy pkg add mpv-mpris`) for media keys and MPRIS
- A reachable Plex Media Server with a music library
- A Plex account that can access that server

## Install

```bash
omarchy plugin add https://github.com/flathack/omarchy-omaplex-music.git --enable
```

The manifest suggests the center of the bar. Move it at any time with:

```bash
omarchy bar move flathack.omaplex-music --section center
```

## Connect Plex

When the player is not connected, click **Connect with Plex**. OmaPlex asks for
the server URL, opens Plex's sign-in page in the browser, and waits for you to
approve the app. Your Plex password is entered only on Plex's website and is
never visible to the plugin.

The same flow is available from a terminal:

```bash
~/.config/omarchy/plugins/flathack.omaplex-music/bin/omarchy-omaplex-music login
```

Enter the base URL, for example `http://192.168.1.20:32400`. If the server has
several music libraries, setup asks which one to use.

Right-clicking the bar widget retains the manual token setup as a recovery
fallback. Plex documents that fallback in
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
- Use the navigation rail to browse artists, albums, playlists, history,
  favorites, and the active queue.
- Click a collection to open it, or use its inline play/shuffle actions.
- Reorder or remove upcoming tracks in the Queue view.
- Use Up/Down and Enter while the search field is focused.
- Hardware media keys work through MPRIS while mpv is running.

The CLI is also useful for troubleshooting:

```bash
PLAYER="$HOME/.config/omarchy/plugins/flathack.omaplex-music/bin/omarchy-omaplex-music"
"$PLAYER" doctor
"$PLAYER" status
"$PLAYER" health
"$PLAYER" library artists --limit 5
"$PLAYER" queue
```

## Configuration

Plugin settings are exposed through Omarchy's schema:

```bash
omarchy bar set flathack.omaplex-music recentAlbumCount 30
omarchy bar set flathack.omaplex-music libraryItemCount 150
```

### Demo mode

Demo mode shows fictional data, never contacts Plex, and never starts mpv:

```bash
omarchy bar set flathack.omaplex-music demoMode true --json
# Restore the real library afterwards:
omarchy bar set flathack.omaplex-music demoMode false --json
```

## Updates and removal

```bash
omarchy plugin update flathack.omaplex-music
omarchy plugin remove flathack.omaplex-music
```

Removing the plugin intentionally leaves connection settings and artwork cache
in place. To remove them too, move these folders to the desktop trash:

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
server configured by the user. The browser sign-in talks to `plex.tv`; no
other third-party service is involved. See
[SECURITY.md](SECURITY.md) for credential handling details.

- Playback is local to this computer; this version does not remote-control a
  Plexamp client on another device.
- Plex transcoding decisions remain under the Plex server's control.
- The plugin implements the Plex server endpoints used by current Plex music
  libraries. Plex does not publish these endpoints as a stable public SDK.

## License

MIT

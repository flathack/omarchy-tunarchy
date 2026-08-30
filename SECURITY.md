# Security

## Credentials

The setup command stores the Plex server URL, access token, and selected music
library in `${XDG_CONFIG_HOME:-~/.config}/omarchy-omaplex-music/config.json`. The
directory is created with mode `0700` and the file with mode `0600`. Credentials
are never stored in this repository or in `shell.json`.

The token is sent only to the configured Plex server. Playback URLs are passed
to mpv over a user-owned Unix socket rather than on mpv's command line. Cover
art is downloaded into `${XDG_CACHE_HOME:-~/.cache}/omarchy-omaplex-music`.

As with every Omarchy shell plugin, the QML and helper execute unsandboxed as
the logged-in user. Review updates before accepting them.

## Reporting a vulnerability

Please open a private GitHub security advisory instead of a public issue. Do
not include Plex tokens, server addresses, or library contents in reports.

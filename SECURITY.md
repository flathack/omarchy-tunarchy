# Security

## Credentials

The Plex browser sign-in stores the server URL, access token, persistent random
client identifier, and selected music
library in `${XDG_CONFIG_HOME:-~/.config}/tunarchy/config.json`. The
directory is created with mode `0700` and the file with mode `0600`. Credentials
are never stored in this repository or in `shell.json`.

Local configuration and cache operations are bound to opened directory file
descriptors. Symlinked path components, files not owned by the current user,
group- or world-accessible files, and oversized payloads are rejected. Updates
are written to private, exclusively created temporary files and atomically
replaced within the same verified directory.

The PIN login exchanges its one-time code directly with `plex.tv`. The resulting
token is sent only to Plex, the configured Plex server, and the local mpv process.
Tunarchy passes it to mpv as a file-local HTTP header over a user-owned Unix
socket; it is not included in process arguments, playback URLs, or MPRIS metadata,
and unrelated URLs opened in mpv do not inherit it. Cover art and
last-good library payloads are stored in
`${XDG_CACHE_HOME:-~/.cache}/tunarchy`, whose size and age are
bounded automatically. Demo mode does not read credentials or contact Plex.

As with every Omarchy shell plugin, the QML and helper execute unsandboxed as
the logged-in user. Review updates before accepting them.

## Reporting a vulnerability

Please open a private GitHub security advisory instead of a public issue. Do
not include Plex tokens, server addresses, or library contents in reports.

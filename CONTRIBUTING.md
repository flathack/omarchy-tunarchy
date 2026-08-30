# Contributing

Bug reports and pull requests are welcome. Keep the runtime dependency-light:
QML/Quickshell for the interface, Python's standard library for Plex access,
and mpv for playback.

Run the checks before opening a pull request:

```bash
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

Never add real Plex URLs, tokens, library names, or media metadata to fixtures.

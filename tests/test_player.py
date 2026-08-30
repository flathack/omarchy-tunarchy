import importlib.machinery
import importlib.util
import json
import pathlib
import stat
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omarchy-omaplex-music"


def load_player():
    loader = importlib.machinery.SourceFileLoader("omarchy_plex_music", str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


player = load_player()


class StorageTests(unittest.TestCase):
    def test_atomic_json_is_private_and_round_trips(self):
        with tempfile.TemporaryDirectory() as folder:
            target = pathlib.Path(folder) / "private" / "config.json"
            player.atomic_json(target, {"token": "secret", "name": "Música"})
            self.assertEqual(player.load_json(target, {}), {"token": "secret", "name": "Música"})
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)

    def test_malformed_json_uses_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            target = pathlib.Path(folder) / "broken.json"
            target.write_text("{", encoding="utf-8")
            self.assertEqual(player.load_json(target, {"ok": False}), {"ok": False})


class PlexModelTests(unittest.TestCase):
    def setUp(self):
        self.config = {"server": "http://plex.test:32400", "token": "tok", "section": "4"}

    def test_metadata_normalizes_missing_rows(self):
        self.assertEqual(player.metadata({}), [])
        self.assertEqual(player.metadata({"MediaContainer": {"Metadata": [{"title": "A"}]}}), [{"title": "A"}])

    def test_sections_keeps_music_libraries_only(self):
        payload = {"MediaContainer": {"Directory": [
            {"key": "1", "title": "Movies", "type": "movie"},
            {"key": "4", "title": "Music", "type": "artist"},
        ]}}
        with mock.patch.object(player, "plex_request", return_value=payload):
            self.assertEqual(player.sections(self.config), [{"key": "4", "title": "Music"}])

    def test_compact_track(self):
        row = {
            "ratingKey": "99", "type": "track", "title": "Song",
            "grandparentTitle": "Artist", "parentTitle": "Album",
            "duration": 183250, "year": 2024, "thumb": "/thumb/99",
        }
        with mock.patch.object(player, "art_path", return_value="file:///cover.jpg"):
            result = player.compact_item(self.config, row)
        self.assertEqual(result["artist"], "Artist")
        self.assertEqual(result["album"], "Album")
        self.assertEqual(result["duration"], 183.25)
        self.assertEqual(result["thumb"], "file:///cover.jpg")

    def test_recent_uses_selected_section_and_clamps_limit(self):
        payload = {"MediaContainer": {"Metadata": [{"ratingKey": "8", "type": "album", "title": "Record"}]}}
        with mock.patch.object(player, "music_section", return_value="4"), \
             mock.patch.object(player, "plex_request", return_value=payload) as request, \
             mock.patch.object(player, "art_path", return_value=""):
            result = player.recent(self.config, 200)
        self.assertEqual(result[0]["title"], "Record")
        self.assertEqual(request.call_args.args[1], "/library/sections/4/recentlyAdded")
        self.assertEqual(request.call_args.args[2]["X-Plex-Container-Size"], 50)

    def test_stream_url_encodes_token(self):
        url = player.stream_url({"server": "http://plex", "token": "a b&c"}, "/library/parts/7/file.flac")
        self.assertEqual(url, "http://plex/library/parts/7/file.flac?X-Plex-Token=a+b%26c")


class PlayerTests(unittest.TestCase):
    def test_play_replaces_old_queue_then_appends_album(self):
        queue = [
            {"key": "1", "type": "track", "title": "First"},
            {"key": "2", "type": "track", "title": "Second"},
        ]
        details = {
            "1": ({"key": "1", "title": "First"}, "/part/1"),
            "2": ({"key": "2", "title": "Second"}, "/part/2"),
        }
        with mock.patch.object(player, "album_tracks", return_value=queue), \
             mock.patch.object(player, "start_mpv"), \
             mock.patch.object(player, "raw_track", side_effect=lambda config, key: details[key]), \
             mock.patch.object(player, "mpv_command") as command, \
             mock.patch.object(player, "atomic_json"), \
             mock.patch.object(player, "status", return_value={"playing": True}):
            result = player.play({"server": "http://plex", "token": "tok"}, "2", "album")
        self.assertEqual(command.call_args_list[0].args[0][-1], "replace")
        self.assertEqual(command.call_args_list[1].args[0][-1], "append")
        self.assertEqual(command.call_args_list[2].args[0], ["set_property", "playlist-pos", 1])
        self.assertTrue(result["playing"])

    def test_control_clamps_volume(self):
        with mock.patch.object(player, "load_config", return_value={}), \
             mock.patch.object(player, "mpv_running", return_value=True), \
             mock.patch.object(player, "mpv_command") as command, \
             mock.patch.object(player, "status", return_value={"volume": 130}):
            result = player.control("volume", 999)
        command.assert_called_once_with(["set_property", "volume", 130])
        self.assertEqual(result["volume"], 130)

    def test_unconfigured_status_does_not_start_player(self):
        with mock.patch.object(player, "load_config", return_value={}), \
             mock.patch.object(player, "load_json", return_value={"queue": []}), \
             mock.patch.object(player, "mpv_running", return_value=False):
            result = player.status()
        self.assertFalse(result["configured"])
        self.assertFalse(result["playing"])


class RepositoryContractTests(unittest.TestCase):
    def test_manifest_and_entry_point(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "flathack.omaplex-music")
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertIn("bar-widget", manifest["kinds"])
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())

    def test_no_credentials_are_tracked(self):
        forbidden = b"X-Plex" + b"-Token=" + b"real"
        for path in ROOT.rglob("*"):
            if path.is_file() and ".git" not in path.parts and "__pycache__" not in path.parts:
                source = path.read_bytes()
                self.assertNotIn(forbidden, source, str(path))


if __name__ == "__main__":
    unittest.main()

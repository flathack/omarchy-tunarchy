import concurrent.futures
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import pathlib
import stat
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "tunarchy"


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
            target.chmod(0o600)
            self.assertEqual(player.load_json(target, {"ok": False}), {"ok": False})

    def test_atomic_json_rejects_symlinked_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            outside = root / "outside"
            outside.mkdir(mode=0o700)
            (root / "state").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(player.PlayerError, "opened safely"):
                player.atomic_json(root / "state" / "config.json", {"ok": True})
            self.assertFalse((outside / "config.json").exists())

    def test_load_json_rejects_symlinked_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            outside = root / "outside"
            outside.mkdir(mode=0o700)
            target = outside / "config.json"
            player.atomic_json(target, {"ok": True})
            (root / "state").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(player.PlayerError, "opened safely"):
                player.load_json(root / "state" / "config.json", {})

    def test_private_storage_rejects_unsafe_permissions(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            unsafe = root / "unsafe"
            unsafe.mkdir(mode=0o777)
            unsafe.chmod(0o777)
            with self.assertRaisesRegex(player.PlayerError, "mode 0700"):
                player.atomic_json(unsafe / "config.json", {"ok": True})
            self.assertEqual(stat.S_IMODE(unsafe.stat().st_mode), 0o777)

            exposed = root / "exposed.json"
            exposed.write_text('{"ok": true}\n', encoding="utf-8")
            exposed.chmod(0o644)
            with self.assertRaisesRegex(player.PlayerError, "private regular file"):
                player.load_json(exposed, {})

    def test_local_storage_enforces_size_limits(self):
        with tempfile.TemporaryDirectory() as folder:
            target = pathlib.Path(folder) / "data.json"
            with self.assertRaisesRegex(player.PlayerError, "security policy"):
                player.atomic_json(target, {"value": "x" * 200}, maximum=64)
            player.atomic_bytes(target, b"x" * 65)
            with self.assertRaisesRegex(player.PlayerError, "size limit"):
                player.read_regular_file(target, maximum=64)

    def test_atomic_write_stays_bound_to_opened_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            state = root / "state"
            held = root / "held"
            state.mkdir(mode=0o700)
            target = state / "config.json"
            real_open = player.secure_parent_directory

            @contextlib.contextmanager
            def replace_path(path, create=False):
                with real_open(path, create=create) as opened:
                    state.rename(held)
                    state.mkdir(mode=0o700)
                    yield opened

            with mock.patch.object(player, "secure_parent_directory", replace_path):
                player.atomic_json(target, {"destination": "held"})
            self.assertEqual(player.load_json(held / "config.json", {}), {"destination": "held"})
            self.assertFalse((state / "config.json").exists())

    def test_private_read_stays_bound_to_opened_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            state = root / "state"
            held = root / "held"
            state.mkdir(mode=0o700)
            player.atomic_json(state / "config.json", {"source": "held"})
            real_open = player.secure_parent_directory

            @contextlib.contextmanager
            def replace_path(path, create=False):
                with real_open(path, create=create) as opened:
                    state.rename(held)
                    state.mkdir(mode=0o700)
                    replacement = state / "config.json"
                    replacement.write_text('{"source": "replacement"}\n', encoding="utf-8")
                    replacement.chmod(0o600)
                    yield opened

            with mock.patch.object(player, "secure_parent_directory", replace_path):
                result = player.load_json(state / "config.json", {})
            self.assertEqual(result, {"source": "held"})

    def test_atomic_json_supports_concurrent_writers(self):
        with tempfile.TemporaryDirectory() as folder:
            target = pathlib.Path(folder) / "state.json"
            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
                list(executor.map(lambda index: player.atomic_json(target, {"writer": index}), range(100)))
            self.assertIn("writer", player.load_json(target, {}))
            self.assertFalse(list(target.parent.glob("*.tmp")))

    def test_state_lock_serializes_read_modify_write(self):
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "STATE_FILE", pathlib.Path(folder) / "state.json"):
            player.atomic_json(player.STATE_FILE, {"count": 0})

            def increment(_):
                with player.state_lock():
                    state = player.load_json(player.STATE_FILE, {})
                    state["count"] += 1
                    player.atomic_json(player.STATE_FILE, state)

            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
                list(executor.map(increment, range(100)))
            self.assertEqual(player.load_json(player.STATE_FILE, {})["count"], 100)

    def test_client_identifier_is_generated_once(self):
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "CONFIG_FILE", pathlib.Path(folder) / "config.json"):
            first = player.client_identifier()
            second = player.client_identifier()
            self.assertEqual(first, second)
            self.assertGreater(len(first), 20)

    def test_cache_cleanup_enforces_size_limit(self):
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "CACHE_DIR", pathlib.Path(folder)), \
             mock.patch.object(player, "ART_CACHE_DIR", pathlib.Path(folder) / "art"), \
             mock.patch.object(player, "DATA_CACHE_DIR", pathlib.Path(folder) / "data"):
            player.ensure_private_dir(player.ART_CACHE_DIR)
            for index in range(3):
                (player.ART_CACHE_DIR / f"{index}.jpg").write_bytes(b"x" * 20)
            result = player.cleanup_cache(max_age_days=30, max_bytes=25)
            self.assertGreaterEqual(result["removed"], 2)
            self.assertLessEqual(sum(path.stat().st_size for path in player.ART_CACHE_DIR.iterdir()), 25)


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

    def test_library_list_applies_client_side_limit(self):
        payload = {"MediaContainer": {"Metadata": [
            {"ratingKey": str(index), "type": "album", "title": f"Album {index}"} for index in range(20)
        ]}}
        with mock.patch.object(player, "music_section", return_value="4"), \
             mock.patch.object(player, "plex_request", return_value=payload), \
             mock.patch.object(player, "compact_items", side_effect=lambda config, rows: rows):
            result = player.library_list(self.config, "albums", 5)
        self.assertEqual(len(result), 5)

    def test_favorites_filters_unrated_tracks_client_side(self):
        payload = {"MediaContainer": {"Metadata": [
            {"ratingKey": "1", "type": "track", "title": "Unrated"},
            {"ratingKey": "2", "type": "track", "title": "Favorite", "userRating": 10},
        ]}}
        with mock.patch.object(player, "music_section", return_value="4"), \
             mock.patch.object(player, "plex_request", return_value=payload), \
             mock.patch.object(player, "compact_items", side_effect=lambda config, rows: rows):
            result = player.library_list(self.config, "favorites", 5)
        self.assertEqual([row["title"] for row in result], ["Favorite"])

    def test_cached_items_uses_last_good_data_for_network_failure(self):
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "DATA_CACHE_DIR", pathlib.Path(folder)):
            target = player.data_cache_path(self.config, "albums")
            player.atomic_json(target, {"items": [{"title": "Cached"}], "cachedAt": 1})
            result = player.cached_items(self.config, "albums", lambda: (_ for _ in ()).throw(player.PlayerError("offline", "unreachable")))
        self.assertTrue(result["stale"])
        self.assertEqual(result["items"][0]["title"], "Cached")

    def test_cache_paths_are_isolated_by_server_and_account(self):
        first = {"server": "http://plex-a:32400", "token": "first", "section": "4"}
        second = {"server": "http://plex-b:32400", "token": "second", "section": "4"}
        self.assertNotEqual(player.data_cache_path(first, "albums"), player.data_cache_path(second, "albums"))
        self.assertNotEqual(player.cache_namespace(first), player.cache_namespace(second))

    def test_art_cache_does_not_cross_server_boundaries(self):
        class Response:
            def __init__(self, value):
                self.value = value

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, _):
                return self.value

        first = {"server": "http://plex-a:32400", "token": "first", "section": "4"}
        second = {"server": "http://plex-b:32400", "token": "second", "section": "4"}
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "ART_CACHE_DIR", pathlib.Path(folder)), \
             mock.patch.object(player.urllib.request, "urlopen", side_effect=[Response(b"first"), Response(b"second")]) as request:
            first_uri = player.art_path(first, "/library/metadata/1/thumb/2")
            second_uri = player.art_path(second, "/library/metadata/1/thumb/2")
        self.assertNotEqual(first_uri, second_uri)
        self.assertEqual(request.call_count, 2)


class AuthenticationTests(unittest.TestCase):
    def test_login_uses_pin_flow_and_saves_token_privately(self):
        responses = [
            {"id": 42, "code": "pin-code"},
            {"authToken": None},
            {"authToken": "access-token"},
        ]
        with tempfile.TemporaryDirectory() as folder, \
             mock.patch.object(player, "CONFIG_FILE", pathlib.Path(folder) / "config.json"), \
             mock.patch.object(player, "plex_cloud_request", side_effect=responses), \
             mock.patch.object(player, "choose_music_library", side_effect=lambda candidate, *args, **kwargs: candidate.update({"section": "4", "sectionTitle": "Music"}) or candidate), \
             mock.patch.object(player.subprocess, "Popen"), \
             mock.patch.object(player.time, "sleep"):
            with contextlib.redirect_stdout(io.StringIO()):
                result = player.login("http://plex:32400")
            saved = player.load_json(player.CONFIG_FILE, {})
            mode = stat.S_IMODE(player.CONFIG_FILE.stat().st_mode)
        self.assertTrue(result["connected"])
        self.assertEqual(saved["token"], "access-token")
        self.assertEqual(mode, 0o600)

    def test_connection_health_preserves_transient_error_code(self):
        with mock.patch.object(player, "load_config", return_value={"server": "http://plex", "token": "x"}), \
             mock.patch.object(player, "sections", side_effect=player.PlayerError("offline", "timeout")):
            result = player.connection_health()
        self.assertEqual(result["code"], "timeout")
        self.assertFalse(result["ok"])


class PlayerTests(unittest.TestCase):
    def setUp(self):
        self.state_folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.state_folder.cleanup)
        self.state_patch = mock.patch.object(player, "STATE_FILE", pathlib.Path(self.state_folder.name) / "state.json")
        self.state_patch.start()
        self.addCleanup(self.state_patch.stop)

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
        self.assertIn("/part/2", command.call_args_list[0].args[0][1])
        self.assertEqual(command.call_args_list[0].args[0][-1], "replace")
        self.assertEqual(command.call_args_list[1].args[0], ["set_property", "pause", False])
        self.assertEqual(command.call_args_list[2].args[0][-1], "append")
        self.assertEqual(command.call_args_list[3].args[0], ["set_property", "playlist-pos", 0])
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

    def test_repeat_cycles_off_all_one(self):
        state = {"queue": [], "repeat": "off", "shuffle": False}
        with mock.patch.object(player, "load_config", return_value={}), \
             mock.patch.object(player, "mpv_running", return_value=True), \
             mock.patch.object(player, "state_data", return_value=state), \
             mock.patch.object(player, "save_state"), \
             mock.patch.object(player, "mpv_command") as command, \
             mock.patch.object(player, "status", return_value={"repeat": "all"}):
            result = player.control("repeat")
        self.assertEqual(state["repeat"], "all")
        self.assertIn(mock.call(["set_property", "loop-playlist", "inf"]), command.call_args_list)
        self.assertEqual(result["repeat"], "all")

    def test_queue_remove_updates_mpv_and_state(self):
        state = {"queue": [{"key": "1"}, {"key": "2"}], "repeat": "off", "shuffle": False}
        with mock.patch.object(player, "state_data", return_value=state), \
             mock.patch.object(player, "mpv_running", return_value=True), \
             mock.patch.object(player, "property_or", return_value=0), \
             mock.patch.object(player, "mpv_command") as command, \
             mock.patch.object(player, "save_state"), \
             mock.patch.object(player, "queue_view", return_value={"items": [{"key": "1"}]}):
            result = player.queue_action("remove", index=1)
        command.assert_called_once_with(["playlist-remove", 1])
        self.assertEqual(state["queue"], [{"key": "1"}])
        self.assertEqual(len(result["items"]), 1)

    def test_current_queue_track_cannot_be_moved_or_removed(self):
        state = {"queue": [{"key": "1"}, {"key": "2"}], "repeat": "off", "shuffle": False}
        with mock.patch.object(player, "state_data", return_value=state), \
             mock.patch.object(player, "mpv_running", return_value=True), \
             mock.patch.object(player, "property_or", return_value=1), \
             mock.patch.object(player, "mpv_command") as command:
            for action in ("move", "remove"):
                with self.assertRaisesRegex(player.PlayerError, "currently playing"):
                    player.queue_action(action, index=1, destination=0)
        command.assert_not_called()

    def test_demo_never_requires_plex(self):
        result = player.demo_dispatch(mock.Mock(command="library", view="artists"))
        self.assertTrue(result["demo"])
        self.assertEqual({item["type"] for item in result["items"]}, {"artist"})


class RepositoryContractTests(unittest.TestCase):
    def test_manifest_and_entry_point(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "io.github.flathack.tunarchy")
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertIn("bar-widget", manifest["kinds"])
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())
        self.assertEqual(manifest["version"], "0.4.5")
        for asset in ("tuna-brand.png", "tuna-ui-18.png", "tuna-ui-24.png", "tuna-ui-64.png"):
            self.assertTrue((ROOT / "assets" / asset).is_file())
        self.assertTrue((ROOT / "preview.png").is_file())

    def test_mpris_client_name_is_a_valid_bus_component(self):
        helper = (ROOT / "bin" / "tunarchy").read_text(encoding="utf-8")
        self.assertIn('"--audio-client-name=Tunarchy"', helper)

    def test_no_credentials_are_tracked(self):
        forbidden = b"X-Plex" + b"-Token=" + b"real"
        for path in ROOT.rglob("*"):
            if path.is_file() and ".git" not in path.parts and "__pycache__" not in path.parts:
                source = path.read_bytes()
                self.assertNotIn(forbidden, source, str(path))


if __name__ == "__main__":
    unittest.main()

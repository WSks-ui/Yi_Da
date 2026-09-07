import io
import json
import unittest
from zipfile import ZipFile

from scripts.check_hap import check_hap


def fixture(change=None, extra=None):
    manifest = {
        "app": {
            "bundleName": "com.chr.Yi_Da", "compileSdkVersion": "26.0.0.105",
            "minAPIVersion": 260000026, "targetAPIVersion": 260000026,
        },
        "module": {
            "name": "entry", "abilities": [{"name": "EntryAbility"}],
            "extensionAbilities": [{"name": "EntryBackupAbility"}],
        },
    }
    if change:
        change(manifest)
    entries = {
        "module.json": json.dumps(manifest),
        "resources/base/profile/backup_config.json": '{"allowToBackupRestore":false}',
        "ets/modules.abc": b"production-bytecode-fixture",
        "resources/rawfile/demo/NOTICE.txt": "fixture attribution",
    }
    entries.update(extra or {})
    data = io.BytesIO()
    with ZipFile(data, "w") as hap:
        for name, content in entries.items():
            hap.writestr(name, content)
    data.seek(0)
    return data


class HapBoundaryTest(unittest.TestCase):
    def test_current_boundary_is_allowed(self):
        self.assertEqual(check_hap(fixture()), ("26.0.0.105", 4))

    def test_test_ability_is_rejected(self):
        with self.assertRaises(ValueError):
            check_hap(fixture(lambda m: m["module"]["abilities"].append({"name": "MediaFixtureAbility"})))

    def test_code_resources_and_source_maps_cannot_leak_test_entry(self):
        for path, content in (
            ("ets/modules.abc", b"\x00FixtureGalleryWriter\x00"),
            ("ets/sourceMaps.map", '{"source":"entry/src/ohosTest/ets/fixtures/MediaFixtureAbility.ets"}'),
            ("resources/base/profile/fixture_pages.json", "{}"),
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                check_hap(fixture(extra={path: content}))

    def test_new_permissions_require_review(self):
        for name in ("ohos.permission.READ_IMAGEVIDEO", "ohos.permission.WRITE_IMAGEVIDEO"):
            with self.subTest(permission=name), self.assertRaises(ValueError):
                check_hap(fixture(lambda m: m["module"].update(requestPermissions=[{"name": name}])))

    def test_api_downgrade_is_rejected(self):
        for field in ("minAPIVersion", "targetAPIVersion", "compileSdkVersion"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                check_hap(fixture(lambda m: m["app"].update({field: "6.1.0" if field == "compileSdkVersion" else 23})))

    def test_enabled_backup_is_rejected(self):
        with self.assertRaises(ValueError):
            check_hap(fixture(extra={"resources/base/profile/backup_config.json": '{"allowToBackupRestore":true}'}))

    def test_test_module_or_missing_code_is_rejected(self):
        with self.assertRaises(ValueError):
            check_hap(fixture(lambda m: m["module"].update(name="entry_test")))
        with self.assertRaises(ValueError):
            check_hap(fixture(extra={"ets/modules.abc": b""}))


if __name__ == "__main__":
    unittest.main()

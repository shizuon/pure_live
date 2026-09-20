import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_unsigned_ipa", Path(__file__).parents[1] / "tool/verify_unsigned_ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IpaPackagingTest(unittest.TestCase):
    def make(self, path, *, platform="iPhoneOS", missing=None):
        prefix = "Payload/Runner.app/"
        members = {
            "Runner": b"app",
            "Frameworks/Flutter.framework/Flutter": b"flutter",
            "Frameworks/App.framework/App": b"aot",
            "Frameworks/App.framework/flutter_assets/AssetManifest.bin": b"assets",
            "Info.plist": plistlib.dumps(dict(CFBundleExecutable="Runner", CFBundleIdentifier="test.app",
                CFBundleShortVersionString="3.0.22", CFBundleVersion="4110", CFBundleSupportedPlatforms=[platform])),
        }
        with zipfile.ZipFile(path, "w") as archive:
            for name, value in members.items():
                if name != missing:
                    archive.writestr(prefix + name, value)

    def test_device_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ipa"
            self.make(path)
            module.verify(path)

    def test_reject_simulator_and_missing_aot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.ipa"
            self.make(path, platform="iPhoneSimulator")
            with self.assertRaisesRegex(ValueError, "device build"):
                module.verify(path)
            self.make(path, missing="Frameworks/App.framework/App")
            with self.assertRaisesRegex(ValueError, "Missing or empty"):
                module.verify(path)


if __name__ == "__main__":
    unittest.main()

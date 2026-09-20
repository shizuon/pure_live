import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_unsigned_ipa", Path(__file__).parents[1] / "tool/verify_unsigned_ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IpaPackagingTest(unittest.TestCase):
    arm64 = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 2, 0, 0, 0, 0)

    def make(self, path, *, platform="iPhoneOS", missing=None):
        prefix = "Payload/Runner.app/"
        members = {
            "Runner": self.arm64,
            "Frameworks/Flutter.framework/Flutter": self.arm64,
            "Frameworks/App.framework/App": self.arm64,
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

    def test_architecture_and_fat_slice_bounds(self):
        fat = struct.pack('>7I', 0xCAFEBABE, 1, 0x0100000C, 0, 28, 32, 0) + self.arm64
        module.verify_arm64(fat, 'fat fixture')
        x64 = struct.pack('<8I', 0xFEEDFACF, 0x01000007, 0, 2, 0, 0, 0, 0)
        for invalid in [x64, b'not a binary', fat[:-1], fat[:28] + x64]:
            with self.assertRaises(ValueError):
                module.verify_arm64(invalid, 'invalid fixture')


if __name__ == "__main__":
    unittest.main()

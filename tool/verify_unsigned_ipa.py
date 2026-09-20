"""Validate the device app payload before handing an IPA to a signing tool.

This verifies packaging, not Apple signing, provisioning or device playback.
"""
import plistlib
import sys
import zipfile
from pathlib import PurePosixPath


def verify(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA ZIP member")
        names = set(archive.namelist())
        prefix = "Payload/Runner.app/"
        if any(PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts for name in names):
            raise ValueError("Unsafe archive member path")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        executable = info.get("CFBundleExecutable", "")
        if not executable or PurePosixPath(executable).name != executable:
            raise ValueError("Missing or invalid app executable name")
        for member in [prefix + executable, prefix + "Frameworks/Flutter.framework/Flutter",
                       prefix + "Frameworks/App.framework/App"]:
            if member not in names or archive.getinfo(member).file_size == 0:
                raise ValueError(f"Missing or empty binary: {member}")
        if not any(name.startswith(prefix + "Frameworks/App.framework/flutter_assets/") for name in names):
            raise ValueError("Missing Flutter assets")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("IPA is not an iPhoneOS device build")
        for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]:
            if not info.get(key):
                raise ValueError(f"Missing {key}")
        print(f"Device IPA payload OK: {info['CFBundleIdentifier']} "
              f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}); requires user signing")


if __name__ == "__main__":
    verify(sys.argv[1])

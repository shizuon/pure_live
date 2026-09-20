"""Validate the device app payload before handing an IPA to a signing tool.

This verifies packaging, not Apple signing, provisioning or device playback.
"""
import plistlib
import struct
import sys
import zipfile
from pathlib import PurePosixPath


def verify_arm64(data, label):
    """Check Mach-O architecture, including universal binaries, without Xcode."""
    if len(data) < 32:
        raise ValueError(f"Truncated Mach-O: {label}")
    magic = data[:4]
    if magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
        endian = '<' if magic == b'\xcf\xfa\xed\xfe' else '>'
        cpu = struct.unpack_from(endian + 'I', data, 4)[0]
        if cpu != 0x0100000C:
            raise ValueError(f"Missing arm64 Mach-O: {label}")
        return
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
                 b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'):
        endian = '>' if magic[:2] == b'\xca\xfe' else '<'
        wide = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        size = 32 if wide else 20
        if count > (len(data) - 8) // size:
            raise ValueError(f"Truncated Mach-O architecture table: {label}")
        for index in range(count):
            entry = 8 + index * size
            cpu = struct.unpack_from(endian + 'I', data, entry)[0]
            if cpu == 0x0100000C:
                offset, length = struct.unpack_from(endian + ('QQ' if wide else 'II'), data, entry + 8)
                if offset < 8 + count * size or length < 32 or offset + length > len(data):
                    raise ValueError(f"Invalid arm64 Mach-O slice: {label}")
                # A fat table claiming arm64 must contain an actual thin arm64 slice.
                if data[offset:offset + 4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
                    raise ValueError(f"Invalid arm64 Mach-O slice: {label}")
                verify_arm64(data[offset:offset + length], label)
                return
    raise ValueError(f"Missing arm64 Mach-O: {label}")


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
            verify_arm64(archive.read(member), member)
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

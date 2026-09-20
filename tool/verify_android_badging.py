"""Verify aapt metadata for this workflow's Flutter split-per-ABI APK."""
import pathlib
import re
import sys


def verify(badging, version, abi='arm64-v8a'):
    name, build = version.split('+')
    # Flutter 3.47 FlutterPluginConstants.ABI_VERSION / versionCodeOverride.
    # The workflow uses --split-per-abi without forceVersionCodeIgnoringAbi.
    expected_code = int(build) + {'armeabi-v7a': 1000, 'arm64-v8a': 2000, 'x86_64': 4000}[abi]
    package = re.search(r'^package: (.*)$', badging, re.M)
    fields = dict(re.findall(r"(\w+)='([^']*)'", package.group(1))) if package else {}
    if fields.get('name') != 'com.mystyle.purelive':
        raise ValueError('Wrong Android package')
    if fields.get('versionCode') != str(expected_code) or fields.get('versionName') != name:
        raise ValueError(f"Wrong Android version: {fields.get('versionName')}+{fields.get('versionCode')}; "
                         f"expected {name}+{expected_code} (Flutter build {build})")
    native = re.search(r'^native-code:\s*(.*)$', badging, re.M)
    if native is None or re.findall(r"'([^']*)'", native.group(1)) != [abi]:
        raise ValueError('Wrong Android ABI set')
    print(f'Android manifest verified: {name}, versionCode={expected_code}, Flutter build={build}, {abi}')


if __name__ == '__main__':
    version = re.search(r'^version:\s*(\S+)', pathlib.Path('pubspec.yaml').read_text(), re.M).group(1)
    verify(pathlib.Path(sys.argv[1]).read_text(), version)

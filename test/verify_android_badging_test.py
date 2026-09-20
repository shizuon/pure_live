import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('badging', Path(__file__).parents[1] / 'tool/verify_android_badging.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BadgingTest(unittest.TestCase):
    good = "package: name='com.mystyle.purelive' versionCode='6110' versionName='3.0.22'\nnative-code: 'arm64-v8a'\n"

    def test_flutter_arm64_split_code(self):
        module.verify(self.good, '3.0.22+4110')

    def test_reject_wrong_build_package_or_abi(self):
        for text in [self.good.replace('6110', '4110'), self.good.replace('6110', '6109'),
                     self.good.replace('3.0.22', '3.0.21'), self.good.replace('com.mystyle.purelive', 'other.app'),
                     self.good.replace("'arm64-v8a'", "'arm64-v8a' 'x86_64'"), '']:
            with self.subTest(badging=text), self.assertRaises(ValueError):
                module.verify(text, '3.0.22+4110')


if __name__ == '__main__':
    unittest.main()

"""Use fake hdiutil; no mounting, building or actual sleep."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "tool/verify_dmg.sh"

class DmgRetryTest(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            fake = base / "hdiutil"
            fake.write_text("""#!/bin/sh
count=0
if [ -f "$COUNT_FILE" ]; then count=$(cat "$COUNT_FILE"); fi
count=$((count + 1))
echo "$count" > "$COUNT_FILE"
if [ "$MODE" = "transient" ] && [ "$count" = "3" ]; then echo VALID; exit 0; fi
if [ "$MODE" = "corrupt" ]; then echo "checksum failed" >&2; exit 1; fi
echo "Resource temporarily unavailable" >&2
exit 1
""")
            fake.chmod(0o755)
            (base / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (base / "sleep").chmod(0o755)
            env = dict(os.environ, PATH=f"{base}:{os.environ['PATH']}", MODE=mode, COUNT_FILE=str(base/"count"))
            result = subprocess.run(["bash", str(SCRIPT), "fixture.dmg"], env=env, capture_output=True)
            return result.returncode, int((base/"count").read_text())

    def test_transient_contention_eventually_passes(self):
        self.assertEqual(self.run_case("transient"), (0, 3))
    def test_real_corruption_fails_without_retry(self):
        self.assertEqual(self.run_case("corrupt"), (1, 1))
    def test_contention_remains_bounded(self):
        self.assertEqual(self.run_case("busy"), (1, 3))

if __name__ == "__main__":
    unittest.main()

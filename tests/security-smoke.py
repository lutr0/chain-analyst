#!/usr/bin/env python3
"""Exercise public CLIs with a local transport fixture; no keys or network needed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


class SecuritySmoke(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="chain-analyst-security-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.skill = self.work / "skill"
        shutil.copytree(ROOT / "scripts", self.skill / "scripts")
        shutil.copyfile(ROOT / "helpers.sh", self.skill / "helpers.sh")
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.response = self.work / "response.json"
        self.capture = self.work / "requests"
        self.env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(self.work),
            "TMPDIR": str(self.work),
            "HYPERSYNC_API_TOKEN": "test-token-not-a-secret",
            "ETHERSCAN_API_KEY": "test-key-not-a-secret",
        }
        self.executable(self.bin / "curl", f'''#!{BASH}
printf '%s\\n' "$@" >> '{self.capture}'
cat '{self.response}'
''')
        (self.work / "query.json").write_text('{"from_block":0}')
        self.response.write_text('{"data":[],"archive_height":1,"next_block":1}')

    def executable(self, path, content):
        path.write_text(content)
        path.chmod(0o700)

    def run_cli(self, script, *args):
        return subprocess.run(
            [BASH, str(self.skill / "scripts" / script), *args],
            cwd=self.work, env=self.env, capture_output=True, text=True, timeout=15,
        )

    def test_env_cannot_replace_executables(self):
        poison = self.work / "poison"
        poison.mkdir()
        marker = self.work / "executed"
        self.executable(poison / "curl", f'''#!{BASH}
touch '{marker}'
cat '{self.response}'
''')
        (self.work / ".env").write_text(f"PATH={poison}:{self.env['PATH']}\n")
        self.response.write_text('{"ethereum":{"usd":42}}')
        result = self.run_cli("get-token-price.sh", "ethereum")
        self.assertFalse(marker.exists(), "workspace env replaced the curl executable")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"usd": 42})

    def test_network_cannot_redirect_credentials(self):
        result = self.run_cli("hypersync-query.sh", "attacker.invalid/path", "query.json", "1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists(), "invalid network reached the transport")

    def test_page_limit_is_not_a_shell_expression(self):
        marker = self.work / "arithmetic-executed"
        expression = f"BASH_VERSINFO[$(touch {marker})]"
        result = self.run_cli("hypersync-query.sh", "base", "query.json", expression)
        self.assertFalse(marker.exists(), "page limit evaluated a shell expression")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())

    def test_provider_cursor_is_not_a_shell_expression(self):
        marker = self.work / "cursor-executed"
        self.response.write_text(json.dumps({
            "data": [{"blocks": [{"number": 0}]}],
            "archive_height": 100,
            "next_block": f"BASH_VERSINFO[$(touch {marker})]",
        }))
        result = self.run_cli("hypersync-query.sh", "base", "query.json", "1")
        self.assertFalse(marker.exists(), "provider cursor evaluated a shell expression")
        self.assertNotEqual(result.returncode, 0)

    def test_provider_address_cannot_remove_files(self):
        victim = self.work / "keep.json"
        victim.write_text("keep this evidence")
        self.response.write_text(json.dumps({
            "data": [{"transactions": [{"to": "../keep"}]}], "archive_height": 1,
        }))
        result = self.run_cli("analyze-tx.sh", "0x" + "a" * 64, "base")
        self.assertTrue(victim.exists(), "provider address deleted a file outside ABI storage")
        self.assertEqual(victim.read_text(), "keep this evidence")
        self.assertNotEqual(result.returncode, 0)

    def test_valid_pagination_and_env_precedence(self):
        (self.work / ".env").write_text("HYPERSYNC_API_TOKEN=workspace-token\n")
        (self.work / ".env.local").write_text("HYPERSYNC_API_TOKEN='local-token'\n")
        self.response.write_text(json.dumps({
            "data": [{"blocks": [{"number": 7}]}], "archive_height": 8, "next_block": 8,
        }))
        result = self.run_cli("hypersync-query.sh", "BASE", "query.json", "1", "aggregate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["data"], [{"blocks": [{"number": 7}]}])
        request = self.capture.read_text()
        self.assertIn("https://base.hypersync.xyz/query", request)
        self.assertIn("Authorization: Bearer local-token", request)

    def test_routing_uses_probability_not_confidence(self):
        self.env["TYPESAFE_API_KEY"] = "test-key-not-a-secret"
        (self.work / "request.json").write_text(json.dumps({
            "request": "Review the lending protocol source and test its invariants.",
        }))
        cases = [
            (0.77, {"audit": 0.83, "lookup": 0.08, "analysis": 0.06, "clarify": 0.03}, "audit"),
            (1.0, {"audit": 0.55, "lookup": 0.15, "analysis": 0.25, "clarify": 0.05}, "clarify"),
        ]
        for confidence, probabilities, expected in cases:
            with self.subTest(expected=expected):
                self.response.write_text(json.dumps({"answers": {"route": {
                    "type": "choice", "choice": "audit",
                    "confidence": confidence, "probabilities": probabilities,
                }}}))
                result = self.run_cli("route-request.sh", "--jev", "request.json")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["mode"], expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)

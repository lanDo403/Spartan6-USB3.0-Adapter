from __future__ import print_function

import os
import shutil
import sys
import tempfile
import unittest


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import run_tb


class RunTbTests(unittest.TestCase):
    def test_full_commands_use_only_full_entrypoint(self):
        repo_root = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
        config = run_tb.make_run_config(repo_root, False)
        commands = run_tb.build_commands(r"C:\Vivado\bin", repo_root, config, "123")
        joined = "\n".join(" ".join(cmd) for cmd in commands)

        self.assertIn(os.path.join(repo_root, "tb", "testbench.sv"), joined)
        self.assertNotIn("testbench_" + "main", joined)
        self.assertNotIn("testbench_" + "requirements", joined)
        self.assertNotIn("-cc_type", joined)
        self.assertIn("--sv_seed 123", joined)

    def test_code_coverage_command_adds_xelab_cc_type(self):
        repo_root = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
        config = run_tb.make_run_config(repo_root, True)
        commands = run_tb.build_commands(r"C:\Vivado\bin", repo_root, config, "random")
        xelab_cmd = commands[1]

        self.assertIn("-cc_type", xelab_cmd)
        self.assertIn("sbct", xelab_cmd)

    def test_validate_xsim_log_text(self):
        good_log = "TEST PASSED\nCOVERAGE SUMMARY END missing_bins=0\n"
        bad_log = "TEST PASSED\nERROR: SVA something\nCOVERAGE SUMMARY END missing_bins=1\n"

        self.assertEqual([], run_tb.validate_xsim_log_text(good_log))
        errors = run_tb.validate_xsim_log_text(bad_log)
        self.assertTrue(any("ERROR: SVA" in item for item in errors))
        self.assertTrue(any("missing_bins=0" in item for item in errors))

    def test_clean_safety_detects_outside_tmp(self):
        tmp_root = tempfile.mkdtemp()
        outside_root = tempfile.mkdtemp()
        try:
            self.assertTrue(run_tb.is_inside(os.path.join(tmp_root, "run"), tmp_root))
            self.assertFalse(run_tb.is_inside(outside_root, tmp_root))
        finally:
            shutil.rmtree(tmp_root)
            shutil.rmtree(outside_root)

    def test_menu_continues_after_action_until_exit(self):
        class Args(object):
            vivado = r"C:\Vivado\bin"
            seed = "random"
            keep = False

        choices = ["3", "0"]
        calls = []
        old_input = getattr(run_tb, "input", None)
        old_open_latest_log = run_tb.open_latest_log

        def fake_input(_prompt):
            return choices.pop(0)

        def fake_open_latest_log(repo_root):
            calls.append(repo_root)
            return 7

        try:
            run_tb.input = fake_input
            run_tb.open_latest_log = fake_open_latest_log

            rc = run_tb.show_menu("repo", Args())

            self.assertEqual(0, rc)
            self.assertEqual(["repo"], calls)
            self.assertEqual([], choices)
        finally:
            if old_input is None:
                del run_tb.input
            else:
                run_tb.input = old_input
            run_tb.open_latest_log = old_open_latest_log


if __name__ == "__main__":
    unittest.main()

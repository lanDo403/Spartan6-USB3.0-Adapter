from __future__ import print_function

import argparse
import os
import shutil
import subprocess
import sys


DEFAULT_VIVADO_BIN = r"C:\AMDDesignTools\2025.2\Vivado\bin"
FULL_RUN_DIR_NAME = "vivado_xsim_tb_full"
CODE_COV_RUN_DIR_NAME = "vivado_xsim_tb_full_cov"


def repo_root_from_script():
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))


def make_run_config(repo_root, code_coverage):
    run_name = CODE_COV_RUN_DIR_NAME if code_coverage else FULL_RUN_DIR_NAME
    snapshot = "tb_full_cov" if code_coverage else "tb_full"
    return {
        "code_coverage": code_coverage,
        "entry": os.path.join(repo_root, "tb", "testbench.sv"),
        "run_dir": os.path.join(repo_root, "tmp", run_name),
        "snapshot": snapshot,
    }


def vivado_tool(vivado_bin, tool_name):
    return os.path.join(vivado_bin, tool_name + ".bat")


def build_commands(vivado_bin, repo_root, config, seed):
    xelab_cmd = [
        vivado_tool(vivado_bin, "xelab"),
        "testbench",
        "-debug",
        "typical",
        "-s",
        config["snapshot"],
        "-cov_db_dir",
        "xsim_cov",
        "-cov_db_name",
        "full",
    ]
    if config["code_coverage"]:
        xelab_cmd.extend(["-cc_type", "sbct"])

    return [
        [
            vivado_tool(vivado_bin, "xvlog"),
            "-sv",
            "-d",
            "TB_HAS_SV_COVERGROUP",
            "-i",
            os.path.join(repo_root, "tb"),
            "-i",
            os.path.join(repo_root, "rtl"),
            config["entry"],
        ],
        xelab_cmd,
        [
            vivado_tool(vivado_bin, "xsim"),
            config["snapshot"],
            "--sv_seed",
            str(seed),
            "-runall",
        ],
        [
            vivado_tool(vivado_bin, "xcrg"),
            "-dir",
            "xsim_cov",
            "-cov_db_name",
            "full",
        ],
    ]


def normalized_path(path):
    return os.path.normcase(os.path.realpath(os.path.abspath(path)))


def is_inside(path, parent):
    path_n = normalized_path(path)
    parent_n = normalized_path(parent)
    return path_n == parent_n or path_n.startswith(parent_n + os.sep)


def safe_rmtree(path, tmp_root):
    if not is_inside(path, tmp_root):
        raise RuntimeError("Refusing to remove path outside tmp: " + path)
    if os.path.isdir(path):
        shutil.rmtree(path)


def ensure_dir(path):
    if not os.path.isdir(path):
        os.makedirs(path)


def prepare_run_dir(repo_root, config, keep):
    tmp_root = os.path.join(repo_root, "tmp")
    ensure_dir(tmp_root)

    if os.path.exists(config["run_dir"]) and not keep:
        safe_rmtree(config["run_dir"], tmp_root)

    ensure_dir(config["run_dir"])

    data_p_src = os.path.join(repo_root, "rtl", "data_p")
    if not os.path.isfile(data_p_src):
        raise RuntimeError("Missing required file: " + data_p_src)
    shutil.copy2(data_p_src, os.path.join(config["run_dir"], "data_p"))


def missing_vivado_tools(vivado_bin):
    missing = []
    for tool_name in ("xvlog", "xelab", "xsim", "xcrg"):
        path = vivado_tool(vivado_bin, tool_name)
        if not os.path.isfile(path):
            missing.append(path)
    return missing


def quote_arg(arg):
    if " " in arg or "\t" in arg:
        return '"' + arg + '"'
    return arg


def format_command(command):
    return " ".join(quote_arg(str(arg)) for arg in command)


def run_command(command, cwd):
    print("")
    print("RUN: " + format_command(command))
    sys.stdout.flush()
    return subprocess.call(command, cwd=cwd)


def validate_xsim_log_text(log_text):
    errors = []
    if "TEST PASSED" not in log_text:
        errors.append("TEST PASSED marker not found")
    if "TEST FAILED" in log_text:
        errors.append("TEST FAILED marker found")
    if "ERROR: SVA" in log_text:
        errors.append("ERROR: SVA marker found")
    if "COVERAGE SUMMARY END missing_bins=0" not in log_text:
        errors.append("COVERAGE SUMMARY END missing_bins=0 marker not found")
    return errors


def validate_xsim_log_file(log_path):
    if not os.path.isfile(log_path):
        return ["xsim.log not found: " + log_path]
    with open(log_path, "r") as log_file:
        return validate_xsim_log_text(log_file.read())


def run_full_regression(repo_root, vivado_bin, seed, keep, code_coverage):
    missing = missing_vivado_tools(vivado_bin)
    if missing:
        print("ERROR: Vivado tools not found:")
        for path in missing:
            print("  " + path)
        return 2

    config = make_run_config(repo_root, code_coverage)
    try:
        prepare_run_dir(repo_root, config, keep)
    except RuntimeError as error:
        print("ERROR: " + str(error))
        return 2

    for command in build_commands(vivado_bin, repo_root, config, seed):
        rc = run_command(command, config["run_dir"])
        if rc != 0:
            print("ERROR: command failed with exit code " + str(rc))
            return rc

    log_path = os.path.join(config["run_dir"], "xsim.log")
    errors = validate_xsim_log_file(log_path)
    if errors:
        print("ERROR: xsim.log validation failed:")
        for error in errors:
            print("  " + error)
        return 1

    print("")
    print("PASS: full regression passed")
    print("LOG:  " + log_path)
    return 0


def runner_dirs(repo_root):
    return [
        make_run_config(repo_root, False)["run_dir"],
        make_run_config(repo_root, True)["run_dir"],
    ]


def find_latest_log(repo_root):
    logs = []
    for run_dir in runner_dirs(repo_root):
        log_path = os.path.join(run_dir, "xsim.log")
        if os.path.isfile(log_path):
            logs.append((os.path.getmtime(log_path), log_path))
    if not logs:
        return None
    logs.sort()
    return logs[-1][1]


def open_latest_log(repo_root):
    log_path = find_latest_log(repo_root)
    if log_path is None:
        print("ERROR: no xsim.log found in runner tmp directories")
        return 1

    print("LOG: " + log_path)
    if hasattr(os, "startfile"):
        os.startfile(log_path)
    return 0


def clean_runner_dirs(repo_root):
    tmp_root = os.path.join(repo_root, "tmp")
    removed = 0
    for run_dir in runner_dirs(repo_root):
        if os.path.isdir(run_dir):
            safe_rmtree(run_dir, tmp_root)
            print("Removed: " + run_dir)
            removed += 1
    if removed == 0:
        print("Nothing to clean")
    return 0


def show_menu(repo_root, args):
    while True:
        print("")
        print("Vivado XSim Testbench Runner")
        print("1. Run full regression")
        print("2. Run full regression + code coverage")
        print("3. Open last xsim.log")
        print("4. Clean simulation tmp directories")
        print("0. Exit")
        choice = input("Select: ").strip()

        if choice == "1":
            return run_full_regression(repo_root, args.vivado, args.seed, args.keep, False)
        if choice == "2":
            return run_full_regression(repo_root, args.vivado, args.seed, args.keep, True)
        if choice == "3":
            return open_latest_log(repo_root)
        if choice == "4":
            return clean_runner_dirs(repo_root)
        if choice == "0":
            return 0

        print("Unknown menu item: " + choice)


def build_parser():
    parser = argparse.ArgumentParser(description="Run the Vivado XSim SystemVerilog testbench.")
    parser.add_argument(
        "command",
        nargs="?",
        help="Command: full, full-cov, log, clean, menu",
    )
    parser.add_argument(
        "--vivado",
        default=os.environ.get("VIVADO_BIN", DEFAULT_VIVADO_BIN),
        help="Path to Vivado bin directory. Default: %(default)s",
    )
    parser.add_argument(
        "--seed",
        default="random",
        help="XSim SystemVerilog seed. Use 'random' or a number. Default: %(default)s",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Do not remove the selected run directory before starting.",
    )
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    repo_root = repo_root_from_script()
    command = args.command

    if command is None or command == "menu":
        return show_menu(repo_root, args)
    if command == "full":
        return run_full_regression(repo_root, args.vivado, args.seed, args.keep, False)
    if command in ("full-cov", "cov", "coverage"):
        return run_full_regression(repo_root, args.vivado, args.seed, args.keep, True)
    if command == "log":
        return open_latest_log(repo_root)
    if command == "clean":
        return clean_runner_dirs(repo_root)

    parser.print_help()
    print("")
    print("ERROR: unknown command: " + command)
    return 2


if __name__ == "__main__":
    sys.exit(main())

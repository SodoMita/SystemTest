#!/usr/bin/env python3
"""
tests/run_lua51.py — run a Lua script under a real Lua 5.1 runtime.

The repo's headless tests (tests/smoke_test.lua) are written for lua5.1.
Where a system lua5.1 interpreter is unavailable, this driver runs them
inside lupa's embedded Lua 5.1 runtime with the repo root as cwd.

os.exit() is intercepted so the process returns the script's exit code
instead of terminating the interpreter directly.

Usage: python3 tests/run_lua51.py tests/smoke_test.lua
"""
import sys
from pathlib import Path

import lupa.lua51


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: run_lua51.py <script.lua> [args...]", file=sys.stderr)
        return 2

    repo = Path(__file__).resolve().parents[1]
    script = Path(sys.argv[1]).resolve()
    if not script.exists():
        print(f"error: {script} not found", file=sys.stderr)
        return 2

    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals()["package"].path = f"{repo}/?.lua;{repo}/?/init.lua;"
    # Neutralize os.exit so the exit code is delivered instead of the
    # interpreter (and the host process) dying immediately.
    lua.execute(
        """
        local _orig_exit = os.exit
        EXIT_CODE = 0
        os.exit = function(code)
            EXIT_CODE = tonumber(code) or 0
            error("__script_exit__", 0)
        end
        """
    )

    args = lua.table_from([str(script)] + sys.argv[2:])
    lua.globals()["arg"] = args

    try:
        lua.execute(f'return dofile("{script.as_posix()}")')
    except lupa.LuaError as e:
        if "__script_exit__" not in str(e):
            print(str(e), file=sys.stderr)
            return 1
    code = lua.globals()["EXIT_CODE"]
    return int(code)


if __name__ == "__main__":
    sys.exit(main())

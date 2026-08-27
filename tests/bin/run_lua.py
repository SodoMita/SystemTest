#!/usr/bin/env python3
"""Tiny dev runner: executes a Lua script (default: the headless stub smoke
test) inside lupa's embedded Lua, shimming the few Lua 5.1 builtins the stub
uses. CI uses luajit directly; this is only for sandboxed/local runs."""
import sys, os, lupa

script = sys.argv[1] if len(sys.argv) > 1 else "tests/smoke_test.lua"
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(root)

L = lupa.LuaRuntime(unpack_returned_tuples=False)
L.execute("loadstring = load; unpack = table.unpack")
L.execute("dofile(%s)" % repr(os.path.join(".", script)))

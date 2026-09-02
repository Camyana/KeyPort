"""Run KeyPort's test suite outside the game.

    python tools/run_tests.py

Loads tools/wow_stubs.lua, then the real Libs and KeyPort.lua, then
tools/test_keyport.lua, in a Lua interpreter (lupa). Exits non-zero on the
first failed check, so it works as a pre-release gate.

    pip install lupa
"""

import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is not installed. Run: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")


def lua_path(*parts):
    """Lua wants forward slashes, even on Windows."""
    return os.path.join(ROOT, *parts).replace("\\", "/")


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ADDON = lua_path("") + "/"
    g.LIBS = lua_path("Libs") + "/"

    for name in ("wow_stubs.lua", "test_keyport.lua"):
        path = os.path.join(TOOLS, name)
        if name == "test_keyport.lua":
            # the suite loads the addon itself, using ADDON and LIBS above
            pass
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        try:
            lua.execute(source)
        except Exception as error:          # noqa: BLE001 - report and stop
            print("\nFAILED in %s:\n  %s" % (name, error))
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

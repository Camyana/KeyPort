# Tests

    pip install lupa
    python tools/run_tests.py

`wow_stubs.lua` is a small stand-in for the game: frames that record what was
set on them, plus the APIs KeyPort calls, shaped the way the real ones are.
`test_keyport.lua` loads the real `KeyPort.lua` and the real LibKeystone against
those stubs and drives the addon the way the game would, by firing events,
clicking rows and typing slash commands.

Every bug that has been fixed once has a test here, marked with the version it
was fixed in, so it cannot come back quietly. Run it before tagging a release:
it exits non-zero on the first failed check.

The stubs are deliberately faithful rather than convenient. `GetText` returns a
string even when `SetText` was handed a number, `Ambiguate` respects its mode
argument, and `GetSearchResultInfo` returns the same table shape the client
does, because a stub that is wrong in shape hides the bug it was meant to catch.

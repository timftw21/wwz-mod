# wwz-mod

wwz-mod is a zombies-focused fork of s2x-mod, a Windows x64 C++ client
for Call of Duty: WWII. Its focus is tweaks, bug fixes, and gameplay additions.

## Game and research

- Installation: `D:\Steam\steamapps\common\Call of Duty WWII`.
- Only multiplayer and zombies are installed; campaign is absent.
- Zombies uses the multiplayer binary (`s2_mp64_ship.exe`).
- GSC research: `D:\wwz-research`; sources: `output\catalog-s2`.
- GrayWolf 0.8.0 and the pinned Brentdevent/gsc-tool fork extracted all 268
  fastfiles: 2,092 GSC entries, representing 1,358 distinct named versions.
- Local parser fixes handle array-literal indexing and assignments through
  call-returned fields; patch: `source\gsc-tool-s2-local.patch` in research.
- All 1,358 versions pass syntax checks. Both previously failing scripts
  compile, and their relevant instructions match the original bytecode.
- Consult the research `README.md`, `scripts.csv`, `coverage.csv`, and
  `tool-versions.json`/`validation.json` for provenance, variants, and checks.
- Some names remain numeric or inferred; runtime behavior is unverified.
- Lua/UI research: `D:\wwz-research\lua`; sources: `catalog\scripts`.
  Includes zombies front-end, intro/movie/onboarding menus and shared LUI code.
- All 268 fastfiles yielded 2,492 Lua entries: 2,052 unique bodies under
  2,066 logical paths. All pass syntax and omitted-code checks; 18 isolated
  behavior cases pass. Installed fastfile hashes remain unchanged.
- Local CoDLuaDecompiler fixes correct branches, loops, live values and repeated
  expression replacement. See `lua\README.md` and its validation, source/zone
  manifests, zombies index, tool hashes and patches.
- Loading: preserve stock paths under `s2x` or the selected mod root; numeric GSC
  filenames also resolve. Stock Lua loads through Havok before module execution,
  including Zombies menus. Restart LUI after UI edits or mod changes.
- Zombies add-ons use `scripts/mp/zombies`; UI packages remain
  `ui_scripts/mp/<package>/__init__.lua` with mode guards. Replacement-only mods
  are recognized. Select matching zone variants; do not deploy the whole dump.
- Premake applies `deps/patches/gsc-tool-parser.patch` to a generated parser copy;
  keep the pinned submodule clean. Loading details and checks:
  `D:\wwz-research\script-loading.md`, `loading-implementation`.
- Keep tools and game-derived research outside tracked client source.
  Preserve installed game files and original bytecode.

## Development

- Fix root causes with focused, concise changes; avoid unrelated refactoring.
- Follow existing components, hooks, commands, and scheduler patterns.
- Add useful debug logging for every behavior change and its failures;
  avoid per-frame log spam.
- wwz-mod disables upstream automatic client/data and Store-runtime updates;
  keep the shared updater policy disabled in Debug and Release builds.
- Preserve native virtual-lobby capacity; forcing a dvar reset value after
  memory allocation causes error 6 161.
- Verify engine behavior, addresses, signatures, and structure layouts from
  evidence. Preserve calling conventions, original calls, alignment, and packing.
- Check state cleanup, callback lifetimes, packet bounds, response validation,
  mode guards, and compatibility with hosted games and dedicated servers.
- Preserve CRLF in existing source files. Avoid unnecessary tests and documents.
- Do not use subagents or computer use without the user's authorization.
- Keep binary analysis bounded and streaming; never scan whole large binaries
  with Python/Capstone or run memory-intensive analysis in parallel.
- After heavy or timed-out commands, check for surviving child processes and
  stop only processes created by that command before continuing.

## Validation

- Run `git diff --check` before finishing.
- For code/build changes, generate with `tools\premake5.exe vs2022`, then build
  `build\s2x.sln` in Debug x64 and Release x64 when VS components are available.
- Smoke-check affected engine/network behavior when runtime setup is available.
- When changes are ready for manual testing, replace the Steam installation's
  `s2x.exe` with the verified Release build and deploy changed UI/data files.
- Clearly distinguish successful builds from runtime checks and report gaps.

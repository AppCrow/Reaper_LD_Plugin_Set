-- The neutral "LD Tools" build (build-package.sh --neutral): one source, two
-- products. This suite stages the neutral payload the way the real build does
-- (minus dmg/zip and PDFs), checks what came out, and then proves the
-- debranded code still RUNS: it debrands a copy of tests/ next to the staged
-- payload and runs the translated suites against it.
--
--   1. ./build-package.sh stage-neutral <tmp>/LD Tools      (stage + debrand + gate)
--   2. our own checks, independent of the script's gate: no "steelblue" in
--      any text file or name, the expected ld_* files, no logo, no video,
--      the neutral SB.BRAND line exactly once, the install folder "ld-tools",
--      the action "LD Tools", the demo RPP pointing at ld_demo_beat.wav
--   3. copy tests/ into the payload and extensions/Windows next to the staged
--      macOS builds (installer_test reads the Windows DLLs' PE headers), then
--      ./build-package.sh debrand <tmp>/LD Tools
--   4. run the translated suites; each must exit 0
--
-- Not run translated, on purpose:
--   bpm_accuracy/busy/confidence/precision/incremental/timing/item_pick,
--   bpm_* DSP suites   they measure the estimator, which debranding does not
--                      touch, and several need tests/Media (not in git).
--                      bpm_hosts_test IS run: it covers the host wiring.
--   ma3_probe_test     the grandMA3 side; nothing in it is part of the REAPER
--                      package that gets debranded. It is not even copied:
--                      its hook global STEELBLUE_MA3_PROBE_TEST is upper case,
--                      which no mapping covers, so the gate would (rightly)
--                      refuse the tree.
--   everything else    the module suites (markers, matools, boot, rename,
--                      copy_*, midi_lanes, pe_arch) test the same code the
--                      host suites load; the prompt names these eight.
--
-- Mutation checks, done by hand on 2026-10-19 before trusting this suite
-- (each change reverted afterwards):
--   (a) planted "-- steelblue" into the staged ld_ui.lua after debrand (one
--       line added to stage_neutral) -> the script's second gate failed,
--       stage-neutral exited 1 -> RED. Same plant with gate() made a no-op ->
--       this suite's own grep named the file -> RED.
--   (b) a second "SB.BRAND = ..." line in steelblue_ui.lua -> debrand died
--       ("expected exactly one line starting 'SB.BRAND = '") -> RED.
--   (c) removed the "steelblue package" mapping -> GREEN, and correctly so:
--       the catch-all "steelblue" -> "LD Tools" yields the same text
--       ("LD Tools package"); that mapping only documents intent. Removed the
--       catch-all pair instead -> the gate listed every file with a comment
--       left -> RED. Removed the INSTALL_SUBFOLDER mapping -> the gate stayed
--       green (the catch-all made it "LD Tools") but this suite's
--       'INSTALL_SUBFOLDER = "ld-tools"' check -> RED.

local HERE = (arg[0]:match("(.*/)") or "./")

local function sh_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function capture(cmd)
  local p = io.popen(cmd)
  local out = p:read("a")
  p:close()
  return out
end

-- os.execute that also says why: returns ok, output
local function run(cmd)
  local log = os.tmpname()
  local ok = os.execute(cmd .. " >" .. sh_quote(log) .. " 2>&1")
  local f = io.open(log)
  local out = f and f:read("a") or ""
  if f then f:close() end
  os.remove(log)
  return ok == true or ok == 0, out
end

local REPO = capture("cd " .. sh_quote(HERE .. "..") .. " && pwd"):gsub("%s+$", "")
local BUILD = sh_quote(REPO .. "/build-package.sh")
local TMP = capture("mktemp -d"):gsub("%s+$", "")
assert(TMP ~= "", "mktemp -d failed")
local ROOT = TMP .. "/LD Tools"
local INNER = ROOT .. "/LD Tools"

local fails = 0
local function check(cond, what)
  print(string.format("  %s  %s", cond and "PASS" or "FAIL", what))
  if not cond then fails = fails + 1 end
  return cond
end

local function exists(path)
  return os.execute("test -e " .. sh_quote(path)) == true
end

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function finish()
  if os.getenv("KEEP_NEUTRAL") then
    print("\nstaging kept at " .. TMP)
  else
    os.execute("rm -rf " .. sh_quote(TMP))
  end
  print(fails == 0 and "\nALL PASS" or string.format("\nFAILED (%d)", fails))
  os.exit(fails == 0 and 0 or 1)
end

-- 1. stage --------------------------------------------------------------------

print("stage-neutral")
local ok, out = run(BUILD .. " stage-neutral " .. sh_quote(ROOT))
if not check(ok, "build-package.sh stage-neutral exits 0 (stage, debrand, gate)") then
  print(out)
  finish()
end

-- 2. what came out --------------------------------------------------------------

print("\nthe staged payload")
local NOT_TEXT = "--exclude='*.png' --exclude='*.wav' --exclude='*.mp4' --exclude='*.pdf'"
  .. " --exclude='*.dylib' --exclude='*.dll'"
local hits = capture("grep -ril " .. NOT_TEXT .. " steelblue " .. sh_quote(ROOT) .. " || true")
check(hits == "", "no text file says steelblue" .. (hits ~= "" and (":\n" .. hits) or ""))
local names = capture("find " .. sh_quote(ROOT) .. " -iname '*steelblue*'")
check(names == "", "no file or folder name says steelblue" .. (names ~= "" and (":\n" .. names) or ""))

for _, rel in ipairs({
  "ld_install.lua", "ld_ui.lua", "ld_workspace.lua",
  "Tutorials/ld.css", "Tutorials/ld-tools.html",
  "Demo Project/ld_demo.RPP", "Demo Project/ld_demo_beat.wav",
}) do
  check(exists(INNER .. "/" .. rel), "exists: " .. rel)
end
check(exists(ROOT .. "/ld_install.lua"), "exists: the installer on top, next to the note")
check(not exists(INNER .. "/Tutorials/mark.svg"), "absent: Tutorials/mark.svg (the logo)")
check(not exists(INNER .. "/Tutorials/video"), "absent: Tutorials/video (shows the branded UI)")
check(not exists(INNER .. "/Guides (PDF)"), "absent: Guides (PDF) (stage mode renders none)")

local NEUTRAL_BRAND = 'SB.BRAND = { word = "LD Tools", sub = "", sub_bar = "", mark = false }'
local ui = read(INNER .. "/ld_ui.lua") or ""
local brand_lines, neutral_lines = 0, 0
for line in ui:gmatch("[^\n]*") do
  if line:find("^SB%.BRAND = ") then brand_lines = brand_lines + 1 end
  if line == NEUTRAL_BRAND then neutral_lines = neutral_lines + 1 end
end
check(brand_lines == 1 and neutral_lines == 1,
  string.format("ld_ui.lua: the neutral SB.BRAND line exactly once (%d brand, %d neutral)",
    brand_lines, neutral_lines))

local inst = read(INNER .. "/ld_install.lua") or ""
check(inst:find('\nlocal INSTALL_SUBFOLDER = "ld-tools"\n', 1, true) ~= nil,
  'ld_install.lua: INSTALL_SUBFOLDER = "ld-tools"')
check(inst:find('file = "ld_workspace.lua",%s+name = "LD Tools" }') ~= nil,
  'ld_install.lua: the ACTIONS entry name = "LD Tools"')
check(read(ROOT .. "/ld_install.lua") == inst, "the installer on top is the same file")

local rpp = read(INNER .. "/Demo Project/ld_demo.RPP") or ""
check(rpp:find("ld_demo_beat.wav", 1, true) ~= nil, "ld_demo.RPP references ld_demo_beat.wav")
check(rpp:find("steelblue_demo_beat.wav", 1, true) == nil, "ld_demo.RPP: no steelblue_demo_beat.wav")

local note = read(ROOT .. "/READ ME FIRST.txt") or ""
check(note:find("LD Tools — REAPER LD Plugin Set\n===============================\n", 1, true) ~= nil,
  "READ ME FIRST.txt: neutral title, underline as long as the title")
check(note:find("Pick  ld_install.lua", 1, true) ~= nil, "READ ME FIRST.txt names ld_install.lua")

-- 3. a debranded copy of tests/ next to the payload -----------------------------

print("\ndebrand tests/")
ok, out = run("rsync -a --exclude Media --exclude ma3_probe_test.lua --exclude neutral_build_test.lua " .. sh_quote(REPO .. "/tests/") .. " " .. sh_quote(INNER .. "/tests/")
  .. " && cp -R " .. sh_quote(REPO .. "/extensions/Windows") .. " " .. sh_quote(INNER .. "/extensions/"))
if not check(ok, "copy tests/ and extensions/Windows into the staging") then
  print(out)
  finish()
end
ok, out = run(BUILD .. " debrand " .. sh_quote(ROOT))
if not check(ok, "build-package.sh debrand over payload + tests (gate included)") then
  print(out)
  finish()
end

-- 4. the translated suites ------------------------------------------------------

print("\nthe translated suites, against the staged payload")
for _, suite in ipairs({
  "plugin_render_test.lua", "ui_smoke_test.lua", "workspace_test.lua", "installer_test.lua",
  "bpm_hosts_test.lua", "copy_hosts_test.lua", "midi_hosts_test.lua", "rename_hosts_test.lua",
}) do
  ok, out = run("lua " .. sh_quote(INNER .. "/tests/" .. suite))
  if not check(ok, suite) then
    -- the tail is where the suites print what failed
    local lines = {}
    for line in out:gmatch("[^\n]+") do lines[#lines + 1] = line end
    for i = math.max(1, #lines - 25), #lines do print("        " .. lines[i]) end
  end
end

finish()

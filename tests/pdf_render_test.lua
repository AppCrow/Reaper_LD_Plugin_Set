-- The PDF step of the neutral build (build-package.sh render_pdfs / render_one),
-- against a fake Chrome (BUILD_CHROME). The real Chrome is not needed: what is
-- tested is how the build reads Chrome's result.
--
-- Why: under load Chrome writes the PDF, then its shutdown overruns its own
-- teardown watchdog and it exits 2 ("Teardown watchdog expired; recording dump
-- and terminating."). The build used to treat that as a failed render and the
-- whole check chain went red at a random guide (3 of 7 full runs on 2026-10-26
-- to 28). Now the PDF and Chrome's "bytes written to file" line decide.
--
--   a. Chrome ok, exit 0                          -> PDFs kept, exit 0
--   b. PDF written, then watchdog, exit 2         -> PDFs kept, exit 0, a note
--   c. first call dies without a PDF              -> retried, exit 0
--   d. every call dies                            -> exit 1, Chrome's words shown
--   e. exit 0 but no PDF and no "bytes written"   -> exit 1 (exit 0 is not enough)
--
-- Mutation check, done by hand on 2026-10-28: with the success test in
-- render_one changed back to "exit code 0 only", (b) went RED; reverted.
-- BUILD_SCRIPT points the suite at a mutated copy of the script.

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
local BUILD = sh_quote(os.getenv("BUILD_SCRIPT") or (REPO .. "/build-package.sh"))
local TMP = capture("mktemp -d"):gsub("%s+$", "")
assert(TMP ~= "", "mktemp -d failed")

local fails = 0
local function check(cond, what)
  print(string.format("  %s  %s", cond and "PASS" or "FAIL", what))
  if not cond then fails = fails + 1 end
  return cond
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function exists(path)
  return os.execute("test -s " .. sh_quote(path)) == true
end

-- a fake Chrome: $BODY runs after the arguments are parsed into $OUT, $N counts calls
local function fake_chrome(name, body)
  local path = TMP .. "/" .. name
  write(path, [[#!/bin/bash
OUT=""
for a in "$@"; do case "$a" in --print-to-pdf=*) OUT="${a#--print-to-pdf=}";; esac; done
N="$(cat "$0.count" 2>/dev/null || echo 0)"; N=$((N + 1)); echo "$N" >"$0.count"
write_pdf() { printf '%%PDF-1.4 fake\n%%%%EOF\n' >"$OUT"; echo "1234 bytes written to file $OUT"; }
]] .. body)
  os.execute("chmod +x " .. sh_quote(path))
  return path
end

-- two guides with a space in the folder name, like the real package
local function guides(name)
  local inner = TMP .. "/" .. name .. "/LD Tools"
  os.execute("mkdir -p " .. sh_quote(inner .. "/Tutorials"))
  write(inner .. "/Tutorials/one.html", "<html>one</html>")
  write(inner .. "/Tutorials/two.html", "<html>two</html>")
  return inner
end

local function render(chrome, inner)
  return run("BUILD_CHROME=" .. sh_quote(chrome) .. " " .. BUILD .. " render-pdfs " .. sh_quote(inner))
end

print("a. Chrome ok")
do
  local inner = guides("a")
  local ok, out = render(fake_chrome("chrome_a", "write_pdf\nexit 0\n"), inner)
  check(ok, "exit 0")
  check(exists(inner .. "/Guides (PDF)/one.pdf") and exists(inner .. "/Guides (PDF)/two.pdf"), "both PDFs there")
  check(not out:find("note:", 1, true), "no note")
end

print("\nb. PDF written, then the teardown watchdog, exit 2")
do
  local inner = guides("b")
  local body = 'write_pdf\necho "Teardown watchdog expired; recording dump and terminating." >&2\nexit 2\n'
  local ok, out = render(fake_chrome("chrome_b", body), inner)
  check(ok, "exit 0 although Chrome said 2")
  check(exists(inner .. "/Guides (PDF)/one.pdf") and exists(inner .. "/Guides (PDF)/two.pdf"), "both PDFs kept")
  check(out:find("note: Chrome exited 2", 1, true) ~= nil, "a note says so")
end

print("\nc. the first call dies without a PDF")
do
  local inner = guides("c")
  local body = 'if [ "$N" = 1 ]; then echo "renderer crashed" >&2; exit 5; fi\nwrite_pdf\nexit 0\n'
  local ok, out = render(fake_chrome("chrome_c", body), inner)
  check(ok, "exit 0 after a retry")
  check(exists(inner .. "/Guides (PDF)/one.pdf") and exists(inner .. "/Guides (PDF)/two.pdf"), "both PDFs there")
  check(out:find("try 1 of 3", 1, true) ~= nil, "the failed try is named")
end

print("\nd. every call dies")
do
  local inner = guides("d")
  local ok, out = render(fake_chrome("chrome_d", 'echo "renderer crashed" >&2\nexit 5\n'), inner)
  check(not ok, "exit 1")
  check(out:find("Chrome failed to render", 1, true) ~= nil, "the build says what failed")
  check(out:find("renderer crashed", 1, true) ~= nil, "Chrome's own words are shown")
  check(select(2, out:gsub("try %d of 3", "")) == 3, "three tries, no more")
end

print("\ne. exit 0 is not enough")
do
  local inner = guides("e")
  local ok = render(fake_chrome("chrome_e", "exit 0\n"), inner)
  check(not ok, "no PDF, no \"bytes written\": exit 1")
end

os.execute("rm -rf " .. sh_quote(TMP))
print(fails == 0 and "\nALL PASS" or string.format("\nFAILED (%d)", fails))
os.exit(fails == 0 and 0 or 1)

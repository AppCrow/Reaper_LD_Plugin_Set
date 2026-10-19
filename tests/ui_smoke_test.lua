-- Smoke-test the theme module against a fake `reaper` built from the REAL
-- ImGui_* function list of the installed dylib. Catches two classes of bug that
-- otherwise only surface in REAPER:
--   1. mistyped API names (crash on first use)
--   2. unbalanced style stack (grows every frame until ImGui asserts)

local dylib = ((arg[0]:match("(.*/)") or "./").."../").."extensions/macOS/reaper_imgui-arm64.dylib"

local real = {}
local count_real = 0
local p = io.popen(string.format("strings %q | grep -oE '^-API_ImGui_[A-Za-z_0-9]+$'", dylib))
for line in p:lines() do
  real[line:gsub("^-API_", "")] = true
  count_real = count_real + 1
end
p:close()
print(string.format("ReaImGui exposes %d ImGui_* functions", count_real))

local missing = {}
local stack = { colors = 0, vars = 0, fonts = 0, windows = 0 }
-- What the header bands drew: the words, and how many arcs (the logo mark's
-- lens is the only thing in the theme drawn with PathArcTo).
local drawn = { texts = {}, arcs = 0 }

reaper = setmetatable({}, {
  __index = function(_, key)
    if not key:match("^ImGui_") then
      return nil
    end
    if not real[key] then
      missing[key] = true
      return nil
    end

    return function(ctx, ...)
      local a = ...
      if key == "ImGui_DrawList_AddTextEx" then drawn.texts[#drawn.texts + 1] = select(6, ...) end
      if key == "ImGui_DrawList_AddText" then drawn.texts[#drawn.texts + 1] = select(4, ...) end
      if key == "ImGui_DrawList_PathArcTo" then drawn.arcs = drawn.arcs + 1 end
      if key == "ImGui_PushStyleColor" then stack.colors = stack.colors + 1 end
      if key == "ImGui_PopStyleColor" then stack.colors = stack.colors - (a or 1) end
      if key == "ImGui_PushStyleVar" then stack.vars = stack.vars + 1 end
      if key == "ImGui_PopStyleVar" then stack.vars = stack.vars - (a or 1) end
      if key == "ImGui_PushFont" then stack.fonts = stack.fonts + 1 end
      if key == "ImGui_PopFont" then stack.fonts = stack.fonts - 1 end
      -- ReaImGui rule: End is called if and only if Begin returned true. A
      -- collapsed window submits nothing and needs no End, so only count the
      -- windows that actually opened.
      if key == "ImGui_Begin" and WINDOW_VISIBLE then stack.windows = stack.windows + 1 end
      if key == "ImGui_End" then stack.windows = stack.windows - 1 end

      if key == "ImGui_CreateFont" then return "font" end
      if key == "ImGui_CreateContext" then return "ctx" end
      if key == "ImGui_GetWindowDrawList" then return "dl" end
      if key == "ImGui_Begin" then return WINDOW_VISIBLE, true end
      if key == "ImGui_GetCursorScreenPos" then return 100, 100 end
      if key == "ImGui_GetContentRegionAvail" then return 400, 300 end
      if key == "ImGui_CalcTextSize" then return 50, 12 end
      if key:match("^ImGui_Col_") or key:match("^ImGui_StyleVar_") or key:match("^ImGui_Cond_") or key:match("Flags") then
        return 1
      end
      if key == "ImGui_Button" then return false end
      return nil
    end
  end,
})

local folder = ((arg[0]:match("(.*/)") or "./").."../")..""
local SB = dofile(folder .. "steelblue_ui.lua")
print("module loaded, version " .. SB.VERSION)
print(string.format("brand blue #%06X, brand grey #%06X", SB.BRAND_BLUE, SB.BRAND_GREY))

local ctx = "ctx"

local function draw_frame()
  local visible, open, font = SB.begin_window(ctx, "Live BPM Analyzer", 420, 400)
  if visible then
    SB.section(ctx, "Tempo")
    SB.display_value(ctx, "130.99", "BPM")
    SB.meter(ctx, 0.8, 200)
    SB.label(ctx, "Raw: 130.99")
    SB.separator(ctx)
    SB.primary_button(ctx, "Precision analyze", 140, 26)
    SB.button(ctx, "Half", 55, 26)
    SB.footer(ctx, "Precision result from 120 s of audio.", "success")
  end
  SB.end_window(ctx, visible, font)
end

-- 60 frames visible, 60 collapsed, 60 visible again: the collapsed stretch is
-- where an End-in-the-wrong-branch or a missed pop_theme would show up
WINDOW_VISIBLE = true
for _ = 1, 60 do draw_frame() end
print(string.format("\nafter 60 visible frames:   colors=%d vars=%d fonts=%d windows=%d",
  stack.colors, stack.vars, stack.fonts, stack.windows))

WINDOW_VISIBLE = false
for _ = 1, 60 do draw_frame() end
print(string.format("after 60 collapsed frames: colors=%d vars=%d fonts=%d windows=%d",
  stack.colors, stack.vars, stack.fonts, stack.windows))

WINDOW_VISIBLE = true
for _ = 1, 60 do draw_frame() end
print(string.format("after 60 visible again:    colors=%d vars=%d fonts=%d windows=%d",
  stack.colors, stack.vars, stack.fonts, stack.windows))

-- The neutral "LD Tools" package (build-package.sh --neutral) rewrites
-- SB.BRAND to this: no mark, one word, no second line. 30 frames through both
-- header bands, inside the same window, so the stack check below covers them.
local branded = SB.BRAND
local function draw_headers()
  -- begin_window draws SB.header itself; header_bar is the workspace's band
  local visible, open, font = SB.begin_window(ctx, "LD Tools", 420)
  if visible then
    SB.header_bar(ctx, {
      left = function(c) SB.button(c, "Analyze", 60, 22) end,
      right = function(c) SB.label(c, "BPM") end,
    })
  end
  SB.end_window(ctx, visible, font)
end

local neutral_fails = {}
local function neutral_check(cond, what)
  if not cond then neutral_fails[#neutral_fails + 1] = what end
end

-- The module's own table first: whatever it says must be what gets drawn --
-- in the source that is the mark plus word, STUDIOS and LD TOOLS. Written
-- against SB.BRAND rather than the literals so the debranded copy of this
-- suite (tests/neutral_build_test.lua) checks the neutral defaults the same way.
drawn.texts, drawn.arcs = {}, 0
draw_headers()
local expected = { branded.word }
if branded.sub ~= "" then expected[#expected + 1] = branded.sub end
if branded.sub_bar ~= "" then expected[#expected + 1] = branded.sub_bar end
local joined = "|" .. table.concat(drawn.texts, "|") .. "|"
for _, word in ipairs(expected) do
  neutral_check(joined:find("|" .. word .. "|", 1, true), "default header did not draw " .. word)
end
-- the word once per band, plus each non-empty second line
local want_texts = 2 + (branded.sub ~= "" and 1 or 0) + (branded.sub_bar ~= "" and 1 or 0)
neutral_check(#drawn.texts == want_texts,
  "default header drew " .. #drawn.texts .. " texts, expected " .. want_texts)
neutral_check((drawn.arcs > 0) == (branded.mark ~= false),
  "default header: logo mark drawn = " .. tostring(drawn.arcs > 0) .. ", BRAND.mark = " .. tostring(branded.mark))

SB.BRAND = { word = "LD Tools", sub = "", sub_bar = "", mark = false }
drawn.texts, drawn.arcs = {}, 0
for _ = 1, 30 do
  local ok, err = pcall(draw_headers)
  if not ok then
    neutral_check(false, "neutral header raised: " .. tostring(err))
    break
  end
end
neutral_check(drawn.arcs == 0, "neutral header still drew the logo mark")
for _, t in ipairs(drawn.texts) do
  neutral_check(t == "LD Tools", "neutral header drew an unexpected text: " .. tostring(t))
end
neutral_check(#drawn.texts == 60,
  "neutral header drew " .. #drawn.texts .. " texts, expected 60 (one per band per frame)")
SB.BRAND = branded

print(string.format("after 30 neutral-brand frames: colors=%d vars=%d fonts=%d windows=%d",
  stack.colors, stack.vars, stack.fonts, stack.windows))

local fails = 0

if #neutral_fails > 0 then
  print("\nNEUTRAL BRAND:")
  local seen = {}
  for _, f in ipairs(neutral_fails) do
    if not seen[f] then print("   " .. f); seen[f] = true end
  end
  fails = fails + 1
end

local miss_list = {}
for k in pairs(missing) do miss_list[#miss_list + 1] = k end
table.sort(miss_list)
if #miss_list > 0 then
  print("\nMISSING / TYPO'd API NAMES (would crash in REAPER):")
  for _, k in ipairs(miss_list) do print("   " .. k) end
  fails = fails + 1
end

for name, value in pairs(stack) do
  if value ~= 0 then
    print(string.format("\nSTACK LEAK: %s is %+d after 180 frames", name, value))
    fails = fails + 1
  end
end

print(fails == 0 and "\nALL PASS -- no typos, stacks balanced" or "\nFAILED")
os.exit(fails == 0 and 0 or 1)

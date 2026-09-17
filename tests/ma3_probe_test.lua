-- Runs grandMA3/probe/steelblue_ma3_probe.lua against a fake grandMA3.
--
-- luac -p only proves the file compiles, and nobody here has a console on the
-- desk. This harness builds the globals MA3 provides (Root, Cmd, Printf, Echo,
-- GetPath, MessageBox, FileExists, Enums), hangs a small but real object tree
-- off Root(), and lets the probe run end to end. What it checks is what would
-- actually hurt on Tobi's machine:
--
--   * the plugin never aborts, not even when half the API is missing
--   * it writes its report, and the report carries all nine sections
--   * it cleans up: the cues it stored and the track group it appended are
--     gone again afterwards
--   * cancelling the confirmation box creates nothing
--
-- The fake deliberately does NOT say yes to everything: it only knows the
-- methods the 2.3 API documents, so a call the probe invents still logs an
-- error line instead of silently passing.

local folder = (arg[0]:match("(.*/)") or "./") .. "../"
local PROBE_FILE = folder .. "grandMA3/probe/steelblue_ma3_probe.lua"

local fails = 0

local function run(name, fn)
  local ok, detail = fn()
  if not ok then
    fails = fails + 1
  end
  print(string.format("%-58s %s%s", name, ok and "PASS" or "FAIL",
    detail and ("  -- " .. detail) or ""))
end

-- ------------------------------------------------------------- scratch dir

local TMP = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "") .. "/steelblue_ma3_probe_test"

local function reset_tmp()
  os.execute(string.format("rm -rf %q", TMP))
  os.execute(string.format("mkdir -p %q", TMP))
  -- The console's folders exist before a plugin runs; the fake's must too, or
  -- "io.open failed" would look like a finding when it is a harness artefact.
  os.execute(string.format("mkdir -p %q", TMP .. "/shows"))
  os.execute(string.format("mkdir -p %q", TMP .. "/plugins"))
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

-- ------------------------------------------------------------- fake handles

local METHODS = {}

local Handle = {}
Handle.__index = function(self, key)
  local method = METHODS[key]
  if method ~= nil then
    return method
  end
  if type(key) == "number" then
    return rawget(self, "kids")[key]
  end
  local named = rawget(self, "named")
  if named ~= nil and named[key] ~= nil then
    return named[key]
  end
  local props = rawget(self, "props")
  if props ~= nil then
    return props[key]
  end
  return nil
end
Handle.__tostring = function(self)
  return "handle:" .. tostring(rawget(self, "class")) .. ":" .. tostring(rawget(self, "name"))
end

local function new_handle(class, name, props)
  return setmetatable({
    class = class,
    name = name,
    props = props or {},
    kids = {},
    named = {},
  }, Handle)
end

local function add_child(parent, child)
  local kids = rawget(parent, "kids")
  kids[#kids + 1] = child
  rawset(child, "parent", parent)
  return child
end

local function add_named(parent, key, child)
  rawget(parent, "named")[key] = child
  rawset(child, "parent", parent)
  return child
end

-- Only the methods the 2.3 object API documents. Anything else the probe tries
-- has to fail, or the harness would be proving nothing.
function METHODS.GetClass(self) return rawget(self, "class") end
function METHODS.GetChildClass(self) return rawget(self, "child_class") end
function METHODS.Count(self) return #rawget(self, "kids") end

function METHODS.Children(self)
  local out = {}
  for i, child in ipairs(rawget(self, "kids")) do
    out[i] = child
  end
  return out
end

function METHODS.Ptr(self, index) return rawget(self, "kids")[index] end

function METHODS.Get(self, property, role)
  if property == "Name" then
    return rawget(self, "name")
  end
  local value = rawget(self, "props")[property]
  if value ~= nil and role ~= nil then
    return tostring(value) .. " (edit)"
  end
  return value
end

function METHODS.Set(self, property, value)
  if property == "Name" then
    rawset(self, "name", value)
    return
  end
  rawget(self, "props")[property] = value
end

function METHODS.Append(self, class)
  local child = new_handle(class or rawget(self, "child_class") or "Unknown", "")
  return add_child(self, child)
end

function METHODS.Delete(self, index)
  local kids = rawget(self, "kids")
  if type(index) ~= "number" or kids[index] == nil then
    error("Delete: no child at index " .. tostring(index), 0)
  end
  table.remove(kids, index)
end

function METHODS.Remove(self, index)
  return METHODS.Delete(self, index)
end

function METHODS.Index(self)
  local parent = rawget(self, "parent")
  if parent == nil then
    return 0
  end
  for i, child in ipairs(rawget(parent, "kids")) do
    if child == self then
      return i - 1 -- 0-based on purpose: the probe must not trust this
    end
  end
  return -1
end

function METHODS.Parent(self) return rawget(self, "parent") end
function METHODS.Addr(self) return "fake.addr." .. tostring(rawget(self, "class")) end
function METHODS.ToAddr(self) return "Fake " .. tostring(rawget(self, "name")) end

function METHODS.Dump(self)
  return string.format("FAKE DUMP class=%s name=%s children=%d",
    tostring(rawget(self, "class")), tostring(rawget(self, "name")), #rawget(self, "kids"))
end

-- ------------------------------------------------------------- fake world

local function build_world()
  local root = new_handle("Root", "Root")
  local show_data = add_named(root, "ShowData", new_handle("ShowData", "ShowData"))
  local pools = add_named(show_data, "DataPools", new_handle("DataPools", "DataPools"))
  local default = add_named(pools, "Default", new_handle("DataPool", "Default"))

  local timecodes = add_named(default, "Timecodes", new_handle("TimecodePool", "Timecodes"))
  local timecode = add_child(timecodes, new_handle("Timecode", "Main TC",
    { no = 1, Framerate = 30, Time = 0 }))
  local group = add_child(timecode, new_handle("TrackGroup", "Group 1", { no = 1 }))
  local track = add_child(group, new_handle("Track", "Track 1", { no = 1, Target = "Sequence 1" }))
  local range = add_child(track, new_handle("TimeRange", "Range 1", { no = 1 }))
  add_child(range, new_handle("Event", "", { no = 1, Time = 4.5, Token = "Go+", Cue = 1 }))

  local sequences = add_named(default, "Sequences", new_handle("SequencePool", "Sequences"))
  local sequence = add_child(sequences, new_handle("Sequence", "Kick", { no = 1 }))
  local cues = add_named(sequence, "Cues", new_handle("CueContainer", "Cues"))
  add_child(cues, new_handle("Cue", "Intro", { no = 1 }))
  add_child(cues, new_handle("Cue", "Drop", { no = 2 }))

  return {
    root = root,
    timecodes = timecodes,
    timecode = timecode,
    group = group,
    sequences = sequences,
    sequence = sequence,
    cues = cues,
  }
end

-- Understands just enough command line to make section 6 and section 9 real.
local function make_cmd(world, log)
  return function(command)
    log[#log + 1] = command

    local seq_no, cue_no = command:match("^Store Sequence (%d+) Cue (%d+)")
    if seq_no and cue_no then
      local kids = rawget(world.cues, "kids")
      for _, cue in ipairs(kids) do
        if tostring(rawget(cue, "props").no) == cue_no then
          return "Ok" -- an existing cue is NOT renamed by a second Store
        end
      end
      add_child(world.cues, new_handle("Cue", "", { no = tonumber(cue_no) }))
      return "Ok"
    end

    local label_seq, label_cue, label = command:match("^Label Sequence (%d+) Cue (%d+) \"(.-)\"")
    if label_seq and label_cue then
      for _, cue in ipairs(rawget(world.cues, "kids")) do
        if tostring(rawget(cue, "props").no) == label_cue then
          rawset(cue, "name", label)
        end
      end
      return "Ok"
    end

    local del_seq, del_cue = command:match("^Delete Sequence (%d+) Cue (%d+)")
    if del_seq and del_cue then
      local kids = rawget(world.cues, "kids")
      for i = #kids, 1, -1 do
        if tostring(rawget(kids[i], "props").no) == del_cue then
          table.remove(kids, i)
        end
      end
      return "Ok"
    end

    -- Track groups: "Store TC 1.3" makes group 3, "Delete TC 1.3" takes it
    -- away again. Enough for section 5 to build something and section 9 to
    -- have something real to clear up.
    local store_group = command:match("^Store TC %d+%.(%d+)")
      or command:match("^Store Timecode %d+%.(%d+)")
    if store_group then
      local kids = rawget(world.timecode, "kids")
      local wanted = tonumber(store_group)
      while #kids < wanted do
        add_child(world.timecode, new_handle("TrackGroup", "", { no = #kids + 1 }))
      end
      return "Ok"
    end

    local delete_group = command:match("^Delete TC %d+%.(%d+)")
      or command:match("^Delete Timecode %d+%.(%d+)")
    if delete_group then
      local kids = rawget(world.timecode, "kids")
      local wanted = tonumber(delete_group)
      if kids[wanted] ~= nil then
        table.remove(kids, wanted)
        return "Ok"
      end
      return "Illegal Command"
    end

    if command:match("^Echo") or command:match("^Select") or command:match("^Dump")
       or command:match("^Set TC") or command:match("^Assign ") then
      return "Ok"
    end
    return "Illegal Command"
  end
end

-- ------------------------------------------------------------- environment

local saved = {}
local GLOBAL_NAMES = {
  "Root", "Cmd", "Printf", "Echo", "GetPath", "GetPathSeparator", "MessageBox",
  "FileExists", "Enums", "Version", "HostOS", "SelectedTimecode",
}

local function set_globals(values)
  for _, name in ipairs(GLOBAL_NAMES) do
    saved[name] = _G[name]
    _G[name] = values[name]
  end
end

local function restore_globals()
  for _, name in ipairs(GLOBAL_NAMES) do
    _G[name] = saved[name]
  end
end

-- Builds a complete fake MA3. `options.messagebox` overrides what the boxes
-- answer; everything else is the well-behaved default.
local function make_environment(options)
  options = options or {}
  reset_tmp()

  local world = build_world()
  local commands = {}
  local boxes = {}

  local values = {
    Root = function() return world.root end,
    Cmd = make_cmd(world, commands),
    Printf = function() end,
    Echo = function() end,
    GetPathSeparator = function() return "/" end,
    FileExists = function(path)
      local file = io.open(path, "r")
      if file then
        file:close()
        return true
      end
      return false
    end,
    Version = function() return "2.3.0.2" end,
    HostOS = function() return "test" end,
    SelectedTimecode = function() return world.timecode end,
    Enums = {
      PathType = { Library = 59, GrandMA3Library = 52, PluginLibrary = 42, Showfiles = 17 },
      Roles = { Edit = 4 },
    },
    GetPath = function(what)
      if what == 59 or what == 52 then
        return TMP
      end
      if what == 42 then
        return TMP .. "/plugins"
      end
      if what == 17 then
        return TMP .. "/shows"
      end
      if what == "shows" then
        return TMP .. "/shows"
      end
      error("unknown path type: " .. tostring(what), 0)
    end,
    MessageBox = function(request)
      boxes[#boxes + 1] = request
      if options.messagebox then
        return options.messagebox(request, #boxes)
      end
      return {
        success = true,
        result = 1,
        selectors = { Timecode = 1, Sequence = 1 },
        states = { ["Import track A"] = true, ["Import track B"] = false,
                   ["Import track C"] = true },
        inputs = { Offset = "0" },
      }
    end,
  }

  if options.strip then
    for _, name in ipairs(options.strip) do
      values[name] = nil
    end
  end

  set_globals(values)
  return world, commands, boxes
end

local function count_cues(world)
  return #rawget(world.cues, "kids")
end

local function cue_numbers(world)
  local out = {}
  for _, cue in ipairs(rawget(world.cues, "kids")) do
    out[#out + 1] = tostring(rawget(cue, "props").no)
  end
  return table.concat(out, ",")
end

print("grandMA3 probe plugin against a fake console:\n")

-- --------------------------------------------------- scenario A: full run

local world, commands, boxes = make_environment()
local main = dofile(PROBE_FILE)
local ok_run, err = pcall(main, "fake-display-handle", nil)
local report = read_file(TMP .. "/steelblue_probe.txt")
restore_globals()

run("(a) the plugin runs to the end without an error", function()
  return ok_run, ok_run and "no error" or tostring(err)
end)

run("(a) it returns a function, as a 2.3 plugin must", function()
  return type(main) == "function", type(main)
end)

run("(a) the report file was written", function()
  return report ~= nil and #report > 0, report and (#report .. " bytes") or "missing"
end)

run("(a) all nine sections are in the report", function()
  if not report then return false, "no report" end
  for i = 1, 9 do
    if not report:find("SECTION " .. i .. "  ", 1, true) then
      return false, "section " .. i .. " missing"
    end
  end
  return true, "1-9"
end)

run("(a) the report ends with PROBE DONE", function()
  return report ~= nil and report:find("PROBE DONE", 1, true) ~= nil
end)

run("(a) no section aborted", function()
  if not report then return false, "no report" end
  local aborted = report:match("!! SECTION %S+ ABORTED: [^\n]*")
  return aborted == nil, aborted
end)

run("(a) Dump() text landed in the file, not only the console", function()
  return report ~= nil and report:find("FAKE DUMP class=Timecode", 1, true) ~= nil
end)

run("(a) the timecode tree was walked down to the event", function()
  if not report then return false, "no report" end
  return report:find("FAKE DUMP class=TrackGroup", 1, true) ~= nil
     and report:find("Token", 1, true) ~= nil
end)

run("(a) the example data file was written and read back", function()
  if not report then return false, "no report" end
  local data = read_file(TMP .. "/steelblue_probe_data.lua")
  if not data then return false, "steelblue_probe_data.lua missing" end
  if not report:find("track%[1%].name%s+= Kick") then
    return false, "the loaded table was not reported"
  end
  return true, "framerate + tracks read"
end)

local function sent(pattern)
  for _, command in ipairs(commands) do
    if command:find(pattern) then
      return command
    end
  end
  return nil
end

run("(a) the three scratch cues were stored", function()
  local hits = 0
  for i = 990, 992 do
    if sent("^Store Sequence 1 Cue " .. i) then hits = hits + 1 end
  end
  return hits == 3, hits .. " of 3"
end)

run("(a) it built a whole event chain on the command line", function()
  local wanted = {
    "^Store TC 1%.%d+%.1$",                      -- track
    "^Assign Sequence 1 at TC 1%.",              -- track target
    '^Store Type "CmdSubTrack" Timecode 1%.',    -- sub-track
    '^Set TC 1%..*Property "time" 12%.437$',     -- event time in seconds
    '^Set TC 1%..*Property "token" "goto"$',     -- event token
  }
  for _, pattern in ipairs(wanted) do
    if not sent(pattern) then
      return false, "missing: " .. pattern
    end
  end
  return true, #wanted .. " lines"
end)

run("(a) it wrote into a track group of its own, not an existing one", function()
  local command = sent("^Store TC 1%.(%d+) \"steelblue probe\"")
  if not command then return false, "no track group was stored" end
  local group = tonumber(command:match("^Store TC 1%.(%d+)"))
  return group ~= nil and group > 1, "group " .. tostring(group)
end)

run("(a) cleanup removed cues 990-992 again", function()
  return count_cues(world) == 2, cue_numbers(world)
end)

run("(a) cleanup removed both track groups it made", function()
  -- One came from Append() in section 4, one from Store TC in section 5.
  local kids = rawget(world.timecode, "kids")
  return #kids == 1, #kids .. " track group(s) left"
end)

run("(a) the original cue names survived", function()
  local kids = rawget(world.cues, "kids")
  return rawget(kids[1], "name") == "Intro" and rawget(kids[2], "name") == "Drop",
    tostring(rawget(kids[1], "name")) .. "/" .. tostring(rawget(kids[2], "name"))
end)

run("(a) two message boxes: the confirmation and the UI test", function()
  return #boxes == 2, #boxes .. " box(es)"
end)

run("(a) the UI box carries 2 selectors, 3 states, 1 input", function()
  local box = boxes[2]
  if not box then return false, "no second box" end
  return #box.selectors == 2 and #box.states == 3 and #box.inputs == 1,
    string.format("%d/%d/%d", #box.selectors, #box.states, #box.inputs)
end)

run("(a) the box return is reported keyed by element name", function()
  if not report then return false, "no report" end
  return report:find("result.selectors%['Timecode'%]%s+= 1") ~= nil
end)

-- ------------------------------------------- scenario B: user hits Cancel

world, commands, boxes = make_environment({
  messagebox = function(_, index)
    if index == 1 then
      return { success = false, result = 2 }
    end
    return { success = true, result = 1 }
  end,
})
main = dofile(PROBE_FILE)
local ok_cancel, cancel_err = pcall(main, "fake-display-handle", nil)
report = read_file(TMP .. "/steelblue_probe.txt")
restore_globals()

run("(b) cancelling does not raise an error", function()
  return ok_cancel, ok_cancel and "clean" or tostring(cancel_err)
end)

run("(b) the report says it was cancelled", function()
  return report ~= nil and report:find("Cancelled at the confirmation box", 1, true) ~= nil
end)

run("(b) nothing was created: no command was sent", function()
  return #commands == 0, #commands .. " command(s)"
end)

-- Checking the timecode afterwards would prove nothing here: cleanup puts it
-- back either way, so that assertion could not fail. What can only be true
-- when the cancel really took hold is that no section ran at all.
run("(b) it stopped before section 1 -- no sections in the report", function()
  if not report then return false, "no report" end
  local stopped = report:find("SECTION 1", 1, true) == nil
  return stopped, stopped and "report holds nothing but the header" or "sections ran anyway"
end)

run("(b) the second message box never appeared", function()
  return #boxes == 1, #boxes .. " box(es)"
end)

-- ----------------------------- scenario C: a console that answers almost nothing

world, commands, boxes = make_environment({
  strip = { "Root", "MessageBox", "Enums", "GetPathSeparator", "SelectedTimecode" },
})
main = dofile(PROBE_FILE)
local ok_bare, bare_err = pcall(main, nil, nil)
-- Without Enums the probe falls back to the string form of GetPath, and the
-- only string the 2.3 manual documents is "shows" -- so that is where the
-- report lands here. Which is itself worth knowing.
report = read_file(TMP .. "/shows/steelblue_probe.txt")
restore_globals()

run("(c) survives a console without Root, Enums or MessageBox", function()
  return ok_bare, ok_bare and "clean" or tostring(bare_err)
end)

run("(c) falls back to the string form of GetPath and still reports", function()
  return report ~= nil and #report > 0, report and (#report .. " bytes") or "missing"
end)

run("(c) the report names what was missing instead of crashing", function()
  if not report then return false, "no report" end
  return report:find("no MessageBox available", 1, true) ~= nil
     and report:find("SECTION 9", 1, true) ~= nil
end)

-- -------------------------- scenario D: no GetPath at all, so no file anywhere

world, commands, boxes = make_environment({ strip = { "GetPath" } })
main = dofile(PROBE_FILE)
local ok_nopath, nopath_err = pcall(main, nil, nil)
restore_globals()

run("(d) survives a console without GetPath", function()
  return ok_nopath, ok_nopath and "clean" or tostring(nopath_err)
end)

os.execute(string.format("rm -rf %q", TMP))

print(fails == 0 and "\nALL PASS" or ("\nFAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)

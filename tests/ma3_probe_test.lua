-- Runs grandMA3/probe/steelblue_ma3_probe.lua against a fake grandMA3.
--
-- luac -p only proves the file compiles, and nobody here has a console on the
-- desk. This harness builds the globals MA3 provides (Root, DataPool, Cmd,
-- Printf, Echo, GetPath, MessageBox, FileExists, Enums), hangs a real object
-- tree off them, and lets the probe run end to end.
--
-- The fake models the two things run 2 got wrong, so the probe cannot pass by
-- accident:
--
--   * THERE ARE TWO DATA POOLS. DataPool() answers pool 2, which holds the
--     timecode and the sequence. Root().ShowData.DataPools.Default is pool 1
--     and is empty. A probe that walks the Default route finds nothing, which
--     is exactly what happened on Tobi's console.
--   * THE CONSOLE PICKS THE EVENT NUMBER. "Store TC 1.2.1.1.1.5" appends the
--     next event whatever number was asked for, and a Set on the number that
--     was asked for answers "Illegal object" -- run 2's finding, reproduced.
--
-- It also puts a MarkerTrack in front of the real Track inside every track
-- group, because that is what a console does and it shifts every child index
-- by one.
--
-- The fake deliberately does NOT say yes to everything: it only knows the
-- methods the 2.3 API documents and only the properties each class really
-- carries, so a call the probe invents still logs an error line instead of
-- silently passing.

local folder = (arg[0]:match("(.*/)") or "./") .. "../"
local PROBE_FILE = folder .. "grandMA3/probe/steelblue_ma3_probe.lua"

local GUID_MARK = "steelblue:11112222-3333-4444"

local fails = 0

local function run(name, fn)
  local ok, detail = fn()
  if not ok then
    fails = fails + 1
  end
  print(string.format("%-62s %s%s", name, ok and "PASS" or "FAIL",
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
local serial = 0

-- Which property each class really has, and whether it may be written. A
-- console answers "Illegal property" for the rest, and so does this.
local CANON = {
  name = "Name", note = "Note", time = "Time", token = "Token",
  cuedestination = "CueDestination", target = "Target",
  framereadout = "FrameReadout", no = "No",
}

local WRITABLE = {
  Timecode     = { Name = true, Note = true, FrameReadout = true },
  TrackGroup   = { Name = true, Note = true },
  MarkerTrack  = { Name = true, Note = true },
  Track        = { Name = true, Note = true, Target = true },
  TimeRange    = { Name = true, Note = true },
  CmdSubTrack  = { Name = true, Note = true },
  -- The interesting one: an event has no free text field at all, so the probe
  -- must report that nothing stuck rather than inventing a place for the GUID.
  CmdEvent     = { Name = true, Time = true, Token = true, CueDestination = true },
  Sequence     = { Name = true, Note = true },
  Cue          = { Name = true, Note = true },
  Timecodes    = { Name = true, Note = true },
  Sequences    = { Name = true, Note = true },
  DataPool     = { Name = true, Note = true },
}

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
  -- Unique per object: the probe tells a new child from an old one by comparing
  -- these strings, exactly as it does with a console address.
  return string.format("%s#%d '%s'", tostring(rawget(self, "class")),
    rawget(self, "serial"), tostring(rawget(self, "name")))
end

local function new_handle(class, name, props)
  serial = serial + 1
  return setmetatable({
    class = class,
    name = name,
    serial = serial,
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

-- Only the methods the 2.3 object API documents.
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
  local canon = CANON[tostring(property):lower()]
  if canon == nil then
    return nil
  end
  if canon == "Name" then
    return rawget(self, "name")
  end
  local value = rawget(self, "props")[canon]
  if value ~= nil and role ~= nil then
    return tostring(value) .. " (edit)"
  end
  return value
end

function METHODS.Set(self, property, value)
  local canon = CANON[tostring(property):lower()]
  local allowed = WRITABLE[rawget(self, "class")]
  if canon == nil or allowed == nil or not allowed[canon] then
    error("Illegal property: " .. tostring(property), 0)
  end
  if canon == "Name" then
    rawset(self, "name", value)
    return
  end
  rawget(self, "props")[canon] = value
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

-- A real Dump lists the properties upper case, with "(Read Only)" on the ones
-- that cannot be written. Section 8 reads exactly that to find a home for the
-- REAPER GUID, so the shape matters more than the content.
function METHODS.Dump(self)
  local class = rawget(self, "class")
  local lines = {
    "Name:  " .. tostring(rawget(self, "name")),
    "Class: " .. tostring(class),
    "Properties:",
    "  INDEX = \"1\" (Read Only)",
    "  NAME = \"" .. tostring(rawget(self, "name")) .. "\"",
  }
  local allowed = WRITABLE[class] or {}
  if allowed.Note then
    lines[#lines + 1] = "  NOTE = \"" .. tostring(rawget(self, "props").Note or "") .. "\""
  end
  lines[#lines + 1] = "  MEMORYFOOTPRINT = \"1 Bytes\" (Read Only)"
  for _, key in ipairs({ "Time", "Token", "CueDestination", "Target", "FrameReadout" }) do
    if allowed[key] then
      lines[#lines + 1] = string.format("  %s = %q", key:upper(),
        tostring(rawget(self, "props")[key] or ""))
    end
  end
  lines[#lines + 1] = "Children:"
  lines[#lines + 1] = "  Count: " .. #rawget(self, "kids")
  return "FAKE DUMP class=" .. tostring(class) .. "\n" .. table.concat(lines, "\n")
end

-- ------------------------------------------------------------- fake world
--
-- Two data pools. Pool 1 is what Root().ShowData.DataPools.Default hands out
-- and it is empty. Pool 2 is what DataPool() hands out and it is where the
-- show lives. That is Tobi's console, and it is the whole point of version 1.1.

local function build_world()
  local root = new_handle("Root", "Root")
  local show_data = add_named(root, "ShowData", new_handle("ShowData", "ShowData"))
  local pools = add_named(show_data, "DataPools", new_handle("DataPools", "DataPools"))

  -- pool 1: reachable as .Default, and empty
  local pool1 = add_named(pools, "Default", new_handle("DataPool", "Default", { no = 1 }))
  add_named(pool1, "Timecodes", new_handle("Timecodes", "Timecodes"))
  local seqs1 = add_named(pool1, "Sequences", new_handle("Sequences", "Sequences"))
  local seq1 = add_child(seqs1, new_handle("Sequence", "Default", { no = 1 }))
  add_child(seq1, new_handle("Cue", "OffCue", {}))
  add_child(seq1, new_handle("Cue", "CueZero", { no = 0 }))

  -- pool 2: what DataPool() answers, and where everything really is
  local pool2 = add_named(pools, 2, new_handle("DataPool", "Show", { no = 2 }))
  local timecodes = add_named(pool2, "Timecodes", new_handle("Timecodes", "Timecodes"))
  local timecode = add_child(timecodes, new_handle("Timecode", "Main TC",
    { no = 1, FrameReadout = "30 fps" }))

  -- One track group that was there before the probe: a MarkerTrack in front of
  -- the real Track, and one event a human made, whose CueDestination shows the
  -- address form the console itself writes.
  local group = add_child(timecode, new_handle("TrackGroup", "Tobi group", { no = 1 }))
  add_child(group, new_handle("MarkerTrack", "Markers", { no = 1 }))
  local track = add_child(group, new_handle("Track", "Track 1", { no = 1, Target = "Sequence 1" }))
  local range = add_child(track, new_handle("TimeRange", "Range 1", { no = 1 }))
  local subtrack = add_child(range, new_handle("CmdSubTrack", "Cmd", { no = 1 }))
  add_child(subtrack, new_handle("CmdEvent", "", {
    no = 1, Time = 1.04, Token = "Goto", CueDestination = "Sequence 1 Cue 3",
  }))

  local sequences = add_named(pool2, "Sequences", new_handle("Sequences", "Sequences"))
  local sequence = add_child(sequences, new_handle("Sequence", "Kick", { no = 1 }))
  add_child(sequence, new_handle("Cue", "Intro", { no = 1 }))
  add_child(sequence, new_handle("Cue", "Drop", { no = 2 }))

  return {
    root = root,
    pool1 = pool1,
    pool2 = pool2,
    timecodes = timecodes,
    timecode = timecode,
    tobi_group = group,
    tobi_event = select(1, rawget(subtrack, "kids")[1]),
    sequences = sequences,
    sequence = sequence,
  }
end

-- ----------------------------------------------------- the fake command line

local function split_address(text)
  local parts = {}
  for piece in tostring(text):gmatch("[^%.]+") do
    parts[#parts + 1] = tonumber(piece)
  end
  return parts
end

local function nth_of_class(parent, class, n)
  local seen = 0
  for _, child in ipairs(rawget(parent, "kids")) do
    if rawget(child, "class") == class then
      seen = seen + 1
      if seen == n then
        return child
      end
    end
  end
  return nil
end

local function make_cmd(world, log)
  -- Walks a command-line address inside the CURRENT pool. Component 3 counts
  -- Tracks only, so "1.2.1" is the first real Track and not the MarkerTrack in
  -- front of it -- the offset the importer has to know about.
  local function resolve(parts)
    local node = nil
    for _, tc in ipairs(rawget(world.timecodes, "kids")) do
      if rawget(tc, "props").no == parts[1] then
        node = tc
      end
    end
    if node == nil or #parts == 1 then return node end
    node = rawget(node, "kids")[parts[2]]
    if node == nil or #parts == 2 then return node end
    node = nth_of_class(node, "Track", parts[3])
    if node == nil or #parts == 3 then return node end
    node = nth_of_class(node, "TimeRange", parts[4])
    if node == nil or #parts == 4 then return node end
    node = nth_of_class(node, "CmdSubTrack", parts[5])
    if node == nil or #parts == 5 then return node end
    return rawget(node, "kids")[parts[6]]
  end

  local function ensure(parts)
    local timecode = nil
    for _, tc in ipairs(rawget(world.timecodes, "kids")) do
      if rawget(tc, "props").no == parts[1] then
        timecode = tc
      end
    end
    if timecode == nil then
      timecode = add_child(world.timecodes,
        new_handle("Timecode", "", { no = parts[1], FrameReadout = "30 fps" }))
    end
    if #parts == 1 then return timecode end

    local kids = rawget(timecode, "kids")
    while #kids < parts[2] do
      add_child(timecode, new_handle("TrackGroup", "", { no = #kids + 1 }))
    end
    local group = kids[parts[2]]
    if #parts == 2 then return group end

    -- A console gives every track group its marker track first.
    if nth_of_class(group, "MarkerTrack", 1) == nil then
      add_child(group, new_handle("MarkerTrack", "Markers", { no = 1 }))
    end
    local n = 0
    while nth_of_class(group, "Track", parts[3]) == nil do
      n = n + 1
      add_child(group, new_handle("Track", "", { no = n }))
      if n > 8 then break end
    end
    local track = nth_of_class(group, "Track", parts[3])
    if #parts == 3 then return track end

    while nth_of_class(track, "TimeRange", parts[4]) == nil do
      add_child(track, new_handle("TimeRange", "", { no = parts[4] }))
    end
    local range = nth_of_class(track, "TimeRange", parts[4])
    if #parts == 4 then return range end

    while nth_of_class(range, "CmdSubTrack", parts[5]) == nil do
      add_child(range, new_handle("CmdSubTrack", "", { no = parts[5] }))
    end
    return nth_of_class(range, "CmdSubTrack", parts[5])
  end

  return function(command)
    log[#log + 1] = command

    -- ---------------------------------------------------------------- cues
    local seq_no, cue_no = command:match("^Store Sequence (%d+) Cue (%d+)")
    if seq_no and cue_no then
      for _, cue in ipairs(rawget(world.sequence, "kids")) do
        if tostring(rawget(cue, "props").no) == cue_no then
          return "OK", {} -- an existing cue is NOT renamed by a second Store
        end
      end
      add_child(world.sequence, new_handle("Cue", "", { no = tonumber(cue_no) }))
      return "OK", {}
    end

    local _, label_cue, label = command:match("^Label Sequence (%d+) Cue (%d+) \"(.-)\"")
    if label_cue then
      for _, cue in ipairs(rawget(world.sequence, "kids")) do
        if tostring(rawget(cue, "props").no) == label_cue then
          rawset(cue, "name", label)
        end
      end
      return "OK", {}
    end

    local _, del_cue = command:match("^Delete Sequence (%d+) Cue (%d+)")
    if del_cue then
      local kids = rawget(world.sequence, "kids")
      for i = #kids, 1, -1 do
        if tostring(rawget(kids[i], "props").no) == del_cue then
          table.remove(kids, i)
        end
      end
      return "OK", {}
    end

    -- ------------------------------------------------------------ timecode
    local store_addr, store_rest = command:match("^Store TC ([%d%.]+)%s*(.*)$")
    if not store_addr then
      store_addr, store_rest = command:match("^Store Timecode ([%d%.]+)%s*(.*)$")
    end
    if store_addr then
      local parts = split_address(store_addr)
      local name = store_rest:match("^\"(.-)\"$")
      if #parts >= 6 then
        -- THE FINDING FROM RUN 2: the number in the address is ignored. The
        -- event is appended, and it gets whatever number comes next.
        local subtrack = ensure({ parts[1], parts[2], parts[3], parts[4], parts[5] })
        if subtrack == nil then return "Illegal object", {} end
        local event = add_child(subtrack, new_handle("CmdEvent", name or "",
          { no = #rawget(subtrack, "kids") + 1 }))
        return "OK", {}, event
      end
      if #parts == 5 and name then
        -- Storing at the sub-track level WITH a name: a new event, named.
        local subtrack = ensure(parts)
        if subtrack == nil then return "Illegal object", {} end
        add_child(subtrack, new_handle("CmdEvent", name,
          { no = #rawget(subtrack, "kids") + 1 }))
        return "OK", {}
      end
      local node = ensure(parts)
      if node == nil then return "Illegal object", {} end
      if name then rawset(node, "name", name) end
      return "OK", {}
    end

    local sub_addr = command:match("^Store Type \"CmdSubTrack\" Timecode ([%d%.]+)$")
    if sub_addr then
      local node = ensure(split_address(sub_addr))
      return node ~= nil and "OK" or "Illegal object", {}
    end

    local set_addr, set_prop, set_value = command:match("^Set TC ([%d%.]+) Property \"(.-)\" (.+)$")
    if set_addr then
      local node = resolve(split_address(set_addr))
      if node == nil then
        return "Illegal object", {}
      end
      local value = set_value:match("^\"(.-)\"$") or tonumber(set_value) or set_value
      local ok = pcall(function() node:Set(set_prop, value) end)
      return ok and "OK" or "Illegal property", {}
    end

    local assign_seq, assign_addr = command:match("^Assign Sequence (%d+) at TC ([%d%.]+)$")
    if assign_addr then
      local node = resolve(split_address(assign_addr))
      if node == nil then return "Illegal object", {} end
      local ok = pcall(function() node:Set("Target", "Sequence " .. assign_seq) end)
      return ok and "OK" or "Illegal property", {}
    end

    local del_addr = command:match("^Delete TC ([%d%.]+)")
      or command:match("^Delete Timecode ([%d%.]+)")
    if del_addr then
      local parts = split_address(del_addr)
      if #parts == 1 then
        local kids = rawget(world.timecodes, "kids")
        for i = #kids, 1, -1 do
          if rawget(kids[i], "props").no == parts[1] then
            table.remove(kids, i)
            return "OK", {}
          end
        end
        return "Illegal object", {}
      end
      local timecode = nil
      for _, tc in ipairs(rawget(world.timecodes, "kids")) do
        if rawget(tc, "props").no == parts[1] then timecode = tc end
      end
      if timecode == nil then return "Illegal object", {} end
      local kids = rawget(timecode, "kids")
      if kids[parts[2]] == nil then return "Illegal object", {} end
      table.remove(kids, parts[2])
      return "OK", {}
    end

    if command:match("^Echo") or command:match("^Select") or command:match("^Dump") then
      return "OK", {}
    end
    return "Illegal Command", {}
  end
end

-- ------------------------------------------------------------- environment

local saved = {}
local GLOBAL_NAMES = {
  "Root", "DataPool", "Cmd", "Printf", "Echo", "GetPath", "GetPathSeparator",
  "MessageBox", "FileExists", "Enums", "Version", "HostOS", "HostType",
  "SelectedTimecode", "SelectedSequence", "ObjectList",
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

local function make_environment(options)
  options = options or {}
  reset_tmp()

  local world = build_world()
  local commands = {}
  local boxes = {}

  local values = {
    Root = function() return world.root end,
    -- The correction version 1.1 exists for: this is pool 2, not .Default.
    DataPool = function() return world.pool2 end,
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
    Version = function() return "2.3.2.0" end,
    HostOS = function() return "test" end,
    HostType = function() return "onPC" end,
    SelectedTimecode = function() return nil end,
    SelectedSequence = function() return world.sequence end,
    ObjectList = function() return { world.timecode } end,
    Enums = {
      PathType = {
        Library = 59, GrandMA3Library = 52, PluginLibrary = 42, Showfiles = 17,
        CustomPluginLibrary = 99, UserTimecodes = 110, UserSequences = 106,
        Temp = 12, MADir = 3,
      },
      Roles = { Edit = 4 },
    },
    GetPath = function(what)
      if what == 59 or what == 52 then
        return TMP
      end
      if what == 42 or what == 99 then
        return TMP .. "/plugins"
      end
      if what == 17 then
        return TMP .. "/shows"
      end
      if what == "shows" then
        return TMP .. "/shows"
      end
      if what == 110 or what == 106 or what == 12 or what == 3 then
        return TMP
      end
      error("unknown path type: " .. tostring(what), 0)
    end,
    MessageBox = function(request)
      boxes[#boxes + 1] = request
      if options.messagebox then
        return options.messagebox(request, #boxes)
      end
      return { success = true, result = 1 }
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

-- Walks every handle in the world, so "did the probe leave anything behind"
-- can be answered for the whole tree rather than the two places one thinks of.
local function walk_all(handle, seen, out)
  seen = seen or {}
  out = out or {}
  if handle == nil or seen[handle] then
    return out
  end
  seen[handle] = true
  out[#out + 1] = handle
  for _, child in ipairs(rawget(handle, "kids") or {}) do
    walk_all(child, seen, out)
  end
  for _, child in pairs(rawget(handle, "named") or {}) do
    walk_all(child, seen, out)
  end
  return out
end

local function cue_names(sequence)
  local out = {}
  for _, cue in ipairs(rawget(sequence, "kids")) do
    out[#out + 1] = tostring(rawget(cue, "name"))
  end
  return table.concat(out, ",")
end

print("grandMA3 probe plugin against a fake console with two data pools:\n")

-- --------------------------------------------------- scenario A: full run

local world, commands, boxes = make_environment()
_G.STEELBLUE_MA3_PROBE_TEST = {}
local main = dofile(PROBE_FILE)
local HOOK = _G.STEELBLUE_MA3_PROBE_TEST
_G.STEELBLUE_MA3_PROBE_TEST = nil
local ok_run, err = pcall(main, "fake-display-handle", nil)
local report = read_file(TMP .. "/steelblue_probe.txt")
restore_globals()
-- The later scenarios overwrite this report, and reading it is by far the
-- fastest way to see what the probe would put in front of Tobi:
--   MA3_PROBE_KEEP=/tmp/report.txt lua tests/ma3_probe_test.lua
if os.getenv("MA3_PROBE_KEEP") then
  os.execute(string.format("cp %q %q", TMP .. "/steelblue_probe.txt", os.getenv("MA3_PROBE_KEEP")))
end

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

-- --------------------------------------------------------- the data pool

run("(a) it names the CURRENT data pool, and that is pool 2", function()
  if not report then return false, "no report" end
  local no = report:match("DataPool%(%)\n?.-its No%s+= (%S+)")
  return no == "2", "its No = " .. tostring(no)
end)

run("(a) it records that .Default is a DIFFERENT pool", function()
  if not report then return false, "no report" end
  return report:find("same handle%?%s+= false") ~= nil
     and report:find("Everything below uses DataPool%(%)") ~= nil
end)

run("(a) the timecode is found -- the whole point of version 1.1", function()
  if not report then return false, "no report" end
  local how = report:match("timecode 1 found by%s+= ([^\n]*)")
  return how == "matched No", tostring(how)
end)

run("(a) the empty .Default pool is reported as the comparison it now is", function()
  if not report then return false, "no report" end
  return report:find("the Default pool's Timecodes %(comparison%)%s+= 0 children") ~= nil
end)

run("(a) the cue list reads the pool the cues land in", function()
  if not report then return false, "no report" end
  return report:find("cues in DataPool 2, Sequence 1", 1, true) ~= nil
end)

-- ------------------------------------------------------ the object API run

run("(a) section 4 really ran this time (it was skipped in run 2)", function()
  if not report then return false, "no report" end
  if report:find("no timecode handle, nothing to create", 1, true) then
    return false, "section 4 bailed out again"
  end
  return report:find("New Event after Set", 1, true) ~= nil, "the event was built and dumped"
end)

run("(a) section 7 really ran too, and put the framerate back", function()
  if not report then return false, "no report" end
  if report:find("setting a time cannot be tested", 1, true) then
    return false, "no event reached section 7"
  end
  local restored = report:match("FrameReadout restored to%s+= ([^\n]*)")
  return restored == "30 fps", "restored to " .. tostring(restored)
end)

run("(a) the framerate on the object is 30 fps again afterwards", function()
  return rawget(world.timecode, "props").FrameReadout == "30 fps",
    tostring(rawget(world.timecode, "props").FrameReadout)
end)

-- --------------------------------------------- the event-number discovery

local function sent(pattern)
  for _, command in ipairs(commands) do
    if command:find(pattern) then
      return command
    end
  end
  return nil
end

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

-- The sharp one. The probe asks for event number 5; the console appends it as
-- number 3. A probe that trusts the number it asked for addresses 5 and gets
-- "Illegal object" -- run 2, exactly. Version 1.1 has to address 3.
run("(a) it addresses the event by the number the console gave it, not 5", function()
  local command = sent('^Set TC 1%.%d+%.1%.1%.1%.3 Property "time" 45%.25$')
  if not command then
    return false, "it never set the third event by the index the tree showed"
  end
  return true, command
end)

run("(a) and it shows what the asked-for number does instead", function()
  if not report then return false, "no report" end
  if not sent('^Set TC 1%.%d+%.1%.1%.1%.5 Property "time" 45%.25$') then
    return false, "the comparison command was never sent"
  end
  -- The fake answers that one "Illegal object", the way Tobi's console did.
  return report:find('%.1%.1%.1%.5 Property \\"time\\" 45%.25"%) %-> Illegal object') ~= nil,
    "the asked-for number is on record as Illegal object"
end)

run("(a) it reports where the MarkerTrack sits and where the Track sits", function()
  if not report then return false, "no report" end
  local marker = report:match("MarkerTrack sits at child index%s+= (%S+)")
  -- "Track sits at ..." is a substring of "MarkerTrack sits at ...", so the
  -- pattern has to start at the beginning of the line.
  local track = report:match("\n%s*Track sits at child index%s+= (%S+)")
  return marker == "1" and track == "2",
    "MarkerTrack " .. tostring(marker) .. ", Track " .. tostring(track)
end)

-- ------------------------------------------------------------- the cues

run("(a) the three scratch cues were stored", function()
  local hits = 0
  for i = 990, 992 do
    if sent("^Store Sequence 1 Cue " .. i) then hits = hits + 1 end
  end
  return hits == 3, hits .. " of 3"
end)

run("(a) the report shows the stored cues, which run 2 never could", function()
  if not report then return false, "no report" end
  return report:find("cue %[3%] no=990") ~= nil, "cue 990 is in the listing"
end)

-- ------------------------------------------------------- the GUID question

run("(a) section 8 looked for a text field on every level", function()
  if not report then return false, "no report" end
  for _, class in ipairs({ "TrackGroup", "Track", "TimeRange", "CmdSubTrack", "CmdEvent" }) do
    if not report:find("-- " .. class .. "  %->") then
      return false, class .. " was never examined"
    end
  end
  return true, "5 levels"
end)

run("(a) it found NOTE on a track group and reports that it stuck", function()
  if not report then return false, "no report" end
  local block = report:match("%-%- TrackGroup  %->.-\n%-%-")
    or report:match("%-%- TrackGroup  %->.*$")
  if not block then return false, "no TrackGroup block" end
  return block:find("IT STUCK", 1, true) ~= nil, "a writable Note exists there"
end)

run("(a) it reports per property whether the string stuck, not just per level", function()
  if not report then return false, "no report" end
  local block = report:match("%-%- CmdEvent  %->.-\n%-%- ") or report:match("%-%- CmdEvent  %->.*$")
  if not block then return false, "no CmdEvent block" end
  -- This fake's event takes a Name but has no Note. Both answers have to be in
  -- the report, or the section cannot tell the importer where the GUID may go.
  local name_line = block:match("\n%s*Name%s+before=[^\n]*")
  local note_line = block:match("\n%s*Note%s+before=[^\n]*")
  if not name_line or not note_line then
    return false, "Name or Note was never tried on the event"
  end
  if not name_line:find("IT STUCK", 1, true) then
    return false, "a writable Name is not reported as usable: " .. name_line
  end
  if note_line:find("IT STUCK", 1, true) then
    return false, "a Note the event does not have is reported as usable"
  end
  return true, "Name sticks, Note does not"
end)

run("(a) it never writes into an object that was already in the show", function()
  for _, handle in ipairs(walk_all(world.root)) do
    if rawget(handle, "name") == GUID_MARK then
      return false, "a name was overwritten: " .. tostring(handle)
    end
    for key, value in pairs(rawget(handle, "props") or {}) do
      if value == GUID_MARK then
        return false, "left behind on " .. tostring(handle) .. "." .. tostring(key)
      end
    end
  end
  return true, "nothing of the probe's is left in the show"
end)

run("(a) the hand-made event is untouched", function()
  local props = rawget(world.tobi_event, "props")
  return props.Time == 1.04 and props.CueDestination == "Sequence 1 Cue 3",
    string.format("Time=%s CueDestination=%s", tostring(props.Time), tostring(props.CueDestination))
end)

-- ----------------------------------------------------------- the clean-up

run("(a) cleanup removed cues 990-992 again", function()
  return #rawget(world.sequence, "kids") == 2, cue_names(world.sequence)
end)

run("(a) the original cue names survived", function()
  return cue_names(world.sequence) == "Intro,Drop", cue_names(world.sequence)
end)

run("(a) cleanup removed both track groups it made", function()
  -- One came from Append() in section 4, one from Store TC in section 5.
  local kids = rawget(world.timecode, "kids")
  return #kids == 1, #kids .. " track group(s) left"
end)

run("(a) cleanup finds its track group again after the numbers shifted", function()
  if not report then return false, "no report" end
  -- Deleting the object-API group first renumbers the command line's group, so
  -- the number section 5 remembered is stale by the time section 9 uses it.
  -- Finding it again by HANDLE is what stops the wrong group being deleted.
  local remembered = report:match("number remembered from section 5%s+= (%S+)")
  local by_handle = report:match("position found again by handle%s+= (%S+)")
  if remembered == nil or by_handle == nil then
    return false, "section 9 did not report both numbers"
  end
  if remembered == by_handle then
    return false, "the numbers did not shift, so this proves nothing"
  end
  return sent("^Delete TC 1%." .. by_handle .. " /NoConfirmation$") ~= nil,
    "remembered " .. remembered .. ", deleted " .. by_handle
end)

run("(a) the track group that was there before is still there", function()
  local kids = rawget(world.timecode, "kids")
  return kids[1] == world.tobi_group, tostring(rawget(kids[1], "name"))
end)

run("(a) the pool the probe must NOT touch is untouched", function()
  local timecodes = rawget(world.pool1, "named").Timecodes
  return #rawget(timecodes, "kids") == 0, #rawget(timecodes, "kids") .. " timecode(s) in pool 1"
end)

run("(a) exactly one message box: the confirmation, and no UI test any more", function()
  return #boxes == 1, #boxes .. " box(es)"
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

run("(b) it stopped before section 1 -- no sections in the report", function()
  if not report then return false, "no report" end
  local stopped = report:find("SECTION 1", 1, true) == nil
  return stopped, stopped and "report holds nothing but the header" or "sections ran anyway"
end)

run("(b) the show is exactly as it was", function()
  local kids = rawget(world.timecode, "kids")
  return #kids == 1 and #rawget(world.sequence, "kids") == 2,
    #kids .. " group(s), " .. #rawget(world.sequence, "kids") .. " cue(s)"
end)

-- ----------------------------- scenario C: a console that answers almost nothing

world, commands, boxes = make_environment({
  strip = { "Root", "DataPool", "MessageBox", "Enums", "GetPathSeparator", "SelectedTimecode" },
})
main = dofile(PROBE_FILE)
local ok_bare, bare_err = pcall(main, nil, nil)
-- Without Enums the probe falls back to the string form of GetPath, and the
-- only string the 2.3 manual documents is "shows" -- so that is where the
-- report lands here. Which is itself worth knowing.
report = read_file(TMP .. "/shows/steelblue_probe.txt")
restore_globals()

run("(c) survives a console without Root, DataPool, Enums or MessageBox", function()
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

-- ------------------------------- scenario E: the two helpers, on their own

run("(e) the dump scanner finds NOTE and skips the read-only lines", function()
  if type(HOOK.text_property_candidates) ~= "function" then
    return false, "the test hook was not filled"
  end
  local found = HOOK.text_property_candidates([[
Properties:
  INDEX = "14" (Read Only)
  NAME = "Timecodes"
  NOTE = ""
  MEMORYFOOTPRINT = "297 Bytes"
  CUENAME = "" (Read Only)
]])
  local joined = table.concat(found, ",")
  return joined == "NAME,NOTE", joined
end)

run("(e) an OK from the console counts, whatever its spelling", function()
  if type(HOOK.cmd_ok) ~= "function" then
    return false, "the test hook was not filled"
  end
  return HOOK.cmd_ok("OK") and HOOK.cmd_ok("Ok")
     and not HOOK.cmd_ok("Illegal object") and not HOOK.cmd_ok(nil),
    "OK / Ok yes, Illegal object no"
end)

run("(e) the file says it is version 1.1", function()
  return HOOK.PROBE_VERSION == "1.1", tostring(HOOK.PROBE_VERSION)
end)

os.execute(string.format("rm -rf %q", TMP))

print(fails == 0 and "\nALL PASS" or ("\nFAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)

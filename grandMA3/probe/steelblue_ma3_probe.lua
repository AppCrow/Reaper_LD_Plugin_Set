-- steelblue_ma3_probe.lua -- grandMA3 probe 1 for the planned REAPER -> MA3 marker importer.
--
-- WHAT THIS IS
--   A read-mostly reconnaissance plugin. It answers the questions the importer
--   cannot be written without, and it answers them on the real console instead
--   of from documentation: which Lua libraries exist, where files may be read
--   and written, what the timecode object tree actually looks like, whether a
--   track and an event can be created from Lua at all, which command-line
--   spelling stores a timecode event, what unit an event time carries, and what
--   a MessageBox with selectors/states/inputs hands back.
--
-- WHAT IT TOUCHES
--   One timecode and one sequence of a THROWAWAY show (numbers below), plus
--   cues 990-992 of that sequence. Section 9 removes everything it created.
--   It writes two files into the library folder: the report and, on the first
--   run, an example data file.
--
-- HOW IT REPORTS
--   Every step is wrapped in pcall, so a call that does not exist on this
--   version logs a line and the probe carries on. Findings go into
--   <library>/steelblue_probe.txt; the path is also printed to the System
--   Monitor. The file is rewritten after every section, so an abort still
--   leaves everything gathered so far on disk.
--
-- LUA DIALECT
--   The 2.3 manual says Lua 5.4.6 (help.malighting.com/grandMA3/2.3/HTML/lua.html),
--   older notes in this project say 5.3. This file therefore stays inside the
--   intersection: no <const>, no <close>, no 5.4-only library call. Section 1
--   prints _VERSION, which settles the question for good.

local PROBE_VERSION = "1.0"

-- ---------------------------------------------------------------- settings
-- Tobi edits these four numbers if his throwaway show uses different ones.
-- The plugin asks nothing; it only shows them once in a confirmation box.

local TIMECODE_NO = 1   -- the EXISTING timecode the probe writes into
local SEQUENCE_NO = 1   -- the EXISTING sequence the probe points a track at
local CUE_FIRST   = 990 -- first scratch cue number (990, 991, 992 are used)
local CUE_COUNT   = 3

-- Optional: an absolute path to any small text file outside the MA3 folders
-- (a file on the desktop, for instance). Left empty the probe tests the
-- sandbox with files it writes itself. Example on Windows:
--   local EXTERNAL_FILE = "C:\\Users\\Tobi\\Desktop\\test.txt"
local EXTERNAL_FILE = ""

-- ------------------------------------------------------------------ output

local report_lines = {}
local report_count = 0
local output_path = nil
local path_sep = "/"

local function safe_tostring(value)
  local ok, text = pcall(tostring, value)
  if ok then
    return text
  end
  return "<tostring failed>"
end

local S = safe_tostring

local function raw(text)
  report_count = report_count + 1
  report_lines[report_count] = text
end

local function w(text)
  raw(text)
end

local function wf(format_string, ...)
  local ok, text = pcall(string.format, format_string, ...)
  if ok then
    raw(text)
  else
    raw(format_string .. "  <format failed: " .. S(text) .. ">")
  end
end

local function kv(key, value)
  wf("  %-38s = %s", S(key), S(value))
end

local function section(number, title)
  raw("")
  raw(string.rep("=", 78))
  wf("SECTION %s  %s", S(number), S(title))
  raw(string.rep("=", 78))
end

local function sub(title)
  raw("")
  wf("-- %s", S(title))
end

-- Console output. Printf is the MA3 way; keep it optional so the file also
-- runs under a bare Lua for the offline test.
local function say(text)
  if type(Printf) == "function" then
    pcall(Printf, "%s", S(text))
  elseif type(Echo) == "function" then
    pcall(Echo, "%s", S(text))
  end
end

local function flush()
  if not output_path then
    return false, "no output path yet"
  end
  if type(io) ~= "table" or type(io.open) ~= "function" then
    return false, "no io library"
  end
  local file, err = io.open(output_path, "w")
  if not file then
    return false, S(err)
  end
  file:write(table.concat(report_lines, "\n"))
  file:write("\n")
  file:close()
  return true
end

-- ----------------------------------------------------------------- helpers

-- Runs fn(...) under pcall, logs what came back, and returns ok plus the
-- first two results. Nothing in this probe may abort the plugin.
local function try(label, fn, ...)
  if type(fn) ~= "function" then
    wf("  SKIP %s -> not a function (%s)", S(label), type(fn))
    return false, nil
  end
  local packed = table.pack(pcall(fn, ...))
  if packed[1] then
    local parts = {}
    for i = 2, packed.n do
      parts[#parts + 1] = S(packed[i])
    end
    if #parts == 0 then
      wf("  OK   %s -> (no value)", S(label))
    else
      wf("  OK   %s -> %s", S(label), table.concat(parts, ", "))
    end
    return true, packed[2], packed[3]
  end
  wf("  ERR  %s -> %s", S(label), S(packed[2]))
  return false, packed[2]
end

-- Calls a method by name on a handle. Written as a separate helper because
-- "does this handle have that method at all" is one of the probe's questions.
local function call_method(handle, method_name, ...)
  local args = table.pack(...)
  return try(S(handle) .. ":" .. method_name .. "()", function()
    local fn = handle[method_name]
    if fn == nil then
      error("no such method", 0)
    end
    return fn(handle, table.unpack(args, 1, args.n))
  end)
end

-- Quiet variant: no log line, just the value. Used where a failure is
-- expected and noise would drown the interesting lines.
local function get_quiet(handle, method_name, ...)
  local ok, value = pcall(function(...)
    local fn = handle[method_name]
    if fn == nil then
      return nil
    end
    return fn(handle, ...)
  end, ...)
  if ok then
    return value
  end
  return nil
end

local function index_quiet(handle, key)
  local ok, value = pcall(function()
    return handle[key]
  end)
  if ok then
    return value
  end
  return nil
end

local function handle_label(handle)
  if handle == nil then
    return "nil"
  end
  local name = index_quiet(handle, "name")
  local class = get_quiet(handle, "GetClass")
  local parts = {}
  if class ~= nil then parts[#parts + 1] = "class=" .. S(class) end
  if name ~= nil then parts[#parts + 1] = "name=" .. S(name) end
  if #parts == 0 then
    return S(handle)
  end
  return S(handle) .. " (" .. table.concat(parts, " ") .. ")"
end

-- Every property name worth asking a timecode-related object about. Asking
-- for one that does not exist is harmless (it answers nil), so a generous
-- list costs nothing and is the point of a probe.
-- The names in the first block come from a real timecode show-file dump
-- (forum.malighting.com thread 5079) and the 2.3 timecode settings page; the
-- rest are plausible spellings that cost one nil each.
local PROPERTY_CANDIDATES = {
  "Name", "No", "Index", "Class", "Note", "Appearance", "Color",
  "Duration", "LoopCount", "TCSlot", "AutoStart", "AutoStop", "SwitchOff",
  "Goto", "Timedisplayformat", "FrameReadout", "Framerate", "FrameRate", "Rate",
  "Time", "Token", "ExecToken", "Status", "CueDestination", "ValCueDestination",
  "Target", "Object", "Sequence", "Cue", "CueNumber", "Assignment",
  "Command", "CmdText", "Cmd", "Type", "TrackType", "SubTrackType",
  "Play", "Rec", "Start", "End", "Length", "Offset", "TimeOffset",
  "Loop", "Follow", "Enabled", "Active", "Speed", "Path", "FileName", "Guid",
}

-- Zero-argument methods the 2.3 object API documents, plus Acquire, which
-- public timecode plugins use to create TimeRange and CmdSubTrack children.
local METHOD_CANDIDATES = {
  "GetClass", "GetChildClass", "Count", "Children", "Addr", "ToAddr",
  "Parent", "Index", "Dump", "Get", "Set", "Append", "Acquire", "Insert",
  "Create", "Delete", "Remove", "Ptr", "IsValid", "IsClass", "IsEmpty",
  "Export", "Import",
}

-- Get(handle, property, role): with Enums.Roles.Edit the value comes back as
-- the display string, which is what the command line would show. Reading both
-- tells the importer which form it has to write back.
local EDIT_ROLE = nil
pcall(function()
  if type(Enums) == "table" and type(Enums.Roles) == "table" then
    EDIT_ROLE = Enums.Roles.Edit
  end
end)

-- Published plugins read properties as LOWERCASE fields (event.time,
-- track.target, timecode.framereadout) while Get() takes the cased name.
-- Both routes are tried, because the importer needs to know which one is real.
local function read_property(handle, property)
  local value = get_quiet(handle, "Get", property)
  if value ~= nil then
    return value, "Get"
  end
  -- A field lookup can land on a METHOD of the same name -- Index, Count and
  -- Parent are all methods -- so anything callable is not the property.
  value = index_quiet(handle, property)
  if value ~= nil and type(value) ~= "function" then
    return value, "field"
  end
  value = index_quiet(handle, property:lower())
  if value ~= nil and type(value) ~= "function" then
    return value, "lowercase field"
  end
  return nil, nil
end

local function list_properties(handle, indent)
  indent = indent or "    "
  local found = 0
  for i = 1, #PROPERTY_CANDIDATES do
    local property = PROPERTY_CANDIDATES[i]
    local value, how = read_property(handle, property)
    if value ~= nil then
      found = found + 1
      local label = property .. " [" .. S(how) .. "]"
      local edit = nil
      if EDIT_ROLE ~= nil then
        edit = get_quiet(handle, "Get", property, EDIT_ROLE)
      end
      if edit ~= nil and S(edit) ~= S(value) then
        wf("%s%-34s = %s  (%s)   [Roles.Edit: %s]", indent, label, S(value), type(value), S(edit))
      else
        wf("%s%-34s = %s  (%s)", indent, label, S(value), type(value))
      end
    end
  end
  if found == 0 then
    wf("%s(no property from the candidate list answered)", indent)
  end
  return found
end

local function list_methods(handle, indent)
  indent = indent or "    "
  local names = {}
  for i = 1, #METHOD_CANDIDATES do
    local name = METHOD_CANDIDATES[i]
    local value = index_quiet(handle, name)
    if value ~= nil then
      names[#names + 1] = name .. ":" .. type(value)
    end
  end
  if #names == 0 then
    wf("%s(indexing the handle for method names answered nothing)", indent)
  else
    wf("%s%s", indent, table.concat(names, "  "))
  end
end

-- pairs() over a handle may or may not work; if it does, it is the most
-- complete answer this probe can get.
local function list_pairs(handle, indent, limit)
  indent = indent or "    "
  limit = limit or 60
  local ok, err = pcall(function()
    local shown = 0
    for key, value in pairs(handle) do
      shown = shown + 1
      if shown > limit then
        wf("%s... (stopped after %d entries)", indent, limit)
        return
      end
      wf("%s%-24s = %s  (%s)", indent, S(key), S(value), type(value))
    end
    if shown == 0 then
      wf("%s(pairs() worked but the handle has no entries)", indent)
    end
  end)
  if not ok then
    wf("%spairs() not possible: %s", indent, S(err))
  end
end

-- Children(handle) is the documented way and returns a plain table; Count()
-- plus Ptr() is the fallback. Which one answers is itself worth recording.
local function children_of(handle)
  local list = get_quiet(handle, "Children")
  if type(list) == "table" and #list > 0 then
    return list, "Children()", #list
  end
  local count = get_quiet(handle, "Count")
  if type(count) == "number" and count > 0 then
    local out = {}
    for i = 1, count do
      local child = get_quiet(handle, "Ptr", i)
      if child == nil then
        child = index_quiet(handle, i)
      end
      out[#out + 1] = child
    end
    return out, "Count() + Ptr()", count
  end
  if type(list) == "table" then
    return list, "Children() -- empty", 0
  end
  return {}, "neither Children() nor Count() answered", 0
end

local function list_children(handle, indent, limit)
  indent = indent or "    "
  limit = limit or 40
  local kids, how, count = children_of(handle)
  wf("%schildren via %s: %s", indent, S(how), S(count))
  for i = 1, #kids do
    if i > limit then
      wf("%s... (stopped after %d children)", indent, limit)
      break
    end
    local child = kids[i]
    wf("%s[%d] %s  no=%s index=%s",
      indent, i, handle_label(child),
      S(index_quiet(child, "no") or get_quiet(child, "Get", "No")),
      S(index_quiet(child, "index")))
  end
  return kids
end

-- The full picture of one object: class, methods, properties, children, and
-- the console Dump() on top of it.
local function describe(handle, title, options)
  options = options or {}
  sub(title .. "  ->  " .. handle_label(handle))
  if handle == nil then
    w("    handle is nil, nothing to describe")
    return
  end
  kv("type(handle)", type(handle))
  kv("tostring(handle)", handle)
  call_method(handle, "GetClass")
  call_method(handle, "GetChildClass")
  call_method(handle, "Addr")
  call_method(handle, "ToAddr")
  w("    methods present on the handle:")
  list_methods(handle, "      ")
  w("    properties that answered:")
  list_properties(handle, "      ")
  if options.pairs ~= false then
    w("    pairs() over the handle:")
    list_pairs(handle, "      ")
  end
  if options.children ~= false then
    list_children(handle, "    ", options.child_limit or 40)
  end
  if options.dump ~= false then
    -- Dump() is documented as returning the information as a string, so it can
    -- land in this file instead of scrolling past in the System Monitor.
    local ok, text = pcall(function() return handle:Dump() end)
    if not ok then
      wf("    Dump() failed: %s", S(text))
    elseif type(text) == "string" and text ~= "" then
      w("    Dump():")
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
          wf("      %s", line)
        end
      end
    else
      wf("    Dump() returned %s -- its text went to the System Monitor instead", S(text))
    end
  end
end

-- --------------------------------------------------------------- sections

local function section_1_environment()
  section(1, "Environment: version, Lua, libraries, paths")

  sub("Lua itself")
  kv("_VERSION", _VERSION)
  kv("PROBE_VERSION", PROBE_VERSION)

  local libraries = {
    "string", "table", "math", "io", "os", "coroutine", "debug", "utf8", "package",
  }
  for i = 1, #libraries do
    local name = libraries[i]
    kv("library " .. name, type(index_quiet(_G or {}, name) or rawget(_ENV or {}, name)))
  end

  local loaders = { "load", "loadstring", "loadfile", "dofile", "require", "rawget", "pcall", "select" }
  for i = 1, #loaders do
    local name = loaders[i]
    local fn = nil
    pcall(function() fn = _ENV[name] end)
    kv("function " .. name, type(fn))
  end

  if type(os) == "table" then
    try("os.time()", os.time)
    try("os.date()", os.date)
    try("os.clock()", os.clock)
    try("os.getenv('HOME')", os.getenv, "HOME")
    try("os.getenv('USERPROFILE')", os.getenv, "USERPROFILE")
    kv("os.remove", type(os.remove))
    kv("os.rename", type(os.rename))
    kv("os.execute", type(os.execute))
  end

  sub("Every global this plugin can see")
  local ok = pcall(function()
    local names = {}
    for key, value in pairs(_ENV) do
      names[#names + 1] = S(key) .. " (" .. type(value) .. ")"
    end
    table.sort(names)
    for i = 1, #names do
      wf("    %s", names[i])
    end
    wf("    -- %d globals in total", #names)
  end)
  if not ok then
    w("    pairs(_ENV) is not possible here; falling back to a name list")
    local candidates = {
      "Root", "Cmd", "CmdIndirect", "CmdIndirectWait", "Printf", "Echo", "ErrPrintf",
      "GetPath", "FileExists", "MessageBox", "TextInput", "Confirm", "PopupInput",
      "ObjectList", "SelectedTimecode", "SelectedSequence", "CurrentUser",
      "CurrentProfile", "CurrentExecPage", "DataPool", "ShowData", "HookObjectChange",
      "Version", "HostOS", "HostType", "HostSubType", "ProductType", "Enums",
      "SetVar", "GetVar", "DelVar", "GlobalVars", "UserVars", "ShowVars",
      "CreateDirectory", "DirList", "Timer", "Time", "Export", "Import",
      "ColorCodeToColor", "HandleToInt", "IntToHandle", "ObjectListWithFilter",
    }
    for i = 1, #candidates do
      local value = nil
      pcall(function() value = _ENV[candidates[i]] end)
      kv(candidates[i], type(value))
    end
  end

  sub("grandMA3 version")
  try("Version()", Version)
  try("HostOS()", HostOS)
  try("HostType()", HostType)
  try("HostSubType()", HostSubType)
  try("ProductType()", ProductType)
  local ok_root, root = try("Root()", Root)
  if ok_root and root ~= nil then
    kv("Root() class", get_quiet(root, "GetClass"))
    kv("Root().version", index_quiet(root, "version"))
    kv("Root():Get('Version')", get_quiet(root, "Get", "Version"))
  end

  sub("GetPath -- which argument gives which folder")
  if type(GetPath) ~= "function" then
    w("    GetPath is not available, so the probe cannot locate any folder")
    return root
  end

  -- The enum route first: if Enums.PathType exists, walk every entry of it.
  local walked = false
  pcall(function()
    if type(Enums) ~= "table" then return end
    local path_type = Enums.PathType
    if path_type == nil then return end
    local entries = {}
    for key, value in pairs(path_type) do
      entries[#entries + 1] = { key = S(key), value = value }
    end
    table.sort(entries, function(a, b) return a.key < b.key end)
    for i = 1, #entries do
      walked = true
      try(string.format("GetPath(Enums.PathType.%s = %s)", entries[i].key, S(entries[i].value)),
        GetPath, entries[i].value)
    end
  end)
  if not walked then
    w("    Enums.PathType could not be walked; trying spellings instead")
  end

  -- "shows" is the only string the 2.3 manual documents. The rest are guesses
  -- that cost one log line each and might save the importer a round trip.
  local spellings = {
    "shows", "gma3_library", "library", "showfile", "showfiles",
    "plugins", "userprofile", "user", "temp",
  }
  for i = 1, #spellings do
    try("GetPath(\"" .. spellings[i] .. "\")", GetPath, spellings[i])
  end
  try("GetPathSeparator()", GetPathSeparator)

  return root
end

-- Works out where the report goes. Called early so later sections can flush.
--
-- There is no "gma3_library" string constant in the 2.3 API; the folder is
-- reached through Enums.PathType. The order below is "most likely to be the
-- gma3_library folder" first, and whichever answers a non-empty string wins.
local LIBRARY_ENUMS = { "Library", "GrandMA3Library", "PluginLibrary", "Showfiles", "UserMedia" }
local LIBRARY_STRINGS = { "library", "gma3_library", "shows" }

local function pick_output_path()
  local library, source = nil, nil
  if type(GetPathSeparator) == "function" then
    local ok, separator = pcall(GetPathSeparator)
    if ok and type(separator) == "string" and separator ~= "" then
      path_sep = separator
    end
  end
  if type(GetPath) == "function" then
    for i = 1, #LIBRARY_ENUMS do
      if type(library) ~= "string" or library == "" then
        pcall(function()
          if type(Enums) == "table" and type(Enums.PathType) == "table"
             and Enums.PathType[LIBRARY_ENUMS[i]] ~= nil then
            library = GetPath(Enums.PathType[LIBRARY_ENUMS[i]])
            source = "Enums.PathType." .. LIBRARY_ENUMS[i]
          end
        end)
      end
    end
    for i = 1, #LIBRARY_STRINGS do
      if type(library) ~= "string" or library == "" then
        pcall(function()
          library = GetPath(LIBRARY_STRINGS[i])
          source = string.format("GetPath(%q)", LIBRARY_STRINGS[i])
        end)
      end
    end
  end
  if type(library) ~= "string" or library == "" then
    return nil, nil, "no GetPath call produced a folder"
  end
  -- A Windows path carries backslashes; do not force a slash into it.
  if library:find("\\", 1, true) and not library:find("/", 1, true) then
    path_sep = "\\"
  end
  local trimmed = library:gsub("[/\\]+$", "")
  return trimmed .. path_sep .. "steelblue_probe.txt", trimmed, source
end

local DATA_EXAMPLE = [[
-- steelblue_probe_data.lua -- example payload, written by the probe itself.
-- The real importer will receive a file shaped like this from REAPER.
return {
  framerate = 30,
  offset = 0,
  tracks = {
    {
      name = "Kick",
      sequence = 12,
      events = {
        { time = 1.5,  cue = 1, name = "Intro",  command = "Go+" },
        { time = 12.25, cue = 2, name = "Drop",   command = "Go+" },
      },
    },
  },
}
]]

local function section_2_files(library_dir)
  section(2, "Reading and writing files")

  kv("library folder", library_dir)
  kv("path separator in use", path_sep)
  kv("report file", output_path)

  sub("A data file next to the plugin, loaded with loadfile")

  -- Where the plugin itself lives. Several candidates, because which folder
  -- MA3 hands out for plugins is one of the open questions.
  local plugin_dirs = {}
  local function add_dir(dir)
    if type(dir) == "string" and dir ~= "" then
      dir = dir:gsub("[/\\]+$", "")
      for i = 1, #plugin_dirs do
        if plugin_dirs[i] == dir then return end
      end
      plugin_dirs[#plugin_dirs + 1] = dir
    end
  end
  add_dir(library_dir)
  if type(GetPath) == "function" then
    pcall(function()
      if type(Enums) == "table" and type(Enums.PathType) == "table" then
        for _, key in ipairs({ "Library", "GrandMA3Library", "PluginLibrary", "Showfiles" }) do
          if Enums.PathType[key] ~= nil then
            add_dir(GetPath(Enums.PathType[key]))
          end
        end
      end
    end)
  end
  if library_dir then
    add_dir(library_dir .. path_sep .. "plugins")
    add_dir(library_dir .. path_sep .. "datapools" .. path_sep .. "plugins")
  end

  local data_path = nil
  for i = 1, #plugin_dirs do
    local candidate = plugin_dirs[i] .. path_sep .. "steelblue_probe_data.lua"
    local exists = nil
    if type(FileExists) == "function" then
      local ok, value = pcall(FileExists, candidate)
      exists = ok and value or nil
    end
    wf("    candidate %-60s FileExists -> %s", candidate, S(exists))
    if exists == true and data_path == nil then
      data_path = candidate
    end
  end

  if data_path == nil and library_dir then
    -- First run: write the example next to the report so the next run finds it.
    data_path = library_dir .. path_sep .. "steelblue_probe_data.lua"
    w("    none of the candidates existed -- writing the example file now")
    local ok_write = try("io.open(data_path, 'w')", function()
      local file, err = io.open(data_path, "w")
      if not file then error(S(err), 0) end
      file:write(DATA_EXAMPLE)
      file:close()
      return "written"
    end)
    if not ok_write then
      data_path = nil
    end
  end

  kv("data file used", data_path)

  if data_path then
    if type(FileExists) == "function" then
      try("FileExists(data_path)", FileExists, data_path)
    end
    local ok_chunk, chunk, load_err = try("loadfile(data_path)", loadfile, data_path)
    if ok_chunk and type(chunk) == "function" then
      local ok_value, value = try("chunk()", chunk)
      if ok_value and type(value) == "table" then
        kv("framerate", value.framerate)
        kv("offset", value.offset)
        kv("#tracks", value.tracks and #value.tracks or nil)
        if value.tracks and value.tracks[1] then
          local track = value.tracks[1]
          kv("track[1].name", track.name)
          kv("track[1].sequence", track.sequence)
          kv("track[1].#events", track.events and #track.events or nil)
          if track.events and track.events[1] then
            kv("track[1].events[1].time", track.events[1].time)
            kv("track[1].events[1].cue", track.events[1].cue)
            kv("track[1].events[1].name", track.events[1].name)
            kv("track[1].events[1].command", track.events[1].command)
          end
        end
      end
    else
      kv("loadfile error", load_err)
    end
    try("dofile(data_path)", dofile, data_path)
  end

  sub("io.open outside the library folder -- is Lua sandboxed?")
  if type(io) ~= "table" then
    w("    no io library, nothing to test")
  else
    if library_dir then
      local escape = library_dir .. path_sep .. ".." .. path_sep .. "steelblue_probe_escape.txt"
      local wrote = try("io.open(<library>/../steelblue_probe_escape.txt, 'w')", function()
        local file, err = io.open(escape, "w")
        if not file then error(S(err), 0) end
        file:write("steelblue probe\n")
        file:close()
        return "written"
      end)
      if wrote then
        try("read it back", function()
          local file = io.open(escape, "r")
          if not file then error("could not reopen", 0) end
          local text = file:read("*a")
          file:close()
          return text
        end)
        if type(os) == "table" and type(os.remove) == "function" then
          try("os.remove(escape file)", os.remove, escape)
        end
      end
    end
    if EXTERNAL_FILE ~= "" then
      try("io.open(EXTERNAL_FILE, 'r')", function()
        local file, err = io.open(EXTERNAL_FILE, "r")
        if not file then error(S(err), 0) end
        local text = file:read(200)
        file:close()
        return S(text)
      end)
    else
      w("    EXTERNAL_FILE is empty -- set it at the top of this file to test an")
      w("    absolute path outside the MA3 folders (a file on the desktop).")
    end
  end
end

-- Walks Root() down to a pool. Two routes: the long address the conductor
-- assumed, and DataPool(), which published timecode plugins actually use.
local function find_pool(root, pool_name)
  local short = nil
  if type(DataPool) == "function" then
    pcall(function()
      local pool = DataPool()
      if pool ~= nil then
        short = index_quiet(pool, pool_name)
      end
    end)
  end
  if root == nil then
    if short ~= nil then
      return short, "DataPool()." .. pool_name
    end
    return nil, "Root() gave nothing and DataPool() did not help"
  end
  -- The long route, one step at a time, so a broken link can be named.
  local long, stopped_at = nil, nil
  local show_data = index_quiet(root, "ShowData")
  if show_data == nil then
    show_data = get_quiet(root, "Get", "ShowData")
  end
  if show_data == nil then
    stopped_at = "Root().ShowData is nil"
  else
    local data_pools = index_quiet(show_data, "DataPools")
    if data_pools == nil then
      stopped_at = "Root().ShowData.DataPools is nil"
    else
      local default = index_quiet(data_pools, "Default") or index_quiet(data_pools, 1)
      if default == nil then
        stopped_at = "DataPools.Default is nil"
      else
        long = index_quiet(default, pool_name)
        if long == nil then
          stopped_at = "DataPools.Default." .. pool_name .. " is nil"
        end
      end
    end
  end

  if long ~= nil then
    local same = (short ~= nil) and (S(short) == S(long))
    return long, string.format("Root().ShowData.DataPools.Default.%s (DataPool() route: %s)",
      pool_name, short == nil and "no handle" or (same and "same handle" or "DIFFERENT handle"))
  end
  if short ~= nil then
    return short, "DataPool()." .. pool_name .. " -- the long route failed: " .. S(stopped_at)
  end
  return nil, S(stopped_at)
end

-- Finds the child whose number matches. MA3 pool indexes and displayed
-- numbers need not agree, so match on No first and fall back to position.
local function child_by_number(pool, number)
  local kids = select(1, children_of(pool))
  for i = 1, #kids do
    local child = kids[i]
    local no = index_quiet(child, "no")
    if no == nil then
      no = get_quiet(child, "Get", "No")
    end
    if no ~= nil and tostring(no) == tostring(number) then
      return child, "matched No"
    end
  end
  local direct = index_quiet(pool, number)
  if direct ~= nil then
    return direct, "pool[" .. S(number) .. "]"
  end
  return nil, "no child with that number"
end

local function section_3_object_model(root)
  section(3, "Object model: timecodes and sequences")

  local timecodes, why = find_pool(root, "Timecodes")
  kv("Timecodes pool", timecodes ~= nil and handle_label(timecodes) or "nil")
  kv("  route", why)
  if timecodes == nil then
    sub("Root() itself, so the next run knows where to walk instead")
    describe(root, "Root()", { dump = false, child_limit = 30 })
    return nil, nil
  end

  describe(timecodes, "Timecodes pool", { child_limit = 40 })

  local timecode, how = child_by_number(timecodes, TIMECODE_NO)
  kv("timecode " .. TIMECODE_NO .. " found by", how)
  if timecode ~= nil then
    describe(timecode, "Timecode " .. TIMECODE_NO, { child_limit = 20 })

    sub("Walking down: TrackGroup -> Track -> TimeRange -> Event")
    local groups = select(1, children_of(timecode))
    for gi = 1, math.min(#groups, 3) do
      local group = groups[gi]
      describe(group, string.format("TrackGroup [%d]", gi), { pairs = false, child_limit = 20 })
      local tracks = select(1, children_of(group))
      for ti = 1, math.min(#tracks, 3) do
        local track = tracks[ti]
        describe(track, string.format("Track [%d.%d]", gi, ti), { pairs = false, child_limit = 20 })
        local ranges = select(1, children_of(track))
        for ri = 1, math.min(#ranges, 2) do
          local range = ranges[ri]
          describe(range, string.format("Track child [%d.%d.%d]", gi, ti, ri),
            { pairs = false, child_limit = 20 })
          local events = select(1, children_of(range))
          for ei = 1, math.min(#events, 3) do
            describe(events[ei], string.format("Event [%d.%d.%d.%d]", gi, ti, ri, ei),
              { pairs = false, children = false, dump = false })
          end
        end
      end
    end
  end

  sub("Sequences")
  local sequences = find_pool(root, "Sequences")
  kv("Sequences pool", sequences ~= nil and handle_label(sequences) or "nil")
  local sequence = nil
  if sequences ~= nil then
    list_children(sequences, "    ", 40)
    sequence = child_by_number(sequences, SEQUENCE_NO)
    if sequence ~= nil then
      describe(sequence, "Sequence " .. SEQUENCE_NO, { pairs = false, child_limit = 10 })
      sub("Cues of sequence " .. SEQUENCE_NO)
      local cue_container = index_quiet(sequence, "Cues") or sequence
      local cues = select(1, children_of(cue_container))
      wf("    %d cue children", #cues)
      for i = 1, math.min(#cues, 40) do
        local cue = cues[i]
        wf("    cue [%d] no=%s name=%s class=%s", i,
          S(index_quiet(cue, "no") or get_quiet(cue, "Get", "No")),
          S(index_quiet(cue, "name") or get_quiet(cue, "Get", "Name")),
          S(get_quiet(cue, "GetClass")))
      end
      if cues[1] ~= nil then
        describe(cues[1], "First cue in detail", { pairs = false, children = true, dump = false })
      end
    end
  end

  sub("Free functions that name objects directly")
  try("SelectedTimecode()", SelectedTimecode)
  try("SelectedSequence()", SelectedSequence)
  try("CurrentUser()", CurrentUser)
  try("DataPool()", DataPool)
  try("ShowData()", ShowData)

  return timecode, sequence
end

-- Everything the probe creates is remembered here so section 9 can undo it.
--
-- Delete and Remove take the PARENT plus a 1-based child index, not the child
-- itself, so the parent has to be remembered alongside the handle.
local created = { handles = {}, commands = {} }

-- The track group number section 5 stores into, so section 9 can delete it.
local probe_group_no = nil

local function remember_handle(handle, note, parent)
  if handle ~= nil then
    created.handles[#created.handles + 1] = { handle = handle, note = note, parent = parent }
  end
end

-- The child's 1-based position inside its parent, found by comparing handles
-- rather than trusting Index(), whose base is one of the open questions.
local function position_in_parent(parent, handle)
  if parent == nil or handle == nil then
    return nil
  end
  local kids = select(1, children_of(parent))
  for i = 1, #kids do
    if kids[i] == handle or S(kids[i]) == S(handle) then
      return i
    end
  end
  return nil
end

local function section_4_object_api(timecode, sequence)
  section(4, "Creating content through the object API")

  if timecode == nil then
    w("  no timecode handle, nothing to create -- see section 3")
    return nil
  end

  -- Documented shapes (bambinito mirror of GetObjApiDescriptor):
  --   Append(handle[, class[, undo[, count]]])      -> child handle
  --   Insert(handle, child_index[, class[, undo]])  -> child handle
  --   Create(handle, child_index[, class[, undo]])  -> child handle
  -- Only the first one is a plain "add at the end", so it is tried first.
  local function append_child(parent, class, note)
    local before = select(3, children_of(parent))
    local ok, value = try(string.format("parent:Append(%q)", S(class)), function()
      return parent:Append(class)
    end)
    if not ok or value == nil then
      -- Acquire is what published timecode plugins use for TimeRange and
      -- CmdSubTrack: "give me the child of that class, make one if needed".
      ok, value = try(string.format("parent:Acquire(%q)", S(class)), function()
        return parent:Acquire(class)
      end)
    end
    if not ok or value == nil then
      ok, value = try("parent:Append()  -- no class argument", function()
        return parent:Append()
      end)
    end
    if not ok or value == nil then
      local index = (tonumber(before) or 0) + 1
      ok, value = try(string.format("parent:Insert(%d, %q)", index, S(class)), function()
        return parent:Insert(index, class)
      end)
    end
    if not ok or value == nil then
      local index = (tonumber(before) or 0) + 1
      ok, value = try(string.format("parent:Create(%d, %q)", index, S(class)), function()
        return parent:Create(index, class)
      end)
    end
    local after = select(3, children_of(parent))
    wf("    child count %s -> %s", S(before), S(after))
    if ok and value ~= nil then
      remember_handle(value, note, parent)
      return value
    end
    return nil
  end

  sub("Append a TrackGroup")
  local group = append_child(timecode, "TrackGroup", "TrackGroup on timecode " .. TIMECODE_NO)
  kv("TrackGroup handle", group and handle_label(group) or "nil")

  if group == nil then
    w("  without a TrackGroup the object route stops here; section 5 tries the command line")
    return nil
  end
  describe(group, "New TrackGroup", { pairs = false, child_limit = 10, dump = false })

  sub("Append a Track inside it")
  local track = append_child(group, "Track", "Track in the new TrackGroup")
  kv("Track handle", track and handle_label(track) or "nil")
  if track == nil then
    return group
  end

  try("track:Set('Name', 'steelblue probe')", function()
    return track:Set("Name", "steelblue probe")
  end)

  sub("Point the track at sequence " .. SEQUENCE_NO)
  -- Which property carries the assignment is exactly what this asks. Set() is
  -- documented as taking a STRING value, so the string form is tried first and
  -- the handle form second -- if the handle form works, the importer is simpler.
  local targets = { "Target", "Object", "Assignment", "Sequence", "Destination" }
  for i = 1, #targets do
    local property = targets[i]
    try(string.format("track:Set(%q, \"Sequence %d\")", property, SEQUENCE_NO), function()
      return track:Set(property, "Sequence " .. SEQUENCE_NO)
    end)
    kv("  read back " .. property, get_quiet(track, "Get", property))
    try(string.format("track:Set(%q, <sequence handle>)", property), function()
      return track:Set(property, sequence)
    end)
    kv("  read back " .. property, get_quiet(track, "Get", property))
    if EDIT_ROLE ~= nil then
      kv("  read back " .. property .. " (Roles.Edit)", get_quiet(track, "Get", property, EDIT_ROLE))
    end
  end

  sub("The track after the assignment attempts")
  describe(track, "New Track", { pairs = false, child_limit = 10 })

  sub("Append an Event")
  local event_parent = track
  local kids = select(1, children_of(track))
  if #kids > 0 then
    wf("    the track already has %d child/children -- trying the first one as the event parent", #kids)
    event_parent = kids[1]
    describe(event_parent, "Track child (TimeRange?)", { pairs = false, children = false, dump = false })
  end

  local event = nil
  local event_classes = { "Event", "TimecodeEvent", "CmdEvent" }
  for i = 1, #event_classes do
    if event == nil then
      event = append_child(event_parent, event_classes[i], "Event (" .. event_classes[i] .. ")")
    end
  end
  kv("Event handle", event and handle_label(event) or "nil")
  if event ~= nil then
    describe(event, "New Event, untouched", { pairs = false, children = false, dump = false })
  end

  return group, track, event
end

local function section_5_command_line(timecode, sequence)
  section(5, "Creating content from the command line")

  if type(Cmd) ~= "function" then
    w("  Cmd is not available")
    return
  end

  local function run(command)
    created.commands[#created.commands + 1] = command
    try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
  end

  -- The chain below is the one a shipping REAPER->MA3 bridge uses
  -- (github.com/mittim88/TCHelper). Cmd answers "Ok", "Syntax Error" or
  -- "Illegal Command", so the return value alone already grades each line.
  --
  -- Address shape: Timecode . TrackGroup . Track . TimeRange . SubTrack . Event
  -- A TimeRange can hold a CmdSubTrack or a FaderSubTrack, which is why the
  -- sub-track line needs the Type keyword.
  --
  -- CG is the track group number the probe works in: one past whatever the
  -- timecode already has, so no existing group is ever addressed by accident.
  local CG = 1
  if timecode ~= nil then
    CG = (tonumber(select(3, children_of(timecode))) or 0) + 1
  end
  probe_group_no = CG
  kv("track group the probe writes into", CG)

  sub("Does Cmd answer at all?")
  run("Echo \"steelblue probe\"")

  sub("Track group and track")
  run(string.format("Store TC %d.%d \"steelblue probe\"", TIMECODE_NO, CG))
  run(string.format("Store TC %d.%d.1", TIMECODE_NO, CG))
  run(string.format("Assign Sequence %d at TC %d.%d.1", SEQUENCE_NO, TIMECODE_NO, CG))

  sub("Time range and command sub-track")
  run(string.format("Store TC %d.%d.1.1", TIMECODE_NO, CG))
  run(string.format("Store Type \"CmdSubTrack\" Timecode %d.%d.1.1.1", TIMECODE_NO, CG))

  sub("An event, and its three properties")
  run(string.format("Store TC %d.%d.1.1.1.1", TIMECODE_NO, CG))
  run(string.format("Set TC %d.%d.1.1.1.1 Property \"time\" 12.437", TIMECODE_NO, CG))
  run(string.format("Set TC %d.%d.1.1.1.1 Property \"token\" \"goto\"", TIMECODE_NO, CG))
  run(string.format("Set TC %d.%d.1.1.1.1 Property \"Status\" \"On\"", TIMECODE_NO, CG))
  run(string.format(
    "Set TC %d.%d.1.1.1.1 Property \"cuedestination\" \"ShowData.DataPools.Default.Sequences.%d.1\"",
    TIMECODE_NO, CG, SEQUENCE_NO))

  sub("A second event, to see whether the numbering is ours to choose")
  run(string.format("Store TC %d.%d.1.1.1.5", TIMECODE_NO, CG))
  run(string.format("Set TC %d.%d.1.1.1.5 Property \"time\" 30.5", TIMECODE_NO, CG))
  run(string.format("Set TC %d.%d.1.1.1.5 Property \"token\" \"Go+\"", TIMECODE_NO, CG))

  sub("Long keyword spellings, in case the short ones are the problem")
  run(string.format("Store Timecode %d.%d.2", TIMECODE_NO, CG))
  run(string.format("Label Timecode %d.%d.2 \"steelblue probe track 2\"", TIMECODE_NO, CG))

  sub("The timecode after the command line had its turn")
  if timecode ~= nil then
    describe(timecode, "Timecode " .. TIMECODE_NO .. " after Cmd", { pairs = false, child_limit = 20 })
    local groups = select(1, children_of(timecode))
    for gi = 1, math.min(#groups, 4) do
      describe(groups[gi], "TrackGroup [" .. gi .. "] after Cmd",
        { pairs = false, child_limit = 20, dump = false })
      local tracks = select(1, children_of(groups[gi]))
      for ti = 1, math.min(#tracks, 4) do
        describe(tracks[ti], string.format("Track [%d.%d] after Cmd", gi, ti),
          { pairs = false, child_limit = 20, dump = false })
      end
    end
  end
end

local function section_6_cues(root, sequence)
  section(6, "Creating and naming cues")

  if type(Cmd) ~= "function" then
    w("  Cmd is not available")
    return
  end

  local function run(command)
    created.commands[#created.commands + 1] = command
    try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
  end

  local function cue_list(title)
    sub(title)
    local sequences = find_pool(root, "Sequences")
    if sequences == nil then
      w("    no sequence pool")
      return
    end
    local seq = child_by_number(sequences, SEQUENCE_NO)
    if seq == nil then
      w("    sequence " .. SEQUENCE_NO .. " not found")
      return
    end
    local container = index_quiet(seq, "Cues") or seq
    local cues = select(1, children_of(container))
    wf("    %d cues", #cues)
    for i = 1, math.min(#cues, 60) do
      local cue = cues[i]
      wf("    cue [%d] no=%s name=%s", i,
        S(index_quiet(cue, "no") or get_quiet(cue, "Get", "No")),
        S(index_quiet(cue, "name") or get_quiet(cue, "Get", "Name")))
    end
  end

  cue_list("Cues before anything is stored")

  -- The 2.3 Store page spells the option /NoConfirmation; /NoConfirm is the
  -- abbreviation the command line normally accepts. Both are tried once, and
  -- the return value says which one this build likes.
  sub("Store an empty cue with an empty programmer")
  run(string.format("Store Sequence %d Cue %d /NoConfirmation", SEQUENCE_NO, CUE_FIRST))
  run(string.format("Store Sequence %d Cue %d /NoConfirm", SEQUENCE_NO, CUE_FIRST + 1))
  run(string.format("Store Sequence %d Cue %d", SEQUENCE_NO, CUE_FIRST + 2))
  cue_list("Cues after the three Store calls")

  sub("Label them")
  for i = 0, CUE_COUNT - 1 do
    run(string.format("Label Sequence %d Cue %d \"Probe %d\"",
      SEQUENCE_NO, CUE_FIRST + i, CUE_FIRST + i))
  end
  cue_list("Cues after labelling")

  sub("Store again over an EXISTING cue -- is the name lost?")
  -- This is the one that decides the importer's cue rule: existing cues must
  -- survive untouched while missing ones are created empty and named.
  run(string.format("Store Sequence %d Cue %d /NoConfirmation", SEQUENCE_NO, CUE_FIRST))
  cue_list("After a plain second Store on cue " .. CUE_FIRST)
  run(string.format("Store Sequence %d Cue %d /Merge /NoConfirmation", SEQUENCE_NO, CUE_FIRST))
  cue_list("After Store /Merge on cue " .. CUE_FIRST .. " -- its name is the answer")
end

local function section_7_time(timecode, event)
  section(7, "Time: unit, framerate, how a value is set")

  if timecode ~= nil then
    sub("Framerate of timecode " .. TIMECODE_NO)
    -- The 2.3 timecode settings page calls the property FrameReadout, with
    -- values Default / Seconds / 24 fps / 25 fps / 30 fps / 60 fps. The others
    -- are the spellings one would guess, kept so a wrong guess is visible.
    local names = { "FrameReadout", "Timedisplayformat", "Framerate", "FrameRate",
                    "Rate", "Duration", "TCSlot" }
    for i = 1, #names do
      local value, how = read_property(timecode, names[i])
      kv(names[i] .. " (" .. S(how) .. ")", value)
    end
  end

  if event == nil then
    w("")
    w("  no event handle from section 4, so setting a time cannot be tested here")
    return
  end

  sub("Setting the event time -- number first, then a timecode string")
  -- A posted show-file dump shows Time="1.04", i.e. seconds as a float, and a
  -- REAPER bridge writes raw REAPER seconds. Both forms are tried anyway: what
  -- comes back out is what the importer has to write in.
  local attempts = {
    { label = "number 12.437", value = 12.437 },
    { label = "integer 12", value = 12 },
    { label = "string \"12.437\"", value = "12.437" },
    { label = "string \"00:00:12.50\"", value = "00:00:12.50" },
    { label = "string \"00:00:12:15\"", value = "00:00:12:15" },
  }
  local properties = { "Time", "TimeCode", "Position", "Start" }
  for p = 1, #properties do
    local property = properties[p]
    for a = 1, #attempts do
      local attempt = attempts[a]
      try(string.format("event:Set(%q, %s)", property, attempt.label), function()
        return event:Set(property, attempt.value)
      end)
      local value, how = read_property(event, property)
      wf("      read back %s = %s  (%s, via %s)", property, S(value), type(value), S(how))
    end
  end

  sub("Setting the token and the target cue")
  -- Token names confirmed from public sources: ExecToken="Flash" in a posted
  -- show-file dump (forum thread 5079) and the lowercase spellings goto / top /
  -- temp / flash in github.com/mittim88/TCHelper. Go+ and Goto are the ones
  -- that can carry a cue destination, which is what the importer needs.
  local tokens = { "Go+", "Go-", "Goto", "goto", "Top", "Flash", "On", "Off", "Temp", "Swap" }
  for i = 1, #tokens do
    try(string.format("event:Set('Token', %q)", tokens[i]), function()
      return event:Set("Token", tokens[i])
    end)
    local value, how = read_property(event, "Token")
    kv("  read back Token (" .. S(how) .. ")", value)
  end

  sub("The cue destination -- the address form and the plain number")
  local destination = string.format("ShowData.DataPools.Default.Sequences.%d.1", SEQUENCE_NO)
  for _, property in ipairs({ "CueDestination", "Cue", "CueNumber", "Target", "Destination" }) do
    try(string.format("event:Set(%q, %q)", property, destination), function()
      return event:Set(property, destination)
    end)
    kv("  read back " .. property, select(1, read_property(event, property)))
    try(string.format("event:Set(%q, %d)", property, CUE_FIRST), function()
      return event:Set(property, CUE_FIRST)
    end)
    kv("  read back " .. property, select(1, read_property(event, property)))
  end
  try("event:Set('Status', 'On')  -- tokens with a status flag need it", function()
    return event:Set("Status", "On")
  end)

  sub("The event with everything the probe could set")
  describe(event, "Event after Set", { pairs = false, children = false, dump = false })
end

local function section_8_ui(display_handle)
  section(8, "MessageBox with selectors, states and inputs")

  if type(MessageBox) ~= "function" then
    w("  MessageBox is not available")
    return
  end

  local request = {
    title = "steelblue probe -- UI test",
    message = "Pick anything, tick anything, type anything.\n" ..
              "This box exists only to show what MessageBox hands back.",
    display = display_handle,
    commands = {
      { value = 1, name = "OK" },
      { value = 0, name = "Cancel" },
    },
    selectors = {
      {
        name = "Timecode",
        selectedValue = 1,
        values = { ["Timecode 1"] = 1, ["Timecode 2"] = 2, ["Timecode 3"] = 3 },
        type = 0,
      },
      {
        name = "Sequence",
        selectedValue = 1,
        values = { ["Sequence 1"] = 1, ["Sequence 2"] = 2, ["Sequence 3"] = 3 },
        type = 0,
      },
    },
    states = {
      { name = "Import track A", state = true },
      { name = "Import track B", state = false },
      { name = "Import track C", state = true },
    },
    inputs = {
      -- The typed signature spells these whiteFilter/blackFilter, the manual
      -- page spells them lowercase. Both are sent so the box cannot be wrong.
      {
        name = "Offset",
        value = "0",
        whiteFilter = "0123456789.:-",
        whitefilter = "0123456789.:-",
        maxTextLength = 16,
      },
    },
  }

  sub("What the probe sent")
  wf("    %d commands, %d selectors, %d states, %d inputs",
    #request.commands, #request.selectors, #request.states, #request.inputs)

  local ok, result = try("MessageBox(request)", MessageBox, request)
  if not ok then
    w("    the call failed -- the table shape above is wrong for this version")
    return
  end

  sub("What came back")
  kv("type(result)", type(result))
  kv("tostring(result)", result)
  if type(result) == "table" then
    -- Documented shape: success, result, and inputs/states/selectors keyed by
    -- the element NAME rather than by position. Both are printed, because the
    -- importer's overview screen depends on which is true.
    kv("result.success", result.success)
    kv("result.result", result.result)
    kv("result.selectors['Timecode']", result.selectors and result.selectors["Timecode"])
    kv("result.selectors['Sequence']", result.selectors and result.selectors["Sequence"])
    kv("result.states['Import track A']", result.states and result.states["Import track A"])
    kv("result.inputs['Offset']", result.inputs and result.inputs["Offset"])
    w("    the whole table:")
  end
  if type(result) == "table" then
    local function walk(t, indent, depth)
      if depth > 4 then
        wf("%s...", indent)
        return
      end
      local keys = {}
      for key in pairs(t) do
        keys[#keys + 1] = key
      end
      table.sort(keys, function(a, b) return S(a) < S(b) end)
      for i = 1, #keys do
        local key = keys[i]
        local value = t[key]
        if type(value) == "table" then
          wf("%s%s = {", indent, S(key))
          walk(value, indent .. "  ", depth + 1)
          wf("%s}", indent)
        else
          wf("%s%-20s = %s  (%s)", indent, S(key), S(value), type(value))
        end
      end
    end
    walk(result, "    ", 1)
  end

  sub("Other input helpers, only tested for existence")
  kv("TextInput", type(TextInput))
  kv("Confirm", type(Confirm))
  kv("PopupInput", type(PopupInput))
  kv("ObjectList", type(ObjectList))
end

local function section_9_cleanup(root)
  section(9, "Cleaning up everything the probe created")

  sub("Cues " .. CUE_FIRST .. "-" .. (CUE_FIRST + CUE_COUNT - 1))
  if type(Cmd) == "function" then
    for i = 0, CUE_COUNT - 1 do
      local command = string.format("Delete Sequence %d Cue %d /NoConfirmation",
        SEQUENCE_NO, CUE_FIRST + i)
      try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
    end
  end

  sub("The track group the command line created")
  -- This one goes FIRST, and on purpose. Track groups are a list, so deleting
  -- the one the object API appended renumbers everything behind it and the
  -- address below would then point at the wrong group -- or at nothing.
  if type(Cmd) == "function" and probe_group_no ~= nil then
    local command = string.format("Delete TC %d.%d /NoConfirmation", TIMECODE_NO, probe_group_no)
    local ok, answer = try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
    if not ok or S(answer) ~= "Ok" then
      command = string.format("Delete Timecode %d.%d /NoConfirmation", TIMECODE_NO, probe_group_no)
      try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
    end
  else
    w("    section 5 never picked a track group number, nothing to delete")
  end

  sub("Handles created through the object API, newest first")
  -- Delete(parent, child_index) and Remove(parent, child_index) both take a
  -- 1-based index on the PARENT. Deleting the parent removes its children with
  -- it, so walking newest first means the inner entries are usually gone
  -- already -- a "not found any more" line here is success, not a failure.
  for i = #created.handles, 1, -1 do
    local entry = created.handles[i]
    wf("    %s", S(entry.note))
    kv("      Index() of the child", get_quiet(entry.handle, "Index"))
    local position = position_in_parent(entry.parent, entry.handle)
    kv("      position inside the parent (1-based)", position)
    if entry.parent == nil then
      w("      no parent remembered, cannot delete by index")
    elseif position == nil then
      w("      not a child of that parent any more -- nothing left to delete")
    else
      local ok = try(string.format("parent:Delete(%d)", position), function()
        return entry.parent:Delete(position)
      end)
      if not ok then
        try(string.format("parent:Remove(%d)", position), function()
          return entry.parent:Remove(position)
        end)
      end
      kv("      still a child?", position_in_parent(entry.parent, entry.handle) ~= nil)
    end
  end

  sub("What the timecode looks like afterwards")
  local timecodes = find_pool(root, "Timecodes")
  if timecodes ~= nil then
    local timecode = child_by_number(timecodes, TIMECODE_NO)
    if timecode ~= nil then
      list_children(timecode, "    ", 20)
    end
  end

  sub("What the sequence looks like afterwards")
  local sequences = find_pool(root, "Sequences")
  if sequences ~= nil then
    local sequence = child_by_number(sequences, SEQUENCE_NO)
    if sequence ~= nil then
      local container = index_quiet(sequence, "Cues") or sequence
      local cues = select(1, children_of(container))
      wf("    %d cues left", #cues)
      for i = 1, math.min(#cues, 60) do
        wf("    cue [%d] no=%s name=%s", i,
          S(index_quiet(cues[i], "no") or get_quiet(cues[i], "Get", "No")),
          S(index_quiet(cues[i], "name") or get_quiet(cues[i], "Get", "Name")))
      end
    end
  end

  sub("Commands this run sent, so anything left over can be undone by hand")
  for i = 1, #created.commands do
    wf("    %s", S(created.commands[i]))
  end
end

-- ------------------------------------------------------------------- main

local function run_section(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    raw("")
    wf("!! SECTION %s ABORTED: %s", S(label), S(err))
  end
  local flushed, why = flush()
  if not flushed and output_path ~= nil then
    say("steelblue probe: could not write the report -- " .. S(why))
  end
  return ok
end

local function main(display_handle, argument)
  report_lines = {}
  report_count = 0
  created = { handles = {}, commands = {} }

  raw("steelblue studios -- grandMA3 probe 1")
  raw("=====================================")
  wf("probe version  %s", PROBE_VERSION)
  wf("timecode       %d", TIMECODE_NO)
  wf("sequence       %d", SEQUENCE_NO)
  wf("scratch cues   %d-%d", CUE_FIRST, CUE_FIRST + CUE_COUNT - 1)
  wf("display handle %s", S(display_handle))
  wf("argument       %s", S(argument))
  if type(os) == "table" and type(os.date) == "function" then
    local ok, stamp = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    if ok then
      wf("run at         %s", S(stamp))
    end
  end

  local library_dir, path_source
  output_path, library_dir, path_source = pick_output_path()
  wf("report path    %s", S(output_path))
  wf("path came from %s", S(path_source))

  say("steelblue probe: report goes to " .. S(output_path))

  -- The one question the probe does ask, because writing into the wrong show
  -- would be rude.
  if type(MessageBox) == "function" then
    local ok, answer = pcall(MessageBox, {
      title = "steelblue probe",
      message = string.format(
        "The probe runs in timecode %d and sequence %d of THIS show,\n" ..
        "and it stores cues %d-%d. Use a throwaway show.\n\n" ..
        "It writes its findings to:\n%s\n\nOK?",
        TIMECODE_NO, SEQUENCE_NO, CUE_FIRST, CUE_FIRST + CUE_COUNT - 1, S(output_path)),
      display = display_handle,
      commands = {
        { value = 1, name = "OK" },
        { value = 0, name = "Cancel" },
      },
    })
    -- The documented return is { success = boolean, result = integer, ... },
    -- where result is the value of the command that was tapped.
    wf("confirmation   ok=%s answer=%s", S(ok), S(answer))
    if ok and type(answer) == "table" then
      wf("               success=%s result=%s", S(answer.success), S(answer.result))
      if answer.success == false or answer.result == 0 then
        raw("")
        raw("Cancelled at the confirmation box -- nothing was created.")
        flush()
        say("steelblue probe: cancelled")
        return
      end
    end
  else
    raw("no MessageBox available -- running without the confirmation box")
  end

  local root = nil
  run_section("1", function() root = section_1_environment() end)
  if root == nil and type(Root) == "function" then
    pcall(function() root = Root() end)
  end

  -- Section 1 enumerates every path type, so a second attempt can succeed
  -- where the early guess came back empty.
  if output_path == nil then
    output_path, library_dir, path_source = pick_output_path()
    if output_path then
      wf("report path found on the second attempt: %s (%s)", S(output_path), S(path_source))
      say("steelblue probe: report goes to " .. S(output_path))
    end
  end

  run_section("2", section_2_files, library_dir)

  local timecode, sequence = nil, nil
  run_section("3", function() timecode, sequence = section_3_object_model(root) end)

  local group, track, event = nil, nil, nil
  run_section("4", function() group, track, event = section_4_object_api(timecode, sequence) end)

  run_section("5", section_5_command_line, timecode, sequence)
  run_section("6", section_6_cues, root, sequence)
  run_section("7", section_7_time, timecode, event)
  run_section("8", section_8_ui, display_handle)
  run_section("9", section_9_cleanup, root)

  raw("")
  raw(string.rep("=", 78))
  raw("PROBE DONE -- send this file to the conductor.")
  wf("file: %s", S(output_path))
  raw(string.rep("=", 78))

  local flushed, why = flush()
  if flushed then
    say("steelblue probe: done, report written to " .. S(output_path))
  else
    say("steelblue probe: done, but the report could NOT be written -- " .. S(why))
    say("reason: " .. S(why))
  end
end

return main

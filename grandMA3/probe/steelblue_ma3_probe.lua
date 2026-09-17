-- steelblue_ma3_probe.lua -- grandMA3 probe for the planned REAPER -> MA3 marker importer.
--
-- WHAT THIS IS
--   A reconnaissance plugin. It answers the questions the importer cannot be
--   written without, and it answers them on the real console instead of from
--   documentation.
--
-- WHAT RUN 2 ALREADY ANSWERED (2026-09-17, MA3 2.3.2.0 onPC, Mac)
--   Lua is 5.4. io / os / loadfile / dofile are all present and NOT sandboxed.
--   GetPath(Enums.PathType.Library) is ~/MALightingTechnology/gma3_library.
--   MessageBox returns { success, result, selectors[name], states[name],
--   inputs[name] }, where result is the VALUE of the button that was tapped.
--   Cmd answers "OK" / "Illegal object" / "Illegal property". The command chain
--   Store TC 1.1 -> Store TC 1.1.1 -> Assign Sequence 1 at TC 1.1.1 ->
--   Store TC 1.1.1.1 -> Store Type "CmdSubTrack" Timecode 1.1.1.1.1 ->
--   Store TC 1.1.1.1.1.1 -> Set ... Property "time"/"token"/"cuedestination"
--   is accepted end to end.
--
-- WHY THERE IS A VERSION 1.1 -- THE THREE THINGS RUN 2 GOT WRONG OR MISSED
--   1. IT READ THE WRONG DATA POOL. Every object lookup went through
--      Root().ShowData.DataPools.Default, which is pool 1. Tobi's show works in
--      pool 2 (DataPool() -> "DataPool 2"). So the timecode was never found,
--      sections 4 and 7 never ran, and the cue list stayed empty while the
--      command line was happily storing cues in the pool nobody was looking at.
--      Version 1.1 goes through DataPool() everywhere and only LOGS what the
--      Default route would have given, as a comparison.
--   2. THE CONSOLE PICKS THE EVENT NUMBER, NOT US. "Store TC 1.1.1.1.1.5" was
--      answered with OK, but "Set TC 1.1.1.1.1.5 ..." came back "Illegal
--      object" -- the event had been created under a different number. Version
--      1.1 therefore lists the children of the CmdSubTrack before and after
--      every Store and works out which child is new, instead of assuming.
--   3. NOBODY KNOWS WHERE A REAPER GUID COULD LIVE. Section 8 now dumps every
--      level of the timecode tree and tries to write a marker string into every
--      text-shaped property it finds, so the importer knows whether it can
--      recognise its own events again on the next import.
--
-- WHAT IT TOUCHES
--   One timecode and one sequence of a THROWAWAY show, plus cues 990-992 of
--   that sequence, all in the CURRENT data pool. Section 9 removes everything
--   it created. It writes two files into the library folder: the report and, on
--   the first run, an example data file.
--
-- HOW IT REPORTS
--   Every step is wrapped in pcall, so a call that does not exist on this
--   version logs a line and the probe carries on. Findings go into
--   <library>/steelblue_probe.txt; the path is also printed to the System
--   Monitor. The file is rewritten after every section, so an abort still
--   leaves everything gathered so far on disk.
--
-- LUA DIALECT
--   Section 1 of run 2 printed "Lua 5.4", so 5.4 is confirmed. This file still
--   stays inside the 5.3/5.4 intersection -- no <const>, no <close>, no
--   5.4-only library call -- because steelblue modules are shared with REAPER.

local PROBE_VERSION = "1.1"

-- ---------------------------------------------------------------- settings
-- Tobi edits these numbers if his throwaway show uses different ones. The
-- plugin asks nothing; it only shows them once in a confirmation box. If the
-- timecode or the sequence does not exist in the CURRENT pool, the probe falls
-- back to the first one that does and says so in the report.

local TIMECODE_NO = 1   -- the EXISTING timecode the probe writes into
local SEQUENCE_NO = 1   -- the EXISTING sequence the probe points a track at
local CUE_FIRST   = 990 -- first scratch cue number (990, 991, 992 are used)
local CUE_COUNT   = 3

-- Optional: an absolute path to any small text file outside the MA3 folders
-- (a file on the desktop, for instance). Left empty the probe tests the
-- sandbox with files it writes itself. Example on Windows:
--   local EXTERNAL_FILE = "C:\\Users\\Tobi\\Desktop\\test.txt"
local EXTERNAL_FILE = ""

-- The string the probe tries to park on every text-shaped property it finds.
-- In the real importer this is where the REAPER marker GUID would go.
local GUID_MARK = "steelblue:11112222-3333-4444"

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

-- Run 2 answered "OK", the manual writes "Ok". Version 1.0 compared against
-- "Ok" and therefore graded every successful command as a failure -- which is
-- why cleanup fired a pointless second Delete. Compare without case.
local function cmd_ok(answer)
  return type(answer) == "string" and answer:lower() == "ok"
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

local function class_of(handle)
  if handle == nil then
    return nil
  end
  return get_quiet(handle, "GetClass")
end

local function name_of(handle)
  if handle == nil then
    return nil
  end
  local name = index_quiet(handle, "name")
  if name ~= nil and type(name) ~= "function" then
    return name
  end
  return get_quiet(handle, "Get", "Name")
end

local function number_of(handle)
  if handle == nil then
    return nil
  end
  local no = index_quiet(handle, "no")
  if no ~= nil and type(no) ~= "function" then
    return no
  end
  return get_quiet(handle, "Get", "No")
end

local function handle_label(handle)
  if handle == nil then
    return "nil"
  end
  local parts = {}
  local class = class_of(handle)
  local name = name_of(handle)
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

-- Children(handle) is the documented way and returns a plain table; Count()
-- plus Ptr() is the fallback. Which one answers is itself worth recording.
local function children_of(handle)
  if handle == nil then
    return {}, "no handle", 0
  end
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

-- One line per child, with the CLASS in it. The class is the point: a
-- TrackGroup holds a MarkerTrack next to the real Tracks, so "the first child"
-- and "the first track" are not the same thing, and the importer has to know
-- which of the two a command-line address counts.
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
    wf("%s[%d] %s  no=%s index=%s", indent, i, handle_label(child),
      S(number_of(child)), S(index_quiet(child, "index")))
  end
  return kids
end

local function dump_text(handle)
  if handle == nil then
    return nil, "no handle"
  end
  local ok, text = pcall(function() return handle:Dump() end)
  if not ok then
    return nil, S(text)
  end
  if type(text) ~= "string" or text == "" then
    return nil, "Dump() returned " .. S(text) .. " -- its text went to the System Monitor"
  end
  return text
end

local function write_dump(handle, indent)
  indent = indent or "    "
  local text, why = dump_text(handle)
  if not text then
    wf("%sDump(): %s", indent, S(why))
    return nil
  end
  wf("%sDump():", indent)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      wf("%s  %s", indent, line)
    end
  end
  return text
end

-- A Dump() lists its properties as
--     NOTE = ""
--     INDEX = "14" (Read Only)
-- Anything that is not read only and whose name reads like free text is a
-- candidate for parking the REAPER GUID on. Returned in the order the dump
-- lists them, without duplicates.
local TEXTY = { "NOTE", "COMMENT", "TEXT", "INFO", "DESCRIPTION", "TAG", "TAGS",
                "NAME", "LABEL", "USERTEXT", "SCRIBBLE", "KEYWORD" }

local function text_property_candidates(dump)
  local out, seen = {}, {}
  if type(dump) ~= "string" then
    return out
  end
  for line in (dump .. "\n"):gmatch("([^\n]*)\n") do
    local key, rest = line:match("^%s*([A-Z][A-Z0-9_]*)%s*=%s*(.*)$")
    if key and not rest:find("(Read Only)", 1, true) then
      local texty = false
      for i = 1, #TEXTY do
        if key:find(TEXTY[i], 1, true) then
          texty = true
          break
        end
      end
      if texty and not seen[key] then
        seen[key] = true
        out[#out + 1] = key
      end
    end
  end
  return out
end

-- pairs() over a handle may or may not work; run 2 says it does not
-- ("bad argument #1 to 'for iterator' (table expected, got ObjMeta)"), so it is
-- off by default now and only switched on where it might still surprise.
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

-- The full picture of one object: class, methods, properties, children, and
-- the console Dump() on top of it.
local function describe(handle, title, options)
  options = options or {}
  sub(title .. "  ->  " .. handle_label(handle))
  if handle == nil then
    w("    handle is nil, nothing to describe")
    return nil
  end
  kv("type(handle)", type(handle))
  kv("tostring(handle)", handle)
  call_method(handle, "GetClass")
  call_method(handle, "GetChildClass")
  call_method(handle, "Addr")
  call_method(handle, "ToAddr")
  if options.methods ~= false then
    w("    methods present on the handle:")
    list_methods(handle, "      ")
  end
  w("    properties that answered:")
  list_properties(handle, "      ")
  if options.pairs then
    w("    pairs() over the handle:")
    list_pairs(handle, "      ")
  end
  if options.children ~= false then
    list_children(handle, "    ", options.child_limit or 40)
  end
  if options.dump ~= false then
    return write_dump(handle, "    ")
  end
  return nil
end

-- --------------------------------------------------------------- sections

-- Run 2 printed all 263 globals and all 118 path types. Both are answered and
-- archived; repeating them would bury the new findings. Section 1 now only
-- confirms the handful the importer depends on.
local IMPORTER_GLOBALS = {
  "Root", "Cmd", "CmdIndirect", "CmdIndirectWait", "CmdObj", "Printf", "Echo",
  "ErrPrintf", "GetPath", "GetPathSeparator", "FileExists", "MessageBox",
  "TextInput", "Confirm", "PopupInput", "ObjectList", "SelectedTimecode",
  "SelectedSequence", "DataPool", "ShowData", "CurrentUser", "Version",
  "HostOS", "HostType", "Enums", "HandleToStr", "StrToHandle", "ToAddr",
  "FromAddr", "GetObject", "IsObjectValid", "DirList", "CreateDirectoryRecursive",
  "Export", "Import", "HookObjectChange", "SetVar", "GetVar",
}

local PATHS_THAT_MATTER = {
  "Library", "CustomPluginLibrary", "PluginLibrary", "UserTimecodes",
  "UserSequences", "Showfiles", "Temp", "MADir",
}

local function section_1_environment()
  section(1, "Environment: version, Lua, libraries, paths")
  w("  (run 2 already listed all 263 globals and all 118 path types -- that is")
  w("   archived. This section only re-confirms what the importer will use.)")

  sub("Lua itself")
  kv("_VERSION", _VERSION)
  kv("PROBE_VERSION", PROBE_VERSION)

  local libraries = { "string", "table", "math", "io", "os", "coroutine", "debug", "utf8", "package" }
  for i = 1, #libraries do
    local name = libraries[i]
    local value = nil
    pcall(function() value = _ENV[libraries[i]] end)
    kv("library " .. name, type(value))
  end

  local loaders = { "load", "loadfile", "dofile", "require", "pcall", "select" }
  for i = 1, #loaders do
    local fn = nil
    pcall(function() fn = _ENV[loaders[i]] end)
    kv("function " .. loaders[i], type(fn))
  end

  if type(os) == "table" then
    try("os.date()", os.date)
    try("os.getenv('HOME')", os.getenv, "HOME")
    kv("os.remove", type(os.remove))
    kv("os.rename", type(os.rename))
  end

  sub("The globals the importer needs")
  local missing = {}
  for i = 1, #IMPORTER_GLOBALS do
    local value = nil
    pcall(function() value = _ENV[IMPORTER_GLOBALS[i]] end)
    if value == nil then
      missing[#missing + 1] = IMPORTER_GLOBALS[i]
    end
    kv(IMPORTER_GLOBALS[i], type(value))
  end
  kv("missing from that list", #missing == 0 and "none" or table.concat(missing, ", "))

  sub("grandMA3 version")
  try("Version()", Version)
  try("HostOS()", HostOS)
  try("HostType()", HostType)
  local ok_root, root = try("Root()", Root)

  sub("The folders the importer will read and write")
  if type(GetPath) ~= "function" then
    w("    GetPath is not available, so the probe cannot locate any folder")
    return ok_root and root or nil
  end
  for i = 1, #PATHS_THAT_MATTER do
    local key = PATHS_THAT_MATTER[i]
    local value = nil
    pcall(function()
      if type(Enums) == "table" and type(Enums.PathType) == "table" then
        value = Enums.PathType[key]
      end
    end)
    if value == nil then
      wf("  SKIP GetPath(Enums.PathType.%s) -> no such enum entry", key)
    else
      try(string.format("GetPath(Enums.PathType.%s = %s)", key, S(value)), GetPath, value)
    end
  end
  try("GetPath(\"gma3_library\")", GetPath, "gma3_library")
  try("GetPathSeparator()", GetPathSeparator)

  return ok_root and root or nil
end

-- Works out where the report goes. Called early so later sections can flush.
--
-- There is no "gma3_library" string constant in the 2.3 API; the folder is
-- reached through Enums.PathType. Run 2 confirmed Enums.PathType.Library is the
-- one, so it stays first; the rest are the fallbacks.
local LIBRARY_ENUMS = { "Library", "GrandMA3Library", "PluginLibrary", "Showfiles", "UserMedia" }
local LIBRARY_STRINGS = { "gma3_library", "library", "shows" }

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
        { time = 1.5,  cue = 1, name = "Intro",  command = "Go+", guid = "{AAAA-1}" },
        { time = 12.25, cue = 2, name = "Drop",   command = "Go+", guid = "{AAAA-2}" },
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
        for _, key in ipairs({ "Library", "CustomPluginLibrary", "PluginLibrary" }) do
          if Enums.PathType[key] ~= nil then
            add_dir(GetPath(Enums.PathType[key]))
          end
        end
      end
    end)
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
            kv("track[1].events[1].guid", track.events[1].guid)
          end
        end
      end
    else
      kv("loadfile error", load_err)
    end
  end

  sub("io.open outside the library folder -- run 2 said yes, confirming once more")
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
      if wrote and type(os) == "table" and type(os.remove) == "function" then
        try("os.remove(escape file)", os.remove, escape)
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

-- ------------------------------------------------- the pool the show is in
--
-- This is the correction that version 1.1 exists for. DataPool() is the pool
-- the user is working in; Root().ShowData.DataPools.Default is pool 1 and is
-- only the same thing by accident. Everything the probe reads or writes goes
-- through here; the Default route is read once, for the comparison line.

local POOL = {
  handle = nil,     -- DataPool()
  no = nil,         -- its number, 2 on Tobi's show
  name = nil,
  default = nil,    -- Root().ShowData.DataPools.Default, for comparison only
  default_no = nil,
  same = nil,
}

local function resolve_pool(root)
  if type(DataPool) == "function" then
    pcall(function() POOL.handle = DataPool() end)
  end
  if POOL.handle ~= nil then
    POOL.no = number_of(POOL.handle)
    POOL.name = name_of(POOL.handle)
  end
  if root ~= nil then
    pcall(function()
      local show_data = index_quiet(root, "ShowData")
      if show_data == nil then return end
      local pools = index_quiet(show_data, "DataPools")
      if pools == nil then return end
      POOL.default = index_quiet(pools, "Default") or index_quiet(pools, 1)
    end)
  end
  if POOL.default ~= nil then
    POOL.default_no = number_of(POOL.default)
  end
  if POOL.handle ~= nil and POOL.default ~= nil then
    POOL.same = (S(POOL.handle) == S(POOL.default))
  end
  return POOL.handle
end

-- Every object lookup in this probe goes through here.
local function pool_child(child_name)
  if POOL.handle == nil then
    return nil, "DataPool() gave no handle"
  end
  local child = index_quiet(POOL.handle, child_name)
  if child == nil then
    child = get_quiet(POOL.handle, "Get", child_name)
  end
  if child == nil then
    return nil, "DataPool()." .. child_name .. " is nil"
  end
  return child, "DataPool()." .. child_name
end

-- What the old route would have given, logged so the difference is on record
-- and nobody re-introduces it.
local function default_child(child_name)
  if POOL.default == nil then
    return nil
  end
  return index_quiet(POOL.default, child_name)
end

-- Finds the child whose displayed number matches. Pool indexes and displayed
-- numbers need not agree, so match on No first and fall back to position.
local function child_by_number(pool, number)
  if pool == nil then
    return nil, "no pool handle"
  end
  local kids = select(1, children_of(pool))
  for i = 1, #kids do
    local no = number_of(kids[i])
    if no ~= nil and tostring(no) == tostring(number) then
      return kids[i], "matched No"
    end
  end
  local direct = index_quiet(pool, number)
  if direct ~= nil then
    return direct, "pool[" .. S(number) .. "]"
  end
  return nil, "no child with that number"
end

local function first_child(pool)
  local kids = select(1, children_of(pool))
  return kids[1]
end

-- The one child of that class, and where it sits. A TrackGroup answers with
-- [1] = MarkerTrack and [2] = Track on a console that has a marker track, so
-- "the first child" is the wrong question to ask.
local function child_of_class(parent, class)
  local kids = select(1, children_of(parent))
  for i = 1, #kids do
    local c = class_of(kids[i])
    if c ~= nil and S(c):lower() == S(class):lower() then
      return kids[i], i
    end
  end
  return nil, nil
end

-- Which children are new since the snapshot. Handles compare by their address
-- string, which is unique per object.
local function snapshot_children(parent)
  local kids = select(1, children_of(parent))
  local seen = {}
  for i = 1, #kids do
    seen[S(kids[i])] = true
  end
  return seen
end

local function new_children(parent, before)
  local kids = select(1, children_of(parent))
  local out = {}
  for i = 1, #kids do
    if not before[S(kids[i])] then
      out[#out + 1] = { handle = kids[i], position = i }
    end
  end
  return out, kids
end

-- Everything the probe creates is remembered here so section 9 can undo it.
--
-- Delete and Remove take the PARENT plus a 1-based child index, not the child
-- itself, so the parent has to be remembered alongside the handle.
local created = { handles = {}, commands = {} }

-- Every level of the timecode tree the probe got hold of, for section 8.
local levels = {}

-- `own` is the important flag: section 8 writes a test string into properties,
-- and it may only ever do that to objects this probe created itself. Tobi's own
-- track groups and events are dumped and read, never written.
local function remember_level(class, handle, addr, own)
  if handle == nil then
    return
  end
  for i = 1, #levels do
    if S(levels[i].handle) == S(handle) then
      if own and not levels[i].own then
        levels[i].own = true
        levels[i].addr = addr or levels[i].addr
      end
      return
    end
  end
  levels[#levels + 1] = { class = class, handle = handle, addr = addr, own = own or false }
end

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

-- The numbers the probe really works with, once the pool has been asked.
local RESOLVED = { timecode_no = TIMECODE_NO, sequence_no = SEQUENCE_NO }

local function section_3_object_model(root)
  section(3, "The current DataPool, its timecodes and its sequences")

  sub("Which pool is the show working in?")
  try("DataPool()", DataPool)
  kv("DataPool()", POOL.handle ~= nil and handle_label(POOL.handle) or "nil")
  kv("  its No", POOL.no)
  kv("  its Name", POOL.name)
  kv("DataPools.Default (comparison only)",
    POOL.default ~= nil and handle_label(POOL.default) or "nil")
  kv("  its No", POOL.default_no)
  kv("same handle?", POOL.same)
  if POOL.same == false then
    w("    -> The two are DIFFERENT. Version 1.0 read the Default pool and")
    w("       therefore found nothing. Everything below uses DataPool().")
  end
  local pool_addr = "ShowData.DataPools." .. S(POOL.no)
  kv("address prefix for this pool", pool_addr)

  sub("How the importer could let the user pick a timecode")
  local timecodes, how = pool_child("Timecodes")
  kv("Timecodes pool", timecodes ~= nil and handle_label(timecodes) or "nil")
  kv("  route", how)
  local default_tcs = default_child("Timecodes")
  kv("  the Default pool's Timecodes (comparison)",
    default_tcs ~= nil and (S(select(3, children_of(default_tcs))) .. " children") or "nil")

  if timecodes ~= nil then
    w("    every timecode in the current pool:")
    local kids = select(1, children_of(timecodes))
    if #kids == 0 then
      w("      (none -- the pool is empty)")
    end
    for i = 1, #kids do
      wf("      [%d] %s  no=%s", i, handle_label(kids[i]), S(number_of(kids[i])))
    end
  end
  try("SelectedTimecode()", SelectedTimecode)
  try("SelectedSequence()", SelectedSequence)
  try("ObjectList(\"Timecode " .. TIMECODE_NO .. "\")", function()
    local list = ObjectList("Timecode " .. TIMECODE_NO)
    if type(list) ~= "table" then
      return list
    end
    return "table with " .. #list .. " entries, [1] = " .. S(list[1])
  end)
  try("ObjectList(\"Timecode *\")", function()
    local list = ObjectList("Timecode *")
    if type(list) ~= "table" then
      return list
    end
    return "table with " .. #list .. " entries"
  end)

  if timecodes == nil then
    w("  no Timecodes pool -- the rest of this section cannot run")
    return nil, nil
  end

  describe(timecodes, "Timecodes pool", { child_limit = 40 })

  local timecode, found_how = child_by_number(timecodes, TIMECODE_NO)
  kv("timecode " .. TIMECODE_NO .. " found by", found_how)
  if timecode == nil then
    timecode = first_child(timecodes)
    if timecode ~= nil then
      RESOLVED.timecode_no = number_of(timecode) or TIMECODE_NO
      wf("    timecode %d does not exist here -- falling back to the first one, No %s",
        TIMECODE_NO, S(RESOLVED.timecode_no))
    else
      w("    the pool has no timecode at all. The command line will be asked to")
      w("    create one, and section 9 removes it again.")
    end
  end

  if timecode ~= nil then
    remember_level("Timecode", timecode, S(RESOLVED.timecode_no))
    describe(timecode, "Timecode " .. S(RESOLVED.timecode_no), { child_limit = 20 })

    sub("Walking down what is already there: TrackGroup -> Track -> TimeRange -> SubTrack -> Event")
    w("  (an event that Tobi made BY HAND is the most valuable thing in this")
    w("   listing -- its CueDestination shows the address form MA3 itself writes)")
    local groups = select(1, children_of(timecode))
    if #groups == 0 then
      w("    the timecode has no track group yet")
    end
    for gi = 1, math.min(#groups, 3) do
      local group = groups[gi]
      remember_level("TrackGroup", group, string.format("%s.%d", S(RESOLVED.timecode_no), gi))
      describe(group, string.format("TrackGroup [%d]", gi), { child_limit = 20 })
      local tracks = select(1, children_of(group))
      for ti = 1, math.min(#tracks, 4) do
        local track = tracks[ti]
        remember_level(S(class_of(track)), track,
          string.format("%s.%d.%d", S(RESOLVED.timecode_no), gi, ti))
        describe(track, string.format("Track [%d.%d]", gi, ti), { child_limit = 20 })
        local ranges = select(1, children_of(track))
        for ri = 1, math.min(#ranges, 2) do
          local range = ranges[ri]
          remember_level(S(class_of(range)), range,
            string.format("%s.%d.%d.%d", S(RESOLVED.timecode_no), gi, ti, ri))
          describe(range, string.format("Track child [%d.%d.%d]", gi, ti, ri), { child_limit = 20 })
          local subs = select(1, children_of(range))
          for si = 1, math.min(#subs, 2) do
            local subtrack = subs[si]
            remember_level(S(class_of(subtrack)), subtrack,
              string.format("%s.%d.%d.%d.%d", S(RESOLVED.timecode_no), gi, ti, ri, si))
            describe(subtrack, string.format("SubTrack [%d.%d.%d.%d]", gi, ti, ri, si),
              { child_limit = 20 })
            local events = select(1, children_of(subtrack))
            for ei = 1, math.min(#events, 3) do
              remember_level(S(class_of(events[ei])), events[ei],
                string.format("%s.%d.%d.%d.%d.%d", S(RESOLVED.timecode_no), gi, ti, ri, si, ei))
              describe(events[ei], string.format("Event [%d.%d.%d.%d.%d]", gi, ti, ri, si, ei),
                { children = false })
            end
          end
        end
      end
    end
  end

  sub("Sequences of the current pool")
  local sequences = pool_child("Sequences")
  kv("Sequences pool", sequences ~= nil and handle_label(sequences) or "nil")
  local sequence = nil
  if sequences ~= nil then
    list_children(sequences, "    ", 40)
    local seq_how
    sequence, seq_how = child_by_number(sequences, SEQUENCE_NO)
    kv("sequence " .. SEQUENCE_NO .. " found by", seq_how)
    if sequence == nil then
      sequence = first_child(sequences)
      if sequence ~= nil then
        RESOLVED.sequence_no = number_of(sequence) or SEQUENCE_NO
        wf("    falling back to the first sequence, No %s", S(RESOLVED.sequence_no))
      end
    end
    if sequence ~= nil then
      describe(sequence, "Sequence " .. S(RESOLVED.sequence_no), { child_limit = 10 })
    end
  end

  return timecode, sequence
end

-- ---------------------------------------------------------------- cue list
-- Shared by sections 6 and 9, and it reads the CURRENT pool. Version 1.0 read
-- the Default pool here, which is why the cue list never showed the cues the
-- command line had just stored.

local function cue_container()
  local sequences = pool_child("Sequences")
  if sequences == nil then
    return nil, "no Sequences pool in the current data pool"
  end
  local sequence = child_by_number(sequences, RESOLVED.sequence_no)
  if sequence == nil then
    return nil, "sequence " .. S(RESOLVED.sequence_no) .. " not found in the current pool"
  end
  local container = index_quiet(sequence, "Cues")
  if container == nil or type(container) == "function" then
    container = sequence
  end
  return container
end

local function cue_list(title)
  sub(title)
  local container, why = cue_container()
  if container == nil then
    wf("    %s", S(why))
    return 0
  end
  local cues = select(1, children_of(container))
  wf("    %d cues in DataPool %s, Sequence %s", #cues, S(POOL.no), S(RESOLVED.sequence_no))
  for i = 1, math.min(#cues, 60) do
    wf("    cue [%d] no=%s name=%s class=%s", i,
      S(number_of(cues[i])), S(name_of(cues[i])), S(class_of(cues[i])))
  end
  return #cues
end

-- ------------------------------------------------------------- section 4

local function section_4_object_api(timecode, sequence)
  section(4, "Creating content through the object API")
  w("  This never ran in version 1.0, because the timecode handle was nil.")
  w("  What works here decides whether the importer can build with handles")
  w("  (fast, no index guessing) or has to go through the command line.")

  if timecode == nil then
    w("  no timecode handle, nothing to create -- see section 3")
    return nil
  end

  -- Documented shapes (bambinito mirror of GetObjApiDescriptor):
  --   Append(handle[, class[, undo[, count]]])      -> child handle
  --   Acquire(handle, class)                        -> existing or new child
  --   Insert(handle, child_index[, class[, undo]])  -> child handle
  --   Create(handle, child_index[, class[, undo]])  -> child handle
  local function append_child(parent, class, note)
    local before = select(3, children_of(parent))
    local ok, value = try(string.format("parent:Append(%q)", S(class)), function()
      return parent:Append(class)
    end)
    if not ok or value == nil then
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
      remember_level(S(class), value, nil, true)
      return value
    end
    return nil
  end

  sub("Append a TrackGroup")
  local group = append_child(timecode, "TrackGroup", "TrackGroup on timecode " .. S(RESOLVED.timecode_no))
  kv("TrackGroup handle", group and handle_label(group) or "nil")
  if group == nil then
    w("  without a TrackGroup the object route stops here; section 5 tries the command line")
    return nil
  end
  try("group:Set('Name', 'steelblue object api')", function()
    return group:Set("Name", "steelblue object api")
  end)
  describe(group, "New TrackGroup", { child_limit = 10 })

  sub("Append a Track inside it")
  local track = append_child(group, "Track", "Track in the new TrackGroup")
  kv("Track handle", track and handle_label(track) or "nil")
  if track == nil then
    return group
  end
  try("track:Set('Name', 'steelblue probe')", function()
    return track:Set("Name", "steelblue probe")
  end)
  w("    what the group holds now -- is there a MarkerTrack next to the Track?")
  list_children(group, "      ", 10)

  sub("Point the track at sequence " .. S(RESOLVED.sequence_no))
  -- Three routes, because the importer only needs one of them to work:
  -- a plain address string, the sequence HANDLE, and the command line.
  local seq_address = string.format("ShowData.DataPools.%s.Sequences.%s",
    S(POOL.no), S(RESOLVED.sequence_no))
  local targets = { "Target", "Object", "Assignment", "Sequence", "Destination" }
  for i = 1, #targets do
    local property = targets[i]
    try(string.format("track:Set(%q, %q)", property, seq_address), function()
      return track:Set(property, seq_address)
    end)
    kv("  read back " .. property, select(1, read_property(track, property)))
    try(string.format("track:Set(%q, \"Sequence %s\")", property, S(RESOLVED.sequence_no)), function()
      return track:Set(property, "Sequence " .. S(RESOLVED.sequence_no))
    end)
    kv("  read back " .. property, select(1, read_property(track, property)))
    if sequence ~= nil then
      try(string.format("track:Set(%q, <sequence handle>)", property), function()
        return track:Set(property, sequence)
      end)
      kv("  read back " .. property, select(1, read_property(track, property)))
    end
  end
  w("    and the same thing from the command line, on the object API's own track:")
  local track_addr = get_quiet(track, "Addr")
  kv("    track:Addr()", track_addr)
  kv("    track:ToAddr()", get_quiet(track, "ToAddr"))

  sub("The track after the assignment attempts")
  describe(track, "New Track", { child_limit = 10 })

  sub("Append a TimeRange, a CmdSubTrack and a CmdEvent")
  local range = append_child(track, "TimeRange", "TimeRange in the new Track")
  kv("TimeRange handle", range and handle_label(range) or "nil")
  if range == nil then
    return group, track, nil
  end
  describe(range, "New TimeRange", { child_limit = 10, dump = false })

  local subtrack = append_child(range, "CmdSubTrack", "CmdSubTrack in the new TimeRange")
  kv("CmdSubTrack handle", subtrack and handle_label(subtrack) or "nil")
  if subtrack == nil then
    return group, track, nil
  end
  describe(subtrack, "New CmdSubTrack", { child_limit = 10, dump = false })

  local event = nil
  local event_classes = { "CmdEvent", "Event", "TimecodeEvent" }
  for i = 1, #event_classes do
    if event == nil then
      event = append_child(subtrack, event_classes[i], "Event (" .. event_classes[i] .. ")")
    end
  end
  kv("Event handle", event and handle_label(event) or "nil")
  if event == nil then
    return group, track, nil
  end

  sub("Setting the event up through the object API alone")
  try("event:Set('Time', 12.5)", function() return event:Set("Time", 12.5) end)
  kv("  read back Time", select(1, read_property(event, "Time")))
  try("event:Set('Token', 'Goto')", function() return event:Set("Token", "Goto") end)
  kv("  read back Token", select(1, read_property(event, "Token")))
  local cue_address = string.format("ShowData.DataPools.%s.Sequences.%s.1",
    S(POOL.no), S(RESOLVED.sequence_no))
  try(string.format("event:Set('CueDestination', %q)", cue_address), function()
    return event:Set("CueDestination", cue_address)
  end)
  kv("  read back CueDestination", select(1, read_property(event, "CueDestination")))

  sub("Dump of the event the object API built -- this is the verification")
  describe(event, "New Event after Set", { children = false })

  return group, track, event
end

-- ------------------------------------------------------------- section 5

-- The track group number section 5 stores into, so section 9 can delete it.
local probe_group_no = nil
local probe_group_handle = nil
local probe_group_name = "steelblue probe"
local timecode_was_created_by_probe = false

local function section_5_command_line(timecode)
  section(5, "The command line, and which number the event really gets")

  if type(Cmd) ~= "function" then
    w("  Cmd is not available")
    return nil, nil
  end

  local function run(command)
    created.commands[#created.commands + 1] = command
    local ok, answer = try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
    return ok and answer or nil
  end

  local TC = S(RESOLVED.timecode_no)

  -- CG is the track group number the probe works in: one past whatever the
  -- timecode already has, so no existing group is ever addressed by accident.
  local CG = 1
  if timecode ~= nil then
    CG = (tonumber(select(3, children_of(timecode))) or 0) + 1
  end
  probe_group_no = CG
  kv("timecode the probe addresses", TC)
  kv("track group the probe writes into", CG)
  kv("the pool the OBJECT side is reading", S(POOL.no))

  sub("Does Cmd answer at all?")
  run("Echo \"steelblue probe\"")

  sub("Track group -- and which pool does the command line write into?")
  local before_current = timecode ~= nil and select(3, children_of(timecode)) or nil
  local default_tcs = default_child("Timecodes")
  local default_tc = default_tcs ~= nil and child_by_number(default_tcs, RESOLVED.timecode_no) or nil
  local before_default = default_tc ~= nil and select(3, children_of(default_tc)) or nil
  run(string.format("Store TC %s.%d %q", TC, CG, probe_group_name))
  local after_current = timecode ~= nil and select(3, children_of(timecode)) or nil
  local after_default = default_tc ~= nil and select(3, children_of(default_tc)) or nil
  wf("    track groups in the CURRENT pool's timecode: %s -> %s", S(before_current), S(after_current))
  wf("    track groups in the DEFAULT pool's timecode: %s -> %s", S(before_default), S(after_default))
  w("    (whichever number moved is the pool the command line works in)")

  if timecode == nil then
    w("    the pool had no timecode before; looking again now")
    local timecodes = pool_child("Timecodes")
    if timecodes ~= nil then
      local fresh = child_by_number(timecodes, RESOLVED.timecode_no)
      if fresh ~= nil then
        timecode = fresh
        timecode_was_created_by_probe = true
        w("    the command line CREATED the timecode -- section 9 removes it again")
      end
    end
  end

  local group = timecode ~= nil and select(1, child_by_number(timecode, CG)) or nil
  if group == nil and timecode ~= nil then
    local kids = select(1, children_of(timecode))
    group = kids[CG]
  end
  kv("track group handle", group and handle_label(group) or "nil")
  probe_group_handle = group
  remember_level("TrackGroup", group, string.format("%s.%d", TC, CG), true)

  sub("Track -- and where does the command line's \"track 1\" actually land?")
  run(string.format("Store TC %s.%d.1", TC, CG))
  run(string.format("Assign Sequence %s at TC %s.%d.1", S(RESOLVED.sequence_no), TC, CG))
  if group ~= nil then
    w("    children of the track group, with their classes:")
    list_children(group, "      ", 10)
    local marker, marker_at = child_of_class(group, "MarkerTrack")
    local track, track_at = child_of_class(group, "Track")
    kv("    MarkerTrack sits at child index", marker ~= nil and marker_at or "no MarkerTrack here")
    kv("    Track sits at child index", track ~= nil and track_at or "no Track here")
    w("    -> the command line address \".1\" produced the object above; if the")
    w("       Track is at index 2, then address N means visible track N, not child N.")
  end
  local track = group ~= nil and select(1, child_of_class(group, "Track")) or nil
  remember_level("Track", track, string.format("%s.%d.1", TC, CG), true)
  if track ~= nil then
    describe(track, "The track the command line made", { child_limit = 10 })
  end

  sub("Time range and command sub-track")
  run(string.format("Store TC %s.%d.1.1", TC, CG))
  run(string.format("Store Type \"CmdSubTrack\" Timecode %s.%d.1.1.1", TC, CG))
  local range = track ~= nil and select(1, child_of_class(track, "TimeRange")) or nil
  if range == nil and track ~= nil then
    range = select(1, children_of(track))[1]
  end
  remember_level("TimeRange", range, string.format("%s.%d.1.1", TC, CG), true)
  if range ~= nil then
    w("    children of the time range:")
    list_children(range, "      ", 10)
  end
  local subtrack = range ~= nil and select(1, child_of_class(range, "CmdSubTrack")) or nil
  if subtrack == nil and range ~= nil then
    subtrack = select(1, children_of(range))[1]
  end
  remember_level("CmdSubTrack", subtrack, string.format("%s.%d.1.1.1", TC, CG), true)
  kv("CmdSubTrack handle", subtrack and handle_label(subtrack) or "nil")

  -- ------------------------------------------------ the event-number question
  --
  -- Run 2: "Store TC 1.1.1.1.1.5" -> OK, "Set TC 1.1.1.1.1.5 ..." -> Illegal
  -- object. The console numbers the event itself. So after every Store the
  -- probe asks the object tree which child is new, and addresses THAT.

  local function store_event(command, label)
    sub(label)
    local before = subtrack ~= nil and snapshot_children(subtrack) or nil
    local before_count = subtrack ~= nil and select(3, children_of(subtrack)) or nil
    local answer = run(command)
    if subtrack == nil then
      w("    no CmdSubTrack handle, so the new event cannot be identified")
      return nil, nil, answer
    end
    local fresh, all = new_children(subtrack, before)
    wf("    events in the sub-track: %s -> %s", S(before_count), S(#all))
    w("    every event the sub-track holds now:")
    for i = 1, #all do
      wf("      [%d] %s  Time=%s Token=%s CueDestination=%s", i, handle_label(all[i]),
        S(select(1, read_property(all[i], "Time"))),
        S(select(1, read_property(all[i], "Token"))),
        S(select(1, read_property(all[i], "CueDestination"))))
    end
    if #fresh == 0 then
      w("    NOTHING new appeared -- the Store did not create an event here")
      return nil, nil, answer
    end
    if #fresh > 1 then
      wf("    %d new children at once -- listing them all", #fresh)
    end
    local entry = fresh[#fresh]
    wf("    the new event is child number %d, handle %s", entry.position,
      handle_label(entry.handle))
    w("    (if that number differs from the one the command asked for, then the")
    w("     console chose it -- and addressing the asked-for number is exactly")
    w("     what answered \"Illegal object\" in run 2)")
    remember_level("CmdEvent", entry.handle,
      string.format("%s.%d.1.1.1.%d", TC, CG, entry.position), true)
    return entry.handle, entry.position, answer
  end

  local event, event_index = store_event(
    string.format("Store TC %s.%d.1.1.1.1", TC, CG),
    "The first event -- asked for number 1")

  if event ~= nil then
    sub("Setting that event, addressed by the index the tree really shows")
    run(string.format("Set TC %s.%d.1.1.1.%d Property \"time\" 12.437", TC, CG, event_index))
    kv("  read back Time", select(1, read_property(event, "Time")))
    run(string.format("Set TC %s.%d.1.1.1.%d Property \"token\" \"goto\"", TC, CG, event_index))
    kv("  read back Token", select(1, read_property(event, "Token")))

    sub("The cue destination -- three address forms, and what MA3 stores back")
    -- Version 1.0 wrote ".Default.", which is pool 1. The current pool has to
    -- be in the address, and the relative form is worth a try because that is
    -- what a hand-made event's Dump tends to show.
    local forms = {
      string.format("ShowData.DataPools.%s.Sequences.%s.1", S(POOL.no), S(RESOLVED.sequence_no)),
      string.format("ShowData.DataPools.Default.Sequences.%s.1", S(RESOLVED.sequence_no)),
      string.format("Sequences.%s.1", S(RESOLVED.sequence_no)),
      string.format("Sequence %s Cue 1", S(RESOLVED.sequence_no)),
    }
    for i = 1, #forms do
      run(string.format("Set TC %s.%d.1.1.1.%d Property \"cuedestination\" %q",
        TC, CG, event_index, forms[i]))
      kv("  read back CueDestination", select(1, read_property(event, "CueDestination")))
      if EDIT_ROLE ~= nil then
        kv("  read back CueDestination (Roles.Edit)",
          get_quiet(event, "Get", "CueDestination", EDIT_ROLE))
      end
    end
    w("    and the dump, which shows the canonical form MA3 keeps:")
    write_dump(event, "    ")
  end

  -- Does the next number do what one would hope?
  local next_index = (event_index or 0) + 1
  local event2, index2 = store_event(
    string.format("Store TC %s.%d.1.1.1.%d", TC, CG, next_index),
    string.format("A second event -- asked for number %d, the one after the first", next_index))
  if event2 ~= nil then
    wf("    asked for %d, got child %s -- %s", next_index, S(index2),
      (index2 == next_index) and "the console agreed" or "the console picked its own number")
    run(string.format("Set TC %s.%d.1.1.1.%d Property \"time\" 30.5", TC, CG, index2))
    kv("  read back Time", select(1, read_property(event2, "Time")))
  end

  -- And the gap that broke run 2.
  local event3, index3 = store_event(
    string.format("Store TC %s.%d.1.1.1.5", TC, CG),
    "A third event -- asked for number 5, leaving a gap on purpose")
  if event3 ~= nil then
    wf("    asked for 5, got child %s -- run 2's \"Illegal object\" is explained if", S(index3))
    wf("    that is not 5. Setting it on child %s now:", S(index3))
    run(string.format("Set TC %s.%d.1.1.1.%d Property \"time\" 45.25", TC, CG, index3))
    kv("  read back Time", select(1, read_property(event3, "Time")))
    w("    and the same Set on the number that was ASKED for, to show the difference:")
    run(string.format("Set TC %s.%d.1.1.1.5 Property \"time\" 45.25", TC, CG))
  end

  -- Can an event be named on the way in?
  local event4 = store_event(
    string.format("Store TC %s.%d.1.1.1 %q", TC, CG, "steelblue named event"),
    "Storing at the SUB-TRACK level with a name -- does the new event get it?")
  if event4 ~= nil then
    kv("    the new event's Name", name_of(event4))
  end

  sub("The track group after the command line had its turn")
  if group ~= nil then
    write_dump(group, "    ")
  end

  return event, subtrack
end

-- ------------------------------------------------------------- section 6

local function section_6_cues()
  section(6, "Creating and naming cues -- now read from the pool they land in")

  if type(Cmd) ~= "function" then
    w("  Cmd is not available")
    return
  end

  local function run(command)
    created.commands[#created.commands + 1] = command
    try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
  end

  local SEQ = S(RESOLVED.sequence_no)

  cue_list("Cues before anything is stored")

  -- The 2.3 Store page spells the option /NoConfirmation; /NoConfirm is the
  -- abbreviation the command line normally accepts. Both are tried once.
  sub("Store an empty cue with an empty programmer")
  run(string.format("Store Sequence %s Cue %d /NoConfirmation", SEQ, CUE_FIRST))
  run(string.format("Store Sequence %s Cue %d /NoConfirm", SEQ, CUE_FIRST + 1))
  run(string.format("Store Sequence %s Cue %d", SEQ, CUE_FIRST + 2))
  cue_list("Cues after the three Store calls -- are empty cues created at all?")

  sub("Label them")
  for i = 0, CUE_COUNT - 1 do
    run(string.format("Label Sequence %s Cue %d %q", SEQ, CUE_FIRST + i,
      string.format("Probe %d", CUE_FIRST + i)))
  end
  cue_list("Cues after labelling")

  sub("Store again over an EXISTING cue -- is the name lost?")
  -- This decides the importer's cue rule: existing cues must survive untouched
  -- while missing ones are created empty and named.
  run(string.format("Store Sequence %s Cue %d /NoConfirmation", SEQ, CUE_FIRST))
  cue_list("After a plain second Store on cue " .. CUE_FIRST)
  run(string.format("Store Sequence %s Cue %d /Merge /NoConfirmation", SEQ, CUE_FIRST))
  cue_list("After Store /Merge on cue " .. CUE_FIRST .. " -- its name is the answer")
end

-- ------------------------------------------------------------- section 7

local function section_7_time(timecode, event)
  section(7, "Time: unit, framerate, how a value is set")
  w("  This never ran in version 1.0 either -- there was no event to ask.")

  if timecode ~= nil then
    sub("Framerate of timecode " .. S(RESOLVED.timecode_no))
    -- The 2.3 timecode settings page calls the property FrameReadout, with
    -- values Default / Seconds / 24 fps / 25 fps / 30 fps / 60 fps.
    local names = { "FrameReadout", "Timedisplayformat", "Framerate", "FrameRate",
                    "Rate", "Duration", "TCSlot" }
    local original = nil
    for i = 1, #names do
      local value, how = read_property(timecode, names[i])
      kv(names[i] .. " (" .. S(how) .. ")", value)
      if names[i] == "FrameReadout" then
        original = value
      end
    end
    w("    the timecode's own dump, where the stored spelling is visible:")
    write_dump(timecode, "    ")

    sub("Setting the framerate to 25 fps and putting it back")
    kv("original FrameReadout", original)
    local TC = S(RESOLVED.timecode_no)
    try("timecode:Set('FrameReadout', '25 fps')", function()
      return timecode:Set("FrameReadout", "25 fps")
    end)
    kv("  read back FrameReadout", select(1, read_property(timecode, "FrameReadout")))
    if type(Cmd) == "function" then
      local command = string.format("Set TC %s Property \"FrameReadout\" \"25 fps\"", TC)
      created.commands[#created.commands + 1] = command
      try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
      kv("  read back FrameReadout", select(1, read_property(timecode, "FrameReadout")))
    end
    if original ~= nil then
      try("timecode:Set('FrameReadout', <original>)", function()
        return timecode:Set("FrameReadout", original)
      end)
      if type(Cmd) == "function" then
        local command = string.format("Set TC %s Property \"FrameReadout\" %q", TC, S(original))
        created.commands[#created.commands + 1] = command
        try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
      end
      kv("  FrameReadout restored to", select(1, read_property(timecode, "FrameReadout")))
    else
      w("    no original value was readable, so nothing was restored -- check by hand")
    end
  end

  if event == nil then
    w("")
    w("  no event handle from sections 4 or 5, so setting a time cannot be tested")
    return
  end

  sub("What the event's time looks like before anything is set")
  local value, how = read_property(event, "Time")
  wf("    Time = %s  (%s, via %s)", S(value), type(value), S(how))
  if EDIT_ROLE ~= nil then
    kv("    Time (Roles.Edit)", get_quiet(event, "Get", "Time", EDIT_ROLE))
  end
  w("    and in the dump, where the unit shows:")
  write_dump(event, "    ")

  sub("Setting the event time -- number first, then a timecode string")
  -- A posted show-file dump shows Time="1.04", i.e. seconds as a float. Both
  -- forms are tried anyway: what comes back out is what the importer writes in.
  local attempts = {
    { label = "number 12.437", value = 12.437 },
    { label = "integer 12", value = 12 },
    { label = "string \"12.437\"", value = "12.437" },
    { label = "string \"00:00:12.50\"", value = "00:00:12.50" },
    { label = "string \"00:00:12:15\"", value = "00:00:12:15" },
  }
  for a = 1, #attempts do
    local attempt = attempts[a]
    try(string.format("event:Set('Time', %s)", attempt.label), function()
      return event:Set("Time", attempt.value)
    end)
    local back, via = read_property(event, "Time")
    wf("      read back Time = %s  (%s, via %s)", S(back), type(back), S(via))
    if EDIT_ROLE ~= nil then
      wf("      read back Time (Roles.Edit) = %s", S(get_quiet(event, "Get", "Time", EDIT_ROLE)))
    end
  end

  sub("Which other time-shaped properties answer at all")
  for _, property in ipairs({ "TimeCode", "Position", "Start", "End", "Offset" }) do
    local v, h = read_property(event, property)
    kv("  " .. property, v ~= nil and (S(v) .. "  (via " .. S(h) .. ")") or "nil")
  end

  sub("Which tokens the event accepts")
  -- Token names confirmed from public sources: ExecToken="Flash" in a posted
  -- show-file dump (forum thread 5079) and the lowercase spellings goto / top /
  -- temp / flash in github.com/mittim88/TCHelper.
  local tokens = { "Go+", "Go-", "Goto", "goto", "Top", "Flash", "On", "Off", "Temp", "Swap" }
  for i = 1, #tokens do
    local ok = try(string.format("event:Set('Token', %q)", tokens[i]), function()
      return event:Set("Token", tokens[i])
    end)
    local back = select(1, read_property(event, "Token"))
    wf("      -> Token is now %s%s", S(back), ok and "" or "  (the Set itself failed)")
  end
end

-- ------------------------------------------------------------- section 8

-- Can the importer recognise its own events on the next import? It needs a
-- place for the REAPER marker GUID. This section dumps every level of the tree
-- and tries to write GUID_MARK into every text-shaped property it can find.
--
-- It writes ONLY into objects this probe created. Tobi's own track groups and
-- events are dumped and read, never written -- a probe that leaves a test
-- string in a real show is not a probe, it is damage.
local function section_8_guid_field()
  section(8, "A free text field for the REAPER GUID")
  w("  The importer has to be a MERGE, not a replace: it must find the event it")
  w("  wrote last time. That needs somewhere to park the REAPER marker GUID.")
  w("  Writing is tried on the probe's OWN objects only; anything that was")
  w("  already in the show is dumped and read, never written.")
  wf("  the string written: %s", GUID_MARK)

  if #levels == 0 then
    w("  no handles were collected in sections 3-5, nothing to test")
    return
  end

  local fixed = { "Note", "Comment", "Text", "Info", "Description", "Tag", "Tags", "Name" }

  -- One entry per class. An object the probe owns beats one it does not, and
  -- among its own, one with a command-line address beats one without: only
  -- then can both routes -- handle:Set and Cmd -- be tried on that level.
  local function score(entry)
    return (entry.own and 2 or 0) + (entry.addr ~= nil and 1 or 0)
  end
  local order, best = {}, {}
  for i = 1, #levels do
    local entry = levels[i]
    local class = S(entry.class)
    if best[class] == nil then
      order[#order + 1] = class
      best[class] = entry
    elseif score(entry) > score(best[class]) then
      best[class] = entry
    end
  end

  for i = 1, #order do
    local entry = best[order[i]]
    local class = order[i]
    sub(class .. "  ->  " .. handle_label(entry.handle) .. "   (address " .. S(entry.addr) .. ")")
    kv("    the probe created this object", entry.own)

    local dump = write_dump(entry.handle, "    ")
    local candidates = text_property_candidates(dump)
    wf("    text-shaped writable properties in that dump: %s",
      #candidates > 0 and table.concat(candidates, ", ") or "(none)")

    if not entry.own then
      w("    not ours -- read only. The values above are the answer for this level.")
      for c = 1, #candidates do
        local property = candidates[c]:sub(1, 1) .. candidates[c]:sub(2):lower()
        local value, via = read_property(entry.handle, property)
        wf("      %-16s = %s  (via %s)", property, S(value), S(via))
      end
    else
      -- The dump spells them upper case; Set() takes the cased name, so both
      -- the dump spelling and the usual spelling are tried.
      local tried = {}
      local function attempt(property)
        local key = property:lower()
        if tried[key] then return end
        tried[key] = true
        local before = select(1, read_property(entry.handle, property))
        try(string.format("handle:Set(%q, GUID_MARK)", property), function()
          return entry.handle:Set(property, GUID_MARK)
        end)
        local after, via = read_property(entry.handle, property)
        wf("      %-16s before=%s  after=%s  (via %s)%s", property, S(before), S(after), S(via),
          (S(after) == GUID_MARK) and "   <-- IT STUCK" or "")
        if type(Cmd) == "function" and entry.addr ~= nil and S(after) ~= GUID_MARK then
          local command = string.format("Set TC %s Property %q %q", S(entry.addr), property, GUID_MARK)
          created.commands[#created.commands + 1] = command
          try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
          local cmd_after = select(1, read_property(entry.handle, property))
          wf("      %-16s after the Cmd = %s%s", property, S(cmd_after),
            (S(cmd_after) == GUID_MARK) and "   <-- IT STUCK via Cmd" or "")
        end
        -- Put it back. Section 9 deletes these objects anyway, but a property
        -- left holding a test string is exactly the kind of thing that outlives
        -- the cleanup it was supposed to be covered by. A property that read
        -- back nil is emptied rather than left holding the mark.
        if S(select(1, read_property(entry.handle, property))) == GUID_MARK then
          pcall(function() entry.handle:Set(property, before ~= nil and before or "") end)
          local restored = select(1, read_property(entry.handle, property))
          if S(restored) == GUID_MARK then
            wf("      %-16s COULD NOT BE PUT BACK -- it still holds the mark", property)
          end
        end
      end

      for c = 1, #candidates do
        attempt(candidates[c]:sub(1, 1) .. candidates[c]:sub(2):lower())
      end
      for f = 1, #fixed do
        attempt(fixed[f])
      end
    end
  end

  sub("If nothing stuck anywhere")
  w("  Then the importer cannot mark its events in the show file itself and has")
  w("  to keep a sidecar file in the library folder (GUID -> timecode address).")
  w("  Section 2 proved that writing such a file is allowed.")
end

-- ------------------------------------------------------------- section 9

local function section_9_cleanup(timecode)
  section(9, "Cleaning up everything the probe created")

  -- Object-API handles first, as ordered: they were appended LAST, so they sit
  -- behind the command line's track group and removing them cannot renumber it.
  sub("Handles created through the object API, newest first")
  for i = #created.handles, 1, -1 do
    local entry = created.handles[i]
    wf("    %s", S(entry.note))
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

  sub("The track group the command line created")
  -- Its number is re-resolved by NAME, not trusted: the deletions above may
  -- have renumbered the list, and deleting the wrong group would take Tobi's
  -- own work with it.
  if type(Cmd) == "function" and timecode ~= nil then
    -- Three ways of finding it, in order of trustworthiness. The HANDLE is
    -- first: the deletions above may have renumbered the list, and section 8
    -- writes into the group's Name, so neither the old number nor the name is
    -- something to bet Tobi's other track groups on.
    local by_handle = position_in_parent(timecode, probe_group_handle)
    local by_name = nil
    local kids = select(1, children_of(timecode))
    for i = 1, #kids do
      if S(name_of(kids[i])) == probe_group_name then
        by_name = i
      end
    end
    kv("    number remembered from section 5", probe_group_no)
    kv("    position found again by handle", by_handle)
    kv("    position found again by name", by_name)
    local position = by_handle or by_name
    if position == nil then
      w("    the track group is gone already -- nothing to delete")
    else
      local command = string.format("Delete TC %s.%d /NoConfirmation", S(RESOLVED.timecode_no), position)
      local ok, answer = try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
      if not ok or not cmd_ok(answer) then
        command = string.format("Delete Timecode %s.%d /NoConfirmation",
          S(RESOLVED.timecode_no), position)
        try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
      end
    end
  else
    w("    no Cmd or no timecode, nothing to delete")
  end

  if timecode_was_created_by_probe and type(Cmd) == "function" then
    sub("The timecode itself, which did not exist before this run")
    local command = string.format("Delete Timecode %s /NoConfirmation", S(RESOLVED.timecode_no))
    try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
  end

  sub("Cues " .. CUE_FIRST .. "-" .. (CUE_FIRST + CUE_COUNT - 1))
  if type(Cmd) == "function" then
    for i = 0, CUE_COUNT - 1 do
      local command = string.format("Delete Sequence %s Cue %d /NoConfirmation",
        S(RESOLVED.sequence_no), CUE_FIRST + i)
      try("Cmd(" .. string.format("%q", command) .. ")", Cmd, command)
    end
  end

  -- The proof, read back out of the current pool.
  sub("What the timecode holds now")
  local timecodes = pool_child("Timecodes")
  if timecodes ~= nil then
    local tc = child_by_number(timecodes, RESOLVED.timecode_no)
    if tc ~= nil then
      list_children(tc, "    ", 20)
    else
      w("    the timecode is gone as well")
    end
  else
    w("    no Timecodes pool to read")
  end

  cue_list("What the sequence holds now")

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
  levels = {}
  probe_group_no = nil
  probe_group_handle = nil
  timecode_was_created_by_probe = false
  RESOLVED.timecode_no = TIMECODE_NO
  RESOLVED.sequence_no = SEQUENCE_NO
  POOL.handle, POOL.no, POOL.name = nil, nil, nil
  POOL.default, POOL.default_no, POOL.same = nil, nil, nil

  raw("steelblue studios -- grandMA3 probe 1b")
  raw("======================================")
  wf("probe version  %s", PROBE_VERSION)
  wf("timecode       %d (falls back to the first one that exists)", TIMECODE_NO)
  wf("sequence       %d (falls back to the first one that exists)", SEQUENCE_NO)
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

  -- The one question the probe asks. Run 2 removed the second box: what a
  -- MessageBox with selectors, states and inputs hands back is answered and
  -- archived, so asking again would only cost Tobi a click.
  if type(MessageBox) == "function" then
    local ok, answer = pcall(MessageBox, {
      title = "steelblue probe 1b",
      message = string.format(
        "The probe runs in timecode %d and sequence %d of the CURRENT\n" ..
        "data pool of THIS show, and it stores cues %d-%d.\n" ..
        "Use a throwaway show.\n\n" ..
        "It writes its findings to:\n%s\n\nOK?",
        TIMECODE_NO, SEQUENCE_NO, CUE_FIRST, CUE_FIRST + CUE_COUNT - 1, S(output_path)),
      display = display_handle,
      commands = {
        { value = 1, name = "OK" },
        { value = 2, name = "Cancel" },
      },
    })
    -- The documented return is { success = boolean, result = integer, ... },
    -- where result is the value of the command that was tapped. Run 1 came back
    -- with success=true, result=0 after OK -- so a 0 must never be read as
    -- Cancel. Cancel is value 2, and only that (or success=false) stops us.
    wf("confirmation   ok=%s answer=%s", S(ok), S(answer))
    if ok and type(answer) == "table" then
      wf("               success=%s result=%s", S(answer.success), S(answer.result))
      if answer.success == false or answer.result == 2 then
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

  if output_path == nil then
    output_path, library_dir, path_source = pick_output_path()
    if output_path then
      wf("report path found on the second attempt: %s (%s)", S(output_path), S(path_source))
      say("steelblue probe: report goes to " .. S(output_path))
    end
  end

  run_section("2", section_2_files, library_dir)

  resolve_pool(root)

  local timecode, sequence = nil, nil
  run_section("3", function() timecode, sequence = section_3_object_model(root) end)

  local group, track, event = nil, nil, nil
  run_section("4", function() group, track, event = section_4_object_api(timecode, sequence) end)

  local cmd_event = nil
  run_section("5", function() cmd_event = section_5_command_line(timecode) end)
  if timecode == nil then
    -- Section 5 may have made the command line create one.
    local timecodes = pool_child("Timecodes")
    if timecodes ~= nil then
      timecode = child_by_number(timecodes, RESOLVED.timecode_no)
    end
  end

  run_section("6", section_6_cues)
  run_section("7", section_7_time, timecode, cmd_event or event)
  run_section("8", section_8_guid_field)
  run_section("9", section_9_cleanup, timecode)

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
  end
end

-- The offline harness reads the pure helpers through this hook, the same way
-- the REAPER plugins expose their internals. MA3 never sets it.
if type(STEELBLUE_MA3_PROBE_TEST) == "table" then
  STEELBLUE_MA3_PROBE_TEST.text_property_candidates = text_property_candidates
  STEELBLUE_MA3_PROBE_TEST.cmd_ok = cmd_ok
  STEELBLUE_MA3_PROBE_TEST.PROBE_VERSION = PROBE_VERSION
end

return main

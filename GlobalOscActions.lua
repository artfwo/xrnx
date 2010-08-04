--[[============================================================================

 GlobalOscActions.lua

 DO NOT EDIT THIS FILE IN THE RENOISE RESOURCE FOLDER! UPDATING RENOISE WILL
 TRASH YOUR MODIFICATIONS!
 
 TO EXTEND THE DEFAULT OSC IMPLEMENTATION, COPY THIS FILE TO THE RENOISE 
 PREFERENCES SCRIPT FOLDER, THEN DO YOUR CHANGES THERE.

============================================================================]]--

--[[

 This file defines Renoise's default OSC server implementation. Besides the 
 messages and patterns you find here, Renoise already processes a few realtime 
 critical messages internally. Those will never be triggered here, and thus can
 not be overloaded here:
 
 
 ---- Realtime Messages
 
 /renoise/trigger/midi(message(u/int32/64))
 
 /renoise/trigger/note_on(instr(int32/64), track(int32/64), 
   note(int32/64), velocity(int32/64))
   
 /renoise/trigger/note_off(instr(int32/64), track(int32/64), 
   note(int32/64))

 
 ---- Message Format
 
 All other messages are handled in this script. 
 
 The message arguments are passed to the process function as a table 
 (array) of:

 argument = {
   tag, -- (OSC type tag. See http://opensoundcontrol.org/spec-1_0)
   value -- (OSC value as lua type: nil, boolean, number or a string)
 }
 
 Please note that the message patterns are strings !without! the "/renoise" 
 prefix in this file. But the prefix must be specified when sending something 
 to Renoise. Some valid message examples are:
 
 /renoise/trigger/midi (handled internally)
 /renoise/transport/start (handled here)
 ...
 
 
 ---- Remote evaluation of Lua expressions via OSC
 
 With the OSC message "/renoise/evaluate" you can evaluate Lua expressions 
 remotely, and thus do "anything" the Renoise Lua API offers remotely. This 
 way you don't need to edit this file in order to extend Renoise's OSC 
 implementation, but can do so in your client.
 
 "/renoise/evaluate" expects exactly one argument, the to be evaluated 
 Lua expression, and will run the expression in a custom, safe Lua environment. 
 This custom environment is a sandbox which only allows access to some global 
 Lua functions and the renoise.XXX modules. This means you can not change any 
 globals or locals from this script. Please see below (evaluate_env) for the 
 complete list of allowed functions and modules. 
 
]]


--------------------------------------------------------------------------------
-- Message Registration
--------------------------------------------------------------------------------

local action_pattern_map = table.create{}


-- argument

-- helper function to define a message argument for an action.
-- name is only needed when generating a list of available messages for the 
-- user. type is the expected lua type name for the OSC argument, NOT the OSC 
-- type tag. e.g. argument("bpm", "number")

local function argument(name, type)
  return { name = name, type = type }
end


-- add_action

-- register a global Renoise OSC message
-- info = {
--   pattern,     -> required. OSC message pattern like "/transport/start"
--   description, -> optional. string which describes the action
--   arguments    -> optional. table of arguments (see function 'argument')
--   handler      -> required. function which applies the action.
-- }

local function add_action(info)

  -- validate actions, help finding common errors and typos
  if not (type(info.pattern) == "string" and 
          type(info.handler) == "function") then
    error("An OSC action needs at least a 'pattern' and "..
      "'handler' function property.")
  end
  
  if not (type(info.description) == "nil" or 
          type(info.description) == "string") then
    error(("OSC action '%s': OSC message description should not be "..
      "specified or should be a string"):format(info.pattern))
  end
  
  if not (type(info.arguments) == "nil" or 
          type(info.arguments) == "table") then
    error(("OSC action '%s': OSC arguments should not be specified or "..
      "should be a table"):format(info.pattern))
  end
    
  for _, argument in pairs(info.arguments or {}) do
    if (argument.type ~= "number" and 
        argument.type ~= "string" and
        argument.type ~= "boolean")
    then
      error(("OSC action '%s': unexpected argument type '%s'. "..
        "expected a lua type (number, string or boolean)"):format(
        info.pattern, argument.type or "nil"))
      end
  end
    
  if (action_pattern_map[info.pattern] ~= nil) then 
    error(("OSC pattern '%s' is already registered"):format(info.pattern))
  end
  
  -- register the action
  info.arguments = info.arguments or {}
  info.description = info.description or "No description available"

  action_pattern_map[info.pattern] = info
end
 

--------------------------------------------------------------------------------
-- Message Helpers
--------------------------------------------------------------------------------

-- clamp_value

local function clamp_value(value, min_value, max_value)
  return math.min(max_value, math.max(value, min_value))
end


--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

-- environment for custom expressions via OSC. such expressions can only 
-- access a few "safe" globals and modules

local evaluate_env = {
  _VERSION = _G._VERSION,
  
  math = table.rcopy(_G.math),
  renoise = table.rcopy(_G.renoise),
  string = table.rcopy(_G.string),
  table = table.rcopy(_G.table),
  assert = _G.assert,
  error = _G.error,
  ipairs = _G.ipairs,
  next = _G.next,
  pairs = _G.pairs,
  pcall = _G.pcall,
  print = _G.print,
  select = _G.select,
  tonumber = _G.tonumber,
  tostring = _G.tostring,
  type = _G.type,
  unpack = _G.unpack,
  xpcall = _G.xpcall
}

-- compile and evaluate an expression in the evaluate_env sandbox

local function evaluate(expression)
  local eval_function, message = loadstring(expression)
  
  if (not eval_function) then 
    -- failed to compile
    return nil, message 
  
  else
    -- run and return the result...
    setfenv(eval_function, evaluate_env)
    return pcall(eval_function)
  end
end


--------------------------------------------------------------------------------

-- evaluate

add_action { 
  pattern = "/evaluate", 
  description = "Evaluate a custom Lua expression, like e.g.\n" ..
    "'renoise.song().transport.bpm = 234'",
  
  arguments = { argument("expression", "string") },
  handler = function(expression)
    print(("OSC Message: evaluating '%s'"):format(expression))

    local succeeded, error_message = evaluate(expression)
    if (not succeeded) then
      print(("*** expression failed: '%s'"):format(error_message))
    end
  end,
}


--------------------------------------------------------------------------------

-- transport

add_action { 
  pattern = "/transport/start", 
  description = "Start playback or restart playing the current pattern.",
  
  arguments = nil,
  handler = function()
    local play_mode = renoise.Transport.PLAYMODE_RESTART_PATTERN
    renoise.song().transport:start(play_mode)
  end,  
}

add_action { 
  pattern = "/transport/stop", 
  description = "Stop playback.",
  
  arguments = nil,
  handler = function()
    renoise.song().transport:stop()
  end,
}

add_action { 
  pattern = "/transport/bpm", 
  description = "Set the songs current BPM [32-999]",
  
  arguments = { argument("bpm", "number") },
  handler = function(bpm)
    renoise.song().transport.bpm = clamp_value(bpm, 32, 999)
  end,
}

add_action {
  pattern = "/transport/lpb", 
  description = "Set the songs current Lines Per Beat [1-255]",

  arguments = { argument("lpb", "number") }, 
  handler = function(lpb)
    renoise.song().transport.lpb = clamp_value(lpb, 1, 255)
  end,  
}


--------------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------------

-- available_messages

-- called by Renoise to show info about all available messages in the 
-- OSC preferences pane

function available_messages()
  local ret = table.create()

  for _, action in pairs(action_pattern_map) do
    local argument_types = table.create()
    for _, argument in pairs(action.arguments) do
      argument_types:insert(argument.type)
    end
    
    ret:insert {
      name = action.pattern,
      description = action.description,
      arguments = argument_types
    }
  end
    
  return ret
end


--------------------------------------------------------------------------------

-- process_message

-- called by Renoise in order to process an OSC message. the returned boolean 
-- is only used for the OSC log view in the preferences  (handled = false will 
-- log messages as REJECTED) 
-- Lua runtime errors that may happen here, will never be shown as errors to 
-- the user, but only dumped to the Lua terminal in Renoise.

function process_message(pattern, arguments)
  local handled = false
  local action = action_pattern_map[pattern]
  
  -- find message, compare argument count
  if (action and #action.arguments == #arguments) then
    local arguments_match = true
    local argument_values = table.create{}
    
    -- check argument types
    for i = 1, #arguments do
      if (action.arguments[i].type == type(arguments[i].value)) then 
        argument_values:insert(arguments[i].value)
      else
        arguments_match = false
        break
      end
    end
    
    -- invoke the action
    if (arguments_match) then
      action.handler(unpack(argument_values))
      handled = true
    end
  end
    
  return handled
end


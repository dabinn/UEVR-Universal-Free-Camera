-- File:    libgamepad.lua
-- Brief:   DS UEVR gamepad library
-- Details: Button configuration and XInput event handling
-- License: MIT
-- Version: 1.2.0
-- Date:    2025/03/16
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

-- Initialize the library and global variables
print("---------- ds-uevr/libcontroller init ----------")
local uId ="DS-Gamepad" -- Unique ID for this plugin
local lib=require("ds-uevr/libcommon")
local events = require("ds-uevr/libevents")
local te=TofuExpress
local function uprint(...)
    lib.uprint(uId, ...)
end

local gamepad={}
gamepad.xinput_enabled = true -- Enable or disable the xinput events
gamepad.STICK_DEADZONE = 0.2 -- Deadzone for the thumbsticks
gamepad.STICK_MAX = 32767
gamepad.TRIGGER_MAX = 255
local LT_RT_THRESHOLD_PERCENT = 0.5 -- Threshold percentages for LT and RT
local LT_RT_THRESHOLD = gamepad.TRIGGER_MAX * LT_RT_THRESHOLD_PERCENT

-- XINPUT Button constants
-- https://learn.microsoft.com/zh-tw/windows/win32/api/xinput/ns-xinput-xinput_gamepad
-- XINPUT_GAMEPAD_DPAD_UP:          1 (0x0001)
-- XINPUT_GAMEPAD_DPAD_DOWN:        2 (0x0002)
-- XINPUT_GAMEPAD_DPAD_LEFT:        4 (0x0004)
-- XINPUT_GAMEPAD_DPAD_RIGHT:       8 (0x0008)
-- XINPUT_GAMEPAD_START:           16 (0x0010)
-- XINPUT_GAMEPAD_BACK:            32 (0x0020)
-- XINPUT_GAMEPAD_LEFT_THUMB:      64 (0x0040)
-- XINPUT_GAMEPAD_RIGHT_THUMB:    128 (0x0080)
-- XINPUT_GAMEPAD_LEFT_SHOULDER:  256 (0x0100)
-- XINPUT_GAMEPAD_RIGHT_SHOULDER: 512 (0x0200)
-- XINPUT_GAMEPAD_A:             4096 (0x1000)
-- XINPUT_GAMEPAD_B:             8192 (0x2000)
-- XINPUT_GAMEPAD_X:            16384 (0x4000)
-- XINPUT_GAMEPAD_Y:            32768 (0x8000)
---- Unofficial / Reserved
-- XINPUT_GAMEPAD_GUIDE:       1024 (0x0400)
-- XINPUT_GAMEPAD_RESERVED:    2048 (0x0800)

-- Extend the original UEVR XINPUT constants
XINPUT_GAMEPAD_GUIDE = 0x0400
XINPUT_GAMEPAD_RESERVED = 0x0800
XINPUT_GAMEPAD_LEFT_TRIGGER = 0x10000
XINPUT_GAMEPAD_RIGHT_TRIGGER = 0x20000


gamepad.buttonDef = {
    DPadUp = 0,      -- XINPUT_GAMEPAD_DPAD_UP          1 (0x0001)
    DPadDown = 1,    -- XINPUT_GAMEPAD_DPAD_DOWN        2 (0x0002)
    DPadLeft = 2,    -- XINPUT_GAMEPAD_DPAD_LEFT        4 (0x0004)
    DPadRight = 3,   -- XINPUT_GAMEPAD_DPAD_RIGHT       8 (0x0008)
    Start = 4,       -- XINPUT_GAMEPAD_START           16 (0x0010)
    Back = 5,        -- XINPUT_GAMEPAD_BACK            32 (0x0020)
    L3 = 6,          -- XINPUT_GAMEPAD_LEFT_THUMB      64 (0x0040)
    R3 = 7,          -- XINPUT_GAMEPAD_RIGHT_THUMB    128 (0x0080)
    LB = 8,          -- XINPUT_GAMEPAD_LEFT_SHOULDER  256 (0x0100)
    RB = 9,          -- XINPUT_GAMEPAD_RIGHT_SHOULDER 512 (0x0200)
    Guide = 10,      -- XINPUT_GAMEPAD_GUIDE         1024 (0x0400) -- Unofficial / Reserved
    Reserved = 11,   -- XINPUT_GAMEPAD_RESERVED      2048 (0x0800) -- Unofficial / Reserved
    A = 12,          -- XINPUT_GAMEPAD_A             4096 (0x1000)
    B = 13,          -- XINPUT_GAMEPAD_B             8192 (0x2000)
    X = 14,          -- XINPUT_GAMEPAD_X            16384 (0x4000)
    Y = 15,          -- XINPUT_GAMEPAD_Y            32768 (0x8000)
    LT = 16,         -- XINPUT_GAMEPAD_LEFT_TRIGGER 65536 (0x10000)  -- Custom
    RT = 17          -- XINPUT_GAMEPAD_RIGHT_TRIGGER 131072 (0x20000) -- Custom
}
gamepad.axesDef = {
    LX = "sThumbLX",
    LY = "sThumbLY",
    RX = "sThumbRX",
    RY = "sThumbRY",
    LT = "bLeftTrigger",
    RT = "bRightTrigger"
}

local interceptConfigDefault = {
    axes = {"LX", "LY", "RX", "RY", "LT", "RT"},
    buttons = {"DPadUp", "DPadDown", "DPadLeft", "DPadRight", "Start", "Back", "L3", "R3", "LB", "RB", "A", "B", "X", "Y", "Guide", "Reserved"}
}

local buttonDefLower = {}
local function buttonDefToLower()
    buttonDefLower = {}
    for key, value in pairs(gamepad.buttonDef) do
        buttonDefLower[key:lower()] = value
    end
end
buttonDefToLower() -- convert buttonDef for parseButtonConfigs()


local interceptAxesNames = {}
local interceptButtonMask = 0
-- Function to set and optionally use custom intercept configuration
-- If no arguments are provided, it will disable the custom configuration and revert to the default configuration.
function gamepad.setInterceptConfig(config)
    interceptAxesNames = {}
    interceptButtonMask = 0

    local intercept = config or interceptConfigDefault -- When config set to nil, use default configuration
    interceptAxesNames = {}
    if type(intercept.axes) == "table" then
        for _, axes in ipairs(intercept.axes) do
            interceptAxesNames[axes] = gamepad.axesDef[axes]
        end
    end
    interceptButtonMask = 0
    if type(intercept.buttons) == "table" then
        for _, button in ipairs(intercept.buttons) do
            interceptButtonMask = interceptButtonMask | (1 << gamepad.buttonDef[button])
        end
    end
end

-- Function to intercept gamepad input
function gamepad.intercept(state)
    -- Disable input from the gamepad to the game based on the configuration
    for _, axisName in pairs(interceptAxesNames) do
        state.Gamepad[axisName] = 0
    end
    state.Gamepad.wButtons = state.Gamepad.wButtons & ~interceptButtonMask
end

gamepad.axisExpoFactor = 1/2 -- Exponent factor for the thumbstick input
-- Function to calculate the percentage of a number raised to an exponent
function gamepad.expoPercent(percentage, exp)
    return percentage^(1/exp)
end

-- Calculate deadzone by percentages
function gamepad.calcDeadzone(percent)
    -- Apply deadzone and normalize
    if math.abs(percent) < gamepad.STICK_DEADZONE then
        return 0
    else
        local normalizedPercent = (percent - lib.sign(percent) * gamepad.STICK_DEADZONE) / (1 - gamepad.STICK_DEADZONE)
        local expoAdjusted = gamepad.expoPercent(math.abs(normalizedPercent), gamepad.axisExpoFactor) -- Apply exponent to absolute value
        return lib.sign(percent) * expoAdjusted -- Restore the original sign
    end
end

-- Config example:
-- buttons = {
--     active = "L3_held",
--     deactive = "L3",
--     resetCam = "R3+Back",
--     speedIncrease = "RB",
--     speedDecrease = "LB",
-- },
-- axes = {
--     move={"LX", "LTRT"},
--     rot={"RX", "RY"},
--     elev={"LY"},
-- }
function gamepad.generateAndSetInterceptConfig(controlConfig)
    local axesConfig = controlConfig.axes
    local buttonsConfig = controlConfig.buttons
    local interceptConfig = {}
    interceptConfig.buttons = {}
    interceptConfig.axes = {}

    -- Process axes
    for motion, axesNames in pairs(axesConfig) do
        for _, axisName in ipairs(axesNames) do
            if axisName == "LTRT" then
                table.insert(interceptConfig.axes, "LT")
                table.insert(interceptConfig.axes, "RT")
            else
                table.insert(interceptConfig.axes, axisName)
            end
        end
    end

    -- Process buttons
    for actionName, buttonConfig in pairs(buttonsConfig) do
        local buttonCombo = buttonConfig:split("+")
        for _, buttonAndEvent in ipairs(buttonCombo) do
            local buttonAndEventParts = buttonAndEvent:split("_")
            local btName = buttonAndEventParts[1]
            -- check BT name with the buttonDefLower
            local btIndex = buttonDefLower[btName:lower()]
            if btIndex ~= nil then
                table.insert(interceptConfig.buttons, btName)
            end
        end
    end
    -- uprint("* Gamepad interception:")
    -- lib.printTable(interceptConfig)
    gamepad.setInterceptConfig(interceptConfig)
end

-- Map the axisName to the axis pecentage
function gamepad.getAxisPercent(state, axisName)
    if axisName == "" then
        return 0
    elseif axisName == "LTRT" then
        return (-state.Gamepad.bLeftTrigger + state.Gamepad.bRightTrigger) / gamepad.TRIGGER_MAX
    elseif axisName == "LT" or axisName == "RT" then
        return  (state.Gamepad[gamepad.axesDef[axisName]])  / gamepad.TRIGGER_MAX
    else
        return gamepad.calcDeadzone(state.Gamepad[gamepad.axesDef[axisName]] / gamepad.STICK_MAX)
    end
end

function gamepad.mapAxes(state, axesConfig)
    -- Initialize the axes percentages
    local axes = {}
    axes.move = {x = 0, y = 0}
    axes.rot = {x = 0, y = 0}
    axes.elev = 0

    -- converting state.Gamepad.<axis> value mapping here first
    for motion, _ in pairs(axes) do
        local axesNames = axesConfig[motion]
        if axesNames then -- if the motion is not defined, default value 0 will be keeping
            if motion == "elev" then
                axes[motion] = gamepad.getAxisPercent(state, axesNames[1])
            else
                axes[motion].x = gamepad.getAxisPercent(state, axesNames[1])
                axes[motion].y = gamepad.getAxisPercent(state, axesNames[2])
            end
        end
    end
    return axes
end


-- XInput event handling 
----------------------------------------

local buttonState = {}
local debounceTime = 0.01 -- Debounce time interval (seconds), seems not working well 
local doubleClickTime = 0.3 -- Double click time interval (seconds)
local heldTime = 0.4 -- Time interval to consider a button as held (seconds)
local buttonEventTriggered = 0 -- Determines whether to emit an event
-- button event generator
--------------------------------
-- For easy callback handling.
-- state.holding: true/false, triggers immediately when the button is pressed and continues to emit until released. This represents the state coming from gamepad.state.
-- state.event: nil/pressed/released. These events occur once when the button is pressed or released, signaling specific actions.
-- state.condition: nil/push/held/doubleclick. Represents special states triggered after specific conditions are met.
-- Unlike state.holding, condition=held only triggers once after the button is held for a certain duration.
local function updateButtonState(btIndex, isPressed)
    local currentTime = os.clock()
    if not buttonState[btIndex] then
        buttonState[btIndex] = {holding=false, event=nil, condition=nil, pressTime=0, releaseTime=0, clickCount=0}
    end

    local lastState = {}
    -- Fiil last state fields
    for k, v in pairs(buttonState[btIndex]) do
        lastState[k] = v
    end
    local state = buttonState[btIndex]
    -- Initialize new state
    -- state.condition is always kept, this helps to distinguish what is happening.
    state.holding = isPressed
    state.event = nil

    local pressTimeDelta = currentTime - lastState.pressTime
    local releaseTimeDelta = currentTime - lastState.releaseTime
    if isPressed then
        if not lastState.holding then -- new pressed 
            -- debounce, ignore the press withing debounceTime
            if releaseTimeDelta < debounceTime then
                -- supress the holding state to prevent emit a event
                state.holding = false
                uprint ("debounce1:"..releaseTimeDelta)
            else
                state.condition = "push"
                state.event = "pressed"
                state.pressTime = currentTime
            end
        else
            -- Triggers held event when the button is held for a certain duration
            if lastState.condition ~= "held" and pressTimeDelta >= heldTime then
                state.condition = "held"
                state.event = "pressed"
            end
        end


    else -- not pressed now
        if lastState.holding then
            -- debounce, ignore the release withing debounceTime
            if pressTimeDelta < debounceTime then
                -- override the pressed state to prevent the release event
                state.holding = true
                uprint ("debounce2:"..pressTimeDelta) -- never saw this happen
            else
                state.event = "released"
                state.releaseTime = currentTime
            end
        else -- previous state is not pressed
            -- do nothing
        end
    end

    -- Double click handling
    if state.condition=="push" and state.event == "pressed" then -- Filter out held condition
        if pressTimeDelta < doubleClickTime then
            state.clickCount = state.clickCount + 1
            if state.clickCount > 1 then
                state.condition = "doubleclick"
                state.clickCount = 0
            end
        else
            -- reset clickCount when it exceeds double click time limit
            state.clickCount = 1
        end
    end

    -- Helps quickly determine if we need to emit the event
    if state.holding or state.event then
        buttonEventTriggered = buttonEventTriggered + 1
    end
end

-- Update the state of all buttons
local function updateAllButtonStates(state)
    local btDef = gamepad.buttonDef
    buttonEventTriggered = 0
    for btName, btIndex in pairs(btDef) do
        if btName ~= "LT" and btName ~= "RT" then
            local buttonMask = 2 ^ btIndex
            updateButtonState(btIndex, (state.Gamepad.wButtons & buttonMask) ~= 0)
        end
    end

    -- Custom button events for LT/RT
    -- LT/RT are not included in the wButtons mask, so we need to handle them separately
    updateButtonState(btDef["LT"], state.Gamepad.bLeftTrigger > LT_RT_THRESHOLD)
    updateButtonState(btDef["RT"], state.Gamepad.bRightTrigger > LT_RT_THRESHOLD)

    if buttonEventTriggered > 0 then
        events:emit("xinput_button_changed", buttonState)
    end
end

local lastXinputTime = os.clock()
local lastuprintTime = os.clock()
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if not gamepad.xinput_enabled then return end

    local currentTime = os.clock()
    local deltaTime = currentTime - lastXinputTime

    lastXinputTime = currentTime
    if currentTime - lastuprintTime >= 1 then
        -- lzDebug("XInput state: " .. state.Gamepad.sThumbLX .. ", " .. state.Gamepad.sThumbLY .. ", " .. state.Gamepad.sThumbRX .. ", " .. state.Gamepad.sThumbRY .. ", " .. state.Gamepad.bLeftTrigger .. ", " .. state.Gamepad.bRightTrigger)
        lastuprintTime = currentTime
    end

    -- Generate button events
    updateAllButtonStates(state)
    -- Pass axes state
    events:emit("xinput_state_changed", retval, user_index, state)

end)



-- Button configuration handling
----------------------------------------

local function parseButtonConfigs(actionName, buttonConfig)
    local buttonAction = {}
    buttonAction.name = actionName
    buttonAction.mappings = {}
    local buttonCombo = buttonConfig:split("+")
    for _, buttonAndEvent in ipairs(buttonCombo) do
        local buttonAndEventParts = buttonAndEvent:split("_")
        local btName = buttonAndEventParts[1]
        local btNameLower = buttonAndEventParts[1]:lower()
        local event = buttonAndEventParts[2] or "released" -- Default event is "released"
        event = event:lower()
        -- check BT name with the buttonDef
        local btIndex = buttonDefLower[btNameLower]
        if btIndex == nil then
            uprint("*** WARNING!! *** Invalid button name: " .. btName)
            -- still write the button name to the config, but set the index to -1
            btIndex = -1
        end
        uprint(actionName..": " .. btName .. ", event: " .. event)
        table.insert(buttonAction.mappings, {btName = btName, btIndex=btIndex, event = event:lower()})
    end
    return buttonAction
end

-- Convert the button configuration to buttonActions table
-- button configuration (control.buttons) --parser-> buttonActions
-- Structure of buttonActions:
-- buttonActions = {
--     buttonAction = {
--         name = actionName,
--         mappings = {
--             {btName = "A", btIndex = 12, event = "pressed"},
--             {btName = "B", btIndex = 13, event = "released"}
--         }
--     }
-- }
function gamepad.updateButtonActions(buttons)
    local buttonActions = {}
    local keys = {}
    for actionName in pairs(buttons) do
        table.insert(keys, actionName)
    end
    table.sort(keys)

    for _, actionName in ipairs(keys) do
        local buttonConfig = buttons[actionName]
        buttonActions[actionName] = parseButtonConfigs(actionName, buttonConfig)
    end
    return buttonActions
end



-- Functions to check button states
----------------------------------------

-- For button debug
gamepad.buttonDebugEnabled = false
function gamepad.buttonDebug(buttonName)
    if not gamepad.buttonDebugEnabled then
        return
    end
    -- btnState should be the same as buttonState
    -- Just passed as a parameter for debugging purposes
    local state = buttonState[gamepad.buttonDef[buttonName]]
    if not state then
        uprint("buttonDebug: " .. buttonName .. " is not found.")
        return
    end
    local btn={}
    btn.e = state.event
    if btn.e then
        btn.h = state.holding and "[o]" or "[ ]"
        btn.c = state.condition
        uprint("buttonDebug: " .. buttonName .. " " .. tostring(btn.h) .. "" .. tostring(btn.c) .. "_" .. tostring(btn.e))
    end
end

-- Check all buttons are set to held event
function gamepad.isHeldButtons(buttonAction)
    if not buttonAction then
        return false
    end
    local mappings = buttonAction.mappings
    if mappings == nil or #mappings < 1 then
        return false

    -- Combo buttons are treat as held button by default
    elseif #mappings > 1 then
        return true
    end

    -- Single button
    local mapping = buttonAction.mappings[1]
    if mapping.event == "held" then
        return true
    end
end


-- Only checks state.holding property.
-- So the event will be triggered every cycle when the button is holding.
function gamepad.checkButtonsNotHolding(buttonAction)
    local mappings = buttonAction.mappings
    if mappings == nil then
        return false
    end
    local allButtonsStateMatch = true
    for _, mapping in ipairs(mappings) do
        local state = buttonState[mapping.btIndex]
        if not (state and state.holding == false) then
            -- uprint("Button state not match")
            allButtonsStateMatch = false
            break
        end
    end

    return allButtonsStateMatch
end
-- Only checks state.holding property.
-- So the event will be triggered every cycle when the button is holding.
function gamepad.checkButtonsHolding(buttonAction)
    if not buttonAction then
        return false
    end
    local mappings = buttonAction.mappings
    if mappings == nil then
        return false
    end
    local allButtonsStateMatch = true
    for _, mapping in ipairs(mappings) do
        local state = buttonState[mapping.btIndex]
        if not (state and state.holding == true) then
            -- uprint("Button state not match")
            allButtonsStateMatch = false
            break
        end
    end

    return allButtonsStateMatch
end


-- Check one or all buttons released event
-- both state.holding and event.released are checked to make sure the event will be triggered only once.
function gamepad.checkButtonsReleased(buttonAction)
    -- Check all buttons are NOT holding first
    if not gamepad.checkButtonsNotHolding(buttonAction) then
        return false
    end

    -- We need 1 released event (emitted by the latest released button)
    local mappings = buttonAction.mappings
    local oneButtonsStateMatch = false
    for _, mapping in ipairs(mappings) do
        local state = buttonState[mapping.btIndex]
        if (state and state.event== "released") then
            oneButtonsStateMatch = true
            break
        end
    end

    return oneButtonsStateMatch
end

-- Check one or all buttons pressed event
-- both state.holding and event.pressed are checked to make sure the event will be triggered only once.
function gamepad.checkButtonsPressed(buttonAction)

    -- Check all buttons are holding first
    if not gamepad.checkButtonsHolding(buttonAction) then
        return false
    end

    -- We need 1 pressed event (emitted by the latest pressed button)
    local mappings = buttonAction.mappings
    local oneButtonsStateMatch = false
    for _, mapping in ipairs(mappings) do
        local state = buttonState[mapping.btIndex]
        if (state and state.condition~="held" and state.event== "pressed") then -- held will triggers 2nd pressed event
            oneButtonsStateMatch = true
            break
        end
    end

    return oneButtonsStateMatch
end
-- Check if the specific button actions match the button state
function gamepad.checkButtonsState(buttonAction)
    if not buttonAction then
        return false
    end
    local mappings = buttonAction.mappings
    if mappings == nil then
        return false
    elseif #mappings == 0 then
        uprint("Button config is empty.")
        return false

    elseif #mappings > 1 then
    -- Combo buttons, use checkButtonsPressed instead
        return gamepad.checkButtonsPressed(buttonAction)
    end

    -- Single button
    local mapping = mappings[1]
    local state = buttonState[mapping.btIndex]

    if not state then
        uprint("Button name is wrong: " .. mapping.btName)
        return false

    -- User customized action events:
    -- pressed, released, held, doubleclick (default: released)
    elseif state.event == "released" then
        if mapping.event == "released" and state.condition ~= "held" then -- condition matches push and doubleclick
            return true
        elseif mapping.event == "doubleclick" and state.condition == "doubleclick" then
            return true
        end
    elseif state.event == "pressed" then
        if mapping.event == "held" and state.condition == "held" then
            return true
        elseif mapping.event == "pressed" and state.condition ~= "held" then -- condition matches push and doubleclick
            return true
        end
    end
    return false
end


return gamepad



-- Usage example:
--[[
local events = require("ds-uevr/"libevents")
local eventGen = require("ds-uevr/libeventgen")

-- Enable event generator
eventGen.enabled = true

-- Define listener functions
local function onButtonEvents(buttonStates)
    for button, state in pairs(buttonStates) do
        if state.event then
            print("Button " .. button .. " " .. state.event)
        end
    end
end

-- Register the listener for the xinput button events
events:on('xinput_button_changed', onButtonEvents)

-- Register an anonymous function for the xinput button events
events:on('xinput_button_changed', function(buttonStates)
    for button, state in pairs(buttonStates) do
        if state.event then
            print("Anonymous function: Button " .. button .. " " .. state.event)
        end
    end
end)

-- Unregister the 'onButtonEvents' listener
events:off('xinput_button_changed', onButtonEvents)
]]

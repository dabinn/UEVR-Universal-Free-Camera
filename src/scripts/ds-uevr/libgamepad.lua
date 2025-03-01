-- File:    libgamepad.lua
-- Brief:   DS UEVR gamepad library
-- Details: Button configuration and XInput event handling
-- License: MIT
-- Version: 1.0.0
-- Date:    2025/02/21
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
buttonDefToLower() -- convert buttonDef for parseButtonAction()


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

-- Calculate deadzone by percentages
function gamepad.calcDeadzone(percent)
    -- Apply deadzone and normalize
    if math.abs(percent) < gamepad.STICK_DEADZONE then
        return 0
    else
        return (percent - lib.sign(percent) * gamepad.STICK_DEADZONE) / (1 - gamepad.STICK_DEADZONE)
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


--- Button configuration handling
--------------------------------
local function parseButtonAction(actionName, config)
    local buttonConfigs = {}
    local buttonCombo = config:split("+")
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
        table.insert(buttonConfigs, {btName = btName, btIndex=btIndex, event = event:lower()})
    end
    return buttonConfigs
end

-- Convert the button configuration to buttonActions table
function gamepad.updateButtonActions(buttons)
    local buttonActions = {}
    local keys = {}
    for actionName in pairs(buttons) do
        table.insert(keys, actionName)
    end
    table.sort(keys)

    for _, actionName in ipairs(keys) do
        local config = buttons[actionName]
        buttonActions[actionName] = parseButtonAction(actionName, config)
    end
    return buttonActions
end


-- This is the simple version of checkButtonHold, only check the hold property
function gamepad.checkButtonHoldState(buttonState, buttonConfigs)
    if buttonConfigs == nil then
        -- uprint("Button config is nil")
        return false
    end
    -- Single button: When event set to held, check hold property instead.
    if #buttonConfigs == 1 then
        local buttonConfig = buttonConfigs[1]
        local state = buttonState[buttonConfig.btIndex]
        if state and state.hold == true then
            return true
        end
        return false
    end

    -- Multi button combo: Ignore user defined buttonConfig.event, only check hold property.
    local allButtonStateMatch = true
    for _, buttonConfig in ipairs(buttonConfigs) do
        local state = buttonState[buttonConfig.btIndex]
        if not (state and state.hold == true) then
            -- uprint("Button state not match")
            allButtonStateMatch = false
            break
        end
    end

    return allButtonStateMatch
end

-- This is the real button pressed state
-- not as the same as event=pressed or event=held
-- Single button: When event set to held, check hold property instead.
function gamepad.checkButtonHold(buttonState, buttonConfigs)
    if buttonConfigs == nil then
        -- uprint("Button config is nil")
        return false
    end
    -- Single button: When event set to held, check hold property instead.
    if #buttonConfigs == 1 then
        local buttonConfig = buttonConfigs[1]
        local state = buttonState[buttonConfig.btIndex]
        if buttonConfig.event then 
            if buttonConfig.event == "held" then
                if state and state.hold == true then
                    return true
                end
            else
                if state and state.event == buttonConfig.event then
                    return true
                end
            end
        end
        return false
    end

    -- Multi button combo: Ignore user defined buttonConfig.event, only check hold property.
    local allButtonStateMatch = true
    for _, buttonConfig in ipairs(buttonConfigs) do
        local state = buttonState[buttonConfig.btIndex]
        if not (state and state.hold == true) then
            -- uprint("Button state not match")
            allButtonStateMatch = false
            break
        end
    end

    return allButtonStateMatch
end

function gamepad.checkButtonState(buttonState, buttonConfigs)
    if buttonConfigs == nil then
        return false
    elseif #buttonConfigs > 1 then  -- Combo buttons, use checkButtonHold instead
        return gamepad.checkButtonHold(buttonState, buttonConfigs)
    elseif #buttonConfigs == 0 then
        uprint("Button config is empty.")
        return false
    end
    -- Check single button state or multi-button combo
    local buttonConfig = buttonConfigs[1]
    local state = buttonState[buttonConfig.btIndex]
    if not state then
        uprint("Button name is wrong: " .. buttonConfig.btName)
        return false
    elseif state.event == buttonConfig.event or (buttonConfig.event == "doubleclick" and state.doubleclick==true) then
        return true
    end
    return false
end

-- Check if the button is a hold button
function gamepad.isAHoldButton(buttonConfigs)
    -- combo butons are hard to hold, just use thme as toggle not hold
    if buttonConfigs == nil or #buttonConfigs > 1 then
        return false
    end
    local buttonConfig = buttonConfigs[1]
    if buttonConfig.event == "held" then
        return true
    end
    return false
end




---------- XInput event handling ----------


local buttonState = {}
local debounceTime = 0.01 -- Debounce time interval (seconds), seems not working well 
local doubleClickTime = 0.925 -- Double click time interval (seconds)
local heldTime = 0.6 -- Time interval to consider a button as held (seconds)
local buttonEventTriggered = 0 -- Determines whether to emit an event

-- button event generator
-- state.hold: true/false, the 'real' push down state of the button. This allows the callback to determine the holding state.
-- state.event: nil/pressed/released/held/heldreleased/doubleclick. For easy callback handling.
-- # The difference between state.hold and event=held: 
-- hold triggers as long as the button is pressed (including press and held), 
-- held triggers only after the button has been held for a certain period of time
-- # Single trigger and multiple triggers
-- press/release will only trigger once to avoid the callback needing to handle it separately
-- hold/held will trigger continuously
-- hold_release is usually not used, it just allows the callback to skip detecting the release state
local function updateButtonState(btIndex, isPressed)
    local currentTime = os.clock()
    if not buttonState[btIndex] then
        buttonState[btIndex] = {hold = false, event = nil, doubleclick=false, lastPress = nil, lastPressTime = 0, lastReleaseTime = 0, clickCount = 0, releaseCount = 0}
    end

    local state = buttonState[btIndex]
    local newPressed = isPressed

    -- clear event
    if state.event ~= "released" then -- record non-released event
        state.lastPress = state.event
    end
    state.event = nil
    state.doubleclick = false

    local lastPress = state.lastPress
    local pressTimeDelta = currentTime - state.lastPressTime
    local releaseTimeDelta = currentTime - state.lastReleaseTime
    if isPressed then
        if not state.hold then -- new pressed
            -- debounce, ignore the press withing debounceTime
            if releaseTimeDelta < debounceTime then
                -- newPressed = false
                uprint ("debounce1:"..releaseTimeDelta)
            else
                state.event = "pressed"
                state.lastPressTime = currentTime
                buttonEventTriggered = buttonEventTriggered + 1
            end
        else
            -- Will not trigger new pressed event when keep pressing for very short time
            if pressTimeDelta >= heldTime then
                state.event = "held"
            end
            -- Even held event not triggered, we still need inform state.hold for callbacks (with state.event=nil)
            buttonEventTriggered = buttonEventTriggered + 1
        end

    else -- not pressed now
        if state.hold then
            -- debounce, ignore the release withing debounceTime
            if pressTimeDelta < debounceTime then
                -- override the pressed state to prevent the release event
                newPressed = true
                uprint ("debounce2:"..pressTimeDelta) -- never saw this happen
            else
                state.releaseCount = 0
                state.event = "released"
                state.lastReleaseTime = currentTime
                buttonEventTriggered = buttonEventTriggered + 1

                if releaseTimeDelta > doubleClickTime then
                    -- reset clickCount when it exceeds double click time limit
                    local tmpCnt = state.clickCount 
                    if lastPress=="held" then -- released from held, will not trigger double click count
                        state.clickCount = 0
                        state.event = "heldreleased"
                    else
                        state.clickCount = 1
                    end
                    -- uprint("time: " .. releaseTimeDelta .. " ,cnt: " .. tmpCnt.."->"..state.clickCount)
                else
                    state.clickCount = state.clickCount + 1
                    -- uprint("time: " .. releaseTimeDelta .. " ,cnt: " .. state.clickCount)
                    if state.clickCount > 1 then
                        state.doubleclick = true
                        state.clickCount = 0
                        buttonEventTriggered = buttonEventTriggered + 1
                    end
                end
            end
        else -- previous state is not pressed
            -- do nothing        
        end
    end

    -- update state
    state.hold = newPressed
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

-- For 1 button test only (only 1 btn_lastEvent)
local btn_lastEvent =nil
function gamepad.buttonDebug(state)
    local btn_e = state.event
    if btn_e then
        if btn_lastEvent == "held" and btn_e == "held" then
           -- do nothing
        else
            -- for k, v in pairs(state) do
            --     uprint("Key: " .. tostring(k) .. "=" .. tostring(v))
            -- end
            uprint("buttonEvent: " .. btn_e)
            if state.doubleclick then
                uprint("buttonEvent: +doubleclick")
            end
        end
        btn_lastEvent = btn_e
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

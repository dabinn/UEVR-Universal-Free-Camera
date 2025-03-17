-- File:    ds-uevr-universal-freecam.lua
-- Brief:   DS UEVR Universal Free Camera plugin
-- Details: This plugin provides a universal free camera functionality for UEVR, 
--          allowing users to freely navigate and explore VR environments. It can 
--          be used as a standalone universal plugin or customized with specific 
--          parameters for other game plugins.
-- License: MIT
-- Version: 1.2.0
-- Date:    2025/03/16
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

-- Initialize the library and global variables
print("---------- ds-uevr-universal-freecam init ----------")
local uId ="DS-Univ-FreeCam" -- Unique ID for this plugin
local lib=require("ds-uevr/libcommon")
local te=TofuExpress

local function uprint(...)
    lib.uprint(uId, ...)
end

-- load  freecam
if not te.freecam then -- Check if freecam lib already loaded by another plugin
    uprint("Universal Free Camera")
else
    uprint("Custom Free Camera already loaded")
    return
end

local freecam = require("ds-uevr/libfreecam")
local cfg=freecam.extCfg

-- Available button codes:
-- A, B, X, Y 
-- LB, RB, L3, R3 (LT, RT are not implemented yet)
-- DPadUp, DPadDown, DPadLeft, DPadRight
-- Back, Start
-- To specify a button combination, use the "+" symbol. For example: "Select+Y"
-- To specify a special event (pressed, held, released, doubleclick), use these words separated by `_` with the button name.
-- For example: `L3_held`, `Select_pressed` 
-- Default event is "released" if not specified.
cfg.buttons = {
    active = "L3_held", -- Activate free camera
    deactive = "L3", -- Deactivate free camera
    resetCam = "R3", -- Reset the camera
    resetAll = "R3_held", -- Reset both the camera and the custom view
    speedIncrease = "RB", -- Increase movement speed
    speedDecrease = "LB", -- Decrease movement speed
    levelFlight = "X", -- Toggle level flight / omni-directional flight mode
    omniFlightWithSpaceControl = "X_held", -- Enable omni-directional flight mode with space control scheme
    followOn = "Y", -- Enable follow mode
    followPositionOnly = "Y_doubleclick", -- Enable follow position only mode
    followOff = "Y_held", -- Disable follow mode (Hold the camera)
    viewCycle = "Back", -- Cycle through saved views
    viewSave = "Back_held", -- Save the current view
    autoGameMenuToggle = "Start", -- Hide the game menu automatically when free camera is enabled
    -- disable = "B", -- for debug only
}

-- Speed Settings
cfg.spd={}
cfg.spd[1] = {
    speedTotalStep = 10,
    move_speed_max = 50000, -- cm per second
    move_speed_min = 50,
    rotate_speed_max = 270, -- degrees per second
    rotate_speed_min = 150, -- degrees per second
    currMoveStep = 4,
    currRotStep = 4
}

-- Freecam Parameters
cfg.opt={
    uevrAttachCameraCompatible = false, -- Compatible with UEVR's attached camera feature, affecting the camera offset value in the UEVR interface.
    autoGameMenuToggle = false, -- Disable game GUI when free camera is enabled
    freecamInvertPitch = false, -- Invert the pitch of the free camera
    levelFlight = true, -- The vertical orientation of the camera does not affect the flight altitude.
    recenterVROnCameraReset = true, -- Reset the camera and recenter VR at the same time
}

freecam.init()

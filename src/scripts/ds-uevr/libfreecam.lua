-- File:    libfreecam.lua
-- Brief:   DS UEVR Universal Free Camera library
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
print("---------- ds-uevr/libfreecam init ----------")
local uId ="DS-FreeCam" -- Unique ID for this plugin
local vr = uevr.params.vr
local lib=require("ds-uevr/libcommon")
local events = require("ds-uevr/libevents")
local eventgen = require("ds-uevr/libeventgen")
local gamepad = require("ds-uevr/libgamepad")
-- gamepad.buttonDebugEnabled = true

local te=TofuExpress
local function uprint(...)
    lib.uprint(uId, ...)
end


-- Indicates that the plugin is loaded, or for data exchange
if te.freecam == nil then
    te.freecam = {}
end

local freecam={}
freecam.cfg={}
freecam.extCfg={}

-- camera type
freecam.camType = {
    default = 0,    -- No processing
    free = 1,       -- Free camera: For all games, needs to toggle cam mode to activate.
    orbit = 2,      -- Orbit camera: Requires specifying the target position.
    scene = 3,      -- For specific scenes, cam offset/moveCam/rotateCam are customizable.
}
local camType = freecam.camType

-- freecam control scheme
local freecamControlType = {
    TPS=1,
    Space=2,
}

-- Default Parameters
local cfg = freecam.cfg
cfg.opt = {
    uevrAttachCameraCompatible = false, -- Compatible with UEVR's attached camera feature, affecting the camera offset value in the UEVR interface.
    autoGameMenuToggle = false, -- Disable game GUI when free camera is enabled
    freecamInvertPitch = false, -- Invert the pitch of the free camera
    levelFlight = true, -- The vertical orientation of the camera does not affect the flight altitude.
    freecamControlScheme = freecamControlType.TPS, -- Control scheme for free camera
    -- freecamControlScheme = controlType.Space, -- Control scheme for free camera
    follow = true, -- Follow both the game camera's position and rotation
    followPositionOnly = false, -- Only follow the game camera's position
    recenterVROnCameraReset = true, -- Reset the camera and recenter VR at the same time
    orbitcamSyncOrientationToFreecam = true, -- Sync the orientation of the orbit camera to the free camera
}
local opt = cfg.opt


local freecamAxes = {}
freecamAxes[freecamControlType.TPS] = {
    move={"LX", "LY"},
    rot={"RX", "RY"},
    elev={"LTRT"},
}
freecamAxes[freecamControlType.Space] = {
    move={"LX", "LTRT"},
    rot={"RX", "RY"},
    elev={"LY"},
}
-- Available button codes:
-- A, B, X, Y 
-- LB, RB, L3, R3 (LT, RT are not implemented yet)
-- DPadUp, DPadDown, DPadLeft, DPadRight
-- Back, Start
-- To specify a button combination, use the "+" symbol. For example: "Select+Y"
-- To specify a special event (pressed, held, released, doubleclick), use these words separated by `_` with the button name.
-- For example: `L3_held`, `Select_pressed` 
-- Default event is "released" if not specified.
cfg.controls ={}
local controls = cfg.controls
controls[camType.default] = {
    buttons = {},
    axes = {},
}
controls[camType.free] = {
    buttons = {
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
    },
    axes = freecamAxes[freecamControlType.TPS],
}
controls[camType.orbit] = {
    buttons = {
        -- camDolly = "RB_held",
        -- camOffset= "Back",
        -- resetCam = "R3",
    },
    axes = {
        rot={"RX", "RY"},
    },
}
controls[camType.scene] = {
    buttons = {
        -- camDolly = "RB_held",
        -- camOffset= "Back",
        -- resetCam = "R3",
    },
    axes = {
        -- move={"LX", "LY"},
        rot={"RX", "RY"},
        -- elev={"LTRT"},
    },
}

-- Converts button configurations into buttonActions
local camButtonActions = {} -- Store button actions for different camera modes

-- Axes configuration for current camera mode
local currCamModeAxes = controls[camType.default].axes

-- Speed settings for different camMode
cfg.spd={}
cfg.spd[camType.free] = {
    speedTotalStep = 10,
    move_speed_max = 50000, -- cm per second
    move_speed_min = 50,
    rotate_speed_max = 270, -- degrees per second
    rotate_speed_min = 150, -- degrees per second
    currMoveStep = 4,
    currRotStep = 4
}
cfg.spd[camType.orbit] = {
    speedTotalStep = 1, -- 1: no speed adjustment, only needs to set the max speed
    move_speed_max = 1000,
    rotate_speed_max = 90,
    currMoveStep = 1,
    currRotStep = 1
}
cfg.spd[camType.scene] = {
    speedTotalStep = 1, -- 1: no speed adjustment, only needs to set the max speed
    move_speed_max = 1000,
    rotate_speed_max = 90,
    currMoveStep = 1,
    currRotStep = 1
}
local spd = cfg.spd[1]

-- Default camera view offsets
local camViewPresets = {}
-- create default preset
for i = 1, 2 do
    camViewPresets[i] = {}
    camViewPresets[i].relPos = Vector3f.new(0, 0, 0)
    camViewPresets[i].relRot = Vector3f.new(0, 0, 0)
end
local camViewPresetNo = 1

-- Set libgamepad's interceptConfig based on axis and button configurations
-- = nil: use default config (intercepts all)
local customInterceptConfig = {}



-- local variables
local currCamMode = camType.default
local cam1ExitMode = camType.default -- Which Mode to switch to when exiting freecam1

-- Use Vector3d if this is a UE5 game (double precision)
local gameCamPos = Vector3f.new(0, 0, 0)
local gameCamRot = Vector3f.new(0, 0, 0)
local freeCamPos = Vector3f.new(0, 0, 0) -- Absolute position, including camView offset.
local freeCamRot = Vector3f.new(0, 0, 0)
local freeCamPosOffset = Vector3f.new(0, 0, 0) -- Offset from the game camera's local position
local freeCamRotOffset = Vector3f.new(0, 0, 0)
local camViewPosOffset = Vector3f.new(0, 0, 0)
local camViewRotOffset = Vector3f.new(0, 0, 0)
local freecamReinitialize = true

local inputPos = Vector3f.new(0, 0, 0)
local inputRot = Vector3f.new(0, 0, 0)


local freecamEnabled = true
local dollyKeyHeld = false

local viewTargetPos = nil -- Used for Orbit camera mode
local moveSpeed = 0
local rotSpeed = 0

local firstEye = true -- Used to determine the first eye in the stereo view offset calculation

-- XYZ Motions
----------------------------------------

local function calcSpeedLimiter(min, max, step)
    local logMin = math.log(min)
    local logMax = math.log(max)
    local logValue = logMin + (logMax - logMin) * (step - 1) / (spd.speedTotalStep - 1)
    return math.exp(logValue)
end

local function calcRotSpeed(step)
    if spd.speedTotalStep == 1 then
        return spd.rotate_speed_max
    end
    local speed = calcSpeedLimiter(spd.rotate_speed_min, spd.rotate_speed_max, step)
    return speed
end

local function calcMoveSpeed(step)
    if spd.speedTotalStep == 1 then
        return spd.move_speed_max
    end
    local speed = calcSpeedLimiter(spd.move_speed_min, spd.move_speed_max, step)
    return speed
end

local function adjustMoveSpeed(stepDir)
    spd.currMoveStep = spd.currMoveStep + 1 * stepDir
    spd.currMoveStep = math.max(1, math.min(spd.speedTotalStep, spd.currMoveStep))
    return calcMoveSpeed(spd.currMoveStep)
end

local function adjustRotSpeed(stepDir)
    spd.currRotStep = spd.currRotStep + 1 * stepDir
    spd.currRotStep = math.max(1, math.min(spd.speedTotalStep, spd.currRotStep))
    return calcRotSpeed(spd.currRotStep)
end

local function updateCamSpeed()
    moveSpeed = calcMoveSpeed(spd.currMoveStep)
    rotSpeed = calcRotSpeed(spd.currRotStep)
end

local function adjustCamSpeed(stepDir)
    moveSpeed = adjustMoveSpeed(stepDir)
    rotSpeed = adjustRotSpeed(stepDir)
    uprint("Move/Rot Speed: ["..spd.currMoveStep.."/"..spd.currRotStep.."] " .. moveSpeed .. " / "..rotSpeed)
end

local function moveCam(pctX, pctY, pctZ, deltaTime) -- send delta distance
    -- Calculate movement deltas
    -- UE: forward=x+, right=y+, up=z+ ,exchange stick x and y
    local moveDeltaX = -pctY * moveSpeed * deltaTime
    local moveDeltaY = pctX * moveSpeed * deltaTime
    local moveDeltaZ = pctZ * moveSpeed * deltaTime

    -- Update inputPos
    inputPos.x = inputPos.x - moveDeltaX
    inputPos.y = inputPos.y + moveDeltaY
    inputPos.z = inputPos.z + moveDeltaZ

    -- check if the distance is too far for x y z
    local maxDistance = 16777216.0 -- max float value?
    
    inputPos.x = math.max(-maxDistance, math.min(maxDistance, inputPos.x))
    inputPos.y = math.max(-maxDistance, math.min(maxDistance, inputPos.y))
    inputPos.z = math.max(-maxDistance, math.min(maxDistance, inputPos.z))
end

local function rotateCam(pctX, pctY, deltaTime) -- send delta rotation
    -- Calculate rotation deltas
    local rotateDeltaX = pctY * rotSpeed * deltaTime * (opt.freecamInvertPitch and -1 or 1)
    local rotateDeltaY = pctX * rotSpeed * deltaTime

    -- Update inputRot
    inputRot.x = inputRot.x + rotateDeltaX
    inputRot.y = inputRot.y + rotateDeltaY
    inputRot.z = 0

end


-- Public Functions
----------------------------------------

local function resetCam()
    -- Force freecam re-initialized to gameCam's Pos/Rot
    freecamReinitialize = true
    -- Re-applying the camera view offset
    lib.xyzSetInPlace(camViewPosOffset, camViewPresets[camViewPresetNo].relPos)
    lib.xyzSetInPlace(camViewRotOffset, camViewPresets[camViewPresetNo].relRot)
end

function freecam.resetCam()
    uprint("Reset camera.")
    resetCam()
end
function freecam.resetAll()
    uprint("Reset ALL.")
    -- Force freecam re-initialized to gameCam's Pos/Rot
    freecamReinitialize = true
    -- Clear the current offsets
    lib.xyzSetInPlace(camViewPosOffset, Vector3f.new(0, 0, 0))
    lib.xyzSetInPlace(camViewRotOffset, Vector3f.new(0, 0, 0))

    -- Set follow mode back to default
    freecam.followModeToggle(true)
end

-- Set the target position for the orbit camera
function freecam.setViewTargetPos(pos)
    viewTargetPos = pos
end

-- For scene swithing
-- Replaced the whole camViewPresets with the defination of the new scene
function freecam.setSceneCamViewPresets(sceneCamViewPresets, presetNo)
    local lastPresetNo = camViewPresetNo
    camViewPresets = sceneCamViewPresets
    freecam.switchCamViews(presetNo) -- Will update camOffsetsPresetNo
    return lastPresetNo
end

function freecam.switchCamViews(presetNo)
    inputPos = Vector3f.new(0, 0, 0) -- reset inputPos but keep inputRot
    if presetNo == 0 then -- switch to next preset
        camViewPresetNo = camViewPresetNo + 1
        if camViewPresetNo > #camViewPresets then
            camViewPresetNo = 1
        end
    else
        camViewPresetNo = presetNo
    end

    -- Force freecam re-initialized to gameCam's Pos/Rot
    freecamReinitialize = true
    lib.xyzSetInPlace(camViewPosOffset, camViewPresets[camViewPresetNo].relPos)
    lib.xyzSetInPlace(camViewRotOffset, camViewPresets[camViewPresetNo].relRot)

    uprint("Switch to camera preset "..camViewPresetNo.." ,offset: " .. camViewPosOffset.x .. ", " .. camViewPosOffset.y .. ", " .. camViewPosOffset.z )
end

function freecam.saveCamView()
    local presetNo = camViewPresetNo

    -- Calulate current offset
    -- relative position in gameCam's local space (Same as follow camera position's calculation)
    local posOffset = Vector3f.new(0, 0, 0)
    local rotOffset = Vector3f.new(0, 0, 0)

    -- if not viewTargetPos then
    --     posOffset = lib.kismet_math:LessLess_VectorRotator(freeCamPos - gameCamPos, gameCamRot)
    -- else
    --     local lookAtRot = lib.kismet_math:FindLookAtRotation(freeCamPos, viewTargetPos)
    --     posOffset = lib.kismet_math:LessLess_VectorRotator(freeCamPos - gameCamPos, lookAtRot)
    -- end
    -- rotOffset = freeCamRot - gameCamRot
    posOffset = freeCamPosOffset:clone()
    rotOffset = freeCamRotOffset:clone()

    -- Update preset data
    camViewPresets[presetNo].relPos = posOffset
    camViewPresets[presetNo].relRot = rotOffset
    -- Also record the absolute position, which might be useful for holding the camera.
    camViewPresets[presetNo].absPos = freeCamPos
    camViewPresets[presetNo].absRot = freeCamRot
    uprint("Save camera view preset "..presetNo..", offset: " .. posOffset.x .. ", " .. posOffset.y .. ", " .. posOffset.z)

    -- Set new view
    freecam.switchCamViews(presetNo)
end

-- Custom contorl configuration, Settings will take effect after toggling the camera mode.  
----------------------------------------
local function setCamAxes(camMode, axes)
    controls[camMode].axes = axes
end
local function setCamButtons(camMode, buttons)
    controls[camMode].buttons = buttons
end
function freecam.setCamControl(camMode, control)
    if not control then
        uprint("Invalid control. camMode:" .. tostring(camMode))
        return
    end
    if control.axes then
        setCamAxes(camMode, control.axes)
    end
    if control.buttons then
        setCamButtons(camMode, control.buttons)
    end
end

-- Convert button configurations into  buttonActions (for one camera mode)
local function updateButtonActions(camMode, buttons)
    uprint("* Generating button actions for camera mode " .. camMode)
    camButtonActions[camMode] = gamepad.updateButtonActions(buttons)
end
local function setCurrCamModeAxes(camMode)
    currCamModeAxes = controls[camMode].axes -- Mainly used by onXinputStateChanged()
    local axesMsgTitle = "* Active axes:"
    local axesMsg = {}
    for k, v in pairs(currCamModeAxes) do
        local msg = k..": "..v[1]
        if v[2] then
            msg = msg .. "/" .. v[2]
        end
        axesMsg[k] = msg
    end
    if next(axesMsg) then
        uprint(axesMsgTitle)
        local msgOrder = {"move", "rot", "elev"}
        for _, v in ipairs(msgOrder) do
            if axesMsg[v] then
                uprint(axesMsg[v])
            end
        end
    else
        uprint(axesMsgTitle.." None.")
    end
end

function freecam.setFreecamControlScheme(controlScheme)
    if not freecamAxes[controlScheme] then
        uprint("Invalid control scheme: " .. controlScheme)
        return
    end
    opt.freecamControlScheme = controlScheme
    cfg.controls[camType.free].axes = freecamAxes[controlScheme]
    setCurrCamModeAxes(currCamMode)
end
function freecam.levelFlightModeToggle(onOff)
    local lastLevelFlight = opt.levelFlight
    if onOff == nil then
        opt.levelFlight = not opt.levelFlight
    else
        opt.levelFlight = onOff
    end
    if lastLevelFlight == opt.levelFlight and opt.freecamControlScheme == freecamControlType.TPS then
        return
    end
    local msg = opt.levelFlight and "Level" or "Omin"
    uprint("# " .. msg .. " Flight Mode.")
    if opt.freecamControlScheme ~= freecamControlType.TPS then
        freecam.setFreecamControlScheme(freecamControlType.TPS)
    end
end
function freecam.omniFlightWithSpaceControl()
    if opt.freecamControlScheme == freecamControlType.Space then
        return
    end
    opt.levelFlight = false
    uprint("# Space Control Scheme")
    freecam.setFreecamControlScheme(freecamControlType.Space)
end

function freecam.followPositionOnly()
    if opt.followPositionOnly then
        return
    end
    uprint("# Follow Mode: Position Only")
    opt.follow = true
    opt.followPositionOnly = true
end
function freecam.followModeToggle(onOff)
    local lastFollow = opt.follow
    if onOff == nil then
        opt.follow = not opt.follow
    else
        opt.follow = onOff
    end
    if lastFollow == opt.follow and not opt.followPositionOnly then
        return
    end
    opt.followPositionOnly = false
    local msg = opt.follow and "On" or "Off"
    uprint("# Follow Mode: " .. msg)
end

function freecam.gameMenuToggle()
    opt.autoGameMenuToggle = not opt.autoGameMenuToggle
    -- autoGameMenuToggle is a flag that is checked during freecam, and we also change the game menu visibility when the user toggles it.
    lib.enableGUI(not opt.autoGameMenuToggle)
end

function freecam.enable(enabled)
    if enabled == freecamEnabled then
        return
    end

    if not enabled then
        if opt.uevrAttachCameraCompatible then
            lib.resetModValueCamOffset()
        end
    end
    local enableStr = enabled and "enabled" or "disabled"
    uprint("# Freecam " .. enableStr..".")
    freecamEnabled = enabled
end

-- help function for camModeToggle
local function camModeToggleUpdate(camMode)
    updateButtonActions(camMode, controls[camMode].buttons)
    setCurrCamModeAxes(camMode)
    if cfg.spd[camMode] then
        spd = cfg.spd[camMode]
        updateCamSpeed()
    end
end

function freecam.camModeToggle(camMode)
    currCamMode = camMode -- update global variable
    local enableGUI = true

    if camMode == camType.free then
        uprint("## FREE CAM ##")
        -- Hide the game menu when free camera is enabled
        if opt.autoGameMenuToggle then
            enableGUI = false
        end
        gamepad.setInterceptConfig(nil) -- Use default config (Intercept all gamepad signals)
    elseif camMode == camType.orbit then
        uprint("## ORBIT CAM ##")
        gamepad.generateAndSetInterceptConfig(controls[camMode])
    elseif camMode == camType.scene then
        uprint("## SCENE CAM ##")
        gamepad.generateAndSetInterceptConfig(controls[camMode])
    else
        uprint("## DEFAULT CAM ##")
        gamepad.setInterceptConfig({}) -- Clear gamepad interception
    end

    camModeToggleUpdate(camMode)
    lib.enableGUI(enableGUI) -- Show the game menu when free camera is disabled

    -- Sets the mode to switch back when exiting free camera
    if camMode ~= 1 then
        cam1ExitMode = camMode
    end
end


-- Event Callbacks
----------------------------------------
local function onEarlyCalculateStereoViewOffset(device, view_index, world_to_meters, position, rotation, is_double)

    -- view_index
    -- (UE4) 0: never execute, 1: left eye, 2: right eye/screen
    -- (UE5) 0: left eye, 1: right eye/screen
    -- Each eye will be triggered separately.
    -- Only processing one eye may result in only one eye moving in VR
    -- L/R values may not be the same while moving (eye2=eye1 but eye1 ~= next eye2)
    -- It should be OK to use eye 1's view_index to process both eyes, but I have not tested it yet.
    -- Be careful, position variable is constantly reseted by UEVR (after each 2 eyes), Even after assigning position = nwPos
    -- uprint("view_index: " .. view_index)

    if firstEye then
        local viewPosOffset = Vector3f.new(0, 0, 0)
        local viewRotOffset = Vector3f.new(0, 0, 0)

        if freecamReinitialize then -- initialize
            gameCamPos = lib.xyzSet(position)
            gameCamRot = lib.xyzSet(rotation)
            freeCamPos = lib.xyzSet(position)
            freeCamRot = lib.xyzSet(rotation)
            freeCamPosOffset = Vector3f.new(0, 0, 0)
            freeCamRotOffset = Vector3f.new(0, 0, 0)
            viewPosOffset = camViewPosOffset:clone()
            viewRotOffset = camViewRotOffset:clone()
            freecamReinitialize = false
        end

        -- Calculate the new position and rotation
        local currPos = position + lib.kismet_math:GreaterGreater_VectorRotator(freeCamPosOffset+viewPosOffset, rotation) -- Initial pos/rot
        local currRot = Vector3f.new(0, 0, 0)
        local newPos = Vector3f.new(0, 0, 0)  -- Final position/rotation/offsets to record
        local newRot = Vector3f.new(0, 0, 0)
        local newPosOffset = Vector3f.new(0, 0, 0)
        local newRotOffset = Vector3f.new(0, 0, 0)
        -- World offsets
        local viewPosOffsetWorld = lib.kismet_math:GreaterGreater_VectorRotator(viewPosOffset, rotation)
        local inputPosOffsetWorld = Vector3f.new(0, 0, 0)



        -- Orbit Camera
        ------------------------------
        if currCamMode == camType.orbit then -- Orbit Camera: Rotation center is at the position of game camera's view target

            local targetPos = Vector3f.new(0,0,0)
            if viewTargetPos then
                targetPos = viewTargetPos
            end

            -- Recalculate the rotation from the current position to the target position
            currRot = lib.kismet_math:FindLookAtRotation(currPos, targetPos)
            newRot = lib.wrapRotationWithPitchLimit(currRot + inputRot)

            local localOffsets = lib.kismet_math:LessLess_VectorRotator(currPos - targetPos, currRot) + inputPos
            newPos = targetPos + lib.kismet_math:GreaterGreater_VectorRotator(localOffsets, newRot)
            local checkDistance = lib.calcDirectionDistance(newPos, viewTargetPos, newRot)
            if checkDistance == 0 then
                local offsetAway = Vector3f.new(-1, 0, 0)
                newPos = viewTargetPos + lib.kismet_math:GreaterGreater_VectorRotator(offsetAway, newRot)
            end

            -- Record the offsets
            newPosOffset =  lib.kismet_math:LessLess_VectorRotator(newPos-position, rotation)

            if opt.orbitcamSyncOrientationToFreecam then
                -- 'fix' the rotaion for freecam mode
                -- Set freecam to the orbitcam's orientation
                newRotOffset = newRot - viewRotOffset - rotation
            else
                -- Orbitcam will not affect the freecam rotation
                newRotOffset = freeCamRotOffset + inputRot
            end




        -- Free/Defaul/Scene Camera
        ------------------------------
        else -- All variants of Free Camera: rotation center is at the position of the free camera.

            -- TODO: Added stabilizer here


            -- # Calculate the new orientation
            currRot = rotation + freeCamRotOffset
            newRot = lib.wrapRotation(currRot + inputRot + viewRotOffset)

            -- # Fly Mode
            if not opt.levelFlight then -- Free Fly
                inputPosOffsetWorld = lib.kismet_math:GreaterGreater_VectorRotator(inputPos, newRot)
            else -- Level Fly
                -- Since the final movement is a horizontal flight in the world space, we first assume that inputPos is a vector in the world coordinate system.
                -- Then rotate inputPos around the world's Z-axis to align it with camRot's horizontal orientation
                local freeCamForwardLeveled = lib.xyzSetZ(lib.kismet_math:Conv_RotatorToVector(newRot), 0) -- no need to normalize
                local freeCamRotLeveled = lib.kismet_math:Conv_VectorToRotator(freeCamForwardLeveled)
                inputPosOffsetWorld = lib.kismet_math:GreaterGreater_VectorRotator(inputPos, freeCamRotLeveled)
            end

            -- Add input/camView offsets
            -- currPos is the rotation center (which are not effected by the newRot)
            newPos = currPos + inputPosOffsetWorld

            -- Calculate local offsets
            -- When not in follow mode, we want gameCamPos/Rot to keep updating.
            -- Compensate for these changes to maintain the free camera's position/rotation.
            if not opt.follow then -- Hold the camera position
                newPos = freeCamPos + inputPosOffsetWorld + viewPosOffsetWorld
            end
            newPosOffset = lib.kismet_math:LessLess_VectorRotator(newPos - position, rotation)

            if not opt.follow or opt.followPositionOnly then -- Hold the camera rotation
                newRot = lib.wrapRotation(freeCamRot + inputRot + viewRotOffset)
            end
            newRotOffset = newRot - rotation

        end -- if camMode

        -- Record the last game camera position/rotation
        lib.xyzSetInPlace(gameCamPos, position)
        lib.xyzSetInPlace(gameCamRot, rotation)
        -- Record the last freecam position/rotation
        lib.xyzSetInPlace(freeCamPos, newPos)
        lib.xyzSetInPlace(freeCamRot, newRot)
        -- Record the freecam offsets
        lib.xyzSetInPlace(freeCamPosOffset, newPosOffset)
        lib.xyzSetInPlace(freeCamRotOffset, newRotOffset)

    end -- if firstEye



    -- Modify the game camera position and rotation
    if freecamEnabled then
        -- -- Set the new position
        if not opt.uevrAttachCameraCompatible then
            -- The 'positoin' method. this won't affect the mod value, but is not compatible with UEVR's attached camera feature
            -- This is the default method.
            -- We need to update this in both eyes, as the position is constantly reseted by UEVR.
            lib.xyzSetInPlace(position, freeCamPos)
        elseif firstEye then
            -- The 'mod_value' method. this will affect the mod value, but is compatible with UEVR's attached camera feature
            local gameCamOffest = lib.kismet_math:LessLess_VectorRotator(freeCamPos - position, freeCamRot)
            lib.setModValueCamOffset(gameCamOffest)
        end

        -- Set the new rotation
        lib.xyzSetInPlace(rotation, freeCamRot)
    end

    firstEye = false

end

local function onPostCalculateStereoViewOffset(device, view_index, world_to_meters, position, rotation, is_double)
end
local function onPreEngineTick(engine, delta_time)
    -- Reuest the targetPos before the pre_calc_stereo callback
    if currCamMode == camType.orbit then
            events:emit('freecam_update_target_position')
    end
    -- uprint("---------- new tick ----------")
    firstEye = true
end
local function onPostEngineTick(engine, delta_time)
    -- clear the inputPos/offset after post_calc_sterio
    lib.xyzClearInPlace(inputPos)
    lib.xyzClearInPlace(inputRot)
end

local function checkCommonActions(buttonActions)

    -- Manual reset camera
    if gamepad.checkButtonsState(buttonActions.resetCam) then
        if opt.recenterVROnCameraReset then
            lib.recenterVR()
        end
        freecam.resetCam()
    end

    -- reset Camera and view
    if gamepad.checkButtonsState(buttonActions.resetAll) then
        if opt.recenterVROnCameraReset then
            lib.recenterVR()
        end
        freecam.resetAll()
    end

    if gamepad.checkButtonsState(buttonActions.followOn) then
        freecam.followModeToggle(true)
    end
    if gamepad.checkButtonsState(buttonActions.followOff) then
        freecam.followModeToggle(false)
    end
    if gamepad.checkButtonsState(buttonActions.followPositionOnly) then
        freecam.followPositionOnly()
    end
    if gamepad.checkButtonsState(buttonActions.levelFlight) then
        freecam.levelFlightModeToggle()
    end
    if gamepad.checkButtonsState(buttonActions.omniFlightWithSpaceControl) then
        freecam.omniFlightWithSpaceControl()
    end

    -- Game menu
    if gamepad.checkButtonsState(buttonActions.autoGameMenuToggle) then
        freecam.gameMenuToggle()
    end

    -- Adjust speed
    if gamepad.checkButtonsState(buttonActions.speedIncrease) then
        adjustCamSpeed(1)
    elseif gamepad.checkButtonsState(buttonActions.speedDecrease) then
        adjustCamSpeed(-1)
    end

    -- Switch camera offsets
    if gamepad.checkButtonsState(buttonActions.viewCycle) then
        freecam.switchCamViews(0)
    end

    -- Custom camera offsets
    if gamepad.checkButtonsState(buttonActions.viewSave) then
        freecam.saveCamView()
    end


    -- Check camera dolly button
    -- event= held : chekc buttonHold
    --        other : toogle the state
    if gamepad.isHeldButtons(buttonActions.camDolly) then
        -- Hold the button and move the axis at the same time
        dollyKeyHeld =  gamepad.checkButtonsHolding(buttonActions.camDolly)
    else
        -- Toggle the action state
        if gamepad.checkButtonsState(buttonActions.camDolly) then
            dollyKeyHeld = not dollyKeyHeld
        end
    end

    -- Use buttons to move
    local fakeDelta = 0.005
    if gamepad.checkButtonsHolding(buttonActions.moveForward) then
        moveCam(0, 1, 0, fakeDelta)
    end
    if gamepad.checkButtonsHolding(buttonActions.moveBackward) then
        moveCam(0, -1, 0, fakeDelta)
    end
    if gamepad.checkButtonsHolding(buttonActions.moveLeft) then
        moveCam(-1, 0, 0, fakeDelta)
    end
    if gamepad.checkButtonsHolding(buttonActions.moveRight) then
        moveCam(1, 0, 0, fakeDelta)
    end
end


local function onXinputButtonChanged(buttonState)
    -- debug
    gamepad.buttonDebug("B")

    local currButtonActions = camButtonActions[currCamMode]
    local freeButtonActions = camButtonActions[camType.free]


    -- Mode switch for 'FreeCam'
    if currCamMode ~= camType.free then
    -- Not in freecam mode
        -- Switch to freecam
        if gamepad.checkButtonsState(freeButtonActions.active) then
            freecam.enable(true)
            freecam.camModeToggle(camType.free) -- activate freecam
        end
    else
    -- In freecam mode
        -- Exit from freecam
        if gamepad.checkButtonsState(freeButtonActions.deactive) then
            freecam.camModeToggle(cam1ExitMode)
        end

        if gamepad.checkButtonsState(freeButtonActions.disable) then
            freecam.enable(false)
            freecam.camModeToggle(cam1ExitMode)
        end
    end


    checkCommonActions(currButtonActions)

end

-- Deal with axis value
local lastXinputTime = os.clock()
local function onXinputStateChanged(retval, user_index, state)
    local currentTime = os.clock()
    local deltaTime = currentTime - lastXinputTime
    if deltaTime == 0 then -- prevent divide by zero
        return
    end


    -- Map the axis and get the percentage of the axis values
    local axes = gamepad.mapAxes(state, currCamModeAxes)

    lastXinputTime = currentTime
    if dollyKeyHeld then
        moveCam(0, axes.rot.y, 0, deltaTime)
        rotateCam(axes.rot.x, 0, deltaTime)
    else
        moveCam(axes.move.x, axes.move.y, axes.elev, deltaTime)
        rotateCam(axes.rot.x, axes.rot.y, deltaTime)
    end

    -- Intercept the gamepad input
    -- This function intercepts the signals sent to the game, controlled by interceptConfig
    gamepad.intercept(state)
end


-- Initialize
----------------------------------------

-- Convert All button configurations into buttonActions
local function updateButtonActionsAll()
    camButtonActions = {}
    for camMode, control in pairs(controls) do
        camButtonActions[camMode] = gamepad.updateButtonActions(control.buttons)
    end
end


-- Read external configurations and update the settings
local function updateConfig(config, extConfig)
    for k, v in pairs(extConfig) do
        -- uprint("extCfg: " .. tostring(k) .. " = " .. tostring(v))
        if type(v) == "table" and type(config[k]) == "table" then
            -- Update nested table
            updateConfig(config[k], v)
        else
            -- uprint("Updating config: " .. tostring(k) .. " = " .. tostring(v))
            config[k] = v
        end
    end
end

local function initExtConfig()
    local extCfg = freecam.extCfg
    uprint("Reading external configurations.")
    if not extCfg then
        uprint("No external configurations found.")
        return
    end
    if extCfg.opt then
        updateConfig(opt, extCfg.opt)
    end
    if extCfg.spd then
        updateConfig(cfg.spd, extCfg.spd)
    end
    if extCfg.buttons then
        updateConfig(controls[camType.free].buttons, extCfg.buttons)
    end

end

local function resetUEVRModSettings()
    uprint("Reset UEVR Mod Settings.")
    lib.enableGUI(true)
    lib.resetModValueCamOffset()
end


local freecamInited = false
function freecam.init()
    if not freecamInited then
        uprint("*** Initializing Free Camera. ***")
    else
        uprint("Free camera already initialized.")
        return
    end
    freecamInited = true


    -- Initialize
    resetUEVRModSettings()
    initExtConfig()
    -- buttonActions for each camera mode will be updated when the mode is toggled, but we need to get the config of the freecam's activation button first.  
    updateButtonActions(camType.free, controls[camType.free].buttons) 
    freecam.camModeToggle(currCamMode)

    -- Register event callbacks
    uevr.sdk.callbacks.on_pre_engine_tick(onPreEngineTick)
    uevr.sdk.callbacks.on_post_engine_tick(onPostEngineTick)
    uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(onEarlyCalculateStereoViewOffset)
    -- uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(onPostCalculateStereoViewOffset)
    events:on('xinput_button_changed', onXinputButtonChanged)
    events:on('xinput_state_changed', onXinputStateChanged)
end

uevr.sdk.callbacks.on_script_reset(function()
    resetUEVRModSettings()
end)

return freecam

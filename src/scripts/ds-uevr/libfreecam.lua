-- File:    libfreecam.lua
-- Brief:   DS UEVR Universal Free Camera library
-- Details: This plugin provides a universal free camera functionality for UEVR, 
--          allowing users to freely navigate and explore VR environments. It can 
--          be used as a standalone universal plugin or customized with specific 
--          parameters for other game plugins.
-- License: MIT
-- Version: 1.0.1
-- Date:    2025/02/09
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
    enableGuiToggle = false, -- Disable game GUI when free camera is enabled
    freecamControlScheme = freecamControlType.TPS, -- Control scheme for free camera
    -- freecamControlScheme = controlType.Space, -- Control scheme for free camera
    freecamFollowPosition = true, -- Follows game camera's position in free camera mode, or the object may run away from the camera.
    freecamFollowRotation = false, -- It feels less `free` when following the rotation of the game camera.
    freecamKeepPosition = false,  -- Don't reset the free camera's position while switching cameras.
    keepOrbitCamPosition = false, -- Freecam will synchronize the position of the orbit camera.
    levelFlight = true, -- The vertical orientation of the camera does not affect the flight altitude.
    cam_invert_pitch = false,
    recenterVROnCameraReset = true, -- Reset the camera and recenter VR at the same time
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
        active = "L3_held",
        deactive = "L3",
        resetCam = "R3",
        speedIncrease = "RB",
        speedDecrease = "LB",
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

-- Speed settings for different freecamMode
cfg.spd={}
cfg.spd[camType.free] = {
    speedTotalStep = 10,
    move_speed_max = 10000, -- cm per second
    move_speed_min = 50,
    rotate_speed_max = 180, -- degrees per second
    rotate_speed_min = 90, -- degrees per second
    currMoveStep = 5,
    currRotStep = 5
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

-- Camera offsets by different scenes
-- Currently only support .x value (For dolly)
local camOffsets = {
    Vector3f.new(0, 0, 0),
}
local camOffsetsPresetNo = 1
local camOffset=Vector3f.new(0, 0, 0)

-- Set libgamepad's interceptConfig based on axis and button configurations
-- = nil: use default config (intercepts all)
local customInterceptConfig = {}



-- local variables
local freeCamMode = camType.default
local cam1ExitMode = camType.default -- Which Mode to switch to when exiting freecam1

-- Use Vector3d if this is a UE5 game (double precision)
local inputPos = Vector3f.new(0, 0, 0)
local inputRot = Vector3f.new(0, 0, 0)
local orbitCamOffsetPos = Vector3f.new(0, 0, 0)
local orbitCamOffsetRot = Vector3f.new(0, 0, 0)
local camOffsetTransformedLR = {}

local lastPosLR ={}
local lastRotLR ={}
local camPosLR = {}
local camRotLR = {}

local viewTargetPos = nil -- Used for Orbit camera mode
local dollyKeyHeld = false
local moveSpeed = 0
local rotSpeed = 0


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
    local rotateDeltaX = pctY * rotSpeed * deltaTime * (opt.cam_invert_pitch and -1 or 1)
    local rotateDeltaY = pctX * rotSpeed * deltaTime

    -- Update inputRot
    inputRot.x = inputRot.x + rotateDeltaX
    inputRot.y = inputRot.y + rotateDeltaY
    inputRot.z = 0

end

-- Transformations
----------------------------------------
local function rotateAroundTarget(position, rotation, targetPos)

    local offsetPosTotal = orbitCamOffsetPos + camOffset
    local dollyDistance = offsetPosTotal.x

    -- Calculate the offset of the camera relative to targetPos
    local distance =(position - targetPos):length()

    -- UEVR's camera maynot  point to the targetPos, recalc it's rotation
    -- local newRot = rotation + offsetRot
    local currentRot = lib.kismet_math:FindLookAtRotation(position, targetPos)
    local newRot = lib.wrapRotationWithPitchLimit(currentRot + orbitCamOffsetRot)
    -- prevent offsetRot from continuously increasing in the background
    orbitCamOffsetRot  = newRot - currentRot
    -- lib.lzprint("newRot.x: " .. newRot.x .. ", offsetRot.x: " .. offsetRot.x)
    -- lib.lzprint("newRot.y: " .. newRot.y .. ", offsetRot.y: " .. offsetRot.y)


    -- Pretend to place the camera at targetPos, rotate it, and then move it backward
    local newPos = targetPos - lib.kismet_math:Conv_RotatorToVector(newRot) * (distance-dollyDistance)

    return newRot, newPos
end


-- Public Functions
----------------------------------------

function freecam.resetCam()
    uprint("Reset camera.")
    inputPos = Vector3f.new(0, 0, 0)
    inputRot = Vector3f.new(0, 0, 0)
    orbitCamOffsetPos = Vector3f.new(0, 0, 0)
    orbitCamOffsetRot = Vector3f.new(0, 0, 0)
    camOffsetTransformedLR = {}
    lastPosLR = {}
    lastRotLR = {}
    camPosLR = {}
    camRotLR = {}
end

-- Set the target position for the orbit camera
function freecam.setViewTargetPos(pos)
    viewTargetPos = pos
end

function freecam.setCamOffsets(offsets, presetNo)
    local lastPresetNo = camOffsetsPresetNo
    camOffsets = offsets
    freecam.switchCamOffsets(presetNo) -- Will update camOffsetsPresetNo
    return lastPresetNo
end

function freecam.switchCamOffsets(presetNo)
    inputPos = Vector3f.new(0, 0, 0) -- reset inputPos but keep inputRot
    if presetNo == 0 then -- switch to next preset
        camOffsetsPresetNo = camOffsetsPresetNo + 1
        if camOffsetsPresetNo > #camOffsets then
            camOffsetsPresetNo = 1
        end
    else
        camOffsetsPresetNo = presetNo
    end

    -- Clear input offset (for orbit cam)
    orbitCamOffsetPos = Vector3f.new(0, 0, 0)

    lib.xyzSetInPlace(camOffset, camOffsets[camOffsetsPresetNo])
    uprint("Switch to camera preset "..camOffsetsPresetNo.." ,offset: " .. camOffset.x .. ", " .. camOffset.y .. ", " .. camOffset.z )
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
    uprint("* Active axes:")
    lib.printTable(currCamModeAxes)
end
-- help function for freeCamModeToggle
local function camModeToggleUpdate(camMode)
    updateButtonActions(camMode, controls[camMode].buttons)
    setCurrCamModeAxes(camMode)
    spd = cfg.spd[camMode]
    updateCamSpeed()
end

function freecam.camModeToggle(camMode)
    freeCamMode = camMode -- update global variable
    lib.enableGUI(true) -- Show the game menu when free camera is disabled

    if camMode == camType.free then
        uprint("## FREE CAM ##")
        if not opt.freecamKeepPosition then
            freecam.resetCam()
        end
        if opt.enableGuiToggle then
            lib.enableGUI(false)
        end
        camModeToggleUpdate(camMode)
        gamepad.setInterceptConfig(nil) -- Use default config (Intercept all gamepad signals)
        -- Hide the game menu when free camera is enabled
    elseif camMode == camType.orbit then
        uprint("## ORBIT CAM ##")
        camModeToggleUpdate(camMode)
        gamepad.generateAndSetInterceptConfig(controls[camMode])
    elseif camMode == camType.scene then
        uprint("## SCENE CAM ##")
        camModeToggleUpdate(camMode)
        gamepad.generateAndSetInterceptConfig(controls[camMode])
    else
        uprint("## DEFAULT CAM ##")
        gamepad.setInterceptConfig({}) -- Clear gamepad interception
    end

    -- Sets the mode to switch back when exiting free camera
    if camMode ~= 1 then
        cam1ExitMode = camMode
    end
end


-- Event Callbacks
----------------------------------------

local function onEarlyCalculateStereoViewOffset(device, view_index, world_to_meters, position, rotation, is_double)

    if freeCamMode == camType.default then
        return
    end

    -- view_index
    -- (UE4) 0: never execute, 1: left eye, 2: right eye/screen
    -- (UE5) 0: left eye, 1: right eye/screen
    -- Each eye will be triggered separately.
    -- Only processing one eye may result in only one eye moving in VR
    -- L/R values may not be the same while moving (eye2=eye1 but eye1 ~= next eye2)
    -- It should be OK to use eye 1's view_index to process both eyes, but I have not tested it yet.
    -- Be careful, position variable is constantly reseted by UEVR (after each 2 eyes), Even after assigning position = nwPos
    
    if not camPosLR[view_index] then -- initialize
        lastPosLR[view_index] = lib.xyzSet(position)
        lastRotLR[view_index] = lib.xyzSet(rotation)
        camPosLR[view_index] = lib.xyzSet(position)
        camRotLR[view_index] = lib.xyzSet(rotation)
        camOffsetTransformedLR[view_index] = Vector3f.new(0, 0, 0)
    end
    local camPos = camPosLR[view_index] -- last freecam position
    local camRot = camRotLR[view_index] -- last freecam rotation
    -- Debug: Check LR eye position match
    -- if view_index == 2 then
    --     if camPosLR[1] ~= camPosLR[2] then
    --         uprint("eye position mismatch.")
    --     else
    --         uprint("eye position match.")
    --     end
    -- end


    -- Update camPos/camRot while the UEVR camera changes its position/rotation
    -- Always update them in scene camera mode, ignoring the follow settings
    -- Follow Camera Position
    if opt.freecamFollowPosition or freeCamMode == camType.scene then
        local lastPosDelta = lib.xyzSub(position, lastPosLR[view_index])
        camPos = camPos + lastPosDelta
        lib.xyzSetInPlace(lastPosLR[view_index], position) -- record UEVR cam position, should not counting freecam movement
    end
    -- Follows Camera Rotation
    if opt.freecamFollowRotation or freeCamMode == camType.scene then
        local lastRotDelta = lib.xyzSub(rotation, lastRotLR[view_index])
        camRot = lib.wrapRotation(camRot + lastRotDelta)
        lib.xyzSetInPlace(lastRotLR[view_index], rotation) -- record UEVR cam rotation, should not counting freecam movement
    end


    -- UEVR Camera vectors
    local uevrCamForward = lib.kismet_math:Conv_RotatorToVector(rotation)
    local uevrCamRight = lib.kismet_math:GetRightVector(rotation)
    local uevrCamUp = lib.kismet_math:GetUpVector(rotation)


    local newPos = Vector3f.new(0, 0, 0)
    local newRot = Vector3f.new(0, 0, 0)

    -- Orbit Camera
    ------------------------------
    if freeCamMode == camType.orbit then -- Orbit Camera: Rotation center is at the position of game camera's view target
        orbitCamOffsetPos = orbitCamOffsetPos + inputPos
        orbitCamOffsetRot = orbitCamOffsetRot + inputRot

        local targetPos = Vector3f.new(0,0,0)
        if viewTargetPos then
            targetPos = viewTargetPos
            -- uprint("targetPos: " .. targetPos.x .. ", " .. targetPos.y .. ", " .. targetPos.z)
        end

        newRot, newPos = rotateAroundTarget(position, rotation, targetPos)
        -- newRot = lib.kismet_math:FindLookAtRotation(newPos, targetPos)


    -- Free Camera/Scene Camera
    ------------------------------
    elseif freeCamMode == camType.free or freeCamMode == camType.scene then -- Free Camera/Scene Camera: rotation center is at the position of free camera


        -- #Orientation
        -- Calculate new orientation base on uevr camera (It is the forward direction of the input)
        -- kismet_math_library seems to require the nightly build
        newRot = camRot + inputRot
        local forward_vector = lib.kismet_math:Conv_RotatorToVector(camRot)
        local right_vector = lib.kismet_math:GetRightVector(camRot)
        local up_vector = Vector3f.new(0, 0, 1)
        -- local up_vector = kismet_math_library:GetUpVector(rot)
        -- local right_vector = calcRight(forward_vector, up_vector)
        -- lzprint("Pos: " .. position.x .. ", " .. position.y .. ", " .. position.z)

        -- #Rotation Center
        -- camPos is the center of rotation
        if not opt.levelFlight then -- Free Fly
            -- # Expression:
            -- newPos = camPos + (inputPos.x * forward_vector) + (inputPos.y * right_vector) + (inputPos.z * up_vector)
            -- # Decompose the calculation:
            newPos = Vector3f.new(
                camPos.x + inputPos.x * forward_vector.x + inputPos.y * right_vector.x + inputPos.z * up_vector.x,
                camPos.y + inputPos.x * forward_vector.y + inputPos.y * right_vector.y + inputPos.z * up_vector.y,
                camPos.z + inputPos.x * forward_vector.z + inputPos.y * right_vector.z + inputPos.z * up_vector.z
            )
        else -- Level Fly
            -- Normalize forward_vector and right_vector to maitian the same speed in all directions
            forward_vector.z = 0
            forward_vector = lib.normalizeVector(forward_vector)
            right_vector.z = 0
            right_vector = lib.normalizeVector(right_vector)

            -- # Expression:
            -- newPos = camPos + (inputPos.x * forward_vector + inputPos.y * right_vector) + Vector3f.new(0, 0, inputPos.z);
            -- # Decompose the calculation:
            newPos = Vector3f.new(
                camPos.x + inputPos.x * forward_vector.x + inputPos.y * right_vector.x,
                camPos.y + inputPos.x * forward_vector.y + inputPos.y * right_vector.y,
                camPos.z + inputPos.z
            )
        end

        -- The camoffset here only for Free/Scene Camera mode
        -- In orbitcam mode, the offset is calulated by orbitAroundTarget(), which is already applied.
        -- Considering our camera's rotation keep changing, we need to recalculate the offset every time, even if the camOffset does not change.
        local camOffsetTransformed = camOffsetTransformedLR[view_index]
        -- remove the applied offset first
        lib.xyzSubInPlace(newPos, camOffsetTransformed)
        -- calculcate new transformed camOffset
        camOffsetTransformed = lib.kismet_math:GreaterGreater_VectorRotator(camOffset, rotation)
        -- Add the offset to newPos for freeCam to follow its position
        lib.xyzAddInPlace(newPos, camOffsetTransformed)

        --record the offseted we applied
        camOffsetTransformedLR[view_index] = camOffsetTransformed

        
        -- Overwrite offsetPos/offsetRot to synchronize the Orbit camera position
        if not opt.keepOrbitCamPosition then
            if cam1ExitMode==camType.orbit and viewTargetPos then
                orbitCamOffsetPos.x = (position - viewTargetPos):length() - (newPos - viewTargetPos):length() - camOffset.x
                orbitCamOffsetRot = lib.kismet_math:FindLookAtRotation(newPos, viewTargetPos) - lib.kismet_math:FindLookAtRotation(position, viewTargetPos)
            end
        end

    else
        -- uprint("Invalid rotation mode")
        return
    end

    -- lib.lzprint("newPos: " .. newPos.x .. ", " .. newPos.y .. ", " .. newPos.z)



    -- Update camPos/camRot to newPos/newRot for free camera calculation.
    lib.xyzSetInPlace(camPosLR[view_index], newPos)
    lib.xyzSetInPlace(camRotLR[view_index], newRot)

    -- Set the new position
    lib.xyzSetInPlace(position, newPos)

    -- vr.set_mod_value("VR_CameraForwardOffset", inputPos.x)
    -- vr.set_mod_value("VR_CameraRightOffset", inputPos.y)
    -- vr.set_mod_value("VR_CameraUpOffset", inputPos.z)

    -- Set the new rotation
    -- Be aware: Changing rotation in stereo post callback may causes stereo view offset to be incorrect ()
    -- (It might be related to both eyes sharing the same rotation values.)
    lib.xyzSetInPlace(rotation, newRot)


end
local function onPostCalculateStereoViewOffset(device, view_index, world_to_meters, position, rotation, is_double)
end
local function onPreEngineTick(engine, delta_time)
    -- Reuest the targetPos before the pre_calc_stereo callback
    if freeCamMode == camType.orbit then
            events:emit('freecam_update_target_position')
    end
end
local function onPostEngineTick(engine, delta_time)
    -- clear the inputPos/offset after post_calc_sterio
    lib.xyzClearInPlace(inputPos)
    lib.xyzClearInPlace(inputRot)
end

local function checkCommonActions(buttonState, buttonActions)

    -- Manual reset camera
    if gamepad.checkButtonState(buttonState, buttonActions.resetCam) then
        if opt.recenterVROnCameraReset then
            local hmd_pos=UEVR_Vector3f.new()
            local hmd_rot=UEVR_Quaternionf.new()

            vr.get_pose(vr.get_hmd_index(), hmd_pos, hmd_rot)
            vr.set_standing_origin(hmd_pos)
            vr.recenter_view()
        end
        freecam.resetCam()
    end

    -- Adjust speed
    if gamepad.checkButtonState(buttonState, buttonActions.speedIncrease) then
        adjustCamSpeed(1)
    elseif gamepad.checkButtonState(buttonState, buttonActions.speedDecrease) then
        adjustCamSpeed(-1)
    end

    -- Switch camera offsets
    if gamepad.checkButtonState(buttonState, buttonActions.camOffset) then
        freecam.switchCamOffsets(0)
    end


    -- Check camera dolly button
    -- event= held : chekc buttonHold
    --        other : toogle the state
    if gamepad.isAHoldButton(buttonActions.camDolly) then
        -- Hold the button and move the axis at the same time
        dollyKeyHeld =  gamepad.checkButtonHold(buttonState, buttonActions.camDolly)
    else
        -- Toggle the action state
        if gamepad.checkButtonState(buttonState, buttonActions.camDolly) then
            dollyKeyHeld = not dollyKeyHeld
        end
    end

    -- Use buttons to move
    local fakeDelta = 0.005
    if gamepad.checkButtonHoldState(buttonState, buttonActions.moveForward) then
        moveCam(0, 1, 0, fakeDelta)
    end
    if gamepad.checkButtonHoldState(buttonState, buttonActions.moveBackward) then
        moveCam(0, -1, 0, fakeDelta)
    end
    if gamepad.checkButtonHoldState(buttonState, buttonActions.moveLeft) then
        moveCam(-1, 0, 0, fakeDelta)
    end
    if gamepad.checkButtonHoldState(buttonState, buttonActions.moveRight) then
        moveCam(1, 0, 0, fakeDelta)
    end
end


local function onXinputButtonChanged(buttonState)
    -- debug
    local btn_b_state = buttonState[gamepad.buttonDef["B"]]
    gamepad.buttonDebug(btn_b_state)

    local buttonActions = camButtonActions[freeCamMode]
    local freecamActive = camButtonActions[camType.free].active

    -- Handle free cam activation
    if freeCamMode ~= camType.free and gamepad.checkButtonState(buttonState, freecamActive) then
        freecam.camModeToggle(camType.free)
    elseif freeCamMode == camType.free then -- Use else here to prevent the released event of the same button from triggering twice
        if gamepad.checkButtonState(buttonState, buttonActions.deactive) then
            freecam.camModeToggle(cam1ExitMode)
        end
    end

    checkCommonActions(buttonState, buttonActions)

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

local freecamInited = false
function freecam.init()
    if not freecamInited then
        uprint("*** Initializing Free Camera. ***")
    else
        uprint("Free camera already initialized.")
        return
    end
    freecamInited = true

    uprint("Reset UEVR camera settings.")
    lib.setModValue("VR_CameraForwardOffset", 0)
    lib.setModValue("VR_CameraRightOffset", 0)
    lib.setModValue("VR_CameraUpOffset", 0)

    -- Initialize
    initExtConfig()
    -- buttonActions for each camera mode will be updated when the mode is toggled, but we need to get the config of the freecam's activation button first.  
    updateButtonActions(camType.default, controls[camType.default].buttons)   -- For the default cam, set an empty table to prevent errors
    updateButtonActions(camType.free, controls[camType.free].buttons) 
    -- updateButtonActionsAll()

    -- Register event callbacks
    uevr.sdk.callbacks.on_pre_engine_tick(onPreEngineTick)
    uevr.sdk.callbacks.on_post_engine_tick(onPostEngineTick)
    uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(onEarlyCalculateStereoViewOffset)
    -- uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(onPostCalculateStereoViewOffset)
    events:on('xinput_button_changed', onXinputButtonChanged)
    events:on('xinput_state_changed', onXinputStateChanged)
end

-- uevr.sdk.callbacks.on_script_reset(function()
--     uprint("Resetting")
--     -- reset_hmd_actor()
-- end)

return freecam

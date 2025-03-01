-- File:    libcommon.ua
-- Brief:   DS UEVR plugin common functions
-- Details: Common functions for DS UEVR plugin
-- License: MIT
-- Version: 1.0.0
-- Date:    2025/02/13
-- Author:  Dabinn Huang @DSlabs
-- Powered by TofuExpress --

-- Initialize the library and global variables
print("---------- ds-uver/libcommon init ----------")
local uId ="DS-Common" -- Unique ID for this plugin
local lib = {}
-- Initialize global variables
function lib.TofuExpressInit()
    if TofuExpress == nil then
        TofuExpress = {}
    end
    local te = TofuExpress
end
lib.TofuExpressInit()

-- Helper functions --
function lib.uprint(prefix, ...)
    local args = {...}
    for i, v in ipairs(args) do
        args[i] = tostring(v)
    end
    print("[" .. prefix .. "] " .. table.concat(args, " "))
end
local function uprint(...)
    lib.uprint(uId, ...)
end
-- lazy uprint
local lastLzprint = os.time()
function lib.lzprint(str)
    local currentTime = os.time()
    if currentTime - lastLzprint >= 1 then
        uprint(str)
        lastLzprint = currentTime
    end
end
function lib.printTable(t, indent)
    indent = indent or 0
    for k, v in pairs(t) do
        if type(v) == "table" then
            uprint(string.rep("  ", indent) .. k .. ":")
            lib.printTable(v, indent + 1)
        else
            uprint(string.rep("  ", indent) .. k .. ": " .. tostring(v))
        end
    end
end

lib.ScriptStartTime = os.clock()

local api = uevr.api
local vr = uevr.params.vr

-- Only use this for one time allocated objects (classes, structs), not things like actors
function lib.find_required_object(name)
    local obj = uevr.api:find_uobject(name)
    if not obj then
        error("Cannot find " .. name)
        return nil
    end

    return obj
end

function lib.find_static_class(name)
    local c = lib.find_required_object(name)
    return c:get_class_default_object()
end

function lib.uprintInstanceNames(class_to_search)
	local obj_class = api:find_uobject(class_to_search)
    if obj_class == nil then 
		uprint(class_to_search, "was not found") 
		return
	end

    local obj_instances = obj_class:get_objects_matching(false)

    for i, instance in ipairs(obj_instances) do
		uprint(i, instance:get_fname():to_string())
	end
end



lib.game_engine_class = api:find_uobject("Class /Script/Engine.GameEngine")
-- lib.kismet_string = lib.find_static_class("Class /Script/Engine.KismetStringLibrary")
lib.kismet_math = lib.find_static_class("Class /Script/Engine.KismetMathLibrary")
-- lib.kismet_system = lib.find_static_class("Class /Script/Engine.KismetSystemLibrary")
lib.Statics = lib.find_static_class("Class /Script/Engine.GameplayStatics")
lib.hitresult_c = api:find_uobject("ScriptStruct /Script/Engine.HitResult")
lib.ftransform_c = lib.find_required_object("ScriptStruct /Script/CoreUObject.Transform")


local camera_component_c = api:find_uobject("Class /Script/Engine.CameraComponent")
local actor_c = lib.find_required_object("Class /Script/Engine.Actor")
local motion_controller_component_c = lib.find_required_object("Class /Script/HeadMountedDisplay.MotionControllerComponent")
local scene_component_c = lib.find_required_object("Class /Script/Engine.SceneComponent")

local temp_vec3 = Vector3d.new(0, 0, 0)
local temp_vec3f = Vector3f.new(0, 0, 0) -- for UE5
local temp_transform = StructObject.new(lib.ftransform_c)


local camera_component = nil
local hmd_actor = nil -- The purpose of the HMD actor is to accurately track the HMD's world transform
local hmd_component = nil



function lib.setModValueB(key, bool)
    if bool then
        vr.set_mod_value(key, "true")
    else
        vr.set_mod_value(key, "false")
    end
end
function lib.setModValue(key, value)
    vr.set_mod_value(key, tostring(value))
end
function lib.enableGUI(bool)
    lib.setModValueB("VR_EnableGUI", bool)
    -- Hide the GUI
    -- local gui = api:find_uobject("WidgetBlueuprint /Game/Blueuprints/WidgetBlueuprints/FreeCamWidget.FreeCamWidget")
    -- if gui then
    --     gui:SetVisibility(UE4.ESlateVisibility.Hidden)
    -- end
    uprint("GUI: " .. (bool and "On" or "Off"))
end

function lib.spawn_actor(world_context, actor_class, location, collision_method, owner)
    temp_transform.Translation = location
    temp_transform.Rotation.W = 1.0
    temp_transform.Scale3D = Vector3f.new(1.0, 1.0, 1.0)

    local actor = lib.Statics:BeginDeferredActorSpawnFromClass(world_context, actor_class, temp_transform, collision_method, owner)

    if actor == nil then
        uprint("Failed to spawn actor")
        return nil
    end

    lib.Statics:FinishSpawningActor(actor, temp_transform)
    uprint("Spawned actor")

    return actor
end



function lib.reset_hmd_actor()
    -- We are using pcall on this because for some reason the actors are not always valid
    -- even if exists returns true
    if hmd_actor ~= nil and UEVR_UObjectHook.exists(hmd_actor) then
        pcall(function()
            if hmd_actor.K2_DestroyActor ~= nil then
                hmd_actor:K2_DestroyActor()
            end
        end)
    end

    hmd_actor = nil
end

function lib.spawn_hmd_actor()
    local game_engine = UEVR_UObjectHook.get_first_object_by_class(lib.game_engine_class)

    local viewport = game_engine.GameViewport
    if viewport == nil then
        uprint("Viewport is nil")
        return
    end

    local world = viewport.World
    if world == nil then
        uprint("World is nil")
        return
    end

    -- lib.reset_hmd_actor()

    local pawn = api:get_local_pawn(0)

    if pawn == nil then
        uprint("Pawn is nil")
        return
    end

    local pos = pawn:K2_GetActorLocation()
    hmd_actor = lib.spawn_actor(world, actor_c, pos, 1, nil)

    if hmd_actor == nil then
        uprint("Failed to spawn hmd actor")
        return
    end
    uprint ("hmd_actor: " .. hmd_actor:get_full_name())
    uprint("Spawned hmd actor")


    uprint("scene_component_c: " .. scene_component_c:get_full_name())

    -- -- Add scene components to the hand actors
    -- -- left_hand_component = left_hand_actor:AddComponentByClass(motion_controller_component_c, false, temp_transform, false)
    -- -- right_hand_component = right_hand_actor:AddComponentByClass(motion_controller_component_c, false, temp_transform, false)
    -- * AddComponentByClass() is only available in UE5, use spawn_object() instead
    -- hmd_component = hmd_actor:AddComponentByClass(scene_component_c, false, temp_transform, false) end
    hmd_component = api:spawn_object(scene_component_c, hmd_actor)

    temp_transform.Translation = temp_vec3:set(0, 0, 0)
    temp_transform.Rotation.W = 1.0
    temp_transform.Scale3D = temp_vec3:set(0.3, 0.3, 0.3)
    if hmd_component == nil then
        uprint("Failed to add hmd scene component")
        return
    end
    uprint("Added scene components")

    -- UE5 only
    -- hmd_actor:FinishAddComponent(hmd_component, false, temp_transform)
    -- UE4 alternatively ?
    -- hmd_actor:RegisterComponent(hmd_component)

    -- The HMD is the only one we need to add manually as UObjectHook doesn't support motion controller components as the HMD
    local hmdstate = UEVR_UObjectHook.get_or_add_motion_controller_state(hmd_component)

    if hmdstate then
        hmdstate:set_hand(2) -- HMD
        hmdstate:set_permanent(true)
    end
end

function lib.reset_hmd_actor_if_deleted()
    if hmd_actor ~= nil and not UEVR_UObjectHook.exists(hmd_actor) then
        hmd_actor = nil
        hmd_component = nil
    end
end


function lib.find_camera_component()
    local pawn = api:get_local_pawn(0)
    lib.uprintInstanceNames("Class /Script/Engine.CameraComponent")
    uprint("Pawn: " .. pawn:get_full_name())
    uprint("component_c: ".. camera_component_c:get_full_name())  
    -- camera_component = pawn:GetComponentByClass(camera_component_c)
    camera_component = UEVR_UObjectHook.get_first_object_by_class(camera_component_c)
    uprint("camera component test: " .. tostring(camera_component.RelativeLocation.x))  

    -- local test2 = test:get_child_properties()
    -- uprint ("test2: "..test:get_properties_size())

    -- uprint("parent of camera_component: " .. camera_component.AttachParent:get_full_name())
    -- -- Package/World/Level/CameraActor/CameraComponent
    -- uprint("outer: " .. camera_component:get_outer():get_full_name())
    -- uprint("outer: " .. camera_component:get_outer():get_outer():get_full_name())
    -- uprint("outer: " .. camera_component:get_outer():get_outer():get_outer():get_full_name())
    -- uprint("outer: " .. camera_component:get_outer():get_outer():get_outer():get_outer():get_full_name())


    if camera_component ~= nil then
        return camera_component
    end

    -- local components = camera_component_c:get_objects_matching(false)
    -- if components == nil or #components == 0 then
    --     uprint("No camera components found")
    --     return nil
    -- end

    -- for _, component in ipairs(components) do
    --     uprint("camera component: " .. component:get_full_name())
    --     -- 檢查 CameraComponent 的擁有者
    --     local owner = component:GetOwner()
    --     if owner then
    --         if owner.get_full_name then
    --             uprint("Owner: " .. owner:get_full_name())
    --         else
    --             uprint("Owner found, but get_full_name() method is not available.")
    --         end

    --     else
    --         uprint("Owner not found.")
    --     end
    --     if component.OwnerCharacter ~= nil then
    --         return component
    --     end
    -- end

    return nil
end

function lib.getCameraComponent()
    camera_component = lib.find_camera_component()
    if not camera_component then
        uprint("camera component not found")
        return false
    else
        if camera_component.get_full_name then
            uprint("Found camera component: " .. camera_component:get_full_name())
        else
            uprint("Found camera component, but get_full_name() method is not available.")
        end
        return true
    end
end





function lib.matrixMultiply(a, b)
    local result = {}
    for i = 1, 3 do
        result[i] = {}
        for j = 1, 3 do
            result[i][j] = 0
            for k = 1, 3 do
                result[i][j] = result[i][j] + a[i][k] * b[k][j]
            end
        end
    end
    return result
end

function lib.rotateVector(vector, rotation)
    local radX = math.rad(rotation.x)
    local radY = math.rad(rotation.y)
    local radZ = math.rad(rotation.z)

    local cosX = math.cos(radX)
    local sinX = math.sin(radX)
    local cosY = math.cos(radY)
    local sinY = math.sin(radY)
    local cosZ = math.cos(radZ)
    local sinZ = math.sin(radZ)

    -- Rotation matrix for X axis
    local rotX = {
        {1, 0, 0},
        {0, cosX, -sinX},
        {0, sinX, cosX}
    }

    -- Rotation matrix for Y axis
    local rotY = {
        {cosY, 0, sinY},
        {0, 1, 0},
        {-sinY, 0, cosY}
    }

    -- Rotation matrix for Z axis
    local rotZ = {
        {cosZ, -sinZ, 0},
        {sinZ, cosZ, 0},
        {0, 0, 1}
    }

    -- Combine the rotation matrices
    local rotMatrix = lib.matrixMultiply(rotZ, lib.matrixMultiply(rotY, rotX))

    -- Rotate the vector
    local rotatedVector = {
        x = rotMatrix[1][1] * vector.x + rotMatrix[1][2] * vector.y + rotMatrix[1][3] * vector.z,
        y = rotMatrix[2][1] * vector.x + rotMatrix[2][2] * vector.y + rotMatrix[2][3] * vector.z,
        z = rotMatrix[3][1] * vector.x + rotMatrix[3][2] * vector.y + rotMatrix[3][3] * vector.z
    }

    return rotatedVector
end


function lib.crossProduct(a, b)
    return Vector3f.new(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

function lib.calcRight(forward, up)
    return lib.crossProduct(up, forward)
end


function lib.rotatorToVector(rotation)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.y)
    local roll = math.rad(rotation.z)

    local x = math.cos(pitch) * math.cos(yaw)
    local y = math.cos(pitch) * math.sin(yaw)
    local z = math.sin(pitch)

    return Vector3f.new(x, y, z)
end
function lib.transform_posDelta(posDelta, forward, right, up)
    local transformed_posDelta = Vector3f.new(
        posDelta.x * right.x + posDelta.y * forward.x + posDelta.z * up.x,
        posDelta.x * right.y + posDelta.y * forward.y + posDelta.z * up.y,
        posDelta.x * right.z + posDelta.y * forward.z + posDelta.z * up.z
    )
    return transformed_posDelta
end


-- Equivalent to: vector:normalized()
function lib.normalizeVector(vector)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    if length > 0 then
        return Vector3f.new(vector.x / length, vector.y / length, vector.z / length)
    else
        return Vector3f.new(0, 0, 0)
    end
end

function lib.wrapRotationWithPitchLimit(rot)
    local maxPitch = 89
    rot.x = ((rot.x + 180) % 360) - 180
    if rot.x > maxPitch then
        rot.x = maxPitch
    end
    if rot.x < -maxPitch then
        rot.x = -maxPitch
    end

    rot.y = ((rot.y + 180) % 360) - 180
    rot.z = ((rot.z + 180) % 360) - 180

    return rot
end

function lib.wrapRotation(rotation)
    rotation.x = ((rotation.x + 180) % 360) - 180
    rotation.y = ((rotation.y + 180) % 360) - 180
    rotation.z = ((rotation.z + 180) % 360) - 180
    return rotation
end

function lib.wrapRotationWithPitchLimit_old(rot)
    local maxPitch = 89
    if rot.x > 180 then
        rot.x = rot.x - 360
    elseif rot.x < -180 then
        rot.x = rot.x + 360
    end
    if rot.x > maxPitch then
        rot.x = maxPitch
    end
    if rot.x < -maxPitch then
        rot.x = -maxPitch
    end

    if rot.y > 180 then
        rot.y = rot.y - 360
    elseif rot.y < -180 then
        rot.y = rot.y + 360
    end

    if rot.z > 180 then
        rot.z = rot.z - 360
    elseif rot.z < -180 then
        rot.z = rot.z + 360
    end

    return rot
end
function lib.wrapRotation_old(rotation)
    if rotation.x > 180 then
        rotation.x = rotation.x - 360
    elseif rotation.x < -180 then
        rotation.x = rotation.x + 360
    end

    if rotation.y > 180 then
        rotation.y = rotation.y - 360
    elseif rotation.y < -180 then
        rotation.y = rotation.y + 360
    end

    if rotation.z > 180 then
        rotation.z = rotation.z - 360
    elseif rotation.z < -180 then
        rotation.z = rotation.z + 360
    end

    return rotation
end

-- Equivalent to: kismet_math:FindLookAtRotation()
function lib.lookAtRotator(camPos, targetPos)
    local direction = targetPos - camPos
    direction = lib.normalizeVector(direction)
    return lib.kismet_math:Conv_VectorToRotator(direction)
end

-- Split function for strings
function string:split(sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    if #fields == 0 then
        fields[1] = self
    end
    return fields
end

function lib.sign(x)
    return (x > 0 and 1) or (x < 0 and -1) or 0
end

function lib.atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    else
        return 0 -- x = 0, y = 0，默认返回 0
    end
end

-- For vectors that need to set individual xyz values，e.g. position/rotation in UEVR stereo callbacks
function lib.xyzSetInPlace(vec1, vec2)
    vec1.x = vec2.x
    vec1.y = vec2.y
    vec1.z = vec2.z
end
function lib.xyzAddInPlace(vec1, vec2)
    vec1.x = vec1.x + vec2.x
    vec1.y = vec1.y + vec2.y
    vec1.z = vec1.z + vec2.z
end
function lib.xyzSubInPlace(vec1, vec2)
    vec1.x = vec1.x - vec2.x
    vec1.y = vec1.y - vec2.y
    vec1.z = vec1.z - vec2.z
end
function lib.xyzClearInPlace(vec)
    vec.x = 0
    vec.y = 0
    vec.z = 0
end
function lib.xyzSet(vec1)
    return Vector3f.new(vec1.x, vec1.y, vec1.z)
end
function lib.xyzAdd(vec1, vec2)
    return Vector3f.new(vec1.x + vec2.x, vec1.y + vec2.y, vec1.z + vec2.z)
end
function lib.xyzSub(vec1, vec2)
    return Vector3f.new(vec1.x - vec2.x, vec1.y - vec2.y, vec1.z - vec2.z)
end

return lib

-- You probably shouldnt touch these.
local AnimationDuration = -1
local ChosenAnimation = ""
local ChosenDict = ""
local IsInAnimation = false
local MostRecentChosenAnimation = ""
local MostRecentChosenDict = ""
local MovementType = 0
local PlayerGender = "male"
local PlayerHasProp = false
local PlayerProps = {}
local PlayerParticles = {}
local SecondPropEmote = false
local lang = Config.MenuLanguage
local PtfxNotif = false
local PtfxPrompt = false
local PtfxWait = 500
local PtfxNoProp = false
local DroppedWeaponObjects = {}
local DroppedWeaponTargetDistance = 1.5
local DroppedWeaponTargetZoneRadius = 1.0
local GunGroups = {
  [GetHashKey('GROUP_PISTOL')] = true,
  [GetHashKey('GROUP_SMG')] = true,
  [GetHashKey('GROUP_RIFLE')] = true,
  [GetHashKey('GROUP_MG')] = true,
  [GetHashKey('GROUP_SHOTGUN')] = true,
  [GetHashKey('GROUP_SNIPER')] = true,
  [GetHashKey('GROUP_HEAVY')] = true,
}

local function IsHoldingGun()
		local weapon = GetSelectedPedWeapon(PlayerPedId())
		if not weapon or weapon == GetHashKey('WEAPON_UNARMED') then
			return false
		end
	
	  return GunGroups[GetWeapontypeGroup(weapon)] == true
end

local function LoadModelHash(modelHash)
  while not HasModelLoaded(modelHash) do
    RequestModel(modelHash)
    Wait(10)
  end
end

local function GetDroppedWeaponClipAmmo(playerPed, weaponHash, ammoCount)
  if not ammoCount or ammoCount <= 0 then
    return 0
  end

  local _, maxClipAmmo = GetMaxAmmoInClip(playerPed, weaponHash, true)

  if maxClipAmmo and maxClipAmmo > 0 then
    return math.min(ammoCount, maxClipAmmo)
  end

  return ammoCount
end

local function RemoveDroppedWeaponTarget(dropData)
  if not dropData then
    return
  end

  if dropData.entity and dropData.targetName then
    exports.ox_target:removeLocalEntity(dropData.entity, dropData.targetName)
  end

  if dropData.zoneId then
    exports.ox_target:removeZone(dropData.zoneId, true)
    dropData.zoneId = nil
  end
end

local function RemoveDroppedWeaponEntry(dropId, shouldDeleteEntity)
  local dropData = DroppedWeaponObjects[dropId]

  if not dropData then
    return
  end

  RemoveDroppedWeaponTarget(dropData)

  if shouldDeleteEntity and dropData.entity and DoesEntityExist(dropData.entity) then
    DeleteEntity(dropData.entity)
  end

  DroppedWeaponObjects[dropId] = nil
end

local function RegisterDroppedWeaponPickup(dropId, dropData)
  dropData.targetName = ('dpemotes_pickup_%s'):format(dropId)

  if dropData.entity and DoesEntityExist(dropData.entity) then
    exports.ox_target:addLocalEntity(dropData.entity, {
      {
        name = dropData.targetName,
        icon = 'fa-solid fa-gun',
        label = 'Pick Up Weapon',
        distance = DroppedWeaponTargetDistance,
        onSelect = function()
          TriggerServerEvent('dp:pickupDroppedWeapon', dropId)
        end
      }
    })
  end

  local targetCoords = dropData.coords

  if dropData.entity and DoesEntityExist(dropData.entity) then
    local entityCoords = GetEntityCoords(dropData.entity)
    targetCoords = {
      x = entityCoords.x,
      y = entityCoords.y,
      z = entityCoords.z
    }
    dropData.coords = targetCoords
  end

  if dropData.zoneId then
    exports.ox_target:removeZone(dropData.zoneId, true)
  end

  dropData.zoneId = exports.ox_target:addSphereZone({
    coords = vec3(targetCoords.x, targetCoords.y, targetCoords.z),
    radius = DroppedWeaponTargetZoneRadius,
    debug = false,
    options = {
      {
        name = ('%s_zone'):format(dropData.targetName),
        icon = 'fa-solid fa-gun',
        label = 'Pick Up Weapon',
        distance = DroppedWeaponTargetDistance,
        onSelect = function()
          TriggerServerEvent('dp:pickupDroppedWeapon', dropId)
        end
      }
    }
  })
end

local function TrackDroppedWeaponTarget(dropId, dropData)
  if dropData.trackingTarget then
    return
  end

  dropData.trackingTarget = true

  CreateThread(function()
    local lastCoords

    while DroppedWeaponObjects[dropId] == dropData do
      if not dropData.entity or not DoesEntityExist(dropData.entity) then
        break
      end

      local entityCoords = GetEntityCoords(dropData.entity)

      if not lastCoords or #(vec3(entityCoords.x, entityCoords.y, entityCoords.z) - vec3(lastCoords.x, lastCoords.y, lastCoords.z)) > 0.1 then
        dropData.coords = {
          x = entityCoords.x,
          y = entityCoords.y,
          z = entityCoords.z
        }
        RegisterDroppedWeaponPickup(dropId, dropData)
        lastCoords = dropData.coords
      end

      Wait(150)
    end

    dropData.trackingTarget = nil
  end)
end

local function SpawnDroppedWeaponObject(dropId, dropData)
  if not dropData.weaponModel or dropData.weaponModel == 0 then
    RegisterDroppedWeaponPickup(dropId, dropData)
    return
  end

  LoadModelHash(dropData.weaponModel)

  local weaponObject = CreateObjectNoOffset(
    dropData.weaponModel,
    dropData.spawnCoords.x,
    dropData.spawnCoords.y,
    dropData.spawnCoords.z,
    false,
    false,
    false
  )

  if weaponObject and weaponObject ~= 0 then
    dropData.entity = weaponObject
    SetEntityHeading(weaponObject, dropData.heading + 90.0)
    SetEntityCollision(weaponObject, true, true)
    SetEntityDynamic(weaponObject, true)
    SetEntityHasGravity(weaponObject, true)
    ActivatePhysics(weaponObject)
    ApplyForceToEntity(
      weaponObject,
      1,
      dropData.force.x,
      dropData.force.y,
      dropData.force.z,
      0.0,
      0.0,
      0.0,
      0,
      false,
      true,
      true,
      false,
      true
    )
    SetModelAsNoLongerNeeded(dropData.weaponModel)
    RegisterDroppedWeaponPickup(dropId, dropData)
    TrackDroppedWeaponTarget(dropId, dropData)

    CreateThread(function()
      Wait(1500)

      if not DroppedWeaponObjects[dropId] or not DoesEntityExist(weaponObject) then
        return
      end

      local landedCoords = GetEntityCoords(weaponObject)
      dropData.coords = {
        x = landedCoords.x,
        y = landedCoords.y,
        z = landedCoords.z
      }

      RegisterDroppedWeaponPickup(dropId, dropData)
    end)
  else
    RegisterDroppedWeaponPickup(dropId, dropData)
  end
end

local function DropHeldGunToGround()
  local playerPed = PlayerPedId()
  local weaponHash = GetSelectedPedWeapon(playerPed)

  if not weaponHash or weaponHash == GetHashKey('WEAPON_UNARMED') then
    return false
  end

  local ammoCount = GetAmmoInPedWeapon(playerPed, weaponHash)
  local clipAmmo = GetDroppedWeaponClipAmmo(playerPed, weaponHash, ammoCount)

  local weaponModel = GetWeapontypeModel(weaponHash)

  local handCoords = GetPedBoneCoords(playerPed, 57005, 0.16, 0.03, 0.02)
  local forwardVector = GetEntityForwardVector(playerPed)
  local dropPayload = {
    weaponHash = weaponHash,
    weaponModel = weaponModel,
    ammo = ammoCount,
    clipAmmo = clipAmmo,
    spawnCoords = {
      x = handCoords.x,
      y = handCoords.y,
      z = handCoords.z
    },
    coords = {
      x = handCoords.x,
      y = handCoords.y,
      z = handCoords.z
    },
    heading = GetEntityHeading(playerPed),
    force = {
      x = forwardVector.x * 0.55,
      y = forwardVector.y * 0.55,
      z = -0.15
    }
  }

  SetCurrentPedWeapon(playerPed, GetHashKey('WEAPON_UNARMED'), true)
  RemoveWeaponFromPed(playerPed, weaponHash)
  TriggerServerEvent('dp:createDroppedWeapon', dropPayload)

  lib.notify({
    title = 'Dropped Gun',
    description = "You dropped your weapon on the ground.",
    type = 'inform',
    position = 'center-right'
  })

  return true
end

local function ToggleHandsUpEmote()
  if IsPedSittingInAnyVehicle(PlayerPedId()) then
    return
  end

  if IsInAnimation and ChosenDict == 'missminuteman_1ig_2' and ChosenAnimation == 'handsup_base' then
    EmoteCancel()
    return
  end

  EmoteCommandStart(nil, { 'handsup' })
end

Citizen.CreateThread(function()
  while true do

    if IsPedShooting(PlayerPedId()) and IsInAnimation then
      EmoteCancel()
    end

    if IsInAnimation and IsHoldingGun() then
      EmoteCancel()
    end

    if PtfxPrompt then
      if not PtfxNotif then
          SimpleNotify(PtfxInfo)
          PtfxNotif = true
      end
      if IsControlPressed(0, 47) then
        PtfxStart()
        Wait(PtfxWait)
        PtfxStop()
      end
    end

    if Config.MenuKeybindEnabled then if IsControlPressed(0, Config.MenuKeybind) then OpenEmoteMenu() end end
    if Config.EnableXtoCancel then if IsControlPressed(0, 73) then EmoteCancel() end end
    Citizen.Wait(1)
  end
end)

-----------------------------------------------------------------------------------------------------
-- Commands / Events --------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------

Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/e', 'Play an emote', {{ name="emotename", help="dance, camera, sit or any valid emote."}})
    TriggerEvent('chat:addSuggestion', '/e', 'Play an emote', {{ name="emotename", help="dance, camera, sit or any valid emote."}})
    TriggerEvent('chat:addSuggestion', '/emote', 'Play an emote', {{ name="emotename", help="dance, camera, sit or any valid emote."}})
    if Config.SqlKeybinding then
      TriggerEvent('chat:addSuggestion', '/emotebind', 'Bind an emote', {{ name="key", help="num4, num5, num6, num7. num8, num9. Numpad 4-9!"}, { name="emotename", help="dance, camera, sit or any valid emote."}})
      TriggerEvent('chat:addSuggestion', '/emotebinds', 'Check your currently bound emotes.')
    end
    TriggerEvent('chat:addSuggestion', '/emotemenu', 'Open dpemotes menu (F3) by default.')
    TriggerEvent('chat:addSuggestion', '/emotes', 'List available emotes.')
    TriggerEvent('chat:addSuggestion', '/walk', 'Set your walkingstyle.', {{ name="style", help="/walks for a list of valid styles"}})
    TriggerEvent('chat:addSuggestion', '/walks', 'List available walking styles.')
end)

RegisterCommand('e', function(source, args, raw) EmoteCommandStart(source, args, raw) end)
RegisterCommand('emote', function(source, args, raw) EmoteCommandStart(source, args, raw) end)
if Config.SqlKeybinding then
  RegisterCommand('emotebind', function(source, args, raw) EmoteBindStart(source, args, raw) end)
  RegisterCommand('emotebinds', function(source, args, raw) EmoteBindsStart(source, args, raw) end)
end
RegisterCommand('emotemenu', function(source, args, raw) OpenEmoteMenu() end)
RegisterCommand('emotes', function(source, args, raw) EmotesOnCommand() end)
RegisterCommand('walk', function(source, args, raw) WalkCommandStart(source, args, raw) end)
RegisterCommand('walks', function(source, args, raw) WalksOnCommand() end)
RegisterCommand('+handsup', function()
  ToggleHandsUpEmote()
end, false)
RegisterCommand('-handsup', function()
end, false)
RegisterKeyMapping('+handsup', 'Toggle hands up emote', 'keyboard', 'X')

RegisterNetEvent('dp:registerDroppedWeapon')
AddEventHandler('dp:registerDroppedWeapon', function(dropId, dropData)
  RemoveDroppedWeaponEntry(dropId, true)

  DroppedWeaponObjects[dropId] = dropData
  SpawnDroppedWeaponObject(dropId, dropData)
end)

RegisterNetEvent('dp:removeDroppedWeapon')
AddEventHandler('dp:removeDroppedWeapon', function(dropId)
  RemoveDroppedWeaponEntry(dropId, true)
end)

RegisterNetEvent('dp:syncDroppedWeapons')
AddEventHandler('dp:syncDroppedWeapons', function(drops)
  for dropId, dropData in pairs(drops) do
    if not DroppedWeaponObjects[dropId] then
      DroppedWeaponObjects[dropId] = dropData
      SpawnDroppedWeaponObject(dropId, dropData)
    end
  end
end)

RegisterNetEvent('dp:giveDroppedWeapon')
AddEventHandler('dp:giveDroppedWeapon', function(weaponHash, ammo, clipAmmo)
  local playerPed = PlayerPedId()

  GiveWeaponToPed(playerPed, weaponHash, ammo or 0, false, true)
  SetPedAmmo(playerPed, weaponHash, ammo or 0)

  if clipAmmo and clipAmmo > 0 then
    SetAmmoInClip(playerPed, weaponHash, clipAmmo)
  end

  lib.notify({
    title = 'Picked Up Gun',
    description = 'You picked the weapon up.',
    type = 'success',
    position = 'center-right'
  })
end)

CreateThread(function()
  Wait(1500)
  TriggerServerEvent('dp:requestDroppedWeapons')
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    DestroyAllProps()
    for dropId in pairs(DroppedWeaponObjects) do
      RemoveDroppedWeaponEntry(dropId, true)
    end
    ClearPedTasksImmediately(GetPlayerPed(-1))
    ResetPedMovementClipset(PlayerPedId())
  end
end)

-----------------------------------------------------------------------------------------------------
------ Functions and stuff --------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------

function EmoteCancel()

  if ChosenDict == "MaleScenario" and IsInAnimation then
    ClearPedTasksImmediately(PlayerPedId())
    IsInAnimation = false
    DebugPrint("Forced scenario exit")
  elseif ChosenDict == "Scenario" and IsInAnimation then
    ClearPedTasksImmediately(PlayerPedId())
    IsInAnimation = false
    DebugPrint("Forced scenario exit")
  end

  PtfxNotif = false
  PtfxPrompt = false

  if IsInAnimation then
    PtfxStop()
    ClearPedTasks(GetPlayerPed(-1))
    DestroyAllProps()
    IsInAnimation = false
  end
end

function EmoteChatMessage(args)
  if args == display then
    TriggerEvent("chatMessage", "^5Help^0", {0,0,0}, string.format(""))
  else
    TriggerEvent("chatMessage", "^5Help^0", {0,0,0}, string.format(""..args..""))
  end
end

function DebugPrint(args)
  if Config.DebugDisplay then
    print(args)
  end
end

function PtfxStart()
    if PtfxNoProp then
      PtfxAt = PlayerPedId()
    else
      PtfxAt = prop
    end
    UseParticleFxAssetNextCall(PtfxAsset)
    Ptfx = StartNetworkedParticleFxLoopedOnEntityBone(PtfxName, PtfxAt, Ptfx1, Ptfx2, Ptfx3, Ptfx4, Ptfx5, Ptfx6, GetEntityBoneIndexByName(PtfxName, "VFX"), 1065353216, 0, 0, 0, 1065353216, 1065353216, 1065353216, 0)
    SetParticleFxLoopedColour(Ptfx, 1.0, 1.0, 1.0)
    table.insert(PlayerParticles, Ptfx)
end

function PtfxStop()
  for a,b in pairs(PlayerParticles) do
    DebugPrint("Stopped PTFX: "..b)
    StopParticleFxLooped(b, false)
    table.remove(PlayerParticles, a)
  end
end

function EmotesOnCommand(source, args, raw)
  local EmotesCommand = ""
  for a in pairsByKeys(DP.Emotes) do
    EmotesCommand = EmotesCommand .. ""..a..", "
  end
  EmoteChatMessage(EmotesCommand)
  EmoteChatMessage(Config.Languages[lang]['emotemenucmd'])
end

function pairsByKeys (t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

function EmoteMenuStart(args, hard)
    local name = args
    local etype = hard

    if etype == "dances" then
        if DP.Dances[name] ~= nil then
          if OnEmotePlay(DP.Dances[name]) then end
        end
    elseif etype == "props" then
        if DP.PropEmotes[name] ~= nil then
          if OnEmotePlay(DP.PropEmotes[name]) then end
        end
    elseif etype == "emotes" then
        if DP.Emotes[name] ~= nil then
          if OnEmotePlay(DP.Emotes[name]) then end
        else
          if name ~= "🕺 Dance Emotes" then end
        end
    elseif etype == "expression" then
        if DP.Expressions[name] ~= nil then
          if OnEmotePlay(DP.Expressions[name]) then end
        end
    end
end

function EmoteCommandStart(source, args, raw)
    if #args > 0 then
    local name = string.lower(args[1])
    if name == "c" then
        if IsInAnimation then
            EmoteCancel()
        else
            EmoteChatMessage(Config.Languages[lang]['nocancel'])
        end
      return
    elseif name == "help" then
      EmotesOnCommand()
    return end

    if DP.Emotes[name] ~= nil then
      if OnEmotePlay(DP.Emotes[name]) then end return
    elseif DP.Dances[name] ~= nil then
      if OnEmotePlay(DP.Dances[name]) then end return
    elseif DP.PropEmotes[name] ~= nil then
      if OnEmotePlay(DP.PropEmotes[name]) then end return
    else
      EmoteChatMessage("'"..name.."' "..Config.Languages[lang]['notvalidemote'].."")
    end
  end
end

function LoadAnim(dict)
  while not HasAnimDictLoaded(dict) do
    RequestAnimDict(dict)
    Wait(10)
  end
end

function LoadPropDict(model)
  while not HasModelLoaded(GetHashKey(model)) do
    RequestModel(GetHashKey(model))
    Wait(10)
  end
end

function PtfxThis(asset)
  while not HasNamedPtfxAssetLoaded(asset) do
    RequestNamedPtfxAsset(asset)
    Wait(10)
  end
  UseParticleFxAssetNextCall(asset)
end

function DestroyAllProps()
  for _,v in pairs(PlayerProps) do
    DeleteEntity(v)
  end
  PlayerHasProp = false
  DebugPrint("Destroyed Props")
end

function AddPropToPlayer(prop1, bone, off1, off2, off3, rot1, rot2, rot3)
  local Player = PlayerPedId()
  local x,y,z = table.unpack(GetEntityCoords(Player))

  if not HasModelLoaded(prop1) then
    LoadPropDict(prop1)
  end

  prop = CreateObject(GetHashKey(prop1), x, y, z+0.2,  true,  true, true)
  AttachEntityToEntity(prop, Player, GetPedBoneIndex(Player, bone), off1, off2, off3, rot1, rot2, rot3, true, true, false, true, 1, true)
  table.insert(PlayerProps, prop)
  PlayerHasProp = true
  SetModelAsNoLongerNeeded(prop1)
end

-----------------------------------------------------------------------------------------------------
-- V -- This could be a whole lot better, i tried messing around with "IsPedMale(ped)"
-- V -- But i never really figured it out, if anyone has a better way of gender checking let me know.
-- V -- Since this way doesnt work for ped models.
-- V -- in most cases its better to replace the scenario with an animation bundled with prop instead.
-----------------------------------------------------------------------------------------------------

function CheckGender()
  local hashSkinMale = GetHashKey("mp_m_freemode_01")
  local hashSkinFemale = GetHashKey("mp_f_freemode_01")

  if GetEntityModel(PlayerPedId()) == hashSkinMale then
    PlayerGender = "male"
  elseif GetEntityModel(PlayerPedId()) == hashSkinFemale then
    PlayerGender = "female"
  end
  DebugPrint("Set gender as = ("..PlayerGender..")")
end

-----------------------------------------------------------------------------------------------------
------ This is the major function for playing emotes! -----------------------------------------------
-----------------------------------------------------------------------------------------------------

function OnEmotePlay(EmoteName)

  InVehicle = IsPedInAnyVehicle(PlayerPedId(), true)
  if not Config.AllowedInCars and InVehicle == 1 then
    return
  end

  if not DoesEntityExist(GetPlayerPed(-1)) then
    return false
  end

  if string.lower(ename or '') == 'hands up' and IsHoldingGun() then
    DropHeldGunToGround()
  elseif Config.DisarmPlayer then
    if IsPedArmed(GetPlayerPed(-1), 7) then
      SetCurrentPedWeapon(GetPlayerPed(-1), GetHashKey('WEAPON_UNARMED'), true)
    end
  end

  ChosenDict,ChosenAnimation,ename = table.unpack(EmoteName)
  AnimationDuration = -1

  if PlayerHasProp then
    DestroyAllProps()
  end

  if ChosenDict == "Expression" then
    SetFacialIdleAnimOverride(PlayerPedId(), ChosenAnimation, 0)
    return
  end

  if ChosenDict == "MaleScenario" or "Scenario" then 
    CheckGender()
    if ChosenDict == "MaleScenario" then if InVehicle then return end
      if PlayerGender == "male" then
        ClearPedTasks(GetPlayerPed(-1))
        TaskStartScenarioInPlace(GetPlayerPed(-1), ChosenAnimation, 0, true)
        DebugPrint("Playing scenario = ("..ChosenAnimation..")")
        IsInAnimation = true
      else
        EmoteChatMessage(Config.Languages[lang]['maleonly'])
      end return
    elseif ChosenDict == "ScenarioObject" then if InVehicle then return end
      BehindPlayer = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 0 - 0.5, -0.5);
      ClearPedTasks(GetPlayerPed(-1))
      TaskStartScenarioAtPosition(GetPlayerPed(-1), ChosenAnimation, BehindPlayer['x'], BehindPlayer['y'], BehindPlayer['z'], GetEntityHeading(PlayerPedId()), 0, 1, false)
      DebugPrint("Playing scenario = ("..ChosenAnimation..")")
      IsInAnimation = true
      return
    elseif ChosenDict == "Scenario" then if InVehicle then return end
      ClearPedTasks(GetPlayerPed(-1))
      TaskStartScenarioInPlace(GetPlayerPed(-1), ChosenAnimation, 0, true)
      DebugPrint("Playing scenario = ("..ChosenAnimation..")")
      IsInAnimation = true
    return end 
  end

  LoadAnim(ChosenDict)

  if EmoteName.AnimationOptions then
    if EmoteName.AnimationOptions.EmoteLoop then
      MovementType = 1
    if EmoteName.AnimationOptions.EmoteMoving then
      MovementType = 51
  end

  elseif EmoteName.AnimationOptions.EmoteMoving then
    MovementType = 51
  elseif EmoteName.AnimationOptions.EmoteMoving == false then
    MovementType = 0
  elseif EmoteName.AnimationOptions.EmoteStuck then
    MovementType = 50
  end

  else
    MovementType = 0
  end

  if InVehicle == 1 then
    MovementType = 51
  end

  if EmoteName.AnimationOptions then
    if EmoteName.AnimationOptions.EmoteDuration == nil then 
      EmoteName.AnimationOptions.EmoteDuration = -1
      AttachWait = 0
    else
      AnimationDuration = EmoteName.AnimationOptions.EmoteDuration
      AttachWait = EmoteName.AnimationOptions.EmoteDuration
    end

    if EmoteName.AnimationOptions.PtfxAsset then
      PtfxAsset = EmoteName.AnimationOptions.PtfxAsset
      PtfxName = EmoteName.AnimationOptions.PtfxName
      if EmoteName.AnimationOptions.PtfxNoProp then
        PtfxNoProp = EmoteName.AnimationOptions.PtfxNoProp
      else
        PtfxNoProp = false
      end
      Ptfx1, Ptfx2, Ptfx3, Ptfx4, Ptfx5, Ptfx6, PtfxScale = table.unpack(EmoteName.AnimationOptions.PtfxPlacement)
      PtfxInfo = EmoteName.AnimationOptions.PtfxInfo
      PtfxWait = EmoteName.AnimationOptions.PtfxWait
      PtfxNotif = false
      PtfxPrompt = true
      PtfxThis(PtfxAsset)
    else
      DebugPrint("Ptfx = none")
      PtfxPrompt = false
    end
  end

  TaskPlayAnim(GetPlayerPed(-1), ChosenDict, ChosenAnimation, 2.0, 2.0, AnimationDuration, MovementType, 0, false, false, false)
  RemoveAnimDict(ChosenDict)
  IsInAnimation = true
  MostRecentDict = ChosenDict
  MostRecentAnimation = ChosenAnimation

  if EmoteName.AnimationOptions then
    if EmoteName.AnimationOptions.Prop then
        PropName = EmoteName.AnimationOptions.Prop
        PropBone = EmoteName.AnimationOptions.PropBone
        PropPl1, PropPl2, PropPl3, PropPl4, PropPl5, PropPl6 = table.unpack(EmoteName.AnimationOptions.PropPlacement)
        if EmoteName.AnimationOptions.SecondProp then
          SecondPropName = EmoteName.AnimationOptions.SecondProp
          SecondPropBone = EmoteName.AnimationOptions.SecondPropBone
          SecondPropPl1, SecondPropPl2, SecondPropPl3, SecondPropPl4, SecondPropPl5, SecondPropPl6 = table.unpack(EmoteName.AnimationOptions.SecondPropPlacement)
          SecondPropEmote = true
        else
          SecondPropEmote = false
        end
        Wait(AttachWait)
        AddPropToPlayer(PropName, PropBone, PropPl1, PropPl2, PropPl3, PropPl4, PropPl5, PropPl6)
        if SecondPropEmote then
          AddPropToPlayer(SecondPropName, SecondPropBone, SecondPropPl1, SecondPropPl2, SecondPropPl3, SecondPropPl4, SecondPropPl5, SecondPropPl6)
        end
    end
  end
  return true
end

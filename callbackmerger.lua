---------------------
-- CALLBACK MERGER --
---------------------
-- Version 10
-- Created by piber

-- This script merges all the callbacks registered by mods into a single one for each callback type, fixing callbacks that wouldn't let later callbacks work.
-- It also fixes a few bugs and implements a few QOL changes to the callbacks, including implementing an "early" and "late" callback system

-- Overrides 'Isaac.RegisterMod', 'Isaac.AddCallback', and 'Isaac.RemoveCallback'. Compatibility may be sketchy but could still work.

-- CallbackMerger.RegisteredMods
-- table
-- A table of registered mods that Callback Merger knows about.
-- Used when comparing origin mods of callbacks and to pass it into callback args
-- Indexed by order of discovery

-- CallbackMerger.Callbacks
-- table
-- Contains all the callbacks that were registered, indexed by callback id
-- Callback data = {mod reference, function, extra variable}
-- Callback Merger calls from this, comparing the included values

-- CallbackMerger.EarlyCallbacks
-- table
-- Contains functions that will be called before all other callbacks, indexed by callback id
-- Callback data = {mod reference, function, extra variable}
-- Return values are ignored in early callbacks

-- CallbackMerger.LateCallbacks
-- table
-- Contains functions that will be called after all other callbacks, indexed by callback id
-- Callback data = {mod reference, function, extra variable}
-- Return values are ignored in late callbacks
-- The arg provided after the mod reference will be what the last callback returned, what would normally be the second arg is pushed forward
-- In the case of MC_ENTITY_TAKE_DMG, you would recieve (mod, returned, entity, amount, flags, source, countdown)
-- Notice the "returned" arg after mod and before entity

-- CallbackMerger.CondensedCallbacks
-- table
-- Contains Callback Merger's main callbacks, which call all other callbacks of the same type
-- Indexed by callback id, then indexed by extra variable.

-- CallbackMerger.CallbackReturnFilters
-- table
-- Used to determine if returning true or false in certain callbacks would be treated the same as if they returned nil.
-- Indexed by callback id, set to one of these:
--	0 = ignore all
--	1 = dont ignore anything
--	2 = ignore true for returning
--	3 = ignore false for returning

-- CallbackMerger.CallbackReturnPreventions
-- table
-- Used to determine if returning certain values would prevent later callbacks from being called
-- Indexed by callback id, set to one of these:
-- 0 = returning anything prevents later callbacks
-- 1 = later callbacks happen regardless of what returns
-- 2 = true prevents later callbacks
-- 3 = false prevents later callbacks

-- CallbackMerger.CallbackReturnToArg
-- table
-- Used to determine what callbacks would have their return values passed into the next callback
-- Indexed by callback id, values can be:
--	number = corresponds to the arg to replace with previous callbacks' return values for later callbacks
--	table  = will replace multiple args using number values from replaced tables at those indexes

-- CallbackMerger.ExtendMod
-- function(table mod)
-- Modifies the mod table provided to add Callback Merger's functions to it.

-- CallbackMerger.RegisterMod - Overrides Isaac.RegisterMod
-- function(table mod, string mod name, number api version)
-- No return value
-- Used to store the mods which have been registered, this is done to handle the merged callbacks.
-- Overrides Isaac.RegisterMod, call CallbackMerger.OldRegisterMod for the unmodified RegisterMod function.

-- CallbackMerger.AddCallback - Overrides Isaac.AddCallback
-- function(table mod, number callback id, function, extra variable)
-- No return value
-- Extends AddCallback, this is done to handle the merged callbacks.
-- Overrides Isaac.AddCallback, call CallbackMerger.OldAddCallback for the unmodified AddCallback function.

-- CallbackMerger.AddEarlyCallback - Can be accessed through mod:AddEarlyCallback
-- function(table mod, number callback id, function, extra variable)
-- No return value
-- Facilitates creation of early callbacks in CallbackMerger.EarlyCallbacks
-- Doesn't work with RENDER or INPUT_ACTION callbacks

-- CallbackMerger.AddLateCallback - Can be accessed through mod:AddLateCallback
-- function(table mod, number callback id, function, extra variable)
-- No return value
-- Facilitates creation of late callbacks in CallbackMerger.LateCallbacks
-- Doesn't work with RENDER or INPUT_ACTION callbacks

-- CallbackMerger.RemoveCallback - Overrides Isaac.RemoveCallback
-- function(table mod, number callback id, function)
-- No return value
-- Extends RemoveCallback, this is done to handle the merged callbacks.
-- Overrides Isaac.RemoveCallback, call CallbackMerger.OldRemoveCallback for the unmodified RemoveCallback function.

-- CallbackMerger.RemoveEarlyCallback - Can be accessed through mod:RemoveEarlyCallback
-- function(table mod, number callback id, function)
-- No return value
-- Facilitates removal of early callbacks in CallbackMerger.EarlyCallbacks

-- CallbackMerger.RemoveLateCallback - Can be accessed through mod:RemoveLateCallback
-- function(table mod, number callback id, function)
-- No return value
-- Facilitates removal of late callbacks in CallbackMerger.LateCallbacks

-- CallbackMerger.RemoveAllCallbacks
-- function(table mod)
-- Removes all callbacks registered to the mod provided
-- Used in luamod support
-- No return value

-- CallbackMerger.RemoveAllEarlyCallbacks
-- function(table mod)
-- Removes all early callbacks registered to the mod provided
-- Used in luamod support
-- No return value

-- CallbackMerger.RemoveAllLateCallbacks
-- function(table mod)
-- Removes all late callbacks registered to the mod provided
-- Used in luamod support
-- No return value

------------------------------------------------------------------------------
--                   IMPORTANT:  DO NOT EDIT THIS FILE!!!                   --
------------------------------------------------------------------------------
-- This file relies on other versions of itself being the same.             --
-- If you need something in this file changed, please let the creator know! --
------------------------------------------------------------------------------

-- CODE STARTS BELOW --


-------------
-- version --
-------------
local fileVersion = 10

--prevent older/same version versions of this script from loading
if CallbackMerger and CallbackMerger.Version >= fileVersion then

	return CallbackMerger

end

local recreateCondensedCallbacks = false
local removeBlacklistCallbacks = false
if not CallbackMerger then

	CallbackMerger = {}
	CallbackMerger.Version = fileVersion
	
elseif CallbackMerger.Version < fileVersion then

	local oldVersion = CallbackMerger.Version
	
	-- handle old versions
	if oldVersion < 10 then
		removeBlacklistCallbacks = true
	end
	if oldVersion < 5 then
	
		--replace the condensed callbacks functions with new ones if some were created
		if #CallbackMerger.CondensedCallbacks > 0 then
			recreateCondensedCallbacks = true
		end
		
	end

	CallbackMerger.Version = fileVersion

end


-----------
-- setup --
-----------
CallbackMerger.Mod = CallbackMerger.Mod or RegisterMod("Callback Merger", 1)


----------------------------
-- callback type handling --
----------------------------

--CallbackMerger.CallbackReturnFilters--
-- 0 = ignore all
-- 1 = dont ignore anything
-- 2 = ignore true for returning
-- 3 = ignore false for returning
CallbackMerger.CallbackReturnFilters = CallbackMerger.CallbackReturnFilters or {}

CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_USE_ITEM] = 3

--these callbacks can only be used once in the base game
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_FAMILIAR_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_NPC_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PLAYER_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PICKUP_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_TEAR_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PROJECTILE_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_KNIFE_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_BOMB_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_NPC_UPDATE] = 3
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD] = 3


--CallbackMerger.CallbackReturnPreventions--
-- 0 = later callbacks happen regardless of what returns
-- 1 = returning anything prevents later callbacks
-- 2 = true prevents later callbacks
-- 3 = false prevents later callbacks
CallbackMerger.CallbackReturnPreventions = CallbackMerger.CallbackReturnPreventions or {}
	
CallbackMerger.CallbackReturnPreventions[ModCallbacks.MC_ENTITY_TAKE_DMG] = 3
CallbackMerger.CallbackReturnPreventions[ModCallbacks.MC_PRE_USE_ITEM] = 2
CallbackMerger.CallbackReturnPreventions[ModCallbacks.MC_PRE_NPC_UPDATE] = 2
CallbackMerger.CallbackReturnPreventions[ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD] = 2

--these callbacks can only be used once in the base game, we're going to make it so returning nil allows later callbacks
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_FAMILIAR_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_NPC_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PLAYER_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PICKUP_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_TEAR_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_PROJECTILE_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_KNIFE_COLLISION] = 1
CallbackMerger.CallbackReturnFilters[ModCallbacks.MC_PRE_BOMB_COLLISION] = 1


--CallbackMerger.CallbackReturnToArg--
-- number corresponds to the arg to replace with previous callbacks' return values for later callbacks
-- table containing numbers will replace multiple args using values from replaced tables at those indexes
CallbackMerger.CallbackReturnToArg = CallbackMerger.CallbackReturnToArg or {}

CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_POST_CURSE_EVAL] = 1 --return value is the curse bitmask
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_POST_PICKUP_SELECTION] = {2,3} --return values are entity variant and subtype

--these callbacks only let the first return do something in the base game
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_PRE_ENTITY_SPAWN] = {1,2,3,7} --return values are entity type, variant, subtype, and seed
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN] = {1,2,3} --return values are entity type, variant, and subtype

--these callbacks dont do this in the base game
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_GET_CARD] = 2 --return value is card id
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_POST_GET_COLLECTIBLE] = 1 --return value is item id
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_GET_PILL_EFFECT] = 1 --return value is pill effect id
CallbackMerger.CallbackReturnToArg[ModCallbacks.MC_GET_TRINKET] = 1 --return value is trinket id

--CallbackMerger.CallbackCompareExtraVar--
-- 0 = no comparison, all callbacks happen
-- 1 = compares the extra var directly to the first arg
-- 2 = compares the extra var directly to a GetPlayerType() call on the first arg
-- 3 = compares the extra var directly to the .Type attribute on the first arg
-- 4 = compares the extra var directly to the .Variant attribute on the first arg
-- 5 = compares the extra var directly to the second arg
CallbackMerger.CallbackCompareExtraVar = CallbackMerger.CallbackCompareExtraVar or {}

CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_USE_ITEM] = 1
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_USE_CARD] = 1
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_USE_PILL] = 1
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_USE_ITEM] = 1

CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PEFFECT_UPDATE] = 2

CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_NPC_UPDATE] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_ENTITY_TAKE_DMG] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_NPC_INIT] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_NPC_RENDER] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_NPC_DEATH] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_NPC_COLLISION] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_ENTITY_REMOVE] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_ENTITY_KILL] = 3
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_NPC_UPDATE] = 3

CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_FAMILIAR_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_FAMILIAR_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PLAYER_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_FAMILIAR_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_FAMILIAR_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PLAYER_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_PLAYER_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PICKUP_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PICKUP_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PICKUP_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_PICKUP_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_TEAR_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_TEAR_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_TEAR_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_TEAR_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PROJECTILE_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PROJECTILE_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_PROJECTILE_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_PROJECTILE_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_LASER_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_LASER_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_LASER_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_KNIFE_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_KNIFE_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_KNIFE_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_KNIFE_COLLISION] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_EFFECT_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_EFFECT_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_EFFECT_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_BOMB_INIT] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_BOMB_UPDATE] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_POST_BOMB_RENDER] = 4
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_PRE_BOMB_COLLISION] = 4

CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_EVALUATE_CACHE] = 5
CallbackMerger.CallbackCompareExtraVar[ModCallbacks.MC_INPUT_ACTION] = 5

-- CallbackMerger.Blacklist
--these callbacks will not be merged, for performance reasons
CallbackMerger.Blacklist = CallbackMerger.Blacklist or {}
CallbackMerger.Blacklist[ModCallbacks.MC_NPC_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PEFFECT_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_FAMILIAR_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_INPUT_ACTION] = true
CallbackMerger.Blacklist[ModCallbacks.MC_LEVEL_GENERATOR] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_NPC_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PLAYER_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PLAYER_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PICKUP_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PICKUP_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_TEAR_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_TEAR_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PROJECTILE_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_PROJECTILE_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_LASER_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_LASER_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_KNIFE_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_KNIFE_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_EFFECT_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_EFFECT_RENDER] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_BOMB_UPDATE] = true
CallbackMerger.Blacklist[ModCallbacks.MC_POST_BOMB_RENDER] = true

CallbackMerger.CallbackIdToString = CallbackMerger.CallbackIdToString or {}
for callbackName, callbackId in pairs(ModCallbacks) do
	CallbackMerger.CallbackIdToString[callbackId] = callbackName
end


-----------------
-- addcallback --
-----------------
CallbackMerger.RegisteredMods = CallbackMerger.RegisteredMods or {}
CallbackMerger.Callbacks = CallbackMerger.Callbacks or {}
CallbackMerger.EarlyCallbacks = CallbackMerger.EarlyCallbacks or {}
CallbackMerger.LateCallbacks = CallbackMerger.LateCallbacks or {}
CallbackMerger.CondensedCallbacks = CallbackMerger.CondensedCallbacks or {}

--override AddCallback to handle merging of callbacks
local compareArgs = {
	[0] = function(args, dataExtraVar) return true end,
	[1] = function(args, dataExtraVar) return args[1] == dataExtraVar end,
	[2] = function(args, dataExtraVar) return args[1]:GetPlayerType() == dataExtraVar end,
	[3] = function(args, dataExtraVar) return args[1].Type == dataExtraVar end,
	[4] = function(args, dataExtraVar) return args[1].Variant == dataExtraVar end,
	[5] = function(args, dataExtraVar) return args[2] == dataExtraVar end
}
CallbackMerger.OldAddCallback = CallbackMerger.OldAddCallback or Isaac.AddCallback
function CallbackMerger.CreateMergedCallback(callbackId)
	
	local functionExistedAlready = false
	if CallbackMerger.CondensedCallbacks[callbackId] then
		functionExistedAlready = true
	end

	CallbackMerger.CondensedCallbacks[callbackId] = function(_, ...)
	
		local args = {...}
		
		local compareType = CallbackMerger.CallbackCompareExtraVar[callbackId]
		local compareFunc = compareArgs[compareType] or compareArgs[0]
		
		
		--EARLY CALLBACKS
		if CallbackMerger.EarlyCallbacks[callbackId] then
		
			for _, callbackData in ipairs(CallbackMerger.EarlyCallbacks[callbackId]) do
			
				local dataExtraVar = callbackData[3]
				if dataExtraVar == -1 or compareFunc(args, dataExtraVar) then
				
					local dataMod = callbackData[1]
					local dataFunction = callbackData[2]
		
					--pcall to catch any errors
					local noErrors, returned = pcall(dataFunction, dataMod, table.unpack(args))
					
					if not noErrors then
					
						error("[" .. tostring(dataMod.Name) .. "] (Early) " .. returned, 2)
					
					end
					
				end
			
			end
			
		end
		
		--MAIN CALLBACKS (THESE CAN RETURN VALUES)
		local toReturn = nil
		if CallbackMerger.Callbacks[callbackId] then
			
			local ignoreTrueReturn = false
			local ignoreFalseReturn = false
			
			if CallbackMerger.CallbackReturnFilters[callbackId] then
			
				-- 0 = ignore all
				-- 1 = dont ignore anything
				-- 2 = ignore true for returning
				-- 3 = ignore false for returning
				ignoreTrueReturn = CallbackMerger.CallbackReturnFilters[callbackId] == 0 or CallbackMerger.CallbackReturnFilters[callbackId] == 2
				ignoreFalseReturn = CallbackMerger.CallbackReturnFilters[callbackId] == 0 or CallbackMerger.CallbackReturnFilters[callbackId] == 3
			
			end
			
			local returnAtTrueReturn = false
			local returnAtFalseReturn = false
			
			if CallbackMerger.CallbackReturnPreventions[callbackId] then
			
				-- 0 = later callbacks happen regardless of what returns
				-- 1 = returning anything prevents later callbacks
				-- 2 = true prevents later callbacks
				-- 3 = false prevents later callbacks
				returnAtTrueReturn = CallbackMerger.CallbackReturnPreventions[callbackId] == 1 or CallbackMerger.CallbackReturnPreventions[callbackId] == 2
				returnAtFalseReturn = CallbackMerger.CallbackReturnPreventions[callbackId] == 1 or CallbackMerger.CallbackReturnPreventions[callbackId] == 3
			
			end
			
			local returnToArg = CallbackMerger.CallbackReturnToArg[callbackId]
		
			for _, callbackData in ipairs(CallbackMerger.Callbacks[callbackId]) do
			
				local dataExtraVar = callbackData[3]

				if dataExtraVar == -1 or compareFunc(args, dataExtraVar) then
				
					local dataMod = callbackData[1]
					local dataFunction = callbackData[2]
				
					--pcall to catch any errors
					local noErrors, returned = pcall(dataFunction, dataMod, table.unpack(args))
					
					if not noErrors then
					
						error("[" .. tostring(dataMod.Name) .. "] " .. returned, 2)
					
					--callback passed with no errors
					elseif type(returned) ~= "nil" then
					
						local doReturn = true
						
						if type(returned) == "boolean" then
							
							--ignore true if we should
							if returned and ignoreTrueReturn then
								doReturn = false
							end
							
							--ignore false if we should
							if not returned and ignoreFalseReturn then
								doReturn = false
							end
							
						end
					
						if doReturn then
						
							toReturn = returned
							
							--set the args to values which were returned
							if returnToArg then
							
								if type(returnToArg) == "number" and type(returned) == "number" then
									args[returnToArg] = returned
								end
							
								if type(returnToArg) == "table" and type(returned) == "table" then
								
									for _,argindex in ipairs(returnToArg) do
									
										if returned[argindex] then
											args[argindex] = returned[argindex]
										end
										
									end
									
								end
								
							end
							
							--prevent later callbacks from happening if we should
							if (toReturn == true and returnAtTrueReturn == true)
							or (toReturn == false and returnAtFalseReturn == true) then
								
								break
								
							end
							
						end
						
					end
					
				end
			
			end
			
		end
		
		--LATE CALLBACKS (THESE CAN SEE WHAT THE LAST CALLBACK RETURNED)
		if CallbackMerger.LateCallbacks[callbackId] then
		
			for _, callbackData in ipairs(CallbackMerger.LateCallbacks[callbackId]) do
			
				local dataExtraVar = callbackData[3]
			
				if dataExtraVar == -1 or compareFunc(args, dataExtraVar) then
				
					local dataMod = callbackData[1]
					local dataFunction = callbackData[2]
		
					--pcall to catch any errors
					local noErrors, returned = pcall(dataFunction, dataMod, toReturn, table.unpack(args))
					
					if not noErrors then
					
						error("[" .. tostring(dataMod.Name) .. "] (Late) " .. returned, 2)
					
					end
					
				end
			
			end
			
		end
		
		return toReturn
	
	end
	
	if not functionExistedAlready then
	
		CallbackMerger.OldAddCallback(CallbackMerger.Mod, callbackId, CallbackMerger.CondensedCallbacks[callbackId], -1)
		
	end

end

function CallbackMerger.AddCallbackToTable(mod, callbackId, fn, extraVar, funcName, callbackTable, warn)
	
	if CallbackMerger.Blacklist[callbackId] or not CallbackMerger.CallbackIdToString[callbackId] then
	
		local callbackAdded, returned = pcall(CallbackMerger.OldAddCallback, mod, callbackId, fn, extraVar)
		
		if callbackAdded then
		
			if warn then
			
				local fullWarning = "[" .. tostring(mod.Name) .. "] Added " .. CallbackMerger.CallbackIdToString[callbackId] .. " callback as a regular callback - cannot be added as a" .. warn .. " callback!"
				Isaac.DebugString(fullWarning)
				print(fullWarning)
			
			end
		
		else
			error(returned, 2)
		end
		
	else
	
		--force undefined/non-number extra vars to -1
		if type(extraVar) ~= "number" then
		
			extraVar = -1
			
		end

		--error if no callback id was provided
		if type(callbackId) ~= "number" then
		
			error("bad argument #2 to '" .. funcName .. "' (number expected, got " .. type(callbackId) .. ")", 2)
			
		end
		
		--error if no function was provided
		if type(fn) ~= "function" then
		
			error("bad argument #3 to '" .. funcName .. "' (function expected, got " .. type(fn) .. ")", 2)
			
		end

		if type(mod) == "table" then
		
			--extend the mod
			CallbackMerger.ExtendMod(mod)

		end

		--add the callback to the callbacks table
		callbackTable[callbackId] = callbackTable[callbackId] or {}
		table.insert(callbackTable[callbackId], {mod, fn, extraVar})
		
		--create a callback for the callback merger mod if it doesnt already exist
		if not CallbackMerger.CondensedCallbacks[callbackId] then
		
			CallbackMerger.CreateMergedCallback(callbackId)
			
		end
	
	end

end

function CallbackMerger.AddCallback(mod, callbackId, fn, extraVar)
	
	CallbackMerger.AddCallbackToTable(mod, callbackId, fn, extraVar, "AddCallback", CallbackMerger.Callbacks)

end
Isaac.AddCallback = CallbackMerger.AddCallback

function CallbackMerger.AddEarlyCallback(mod, callbackId, fn, extraVar)
	
	CallbackMerger.AddCallbackToTable(mod, callbackId, fn, extraVar, "AddEarlyCallback", CallbackMerger.EarlyCallbacks, "n early")

end

function CallbackMerger.AddLateCallback(mod, callbackId, fn, extraVar)
	
	CallbackMerger.AddCallbackToTable(mod, callbackId, fn, extraVar, "AddLateCallback", CallbackMerger.LateCallbacks, " late")

end


--------------------
-- removecallback --
--------------------
--override RemoveCallback to handle removing of merged callbacks
CallbackMerger.OldRemoveCallback = CallbackMerger.OldRemoveCallback or Isaac.RemoveCallback
function CallbackMerger.RemoveCallbackFromTable(mod, callbackId, fn, funcName, callbackTable)
	
	if CallbackMerger.Blacklist[callbackId]
	or not CallbackMerger.CallbackIdToString[callbackId]
	or not CallbackMerger.Callbacks[callbackId]
	or not CallbackMerger.EarlyCallbacks[callbackId]
	or not CallbackMerger.LateCallbacks[callbackId] then
	
		local callbackRemoved, returned = pcall(CallbackMerger.OldRemoveCallback, mod, callbackId, fn)
		
		if not callbackRemoved then
			error(returned, 2)
		end
		
	else
	
		--error if no callback id was provided
		if type(callbackId) ~= "number" then
		
			error("bad argument #2 to '" .. funcName .. "' (number expected, got " .. type(callbackId) .. ")", 2)
			
		end
		
		--error if no function was provided
		if type(fn) ~= "function" then
		
			error("bad argument #3 to '" .. funcName .. "' (function expected, got " .. type(fn) .. ")", 2)
			
		end
		
		if type(mod) == "table" then
		
			--extend the mod
			CallbackMerger.ExtendMod(mod)

		end
		
		--remove the callback from the callbacks table
		if callbackTable[callbackId] then
		
			for i=#callbackTable[callbackId], 1, -1 do
			
				local callbackData = callbackTable[callbackId][i]
				
				if callbackData[1] == mod and callbackData[2] == fn then
				
					table.remove(callbackTable[callbackId], i)
				
				end
				
			end
			
		end
	
	end

end

function CallbackMerger.RemoveCallback(mod, callbackId, fn)
	
	CallbackMerger.RemoveCallbackFromTable(mod, callbackId, fn, "RemoveCallback", CallbackMerger.Callbacks)

end
Isaac.RemoveCallback = CallbackMerger.RemoveCallback

function CallbackMerger.RemoveEarlyCallback(mod, callbackId, fn)
	
	CallbackMerger.RemoveCallbackFromTable(mod, callbackId, fn, "RemoveEarlyCallback", CallbackMerger.EarlyCallbacks)

end

function CallbackMerger.RemoveLateCallback(mod, callbackId, fn)
	
	CallbackMerger.RemoveCallbackFromTable(mod, callbackId, fn, "RemoveLateCallback", CallbackMerger.LateCallbacks)

end


--------------------------
-- remove all callbacks --
--------------------------
function CallbackMerger.RemoveAllCallbacksFromTable(mod, funcName, callbackTable)
	
	if type(mod) == "table" then
	
		--extend the mod
		CallbackMerger.ExtendMod(mod)

	end
	
	--remove the callback from the callbacks table
	for _,callbacks in pairs(callbackTable) do
	
		for i=#callbacks, 1, -1 do
		
			local callbackData = callbacks[i]
			
			if callbackData[1] == mod then
			
				table.remove(callbacks, i)
			
			end
			
		end
		
	end

end

function CallbackMerger.RemoveAllCallbacks(mod)
	
	CallbackMerger.RemoveAllCallbacksFromTable(mod, "RemoveAllCallbacks", CallbackMerger.Callbacks)

end
Isaac.RemoveCallback = CallbackMerger.RemoveCallback

function CallbackMerger.RemoveAllEarlyCallbacks(mod)
	
	CallbackMerger.RemoveAllCallbacksFromTable(mod, "RemoveAllEarlyCallbacks", CallbackMerger.EarlyCallbacks)

end

function CallbackMerger.RemoveAllLateCallbacks(mod)
	
	CallbackMerger.RemoveAllCallbacksFromTable(mod, "RemoveAllLateCallbacks", CallbackMerger.LateCallbacks)

end


-----------------
-- registermod --
-----------------

function CallbackMerger.ExtendMod(mod)

	--check if the mod is already in the table
	local modAlreadyRegistered = false
	for i=1, #CallbackMerger.RegisteredMods do
		
		if CallbackMerger.RegisteredMods[i] == mod then
			modAlreadyRegistered = true
			break
		end
		
	end
	
	--add mod to registered mods table
	if not modAlreadyRegistered then
		CallbackMerger.RegisteredMods[#CallbackMerger.RegisteredMods+1] = mod
	end
	
	if not mod.CallbackMergerExtended or mod.CallbackMergerExtended < fileVersion then
		
		mod.CallbackMergerExtended = fileVersion
		
		--AddEarlyCallback
		mod.AddEarlyCallback = function(self, callbackId, fn, extraVar)
		
			if extraVar == nil then
			
				extraVar = -1
				
			end

			CallbackMerger.AddEarlyCallback(self, callbackId, fn, extraVar)
			
		end
		
		--AddLateCallback
		mod.AddLateCallback = function(self, callbackId, fn, extraVar)
		
			if extraVar == nil then
			
				extraVar = -1
				
			end

			CallbackMerger.AddLateCallback(self, callbackId, fn, extraVar)
			
		end
		
		--RemoveEarlyCallback
		mod.RemoveEarlyCallback = function(self, callbackId, fn)
		
			CallbackMerger.RemoveEarlyCallback(self, callbackId, fn)
			
		end
		
		--RemoveLateCallback
		mod.RemoveLateCallback = function(self, callbackId, fn)
		
			CallbackMerger.RemoveLateCallback(self, callbackId, fn)
			
		end
	
	end
	
end

--override RegisterMod to catch registered mods and add new functions
CallbackMerger.OldRegisterMod = CallbackMerger.OldRegisterMod or Isaac.RegisterMod
function CallbackMerger.RegisterMod(mod, modname, apiversion)

	--check if a mod that shares this mod's name is already in the table, and remove all of its callbacks if it is
	--helps handle luamod better
	for i=#CallbackMerger.RegisteredMods, 1, -1 do
		
		if CallbackMerger.RegisteredMods[i].Name == mod.Name then
		
			CallbackMerger.RemoveAllCallbacks(CallbackMerger.RegisteredMods[i])
			CallbackMerger.RemoveAllEarlyCallbacks(CallbackMerger.RegisteredMods[i])
			CallbackMerger.RemoveAllLateCallbacks(CallbackMerger.RegisteredMods[i])
			
			table.remove(CallbackMerger.RegisteredMods, i)
			
		end
		
	end
	
	--call the old register mod function
	--pcall to catch any errors
	local modRegistered, returned = pcall(CallbackMerger.OldRegisterMod, mod, modname, apiversion)
	
	--erroring
	if not modRegistered then
	
		returned = string.gsub(returned, "callbackmerger.OldRegisterMod", "RegisterMod")
		error(returned, 2)
		
	end
	
	if type(mod) == "table" then
	
		--extend the mod
		CallbackMerger.ExtendMod(mod)

	end
	
end
Isaac.RegisterMod = CallbackMerger.RegisterMod

------------------------
-- old version compat --
------------------------
if removeBlacklistCallbacks then

	for callbackId, callbackFunc in pairs(CallbackMerger.CondensedCallbacks) do
	
		if CallbackMerger.Blacklist[callbackId] or not CallbackMerger.CallbackIdToString[callbackId] then
			CallbackMerger.OldRemoveCallback(CallbackMerger.Mod, callbackId, callbackFunc)
		end
	
		CallbackMerger.CondensedCallbacks[callbackId] = nil
		
		if CallbackMerger.EarlyCallbacks[callbackId] then
		
			for _, callbackData in ipairs(CallbackMerger.EarlyCallbacks[callbackId]) do
			
				local dataMod = callbackData[1]
				local dataFunction = callbackData[2]
				local dataExtraVar = callbackData[3]
				
				CallbackMerger.OldAddCallback(dataMod, callbackId, dataFunction, dataExtraVar)
				
			end
			
		end
		
		if CallbackMerger.Callbacks[callbackId] then
		
			for _, callbackData in ipairs(CallbackMerger.Callbacks[callbackId]) do
			
				local dataMod = callbackData[1]
				local dataFunction = callbackData[2]
				local dataExtraVar = callbackData[3]
				
				CallbackMerger.OldAddCallback(dataMod, callbackId, dataFunction, dataExtraVar)
				
			end
			
		end
		
		if CallbackMerger.LateCallbacks[callbackId] then
		
			for _, callbackData in ipairs(CallbackMerger.LateCallbacks[callbackId]) do
			
				local dataMod = callbackData[1]
				local dataFunction = callbackData[2]
				local dataExtraVar = callbackData[3]
				
				CallbackMerger.OldAddCallback(dataMod, callbackId, dataFunction, dataExtraVar)
				
			end
			
		end
		
	end
	
end

if recreateCondensedCallbacks then
	
	for callbackId, _ in pairs(CallbackMerger.CondensedCallbacks) do
	
		CallbackMerger.CreateMergedCallback(callbackId)
		
	end
	
end

------------
-- return --
------------
return CallbackMerger


-- Given a feature structure containing a "here" rule, return {x,y} the tile the
-- here points at, or nil if there is no "here".
function getHereTarget(feature)
	local unitids = feature[3]
	local hereword = nil
	for i = #unitids, 1, -1 do
		local word = mmf.newObject(unitids[i][1])
		if (word ~= nil and word.strings[UNITNAME] == "text_here") then
			hereword = word
			break
		end
	end

	if hereword == nil then
		return nil
	end

	local x, y = hereword.values[XPOS],hereword.values[YPOS]
	local newx, newy = getadjacenttile(hereword.fixed, x, y, hereword.values[DIR])

	if newx < 1 or newx > roomsizex - 2 or newy < 1 or newy > roomsizey - 2 then
		return {x, y}
	end

	return {newx, newy}
end

-- As above, but for "there".
function getThereTarget(feature)
	local unitids = feature[3]
	local thereword = nil
	for i = #unitids, 1, -1 do
		local word = mmf.newObject(unitids[i][1])
		if (word ~= nil and word.strings[UNITNAME] == "text_there") then
			thereword = word
			break
		end
	end

	if thereword == nil then
		return nil
	end

	local x, y = thereword.values[XPOS], thereword.values[YPOS]
	local targetdir = thereword.values[DIR]
	local warps = {}

	while true do
		local newx, newy, newdir, newwarps = getadjacenttile(thereword.fixed, x, y, targetdir)

		-- Don't follow the same warp more than once (infinite loop protection)
		for _, warp in ipairs(newwarps) do
			for _, otherwarp in ipairs(warps) do
				if warp[1] == otherwarp[1] and warp[2] == otherwarp[2] then
					return {x, y}
				end
			end

			table.insert(warps, warp)
		end

		if newx < 1 or newx > roomsizex - 2 or newy < 1 or newy > roomsizey - 2 then
			return {x, y}
		end

		local obstacles = unitmap[newy * roomsizex + newx]

		if obstacles ~= nil then
			for _,obstacleid in ipairs(obstacles) do
				local obstacle = mmf.newObject(obstacleid)
				local name = getname(obstacle)
				if hasfeature(name,"is","stop",obstacleid) ~= nil or hasfeature(name,"is","push",obstacleid) ~= nil or hasfeature(name,"is","pull",obstacleid) ~= nil then
					return {x, y}
				end
			end
		end

		x, y, targetdir = newx, newy, newdir
	end
end

local lookup = {
	["here"] = getHereTarget,
	["there"] = getThereTarget
}

-- Hook "update", found in tools.lua
local oldUpdate = update
function myUpdate(unitid,x,y,dir_)
	local unit = mmf.newObject(unitid)
	local name = getname(unit)
	local dir = dir_

	-- In vanilla Baba, the right/up/left/down rules only apply once,
	-- fairly late in the turn. This means that if, say, rock is push and left,
	-- and you push it up, it will still be facing up for a while before it points
	-- left again. With THOSE and "text is right/up/left/down", this causes unpredictable
	-- behaviour, so we fix this issue here by preventing all other direction changes when these rules apply.
	if hasfeature(name,"is","down",unitid) then
		dir = 3
	elseif hasfeature(name,"is","left",unitid) then
		dir = 2
	elseif hasfeature(name,"is","up",unitid) then
		dir = 1
	elseif hasfeature(name,"is","right",unitid) then
		dir = 0
	end

	-- In "check" we prevent regular movement from moving the unit onto "not here" tiles.
	-- But there are some special kinds of movement as well, like TELE. Prevent those.
	if neitherHereNorThere(unitid,x,y) then
		oldUpdate(unitid,unit.values[XPOS],unit.values[YPOS],dir)
	else
		oldUpdate(unitid,x,y,dir)
	end
end



update = myUpdate

	function neitherHereNorThere(unitid,x,y)
		local unit = mmf.newObject(unitid)

		for rulename,targetfunction in pairs(lookup) do
			local rules = featureindex["not " .. rulename]

			if rules ~= nil then
				for _,rule in ipairs(rules) do
					local baserule = rule[1]
					local conds = rule[2]
					local target = targetfunction(rule)

					if target ~= nil and x == target[1] and y == target[2] then
						if getname(unit) == baserule[1] and testcond(conds,unitid) then
							return true
						elseif baserule[1] == "group" and hasfeature(getname(unit),"is","group",unitid) and testcond(conds,unitid) then
							-- Group needs a special case here. The featureindex does include additional entries for
							-- each type of thing in the group, but the word IDs do not include the "here" rule, so getHereTarget doesn't work for those.
							return true
						end
					end
				end
			end
		end
		return false
	end

	-- Apply all IS HERE and IS THERE rules.
	function applyHeresAndTheres()
		for rulename,targetfunction in pairs(lookup) do
			local rules = featureindex[rulename]
			if rules ~= nil then
				for _,rule in ipairs(rules) do
					local baserule = rule[1]
					if baserule[2] == "is" then
						local conds = rule[2]
						local target = targetfunction(rule)

						if target ~= nil then
							local targetx,targety = target[1],target[2]
							local applied = false

							if baserule[1] == "group" then
								-- Group needs a special case here. The featureindex does include additional entries for
								-- each type of thing in the group, but the word IDs do not include the "here" rule, so getheretarget/gettheretarget doesn't work for those.
								for _,selector in ipairs(findgroup()) do
									for _,unitid in ipairs(findall(selector)) do
										if testcond(conds,unitid) then
											local unit = mmf.newObject(unitid)
											if unit.values[XPOS] ~= targetx or unit.values[YPOS] ~= targety then
												addaction(unitid,{"update",targetx,targety,unit.values[DIR]})
												applied = true
											end
										end
									end
								end
							else
								for _,unitid in ipairs(findall({baserule[1], conds})) do
									local unit = mmf.newObject(unitid)
									if unit.values[XPOS] ~= targetx or unit.values[YPOS] ~= targety then
										addaction(unitid,{"update",targetx,targety,unit.values[DIR]})
										applied = true
									end
								end
							end

							if applied then
								local pmult,sound = checkeffecthistory("here")
								MF_particles("glow",targetx,targety,5 * pmult,1,4,1,1)
								setsoundname("turn",6,sound)
							end
						end
					end
				end
			end
		end
	end

	condlist.those = function (params, checkedconds,checkedconds_,cdata)

		local unitid, wordids = cdata.unitid, cdata.wordids



		local x_ = cdata.x
		local y_ = cdata.y

		if x_ == nil or y_ == nil then
			if unitid ~= 1 and unitid ~= 2 then
				local unit = mmf.newObject(unitid)
				x_, y_ = unit.values[XPOS], unit.values[YPOS]
			end
		end
		local ourresult = true

		local words = {}

		for a, b in ipairs(wordids) do
			local wunit = mmf.newObject(b[1])
			if wunit.strings[UNITNAME] == "text_those" then
				table.insert(words, b[1])
			end
		end

		for a, b in ipairs(words) do
			local word = mmf.newObject(b)
			if (word == nil) then
				print("Word is nil!")
				return false, checkedconds
			end

			local wx,wy = word.values[XPOS],word.values[YPOS]
			local wdir = ndirs[word.values[DIR] + 1]
			local ox,oy = wdir[1],wdir[2]



			if (ox == 0) then
				ourresult = ourresult and (x_ == wx)
			else
				ourresult = ourresult and (ox * x_ > ox * wx)
			end

			if (oy == 0) then
				ourresult = ourresult and (y_ == wy)
			else
				ourresult = ourresult and (oy * y_ > oy * wy)
			end
		end

		return ourresult, checkedconds
	end

	table.insert(editor_objlist_order, "text_those")
	table.insert(editor_objlist_order, "text_here")
	table.insert(editor_objlist_order, "text_there")

	--[[mod.tiles["those"] = {
		name = "text_those",
		sprite = "text_those",
		sprite_in_root = false,
		unittype = "text",
		tiling = 2,
		type = 3,
		operatortype = "cond_start",
		colour = {3, 2},
		active = {3, 3},
		tile = {0, 25},
		layer = 20,
	}]]

	editor_objlist["text_those"] =
	{
		name = "text_those",
		sprite_in_root = false,
		unittype = "text",
		tags = {"text","text_condition"},
		tiling = 2,
		type = 3,
		layer = 20,
		colour = {3, 2},
		colour_active = {3, 3},
		layer = 20,
	}

	--[[mod.tiles["here"] = {
		name = "text_here",
		sprite = "text_here",
		sprite_in_root = false,
		unittype = "text",
		tiling = 2,
		type = 2,
		colour = {3, 2},
		active = {3, 3},
		tile = {1, 25},
		layer = 20,
	}]]

	editor_objlist["text_here"] =
	{
		name = "text_here",
		sprite_in_root = false,
		unittype = "text",
		tags = {"text","text_adjective"},
		tiling = 2,
		type = 2,
		layer = 20,
		colour = {3, 2},
		colour_active = {3, 3},
		layer = 20,
	}


--[[
	mod.tiles["there"] = {
		name = "text_there",
		sprite = "text_there",
		sprite_in_root = false,
		unittype = "text",
		tiling = 2,
		type = 2,
		colour = {1, 2},
		colour_active = {1, 4},
		tile = {2, 25},
		layer = 20,
	}]]

	editor_objlist["text_there"] =
	{
		name = "text_there",
		sprite_in_root = false,
		unittype = "text",
		tags = {"text","text_adjective"},
		tiling = 2,
		type = 2,
		layer = 20,
		colour = {1, 2},
		colour_active = {1, 4},
	}

formatobjlist()

--Imported from Warps. Has no features like Portal or Wrap, so this is significantly shorter.
	function getadjacenttile(unitid,x,y,dir,warps)
		local ndrs = ndirs[dir + 1]

		local rx, ry, rdir = x + ndrs[1], y + ndrs[2], dir

		return rx, ry, dir, {}
	end

	local oldmoveblock = moveblock
	function moveblock(onlystartblock_)
		oldmoveblock()
		local osb = onlystartblock_ or false
		if osb == false then
			applyHeresAndTheres()
			doupdate()
		end
	end

function testcond(conds,unitid,x_,y_,autofail_,limit_,checkedconds_,ignorebroken_,subgroup_)
	local result = true

	local orhandling = false
	local orresult = false

	local x,y,name,dir,broken = 0,0,"",4,0
	local surrounds = {}
	local autofail = autofail_ or {}
	local limit = limit_ or 0

	limit = limit + 1
	if (limit > 80) then
		HACK_INFINITY = 200
		destroylevel("infinity")
		return
	end

	local checkedconds = {}
	local ignorebroken = ignorebroken_ or false
	local subgroup = subgroup_ or {}

	if (checkedconds_ ~= nil) then
		for i,v in pairs(checkedconds_) do
			checkedconds[i] = v
		end
	end

	if (#features == 0) then
		return false
	end

	-- 0 = bug, 1 = level, 2 = empty

	if (unitid ~= 0) and (unitid ~= 1) and (unitid ~= 2) and (unitid ~= nil) then
		local unit = mmf.newObject(unitid)
		x = unit.values[XPOS]
		y = unit.values[YPOS]
		name = unit.strings[UNITNAME]
		dir = unit.values[DIR]
		broken = unit.broken or 0

		if (unit.strings[UNITTYPE] == "text") then
			name = "text"
		end
	elseif (unitid == 2) then
		x = x_
		y = y_
		name = "empty"
		broken = 0

		if (featureindex["broken"] ~= nil) and (ignorebroken == false) and (checkedconds[tostring(conds)] == nil) then
			checkedconds[tostring(conds)] = 1
			broken = isitbroken("empty",2,x,y,checkedconds)
		end
	elseif (unitid == 1) then
		name = "level"
		surrounds = parsesurrounds()
		dir = tonumber(surrounds.dir) or 4
		broken = 0

		if (featureindex["broken"] ~= nil) and (ignorebroken == false) and (checkedconds[tostring(conds)] == nil) then
			checkedconds[tostring(conds)] = 1
			broken = isitbroken("level",1,x,y,checkedconds)
		end
	end

	checkedconds[tostring(conds)] = 1
	checkedconds[tostring(conds) .. "_s_"] = 1

	if (unitid == 0) or (unitid == nil) then
		print("WARNING!! Unitid is " .. tostring(unitid))
	end

	if ignorebroken then
		broken = 0
	end

	if (broken == 1) then
		result = false
	end

	if (conds ~= nil) and ((broken == nil) or (broken == 0)) then
		if (#conds > 0) then
			local valid = false

			for i,cond in ipairs(conds) do
				local condtype = cond[1]
				local params_ = cond[2]
				--wordid handling 1
				local wordids = cond[3] or {}

				local params = {}

				local extras = {}

				if (string.sub(condtype, 1, 1) == "(") then
					condtype = string.sub(condtype, 2)
					orhandling = true
					orresult = false
				end

				if (string.sub(condtype, -1) == ")") then
					condtype = string.sub(condtype, 1, string.len(condtype) - 1)
				end

				local basecondtype = string.sub(condtype, 1, 4)
				local notcond = false

				if (basecondtype == "not ") then
					basecondtype = string.sub(condtype, 5)
					notcond = true
				else
					basecondtype = condtype
				end

				if (condtype ~= "never") then
					local condname = unitreference["text_" .. basecondtype]

					local conddata = conditions[condname] or {}
					if (conddata.argextra ~= nil) then
						extras = conddata.argextra
					end
				end

				for a,b in ipairs(autofail) do
					if (condtype == b) then
						result = false
						valid = true
					end
				end

				if (result == false) and valid then
					break
				end

				if (params_ ~= nil) then
					local handlegroup = false

					for a,b in ipairs(params_) do
						if (string.sub(b, 1, 4) == "not ") then
							table.insert(params, b)
						else
							table.insert(params, 1, b)
						end

						if (string.sub(b, 1, 5) == "group") or (string.sub(b, 1, 9) == "not group") then
							handlegroup = true
						end
					end

					local removegroup = {}
					local removegroupoffset = 0

					if handlegroup then
						local plimit = #params

						for a=1,plimit do
							local b = params[a]
							local mem = subgroup_
							local notnoun = false

							if (string.sub(b, 1, 5) == "group") then
								if (mem == nil) then
									mem = findgroup(b,false,limit,checkedconds)
								end
								table.insert(removegroup, a)
							elseif (string.sub(b, 1, 9) == "not group") then
								notnoun = true

								if (mem == nil) then
									mem = findgroup(string.sub(b, 5),true,limit,checkedconds)
								else
									local memfound = {}

									for c,d in ipairs(mem) do
										memfound[d] = 1
									end

									mem = {}

									for c,mat in pairs(objectlist) do
										if (memfound[c] == nil) and (findnoun(c,nlist.short) == false) then
											table.insert(mem, c)
										end
									end
								end
								table.insert(removegroup, a)
							end

							if (mem ~= nil) then
								for c,d in ipairs(mem) do
									if notnoun then
										table.insert(params, d)
									else
										table.insert(params, 1, d)
										removegroupoffset = removegroupoffset - 1
									end
								end
							end

							if (mem == nil) or (#mem == 0) then
								table.insert(params, "_NONE_")
								break
							end
						end

						for a,b in ipairs(removegroup) do
							table.remove(params, b - removegroupoffset)
							removegroupoffset = removegroupoffset + 1
						end
					end
				end

				local condsubtype = ""

				if (string.sub(basecondtype, 1, 7) == "powered") then
					for a,b in pairs(condlist) do
						if (#basecondtype > #a) and (string.sub(basecondtype, 1, #a) == a) then
							condsubtype = string.sub(basecondtype, #a + 1)
							basecondtype = string.sub(basecondtype, 1, #a)
							break
						end
					end
				end

				if (condlist[basecondtype] ~= nil) then
					valid = true

					local cfunc = condlist[basecondtype]
					local subresult = true
					local ccc = false
					--Add wordids to the cdata list, specifically for THOSE
					local cdata = {name = name, x = x, y = y, unitid = unitid, dir = dir, extras = extras, limit = limit, conds = conds, subtype = condsubtype, i = i, surrounds = surrounds, notcond = notcond, debugname = cond[1],wordids = wordids}
					subresult,checkedconds,ccc = cfunc(params,checkedconds,checkedconds_,cdata)
					local clearcconds = ccc or false

					if notcond then
						subresult = not subresult
					end

					if subresult and clearcconds then
						checkedconds = {}

						if (checkedconds_ ~= nil) then
							for i,v in pairs(checkedconds_) do
								checkedconds[i] = v
							end
						end

						checkedconds[tostring(conds)] = 1
						checkedconds[tostring(conds) .. "_s_"] = 1
					end

					if (subresult == false) then
						if (orhandling == false) then
							result = false
							break
						end
					elseif orhandling then
						orresult = true
					end
				else
					MF_alert("condtype " .. tostring(condtype) .. " doesn't exist?")
					result = false
					break
				end

				if (string.sub(cond[1], -1) == ")") then
					orhandling = false

					if (orresult == false) then
						result = false
						break
					else
						result = true
					end
				end
			end

			if (valid == false) then
				MF_alert("invalid condition!")
				result = true

				for a,b in ipairs(conds) do
					MF_alert(tostring(b[1]))
				end
			end
		end
	end

	return result
end

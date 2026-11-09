if not Engine.IsPC() then
	return
end

local preload = PCOptionsUtils.PreLoad
local fov_label = Engine.Localize( "@PLATFORM_FOV" )

local function replace_fov_row( menu )
	local rows = LUI.FlowManager.GetScopedData( menu ).gridData
	for index, row in ipairs( rows ) do
		if row.buttonType == "GenericButtonScrollable" and row.buttonText == fov_label then
			local function get_bounds()
				local values = Engine.GetFovList()
				return tonumber( values[1] ), tonumber( values[#values] )
			end

			local min, max = get_bounds()
			if not min or not max or min >= max then
				print( "[wwz-mod] Could not read FOV slider limits" )
				return
			end

			local function set_fov( value )
				value = math.min( max, math.max( min, math.floor( value + 0.5 ) ) )
				PCOptionsUtils.SetDvarValue( "cg_fov", value )
				-- Use the accepted value for the second local client, as the stock option does.
				local applied = Engine.GetDvarFloat( "cg_fov" )
				PCOptionsUtils.SetDvarValue( "cg_fov1", applied )
				if applied ~= value or Engine.GetDvarFloat( "cg_fov1" ) ~= applied then
					print( "[wwz-mod] FOV settings did not accept " .. value )
				end
			end

			rows[index] = {
				buttonType = "GenericButtonSliderWithInfo",
				buttonText = row.buttonText,
				buttonDesc = row.buttonDesc,
				buttonOverFunc = row.buttonOverFunc,
				buttonOverDisableFunc = row.buttonOverDisableFunc,
				buttonDisplayFunc = function ()
					local percent = (Engine.GetDvarFloat( "cg_fov" ) - min) / (max - min)
					return math.min( 1, math.max( 0, percent ) )
				end,
				buttonLeftFunc = function ()
					set_fov( Engine.GetDvarFloat( "cg_fov" ) - 1 )
				end,
				buttonRightFunc = function ()
					set_fov( Engine.GetDvarFloat( "cg_fov" ) + 1 )
				end,
				infoDisplayFunc = function ()
					return string.format( "%.0f", Engine.GetDvarFloat( "cg_fov" ) )
				end,
				directSetFunc = function ( button, event )
					local value = tonumber( event.text )
					if value then
						set_fov( value )
					else
						print( "[wwz-mod] Ignored invalid FOV input" )
					end
					button:processEvent( { name = "content_refresh" } )
				end
			}
			-- The stock slider refreshes its display but does not bind row handlers.
			menu:addEventHandler( "refresh_values", function ()
				local new_min, new_max = get_bounds()
				if new_min and new_max and new_min < new_max then
					min, max = new_min, new_max
				end
				menu:processEvent( { name = "content_refresh", dispatchChildren = true } )
			end )
			print( string.format( "[wwz-mod] FOV slider ready (%d-%d)", min, max ) )
			return
		end
	end
	print( "[wwz-mod] Could not find the FOV settings row" )
end

PCOptionsUtils.PreLoad = function ( menu, properties )
	preload( menu, properties )
	if menu.id == "pc_graphics_advanced_options" then
		replace_fov_row( menu )
	end
end

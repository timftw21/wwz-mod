if not Engine.IsPC() or not Engine.IsZombiesMode() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_nav = builders.masterNavigationBar

local function size_bumper( tab, right )
	local arrow = tab.arrow
	local label = arrow:getNextSibling()
	local width = LUI.NavArrows.ArrowWidth
	local anchor = right and 1 or 0
	local center = (right and -width or width) / 2
	local binding = right and ButtonMap.button_shoulderr or ButtonMap.button_shoulderl

	-- The stock hover animation also restores the original bounds. Keep its color
	-- and opacity here so changes in input mode own the geometry.
	arrow:registerAnimationState( "visible", { alpha = 1, color = Colors.white } )
	label:registerAnimationState( "default", { color = Colors.white } )
	label:setFont( FONTS.BodyFont.Font )
	label:setScale( 0, 0 )

	local function update_size()
		if CoD.UsingController( arrow.exclusiveController ) then
			arrow:setAnchorsAndPosition( anchor, 1 - anchor, 1, 1, center - width / 2,
				center + width / 2, 0, 0, 0 )
			return
		end

		-- Use the footer's font, padding and nine-slice dimensions for the keyboard keycap.
		local splitscreen = GameX.IsHorizontalSplitscreen()
		local font_size = splitscreen and 18 or 21
		local key = Engine.Localize( binding.keyboard_string )
		local left, _, right_edge = GetTextDimensions( key, FONTS.BodyFont.Font,
			LUI.FontIconSet.Frontend, splitscreen and font_size or font_size * _1080p )
		local padding = splitscreen and right_edge > 11 and 6 or 12
		local half_width = (right_edge - left + padding) / 2
		local half_height = 13.5 * _1080p
		arrow:setAnchorsAndPosition( anchor, 1 - anchor, 0.5, 0.5, center - half_width,
			center + half_width, -half_height, half_height, 0 )
		arrow:setScale( 0, 0 )
		arrow:setup9SliceImage( 8, 8, 0.47, 0.47 )
		label:setFontSize( font_size, 0 )
		-- Middle alignment centers the font's line box. Lower the glyph to center its ink.
		local baseline = 2 * _1080p
		label:setAnchorsAndPosition( anchor, 1 - anchor, 0.5, 0.5, center - half_width,
			center + half_width, baseline - half_height, baseline + half_height, 0 )
	end

	for _, event_name in ipairs( { "button_config_updated", "exclusive_controller_updated" } ) do
		local stock_update = arrow.m_eventHandlers[event_name]
		arrow:registerEventHandler( event_name, function ( element, event )
			local handled = stock_update( element, event )
			update_size()
			return handled
		end )
	end

	update_size()
end

builders.masterNavigationBar = function ( menu, properties )
	local nav = build_nav( menu, properties )
	local buttons = nav.NavigationButtons
	if buttons then
		size_bumper( buttons.tabLeft, false )
		size_bumper( buttons.tabRight, true )
	else
		print( "[wwz-mod] Could not find the Zombies navigation prompts" )
	end
	return nav
end

print( "[wwz-mod] Zombies navigation keycaps use the footer prompt size" )

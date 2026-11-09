if game:issingleplayer() or not Engine.InFrontend() or not Engine.IsZombiesMode() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_sidebar = builders.sidebar_modal
local build_option = builders.GenericOptionsButton

builders.GenericOptionsButton = function( menu, properties )
	local button = build_option( menu, properties )
	local refresh_content = button.RefreshContent
	button.RefreshContent = function( self, controller, data )
		refresh_content( self, controller, data )
		local scoped = LUI.FlowManager.GetScopedData( self )
		local modal = scoped and scoped.sideBarModal and scoped.sideBarModal.menu
		if not modal or modal._choices ~= Cao.ZMCharacterPreferences or not data.defaultChecked then
			return
		end
		-- The stock grid marks the saved choice as defaultChecked, but its normal
		-- button does not draw that state. Attach the native equipped icon to the
		-- refreshed content so recycling a row also removes its old marker.
		local icon = LUI.UIImage.new()
		icon.id = "EquippedCharacterIcon"
		icon:setImage( RegisterMaterial( "menugrid_equip" ), 0 )
		icon:setAnchorsAndPosition( 1, 0, 0.5, 0.5, -29.5 * _1080p, -10.5 * _1080p,
			-9 * _1080p, 9 * _1080p )
		icon:setRGBFromInt( SWATCHES.Button.MenuOffWhite, 0 )
		icon:setZRotation( 90, 0 )
		self.GenericButton:addElement( icon )
	end
	return button
end

builders.sidebar_modal = function( menu, properties )
	if not properties or properties.choices ~= Cao.ZMCharacterPreferences then
		return build_sidebar( menu, properties )
	end

	-- The 800px viewport fits twelve 62px rows with 3px gaps, not fourteen.
	-- The stock builder supplies its own four-row layout for horizontal splitscreen.
	if not GameX.IsHorizontalSplitscreen() then
		properties.OptionsGrid_maxVisibleRows = math.min( properties.OptionsGrid_maxVisibleRows or 14, 12 )
	end

	local modal = build_sidebar( menu, properties )
	local grid = modal.OptionsGrid.OptionsGrid
	local footer = modal.ButtonHelperBar
	local counter = modal.GridPositionIndicator0
	if not counter then
		counter = LUI.UIGridPositionIndicator.new( {
			controllerIndex = modal._controllerIndex,
			fontIconSet = properties.fontIconSet,
			hasCarots = true
		} )
		counter.id = "CharacterPositionIndicator"
		modal.CharacterPositionIndicator = counter
		grid:SetPositionIndicator( counter )
	else
		modal:removeElement( counter )
	end
	-- Both footer items inherit the stock opening and closing animations.
	footer:addElement( counter )
	-- Match the stock prompt row; its key outline and hover box use the bottom baseline.
	counter:setAnchorsAndPosition( 0, 1, 0, 0, 100 * _1080p, 500 * _1080p,
		10 * _1080p, -5 * _1080p )
	-- Use the Advanced Settings counter's native font, size and both arrows.
	counter:setFont( FONTS.BodyBoldFont.Font )
	counter:setFontSize( 20, 0 )
	counter:setRGBFromInt( SWATCHES.Button.MenuOffWhite, 0 )
	counter:setHorizontalAlignment( LUI.HorizontalAlignment.Left )
	counter:setVerticalAlignment( LUI.VerticalAlignment.Bottom )

	local right_buttons = footer.RightSideButtons
	right_buttons:setRight( -40 * _1080p, 0 )
	-- The 940px footer needs a 40px inset to meet the boxes' 900px right edge.
	-- Update the button-refresh animation too so it retains that inset.
	right_buttons.sequences.NewButtonsSlideIn[1] = {
		function () return right_buttons:setRight( -70 * _1080p, 0 ) end,
		function () return right_buttons:setRight( -40 * _1080p, 250, LUI.EASING.inQuadratic ) end
	}

	-- "No Preference" is the first choice, not a character (displayed as 0/N).
	counter:setShouldIgnoreFirstCell( true )
	local last_row
	local function update_counter( row )
		counter:updateText( row + 1, #modal._choices )
		counter:updateCarots( grid )
		if row ~= last_row then
			last_row = row
			print( string.format( "[wwz-mod] character_select: controller=%d character=%d/%d",
				modal._controllerIndex, row, #modal._choices - 1 ) )
		end
	end

	-- A grid can temporarily lose focus; the stock callback assumes a valid row.
	grid.UpdateNumbers = function( self )
		local row = self:GetFocusPosition( LUI.DIRECTION.vertical )
		if row ~= nil then
			update_counter( row )
		end
	end
	update_counter( properties.defaultIndex )
	grid:UpdateNumbers()
	print( string.format( "[wwz-mod] character_select: visible_rows=%d equipped_choice=%d native_counter_arrows=true equipped_marker=true animated_footer=true back_right=900 prompt_baseline=stock_bottom",
		properties.OptionsGrid_maxVisibleRows, properties.defaultIndex ) )
	return modal
end

print( "[wwz-mod] Zombies character-select layout, Advanced Settings counter and equipped marker installed" )

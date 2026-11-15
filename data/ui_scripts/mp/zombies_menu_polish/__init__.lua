if not Engine.IsZombiesMode() or not Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build

-- Find Match starts PublicMatch/PublicMatchAlt; public and custom lobbies
-- start ReadyUp/ShatteredLobby. Return the stock "no tutorial" result so
-- callers give focus to the menu instead of waiting for a tutorial to finish.
local match_tutorials = {
	PublicMatch = true,
	PublicMatchAlt = true,
	ReadyUp = true,
	ShatteredLobby = true
}
local attempt_tutorial = ZombiesOnboarding and ZombiesOnboarding.AttemptFirstTouchPopup
if type( attempt_tutorial ) == "function" then
	ZombiesOnboarding.AttemptFirstTouchPopup = function ( controller, tutorial )
		if match_tutorials[tutorial] then
			return false
		end
		return attempt_tutorial( controller, tutorial )
	end
	print( "[wwz-mod] Disabled Zombies public/custom match selection and lobby tutorials" )
else
	print( "[wwz-mod] Could not disable match tutorials: Zombies onboarding function missing" )
end

local build_soldier = builders.zm_soldier_menu
if build_soldier then
	builders.zm_soldier_menu = function ( menu, properties )
		local soldier = build_soldier( menu, properties )
		local message = soldier.LockedMessage
		local message_button
		message:setAlpha( 0, 0 )

		local function style_locked( button, focused, duration )
			-- Match the lock and title in the Weapon Build Kits weapon list.
			local offset = focused and 20 or 0
			local alpha = focused and 0.5 or 0.3
			local easing = LUI.EASING.outSine
			local icon = button.Icon
			icon:setAnchorsAndPosition( 0, 1, 0.5, 0.5, (20 + offset) * _1080p, (44 + offset) * _1080p,
				-11 * _1080p, 13 * _1080p, duration, easing )
			icon:setRGBFromInt( focused and SWATCHES.Menus.MenuGold or SWATCHES.Button.MenuOffWhite, 0 )
			icon:setAlpha( alpha, 0 )
			button.Name:setLeft( (54 + offset) * _1080p, duration, easing )
			button.Name:setFontSize( focused and 26 or 24, 0 )
			button.Name:setAlpha( alpha, 0 )

			if focused then
				local _, top, _, bottom = button:getLocalRect()
				message:setTopBottom( true, false, top, bottom, 0 )
				message:setAlpha( 1, 0 )
				message_button = button
			elseif message_button == button then
				message:setAlpha( 0, 0 )
				message_button = nil
			end
		end

		local styled = false
		for _, id in ipairs( { "LoadoutButton", "ModsButton", "ConsumablesMenu" } ) do
			local button = soldier[id]
			if button and button.disabled then
				button.Icon:setImage( RegisterMaterial( "unlock_level" ), 0 )
				button.Name:setRGBFromInt( SWATCHES.Button.MenuWhite, 0 )
				button.actionSFX = CoD.SFX.Error

				-- The stock breadcrumb follows the title's unlocked position.
				local breadcrumb = button.BreadCrumbIcon
				local breadcrumb_anchor = LUI.UIElement.new()
				breadcrumb_anchor:setAnchorsAndPosition( 0, 0, 0, 0, 34 * _1080p, 34 * _1080p, 0, 0, 0 )
				button:removeElement( breadcrumb )
				button:addElement( breadcrumb_anchor )
				breadcrumb_anchor:addElement( breadcrumb )

				button._sequences.Focused = function ()
					style_locked( button, true, 281 )
				end
				button._sequences.Unfocused = function ()
					style_locked( button, false, 0 )
				end
				style_locked( button, button:isInFocus(), 0 )
				styled = true
			end
		end
		if styled then
			print( "[wwz-mod] Applied the Weapon Build Kits lock style to the Soldier tab" )
		end
		return soldier
	end
else
	print( "[wwz-mod] Could not find the Zombies Soldier menu builder" )
end

local function text_height( label, icon_set )
	local left, _, right = label:getLocalRect()
	local _, top, _, bottom = GetTextDimensions( label:getText() or "", label:getCurrentFont(),
		icon_set, label:getFontSize(), (right - left) / _1080p, label:getTrackingSize() )
	return math.abs( top - bottom ) * _1080p
end

local build_maps = builders.zm_select_map
local trimmed_descriptions = {}
if build_maps then
	builders.zm_select_map = function ( menu, properties )
		local maps = build_maps( menu, properties )
		local label, description = maps.UnlockMessage, maps.Description
		local icon_set = properties and properties.fontIconSet or LUI.FontIconSet.Frontend
		local left, top, right, bottom = label:getLocalRect()
		local survival_message = Engine.Localize( "ZOMBIES_MENU_SURVIVAL_MAP_UNLOCKED" )
		local survival = false
		local skull = LUI.UIImage.new()
		skull.id = "SurvivalMapIcon"
		skull:setImage( RegisterMaterial( "headicon_dead" ), 0 )
		skull:setRGBFromInt( SWATCHES.HUD.hudCream, 0 )
		maps:addElement( skull )

		local function layout()
			skull:setAlpha( survival and 1 or 0, 0 )
			if survival then
				local x, y = description:getLocalRect()
				-- Measure the new text directly; the element's own text dimensions lag behind
				-- setText and still describe the previously focused map.
				y = y + text_height( description, icon_set ) + 4 * _1080p
				-- The skull material has transparent margins around its artwork.
				skull:setAnchorsAndPosition( 0, 1, 0, 1, x - 12 * _1080p, x + 36 * _1080p,
					y - 8 * _1080p, y + 40 * _1080p, 0 )
				label:setAnchorsAndPosition( 0, 1, 0, 1, x + 36 * _1080p, right,
					y, y + 32 * _1080p, 0 )
			else
				label:setAnchorsAndPosition( 0, 1, 0, 1, left, right, top, bottom, 0 )
			end
		end

		local set_label = label.setText
		label.setText = function ( self, text, ... )
			survival = text == survival_message
			local result = set_label( self, survival and "Survival map" or text, ... )
			layout()
			return result
		end
		local set_description = description.setText
		description.setText = function ( self, text, ... )
			-- Altar of Blood's localized description ends in blank lines that inflate its height.
			-- They are not Lua whitespace (the trim never matched), so also strip the literal
			-- "\n" escapes the text renderer expands.
			if type( text ) == "string" then
				local trimmed = text
				repeat
					local previous = trimmed
					trimmed = trimmed:gsub( "%s+$", "" ):gsub( "\\[nrt]$", "" ):gsub( "\194\160$", "" )
				until trimmed == previous
				if trimmed ~= text then
					if not trimmed_descriptions[trimmed] then
						trimmed_descriptions[trimmed] = true
						print( "[wwz-mod] Trimmed trailing blank lines from the Zombies map description" )
					end
					text = trimmed
				end
			end
			local result = set_description( self, text, ... )
			layout()
			return result
		end
		description:setText( description:getText() or "", 0 )
		label:setText( label:getText(), 0 )
		print( "[wwz-mod] Enlarged the Survival map skull and aligned the label to the wrapped description" )
		return maps
	end
else
	print( "[wwz-mod] Could not find the Zombies map selection builder" )
end

local build_challenges = builders.zm_hiddenChallenges
if build_challenges then
	builders.zm_hiddenChallenges = function ( menu, properties )
		local challenges = build_challenges( menu, properties )
		-- The stock grid clips 500-pixel buttons to a 418-pixel viewport.
		challenges.Categories:setRight( 590 * _1080p, 0 )
		print( "[wwz-mod] Matched the hidden-challenge viewport to its full button width" )
		return challenges
	end
else
	print( "[wwz-mod] Could not find the hidden-challenge menu builder" )
end

local build_details = builders.cac_details_pane
if build_details then
	builders.cac_details_pane = function ( menu, properties )
		local pane = build_details( menu, properties )
		local paragraph, historical = pane.Paragraph, pane.Historical
		local equipment = false
		local icon_set = properties and properties.fontIconSet or LUI.FontIconSet.Frontend
		local function layout()
			if equipment then
				local _, top = paragraph:getLocalRect()
				-- Long equipment descriptions must leave a gap before the blast-radius text.
				local y = math.max( 136.5 * _1080p, top + text_height( paragraph, icon_set ) + 16 * _1080p )
				historical:setTop( y, 0 )
				historical:setBottom( y + 30 * _1080p, 0 )
			end
		end
		for name, sequence in pairs( pane._sequences ) do
			pane._sequences[name] = function ( ... )
				equipment = name == "EquipmentScene"
				local result = sequence( ... )
				layout()
				return result
			end
		end
		for _, method in ipairs( { "setText", "setFontSize" } ) do
			local original = paragraph[method]
			paragraph[method] = function ( self, ... )
				local result = original( self, ... )
				layout()
				return result
			end
		end
		print( "[wwz-mod] Added adaptive spacing between equipment descriptions and blast-radius text" )
		return pane
	end
else
	print( "[wwz-mod] Could not find the equipment details builder" )
end

local build_recordings = builders.zm_audio_logs_menu
if build_recordings then
	builders.zm_audio_logs_menu = function ( menu, properties )
		local recordings = build_recordings( menu, properties )
		local bar = recordings.ButtonHelperBar
		local back = bar:GetEntryForButton( LuaButton.secondary )
		if back and back.callback then
			bar:BeginSet():AddLeft( LuaButton.primary, "LUA_MENU_SELECT" ):AddBackButton( nil, back.callback ):Finish()
			print( "[wwz-mod] Moved the Recordings Back prompt to the standard position" )
		else
			print( "[wwz-mod] Could not find the Recordings Back action" )
		end
		return recordings
	end
else
	print( "[wwz-mod] Could not find the Recordings menu builder" )
end

local hidden_status, status_alpha
local function restore_lobby_status()
	if hidden_status then
		hidden_status:setAlpha( status_alpha, 0 )
		hidden_status, status_alpha = nil, nil
		print( "[wwz-mod] Restored lobby status after Recordings video playback" )
	end
end

local function hide_lobby_status()
	local foreground = Engine.GetLuiRoot().persistentForeground
	local status = foreground and foreground.NextMatchWidget
	if not status then
		print( "[wwz-mod] No lobby status widget found during Recordings video playback" )
		return
	end
	if hidden_status ~= status then
		restore_lobby_status()
		hidden_status, status_alpha = status, status:getAlpha()
	end
	if not status.wwzRecordingHandler then
		-- The persistent widget also receives cleanup when Recordings is popped mid-video.
		status:registerDvarHandler( "snd_playing_log", function ()
			if hidden_status == status and Engine.GetDvarInt( "snd_playing_log" ) == 0 then
				restore_lobby_status()
			end
		end )
		status.wwzRecordingHandler = true
	end
	status:setAlpha( 0, 0 )
	print( "[wwz-mod] Hid lobby status during Recordings video playback" )
end

local build_video = builders.zm_video_log
if build_video then
	builders.zm_video_log = function ( menu, properties )
		local video = build_video( menu, properties )
		for name, callback in pairs( {
			CinematicFullscreen = hide_lobby_status,
			CinematicReset = restore_lobby_status
		} ) do
			local sequence = video._sequences[name]
			video._sequences[name] = function ( ... )
				local result = sequence( ... )
				callback()
				return result
			end
		end
		return video
	end
else
	print( "[wwz-mod] Could not find the Recordings video builder" )
end

local build_consumable_preview = builders.zm_consumables_menu_preview
if build_consumable_preview then
	builders.zm_consumables_menu_preview = function ( menu, properties )
		local preview = build_consumable_preview( menu, properties )
		local charges = preview.Charges
		if not charges then
			print( "[wwz-mod] Could not find the Consumables charge label" )
			return preview
		end
		local set_text = charges.setText
		charges.setText = function ( element, text, ... )
			-- The stock picker pairs every charge count with the singular label.
			local count, label
			if type( text ) == "string" then
				count, label = text:match( "^(%d+) (.+)$" )
			end
			if count and count ~= "1" and label == Engine.Localize( "ZOMBIES_CONSUMABLE_CHARGE" ) then
				text = count .. " " .. Engine.Localize( "ZOMBIES_CONSUMABLE_CHARGE_PLURAL" )
				if not preview.wwzLoggedCharges then
					preview.wwzLoggedCharges = true
					print( "[wwz-mod] Pluralized the Consumables charge count" )
				end
			end
			return set_text( element, text, ... )
		end
		return preview
	end
else
	print( "[wwz-mod] Could not find the Consumables preview builder" )
end

-- The Self-Revive panel's slide sequences use slightly different sizes and heights in each
-- direction, so its multi-line description rewrapped and jumped. Slide it at its resting size.
local build_consumables = builders.zm_consumables_menu
if build_consumables then
	local self_revive_rects = {
		SelfReviveIconBackground = { 187, 315, 553, 683 },
		SelfReviveIcon = { 187, 315, 553, 683 },
		SelfReviveName = { 327, 677, 533, 581.5 },
		SelfReviveDesc = { 327, 832.03, 581, 611 }
	}
	local slide = 705
	builders.zm_consumables_menu = function ( menu, properties )
		local consumables = build_consumables( menu, properties )
		local fixed = 0
		for name, rect in pairs( self_revive_rects ) do
			local element = consumables[name]
			if element and element.RegisterAnimationSequence then
				local left, right, top, bottom = rect[1] * _1080p, rect[2] * _1080p, rect[3] * _1080p, rect[4] * _1080p
				local offset = slide * _1080p
				local function place( shift, duration, easing )
					-- Match the stock calls exactly: the native setter rejects an explicit nil easing.
					if easing then
						return element:setAnchorsAndPosition( 0, 1, 0, 1, left + shift, right + shift, top, bottom, duration, easing )
					end
					return element:setAnchorsAndPosition( 0, 1, 0, 1, left + shift, right + shift, top, bottom, duration )
				end
				element:RegisterAnimationSequence( "SlideLeft", {
					{ function () return element:setAlpha( 0, 281 ) end },
					{
						function () return place( 0, 0 ) end,
						function () return place( -offset, 281, LUI.EASING.outSine ) end
					}
				} )
				element:RegisterAnimationSequence( "SlideRight", {
					{ function () return element:setAlpha( 1, 0 ) end },
					{
						function () return place( -offset, 0 ) end,
						function () return place( 0, 281, LUI.EASING.outSine ) end
					}
				} )
				fixed = fixed + 1
			end
		end
		print( "[wwz-mod] Kept " .. fixed .. " Self-Revive panel elements at their resting size while sliding" )
		return consumables
	end
else
	print( "[wwz-mod] Could not find the Consumables menu builder" )
end

-- The Tortured Path vignette is only added when a lobby background variant is built,
-- so selecting the mode kept the previous background until another tab rebuilt it.
local set_background = PersistentBackground and PersistentBackground.Set
local lobby_backgrounds = {}
for _, name in ipairs( { "HubLobby", "ZombieVendor", "ZombiesVLobby" } ) do
	local variant = set_background and PersistentBackground.Variants[name]
	if variant then
		lobby_backgrounds[variant] = true
	end
end
if set_background and next( lobby_backgrounds ) then
	local built_shattered

	local function shattered()
		return CONDITIONS.IsZombiesShatteredModeLobby() == true
	end

	local function stale( variant )
		return lobby_backgrounds[variant] and built_shattered ~= shattered()
	end

	local function refresh_background()
		local variant = PersistentBackground.current
		if variant and stale( variant ) then
			PersistentBackground.Set( variant, true )
			print( "[wwz-mod] Rebuilt the lobby background after the Zombies mode changed" )
		end
	end

	local function watch_mode()
		local container = Engine.GetLuiRoot().persistentBackground
		local lobby = DataSources.inFrontend.MP.lobby
		if not container or container.wwzModeWatcher or not lobby then
			return
		end
		local watcher = LUI.UIElement.new()
		watcher.id = "wwzModeWatcher"
		container:addElement( watcher )
		container.wwzModeWatcher = watcher
		watcher:registerEventHandler( "wwz_refresh_lobby_background", refresh_background )
		local controller = Engine.GetFirstActiveController()
		for _, source in ipairs( { lobby.mapRef, lobby.gameTypeRef } ) do
			watcher:SubscribeToModel( source:GetModel( controller ), function ()
				refresh_background()
				-- Check once more after the party settles the new map and game type.
				watcher:addElement( LUI.UITimer.new( 250, "wwz_refresh_lobby_background", nil, true ) )
			end )
		end
		print( "[wwz-mod] Watching the lobby map and mode for the Tortured Path background" )
	end

	PersistentBackground.Set = function ( variant, force, ... )
		if variant and variant == PersistentBackground.current and not force and stale( variant ) then
			force = true
			print( "[wwz-mod] Rebuilt the lobby background for the current Zombies mode" )
		end
		local rebuilt = variant ~= PersistentBackground.current or force
		local result = set_background( variant, force, ... )
		if rebuilt then
			built_shattered = shattered()
		end
		watch_mode()
		return result
	end
else
	print( "[wwz-mod] Could not hook the Zombies lobby background" )
end

-- Menus add Supply Drops ahead of their Back or Leave Match prompt on the right side of
-- the prompt bar; place it on the other side, as in the lobby.
local bar_builder = LUI.ButtonHelperBarBuilder
local finish_bar = bar_builder and bar_builder.Finish
if finish_bar then
	local supply_text = Engine.Localize( "LUA_MENU_SUPPLY_DROP_PLURAL" )
	local swapped = false
	bar_builder.Finish = function ( self, ... )
		local back, supply
		for _, entry in ipairs( self._buttons or {} ) do
			if entry.screenLocation == ButtonBarScreenLocations.Right then
				if entry.button == LuaButton.secondary then
					back = entry
				elseif entry.button == LuaButton.right_trigger and entry.text == supply_text then
					supply = entry
				end
			end
		end
		if back and supply and supply.priority <= back.priority then
			supply.priority = back.priority + 1
			if not swapped then
				swapped = true
				print( "[wwz-mod] Placed Supply Drops after the Back and Leave Match prompts" )
			end
		end
		return finish_bar( self, ... )
	end
else
	print( "[wwz-mod] Could not find the prompt bar builder" )
end

-- Scrolling tab bars show fewer tabs than they hold. Clip the hidden ones while they
-- slide, and keep the bar as wide as its widest run of visible tabs: the stock resize
-- fits the bar to the tabs currently shown, which moves the right bumper prompt.
local function tab_width( text, icon_set )
	-- Mirrors masterNavigationBarItem, which sizes every tab in its focused style.
	local left, _, right = GetTextDimensions( MODIFIERS.ToUpperCase( text ), FONTS.BodyBoldFont.Font,
		icon_set, Engine.AdjustFontSizeByLanguage( 21 ), nil, 1.4 )
	return math.max( (right - left) * _1080p + 12, TopNavBarUtils.ItemMinimumWidth )
end

local function widest_tab_run( bar, visible, spacing, icon_set )
	local source, controller = bar.BarElements:GetGridDataSource()
	local count = source and source.GetCountValue and tonumber( source:GetCountValue( controller ) ) or 0
	if count <= visible then
		return nil
	end
	local widths = {}
	for index = 0, count - 1 do
		local item = source:GetDataSourceAtIndex( index, controller )
		if item.isIcon and item.isIcon:GetValue( controller ) then
			widths[index + 1] = TopNavBarUtils.ItemIconStateDefaultWidth
		else
			local name = item.name and item.name:GetValue( controller )
			if type( name ) ~= "string" then
				return nil
			end
			widths[index + 1] = tab_width( name, icon_set )
		end
	end
	local widest = 0
	for first = 1, count - visible + 1 do
		local run = 0
		for index = first, first + visible - 1 do
			run = run + widths[index]
		end
		widest = math.max( widest, run )
	end
	local bumpers = math.abs( GLOBAL_CONSTANTS.MasterNavigationBarBumperSizeLeft ) +
		math.abs( GLOBAL_CONSTANTS.MasterNavigationBarBumperSizeRight )
	return widest + spacing * (visible - 1) + (TopNavBarUtils.Padding + bumpers) * _1080p
end

local build_navbar = builders.masterNavigationBar
if build_navbar then
	local clipped, pinned = false, false
	builders.masterNavigationBar = function ( menu, properties )
		local bar = build_navbar( menu, properties )
		local visible = properties and properties.BarElements_maxVisibleColumns
		if not visible or not bar.BarElements then
			return bar
		end
		bar.BarElements:setUseStencil( true )
		if not clipped then
			clipped = true
			print( "[wwz-mod] Clipped scrolling tab bars to their bounds" )
		end

		local spacing = properties.BarElements_spacingX or 32 * _1080p
		local icon_set = properties.fontIconSet or LUI.FontIconSet.Frontend
		local set_width = bar.setWidth
		local widest = 0
		bar.setWidth = function ( self, width, ... )
			local ok, run = pcall( widest_tab_run, self, visible, spacing, icon_set )
			if ok and run then
				-- Never shrink, in case a run measures wider in game than estimated.
				widest = math.max( widest, run, width )
				width = widest
				if not pinned then
					pinned = true
					print( "[wwz-mod] Pinned scrolling tab bars to their widest run of tabs" )
				end
			elseif not ok and not self.wwzMeasureFailed then
				self.wwzMeasureFailed = true
				print( "[wwz-mod] Could not measure a scrolling tab bar: " .. tostring( run ) )
			end
			return set_width( self, width, ... )
		end
		return bar
	end
else
	print( "[wwz-mod] Could not find the tab bar builder" )
end

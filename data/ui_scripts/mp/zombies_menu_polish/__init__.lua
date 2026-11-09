if not Engine.IsZombiesMode() or not Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build

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
if build_maps then
	builders.zm_select_map = function ( menu, properties )
		local maps = build_maps( menu, properties )
		local label, description = maps.UnlockMessage, maps.Description
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
				local _, wrapped_height = description:getElementTextDims( false, true, true )
				y = y + (wrapped_height + 4) * _1080p
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
			if type( text ) == "string" then
				local trimmed = text:gsub( "%s+$", "" )
				if trimmed ~= text then
					print( "[wwz-mod] Trimmed trailing whitespace from the Zombies map description" )
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

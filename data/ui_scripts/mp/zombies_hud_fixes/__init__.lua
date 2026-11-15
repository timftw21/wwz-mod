if not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build

local build_hints = builders.zm_HintsWidget
if build_hints then
	builders.zm_HintsWidget = function ( menu, properties )
		local hints = build_hints( menu, properties )
		-- Stock creates CGInvalidCmdHint first, followed by the scope zoom hint.
		local invalid_command = hints:getFirstChild()
		if invalid_command then
			-- The native renderer centers text on the ownerdraw rectangle's alignment
			-- point. Center both that rectangle and its horizontal alignment explicitly.
			local left, _, right = invalid_command:getLocalRect()
			local half_width = (right - left) / 2
			invalid_command:setAnchors( 0.5, 0.5, 0, 1, 0 )
			invalid_command:setLeft( -half_width, 0 )
			invalid_command:setRight( half_width, 0 )
			invalid_command:setHorizontalAlignment( LUI.HorizontalAlignment.Center )
			print( "[wwz-mod] Centered Zombies stance warnings, including Prone Blocked" )
		else
			print( "[wwz-mod] Could not find the Zombies stance warning ownerdraw" )
		end
		return hints
	end
else
	print( "[wwz-mod] Could not find the Zombies hints builder" )
end

local function align_ability_prompt( prompt )
	-- Both ammo warnings already use the screen midpoint. The ability prompt's stock bounds are 6 pixels left.
	local left, _, right = prompt:getLocalRect()
	local center = (left + right) / 2
	prompt:setLeft( left - center, 0 )
	prompt:setRight( right - center, 0 )

	-- The stock HUD entrance animation reapplies the same horizontal offset.
	local set_position = prompt.setAnchorsAndPosition
	prompt.setAnchorsAndPosition = function ( self, left_anchor, right_anchor, top_anchor, bottom_anchor, left, right, ... )
		if left_anchor == 0.5 and right_anchor == 0.5 then
			local center = (left + right) / 2
			left, right = left - center, right - center
		end
		return set_position( self, left_anchor, right_anchor, top_anchor, bottom_anchor, left, right, ... )
	end
	print( "[wwz-mod] Aligned the Zombies ability prompt with the ammo warnings" )
end

local function session_state()
	if not Engine.NetConstStrings_AreStringsLoaded() then
		return nil
	end
	return Game.GetOmnvar( "ui_session_state" )
end

local function add_spawn_cover( hud )
	-- Until the first spawn the player is a spectator. On maps without a loading cinematic, such as
	-- The Final Reich, those spectator frames show as the map appears; a spawn that waits for its
	-- weapons to stream lasts longer, and wwz_spawn_cover.gsc signals while it does. Late joiners
	-- who wait for the next round get no signal, so the cover times out to the stock spectator view.
	local cover = LUI.UIImage.new()
	cover.id = "wwz_spawn_cover"
	cover:setImage( RegisterMaterial( "white" ), 0 )
	cover:setRGB( 0, 0, 0 )
	cover:setAlpha( 0, 0 )
	-- Overscan past the 1920x1080 HUD so wider screens stay covered.
	cover:setAnchorsAndPosition( 0, 0, 0, 0, -1920 * _1080p, 1920 * _1080p, -1080 * _1080p, 1080 * _1080p, 0 )
	hud:addElement( cover )

	local spawned, shown, timer = false, false, nil
	local remaining, elapsed = 0, 0
	local function stop()
		if timer then
			timer:Stop()
			timer:close()
			timer = nil
		end
	end
	local function refresh()
		local state = session_state()
		spawned = spawned or state == "playing"
		-- The loading cinematic draws beneath the HUD, so never cover it.
		local want = not spawned and remaining > 0 and not Engine.IsLoadingVideoPlaying()
		if want ~= shown then
			shown = want
			cover:setAlpha( want and 1 or 0, want and 0 or 250 )
			print( (want and "[wwz-mod] Covered the spectator view before the first spawn at "
				or "[wwz-mod] Revealed the first spawn at ") .. elapsed .. " ms, state " .. tostring( state ) )
		end
		if spawned or remaining <= 0 then
			stop()
		end
	end
	local function watch( allowance )
		if spawned then
			return
		end
		remaining = math.max( remaining, allowance )
		if not timer then
			timer = LUI.UITimer.new( 50, { name = "wwz_spawn_cover_tick", dispatchChildren = false }, nil, false, false, false, false )
			timer.timerEventTarget = timer
			timer:registerEventHandler( "wwz_spawn_cover_tick", function ( element, tick )
				local step = tick.timeElapsed or 50
				-- The allowance starts once the loading cinematic, which hides the view anyway, ends.
				if not Engine.IsLoadingVideoPlaying() then
					remaining = remaining - step
				end
				elapsed = elapsed + step
				refresh()
			end )
			cover:addElement( timer )
		end
		refresh()
	end
	hud:addEventHandler( "wwz_first_spawn_pending", function ()
		watch( 700 )
	end )
	-- The HUD is built with the map, before the first spawn reaches this client.
	if session_state() ~= "playing" then
		watch( 3000 )
	end
end

local function hide_crosshair_with_scoreboard( hud, controller )
	-- cg_drawCrosshair (hashed 1874) is set by the match scripts and not saved; the player's
	-- crosshair option is ui_drawCrosshair, so this toggle leaves their setting alone.
	local open = DataSources.inGame.HUD.scoreboardOpen
	local hidden, logged = false, false
	hud:SubscribeToModel( open:GetModel( controller ), function ()
		local visible = open:GetValue( controller )
		if visible then
			-- Lets a reported spot (stray fog, an out-of-bounds drop) be found from the log.
			local ok, origin = pcall( Game.GetEntityOrigin, Game.GetPlayerClientnum() )
			if ok and type( origin ) == "table" and origin[1] then
				print( string.format( "[wwz-mod] Scoreboard opened at (%.0f, %.0f, %.0f)", origin[1], origin[2], origin[3] ) )
			end
		end
		if visible and not hidden and Engine.GetDvarBool( "1874" ) then
			hidden = true
			Engine.SetDvarBool( "1874", false )
			if not logged then
				logged = true
				print( "[wwz-mod] Hid the crosshair behind the Zombies scoreboard" )
			end
		elseif not visible and hidden then
			hidden = false
			Engine.SetDvarBool( "1874", true )
		end
	end )
end

local build_hud = builders.ZMHud
if build_hud then
	builders.ZMHud = function ( menu, properties )
		local hud = build_hud( menu, properties )
		add_spawn_cover( hud )
		hide_crosshair_with_scoreboard( hud, properties and properties.controllerIndex or hud:getRootController() )
		if hud.SpecialAbilityPrompt then
			align_ability_prompt( hud.SpecialAbilityPrompt )
		end
		local feed = hud.SubtitleWidget0 and hud.SubtitleWidget0.Feed0
		if feed then
			-- Reserve the strip between interaction prompts and the bottom HUD.
			feed:RegisterAnimationSequence( "DefaultSequence", { {
				function ()
					return feed:setAnchorsAndPosition( 0, 0, 1, 0, 340 * _1080p, -340 * _1080p,
						-314 * _1080p, -204 * _1080p, 0 )
				end
			} } )
			feed:AnimateSequence( "DefaultSequence" )
			print( "[wwz-mod] Moved Zombies subtitles clear of the bottom HUD" )
		else
			print( "[wwz-mod] Could not find the Zombies subtitle feed" )
		end
		return hud
	end
else
	print( "[wwz-mod] Could not find the Zombies HUD builder" )
end

local function names_akimbo( name )
	return type( name ) == "string" and name:lower():find( "akimbo", 1, true ) ~= nil
end

local build_weapon_info = builders.zm_WeaponInfoLayout
if build_weapon_info then
	builders.zm_WeaponInfoLayout = function ( menu, properties )
		local info = build_weapon_info( menu, properties )
		if properties and properties.isBuildChild then
			return info
		end
		local clip, separator = info.AmmoClipAkimbo, info.LineSeparatorAkimbo
		if not clip or not separator then
			print( "[wwz-mod] Could not find the Zombies akimbo ammo elements" )
			return info
		end
		local controller = properties and properties.controllerIndex or info:getRootController()
		local weapon = DataSources.inGame.HUD.currentWeapon
		local set_clip_alpha, set_separator_alpha = clip.setAlpha, separator.setAlpha
		local function refresh()
			-- Weapon names update before the dual-wield state finishes switching.
			local akimbo = names_akimbo( weapon.name:GetValue( controller ) )
				or names_akimbo( weapon.displayName:GetValue( controller ) )
				or (Game.IsWeaponDualWielding() and (Game.GetPlayerMaxClipAmmo( 2 ) or 0) > 0)
			local alpha = akimbo and not CONDITIONS.IsPlayerOnTurret() and 1 or 0
			set_clip_alpha( clip, alpha, 0 )
			set_separator_alpha( separator, alpha, 0 )
		end
		clip.setAlpha = refresh
		separator.setAlpha = refresh
		for _, source in ipairs( { weapon.name, weapon.displayName, weapon.isDualWielding, weapon.clipAmmoLeft } ) do
			info:SubscribeToModel( source:GetModel( controller ), refresh )
		end
		refresh()
		print( "[wwz-mod] Tied akimbo counter visibility to weapon identity and ammo state" )
		return info
	end
else
	print( "[wwz-mod] Could not find the Zombies weapon HUD builder" )
end

local build_player_info = builders.zm_PlayerInfo_Widget
if build_player_info then
	builders.zm_PlayerInfo_Widget = function ( menu, properties )
		local info = build_player_info( menu, properties )
		local ring = info.HealthRadial
		if not ring or not ring.SetTimerEulerAngle then
			print( "[wwz-mod] Could not find the Zombies portrait ring" )
			return info
		end
		local controller = properties and properties.controllerIndex or info:getRootController()
		local hud = DataSources.inGame.HUD
		local match = hud.match
		local set_angle = ring.SetTimerEulerAngle
		local function revive_angle()
			-- Text state 3 is also used by a teammate doing a revive. Only the downed player self-revives.
			if match.revivalText:GetValue( controller ) ~= 3 or not Game.IsInLastStand() then
				return
			end
			local start_time = match.revivalStartTime:GetValue( controller )
			local end_time = match.revivalEndTime:GetValue( controller )
			local current_time = match.revivalCurrentTime:GetValue( controller )
			if start_time and end_time and current_time and end_time > math.max( start_time, 0 ) then
				return 360 * LUI.clamp( (current_time - start_time) / (end_time - start_time), 0, 1 )
			end
		end
		ring.SetTimerEulerAngle = function ( self, angle, ... )
			local revive = revive_angle()
			if revive then
				return set_angle( self, revive, 0 )
			end
			return set_angle( self, angle, ... )
		end
		local function refresh()
			local angle = revive_angle()
			if not angle then
				local health = hud.healthPercent:GetValue( controller )
				if health == nil then
					return
				end
				local player = info.myDatasource
				angle = player and player.bleedoutEndTime:GetValue( controller ) ~= 0 and 0 or health * 360
			end
			set_angle( ring, angle, 0 )
		end
		for _, source in ipairs( { match.revivalText, match.revivalStartTime, match.revivalEndTime,
			match.revivalCurrentTime, hud.isInLastStand } ) do
			info:SubscribeToModel( source:GetModel( controller ), refresh )
		end
		refresh()
		print( "[wwz-mod] Synchronized the portrait ring with self-revive progress" )
		return info
	end
else
	print( "[wwz-mod] Could not find the Zombies player HUD builder" )
end

local build_bleedout = builders.zm_BleedoutWidget
if build_bleedout then
	builders.zm_BleedoutWidget = function ( menu, properties )
		local widget = build_bleedout( menu, properties )
		-- The Self-Revive prompt spans the same width as the centered Bleeding Out title.
		widget.ReviveHint:setHorizontalAlignment( LUI.HorizontalAlignment.Center )

		-- Perk markers keep their last bleed-out layout, but the stock update only hides
		-- markers still in the perk list. A lost perk's marker (a blank image) then showed
		-- under the bar while reviving a teammate.
		local set_alpha = widget.setAlpha
		local hid_stale = false
		widget.setAlpha = function ( self, ... )
			local result = set_alpha( self, ... )
			local count = self.currentPerksList and #self.currentPerksList or 0
			local index = 0
			local item = self.zm_BleedoutWidget_PerkItem0
			while item do
				if self.isReviving or index >= count then
					item:setAlpha( 0 )
					if index >= count and not hid_stale then
						hid_stale = true
						print( "[wwz-mod] Hid stale bleed-out perk markers" )
					end
				end
				index = index + 1
				item = self["zm_BleedoutWidget_PerkItem" .. index]
			end
			return result
		end
		print( "[wwz-mod] Centered the Self-Revive prompt and guarded bleed-out perk markers" )
		return widget
	end
else
	print( "[wwz-mod] Could not find the Zombies bleed-out builder" )
end

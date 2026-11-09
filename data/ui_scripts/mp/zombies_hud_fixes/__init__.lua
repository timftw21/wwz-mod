if not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build

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

local build_hud = builders.ZMHud
if build_hud then
	builders.ZMHud = function ( menu, properties )
		local hud = build_hud( menu, properties )
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

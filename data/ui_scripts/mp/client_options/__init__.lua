if not Engine.IsPC() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local preload = PCOptionsUtils.PreLoad
local title = "WWZ-MOD Options"
local menu_name = "wwz_client_options"
local locations = "wwz_zm_map_locations"
local jumpscares = "wwz_zm_jumpscares"
local feed = "wwz_zm_notification_feed"
local objectives = "wwz_zm_objective_text"
local hud_dvar = "wwz_zm_hud"
local double_xp = "wwz_zm_double_xp"
local states = {
	{ text = "@LUA_MENU_ENABLED", value = true },
	{ text = "@LUA_MENU_DISABLED", value = false }
}

local function add_toggle( rows, name, description, dvar )
	PCOptionsUtils.BuildScrollable( rows, name, description, dvar, nil, states, function ()
		print( string.format( "[wwz-mod] %s: %s", name, tostring( Engine.GetDvarBool( dvar ) ) ) )
	end )
end

PCOptionsUtils.PreLoad = function ( menu, properties )
	preload( menu, properties )
	if menu.id ~= "pc_options" then
		return
	end

	local scoped = LUI.FlowManager.GetScopedData( menu )
	if properties.wwzClientOptions then
		local rows = {}
		add_toggle( rows, "HUD", "Show the Zombies HUD and crosshair. Opening the scoreboard still shows the HUD.", hud_dvar )
		add_toggle( rows, "Map Locations", "Show the current area name on the Zombies HUD.", locations )
		add_toggle( rows, "Jumpscare Zombies", "Allow optional environmental jumpscares when you host Zombies.", jumpscares )
		add_toggle( rows, "HUD Activity Stream", "Show purchase and other activity messages on the Zombies HUD.", feed )
		add_toggle( rows, "Objective Text", "Show objective hints and the key prompt on the Zombies HUD.", objectives )
		add_toggle( rows, "OBJECTIVE OUTLINES", "Show white outlines on Zombies quest items and interactable objects.", "wwz_zm_objective_outlines" )
		add_toggle( rows, "Double XP", "Earn double Zombies XP when you host, and show the Double XP icons.", double_xp )
		scoped.gridData = rows
	else
		local entry = {}
		PCOptionsUtils.BuildButton( entry, title, "Change wwz-mod client settings.", menu_name )
		table.insert( scoped.gridData, 1, entry[1] )
	end
end

LUI.MenuBuilder.registerType( menu_name, function ( menu, properties )
	local options = LUI.DeepCopy( properties or {} )
	options.wwzClientOptions = true
	-- The reused Settings page can omit Back or bind it to the hub or pause page.
	options.noBack = false
	options.defaultBackButtonHandler = function ( element, controller )
		ACTIONS.LeaveMenu( element, nil, controller )
		print( "[wwz-mod] Closed WWZ-MOD Options" )
	end
	local page = builders.pc_options( menu, options )
	page.id = menu_name
	page.Title:SetTitle( title, "MENU_SETTINGS" )
	-- The Settings hub skips its blurred backdrop in game, where the pause menu sits behind it.
	-- Audio, Graphics and the other settings pages always build one, so match them.
	local first = page:getFirstChild()
	if not page.GenericMenuBackground0 and first then
		local background = LUI.MenuBuilder.BuildRegisteredType( "GenericMenuBackground", {
			controllerIndex = options.controllerIndex,
			fontIconSet = options.fontIconSet
		} )
		background.id = "GenericMenuBackground0"
		background:setAnchors( 0, 0, 0, 0, 0 )
		background:setLeft( 0, 0 )
		background:setRight( 0, 0 )
		background:setTop( 0, 0 )
		background:setBottom( 0, 0 )
		background:addElementBefore( first )
		page.GenericMenuBackground0 = background
		print( "[wwz-mod] Added the settings backdrop blur to WWZ-MOD Options" )
	end
	return page
end )

if Engine.IsZombiesMode() and not Engine.InFrontend() then
	local build_hud = builders.ZMHud

	-- Keep the stock alpha requested through setAlpha and show it only while visible() holds.
	-- Returns a function that reapplies the current state.
	local function gate_alpha( widget, visible )
		local set_alpha = widget.setAlpha
		local stock_alpha = widget:getAlpha()
		widget.setAlpha = function ( self, alpha, ... )
			stock_alpha = alpha
			return set_alpha( self, visible() and stock_alpha or 0, ... )
		end
		return function ()
			set_alpha( widget, visible() and stock_alpha or 0, 0 )
		end
	end

	-- Screen effects, subtitles (which have their own setting) and host migration notices stay
	-- visible without the HUD; zombies_hud_fixes keeps the spawn cover and hides the crosshair.
	local hud_kept = {
		BloodOverlay = true,
		SubtitleWidget0 = true,
		HostMigrationWidget0 = true,
		wwz_spawn_cover = true
	}

	builders.ZMHud = function ( menu, properties )
		local hud = build_hud( menu, properties )
		local controller = properties and properties.controllerIndex or hud:getRootController()
		local scoreboard = DataSources.inGame.HUD.scoreboardOpen
		local function scoreboard_open()
			return scoreboard:GetValue( controller ) == true
		end
		local function hud_visible()
			return Engine.GetDvarBool( hud_dvar ) or scoreboard_open()
		end
		local function option( dvar, with_scoreboard )
			return function ()
				return hud_visible() and (Engine.GetDvarBool( dvar ) or with_scoreboard and scoreboard_open())
			end
		end

		-- One gate per widget, so a hidden alpha is never mistaken for the stock one.
		local conditions = {}
		local widgets = {}
		local function add( widget, visible )
			if widget and not conditions[widget] then
				conditions[widget] = visible
				table.insert( widgets, widget )
			end
		end
		add( hud.zm_ZoneWidget0, option( locations ) )
		add( hud.zm_Notifications0, option( feed ) )
		add( hud.zm_QuestHintWidget0, option( objectives, true ) )
		local child = hud:getFirstChild()
		while child do
			if not hud_kept[child.id] then
				add( child, hud_visible )
			end
			child = child:getNextSibling()
		end

		local refreshers = {}
		for _, widget in ipairs( widgets ) do
			table.insert( refreshers, gate_alpha( widget, conditions[widget] ) )
		end
		local enabled
		local function refresh()
			for _, apply in ipairs( refreshers ) do
				apply()
			end
			local now = Engine.GetDvarBool( hud_dvar )
			if now ~= enabled then
				enabled = now
				print( string.format( "[wwz-mod] Zombies HUD %s (%d elements gated)", now and "enabled" or "disabled", #refreshers ) )
			end
		end
		for _, dvar in ipairs( { hud_dvar, locations, feed, objectives } ) do
			hud:registerDvarHandler( dvar, refresh )
		end
		hud:SubscribeToModel( scoreboard:GetModel( controller ), refresh, true )
		refresh()
		return hud
	end
end

if Engine.IsZombiesMode() then
	-- The bundled playlist enables Zombies 2XP and wwz_double_xp.gsc applies this toggle on the host.
	-- Every Zombies 2XP icon (lobbies, map selection, loading screen) is drawn by these two widgets.
	local logged_double_xp
	local function double_xp_enabled()
		local enabled = Engine.GetDvarBool( double_xp )
		if enabled ~= logged_double_xp then
			logged_double_xp = enabled
			print( "[wwz-mod] Zombies Double XP icons " .. (enabled and "shown" or "hidden") )
		end
		return enabled
	end

	local function wrap_builder( name, wrap )
		local build = builders[name]
		if not build then
			print( "[wwz-mod] Could not find the " .. name .. " builder" )
			return
		end
		builders[name] = function ( menu, properties )
			local widget = build( menu, properties )
			wrap( widget )
			return widget
		end
	end

	-- Private and public lobby icons.
	wrap_builder( "DoubleXPSignpostingItem", function ( item )
		local function zm_types( self )
			if not double_xp_enabled() then
				return {}
			end
			self:SetDoubleXPTypeZM( DoubleXPUtilsZM.XPType.PlayerRank )
			return { DoubleXPUtilsZM.XPType.PlayerRank }
		end
		item.SetZMDoubleXPTypeByDvar = zm_types
		item.SetZMDoubleXPTypeByPlaylist = zm_types
	end )

	-- Map selection and loading screen icons.
	wrap_builder( "DoubleXPSignposting", function ( signposting )
		local function zm_scales( self, animation )
			if not double_xp_enabled() then
				ACTIONS.AnimateSequence( self, "NoneActive" )
				return {}
			end
			self.DoubleXPSignpostingItem0:SetDoubleXPTypeZM( DoubleXPUtilsZM.XPType.PlayerRank, animation )
			ACTIONS.AnimateSequence( self, "OneActive" )
			return { DoubleXPUtilsZM.XPType.PlayerRank }
		end
		signposting.SetXPScalesFromDVars = zm_scales
		signposting.SetZMXPScalesFromPlaylistBools = function ( self, _, animation )
			return zm_scales( self, animation )
		end
	end )
end

print( "[wwz-mod] WWZ-MOD Options registered" )

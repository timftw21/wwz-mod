if not Engine.IsPC() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local preload = PCOptionsUtils.PreLoad
local title = "Client Options"
local menu_name = "wwz_client_options"
local locations = "wwz_zm_map_locations"
local jumpscares = "wwz_zm_jumpscares"
local feed = "wwz_zm_notification_feed"
local objectives = "wwz_zm_objective_text"
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
		add_toggle( rows, "Map Locations", "Show the current area name on the Zombies HUD.", locations )
		add_toggle( rows, "Jumpscare Zombies", "Allow optional environmental jumpscares when you host Zombies.", jumpscares )
		add_toggle( rows, "HUD Text Stream", "Show purchase and other activity messages on the Zombies HUD.", feed )
		add_toggle( rows, "Objective Text", "Show objective hints and the key prompt on the Zombies HUD.", objectives )
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
		print( "[wwz-mod] Closed Client Options" )
	end
	local page = builders.pc_options( menu, options )
	page.id = menu_name
	page.Title:SetTitle( title, "MENU_SETTINGS" )
	return page
end )

if Engine.IsZombiesMode() and not Engine.InFrontend() then
	local build_hud = builders.ZMHud

	local function gate_visibility( widget, dvar, show_with, controller )
		local set_alpha = widget.setAlpha
		local stock_alpha = widget:getAlpha()
		local function visible_alpha()
			return (Engine.GetDvarBool( dvar ) or (show_with and show_with:GetValue( controller ))) and stock_alpha or 0
		end
		widget.setAlpha = function ( self, alpha, ... )
			stock_alpha = alpha
			return set_alpha( self, visible_alpha(), ... )
		end
		local function refresh()
			set_alpha( widget, visible_alpha(), 0 )
		end
		widget:registerDvarHandler( dvar, refresh )
		if show_with then
			widget:SubscribeToModel( show_with:GetModel( controller ), refresh, true )
		end
		refresh()
	end

	builders.ZMHud = function ( menu, properties )
		local hud = build_hud( menu, properties )
		gate_visibility( hud.zm_ZoneWidget0, locations )
		if hud.zm_Notifications0 then
			gate_visibility( hud.zm_Notifications0, feed )
		end
		if hud.zm_QuestHintWidget0 then
			local controller = properties and properties.controllerIndex or hud:getRootController()
			gate_visibility( hud.zm_QuestHintWidget0, objectives, DataSources.inGame.HUD.scoreboardOpen, controller )
		end
		return hud
	end
end

print( "[wwz-mod] Client Options registered" )

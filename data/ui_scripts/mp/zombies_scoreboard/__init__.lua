if not Engine.IsZombiesMode() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_scoreboard = builders.zm_scoreboardDetailed
local build_row = builders.zm_score_row
local get_aar_info = ScoreboardUtils.GetPlayerScoreAARInfo
local match_loadouts = {}
local lobby_state = 2 -- Lobby.MemberListStates.Lobby is only defined in the frontend.

local function read_lobby_loadouts( loadouts )
	local get_member_count = Lobby.S2xStockGetCurrentMemberCount or Lobby.GetCurrentMemberCount
	local count = math.min( get_member_count( lobby_state ) or 0, 48 )
	for index = 0, count - 1 do
		local xuid = Lobby.GetMemberXuid( index )
		if xuid and xuid ~= "" and xuid ~= "0" then
			local loadout = Lobby.GetMemberLoadout( lobby_state, index, Teams.allies )
			if loadout then
				-- The report stores the hexadecimal form of the lobby member's XUID.
				loadouts[xuid] = loadout
				local hex = Engine.PlatformXUIDToHexXUID( xuid )
				if hex and hex ~= "" then
					loadouts[hex] = loadout
				end
			end
		end
	end
end

local function move_context_hints( hud )
	for _, name in ipairs( { "PerkContextualHint", "WeaponContextualHint" } ) do
		local panel = hud[name]
		if panel then
			local _, top, _, bottom = panel:getLocalRect()
			local upper = 48 * _1080p
			panel:setTop( upper, 0 )
			panel:setBottom( upper + bottom - top, 0 )
		end
	end
	print( "[wwz-mod] Moved Zombies contextual hints to the upper right" )
end

local function add_objective_scoreboard( inventory, hints, controller, icon_set )
	local open = DataSources.inGame.HUD.scoreboardOpen
	local hint_top, hint_bottom
	if hints then
		local _, top, _, bottom = hints:getLocalRect()
		hint_top, hint_bottom = top, bottom
	end
	local board
	inventory:SubscribeToModel( open:GetModel( controller ), function ()
		local visible = open:GetValue( controller )
		if hint_top then
			-- Leave room for four full-size rows beneath the quest text.
			local rise = visible and 44 * _1080p or 0
			hints:setTop( hint_top - rise, 0 )
			hints:setBottom( hint_bottom - rise, 0 )
		end
		if visible then
			if not board then
				board = LUI.MenuBuilder.BuildRegisteredType( "zm_scoreboardDetailed", {
					controllerIndex = controller,
					fontIconSet = icon_set,
					disableInteractivity = true
				} )
				for _, child in ipairs( { "GameMode", "Image4", "Image0", "zm_title_divider0", "Wave", "Map" } ) do
					board[child]:setAlpha( 0, 0 )
				end
				inventory:addElement( board )
				board:setAnchorsAndPosition( 0.5, 0.5, 0, 1, -960 * _1080p, 960 * _1080p,
					-402 * _1080p, 48 * _1080p, 0 )
				print( "[wwz-mod] Added the full-size live scoreboard to the Zombies objective screen" )
			else
				board:setAlpha( 1, 0 )
				LUI.UITimer.Enable( board.RefreshTimer )
				board.RefreshTimer:processEvent( { name = "zm_scoreboardDetailed_tick", controller = controller } )
			end
		elseif board then
			board:setAlpha( 0, 0 )
			LUI.UITimer.Disable( board.RefreshTimer )
		end
	end )
end

if builders.ZMHud then
	local build_hud = builders.ZMHud
	builders.ZMHud = function ( menu, properties )
		local hud = build_hud( menu, properties )
		match_loadouts = {}
		local round = DataSources.inGame.HUD.match.roundNumber
		local controller = properties and properties.controllerIndex or hud:getRootController()
		hud:SubscribeToModel( round:GetModel( controller ), function ()
			read_lobby_loadouts( match_loadouts )
		end )
		local inventory = hud.zm_QuestInventory_Container0
		if inventory then
			move_context_hints( hud )
			if not inventory.zm_scoreboard_s2_dlc3 then
				add_objective_scoreboard( inventory, hud.zm_QuestHintWidget0, controller, properties and properties.fontIconSet )
			end
		end
		return hud
	end
end

ScoreboardUtils.GetPlayerScoreAARInfo = function ( player, controller )
	local info = get_aar_info( player, controller )
	if player ~= nil and info then
		info.prestige = tonumber( AAR.GetPlayerStat( player, "prestige" ) ) or 0
	end
	return info
end

local function set_report_loadout( data, controller )
	local xuid = data.xuid:GetValue( controller )
	local loadout = match_loadouts[xuid]
	if not loadout and xuid and xuid ~= "" then
		local lobby_loadouts = {}
		read_lobby_loadouts( lobby_loadouts )
		loadout = lobby_loadouts[xuid]
		if not loadout then
			print( "[wwz-mod] No match or lobby loadout found for an AAR player" )
		end
	end

	local function perk_icon( perk )
		if not perk then
			return "ui_invisible"
		end
		local row = Engine.TableLookupGetRowNum( PerkTable.File, PerkTable.Cols.Index, tostring( perk ) )
		local icon = row >= 0 and Engine.TableLookupByRow( PerkTable.File, row, PerkTable.Cols.Image )
		return icon and icon ~= "" and icon or "ui_invisible"
	end

	data.perk1:SetValue( controller, perk_icon( loadout and loadout.perk1 ) )
	data.perk2:SetValue( controller, perk_icon( loadout and loadout.perk4 ) )
	data.perk3:SetValue( controller, perk_icon( loadout and loadout.perk7 ) )
	local ability = loadout and loadout.ability and Engine.GetItemReferenceFromGUID( loadout.ability )
	local image = ability and ability ~= "" and Cac.GetWeaponImageName( "Ability", ability )
	data.ability:SetValue( controller, image and image ~= "" and image or "ui_invisible" )
end

local function make_ping_label( text, size, color )
	local label = LUI.UIText.new()
	label:setFont( FONTS.BodyFont.Font )
	label:setFontSize( size, 0 )
	label:setRGBFromInt( color, 0 )
	label:setHorizontalAlignment( LUI.HorizontalAlignment.Center )
	label:setVerticalAlignment( LUI.VerticalAlignment.Middle )
	label:setText( text, 0 )
	return label
end

builders.zm_score_row = function ( menu, properties )
	local row = build_row( menu, properties )
	-- BodyFont's visible glyphs sit above the center of its line box.
	for _, label in ipairs( { row.LevelLabel, row.NameLabel, row.ClanTagLabel,
		row.KillsLabel, row.HeadshotLabel, row.RevivesLabel, row.ScoreLabel } ) do
		local _, top, _, bottom = label:getLocalRect()
		label:setTop( top + 2 * _1080p, 0 )
		label:setBottom( bottom + 2 * _1080p, 0 )
	end
	local ping_bar = row.PingBar
	ping_bar:UnsubscribeFromAllModels()
	ping_bar:setImage( RegisterMaterial( "ui_invisible" ), 0 )

	if ScoreboardUtils.IsAARMode() then
		row:SubscribeToModelThroughElement( row, "xuid", function ()
			local data, controller = row:GetDataSource()
			if data and not CONDITIONS.IsZombieTraining() then
				set_report_loadout( data, controller )
			end
		end )
		return row
	end

	-- Keep the stock ping element's row visibility and use its center for the value.
	local value = make_ping_label( "-", 22, SWATCHES.ZM.hudText )
	ping_bar:addElement( value )
	value:setAnchorsAndPosition( 0.5, 0.5, 0, 0, -30 * _1080p, 30 * _1080p, 2 * _1080p, 2 * _1080p, 0 )
	local function update_ping()
		local data, controller = row:GetDataSource()
		local client = data and data.clientNum:GetValue( controller )
		local ping = client and game:getscoreboardping( client, client == Game.GetPlayerClientnum() )
		value:setText( ping and ping >= 0 and tostring( ping ) or "-", 0 )
	end
	row:SubscribeToModelThroughElement( row, "clientNum", update_ping )
	row:registerEventHandler( "wwz_refresh_scoreboard_ping", update_ping )
	return row
end

builders.zm_scoreboardDetailed = function ( menu, properties )
	local board = build_scoreboard( menu, properties )
	if ScoreboardUtils.IsAARMode() then
		return board
	end

	local label = make_ping_label( Engine.Localize( "LUA_MENU_PING" ), 22, SWATCHES.ZM.hudSubtext )
	local baseline = GameX.IsSplitscreen() and 210.75 or 221.97
	label:setAnchorsAndPosition( 0, 1, 0, 1, 1734.69 * _1080p, 1810.69 * _1080p,
		(baseline - 29.47) * _1080p, baseline * _1080p, 0 )
	label:setVerticalAlignment( LUI.VerticalAlignment.Bottom )
	board:addElement( label )

	game:requestscoreboardpings()
	board.RefreshTimer:addEventHandler( "zm_scoreboardDetailed_tick", function ()
		game:requestscoreboardpings()
		board.Scores:processEvent( { name = "wwz_refresh_scoreboard_ping", dispatchChildren = true } )
	end )
	return board
end

print( "[wwz-mod] Zombies scoreboard centers row values, shows latency, and restores report prestige and loadouts" )

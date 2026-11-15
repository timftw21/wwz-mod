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

-- Master Prestige ranks follow the last regular Zombies rank, which displays as level 45.
local master_color = Rank and Rank.GetMasterPrestigeColor and Rank.GetMasterPrestigeColor() or { r = 0.86, g = 0.64, b = 0 }
local master_logged = false
local function is_master_level( level )
	local ok, max_rank = pcall( function () return Rank.GetMaxRank( 0, CoD.PlayMode.Zombies ) end )
	max_rank = ok and tonumber( max_rank ) or 44
	level = tonumber( level )
	return level ~= nil and level > max_rank + 1
end

local function color_level( label, level, default_color )
	if is_master_level( level ) then
		label:setRGB( master_color.r, master_color.g, master_color.b )
		if not master_logged then
			master_logged = true
			print( "[wwz-mod] Colored a Master Prestige level" )
		end
	elseif default_color then
		label:setRGBFromInt( default_color, 0 )
	else
		label:setRGB( 1, 1, 1 )
	end
end

local build_rank_progress = builders.aar_stats_rank_progress
if build_rank_progress then
	builders.aar_stats_rank_progress = function ( menu, properties )
		local progress = build_rank_progress( menu, properties )
		local controller = properties and properties.controllerIndex or progress:getRootController()
		local rank = DataSources.Shared.PlayerStats.rank
		progress.RankValue:SubscribeToModel( rank:GetModel( controller ), function ()
			color_level( progress.RankValue, rank:GetValue( controller ), SWATCHES.Menus.MenuOffWhite )
		end )
		return progress
	end
end

local build_aar_summary = builders.aar_summary_menu
if build_aar_summary then
	builders.aar_summary_menu = function ( menu, properties )
		local summary = build_aar_summary( menu, properties )
		local value = summary.NewRankValue
		if value then
			local set_text = value.setText
			value.setText = function ( self, text, ... )
				local result = set_text( self, text, ... )
				color_level( self, text, SWATCHES.Menus.MenuOffWhite )
				return result
			end
		end
		return summary
	end
end

-- The Social tab's player panel shows the selected player's raw rank and game mode.
local build_social_info = builders.player_interact_social_info_widget
if build_social_info then
	builders.player_interact_social_info_widget = function ( menu, properties )
		local widget = build_social_info( menu, properties )
		local update = widget.UpdatePlayerInfo
		if update then
			widget.UpdatePlayerInfo = function ( self, controller, info, ... )
				local result = update( self, controller, info, ... )
				local ok, master = pcall( function ()
					return Rank.IsMasterPrestigeRank( info.rank or 0, info.gameMode or CoD.PlayMode.Zombies )
				end )
				if ok and master then
					self.RankValue:setRGB( master_color.r, master_color.g, master_color.b )
					if not master_logged then
						master_logged = true
						print( "[wwz-mod] Colored a Master Prestige level" )
					end
				else
					self.RankValue:setRGBFromInt( SWATCHES.Button.MenuWhite, 0 )
				end
				return result
			end
		end
		return widget
	end
end

-- Five stat columns share the stock span from Kills (657.01) to the end of Score (1246.05),
-- alternating backgrounds as before. Headers sit 100 units right of the rows.
local columns = {
	kills = { 657.01, 765.01 },
	headshots = { 765.01, 893.01 },
	revives = { 893.01, 1008.01 },
	downs = { 1008.01, 1118.01 },
	score = { 1118.01, 1246.05 }
}

local function place_column( element, span, shift )
	element:setLeft( (span[1] + shift) * _1080p, 0 )
	element:setRight( (span[2] + shift) * _1080p, 0 )
end

local function add_downs_label( row, properties )
	local label = LUI.UIText.new()
	label.id = "DownsLabel"
	if properties and properties.fontIconSet ~= nil then
		label:setFontIconSet( properties.fontIconSet )
	end
	label:setAnchors( 0, 1, 0, 1, 0 )
	label:setTop( 0, 0 )
	label:setBottom( 54 * _1080p, 0 )
	label:setFont( FONTS.BodyFont.Font )
	label:setFontSize( 26, 0 )
	label:setHorizontalAlignment( LUI.HorizontalAlignment.Center )
	label:setVerticalAlignment( LUI.VerticalAlignment.Middle )
	place_column( label, columns.downs, 0 )
	row:addElement( label )
	row.DownsLabel = label
	label:SubscribeToModelThroughElement( row, "downs", function ()
		local data, controller = row:GetDataSource()
		local downs = data and data.downs and data.downs:GetValue( controller )
		if downs ~= nil then
			label:setText( downs, 0 )
		end
	end )
	if properties and properties.isBuildChild == true then
		row:addEventHandler( "grid_cell_empty", function ()
			label:setAlpha( 0 )
		end )
		row:addEventHandler( "grid_cell_populated", function ()
			label:setAlpha( 1 )
		end )
	end
	return label
end

-- Zombies leaves the scoreboard deaths field unused; wwz_scoreboard_downs.gsc stores downs in it.
local function read_score_infos( controller )
	-- Same sources and order as the stock refresh, which skips missing entries.
	local infos = {}
	if ScoreboardUtils.IsAARMode() then
		local players = ScoreboardUtils.playersTeamAxis
		if ScoreboardUtils.GetPlayerTeam( controller ) == Teams.allies then
			players = ScoreboardUtils.playersTeamAllies or ScoreboardUtils.playersTeamAxis
		end
		for index = 1, players and #players or 0 do
			infos[#infos + 1] = ScoreboardUtils.GetPlayerScoreAARInfo( players[index], controller )
		end
	else
		for rank = 1, CoD.MaxZombiePlayers do
			local info = Game.GetPlayerScoreInfoAtRank( Teams.allies, rank )
			if info then
				infos[#infos + 1] = info
			end
		end
	end
	return infos
end

local downs_logged = false
local function add_downs_to_list( list )
	local populate = list.Populate
	list.Populate = function ( self, count, fill, focus, controller, ... )
		local infos = read_score_infos( controller )
		return populate( self, count, function ( element, index, item_controller, ... )
			fill( element, index, item_controller, ... )
			if not element.downs then
				element.downs = element:GetDataSourceForSubmodel( "downs", 0 )
			end
			local info = infos[index + 1]
			element.downs:SetValue( item_controller, info and tonumber( info.deaths ) or 0 )
			if not downs_logged then
				downs_logged = true
				print( "[wwz-mod] Filled the Zombies scoreboard downs column" )
			end
		end, focus, controller, ... )
	end
end

builders.zm_score_row = function ( menu, properties )
	local row = build_row( menu, properties )
	row.LevelLabel:SubscribeToModelThroughElement( row, "rank", function ()
		local data, controller = row:GetDataSource()
		if data and data.rank then
			color_level( row.LevelLabel, data.rank:GetValue( controller ) )
		end
	end )
	place_column( row.KillsLabel, columns.kills, 0 )
	place_column( row.BackHS, columns.headshots, 0 )
	place_column( row.HeadshotLabel, columns.headshots, 0 )
	place_column( row.RevivesLabel, columns.revives, 0 )
	-- Score's stock background now shades Downs, keeping the columns alternating.
	place_column( row.ScoresBack, columns.downs, 0 )
	place_column( row.ScoreLabel, columns.score, 0 )
	local downs_label = add_downs_label( row, properties )
	-- BodyFont's visible glyphs sit above the center of its line box.
	for _, label in ipairs( { row.LevelLabel, row.NameLabel, row.ClanTagLabel,
		row.KillsLabel, row.HeadshotLabel, row.RevivesLabel, downs_label, row.ScoreLabel } ) do
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

local function add_downs_header( board, properties )
	for name, span in pairs( { Label0 = columns.kills, Label1 = columns.headshots,
		Label2 = columns.revives, Label3 = columns.score } ) do
		place_column( board[name], span, 100 )
	end
	local revives = board.Label2
	local header = LUI.UIText.new()
	header.id = "DownsHeader"
	if properties and properties.fontIconSet ~= nil then
		header:setFontIconSet( properties.fontIconSet )
	end
	header:setAnchors( 0, 1, 0, 1, 0 )
	-- Match the Revives header, including its split-screen position.
	local _, top, _, bottom = revives:getLocalRect()
	header:setTop( top, 0 )
	header:setBottom( bottom, 0 )
	header:setFont( FONTS.BodyFont.Font )
	header:setFontSize( 22, 0 )
	header:setHorizontalAlignment( LUI.HorizontalAlignment.Center )
	header:setVerticalAlignment( LUI.VerticalAlignment.Bottom )
	header:setRGBFromInt( SWATCHES.ZM.hudSubtext, 0 )
	header:setText( Engine.Localize( "MPUI_DOWNS" ), 0 )
	place_column( header, columns.downs, 100 )
	board:addElement( header )
	-- Grid cells hide and show the headers together; follow the Revives header.
	local set_alpha = revives.setAlpha
	revives.setAlpha = function ( self, ... )
		header:setAlpha( ... )
		return set_alpha( self, ... )
	end
end

builders.zm_scoreboardDetailed = function ( menu, properties )
	-- The stock build creates and first populates the player list; add downs to it as it does.
	local new_list = LUI.ArchetypeListDataSource.new
	local found = false
	LUI.ArchetypeListDataSource.new = function ( archetype, path, ... )
		local list = new_list( archetype, path, ... )
		if path == "cg.hud.zombiesScoreboard" then
			found = true
			add_downs_to_list( list )
		end
		return list
	end
	local ok, board = pcall( build_scoreboard, menu, properties )
	LUI.ArchetypeListDataSource.new = new_list
	if not ok then
		error( board, 0 )
	end
	if not found then
		print( "[wwz-mod] Could not find the Zombies scoreboard player list" )
	end
	add_downs_header( board, properties )
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

print( "[wwz-mod] Zombies scoreboard centers row values, shows latency and downs, colors Master Prestige levels, and restores report prestige and loadouts" )

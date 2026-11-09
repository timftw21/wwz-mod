if not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_splashes = builders.SplashesWidget
local icons = RankTable_ZM and RankTable_ZM.IconTable
if not build_splashes or not icons then
	print( "[wwz-mod] Could not find the Zombies notification feed or rank icon table" )
	return
end

local function local_score( controller )
	if Game.GetPlayerControllerIndex() ~= controller then
		return
	end
	local client = Game.GetPlayerClientnum()
	for index = 1, CoD.MaxZombiePlayers do
		local score = Game.GetPlayerScoreInfoAtRank( Teams.allies, index )
		if score and score.client == client then
			return score
		end
	end
end

local function update_rank_icon( material, controller )
	local stock_icon = material:GetValue( controller ) or ""
	local mode = CoD.PlayMode.Zombies
	local rank
	if stock_icon:lower() == "rank_prestigemaster" then
		rank = Rank.GetMaxRank( 0, mode ) + 1
	elseif stock_icon ~= "" then
		-- The original image identifies the earned rank even when the popup is queued.
		rank = tonumber( Engine.TableLookup( icons.File, icons.Cols.Standard, stock_icon, icons.Cols.RankId ) )
	end
	local score = local_score( controller )
	rank = rank or (score and tonumber( score.rank ))
	local prestige = tonumber( score and score.prestige ) or tonumber( AAR.GetPrestigeLevel( controller ) ) or 0
	local icon = rank and Rank.GetRankIcon( rank, prestige, nil, mode )
	if icon and icon ~= "" then
		material:SetValue( controller, icon )
		print( "[wwz-mod] Zombies promotion uses " .. icon .. " at prestige " .. prestige )
	else
		if stock_icon ~= "" then
			MODIFIERS.CacheIconMaterial( stock_icon )
		end
		print( "[wwz-mod] Could not resolve a Zombies promotion icon for " .. stock_icon )
	end
end

builders.SplashesWidget = function ( menu, properties )
	local widget = build_splashes( menu, properties )
	local feed = widget.Feed and widget.Feed:GetFeedDataSource()
	if not feed then
		print( "[wwz-mod] Could not attach prestige icons to the Zombies notification feed" )
		return widget
	end
	if not feed.wwzRankIconHook then
		feed.wwzRankIconHook = true
		local push = feed.PushData
		feed.PushData = function ( self, controller )
			local splash = DataSources.inGame.HUD.splashesFeed
			-- Set the cached icon before the stock feed copies the notification into a display slot.
			if splash.splashType:GetValue( controller ) == "rankup_splash" then
				update_rank_icon( splash.materialName, controller )
			end
			return push( self, controller )
		end
	end
	return widget
end

print( "[wwz-mod] Enabled cached prestige icons in the Zombies notification feed" )

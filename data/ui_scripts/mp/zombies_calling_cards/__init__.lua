if not Engine.IsZombiesMode() or not Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_menu = builders.callingcard_menu
local dossier = DataSources.inFrontend and DataSources.inFrontend.MP and DataSources.inFrontend.MP.Dossier
local navbar = dossier and dossier.callingCardNavbar
local card_list = dossier and dossier.availableCallingCards
if not build_menu or type( navbar ) ~= "table" or type( card_list ) ~= "table" then
	print( "[wwz-mod] Could not add the Nazi Zombies calling card category: menu data missing" )
	return
end

local card_file = "mp/callingcards.csv"
local columns = {
	Ref = 0,
	Image = 1,
	Name = 2,
	Reference = 3,
	BorderImage = 8,
	DisplayOrder = 9
}
local prefix = "playercard_zm_challenge_"
local card_count = 11
local challenge_type = 3

local function card_number( reference )
	return type( reference ) == "string" and tonumber( reference:match( "^" .. prefix .. "(%d+)$" ) ) or nil
end

-- Cards 1-10 are granted on entering each Zombies prestige; card 11 on entering
-- Master Prestige (level 46 at Prestige 10, the "zombie" prestige event 11).
local function requirement( number )
	if number > 10 then
		return "Unlocked at Master Prestige."
	end
	return Engine.Localize( "CHALLENGE_DESC_PRESTIGE_" .. number )
end

local function locked_card( number )
	local reference = string.format( "%s%02d", prefix, number )
	local row = Engine.TableLookupGetRowNum( card_file, columns.Reference, reference )
	if not row or row < 0 then
		return nil
	end
	local name_ref = Engine.TableLookupByRow( card_file, row, columns.Name )
	local name = Engine.Localize( name_ref )
	local border = Engine.TableLookupByRow( card_file, row, columns.BorderImage )
	return {
		category = "nazi_zombies",
		nameRef = name_ref,
		name = name,
		reference = reference,
		sortName = MODIFIERS.ToUpperCase( name ),
		cardIndex = tonumber( Engine.TableLookupByRow( card_file, row, columns.Ref ) ),
		image = Engine.TableLookupByRow( card_file, row, columns.Image ),
		borderImage = border ~= "" and border or nil,
		displayOrder = tonumber( Engine.TableLookupByRow( card_file, row, columns.DisplayOrder ) ) or number,
		locked = true,
		displayStatus = "locked"
	}
end

local function take_prestige_cards( cards, owned )
	for position = #cards, 1, -1 do
		local number = card_number( cards[position].reference )
		if number then
			owned[number] = table.remove( cards, position )
		end
	end
end

local function add_category( controller, categories, current, owned )
	local prestige = tonumber( Engine.GetPlayerData( controller, CoD.StatsGroup.Coop, "prestigeLevel" ) ) or 0
	for index = #categories, 1, -1 do
		local category = categories[index]
		if type( category.callingCards ) == "table" then
			take_prestige_cards( category.callingCards, owned )
			-- Drop a page the move emptied, unless it is shown or precedes the shown page.
			if #category.callingCards == 0 and index > current then
				table.remove( categories, index )
			end
		end
	end

	local cards = {}
	for number = 1, card_count do
		local card = owned[number] or locked_card( number )
		if card then
			-- Unlocked cards come from the stock lists; locked ones are hidden by the stock menu.
			card.challengeData = {
				name = card.name,
				desc = requirement( number ),
				progress = number > 10 and 0 or math.min( prestige, number ),
				target = number > 10 and 1 or number,
				activeTier = 1,
				numTiers = 1
			}
			table.insert( cards, card )
		end
	end
	if #cards == 0 then
		print( "[wwz-mod] Could not add the Nazi Zombies calling card category: no prestige cards found" )
		return false
	end
	table.insert( categories, {
		reference = "nazi_zombies",
		name = "LUA_MENU_ZOMBIES_CAPS",
		type = challenge_type,
		callingCards = cards
	} )
	print( "[wwz-mod] Moved " .. #cards .. " Zombies prestige cards into the Nazi Zombies calling card category" )
	return true
end

builders.callingcard_menu = function ( menu, properties )
	local owned = {}
	local own_cards_populate = rawget( card_list, "Populate" )
	local own_navbar_populate = rawget( navbar, "Populate" )

	-- The opening page is populated before the category bar, so filter it first and keep
	-- the equipped card selected.
	local populate_cards = card_list.Populate
	card_list.Populate = function ( self, count, fill, index, controller, cards, ... )
		rawset( card_list, "Populate", own_cards_populate )
		if type( cards ) == "table" then
			local selected = cards[( tonumber( index ) or 0 ) + 1]
			take_prestige_cards( cards, owned )
			count, index = #cards, 0
			for position, card in ipairs( cards ) do
				if card == selected then
					index = position - 1
					break
				end
			end
		end
		return populate_cards( self, count, fill, index, controller, cards, ... )
	end

	local populate_navbar = navbar.Populate
	navbar.Populate = function ( self, count, fill, index, controller, categories, ... )
		rawset( navbar, "Populate", own_navbar_populate )
		if type( categories ) == "table" and type( controller ) == "number" and
			add_category( controller, categories, ( tonumber( index ) or 0 ) + 1, owned ) then
			count = #categories
		end
		return populate_navbar( self, count, fill, index, controller, categories, ... )
	end

	local ok, result = pcall( build_menu, menu, properties )
	rawset( card_list, "Populate", own_cards_populate )
	rawset( navbar, "Populate", own_navbar_populate )
	if not ok then
		error( result, 0 )
	end
	return result
end

if not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local title = "RESTART MATCH"
local function can_restart()
	return Engine.GetDvarBool( "1080" ) -- sv_running: this machine hosts the match.
end

local restart_page = {
	Name = title,
	Disabled = function () return not can_restart() end,
	IsLegacyMenu = true,
	GetBuildOptions = function ()
		return {
			type = "generic_yesno_popup",
			properties = {
				popup_title = title,
				message_text = "Restart this match from the beginning for all players?",
				wwzFullscreenOverlay = true,
				popup_list_spacing = 4,
				-- The stock window sums the five row heights, excluding the four gaps.
				padding_bottom = 10 + 4 * 4,
				yes_action = function ()
					if not can_restart() then
						print( "[wwz-mod] Restart Match skipped because this client is no longer the host" )
						return
					end
					print( "[wwz-mod] Host confirmed Restart Match" )
					Engine.ExecFirstClient( "map_restart" )
				end
			}
		}
	end
}

local controller = require( "s2.mp_pause_menu_uc" )
local preload = controller.PreLoadFunc
controller.PreLoadFunc = function ( menu, index, properties )
	local scope = LUI.FlowManager.GetScopedData( menu )
	local current = scope.pauseMenu and scope.pauseMenu.currentPage
	preload( menu, index, properties )
	local pause = scope.pauseMenu
	for i, page in ipairs( pause.pages ) do
		if page.Name == title or page.Name == "LUA_MENU_END_GAME" then
			if page.Name ~= title then
				table.insert( pause.pages, i, restart_page )
			end
			-- The saved page is one-based. A fresh stock selection is zero-based
			-- and counts only the original tabs.
			if current then
				pause.initialIndex = current - 1
			elseif pause.initialIndex >= i - 1 then
				pause.initialIndex = pause.initialIndex + 1
			end
			return
		end
	end
end

-- The generated menu captures PreLoadFunc when its module loads.
local builders = LUI.MenuBuilder.m_types_build
local module_name = "s2.mp_pause_menu"
local old_builder, old_module = builders.mp_pause_menu, package.loaded[module_name]
builders.mp_pause_menu, package.loaded[module_name] = nil, nil
local ok, err = pcall( require, module_name )
controller.PreLoadFunc = preload
if not ok or not builders.mp_pause_menu then
	builders.mp_pause_menu, package.loaded[module_name] = old_builder, old_module
	print( "[wwz-mod] Could not register Restart Match: " .. tostring( err ) )
else
	print( "[wwz-mod] Registered Restart Match before Leave Game in the Zombies pause menu" )
end

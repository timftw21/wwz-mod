if game:issingleplayer() then
	return
end

-- Keep the menu context from UI startup, as in the original lobby fix.
local frontend = Engine.InFrontend()
if not frontend and not Engine.IsZombiesMode() then
	return
end

local function fullscreen_overlay( popup )
	if popup._wwzFullscreenOverlay then
		return popup
	end
	local intermediate = assert( popup:getChildById( "generic_selectionList_intermediate" ),
		"[wwz-mod] popup_overlay: missing popup container" )
	local window = assert( intermediate:getChildById( "generic_selectionList_window_id" ),
		"[wwz-mod] popup_overlay: missing content window" )
	local overlay = assert( window:getFirstChild(), "[wwz-mod] popup_overlay: missing screen overlay" )
	-- The content window is vertically offset when resized. Its screen overlay
	-- belongs to the full-screen container so that offset cannot leave a gap.
	window:removeElement( overlay )
	overlay:addElementBefore( window )
	popup._wwzFullscreenOverlay = true
	print( "[wwz-mod] popup_overlay: screen overlay moved outside the resized content window" )
	return popup
end

local build_popup = LUI.MenuGenerics.generic_selectionList_popup
local function fullscreen_popup( menu, properties )
	local popup = build_popup( menu, properties )
	if frontend or properties.wwzFullscreenOverlay then
		return fullscreen_overlay( popup )
	end
	return popup
end

LUI.MenuGenerics.generic_selectionList_popup = fullscreen_popup
local builders = LUI.MenuBuilder.m_types_build
if builders.generic_selectionList_popup == build_popup then
	builders.generic_selectionList_popup = fullscreen_popup
end

-- Custom Tag and direct numeric entry both open this registered keyboard.
local build_keyboard = builders.virtual_keyboard
if build_keyboard then
	builders.virtual_keyboard = function ( menu, properties )
		return fullscreen_overlay( build_keyboard( menu, properties ) )
	end
end
print( "[wwz-mod] Installed full-screen overlays for lobby popups and text entry" )

if game:issingleplayer() or not Engine.InFrontend() then
	return
end

local build_popup = LUI.MenuGenerics.generic_selectionList_popup
local function fullscreen_popup( menu, properties )
	local popup = build_popup( menu, properties )
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

LUI.MenuGenerics.generic_selectionList_popup = fullscreen_popup
local builders = LUI.MenuBuilder.m_types_build
if builders.generic_selectionList_popup == build_popup then
	builders.generic_selectionList_popup = fullscreen_popup
end
print( "[wwz-mod] Full-screen popup overlays installed (including clan-tag keyboard)" )

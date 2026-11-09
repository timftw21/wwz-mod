if not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_hud = builders.ZMHud

local function center_text( text )
	local left, _, right = text:getLocalRect()
	local half_width = left and right and right > left and (right - left) / 2 or 300 * _1080p
	text:setHorizontalAlignment( LUI.HorizontalAlignment.Center )
	text:setLeft( -half_width, 0 )
	text:setRight( half_width, 0 )
end

local function hold_key_span( text, controller )
	local lower = text:lower()
	local first = lower:match( "^%s*hold%s+()" ) or lower:match( "^%s*press and hold%s+()" )
	if not first then
		return
	end

	local rest = text:sub( first )
	-- The model may supply the original directive or an already resolved, colored binding.
	local key = rest:match( "^(%^3.-%^7)%s+" ) or rest:match( "^(%[%{[^}]+%}%])%s+" )
	if not key then
		local binding = Engine.GetKeyBindingLocalizedString( controller, "+activate" )
		if binding and binding ~= "" and rest:sub( 1, #binding ) == binding and rest:sub( #binding + 1, #binding + 1 ):match( "%s" ) then
			key = binding
		end
	end
	if key then
		return first, first + #key - 1
	end
end

local function center_interaction( prompt, controller, icon_set )
	local message = prompt.InteractHintMessage
	local interact = prompt.InteractText
	local inline_icon = prompt.FirstLineImage
	local ring = prompt.ProgressiveInteractWidget
	local labels = { message, interact }
	local ring_top, ring_bottom

	local function text_width( label, text )
		local left, _, right = GetTextDimensions( text, label:getCurrentFont(), icon_set,
			label:getFontSize() * _1080p )
		return right - left
	end

	local function first_line( label )
		return (label:getText() or ""):match( "^[^\r\n]*" )
	end

	local function align_accessories()
		local message_line = first_line( message )
		local message_width = text_width( message, message_line )
		local rtl = CONDITIONS.IsCurrentLanguageRTL()
		local direction = rtl and 1 or -1
		local icon_center = direction * (math.min( message_width, message:getWidth() or 600 * _1080p ) / 2 + 46 * _1080p)
		inline_icon:setLeft( icon_center - 32 * _1080p, 0 )
		inline_icon:setRight( icon_center + 32 * _1080p, 0 )

		local active = message:getAlpha() > 0 and message or interact
		local line = active == message and message_line or first_line( active )
		local width = active == message and message_width or text_width( active, line )
		local available = active:getWidth() or 600 * _1080p
		local first, last = hold_key_span( line, controller )
		local keyboard = Engine.IsPC() and not Engine.IsGamepadEnabled( controller )
		local ring_center, ring_scale
		if first then
			local key_width = text_width( active, line:sub( first, last ) )
			local scale = active == interact and available > 0 and width > available and available / width or 1
			-- Measure through the end of the key so the font includes the space before it.
			ring_center = (text_width( active, line:sub( 1, last ) ) - (key_width + width) / 2) * scale
			ring_center = rtl and -ring_center or ring_center
			-- The stock ring is 50px across at unit scale. Fit it to the key and one line of text.
			ring_scale = math.max( active:getFontSize(), key_width / _1080p + 4 ) * scale / 50 - 1
		else
			local gap = active == message and inline_icon:getAlpha() > 0 and 96 or 32
			ring_center = direction * (math.min( width, available ) / 2 + gap * _1080p)
			ring_scale = keyboard and -0.3 or 0
		end
		-- Keyboard glyphs sit slightly above the center of their line box.
		local rise = first and keyboard and 2 * _1080p or 0
		ring:setAnchorsAndPosition( 0.5, 0.5, 0, 1, ring_center - 64 * _1080p, ring_center + 64 * _1080p,
			ring_top - rise, ring_bottom - rise, 0 )
		ring:setScale( ring_scale, 0 )
	end

	for _, label in ipairs( labels ) do
		local set_text = label.setText
		label.setText = function ( self, text, ... )
			set_text( self, text, ... )
			align_accessories()
		end
	end
	local set_message_alpha = message.setAlpha
	message.setAlpha = function ( self, alpha, ... )
		set_message_alpha( self, alpha, ... )
		align_accessories()
	end

	local function align_lines()
		for _, text in ipairs( { interact, prompt.CostText, message,
			prompt.Consumable0Hint, prompt.Consumable1Hint } ) do
			center_text( text )
		end
		-- Weapon art appears on its own line.
		prompt.SecondLineImage:setLeft( -128 * _1080p, 0 )
		prompt.SecondLineImage:setRight( 128 * _1080p, 0 )
		-- Preserve the vertical layout for this input mode and replace the stock left anchor.
		local _, top, _, bottom = ring:getLocalRect()
		ring_top, ring_bottom = top, bottom
		align_accessories()
	end

	local configure = prompt.m_eventHandlers.button_config_updated
	prompt:registerEventHandler( "button_config_updated", function ( self, event )
		local handled = configure( self, event )
		controller = event.controller or controller
		align_lines()
		return handled
	end )
	align_lines()
end

builders.ZMHud = function ( menu, properties )
	local hud = build_hud( menu, properties )
	local prompt = hud.InteractPrompt
	if not prompt then
		print( "[wwz-mod] Could not find the Zombies HUD interaction widget" )
		return hud
	end
	-- The stock box starts just left of the reticle and extends 600px to the right.
	prompt:setLeft( -300 * _1080p, 0 )
	prompt:setRight( 300 * _1080p, 0 )
	local controller = properties and properties.controllerIndex or hud:getRootController()
	center_interaction( prompt, controller, properties and properties.fontIconSet or LUI.FontIconSet.Default )
	return hud
end

print( "[wwz-mod] Centered Zombies interaction prompts and aligned hold rings to their keys" )

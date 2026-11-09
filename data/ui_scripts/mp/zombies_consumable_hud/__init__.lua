if not Engine.IsPC() or not Engine.IsZombiesMode() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local build_slots = builders.zm_ActionSlots
if not build_slots then
	print( "[wwz-mod] Could not find the Zombies consumable HUD builder" )
	return
end

local function align_prompt( label, controller, command )
	if command then
		local set_text = label.setText
		label.setText = function ( self, text, ... )
			if not Engine.IsGamepadEnabled( controller ) then
				-- Match the consumables' binding resolver, including after a rebind.
				text = Engine.GetKeyBindingLocalizedString( controller, command )
			end
			return set_text( self, text, ... )
		end
		label:setText( label:getText(), 0 )
	end
	-- Use the same keyboard layout for every row. Stock input-mode updates replay this sequence.
	label:RegisterAnimationSequence( "PC_KBM", { {
		function ()
			return label:setAnchorsAndPosition( 1, 0, 0, 1, -48 * _1080p, 0,
				-0.5 * _1080p, 47.5 * _1080p, 0 )
		end
	} } )
	if not Engine.IsGamepadEnabled( controller ) then
		label:AnimateSequence( "PC_KBM" )
	end
end

builders.zm_ActionSlots = function ( menu, properties )
	local slots = build_slots( menu, properties )
	local first = slots.zm_consumable_widget0
	local second = slots.zm_consumable_widget1
	local share = slots.zm_ShareMoneyWidget0
	local quest = slots.zm_QuestItemCycler0
	if not first or not second or not share or not quest then
		print( "[wwz-mod] Could not find all four Zombies action-slot widgets" )
		return slots
	end
	local controller = properties and properties.controllerIndex or slots:getRootController()
	for _, consumable in ipairs( { first, second } ) do
		consumable.Count:setFont( FONTS.TitleFont.Font )
		align_prompt( consumable.keyBinding, controller )
	end
	align_prompt( share.GivePointsPrompt, controller, "+actionslot 3" )
	align_prompt( quest.Input, controller, "+actionslot 4" )
	print( "[wwz-mod] Aligned Zombies HUD keybinds and applied the round-counter font to consumable quantities" )
	return slots
end

if game:issingleplayer() or Engine.InFrontend() then
	return
end

local builders = LUI.MenuBuilder.m_types_build
local stock_widget = builders.PeriodicChallengeProgressWidget
builders.PeriodicChallengeProgressWidget = function ( menu, properties )
	local widget = stock_widget( menu, properties )
	local controller = properties and properties.controllerIndex or widget:getRootController()
	local stock_event = widget.m_eventHandlers.achievementEngine
	if not stock_event then
		return widget
	end

	local milestones = {}
	local function progress_bucket( id, progress, target )
		if progress == nil or target == nil then
			return nil
		end
		if id == 433 then
			progress = AchievementEngineUtils.GetBitfieldValue( progress )
			target = AchievementEngineUtils.GetBitfieldValue( target )
		end
		progress, target = tonumber( progress ), tonumber( target )
		if not progress or not target or target <= 0 then
			return nil
		end
		return math.floor( 4 * progress / target )
	end

	local function seed_milestones()
		if not Engine.AE_ArePlayerAchievementsFetched( controller ) then
			return
		end
		milestones = {}
		for _, order in ipairs( DwDataUtils._updateChallengeDataByType( controller, GameChallengeGroup.PlayerActive ) ) do
			milestones[order.ID] = progress_bucket( order.ID, order.progress, order.target )
		end
	end

	local function reached_milestone( event )
		if not Engine.AE_ArePlayerAchievementsFetched( controller ) then
			return false
		end
		for _, order in ipairs( DwDataUtils._updateChallengeDataByType( controller, GameChallengeGroup.PlayerActive ) ) do
			if order.ID == event.ID then
				local bucket = progress_bucket( event.ID, event.progress, order.target )
				if not bucket then
					DebugPrint( "[wwz-mod] Skipping Order progress with an invalid target: " .. tostring( event.ID ) )
					return false
				end
				local previous = milestones[event.ID] or 0
				milestones[event.ID] = bucket
				-- Completion has its own notification; do not show a duplicate 100% popup.
				return bucket > previous and bucket > 0 and bucket < 4
			end
		end
		return false
	end

	seed_milestones()
	DebugPrint( "[wwz-mod] Order popups limited to 25%, 50%, 75% and completion" )

	-- The stock builder captures its UC actions in these animation callbacks.
	-- Wrap the callbacks on this widget, keeping its layout and display logic.
	local showing = widget.ChallengeDesc.sequences.NotificationShowingFast[1]
	local animate_out = widget.ChallengeDesc.sequences.AnimateOut[1]
	local stock_display_unlock = showing[#showing]
	local stock_animate_out = animate_out[#animate_out]

	local function prepare_completion( event )
		if event and event.eventType == AEEventType.AchievementClaimable and event.ID ~= nil
			and event.kind ~= GameChallengeType.GameAchievementKind_AlwaysOn
			and event.kind ~= GameChallengeType.GameAchievementKind_Community then
			-- Stock rejects completion if no earlier progress popup supplied a title.
			DataSources.Shared.MP.PeriodicChallengeProgress.challengeDescription:SetValue(
				controller, AchievementEngineUtils.GetTitleByID( event.ID ) )
		end
	end

	local function drain_queue()
		widget._challengeLock = false
		widget._currentEventIndex = 1
		ACTIONS.AnimateSequence( widget, "HideImmediate" )
		if not Engine.AE_ArePlayerAchievementsFetched( controller ) then
			-- A full fetch clears the native cache. Keep the pending events until
			-- PlayerAchievementsFetched, but let the current popup disappear.
			return
		end

		while #widget._challengeArray > 0 and not widget._challengeLock do
			-- Missing/expired targets can make the stock action return without
			-- displaying anything. Continue to the next event in that case.
			prepare_completion( widget._challengeArray[1] )
			stock_animate_out()
		end
	end

	showing[#showing] = function ()
		-- The stock action consumes a same-Order update even if its display
		-- helper rejects it. Schedule the normal fade-out first so that early
		-- return cannot strand the popup. Valid updates replace this sequence.
		ACTIONS.AnimateSequence( widget, "NotificationShowing" )
		if Engine.AE_ArePlayerAchievementsFetched( controller ) then
			stock_display_unlock()
		end
		return nil
	end

	animate_out[#animate_out] = function ()
		drain_queue()
		return nil
	end

	widget:registerEventHandler( "achievementEngine", function ( element, event )
		if event.eventType == AEEventType.PlayerAchievementsFetched and event.success then
			seed_milestones()
		end
		local notification = event.eventType == AEEventType.ProgressionUpdate
			or event.eventType == AEEventType.AchievementClaimable
		if notification and event.kind ~= GameChallengeType.GameAchievementKind_AlwaysOn
			and event.kind ~= GameChallengeType.GameAchievementKind_Community then
			if event.eventType == AEEventType.ProgressionUpdate and not reached_milestone( event ) then
				return
			end
			-- Keep only the newest milestone, or completion, for an Order waiting to display.
			for index = #widget._challengeArray, 1, -1 do
				local pending = widget._challengeArray[index]
				if pending.ID == event.ID and pending.eventType == AEEventType.ProgressionUpdate then
					table.remove( widget._challengeArray, index )
				end
			end
			widget._currentEventIndex = 1
			DebugPrint( "[wwz-mod] Showing Order milestone/completion: " .. tostring( event.ID ) )
			if not Engine.AE_ArePlayerAchievementsFetched( controller )
				or ( not widget._challengeLock and #widget._challengeArray > 0 ) then
				table.insert( widget._challengeArray, event )
				if not widget._challengeLock then
					drain_queue()
				end
				return
			end
		end

		if not widget._challengeLock then
			prepare_completion( event )
		end
		stock_event( element, event )
		if event.eventType == AEEventType.PlayerAchievementsFetched and event.success
			and not widget._challengeLock and #widget._challengeArray > 0 then
			drain_queue()
		end
	end )
	return widget
end

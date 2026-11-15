#pragma once

#include <cstdint>
#include <optional>

namespace demonware::reward_game_events
{
	struct event;
}

namespace hidden_challenges
{
	bool get_completion(const demonware::reward_game_events::event& event,
		std::uint32_t& group, std::uint32_t& challenge);
	void submit_completion(std::uint32_t group, std::uint32_t challenge);
	// The local profile's completed challenges in a hidden character group (bit n is
	// challenge n), including completions waiting to be saved; empty while unavailable.
	std::optional<std::uint16_t> get_owned_challenges(std::uint32_t group);
	void submit_reward_game_event(demonware::reward_game_events::event event);
}

#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>

namespace zombies_objective_outlines
{
	namespace
	{
		const game::dvar_t* objective_outlines;

		int get_outline_style(const game::mp::playerState_s* player, const int slot)
		{
			const auto style = utils::hook::invoke<int>(0x23AA10_g, player, slot);
			// The server encodes script color 0 (locks, fuses and pickups) as 1.
			// A negative result skips both its outline and the ADS fallback at this call site.
			return style == 1 && !objective_outlines->current.enabled ? -1 : style;
		}
	}

	class component final : public generic_component
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::uses_multiplayer_binary() || game::environment::is_dedicated())
			{
				return;
			}
			objective_outlines = game::Dvar_RegisterBool("wwz_zm_objective_outlines", true, game::DVAR_FLAG_SAVED);
			if (!game::environment::is_zombies())
			{
				return;
			}

			auto* call = reinterpret_cast<std::uint8_t*>(0x3E9C5F_g);
			if (!objective_outlines || *call != 0xE8 || utils::hook::follow_branch(call) != reinterpret_cast<void*>(0x23AA10_g))
			{
				console::error("[Objective Outlines] Could not install the Zombies outline preference.\n");
				return;
			}

			utils::hook::call(call, get_outline_style);
			console::debug("[Objective Outlines] Enabled per-client control of white objective outlines.\n");
		}
	};
}

REGISTER_COMPONENT(zombies_objective_outlines::component)

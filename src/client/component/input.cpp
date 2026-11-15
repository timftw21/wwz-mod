#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console/console.hpp"
#include "game_console.hpp"
#include "pause_coop.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

namespace input
{
	namespace
	{
		utils::hook::detour cl_char_event_hook;
		utils::hook::detour cl_key_event_hook;

		void cl_char_event_stub(const int local_client_num, const int key)
		{
			if (!game_console::console_char_event(local_client_num, key))
			{
				return;
			}

			cl_char_event_hook.invoke<void>(local_client_num, key);
		}

		bool is_cinematic_skip_key(const int key)
		{
			// The native key-name table maps KP_ENTER to 0xC0, unlike keyNum_t's approximation.
			constexpr auto keypad_enter = 0xC0;
			return key == game::K_SPACE || key == game::K_ENTER || key == keypad_enter || key == game::K_MOUSE1;
		}

		// Mirrors CL_KeyEvent's Escape case for the active connection state (0x45DF0E), which ends a
		// skippable loading cinematic, such as a Zombies map intro, before it would open the pause menu.
		bool skip_loading_cinematic(const int local_client_num, const int key, const int down)
		{
			// The Escape case indexes these tables by local client; PC play only uses the first.
			if (!down || local_client_num != 0 || !is_cinematic_skip_key(key) || !game::environment::is_zombies())
			{
				return false;
			}

			// clientUIActive_t begins with keyCatchers and connectionState; state 10 is in-game.
			const auto* ui_active = reinterpret_cast<const int*>(0x1BAF4E0_g);
			// Console, message, UI and LUI catchers take Escape before that case.
			if ((ui_active[0] & 0x78) != 0 || ui_active[1] != 10)
			{
				return false;
			}

			if (utils::hook::invoke<bool>(0x910400_g, local_client_num) ||
				*reinterpret_cast<const std::uint8_t*>(0x1BD3CF8_g + local_client_num) ||
				(*reinterpret_cast<const std::uint8_t*>(0x1BD36F8_g) && !utils::hook::invoke<bool>(0xB8C40_g)) ||
				// A playing cinematic whose name contains "_load" and that permits skipping.
				!utils::hook::invoke<bool>(0x86F430_g))
			{
				return false;
			}

			utils::hook::invoke<void>(0x86F810_g, true);
			utils::hook::invoke<void>(0x870200_g);
			console::info("Skipped the loading cinematic with key %d.\n", key);
			return true;
		}

		void cl_key_event_stub(const int local_client_num, const int key, const signed int down, const int arg4)
		{
			if (!game_console::console_key_event(local_client_num, key, down))
			{
				return;
			}

			// Escape stays native; the other skip keys must not also reach their game bindings.
			if (skip_loading_cinematic(local_client_num, key, down))
			{
				return;
			}

			const auto catchers_before = *game::keyCatchers;
			cl_key_event_hook.invoke<void>(local_client_num, key, down, arg4);
			pause::coop::key_event(local_client_num, key, down, catchers_before);
		}
	}

	class component final : public generic_component
	{
	public:
		void post_unpack() override
		{
			cl_char_event_hook.create(game::select(0x45D960, 0x2656F0), cl_char_event_stub);
			cl_key_event_hook.create(game::select(0x45DBC0, 0x265970), cl_key_event_stub);
		}
	};
}

REGISTER_COMPONENT(input::component)

#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>

namespace final_reich
{
	namespace
	{
		struct primary_light
		{
			std::uint8_t type;
			char pad0[3];
			std::uint32_t id;
			char pad1[0x88];
			float airlight_distance_squared;
			char pad2[0x14];
		};

		struct com_world
		{
			const char* name;
			char pad[8];
			std::uint32_t light_count;
			primary_light* lights;
		};

		static_assert(offsetof(com_world, lights) == 0x18);
		static_assert(offsetof(primary_light, airlight_distance_squared) == 0x90);
		static_assert(sizeof(primary_light) == 0xA8);

		void limit_bunker_glow(const com_world& world)
		{
			// The two point lights on the medical-room puzzle controller. The closest
			// street surfaces are 165 and 170 units from their respective fog origins.
			constexpr std::uint32_t bulb_ids[] = {0x5E7C17DB, 0x14C98C57};
			constexpr float stock_distance = 605.0f;
			constexpr float room_distance = 160.0f;

			unsigned matched = 0;
			for (std::uint32_t i = 0; world.lights && i < world.light_count; ++i)
			{
				auto& light = world.lights[i];
				if (light.type != 3 || (light.id != bulb_ids[0] && light.id != bulb_ids[1]))
				{
					continue;
				}

				// R_InitPrimaryLights (0x86A585) copies this to GfxLight + 0x94.
				// The airlight pass (0x8B796C) compares it with squared eye distance.
				if (light.airlight_distance_squared == stock_distance * stock_distance ||
					light.airlight_distance_squared == room_distance * room_distance)
				{
					light.airlight_distance_squared = room_distance * room_distance;
					++matched;
				}
			}

			if (matched)
			{
				console::debug("[Final Reich] Limited fog glow below the workshop barricade on %u bulb(s).\n", matched);
			}
			if (matched != std::size(bulb_ids))
			{
				console::warn("[Final Reich] Expected two stock bunker fog lights, matched %u.\n", matched);
			}
		}

		void load_com_world_asset(com_world** asset)
		{
			const auto* world = *asset;
			if (world && world->name && std::string_view(world->name) == "maps/mp/mp_zombie_nest_01.d3dbsp")
			{
				limit_bunker_glow(*world);
			}
			utils::hook::invoke<void>(0xD81F0_g, asset);
		}
	}

	class component final : public generic_component
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_zombies() || game::environment::is_dedicated())
			{
				return;
			}

			// Both inline-asset paths in Load_ComWorldPtr, after the light array
			// is loaded and before the database publishes the asset.
			const std::uintptr_t calls[] = {0x4AA7EA_g, 0x4AA80D_g};
			for (const auto site : calls)
			{
				auto* call = reinterpret_cast<std::uint8_t*>(site);
				if (*call != 0xE8 || utils::hook::follow_branch(call) != reinterpret_cast<void*>(0xD81F0_g))
				{
					console::error("[Final Reich] Unexpected ComWorld loader. Workshop lighting fix skipped.\n");
					return;
				}
			}
			for (const auto site : calls)
			{
				utils::hook::call(site, load_com_world_asset);
			}
		}
	};
}

REGISTER_COMPONENT(final_reich::component)

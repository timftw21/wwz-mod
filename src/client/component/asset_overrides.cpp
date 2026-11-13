#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console/console.hpp"
#include "prompt_text.hpp"
#include "zombies_subtitle_text.hpp"

#include <utils/hook.hpp>

namespace asset_overrides
{
	namespace
	{
		constexpr std::string_view override_prefix = "override/";

		utils::hook::detour db_find_xasset_header_hook;

		std::mutex logged_mutex;
		std::unordered_set<std::string> logged_names;

		// S2 FX layout: Load_FxEffectDef (0x4AC960) and Load_FxElemDef (0x4ACC20).
		// Both installed maps contain the same two-element lantern effect.
		struct fx_visual_state
		{
			float color[4];
			float emissive[3];
			char remaining[0x20];
		};

		struct fx_visual_sample
		{
			fx_visual_state base;
			fx_visual_state amplitude;
		};

		struct fx_element
		{
			char prefix[0xBC];
			std::uint8_t type;
			char counts[3];
			std::uint8_t visual_intervals;
			char padding[0xF];
			fx_visual_sample* samples;
			char remaining[0x90];
		};

		struct fx_effect
		{
			const char* name;
			char prefix[0xC];
			int looping_count;
			int oneshot_count;
			int emission_count;
			char remaining[0x20];
			fx_element* elements;
		};

		static_assert(sizeof(fx_visual_state) == 0x3C && sizeof(fx_visual_sample) == 0x78);
		static_assert(offsetof(fx_element, samples) == 0xD0 && sizeof(fx_element) == 0x168);
		static_assert(offsetof(fx_effect, elements) == 0x40 && sizeof(fx_effect) == 0x48);

		void brighten_lantern_glow(void* asset)
		{
			const auto* map = game::Dvar_FindMalleableVar("mapname");
			if (!map || !map->current.string || (std::string_view(map->current.string) != "mp_zombie_training" &&
				std::string_view(map->current.string) != "mp_zombie_house"))
			{
				return;
			}

			const auto* effect = static_cast<fx_effect*>(asset);
			if (!effect || !effect->name || std::string_view(effect->name) != "vfx/map/mp_zombie_training/zmb_ee_lamp_glow" ||
				effect->looping_count != 2 || effect->oneshot_count || effect->emission_count || !effect->elements ||
				effect->elements[0].type != 0 || effect->elements[0].visual_intervals != 4 || !effect->elements[0].samples)
			{
				console::warn("[wwz-mod] Lantern brightness skipped: unexpected FX definition.\n");
				return;
			}

			std::lock_guard _(logged_mutex);
			auto* samples = effect->elements[0].samples;
			// Only the purple glow: the second element is heat distortion. Absolute values
			// make repeated lookups/reloads safe, without retaining pointers to zone memory.
			constexpr float stock_emissive = 19.5f;
			constexpr float brighter_emissive = stock_emissive * 12.0f;
			for (auto i = 0; i < 5; ++i)
			{
				for (const auto* state : {&samples[i].base, &samples[i].amplitude})
				{
					for (const auto value : state->emissive)
					{
						if (value != stock_emissive && value != brighter_emissive)
						{
							console::warn("[wwz-mod] Lantern brightness skipped: custom FX emission curve.\n");
							return;
						}
					}
				}
			}

			if (samples[0].base.emissive[0] == brighter_emissive)
			{
				return;
			}
			for (auto i = 0; i < 5; ++i)
			{
				for (auto* state : {&samples[i].base, &samples[i].amplitude})
				{
					std::fill(std::begin(state->emissive), std::end(state->emissive), brighter_emissive);
				}
			}
			console::debug("[wwz-mod] Increased %s purple lantern glow emission twelvefold.\n", map->current.string);
		}

		void log_redirect(const char* name, const std::string& override_name)
		{
			std::lock_guard _(logged_mutex);
			if (logged_names.emplace(name).second)
			{
				console::info("[override] %s -> %s\n", name, override_name.data());
			}
		}

		game::LocalizeEntry* format_scavenging_notification(game::LocalizeEntry* entry)
		{
			if (!entry || !entry->name || !entry->value)
			{
				return entry;
			}

			static game::LocalizeEntry ammo{"Scavenged Ammo", "ZOMBIES_NOTIFICATION_MESSAGE_HEAVY_MELEE_AMMO"};
			static game::LocalizeEntry lethal{"Scavenged Lethal Equipment", "ZOMBIES_NOTIFICATION_MESSAGE_HEAVY_MELEE_LETHAL"};
			const std::string_view name{entry->name};
			const std::string_view value{entry->value};
			if (name == ammo.name && value == "Scavenged some ammo.")
			{
				return &ammo;
			}
			if (name == lethal.name && value == "Scavenged some lethal equipment.")
			{
				return &lethal;
			}
			return entry;
		}

		game::XAssetHeader db_find_xasset_header_stub(const game::XAssetType type, const char* name, const int allow_create_default)
		{
			if (type == game::ASSET_TYPE_RAWFILE && name && !std::string_view(name).starts_with(override_prefix))
			{
				const auto override_name = std::string(override_prefix) + name;

				if (game::DB_XAssetExists(type, override_name.data()) &&
					!game::DB_IsXAssetDefault(type, override_name.data()))
				{
					const auto header = db_find_xasset_header_hook.invoke<game::XAssetHeader>(type, override_name.data(), 0);
					if (header.rawfile)
					{
						log_redirect(name, override_name);
						return header;
					}
				}
			}

			auto header = db_find_xasset_header_hook.invoke<game::XAssetHeader>(type, name, allow_create_default);
			if (type == game::ASSET_TYPE_FX && name &&
				std::string_view(name) == "vfx/map/mp_zombie_training/zmb_ee_lamp_glow" &&
				game::environment::is_zombies() && !game::environment::is_dedicated())
			{
				brighten_lantern_glow(header.data);
			}
			if (type == game::ASSET_TYPE_LOCALIZE && game::environment::uses_multiplayer_binary() &&
				!game::environment::is_dedicated())
			{
				// Scripted hold hints resolve assets directly, alongside the regular text lookup.
				header.localize = prompt_text::format_entry(header.localize);
				if (game::environment::is_zombies())
				{
					header.localize = format_scavenging_notification(header.localize);
					header.localize = zombies_subtitle_text::format_entry(header.localize);
				}
			}
			return header;
		}
	}

	class component final : public generic_component
	{
	public:
		void post_unpack() override
		{
			db_find_xasset_header_hook.create(game::DB_FindXAssetHeader, db_find_xasset_header_stub);
			console::debug("Installed asset-level interaction prompt formatting.\n");
			if (game::environment::is_zombies() && !game::environment::is_dedicated())
			{
				console::debug("Installed English Zombies subtitle and scavenging text corrections.\n");
			}
		}
	};
}

REGISTER_COMPONENT(asset_overrides::component)

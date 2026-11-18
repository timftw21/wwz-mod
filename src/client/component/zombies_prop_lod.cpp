#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "game/types/rendering.hpp"
#include "console/console.hpp"

#include <cmath>
#include <utils/hook.hpp>

namespace zombies_prop_lod
{
	namespace
	{
		void correct_prop_lods(game::XModel& model)
		{
			const int count = model.lod_count;
			if (!model.use_lod_distances || count < 3 || count > static_cast<int>(std::size(model.lods)) || !model.name)
			{
				return;
			}

			// Zombies map props use prefixes such as zmb_, zmi_, zmd_ and zmw_.
			const std::string_view name = model.name;
			if (name.size() < 4 || !name.starts_with("zm") || name[3] != '_')
			{
				return;
			}

			int first = count;
			while (first > 0 && model.lods[first - 1].surface_count == 1)
			{
				--first;
			}
			// Keep the first authored switch as a reference for single-material props.
			first = std::max(first, 2);
			if (first == count)
			{
				return;
			}

			// The native selector at 0x7E7950 compares area per triangle with
			// squared distance. Measure the largest apparent triangle at entry
			// to an earlier LOD using this prop's own authored distances.
			double max_projected_area = 0.0;
			for (int lod = 1; lod < first; ++lod)
			{
				const double distance = model.lods[lod - 1].distance;
				const double area = model.lod_triangle_area[lod];
				if (!(distance > 0 && area > 0) || !std::isfinite(distance) || !std::isfinite(area))
				{
					return;
				}
				max_projected_area = std::max(max_projected_area, area / (distance * distance));
			}

			// Work back from the farthest mesh so adjacent cutoffs stay ordered.
			for (int lod = count - 1; lod >= first; --lod)
			{
				auto& distance = model.lods[lod - 1].distance;
				const auto corrected = static_cast<float>(std::sqrt(model.lod_triangle_area[lod] / max_projected_area));
				if (corrected > distance && corrected < model.lods[lod].distance)
				{
					console::debug("[Prop LOD] %s: LOD %d starts at %.0f (was %.0f).\n",
						model.name, lod, corrected, distance);
					distance = corrected;
				}
			}
		}

		void load_model(game::XModel** asset)
		{
			if (*asset)
			{
				correct_prop_lods(**asset);
			}
			utils::hook::invoke<void>(0xDB440_g, asset);
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

			// Both inline loads of the 0x378-byte model, before DB registration.
			const std::uintptr_t calls[] = {0x4C75FA_g, 0x4C761D_g};
			for (const auto site : calls)
			{
				auto* call = reinterpret_cast<std::uint8_t*>(site);
				if (*call != 0xE8 || utils::hook::follow_branch(call) != reinterpret_cast<void*>(0xDB440_g))
				{
					console::error("[Prop LOD] Unexpected model loader. Skipped Zombies prop corrections.\n");
					return;
				}
			}
			for (const auto site : calls)
			{
				utils::hook::call(site, load_model);
			}
		}
	};
}

REGISTER_COMPONENT(zombies_prop_lod::component)

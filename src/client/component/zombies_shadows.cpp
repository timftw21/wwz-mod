#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>

namespace zombies_shadows
{
	namespace
	{
		template <typename T>
		T field(const std::byte* base, const size_t offset)
		{
			T value;
			std::memcpy(&value, base + offset, sizeof(value));
			return value;
		}

		// The frontend builds a scene per local client. Camera workers read the
		// pose recorded for that scene. Shadow workers use their stock draw path.
		std::array<std::atomic<const std::byte*>, game::LOCAL_CLIENT_COUNT> shadow_poses{};
		thread_local std::atomic<const std::byte*>* checking_local_body = nullptr;

		int should_submit_body(const int local_client, const int pose_only)
		{
			if (static_cast<unsigned>(local_client) >= shadow_poses.size())
			{
				return utils::hook::invoke<int>(0x42B4F0_g, local_client, pose_only);
			}

			auto& pose = shadow_poses[local_client];
			pose.store(nullptr, std::memory_order_relaxed);
			checking_local_body = &pose;
			const auto result = utils::hook::invoke<int>(0x42B4F0_g, local_client, pose_only);
			checking_local_body = nullptr;
			return result;
		}

		bool include_first_person_body(const std::byte* cg)
		{
			// This is the final camera check, after the engine has validated the
			// DObj, entity flags and third-person modes. Preserve pose-only views.
			if (utils::hook::invoke<bool>(0x38B810_g, cg))
			{
				return true;
			}
			if (!checking_local_body || field<unsigned char>(cg, 2) >= 5 || field<std::uint8_t>(cg, 0x439EB8) || game::virtual_lobby_loaded())
			{
				return false;
			}
			const auto* pose = field<const std::byte*>(cg, 0x5940);
			if (!pose || field<unsigned char>(pose, 0x49A) != 1 ||
				field<short>(pose, 0x490) != field<signed char>(cg, 0))
			{
				return false;
			}

			checking_local_body->store(pose, std::memory_order_relaxed);
			static std::once_flag logged;
			std::call_once(logged, [] { console::debug("[Shadows] Submitted the first-person character for shadows.\n"); });
			return true;
		}

		int has_camera_surfaces(const std::byte* scene_entity)
		{
			// R_BeginScene sets this client number. R_AddDObjToScene stores the
			// original pose at +0x120, including when submissions are queued.
			const auto client = *reinterpret_cast<const unsigned*>(0x14DA3A8_g);
			if (client < shadow_poses.size())
			{
				const auto* pose = shadow_poses[client].load(std::memory_order_relaxed);
				if (pose && pose == field<const std::byte*>(scene_entity, 0x120))
				{
					return 0;
				}
			}
			return utils::hook::invoke<int>(0x1A3C10_g, scene_entity);
		}

		struct scene_light
		{
			std::uint8_t type;
			std::uint8_t casts_shadows;
			std::byte pad[0x2E];
			float origin[3];
			float radius;
			std::byte tail[0x70];
		};
		static_assert(offsetof(scene_light, origin) == 0x30);
		static_assert(offsetof(scene_light, radius) == 0x3C);
		static_assert(sizeof(scene_light) == 0xB0);

		void select_spot_shadows(std::byte* scene, const unsigned* visible, const unsigned* moving,
			const std::byte* view)
		{
			// The native selector reads ceil(light_count / 32) words. Work on a
			// private mask so offscreen lights stay culled from the lighting pass.
			std::array<unsigned, 0x104 / sizeof(unsigned)> candidates;
			const auto count = field<unsigned>(view, 0x1D8);
			if (count <= candidates.size() * 32)
			{
				std::copy_n(visible, (count + 31) / 32, candidates.begin());
				const auto eye = field<std::array<float, 3>>(view, 0x100);
				const auto* lights = reinterpret_cast<const scene_light*>(scene + 0xC8FA00);
				// These are the same resident slots the engine visits to associate
				// a moving character with local shadow lights (0x8B7189).
				const auto* slots = utils::hook::invoke<const std::byte*>(0x8F81B0_g, scene);
				const auto slots_count = utils::hook::invoke<unsigned>(0x8F8290_g, scene);
				for (unsigned i = 0; slots && i < slots_count; ++i)
				{
					const auto index = field<unsigned>(slots + i * 0xB0, 0x80);
					if (index >= count || (candidates[index / 32] & (1u << (index % 32))))
					{
						continue;
					}
					const auto& light = lights[index];
					if (!light.casts_shadows || (light.type != 2 && light.type != 3))
					{
						continue;
					}
					const auto delta_x = eye[0] - light.origin[0];
					const auto delta_y = eye[1] - light.origin[1];
					const auto delta_z = eye[2] - light.origin[2];
					if (light.radius > 0 && delta_x * delta_x + delta_y * delta_y + delta_z * delta_z < light.radius * light.radius)
					{
						candidates[index / 32] |= 1u << (index % 32);
					}
				}
				visible = candidates.data();
			}
			utils::hook::invoke<void>(0x8B54F0_g, scene, visible, moving, view);
		}

		bool calls(const std::uintptr_t site, const std::uintptr_t target)
		{
			auto* call = reinterpret_cast<std::uint8_t*>(site);
			return *call == 0xE8 && utils::hook::follow_branch(call) == reinterpret_cast<void*>(target);
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
			if (calls(0x698D3_g, 0x42B4F0_g) && calls(0x42B58D_g, 0x38B810_g) && calls(0x875222_g, 0x1A3C10_g))
			{
				utils::hook::call(0x875222_g, has_camera_surfaces);
				utils::hook::call(0x42B58D_g, include_first_person_body);
				utils::hook::call(0x698D3_g, should_submit_body);
				console::debug("[Shadows] Enabled first-person character shadows.\n");
			}
			else
			{
				console::error("[Shadows] Unexpected character renderer. Skipped first-person shadows.\n");
			}

			// R_ScoreSpotLight normally measures from a point projected along the
			// camera axis. Score from the eye so turning in place keeps distances stable.
			constexpr std::uint8_t load_projection[] = {0xF3, 0x0F, 0x10, 0x2D, 0x68, 0x5E, 0xC2, 0x00};
			constexpr std::uint8_t zero_projection[] = {0x0F, 0x57, 0xED, 0x0F, 0x1F, 0x44, 0x00, 0x00};
			if (calls(0xECCBD_g, 0x8B54F0_g) &&
				std::memcmp(reinterpret_cast<void*>(0x8B51CC_g), load_projection, sizeof(load_projection)) == 0)
			{
				utils::hook::copy(0x8B51CC_g, zero_projection, sizeof(zero_projection));
				utils::hook::call(0xECCBD_g, select_spot_shadows);
				console::debug("[Shadows] Enabled position-based spotlight selection and nearby shadow retention.\n");
			}
			else
			{
				console::error("[Shadows] Unexpected spotlight selector. Skipped nearby shadow retention.\n");
			}
		}
	};
}

REGISTER_COMPONENT(zombies_shadows::component)

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

		constexpr unsigned spot_shadow_distance_scale = 16;

		void setup_shadow_settings(std::byte* scene, std::byte* view, const std::byte* settings)
		{
			utils::hook::invoke<void>(0xEC0A0_g, scene, view, settings);

			// Raising every light's score still leaves the same nearest lights on top.
			// Allow more of them to cast and refresh shadows within the selector's
			// native limits (0x8B5520 and 0x8B554A). Zero still disables a budget.
			constexpr unsigned budget_scale = 4;
			auto& priority = *reinterpret_cast<unsigned*>(view + 0x1C44);
			auto& updates = *reinterpret_cast<unsigned*>(view + 0x1C50);
			priority = std::min(std::min(priority, 16u) * budget_scale, 16u);
			updates = std::min(std::min(updates, 8u) * budget_scale, 8u);
		}

		void* scaled_distance_stub(const asmjit::x86::Vec result)
		{
			// XMM2 holds squared distance. Preserve the other registers and flags:
			// the prop renderer branches on a comparison made before the square root.
			return utils::hook::assemble([result](utils::hook::assembler& a)
			{
				const auto inverse_scale = a.new_label();
				a.sqrtss(result, xmm2);
				a.mulss(result, dword_ptr(inverse_scale));
				a.ret();
				a.bind(inverse_scale);
				a.embed_float(1.0f / spot_shadow_distance_scale);
			});
		}

		std::array<float, 3> scaled_volume_eye(const float* origin, const float* eye)
		{
			std::array<float, 3> scaled;
			for (size_t i = 0; i < scaled.size(); ++i)
			{
				scaled[i] = origin[i] + (eye[i] - origin[i]) / spot_shadow_distance_scale;
			}
			return scaled;
		}

		bool cull_spot_volume(const std::byte* primary_light, const float* eye, const float margin)
		{
			const auto* origin = reinterpret_cast<const float*>(primary_light + 0x34);
			const auto scaled = scaled_volume_eye(origin, eye);
			return utils::hook::invoke<bool>(0x8B4EE0_g, primary_light, scaled.data(), margin);
		}

		bool cull_spot_hulls(const void* hulls, const float* origin, const float* eye, const float margin)
		{
			const auto scaled = scaled_volume_eye(origin, eye);
			return utils::hook::invoke<bool>(0x8B6090_g, hulls, origin, scaled.data(), margin);
		}

		void select_spot_shadows(std::byte* scene, const unsigned* visible, const unsigned* moving,
			const std::byte* view)
		{
			// The native selector reads ceil(light_count / 32) words. Work on a
			// private mask so offscreen lights stay culled from the lighting pass.
			constexpr unsigned max_scene_lights = 0x819; // First invalid light in the native cache lookup tables.
			std::array<unsigned, (max_scene_lights + 31) / 32> candidates;
			const auto count = field<unsigned>(view, 0x1D8);
			if (count <= max_scene_lights)
			{
				std::copy_n(visible, (count + 31) / 32, candidates.begin());
				const auto eye = field<std::array<float, 3>>(view, 0x100);
				const auto* lights = reinterpret_cast<const scene_light*>(scene + 0xC8FA00);
				// A light can enter shadow range before it has a cache slot. The
				// scorer still enforces the world's light visibility and shadow flags.
				for (unsigned index = 0; index < count; ++index)
				{
					if (candidates[index / 32] & (1u << (index % 32)))
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
					const float range = light.radius * spot_shadow_distance_scale;
					if (range > 0 && delta_x * delta_x + delta_y * delta_y + delta_z * delta_z < range * range)
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

			// Static-model submission, cached-model validation and dynamic-light
			// submission each measure the camera distance independently.
			const std::uintptr_t caster_sites[] = {0x86541D_g, 0x86635D_g, 0x864216_g};
			constexpr std::uint8_t distance_code[] = {0xF3, 0x0F, 0x10, 0xF2, 0xF3, 0x0F, 0x51, 0xF6};
			for (const auto site : caster_sites)
			{
				if (std::memcmp(reinterpret_cast<const void*>(site), distance_code, sizeof(distance_code)) != 0)
				{
					console::error("[Shadows] Unexpected spotlight caster distance check. Skipped spotlight changes.\n");
					return;
				}
			}

			// Keep the stock beam center for ranking, with no offset along the camera
			// axis. Scaling the eye about the lamp origin here would move that center.
			constexpr std::uint8_t camera_projection[] = {0xF3, 0x0F, 0x10, 0x2D, 0x68, 0x5E, 0xC2, 0x00};
			constexpr std::uint8_t zero_projection[] = {0x0F, 0x57, 0xED, 0x0F, 0x1F, 0x44, 0x00, 0x00};
			constexpr std::uint8_t score_distance[] = {0xF3, 0x44, 0x0F, 0x51, 0xC2};
			if (!calls(0x6A849_g, 0xEC0A0_g) || !calls(0xECCBD_g, 0x8B54F0_g) ||
				!calls(0x8B53D7_g, 0x8B4EE0_g) || !calls(0x8B5407_g, 0x8B6090_g) ||
				std::memcmp(reinterpret_cast<const void*>(0x8B51CC_g), camera_projection, sizeof(camera_projection)) ||
				std::memcmp(reinterpret_cast<const void*>(0x8B52C6_g), score_distance, sizeof(score_distance)))
			{
				console::error("[Shadows] Unexpected spotlight selector or settings. Skipped spotlight changes.\n");
				return;
			}

			auto* caster_distance = scaled_distance_stub(xmm6);
			auto* beam_distance = scaled_distance_stub(xmm8);
			if (!caster_distance || !beam_distance)
			{
				console::error("[Shadows] Could not create spotlight distance hooks.\n");
				return;
			}
			for (const auto site : caster_sites)
			{
				utils::hook::call(site, caster_distance);
				utils::hook::nop(site + 5, sizeof(distance_code) - 5);
			}
			utils::hook::copy(0x8B51CC_g, zero_projection, sizeof(zero_projection));
			utils::hook::call(0x8B52C6_g, beam_distance);
			utils::hook::call(0x8B53D7_g, cull_spot_volume);
			utils::hook::call(0x8B5407_g, cull_spot_hulls);
			utils::hook::call(0x6A849_g, setup_shadow_settings);
			utils::hook::call(0xECCBD_g, select_spot_shadows);
			console::info("[Shadows] Enabled %ux spotlight selection and caster draw distance.\n", spot_shadow_distance_scale);
		}
	};
}

REGISTER_COMPONENT(zombies_shadows::component)

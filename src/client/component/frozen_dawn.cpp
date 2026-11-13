#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>

#include <atomic>
#include <cmath>

namespace frozen_dawn
{
	namespace
	{
		constexpr std::string_view blood_screen = "vfx/map/mp_zombie_descent/zmb_desc_bloodtube_screen";
		constexpr std::string_view charged_scythe = "vfx/zombie/rvn_weapons/zmb_death_scythe_charged";

		struct effect_definition
		{
			const char* name;
		};

		struct effect_instance
		{
			const effect_definition* definition;
		};

		struct effect_element
		{
			std::uint32_t flags;
		};

		// MP FX draw state, verified in 0x4E7B70 (billboards), 0x4EA7D0
		// (camera), 0x4EC3B0 (culling), and 0x4EB760 (quad submission).
		struct effect_camera
		{
			float origin[3];
			char padding[0x64];
			float forward[3];
		};

		struct effect_draw_state
		{
			char prefix[0x48];
			const effect_instance* effect;
			void* particle;
			const effect_element* element;
			void* draw_buffer;
			const effect_camera* camera;
			char padding[0x48];
			float origin[3];
			char visual_state[0x34];
			float size[2];
		};

		static_assert(offsetof(effect_camera, forward) == 0x70);
		static_assert(offsetof(effect_draw_state, element) == 0x58);
		static_assert(offsetof(effect_draw_state, camera) == 0x68);
		static_assert(offsetof(effect_draw_state, origin) == 0xB8);
		static_assert(offsetof(effect_draw_state, size) == 0xF8);

		bool named_effect(const effect_definition* definition, const std::string_view name)
		{
			return definition && definition->name && name == definition->name;
		}

		void keep_blood_in_front_of_near_plane(effect_draw_state* state)
		{
			if (!state->effect || !named_effect(state->effect->definition, blood_screen) ||
				!state->element || (state->element->flags & 0x1C0) != 0x100 ||
				!state->camera || !game::environment::is_zombies())
			{
				return;
			}

			// 0x4EAD60 scales camera-relative FX depth by tan(65/2)/tan(FOV/2).
			// The blood starts just 5 units away; PC FOV can push it behind r_znear.
			// Scale the completed quad about the eye, preserving its screen footprint,
			// animation and FOV compensation, before native culling and submission.
			const auto near_plane = game::Dvar_GetFloat("r_znear");
			float offset[3];
			float depth = 0.0f;
			for (auto i = 0; i < 3; ++i)
			{
				offset[i] = state->origin[i] - state->camera->origin[i];
				depth += offset[i] * state->camera->forward[i];
			}
			if (!std::isfinite(near_plane) || near_plane <= 0.0f || !std::isfinite(depth) || depth <= 0.0f)
			{
				static std::atomic_bool warned{};
				if (!warned.exchange(true))
				{
					console::warn("[Frozen Dawn] Blood overlay correction skipped: invalid camera depth or near plane.\n");
				}
				return;
			}

			const auto safe_depth = near_plane + std::max(0.01f, near_plane * 0.01f);
			if (depth >= safe_depth)
			{
				return;
			}
			const auto scale = safe_depth / depth;
			for (auto i = 0; i < 3; ++i)
			{
				state->origin[i] = state->camera->origin[i] + offset[i] * scale;
			}
			for (auto& size : state->size)
			{
				size *= scale;
			}
			static std::atomic_bool logged{};
			if (!logged.exchange(true))
			{
				console::debug("[Frozen Dawn] Kept teleport blood overlay beyond the camera near plane.\n");
			}
		}

		bool cull_blood_sprite_stub(effect_draw_state* state)
		{
			keep_blood_in_front_of_near_plane(state);
			return utils::hook::invoke<bool>(0x4EC3B0_g, state);
		}

		std::uint32_t linked_effect_flags(const effect_definition* definition, const int bolt_object,
			const std::uint32_t flags)
		{
			// CG's linked-effect handler (0x3EEA80) selects handle 0x800 only for
			// the visible first-person weapon. World/other-player handles stay intact.
			// Unlike FX_PlayBoltedEffect (0x50EEAE), FX_PlayEntityBoltedEffect
			// (0x50FD60) forgets the 0x20000 viewmodel flag passed to sprite batches.
			if (bolt_object != 0x800 || !named_effect(definition, charged_scythe) ||
				!game::environment::is_zombies())
			{
				return flags;
			}
			static std::atomic_bool logged{};
			if (!logged.exchange(true))
			{
				console::debug("[Frozen Dawn] Corrected first-person charged scythe FX projection.\n");
			}
			return flags | 0x20000;
		}

		void linked_effect_flags_stub(utils::hook::assembler& a)
		{
			a.pushad64();
			a.sub(rsp, 0x60);
			for (auto i = 0; i < 6; ++i)
			{
				a.movdqu(xmmword_ptr(rsp, i * 0x10), asmjit::x86::xmm(i));
			}
			a.mov(rcx, rsi);
			a.mov(edx, r15d);
			a.mov(r8d, ebp);
			a.call_aligned(linked_effect_flags);
			// Original instruction: mov [rsp+0xC8], ebp. Save only the corrected
			// spawn flags; retain every register and the engine's remaining arguments.
			a.mov(dword_ptr(rsp, 0x78 + 0x60 + 0xC8), eax);
			for (auto i = 0; i < 6; ++i)
			{
				a.movdqu(asmjit::x86::xmm(i), xmmword_ptr(rsp, i * 0x10));
			}
			a.add(rsp, 0x60);
			a.popad64();
			a.jmp(0x50FE79_g);
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
			constexpr unsigned char cull_call[] = {0xE8, 0x5B, 0x44, 0x00, 0x00};
			constexpr unsigned char flags_store[] = {0x89, 0xAC, 0x24, 0xC8, 0x00, 0x00, 0x00};
			if (std::memcmp(reinterpret_cast<const void*>(0x4E7F50_g), cull_call, sizeof(cull_call)) ||
				std::memcmp(reinterpret_cast<const void*>(0x50FE72_g), flags_store, sizeof(flags_store)))
			{
				console::error("[Frozen Dawn] FX fixes not installed: unexpected engine instructions.\n");
				return;
			}
			utils::hook::call(0x4E7F50_g, cull_blood_sprite_stub);
			utils::hook::jump(0x50FE72_g, utils::hook::assemble(linked_effect_flags_stub));
			utils::hook::nop(0x50FE77_g, 2);
			console::debug("[Frozen Dawn] Installed teleport blood and charged scythe FX corrections.\n");
		}
	};
}

REGISTER_COMPONENT(frozen_dawn::component)

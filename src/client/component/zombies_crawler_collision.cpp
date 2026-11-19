#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "game/types/rendering.hpp"
#include "console/console.hpp"

#include <utils/hook.hpp>

namespace zombies_crawler_collision
{
	namespace
	{
		constexpr unsigned crawler_radius = 12;
		constexpr unsigned crawler_height = 24;

		bool has_crawler_bounds(const std::byte* state)
		{
			// SV_LinkEntity packs radius, bottom + 1 and top + 32 into s.solid.
			constexpr auto solid = crawler_radius | (1u << 8) | ((crawler_height + 32u) << 16);
			return state && state[0xA] == std::byte{0x14} &&
				*reinterpret_cast<const unsigned*>(state + 0x24) == solid;
		}

		void get_character_bounds(const std::byte* entity, game::Bounds* bounds)
		{
			if (has_crawler_bounds(entity + 0x490))
			{
				// Use the same snapshot bounds decoder as the client's ordinary movement trace.
				game::Bounds absolute_bounds{};
				utils::hook::invoke<void>(0x457230_g, entity, bounds, &absolute_bounds);
				static std::once_flag logged;
				std::call_once(logged, [] { console::debug("[Crawler collision] Using crawler bounds for player movement.\n"); });
				return;
			}
			utils::hook::invoke<void>(0x411BC0_g, entity, bounds);
		}

		enum contact { stock, clear, blocking };

		contact crawler_contact(const std::byte* move, const unsigned short id, const float* target, float* radius)
		{
			const auto handler = static_cast<unsigned char>(move[0x204]);
			const auto* state = utils::hook::invoke<const std::byte*>(0x38AB80_g, handler, id);
			if (!has_crawler_bounds(state))
			{
				return stock;
			}

			const auto* ps = *reinterpret_cast<const std::byte* const*>(move);
			const auto& bounds = *reinterpret_cast<const game::Bounds*>(move + 0x194);
			const float center = *reinterpret_cast<const float*>(ps + 0x8C) + bounds.midpoint[2];
			if (center - bounds.half_size[2] >= target[2] + crawler_height ||
				center + bounds.half_size[2] <= target[2])
			{
				return clear;
			}

			*radius = std::min(bounds.half_size[0], bounds.half_size[1]) + crawler_radius;
			return blocking;
		}

		void resolve_character_contact(utils::hook::assembler& a)
		{
			const auto original = a.new_label();
			const auto overlap = a.new_label();
			// PMove has the candidate's origin in its frame and the mover's origin in R15.
			// This is a native call boundary with aligned shadow space.
			a.mov(rcx, rbx);
			a.mov(edx, edi);
			a.lea(r8, ptr(rbp, -0x38));
			a.lea(r9, ptr(rsp, 0x6C));
			a.call(crawler_contact);
			a.test(eax, eax);
			a.jz(original);
			a.cmp(eax, blocking);
			a.je(overlap);
			a.jmp(0x39973F_g); // No vertical overlap. Continue with the next character.

			a.bind(overlap);
			a.movss(xmm6, dword_ptr(rsp, 0x6C));
			a.movss(xmm12, dword_ptr(r15, 8));
			a.movss(dword_ptr(rbp, -0x30), xmm12);
			a.lea(r8, ptr(rbp, -0x38));
			a.lea(rdx, ptr(rbp, -0x28));
			a.jmp(0x39920F_g); // Native horizontal sweep and contact response.

			a.bind(original);
			a.mov(rcx, 0xB6991C_g); // Half-size of the native standing character.
			a.jmp(0x399178_g);
		}
	}

	class component final : public generic_component
	{
	public:
		void post_unpack() override
		{
			if (!game::environment::is_zombies())
			{
				return;
			}

			// Both server movement and client prediction use this standing capsule for every character.
			auto* shape = reinterpret_cast<std::uint8_t*>(0x399171_g);
			const std::uint8_t half_size_load[] = {0x48, 0x8D, 0x0D, 0xA4, 0x07, 0x7D, 0x00};
			if (std::memcmp(shape, half_size_load, sizeof(half_size_load)) != 0)
			{
				console::error("[Crawler collision] Unexpected movement bounds. Skipped character contact change.\n");
				return;
			}
			utils::hook::jump(shape, utils::hook::assemble(resolve_character_contact));
			console::debug("[Crawler collision] Installed character contact bounds.\n");
			if (game::environment::is_dedicated())
			{
				return;
			}

			// The character query in predicted movement otherwise uses standing player bounds for agents.
			auto* call = reinterpret_cast<std::uint8_t*>(0x39081D_g);
			if (*call != 0xE8 || utils::hook::follow_branch(call) != reinterpret_cast<void*>(0x411BC0_g))
			{
				console::error("[Crawler collision] Unexpected character bounds call. Skipped prediction change.\n");
				return;
			}
			utils::hook::call(call, get_character_bounds);
		}
	};
}

REGISTER_COMPONENT(zombies_crawler_collision::component)

#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "console/console.hpp"
#include "scoreboard_ping.hpp"

#include "game/game.hpp"

#include <charconv>

namespace scoreboard_ping
{
	namespace
	{
		constexpr auto request_command = "wwz_scoreping";
		constexpr auto response_command = "$wwz_scoreping";
		constexpr auto max_players = 48;
		constexpr auto max_ping = 999;
		constexpr auto interval = 1s;
		constexpr auto expiry = 3s;
		using clock = std::chrono::steady_clock;

		std::array<clock::time_point, max_players> next_reply{};
		std::array<int, max_players> pings{};
		clock::time_point next_request{};
		clock::time_point received_at{};

		bool playing()
		{
			return game::environment::is_zombies() && !game::virtual_lobby_loaded();
		}

		void reply(const int slot, const command::params_sv& args)
		{
			if (args.size() != 1 || !playing() || !game::SV_Loaded())
			{
				return;
			}

			const auto count = std::clamp(*game::sv_maxclients, 0, max_players);
			auto* clients = *game::mp::svs_clients;
			if (!clients || slot < 0 || slot >= count || clients[slot].state < 5)
			{
				return;
			}

			const auto now = clock::now();
			auto& recipient = clients[slot];
			if (now < next_reply[slot] ||
				static_cast<int64_t>(recipient.reliableSequence) - recipient.reliableAcknowledge >= 64)
			{
				return;
			}
			next_reply[slot] = now + interval;

			std::string response = response_command;
			for (auto i = 0; i < max_players; ++i)
			{
				// State 5 is active. Earlier states have no usable gameplay latency.
				const auto ping = i < count && clients[i].state >= 5 ? clients[i].ping : -1;
				response += " " + std::to_string(ping >= 0 && ping <= max_ping ? ping : -1);
			}

			game::SV_SendServerCommand(&recipient, game::SV_CMD_RELIABLE, "%s", response.c_str());
		}
	}

	void request()
	{
		const auto now = clock::now();
		if (now < next_request || !playing() || !game::CL_IsLocalClientInGame(0))
		{
			return;
		}
		next_request = now + interval;
		const std::string text = request_command;
		const command::params tokens{text};
		game::CL_ForwardCommandToServer(0, text.c_str());
	}

	int get(const int client_num, const bool local_player)
	{
		if (!playing() || client_num < 0 || client_num >= max_players || !game::CL_IsLocalClientInGame(0))
		{
			return -1;
		}

		if (received_at != clock::time_point{} && clock::now() - received_at <= expiry)
		{
			return pings[client_num];
		}

		// A stock host only sends connection bars. Its snapshot still measures our own round trip.
		if (local_player)
		{
			const auto* client = game::CL_GetLocalClientActive.call_safe(game::LOCAL_CLIENT_0);
			if (client)
			{
				int ping{};
				std::memcpy(&ping, client + 0x6330, sizeof(ping));
				if (ping >= 0 && ping <= max_ping)
				{
					return ping;
				}
			}
		}
		return -1;
	}

	bool receive(const unsigned int local_client, const command::params& args)
	{
		if (!args.size() || std::string_view{args[0]} != response_command)
		{
			return false;
		}
		if (local_client != 0 || !playing() || !game::CL_IsLocalClientInGame(0))
		{
			return true;
		}
		if (args.size() != max_players + 1)
		{
			console::debug("Rejected scoreboard ping response with %d arguments.\n", args.size());
			return true;
		}

		std::array<int, max_players> received{};
		for (auto i = 0; i < max_players; ++i)
		{
			const std::string_view value{args[i + 1]};
			const auto end = value.data() + value.size();
			const auto [last, error] = std::from_chars(value.data(), end, received[i]);
			if (error != std::errc{} || last != end || received[i] < -1 || received[i] > max_ping)
			{
				console::debug("Rejected invalid scoreboard ping at slot %d.\n", i);
				return true;
			}
		}
		if (received_at == clock::time_point{})
		{
			console::debug("Received Zombies scoreboard latency from the host.\n");
		}
		pings = received;
		received_at = clock::now();
		return true;
	}

	void disconnect()
	{
		next_request = {};
		received_at = {};
	}

	class component final : public multiplayer_component
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_zombies())
			{
				command::add_sv(request_command, reply);
			}
		}
	};
}

REGISTER_COMPONENT(scoreboard_ping::component)

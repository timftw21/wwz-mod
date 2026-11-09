#pragma once

namespace command
{
	class params;
}

namespace scoreboard_ping
{
	void request();
	int get(int client_num, bool local_player);
	bool receive(unsigned int local_client, const command::params& args);
	void disconnect();
}

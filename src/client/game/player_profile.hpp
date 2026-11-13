#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace player_profile
{
	const std::string& name();
	const std::filesystem::path& user_directory();
	void reserve();
	void request_fresh_start();
	void cancel_fresh_start();
	bool fresh_start_completed();

	// Launcher selection is saved separately from the profile's stats. An explicit
	// -profile overrides it; selection cannot change after the game starts.
	std::vector<std::string> list();
	void select(const std::string& name);
	void create(const std::string& name);
	std::string relaunch_arguments();
}

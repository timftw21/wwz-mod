#pragma once

namespace updater
{
	// wwz-mod must not replace its executable or data with upstream S2x files.
	inline constexpr bool automatic_updates_enabled = false;

	void update();
	void update_store_runtime(const std::filesystem::path& base, const std::string& required_file);
}

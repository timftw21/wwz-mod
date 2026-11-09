#pragma once

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace script_paths
{
	inline std::optional<std::uint16_t> numeric_id(const std::string_view name)
	{
		if (name.empty()) return {};
		std::uint16_t id{};
		const auto [end, error] = std::from_chars(name.data(), name.data() + name.size(), id);
		if (error != std::errc{} || end != name.data() + name.size() || id == 0)
		{
			return {};
		}
		return id;
	}

	inline std::string lua_asset_name(std::string name)
	{
		if (name.starts_with('@')) name.erase(name.begin());
		std::ranges::replace(name, '\\', '/');
		for (auto& character : name)
		{
			if (character >= 'A' && character <= 'Z') character += 'a' - 'A';
		}

		if (name.starts_with('/') || name.find(':') != std::string::npos || name.find('\0') != std::string::npos || !name.ends_with(".lua"))
		{
			return {};
		}
		for (const auto& part : std::filesystem::path(name))
		{
			if (part == "." || part == "..") return {};
		}
		return std::filesystem::path(name).lexically_normal().generic_string();
	}
}

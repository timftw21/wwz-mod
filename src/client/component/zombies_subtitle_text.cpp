#include <std_include.hpp>
#include "zombies_subtitle_text.hpp"

#include "game/game.hpp"

namespace zombies_subtitle_text
{
	namespace
	{
		struct correction
		{
			game::LocalizeEntry entry;
			std::uint64_t original;
		};

		correction corrections[] = {
#include "zombies_subtitle_edits.inc"
		};

		std::uint64_t text_hash(const std::string_view text)
		{
			std::uint64_t hash = 14695981039346656037ull;
			for (const auto byte : text)
			{
				hash = (hash ^ static_cast<unsigned char>(byte)) * 1099511628211ull;
			}
			return hash;
		}
	}

	game::LocalizeEntry* format_entry(game::LocalizeEntry* entry)
	{
		if (!entry || !entry->name || !entry->value)
		{
			return entry;
		}

		const std::string_view name{entry->name};
		if (!name.starts_with("SUBTITLE_") && !name.starts_with("ZM_VIDSUBTITLES_"))
		{
			return entry;
		}

		const auto end = std::end(corrections);
		const auto found = std::lower_bound(std::begin(corrections), end, name,
			[](const correction& item, const std::string_view key) { return item.entry.name < key; });
		// Only replace the audited English text, preserving other languages and custom versions.
		if (found != end && found->entry.name == name && found->original == text_hash(entry->value))
		{
			return &found->entry;
		}
		return entry;
	}
}

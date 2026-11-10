#include <std_include.hpp>
#include "zombies_subtitle_text.hpp"

#include "console/console.hpp"
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

		struct colored_subtitle
		{
			std::string text;
			game::LocalizeEntry entry{};
		};

		game::LocalizeEntry* color_straub(game::LocalizeEntry* entry, const std::string_view name)
		{
			const std::string_view text{entry->value};
			const bool speaker = name == "SUBTITLE_NAMES_STRA" && text.starts_with("^G");
			const bool recording = name.starts_with("ZM_VIDSUBTITLES_ZOMBIE_STRAUB_") && text.starts_with("^H");
			if (!speaker && !recording)
			{
				return entry;
			}

			// Keep the localized name, dialogue and their reset codes intact.
			static std::mutex mutex;
			static std::unordered_map<std::string, colored_subtitle> subtitles;
			std::string key{name};
			key += '\0';
			key += text;
			const std::lock_guard lock{mutex};
			const auto [stored, inserted] = subtitles.try_emplace(std::move(key), colored_subtitle{std::string{text}});
			if (inserted)
			{
				stored->second.text[1] = '1';
				stored->second.entry = {stored->second.text.c_str(), stored->first.c_str()};
				if (subtitles.size() == 1)
				{
					console::debug("Applied the red speaker color to Straub's subtitles.\n");
				}
			}
			return &stored->second.entry;
		}

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
			entry = &found->entry;
		}
		return color_straub(entry, name);
	}
}

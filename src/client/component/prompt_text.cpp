#include <std_include.hpp>
#include "prompt_text.hpp"

#include "game/game.hpp"

namespace prompt_text
{
	namespace
	{
		struct translation
		{
			std::string text;
			game::LocalizeEntry entry{};
		};

		// Own both the strings and the asset descriptors across fastfile unloads.
		std::mutex translations_mutex;
		std::unordered_map<std::string, translation> translations;

		std::string_view trim_space(std::string_view text)
		{
			const auto first = text.find_first_not_of(" \t");
			return first == text.npos ? std::string_view{} : text.substr(first);
		}

		std::string format_line(std::string_view text)
		{
			const auto line = trim_space(text);
			auto binding = line;
			if (binding.starts_with('^') && binding.size() >= 2)
			{
				binding.remove_prefix(2);
			}
			if (!binding.starts_with("[{"))
			{
				return {};
			}

			const auto close = binding.find("}]");
			if (close == binding.npos)
			{
				return {};
			}

			auto end = line.size() - binding.size() + close + 2;
			if (line.size() >= end + 2 && line[end] == '^')
			{
				end += 2;
			}

			const auto action = trim_space(line.substr(end));
			if (action.empty() || action.size() == line.size() - end)
			{
				return {};
			}

			for (const std::string_view verb : {"Press and hold", "Double tap", "Hold", "Press", "Tap", "to"})
			{
				if (action.size() <= verb.size() || (action[verb.size()] != ' ' && action[verb.size()] != '\t')
					|| _strnicmp(action.data(), verb.data(), verb.size()) != 0)
				{
					continue;
				}

				const auto leading_space = text.size() - line.size();
				std::string result{text.substr(0, leading_space)};
				result += verb == "to" ? "Use" : action.substr(0, verb.size());
				result += ' ';
				result += line.substr(0, end);
				result += ' ';
				result += verb == "to" ? action : trim_space(action.substr(verb.size()));
				return result;
			}
			return {};
		}

	}

	game::LocalizeEntry* format_entry(game::LocalizeEntry* entry)
	{
		if (!entry || !entry->name || !entry->value)
		{
			return entry;
		}

		const std::string_view text{entry->value};
		if (text.find("[{") == text.npos)
		{
			return entry;
		}

		std::string result;
		bool changed = false;
		for (std::size_t start = 0; start < text.size();)
		{
			const auto end = text.find('\n', start);
			const auto line = text.substr(start, end == text.npos ? end : end - start);
			const auto formatted = format_line(line);
			changed |= !formatted.empty();
			result += formatted.empty() ? line : formatted;
			if (end == text.npos)
			{
				break;
			}
			result += '\n';
			start = end + 1;
		}
		if (!changed)
		{
			return entry;
		}

		std::string key{entry->name};
		key += '\0';
		key += text;
		const std::lock_guard lock{translations_mutex};
		const auto [stored, inserted] = translations.try_emplace(std::move(key), translation{std::move(result)});
		if (inserted)
		{
			stored->second.entry = {stored->second.text.c_str(), stored->first.c_str()};
		}
		return &stored->second.entry;
	}
}

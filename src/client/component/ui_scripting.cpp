#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "scheduler.hpp"
#include "command.hpp"
#include "console/console.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"
#include "game/ui_scripting/execution.hpp"
#include "game/ui_scripting/debug.hpp"

#include "filesystem.hpp"
#include "ui_scripting.hpp"
#include "scoreboard_ping.hpp"
#include "script_paths.hpp"

#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/finally.hpp>
#include <utils/string.hpp>

namespace ui_scripting
{
	namespace
	{
		std::unordered_map<game::hks::cclosure*, std::function<arguments(const function_arguments& args)>> converted_functions;
		std::vector<std::function<void()>> start_callbacks;

		utils::hook::detour hks_start_hook;
		utils::hook::detour hks_shutdown_hook;
		utils::hook::detour hks_package_require_hook;

		struct script
		{
			std::string name;
			std::string root;
		};

		static_assert(sizeof(game::LuaFile) == 0x18);
		static_assert(offsetof(game::LuaFile, buffer) == 0x10);

		struct stock_script
		{
			std::string name;
			std::string source;
			game::LuaFile asset{};

			stock_script(std::string script_name, std::string data)
				: name(std::move(script_name)), source(std::move(data))
			{
				asset.name = name.c_str();
				asset.len = static_cast<int>(source.size());
				asset.buffer = source.c_str();
			}
		};

		// Stable asset buffers for the synchronous DB lookup/reader/compiler path.
		// A UI restart drops them so edits and a newly mounted mod are re-read.
		thread_local std::unordered_map<std::string, std::unique_ptr<stock_script>> stock_scripts;
		thread_local stock_script* pending_stock_script{};

		stock_script* find_stock_script(const char* name)
		{
			const auto asset_name = script_paths::lua_asset_name(name);
			if (asset_name.empty()) return nullptr;

			if (const auto found = stock_scripts.find(asset_name); found != stock_scripts.end())
			{
				return found->second.get();
			}

			std::string data, real_path;
			if (!filesystem::read_file(asset_name, &data, &real_path)) return nullptr;
			if (data.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
			{
				console::error("Lua override '%s' is too large.\n", real_path.c_str());
				return nullptr;
			}

			auto entry = std::make_unique<stock_script>(asset_name, std::move(data));
			auto* result = entry.get();
			stock_scripts.emplace(asset_name, std::move(entry));
			console::info("Loading stock Lua override '%s' from '%s'\n", asset_name.c_str(), real_path.c_str());
			return result;
		}

		struct globals_s
		{
			std::string in_require_script;
			std::vector<script> loaded_scripts;
			bool load_raw_script{};
			std::string raw_script_name{};
			std::vector<std::string> script_stack{};
		};

		std::unordered_map<game::hks::lua_State*, globals_s> state_globals{};
		thread_local game::hks::lua_State* active_lua_state{};

		std::string normalize_script_path(std::string path)
		{
			if (!path.empty() && path[0] == '@')
			{
				path.erase(path.begin());
			}

			std::ranges::replace(path, '\\', '/');
			return path;
		}

		globals_s& get_globals(game::hks::lua_State* state)
		{
			return state_globals[state];
		}

		bool is_loaded_script(const globals_s& globals, const std::string& name)
		{
			const auto normalized_name = normalize_script_path(name);
			return std::ranges::any_of(globals.loaded_scripts, [&normalized_name](const auto& loaded_script)
			{
				return loaded_script.name == normalized_name;
			});
		}

		std::string select_require_script(const globals_s& globals, const std::string& hks_script)
		{
			if (is_loaded_script(globals, hks_script))
			{
				return hks_script;
			}

			if (!globals.script_stack.empty())
			{
				return globals.script_stack.back();
			}

			return hks_script;
		}

		std::string get_root_script(globals_s& globals, const std::string& name)
		{
			const auto normalized_name = normalize_script_path(name);
			for (const auto& loaded_script : globals.loaded_scripts)
			{
				if (loaded_script.name == normalized_name)
				{
					return loaded_script.root;
				}
			}

			if (normalized_name.find("ui_scripts/") != std::string::npos && utils::io::file_exists(normalized_name))
			{
				globals.loaded_scripts.push_back({ normalized_name, normalized_name });
				return normalized_name;
			}

			return {};
		}

		std::string find_local_script(const std::string& folder, const std::string& name)
		{
			std::vector<std::string> candidates{};

			const auto add_candidate = [&](std::string path)
			{
				path = normalize_script_path(std::move(path));
				if (!path.ends_with(".lua"))
				{
					path += ".lua";
				}

				if (std::ranges::find(candidates, path) == candidates.end())
				{
					candidates.push_back(std::move(path));
				}
			};

			add_candidate(folder + "/" + name);

			auto module_name = name;
			const auto has_lua_extension = module_name.ends_with(".lua");
			if (has_lua_extension)
			{
				module_name.resize(module_name.size() - 4);
			}

			std::ranges::replace(module_name, '.', '/');
			if (has_lua_extension)
			{
				module_name += ".lua";
			}

			add_candidate(folder + "/" + module_name);

			if (const auto slash = module_name.find('/'); slash != std::string::npos)
			{
				add_candidate(folder + "/" + module_name.substr(slash + 1));
			}

			if (const auto slash = module_name.find_last_of('/'); slash != std::string::npos)
			{
				add_candidate(folder + "/" + module_name.substr(slash + 1));
			}

			for (const auto& candidate : candidates)
			{
				if (utils::io::file_exists(candidate))
				{
					return candidate;
				}
			}

			return {};
		}

		table get_globals()
		{
			const auto state = *game::hks::lui_lua_state;
			return state->globals.v.table;
		}

		void print_error(const std::string& error)
		{
			console::error("************** LUI script execution error **************\n");
			console::error("%s\n", error.data());
			console::error("********************************************************\n");
		}

		void print_loading_script(const std::string& name)
		{
			console::info("Loading LUI script '%s'\n", name.data());
		}

		std::string get_current_script(game::hks::lua_State* state)
		{
			game::hks::lua_Debug info{};
			game::hks::hksi_lua_getstack(state, 1, &info);
			game::hks::hksi_lua_getinfo(state, "nSl", &info);
			return info.short_src;
		}

		int load_buffer(game::hks::lua_State* state, const std::string& name, const std::string& data)
		{
			const auto sharing_mode = state->m_global->m_bytecodeSharingMode;
			state->m_global->m_bytecodeSharingMode = game::hks::HKS_BYTECODE_SHARING_ON;
			const auto _0 = utils::finally([&]()
			{
				state->m_global->m_bytecodeSharingMode = sharing_mode;
			});

			game::hks::HksCompilerSettings compiler_settings{};
			return debug::load_buffer(state, &compiler_settings, name, data);
		}

		std::string get_load_error(game::hks::lua_State* state, const std::ptrdiff_t top, const int result)
		{
			if (state->m_apistack.top - state->m_apistack.bottom > top)
			{
				const auto& error = state->m_apistack.top[-1];

				if (error.t == game::hks::TSTRING && error.v.str)
				{
					return error.v.str->m_data;
				}
			}

			return utils::string::va("Lua returned %d with no string error message", result);
		}

		void load_script(const std::string& name, const std::string& data)
		{
			const auto state = *game::hks::lui_lua_state;
			auto& globals = get_globals(state);

			const auto normalized_name = normalize_script_path(name);

			const auto previous_active_state = active_lua_state;
			auto previous_require_script = globals.in_require_script;
			const auto previous_depth = globals.script_stack.size();
			const auto top = state->m_apistack.top - state->m_apistack.bottom;

			const auto restore_state = utils::finally([&]()
			{
				state->m_apistack.top = state->m_apistack.bottom + top;
				globals.script_stack.resize(previous_depth);
				globals.in_require_script.swap(previous_require_script);
				active_lua_state = previous_active_state;
			});

			active_lua_state = state;
			globals.in_require_script = normalized_name;
			globals.loaded_scripts.push_back({ normalized_name, normalized_name });
			globals.script_stack.push_back(normalized_name);

			const auto load_result = load_buffer(state, normalized_name, data);

			if (load_result != 0)
			{
				print_error(get_load_error(state, top, load_result));

				return;
			}

			if (state->m_apistack.top - state->m_apistack.bottom <= top ||
				(state->m_apistack.top[-1].t != game::hks::TIFUNCTION &&
					state->m_apistack.top[-1].t != game::hks::TCFUNCTION))
			{
				print_error(utils::string::va("Failed to load '%s': compiled chunk is not a function", normalized_name.data()));

				return;
			}

			const auto result = game::hks::hksi_lua_pcall(state, 0, 0, 0);

			if (result != 0)
			{
				print_error(get_load_error(state, top, result));
			}
		}

		void load_scripts(const std::string& script_dir)
		{
			if (!utils::io::directory_exists(script_dir))
			{
				return;
			}

			const auto scripts = utils::io::list_files(script_dir);

			for (const auto& script : scripts)
			{
				std::string data{};
				if (std::filesystem::is_directory(script) && utils::io::read_file(script / "__init__.lua", &data))
				{
					print_loading_script(script.generic_string());
					load_script((script / "__init__.lua").generic_string(), data);
				}
			}
		}

		void setup_functions()
		{
			const auto lua = get_globals();

			using game = table;
			auto game_type = game();
			lua["game"] = game_type;

			game_type["issingleplayer"] = [](const game&)
			{
				return ::game::environment::is_singleplayer();
			};

			game_type["ismultiplayer"] = [](const game&)
			{
				return ::game::environment::is_multiplayer();
			};

			game_type["requestscoreboardpings"] = [](const game&)
			{
				scoreboard_ping::request();
			};

			game_type["getscoreboardping"] = [](const game&, const int client_num, const bool local_player)
			{
				return scoreboard_ping::get(client_num, local_player);
			};
		}

		void run_start_callbacks()
		{
			for (const auto& callback : start_callbacks)
			{
				try
				{
					callback();
				}
				catch (const std::exception& e)
				{
					console::error("Failed to run LUI start callback: %s\n", e.what());
				}
			}
		}

		void enable_globals()
		{
			const auto lua = get_globals();
			const std::string script =
				"local g = getmetatable(_G)\n"
				"if not g then\n"
					"g = {}\n"
					"setmetatable(_G, g)\n"
				"end\n"
				"g.__newindex = nil\n";

			(void)lua["loadstring"](script)[0]();
		}

		void start()
		{
			get_globals(*game::hks::lui_lua_state) = {};
			const auto lua = get_globals();

			enable_globals();
			setup_functions();

			lua["print"] = function(reinterpret_cast<game::hks::lua_function>(game::hks::base_print.get()));
			lua["table"]["unpack"] = lua["unpack"];
			lua["luiglobals"] = lua;

			for (const auto& path : filesystem::get_search_paths_rev())
			{
				load_scripts((std::filesystem::path(path) / "ui_scripts").generic_string());

				if (!game::environment::uses_multiplayer_binary())
				{
					load_scripts((std::filesystem::path(path) / "ui_scripts/sp").generic_string());
				}
				else
				{
					load_scripts((std::filesystem::path(path) / "ui_scripts/mp").generic_string());
				}
			}

			run_start_callbacks();
		}

		void try_start()
		{
			try
			{
				start();
			}
			catch (const std::exception& e)
			{
				console::error("Failed to load LUI scripts: %s\n", e.what());
			}
		}

		void hks_start_stub(const bool frontend, const bool cg)
		{
			const auto _0 = utils::finally(&try_start);
			hks_start_hook.invoke<void>(frontend, cg);
		}

		void hks_shutdown_stub()
		{
			// Keep source buffers and callbacks alive through the engine's teardown.
			hks_shutdown_hook.invoke<void>();
			active_lua_state = nullptr;
			converted_functions.clear();
			state_globals.clear();
			pending_stock_script = nullptr;
			stock_scripts.clear();
			debug::clear();
		}

		int hks_package_require_stub(game::hks::lua_State* state)
		{
			int result{};

			try
			{
				auto& globals = get_globals(state);

				const auto hks_script = normalize_script_path(get_current_script(state));
				const auto script = select_require_script(globals, hks_script);
				const auto root = get_root_script(globals, script);

				const auto previous_active_state = active_lua_state;
				auto previous_require_script = globals.in_require_script;
				auto previous_raw_script_name = globals.raw_script_name;
				const auto previous_load_raw_script = globals.load_raw_script;
				auto* const previous_stock_script = pending_stock_script;

				const auto restore_state = utils::finally([&]()
				{
					globals.in_require_script.swap(previous_require_script);
					globals.raw_script_name.swap(previous_raw_script_name);
					globals.load_raw_script = previous_load_raw_script;
					pending_stock_script = previous_stock_script;
					active_lua_state = previous_active_state;
				});

				active_lua_state = state;
				globals.in_require_script = root;
				globals.load_raw_script = false;
				globals.raw_script_name.clear();
				pending_stock_script = nullptr;

				const auto nargs = static_cast<int>(state->m_apistack.top - state->m_apistack.base);
				reserve_stack(state, 1);
				game::hks::hksi_lua_pushcclosure(state,
					reinterpret_cast<game::hks::lua_function>(hks_package_require_hook.get_original()),
					0, "require", 0, 0);

				const auto closure = state->m_apistack.top[-1];

				std::memmove(state->m_apistack.base + 1, state->m_apistack.base,
					static_cast<size_t>(nargs) * sizeof(game::hks::HksObject));
				state->m_apistack.base[0] = closure;

				// Catch Lua's nonlocal jump before restoring the require context.
				result = game::hks::hksi_lua_pcall(state, nargs, 1, 0);
			}
			catch (const std::exception& e)
			{
				reserve_stack(state, 1);
				game::hks::hksi_lua_pushlstring(state, e.what(), static_cast<int>(std::strlen(e.what())));
				result = game::hks::HKS_ERRRUN;
			}

			if (result != 0)
			{
				game::hks::hksi_lua_error(state);
			}

			return 1;
		}

		game::XAssetHeader db_find_x_asset_header_stub(game::XAssetType type, const char* name, int allow_create_default)
		{
			if (type != game::ASSET_TYPE_LUAFILE || !name)
			{
				return game::DB_FindXAssetHeader(type, name, allow_create_default);
			}

			pending_stock_script = nullptr;

			// Preserve package-local imports before consulting canonical stock paths.
			if (active_lua_state)
			{
				auto& globals = get_globals(active_lua_state);
				const auto root = normalize_script_path(globals.in_require_script);
				const auto folder_end = root.find_last_of('/');
				if (is_loaded_script(globals, root) && folder_end != std::string::npos)
				{
					const auto target = find_local_script(root.substr(0, folder_end), normalize_script_path(name));
					if (!target.empty())
					{
						globals.load_raw_script = true;
						globals.raw_script_name = target;
						return { .luaFile = reinterpret_cast<game::LuaFile*>(1) };
					}
				}
			}

			// These loader call sites also run during stock startup, before custom
			// packages exist. Return a real LuaFile, including for new dependencies.
			if (auto* source = find_stock_script(name))
			{
				pending_stock_script = source;
				return { .luaFile = &source->asset };
			}
			return game::DB_FindXAssetHeader(type, name, allow_create_default);
		}

		int hks_load_stub(game::hks::lua_State* state, void* compiler_options,
			void* reader, void* reader_data, const char* chunk_name)
		{
			try
			{
				const auto* stock = std::exchange(pending_stock_script, nullptr);
				auto& globals = get_globals(state);
				const auto previous_active_state = active_lua_state;

				const auto restore_state = utils::finally([&]()
				{
					active_lua_state = previous_active_state;
				});

				active_lua_state = state;

				if (globals.load_raw_script)
				{
					globals.load_raw_script = false;

					const auto script_name = std::exchange(globals.raw_script_name, {});
					const auto require_root = globals.in_require_script;
					const auto result = load_buffer(state, script_name, utils::io::read_file(script_name));

					if (result == 0)
					{
						globals.loaded_scripts.push_back({ script_name, require_root });

						return result;
					}
				}
				else
				{
					if (!stock)
					{
						return game::hks::load(state, compiler_options, reader, reader_data, chunk_name);
					}

					// Bind the source to the DB request, independent of the engine's
					// diagnostic chunk label. The caller still owns execution and caching.
					const auto result = load_buffer(state, stock->name, stock->source);
					if (result == 0) return result;
				}
			}
			catch (const std::exception& e)
			{
				reserve_stack(state, 1);
				game::hks::hksi_lua_pushlstring(state, e.what(), static_cast<int>(std::strlen(e.what())));
			}

			// Preserve the compiler error instead of the loader's generic "unable to load module".
			game::hks::hksi_lua_error(state);
			return game::hks::HKS_ERRFILE;
		}

		int main_handler(game::hks::lua_State* state)
		{
			const auto value = state->m_apistack.base[-1];
			if (value.t != game::hks::TCFUNCTION)
			{
				return 0;
			}

			const auto closure = value.v.cClosure;
			if (!converted_functions.contains(closure))
			{
				return 0;
			}

			const auto& function = converted_functions[closure];

			try
			{
				const auto args = get_return_values(state);
				const auto results = function(args);

				for (const auto& result : results)
				{
					push_value(state, result.get_raw());
				}

				return static_cast<int>(results.size());
			}
			catch (const std::exception& e)
			{
				reserve_stack(state, 1);
				game::hks::hksi_lua_pushlstring(state, e.what(), static_cast<int>(std::strlen(e.what())));
			}

			game::hks::hksi_lua_error(state);
			return 0;
		}

		int hks_base_printf_stub(const char* fmt, ...)
		{
			char buffer[4096]{};

			va_list args;
			va_start(args, fmt);
			const auto len = vsnprintf_s(buffer, sizeof(buffer), _TRUNCATE, fmt, args);
			va_end(args);

			if (len > 0)
			{
				console::info("[LUI] %s\n", buffer);
			}

			return len;
		}
	}

	table get_globals()
	{
		const auto state = *game::hks::lui_lua_state;
		return state->globals.v.table;
	}

	game::hks::cclosure* convert_function(const std::function<arguments(const function_arguments&)>& f)
	{
		reserve_stack(*game::hks::lui_lua_state, 1);
		const auto closure = game::hks::cclosure_Create(main_handler);
		converted_functions[closure] = f;

		return closure;
	}

	void on_start(const std::function<void()>& callback)
	{
		start_callbacks.push_back(callback);
	}

	class component final : public generic_component
	{
	public:

		void post_unpack() override
		{
			if (game::environment::is_dedicated())
			{
				return;
			}
			
			debug::initialize();

			utils::hook::call(game::select(0x309B7B, 0x17E16B), db_find_x_asset_header_stub);
			utils::hook::call(game::select(0x309CBC, 0x17E2AC), db_find_x_asset_header_stub);
			utils::hook::call(game::select(0x309CFF, 0x17E2EF), hks_load_stub);
			utils::hook::call(game::select(0x2BA4B7, 0x12E877), hks_base_printf_stub);

			hks_package_require_hook.create(game::hks::package_require, hks_package_require_stub);
			hks_start_hook.create(game::LUI_CoD_Init, hks_start_stub);
			hks_shutdown_hook.create(game::LUI_CoD_Shutdown, hks_shutdown_stub);

			command::add("lui_restart", []()
			{
				game::LUI_CoD_Restart(true);
			});

			// TODO: Patch unsafe LUA functions
		}
	};
}

REGISTER_COMPONENT(ui_scripting::component)

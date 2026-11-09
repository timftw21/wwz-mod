gsc_tool = {
	source = path.join(dependencies.basePath, "gsc-tool"),
}

function gsc_tool.import()
	links { "xsk-gsc-s2", "xsk-gsc-utils" }
	gsc_tool.includes()
end

function gsc_tool.includes()
	includedirs {
		path.join(gsc_tool.source, "include"),
	}
end

-- Apply the pinned compiler's grammar fixes to a generated copy. Keep the
-- submodule clean and leave unchanged output timestamps alone on regeneration.
function gsc_tool.patched_parser()
	local staged_root = path.join(_MAIN_SCRIPT_DIR, "build/patched/gsc-tool")
	local staged = path.join(staged_root, "src/gsc/parser.cpp")
	local output = path.join(_MAIN_SCRIPT_DIR, "build/patched/gsc-tool-parser.cpp")
	os.mkdir(path.getdirectory(staged))
	assert(os.copyfile(path.join(gsc_tool.source, "src/gsc/parser.cpp"), staged))
	local result = os.execute(('git -C "%s" apply --directory="build/patched/gsc-tool" "%s"')
		:format(_MAIN_SCRIPT_DIR, path.join(_MAIN_SCRIPT_DIR, "deps/patches/gsc-tool-parser.patch")))
	assert(result == 0 or result == true, "Could not apply the gsc-tool parser fixes")
	local patched = assert(io.readfile(staged))
	if io.readfile(output) ~= patched then
		assert(io.writefile(output, patched))
	end
	return output
end

function gsc_tool.project()
	local patched_parser = gsc_tool.patched_parser()
	project "xsk-gsc-utils"
		kind "StaticLib"
		language "C++"

		files {
			path.join(gsc_tool.source, "include/xsk/utils/*.hpp"),
			path.join(gsc_tool.source, "src/utils/*.cpp"),
		}

		includedirs {
			path.join(gsc_tool.source, "include"),
		}

		zlib.includes()

	project "xsk-gsc-s2"
		kind "StaticLib"
		language "C++"

		filter "action:vs*"
			buildoptions "/Zc:__cplusplus"
		filter {}

		files {
			patched_parser,
			path.join(gsc_tool.source, "include/xsk/stdinc.hpp"),

			path.join(gsc_tool.source, "include/xsk/gsc/engine/s2.hpp"),
			path.join(gsc_tool.source, "src/gsc/engine/s2.cpp"),

			path.join(gsc_tool.source, "src/gsc/engine/s2_code.cpp"),
			path.join(gsc_tool.source, "src/gsc/engine/s2_func.cpp"),
			path.join(gsc_tool.source, "src/gsc/engine/s2_meth.cpp"),
			path.join(gsc_tool.source, "src/gsc/engine/s2_token.cpp"),

			path.join(gsc_tool.source, "src/gsc/*.cpp"),

			path.join(gsc_tool.source, "src/gsc/common/*.cpp"),
			path.join(gsc_tool.source, "include/xsk/gsc/common/*.hpp"),
		}

		removefiles { path.join(gsc_tool.source, "src/gsc/parser.cpp") }

		includedirs {
			path.join(gsc_tool.source, "include"),
		}
end

table.insert(dependencies, gsc_tool)

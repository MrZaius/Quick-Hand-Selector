local config = {}

local logger = require('quickhand.logger')

local DEFAULTS = {
	['config_version'] = 1,
	-- Right-hand side of the play area, clear of the consumables row.
	['position'] = {
		['x'] = 16.2,
		['y'] = 3.2,
	},
	-- Rebindable keys, mirroring the panel: the number row for the hand list, QWER
	-- across the suit row, T and F for the two side actions, A and D for the bottom row.
	['keys'] = {
		['hand_1'] = '1',
		['hand_2'] = '2',
		['hand_3'] = '3',
		['hand_4'] = '4',
		['hand_5'] = '5',
		['hand_6'] = '6',
		['hand_7'] = '7',
		['hand_8'] = '8',
		['hand_9'] = '9',
		['suit_1'] = 'q',
		['suit_2'] = 'w',
		['suit_3'] = 'e',
		['suit_4'] = 'r',
		['fill'] = 't',
		['invert'] = 'f',
		['debuffed'] = 'a',
		['facedown'] = 'd',
		['clear'] = 'x',
		['inverse'] = 'space',
	},
	['options'] = {
		-- Suit buttons take the best cards of the suit. Off, they take the lowest --
		-- useful if you use them to clear a suit out rather than to build a flush.
		['suit_highest_first'] = true,
		-- Debuffed cards score nothing, so by default they are the first thing offered
		-- up when discarding. Off, everything is ordered purely by rank.
		['debuffed_first'] = true,
		-- Remember what was selected just before an Invert, so Add-lowest leaves those
		-- cards alone. Off, Add-lowest treats every unselected card as fair game.
		['remember_kept'] = true,
		-- Leave face-down cards out of Invert and Add-lowest entirely.
		['skip_face_down'] = false,
		-- Stop the panel being dragged, so a misclick near an edge cannot move it.
		['lock_position'] = false,
		-- A copy of the game's Play/Discard buttons as a column beside the panel.
		['show_play_discard'] = false,
		-- Which side that column sits on: left of everything, or right of the invert bar.
		['play_discard_on_right'] = false,
	},
}

-- Order the checkboxes appear in on the options tab.
config.OPTION_ORDER = {
	'suit_highest_first',
	'debuffed_first',
	'remember_kept',
	'skip_face_down',
	'lock_position',
	'show_play_discard',
	'play_discard_on_right',
}

-- The keybind screen shows these as two columns of nine, so both lists stay the same
-- length on purpose.
config.HAND_KEYS = {
	'hand_1', 'hand_2', 'hand_3', 'hand_4', 'hand_5',
	'hand_6', 'hand_7', 'hand_8', 'hand_9',
}

-- `inverse` leads the column: it is a modifier rather than an action, so it reads
-- better as the rule that governs the rest than as an afterthought after them.
config.ACTION_KEYS = {
	'inverse',
	'suit_1', 'suit_2', 'suit_3', 'suit_4',
	'fill', 'invert', 'clear', 'debuffed', 'facedown',
}

--- Puts every key back to its shipped default.
function config.reset_keys()
	for action, key in pairs(DEFAULTS.keys) do
		config.keys[action] = key
	end
	config.save()
end

local SAVE_FILE_NAME = 'QuickHandSelector.jkr'
local SAVE_DIR = 'config'
local SAVE_PATH = SAVE_DIR .. '/' .. SAVE_FILE_NAME

--- Copies missing keys from `source` into `target`. Returns true if anything was
--- added, so callers can skip a pointless disk write.
local function deep_merge(source, target)
	local changed = false
	for k, v in pairs(source) do
		if type(v) == 'table' then
			if type(target[k]) ~= 'table' then
				target[k] = {}
				changed = true
			end
			changed = deep_merge(v, target[k]) or changed
		elseif target[k] == nil then
			target[k] = v
			changed = true
		end
	end
	return changed
end

--- Picks out the saved data, so STR_PACK never sees the functions and lookup tables
--- also hanging off `config`. The sub-tables are passed by reference: they hold plain
--- data only, and STR_PACK just reads them.
local function to_data()
	return {
		config_version = config.config_version,
		position = config.position,
		keys = config.keys,
		options = config.options,
	}
end

function config.save()
	if not love.filesystem.getInfo(SAVE_DIR) then
		if not love.filesystem.createDirectory(SAVE_DIR) then
			logger.log_error('Failed to create config folder')
			return
		end
	end

	-- STR_PACK is the game's own serializer and emits the `return { ... }` shape the
	-- loader below expects. Plaintext rather than compress_and_save, so the file stays
	-- hand-editable.
	local success, err = love.filesystem.write(SAVE_PATH, STR_PACK(to_data()))
	if not success then
		logger.log_error('Failed to save config file: ' .. tostring(err))
	end
end

function config.load()
	local loaded = {}
	if love.filesystem.getInfo(SAVE_PATH) then
		local contents, read_err = love.filesystem.read(SAVE_PATH)
		if not contents then
			logger.log_error('Failed to read config file: ' .. tostring(read_err))
		else
			-- STR_UNPACK asserts rather than returning an error, hence the pcall.
			local success, load_err = pcall(function()
				loaded = STR_UNPACK(contents) or {}
			end)
			if not success then
				logger.log_error('Error loading existing config file: ' .. tostring(load_err))
				loaded = {}
			end
		end
	end

	deep_merge(loaded, config)
	if deep_merge(DEFAULTS, config) then
		config.save()
	end

	return config
end

return config

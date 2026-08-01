local settings_ui = {}

local config = require('quickhand.config')
local locale = require('quickhand.locale')
local hands = require('quickhand.hands')
local ui = require('quickhand.ui')

-- Live captions for the rebind buttons, keyed by action id. Written by
-- refresh_labels and read by the UI through ref_table, so a rebind updates the button
-- in place without rebuilding the menu.
settings_ui.labels = {}

--- Turns a LÖVE key name into something readable on a button.
local function key_caption(key)
	if not key or key == '' then return '-' end
	if key == 'space' then return locale.translate('quickhand_key_space') end
	if #key == 1 then return string.upper(key) end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

--- core calls this through QuickHand whenever the listening state changes.
function settings_ui.refresh_labels()
	for _, list in ipairs({ config.HAND_KEYS, config.ACTION_KEYS }) do
		for _, action in ipairs(list) do
			if QuickHand.listening == action then
				settings_ui.labels[action] = locale.translate('quickhand_key_listening')
			else
				settings_ui.labels[action] = key_caption(config.keys[action])
			end
		end
	end
end

--- Row captions. Suits use the game's own localized suit names rather than a
--- position, so the row says "Hearts" instead of "Suit 2".
local function action_caption(action)
	local suit_index = string.match(action, '^suit_(%d)$')
	if suit_index then
		return localize(hands.SUITS[tonumber(suit_index)], 'suits_plural')
	end

	local hand_index = string.match(action, '^hand_(%d)$')
	if hand_index then
		return locale.translate('quickhand_action_hand') .. ' ' .. hand_index
	end

	return locale.translate('quickhand_action_' .. action)
end

local LABEL_W = 2.6
local KEY_W = 1.6

--- One "action name  [KEY]" row.
local function create_bind_row(action)
	-- Optional per-action explanation, hung off the key button because that node is
	-- already hoverable. Only the ones whose purpose is not obvious from the name
	-- define this key -- `inverse` above all, since it is a held modifier rather than
	-- something that does anything on its own.
	local info_key = 'quickhand_action_' .. action .. '_info'
	local info = locale.translate(info_key)
	local tooltip = info ~= info_key and { text = { info } } or nil

	return {
		n = G.UIT.R,
		config = { align = 'cm', padding = 0.03 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = 'cr', minw = LABEL_W, maxw = LABEL_W },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = action_caption(action),
							scale = 0.35,
							colour = G.C.UI.TEXT_LIGHT,
							maxw = LABEL_W - 0.1,
						},
					},
				},
			},
			{ n = G.UIT.C, config = { minw = 0.15 } },
			{
				n = G.UIT.C,
				config = {
					align = 'cm',
					minw = KEY_W,
					maxw = KEY_W,
					minh = 0.55,
					padding = 0.08,
					r = 0.1,
					hover = true,
					shadow = true,
					colour = G.C.BLUE,
					button = 'quickhand_rebind',
					ref_table = { action = action },
					tooltip = tooltip,
				},
				nodes = {
					{
						n = G.UIT.T,
						config = {
							ref_table = settings_ui.labels,
							ref_value = action,
							scale = 0.33,
							colour = G.C.UI.TEXT_LIGHT,
							shadow = true,
							maxw = KEY_W - 0.15,
						},
					},
				},
			},
		},
	}
end

--- A titled column of bind rows.
local function create_bind_column(title_key, actions)
	local rows = {
		{
			n = G.UIT.R,
			config = { align = 'cm', padding = 0.06 },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = locale.translate(title_key),
						scale = 0.4,
						colour = G.C.WHITE,
						shadow = true,
					},
				},
			},
		},
	}

	for _, action in ipairs(actions) do
		rows[#rows + 1] = create_bind_row(action)
	end

	return { n = G.UIT.C, config = { align = 'tm', padding = 0.1 }, nodes = rows }
end

--- The keybinds tab. create_tabs calls this to build the tab body.
--- Two columns of nine rather than one list of eighteen, which would not fit on
--- screen. Hands on the left, everything else on the right, matching the panel.
function settings_ui.keybinds_tab()
	settings_ui.refresh_labels()

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', padding = 0.1, colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.R,
				config = { align = 'tm' },
				nodes = {
					create_bind_column('quickhand_column_hands', config.HAND_KEYS),
					create_bind_column('quickhand_column_actions', config.ACTION_KEYS),
				},
			},
			{
				n = G.UIT.R,
				config = { align = 'cm', padding = 0.08 },
				nodes = {
					UIBox_button({
						label = { locale.translate('quickhand_reset_keys') },
						button = 'quickhand_reset_keys',
						colour = G.C.RED,
						minw = 4,
						minh = 0.6,
						scale = 0.38,
					}),
				},
			},
		},
	}
end

--- The description under a checkbox. create_toggle renders one line per entry with no
--- wrapping, so a longer explanation is spelled out as `_info`, `_info2`, `_info3`.
--- Options whose purpose fits on one line just define the first.
local function option_info(option)
	local lines = {}
	for _, suffix in ipairs({ '_info', '_info2', '_info3' }) do
		local key = 'quickhand_option_' .. option .. suffix
		local text = locale.translate(key)
		if text == key then break end
		lines[#lines + 1] = text
	end
	return lines
end

--- One checkbox bound straight to config.options. create_toggle flips the value for
--- us; the callback only has to persist it.
local function create_option_toggle(option)
	return create_toggle({
		label = locale.translate('quickhand_option_' .. option),
		info = option_info(option),
		ref_table = config.options,
		ref_value = option,
		w = 4.5,
		label_scale = 0.38,
		callback = function()
			config.save()
			-- Some of these change the panel's shape or whether it can be dragged, and
			-- none of them move the hand signature the refresh normally keys off.
			ui.invalidate()
		end,
	})
end

function settings_ui.options_tab()
	local rows = {}
	for _, option in ipairs(config.OPTION_ORDER) do
		rows[#rows + 1] = create_option_toggle(option)
	end

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', padding = 0.15, colour = G.C.CLEAR, minw = 6 },
		nodes = rows,
	}
end

function G.UIDEF.quickhand_options()
	return create_UIBox_generic_options({
		back_func = 'quickhand_exit_options',
		contents = {
			{
				n = G.UIT.R,
				config = { align = 'cm', padding = 0 },
				nodes = {
					create_tabs({
						tabs = {
							{
								label = locale.translate('quickhand_tab_keybinds'),
								chosen = true,
								tab_definition_function = settings_ui.keybinds_tab,
							},
							{
								label = locale.translate('quickhand_tab_options'),
								tab_definition_function = settings_ui.options_tab,
							},
						},
						snap_to_nav = true,
						colour = G.C.BOOSTER,
					}),
				},
			},
		},
	})
end

G.FUNCS.quickhand_open_options = function()
	G.SETTINGS.paused = true
	QuickHand.set_listening(nil)
	G.FUNCS.overlay_menu({ definition = G.UIDEF.quickhand_options() })
end

G.FUNCS.quickhand_exit_options = function(e)
	QuickHand.set_listening(nil)
	if e then return G.FUNCS.options(e) end
end

G.FUNCS.quickhand_reset_keys = function()
	-- Cancel any rebind in progress first, or the next keypress would be captured
	-- into an action the player just reset.
	QuickHand.set_listening(nil)
	config.reset_keys()
	settings_ui.refresh_labels()
	play_sound('button', 1, 0.4)
end

G.FUNCS.quickhand_rebind = function(e)
	local action = e.config.ref_table and e.config.ref_table.action
	if not action then return end
	-- Second click on the same button cancels, so the player is never stuck listening.
	QuickHand.set_listening(QuickHand.listening ~= action and action or nil)
end

-- Appending to the options list the way Handy does: wrap the builder and push a
-- button onto the same column the vanilla entries live in. Guarded because that path
-- is deep, and a future patch could reshape it.
local create_UIBox_options_ref = create_UIBox_options
function create_UIBox_options()
	local contents = create_UIBox_options_ref()

	local ok, column = pcall(function()
		return contents.nodes[1].nodes[1].nodes[1].nodes
	end)

	if ok and column then
		column[#column + 1] = UIBox_button({
			label = { locale.translate('quickhand_options_button') },
			button = 'quickhand_open_options',
			minw = 5,
			colour = G.C.BOOSTER,
		})
	end

	return contents
end

QuickHand.refresh_bind_labels = settings_ui.refresh_labels
settings_ui.refresh_labels()

return settings_ui

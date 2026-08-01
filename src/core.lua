QuickHand = {}

local config = require('quickhand.config')
local hands = require('quickhand.hands')
local ui = require('quickhand.ui')

config.load()

--- The window only makes sense while there is a hand to select from: during a blind,
--- not in the shop, blind select, cash out or any menu.
function QuickHand.is_visible()
	if not G or not G.STATES or G.STAGE ~= G.STAGES.RUN then return false end
	if G.SETTINGS.paused or G.OVERLAY_MENU then return false end
	if not G.hand or not G.hand.cards or #G.hand.cards == 0 then return false end
	if not G.hand.states.visible then return false end

	local state = G.STATE
	return state == G.STATES.SELECTING_HAND
		or state == G.STATES.DRAW_TO_HAND
		or state == G.STATES.PLAY_TAROT
end

-- One registry for every panel action, keyed by the same id the keybind config and
-- the settings menu use. Left-click, right-click and keyboard all resolve through it,
-- so adding an action is one entry here instead of three parallel lists.
--
-- `hands.select` stays outside it: it is the only action carrying a payload (which
-- hand button was pressed, via ref_table).
local ACTIONS = {
	fill = function(inverse) hands.fill(inverse) end,
	-- Invert has no opposite -- it *is* the opposite -- so it ignores `inverse`. It is
	-- still registered so a right-click on it does not fall through to vanilla, which
	-- would clear the selection instead.
	invert = function() hands.invert() end,
	-- Clear ignores `inverse` too: there is no opposite of starting over.
	clear = function() hands.clear() end,
	debuffed = function(inverse) hands.select_debuffed(inverse) end,
	facedown = function(inverse) hands.select_face_down(inverse) end,
}

for i, suit in ipairs(hands.SUITS) do
	ACTIONS['suit_' .. i] = function(inverse) hands.select_suit(suit, inverse) end
end

G.FUNCS.quickhand_select = function(e)
	local index = e.config.ref_table and e.config.ref_table.index
	local entry = index and ui.entries[index]
	if entry then hands.select(entry) end
end

for id, run in pairs(ACTIONS) do
	G.FUNCS['quickhand_' .. id] = function() run(false) end
end

--- Right-click runs each button's opposite. Returns true when it handled the press,
--- which stops the event reaching vanilla -- important, because vanilla right-click
--- calls G.hand:unhighlight_all(), so falling through would wipe the very selection
--- the button just made.
--- @param button string the G.FUNCS name on the hovered node
--- @param ref_table table|nil the node's ref_table, carrying the hand index
function QuickHand.handle_right_click(button, ref_table)
	if button == 'quickhand_select' then
		local index = ref_table and ref_table.index
		local entry = index and ui.entries[index]
		if entry then hands.select(entry, true) end
		return true
	end

	local run = ACTIONS[string.match(button, '^quickhand_(.+)$') or '']
	if not run then return false end

	run(true)
	return true
end

--- The node under the cursor, if it is one of ours. hovering.target is the button
--- itself for UI elements, but fall back to scanning everything under the cursor in
--- case another mod has taken the hover target.
local function hovered_quickhand_button(controller)
	local target = controller.hovering.target
	if target and target.config and type(target.config.button) == 'string' then
		if string.match(target.config.button, '^quickhand_') then
			return target.config.button, target.config.ref_table
		end
	end

	for _, node in ipairs(controller.nodes_at_cursor or {}) do
		if node.config and type(node.config.button) == 'string'
			and string.match(node.config.button, '^quickhand_') then
			return node.config.button, node.config.ref_table
		end
	end

	return nil
end

local queue_R_cursor_press_ref = Controller.queue_R_cursor_press
function Controller:queue_R_cursor_press(x, y)
	if G.HUD_quickhand and not self.locks.frame then
		local button, ref_table = hovered_quickhand_button(self)
		if button and QuickHand.handle_right_click(button, ref_table) then
			return
		end
	end

	return queue_R_cursor_press_ref(self, x, y)
end

-- Keyboard shortcuts resolve through the same ACTIONS registry as the mouse, keyed by
-- the ids in config.keys. Every one is rebindable from Options -> Quick Hand Selector.
--
-- Set while the player is rebinding: the next key pressed becomes that action's key.
QuickHand.listening = nil

--- Lives here because handle_key below is what clears it; settings_ui installs the
--- label refresh onto QuickHand rather than core requiring it back, since core already
--- requires settings_ui at the bottom of this file and a mutual require would loop.
function QuickHand.set_listening(action)
	QuickHand.listening = action
	if QuickHand.refresh_bind_labels then QuickHand.refresh_bind_labels() end
end

--- @return boolean true when the key was ours and should not reach anything else
function QuickHand.handle_key(key)
	-- Checked before the panel-visibility gate: rebinding happens in the options
	-- menu, where the panel does not exist.
	if QuickHand.listening then
		if key ~= 'escape' then
			config.keys[QuickHand.listening] = key
			config.save()
			play_sound('button', 1, 0.4)
		end
		QuickHand.set_listening(nil)
		return true
	end

	if not G.HUD_quickhand or not QuickHand.is_visible() then return false end

	local inverse = not not (G.CONTROLLER and G.CONTROLLER.held_keys
		and G.CONTROLLER.held_keys[config.keys.inverse])

	for i, action in ipairs(config.HAND_KEYS) do
		if config.keys[action] == key then
			local entry = ui.entries[i]
			if entry then hands.select(entry, inverse) end
			-- Swallowed even with no hand at that position: while the panel is up the
			-- key belongs to it, and falling through would be inconsistent.
			return true
		end
	end

	for action, run in pairs(ACTIONS) do
		if config.keys[action] == key then
			run(inverse)
			return true
		end
	end

	return false
end

-- key_press_update is the seam that already knows about text fields: it swallows keys
-- into G.FUNCS.text_input_key while one is focused, so guarding on text_input_hook
-- keeps these shortcuts from firing while the player types a seed or profile name.
local key_press_update_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
	-- The original rewrites 'kp1' to '1', which would silently bind the numpad
	-- alongside the top-row digits. Reject it here, before that happens.
	if not self.text_input_hook and not self.locks.frame and string.sub(key, 1, 2) ~= 'kp' then
		if QuickHand.handle_key(key) then return end
	end

	return key_press_update_ref(self, key, dt)
end

local game_update_ref = Game.update
function Game:update(dt)
	local ret = game_update_ref(self, dt)
	ui.refresh(QuickHand.is_visible())
	return ret
end

-- Required last: it reads the QuickHand table above when wiring the options menu.
require('quickhand.settings_ui')

return QuickHand

local ui = {}

local config = require('quickhand.config')
local locale = require('quickhand.locale')
local hands = require('quickhand.hands')
local draggable_container = require('quickhand.draggablecontainer')

-- Layout, in tiles. CELL_W is the base unit: every button on the top row is exactly
-- one cell wide, the hand list spans four of them, and the invert bar spans the
-- fifth. Changing CELL_W rescales the whole panel and keeps those relationships.
--
-- Horizontal and vertical spacing are separate: stacked rows read better tighter than
-- side-by-side buttons do, so they are tuned independently rather than sharing a
-- single GAP.
local CELL_W = 0.58
local GAP = 0.06
local ROW_GAP = 0.03
local LIST_W = 4 * CELL_W + 3 * GAP
local TOTAL_W = 5 * CELL_W + 4 * GAP

local HAND_H = 0.52
local TOP_H = 0.5
local BOTTOM_H = 0.5

-- Shortest a Play/Discard button can be before its rotated label stops fitting and the
-- button starts growing on its own -- which is what made that column stick out past
-- the rest of the panel on a short hand list. Used as a floor for the panel height
-- rather than letting the text drive it.
local PLAY_LABEL_MIN_H = 1.1

-- The right-hand column is Invert with the Clear button beneath it, so the row has to
-- be tall enough for both: Clear at a fixed size, and enough left over for Invert's
-- rotated label to stay readable.
local CLEAR_H = 0.5
local INVERT_MIN_H = 1.0
local RIGHT_COLUMN_MIN_H = INVERT_MIN_H + ROW_GAP + CLEAR_H

-- The current button list. Click handlers look their entry up by index here rather
-- than capturing Card references that a rebuild would leave dangling.
ui.entries = {}

local last_signature = nil

--- Height of the hand-button column, which the invert bar has to match exactly. Must
--- stay in step with the spacers create_UIBox puts between those buttons.
local function stack_height(count)
	if count < 1 then return HAND_H end
	return count * HAND_H + (count - 1) * ROW_GAP
end

local function gap_column()
	return { n = G.UIT.C, config = { minw = GAP } }
end

local function gap_row()
	return { n = G.UIT.R, config = { minh = ROW_GAP } }
end

--- The initial of a localized name, as one whole UTF-8 character. The game's font has
--- no suit glyphs (its cmap stops well short of U+2660), so suit buttons are labelled
--- with an initial instead, and a plain sub(1,1) would slice a multi-byte name in half.
--- `utf8.pattern` is the game's own single-character pattern (misc_functions.lua).
---
--- Note this only stays unambiguous while the initials differ: English S/H/C/D and
--- Spanish P/C/T/D are fine, but German Kreuz and Karo would both render as "K". If
--- this mod ever ships German, that pair needs a second character.
local function initial(text)
	return string.upper(string.match(text, utf8.pattern) or text)
end

--- A labelled button cell of an exact size. Both the top row (always CELL_W wide, so
--- the row divides evenly and the rows below are multiples of it) and the bottom row
--- (half or full panel width) are this same shape.
local function create_cell(w, h, label, colour, tooltip, button_func, text_colour)
	return {
		n = G.UIT.C,
		config = {
			align = 'cm',
			minw = w,
			maxw = w,
			minh = h,
			r = 0.1,
			hover = true,
			shadow = true,
			colour = colour,
			button = button_func,
			tooltip = tooltip and { text = { tooltip } } or nil,
		},
		nodes = {
			{
				n = G.UIT.T,
				config = {
					text = label,
					scale = 0.3,
					colour = text_colour or G.C.UI.TEXT_LIGHT,
					shadow = true,
					maxw = w - 0.1,
				},
			},
		},
	}
end

local function create_top_row()
	local nodes = {}

	for i, suit in ipairs(hands.SUITS) do
		local name = localize(suit, 'suits_plural')
		nodes[#nodes + 1] = create_cell(
			CELL_W, TOP_H,
			initial(name),
			G.C.SUITS[suit],
			name,
			'quickhand_suit_' .. i
		)
		nodes[#nodes + 1] = gap_column()
	end

	nodes[#nodes + 1] = create_cell(
		CELL_W, TOP_H,
		locale.translate('quickhand_fill_label'),
		G.C.BLUE,
		locale.translate('quickhand_fill_tooltip'),
		'quickhand_fill'
	)

	return { n = G.UIT.R, config = { align = 'cm' }, nodes = nodes }
end

local function create_hand_button(entry, index)
	return {
		n = G.UIT.R,
		config = { align = 'cm' },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = 'cm',
					minw = LIST_W,
					maxw = LIST_W,
					minh = HAND_H,
					r = 0.1,
					colour = G.C.ORANGE,
					hover = true,
					shadow = true,
					button = 'quickhand_select',
					ref_table = { index = index },
				},
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = entry.label,
							scale = 0.36,
							colour = G.C.UI.TEXT_LIGHT,
							shadow = true,
							maxw = LIST_W - 0.15,
						},
					},
				},
			},
		},
	}
end

--- Shown when every card in hand is face down. Deliberately inert: no `button` key,
--- so it has no callback and no hover highlight, and greyed with the game's own
--- inactive colour. There is nothing legitimate to offer here, and guessing would
--- give away the very ranks the blind is hiding.
local function create_unknown_button()
	return {
		n = G.UIT.R,
		config = { align = 'cm' },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = 'cm',
					minw = LIST_W,
					maxw = LIST_W,
					minh = HAND_H,
					r = 0.1,
					colour = G.C.UI.BACKGROUND_INACTIVE,
					shadow = true,
					tooltip = { text = { locale.translate('quickhand_hidden_tooltip') } },
				},
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = '? ? ?',
							scale = 0.4,
							colour = G.C.UI.TEXT_INACTIVE,
							shadow = true,
						},
					},
				},
			},
		},
	}
end

--- The invert bar: one cell wide, spanning the full height of the row it sits in.
--- Labelled with rotated text, the same `vert = true` the game uses for its own narrow
--- side panels ("CONSUMABLES", "STAKE").
local function create_invert_bar(height)
	return {
		n = G.UIT.C,
		config = {
			align = 'cm',
			minw = CELL_W,
			maxw = CELL_W,
			minh = height,
			r = 0.1,
			hover = true,
			shadow = true,
			colour = G.C.RED,
			button = 'quickhand_invert',
			tooltip = { text = { locale.translate('quickhand_invert_tooltip') } },
		},
		nodes = {
			{
				n = G.UIT.R,
				config = { align = 'cm' },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = locale.translate('quickhand_invert_label'),
							scale = 0.34,
							colour = G.C.UI.TEXT_LIGHT,
							shadow = true,
							vert = true,
							maxh = height - 0.2,
						},
					},
				},
			},
		},
	}
end

--- The right-hand column: Invert filling the space, Clear pinned underneath it. Clear
--- sits at the far end from the -VAL button that tops this same column, so the two
--- "reset-ish" and "add-ish" actions bookend it.
local function create_invert_column(height)
	return {
		n = G.UIT.C,
		config = { align = 'cm' },
		nodes = {
			{
				n = G.UIT.R,
				config = { align = 'cm' },
				nodes = { create_invert_bar(height - ROW_GAP - CLEAR_H) },
			},
			gap_row(),
			{
				n = G.UIT.R,
				config = { align = 'cm' },
				nodes = {
					create_cell(
						CELL_W, CLEAR_H,
						locale.translate('quickhand_clear_label'),
						G.C.GREY,
						locale.translate('quickhand_clear_tooltip'),
						'quickhand_clear'
					),
				},
			},
		},
	}
end

--- Bottom row. Only exists when at least one of its buttons has something to act on.
--- Unlike the rows above it does not follow the cell grid: one button fills the whole
--- width, two split it down the middle.
local function create_bottom_row(has_debuffed, has_face_down)
	if not has_debuffed and not has_face_down then return nil end

	local both = has_debuffed and has_face_down
	local width = both and (TOTAL_W - GAP) / 2 or TOTAL_W
	local nodes = {}

	if has_debuffed then
		nodes[#nodes + 1] = create_cell(
			width, BOTTOM_H,
			locale.translate('quickhand_debuffed_label'),
			G.C.GREEN,
			locale.translate('quickhand_debuffed_tooltip'),
			'quickhand_debuffed'
		)
	end

	if both then
		nodes[#nodes + 1] = gap_column()
	end

	if has_face_down then
		nodes[#nodes + 1] = create_cell(
			width, BOTTOM_H,
			locale.translate('quickhand_facedown_label'),
			G.C.JOKER_GREY,
			locale.translate('quickhand_facedown_tooltip'),
			'quickhand_facedown',
			G.C.UI.TEXT_DARK
		)
	end

	return { n = G.UIT.R, config = { align = 'cm' }, nodes = nodes }
end

--- A copy of one of the game's own bottom-bar buttons, turned on its side.
---
--- Text, colour and behaviour all come from vanilla: the same localization key, the
--- same G.FUNCS action, and the same `func` that greys the button out when the action
--- is unavailable (can_play blanks the colour and clears the button when you have no
--- valid selection). `one_press` matches vanilla too, so a double click cannot play
--- twice -- the panel rebuilds the moment the hand changes, which re-arms it.
local function create_vanilla_action(height, loc_key, colour, button_func, enable_func)
	return {
		n = G.UIT.R,
		config = { align = 'cm' },
		nodes = {
			{
				n = G.UIT.C,
				config = {
					align = 'cm',
					minw = CELL_W,
					maxw = CELL_W,
					minh = height,
					r = 0.1,
					hover = true,
					shadow = true,
					colour = colour,
					button = button_func,
					one_press = true,
					func = enable_func,
				},
				nodes = {
					{
						n = G.UIT.R,
						config = { align = 'cm' },
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = localize(loc_key),
									scale = 0.34,
									colour = G.C.UI.TEXT_LIGHT,
									shadow = true,
									vert = true,
									maxh = height - 0.2,
								},
							},
						},
					},
				},
			},
		},
	}
end

--- Leftmost column: Play on top, Discard below, mirroring the game's own left-to-right
--- order in its bottom bar. Spans the full height of everything to its right.
local function create_play_discard_column(total_height)
	local button_h = (total_height - ROW_GAP) / 2

	return {
		n = G.UIT.C,
		config = { align = 'cm' },
		nodes = {
			create_vanilla_action(button_h, 'b_play_hand', G.C.BLUE,
				'play_cards_from_highlighted', 'can_play'),
			gap_row(),
			create_vanilla_action(button_h, 'b_discard', G.C.RED,
				'discard_cards_from_highlighted', 'can_discard'),
		},
	}
end

local function create_UIBox(entries, all_hidden, has_debuffed, has_face_down)
	local list_rows = {}
	if all_hidden then
		list_rows[1] = create_unknown_button()
	else
		for i, entry in ipairs(entries) do
			if i > 1 then
				list_rows[#list_rows + 1] = gap_row()
			end
			list_rows[#list_rows + 1] = create_hand_button(entry, i)
		end
	end

	local hand_count = all_hidden and 1 or #entries
	local bottom = create_bottom_row(has_debuffed, has_face_down)
	local extra_rows = bottom and (ROW_GAP + BOTTOM_H) or 0

	-- Every column ends up the height of the tallest, with two deliberate exceptions:
	-- the top row keeps its fixed height, and the hand list keeps its buttons at their
	-- natural size and takes up the slack as empty space underneath. Only the middle
	-- row stretches, because it is the one with room to give.
	local natural_stack = stack_height(hand_count)
	-- Floor: the right-hand column has to fit Invert *and* Clear whatever the hand list
	-- is doing.
	local stack_h = math.max(natural_stack, RIGHT_COLUMN_MIN_H)

	if config.options.show_play_discard then
		local min_total = 2 * PLAY_LABEL_MIN_H + ROW_GAP
		stack_h = math.max(stack_h, min_total - TOP_H - ROW_GAP - extra_rows)
	end

	if stack_h > natural_stack then
		list_rows[#list_rows + 1] = { n = G.UIT.R, config = { minh = stack_h - natural_stack } }
	end

	local rows = {
		create_top_row(),
		gap_row(),
		{
			n = G.UIT.R,
			config = { align = 'tm' },
			nodes = {
				{ n = G.UIT.C, config = { align = 'tm' }, nodes = list_rows },
				gap_column(),
				-- These stay live even with everything face down: which cards you have
				-- selected is on screen either way, so flipping or clearing that
				-- selection reveals nothing about the hidden ranks.
				create_invert_column(stack_h),
			},
		},
	}

	if bottom then
		rows[#rows + 1] = gap_row()
		rows[#rows + 1] = bottom
	end

	local main = { n = G.UIT.C, config = { align = 'cm' }, nodes = rows }
	local row_nodes = { main }

	if config.options.show_play_discard then
		local column = create_play_discard_column(TOP_H + ROW_GAP + stack_h + extra_rows)
		if config.options.play_discard_on_right then
			row_nodes = { main, gap_column(), column }
		else
			row_nodes = { column, gap_column(), main }
		end
	end

	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', colour = G.C.CLEAR, padding = 0.06, r = 0.1 },
		nodes = {
			{ n = G.UIT.R, config = { align = 'cm' }, nodes = row_nodes },
		},
	}
end

-- Keep at least a sliver on screen so the window can never be dragged out of reach.
local VISIBLE_MARGIN = 0.15

local function constrain_position(x, y, w, h)
	local room = G.ROOM.T
	local margin_x = math.min(VISIBLE_MARGIN, w)
	local margin_y = math.min(VISIBLE_MARGIN, h)

	return math.max(margin_x - w, math.min(x, room.w - margin_x)),
		math.max(margin_y - h, math.min(y, room.h - margin_y))
end

local function reset(entries, visible, all_hidden, has_debuffed, has_face_down)
	local prev_pos
	if G.HUD_quickhand then
		prev_pos = { x = G.HUD_quickhand.T.x, y = G.HUD_quickhand.T.y }
		G.HUD_quickhand:remove()
		G.HUD_quickhand = nil
	end

	if not visible or (#entries == 0 and not all_hidden) then return end

	local position = { x = config.position.x, y = config.position.y }
	prev_pos = prev_pos or position

	G.HUD_quickhand = draggable_container({
		T = { x = position.x, y = position.y },
		VT = { x = prev_pos.x, y = prev_pos.y },
		config = { major = G, bond = 'Weak' },
		definition = create_UIBox(entries, all_hidden, has_debuffed, has_face_down),
		-- No zoom: the inherited hover scaling is meant for a passive display like a
		-- clock. On a panel of buttons it resizes the whole thing under the cursor.
		zoom = false,
		can_drag = not config.options.lock_position,
	})

	local widget = G.HUD_quickhand

	-- The inherited hover juices the entire panel. That momentarily changes its size,
	-- which moves the child hitboxes out from under a cursor resting near an edge --
	-- hover ends, the panel springs back, hover fires again: a rapid shrink/grow
	-- oscillation. The buttons already give their own hover feedback, so drop it.
	widget.hover = function(self)
		UIBox.hover(self)
	end
	widget.stop_hover = function(self)
		UIBox.stop_hover(self)
	end

	local x, y = constrain_position(widget.T.x, widget.T.y, widget.T.w, widget.T.h)
	if x ~= widget.T.x or y ~= widget.T.y then
		widget.T.x, widget.T.y = x, y
		config.position.x, config.position.y = x, y
		config.save()
	end

	-- Constrain during the drag rather than on release, so it slides along the edge
	-- instead of being yanked back once dropped.
	widget.drag = function(self)
		draggable_container.drag(self)
		self.T.x, self.T.y = constrain_position(self.T.x, self.T.y, self.T.w, self.T.h)
	end

	widget.stop_drag = function(self)
		draggable_container.stop_drag(self)
		config.position.x, config.position.y = self.T.x, self.T.y
		config.save()
	end
end

--- Forces the next refresh to rebuild. Called when an option changes shape or
--- behaviour of the panel, since those do not move the hand signature.
function ui.invalidate()
	last_signature = nil
end

--- Called once per frame. Rebuilds only when the set of available hands changes, or
--- when the window was wiped by a scene transition.
function ui.refresh(visible)
	if not visible then
		if last_signature ~= nil then
			reset({}, false)
			ui.entries = {}
			last_signature = nil
		end
		return
	end

	local signature, entries, all_hidden, debuffed, face_down = hands.signature()
	if signature ~= last_signature or not G.HUD_quickhand then
		ui.entries = entries or {}
		reset(ui.entries, true, all_hidden, (debuffed or 0) > 0, (face_down or 0) > 0)
		last_signature = signature
	end
end

return ui

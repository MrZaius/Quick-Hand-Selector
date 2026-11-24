local hands = {}

local config = require('quickhand.config')

local DEBUG_HANDS = false

local function debug_log(message)
	if not DEBUG_HANDS then return end

	local text = '[QuickHand debug] ' .. tostring(message)
	if sendInfoMessage then
		sendInfoMessage(text, 'QuickHand')
	else
		print(text)
	end
end

debug_log('hands.lua loaded')

local function describe_card(card)
	local base = card.base or {}
	local ability = card.ability or {}
	local center = card.config and card.config.center
	return table.concat({
		'ID=' .. tostring(card.ID),
						'base.id=' .. tostring(base.id),
						'base.value=' .. tostring(base.value),
						'base.suit=' .. tostring(base.suit),
						'effect=' .. tostring(ability.effect),
						'center=' .. tostring(center and center.key),
						'facing=' .. tostring(card.facing),
	}, ' ')
end

local function describe_cards(cards)
	local parts = {}
	for i, card in ipairs(cards or {}) do
		parts[i] = describe_card(card)
	end
	return table.concat(parts, ' | ')
end

local function debug_evaluate(label, cards)
	local evaluated = evaluate_poker_hand(cards)
	local lines = {}

	for _, key in ipairs(hands.ORDER) do
	local matches = evaluated[key]
	if matches and next(matches) then
		for i, combo in ipairs(matches) do
			lines[#lines + 1] =
			label .. ' ' .. key .. '[' .. i .. ']: '
			.. describe_cards(combo)
		end
	end
	end

	if #lines == 0 then
				debug_log(label .. ': no poker hands found')
	else
		for _, line in ipairs(lines) do
			debug_log(line)
		end
	end
end

-- Static hand-rank order, best first. This is deliberately the *base* ranking and
-- nothing else: no hand levels, no chips/mult, no joker scoring. The mod exists to
-- save clicks, not to work out the best play for you -- that's the actual game.
-- Mechanics that change which hands are *possible* (Four Fingers, Shortcut) are
-- still respected, because evaluate_poker_hand below is the game's own function and
-- consults them internally.
hands.ORDER = {
	'Flush Five',
	'Flush House',
	'Five of a Kind',
	'Straight Flush',
	'Four of a Kind',
	'Full House',
	'Flush',
	'Straight',
	'Three of a Kind',
	'Two Pair',
	'Pair',
	'High Card',
}

hands.SUITS = { 'Spades', 'Hearts', 'Clubs', 'Diamonds' }

local function highlight_limit()
	return (G.hand and G.hand.config and G.hand.config.highlighted_limit) or 5
end

local function is_face_down(card)
	return card.facing == 'back'
end

--- Face-up and debuffed. Debuff state is only knowable for a card you can read, so a
--- face-down card never counts here even if it happens to be debuffed.
local function is_known_debuffed(card)
	return not is_face_down(card) and card.debuff
end

--- The cards the player can actually read. Blinds like The Fish or The Wheel deal
--- cards face down, and their rank is information the player is not supposed to
--- have -- so they never reach the evaluator. Without this the mod would quietly
--- defeat those blinds by announcing what is hidden.
local function face_up_cards()
	local visible = {}
	if not G.hand or not G.hand.cards then return visible end

	for _, card in ipairs(G.hand.cards) do
		if not is_face_down(card) then
			visible[#visible + 1] = card
		end
	end
	return visible
end


-- Card:get_id() is NOT stable: for a Stone Card it returns -math.random(100, 1000000),
-- a fresh number on every call (card.lua:957). Comparing it inside a sort comparator
-- gives table.sort an inconsistent ordering, which LuaJIT rejects outright with
-- "invalid order function for sorting". Read each rank exactly once instead.
local function sort_by_rank(cards, descending)
	local rank = {}
	for _, card in ipairs(cards) do
		rank[card] = card:get_id()
	end

	table.sort(cards, function(a, b)
		if descending then return rank[a] > rank[b] end
		return rank[a] < rank[b]
	end)
end

--- Orders candidates into three buckets, then by rank within them.
---
--- `descending` picks which end matters: best cards first, for actions about keeping
--- cards, or most expendable first, for actions about throwing them away. Either way
--- debuffed cards land on the expendable end -- they score zero chips and zero mult,
--- so a debuffed King is neither a good keep nor a bad discard.
---
--- Face-down cards always come last, in hand order, and are ordered by neither rank
--- nor debuff state: you can read neither through the back of a card, so using them
--- would leak exactly what a face-down blind is hiding.
---
--- This is a plain sort by rank, not an evaluation: no hand levels, no chips, no mult,
--- no jokers. Which cards are actually worth keeping stays the player's call.
local function order_cards(candidates, descending)
	local live, debuffed, face_down = {}, {}, {}
	local separate_debuffed = config.options.debuffed_first

	for _, card in ipairs(candidates) do
		if is_face_down(card) then
			face_down[#face_down + 1] = card
		elseif separate_debuffed and is_known_debuffed(card) then
			debuffed[#debuffed + 1] = card
		else
			live[#live + 1] = card
		end
	end

	sort_by_rank(live, descending)
	sort_by_rank(debuffed, descending)

	local order = descending and { live, debuffed, face_down } or { debuffed, live, face_down }

	local result = {}
	for _, group in ipairs(order) do
		for _, card in ipairs(group) do
			result[#result + 1] = card
		end
	end

	return result
end
-- Hands the whole-hand pass cannot report, because vanilla only ever calls the
-- evaluator with a played hand of at most five cards and takes shortcuts that are safe
-- only under that assumption. Both are found by asking about five-card subsets, where
-- the assumption holds again.
--
--   * Flush family and Straight: get_flush and get_straight bail out immediately on
--     `#hand > 5`, so a full eight-card hand reports neither.
--   * Two Pair: guarded by `#parts._2 == 2`, an *exact* count. Three pairs in hand is
--     impossible in five cards but ordinary in eight, and makes the test false -- so
--     holding three pairs silently offered no Two Pair at all.
--
-- Everything else uses `next()` and is unaffected by hand size.
local SUBSET_ONLY = {
	'Flush Five',
	'Flush House',
	'Straight Flush',
	'Flush',
	'Straight',
	'Two Pair',
}

-- Guard against pathological hand sizes: C(n,5) grows fast and this runs on every
-- hand change. Twelve cards is 792 subsets, already well past any real Balatro hand.
local MAX_SUBSET_SEARCH_CARDS = 12

-- The evaluator hands back oversized card sets for the rank-based hands, because its
-- "downgrade" pass at the end slices the wrong thing:
--
--     results["Pair"] = {results["Three of a Kind"][1], results["Three of a Kind"][2]}
--
-- `[1]` and `[2]` are *combinations*, not cards, so Pair ends up holding the whole
-- triple. Likewise a four-of-a-kind leaks into Three of a Kind and Pair, and a
-- three-of-a-kind plus a pair makes Two Pair the five-card full house. Vanilla never
-- notices: those downgraded entries exist only so a played hand can be named, and the
-- higher hand always wins. Reading every key, as this mod does, exposes them -- and
-- pressing "Pair" would select a triple, which the game then scores as one.
--
-- Trimming to the first N cards is always valid here: any two of three matching cards
-- are a pair, any four of the full-house set are two pairs, and so on. Flush and
-- straight families are deliberately absent, since Four Fingers legitimately makes
-- those four cards long.
local EXACT_SIZE = {
	['Pair'] = 2,
	['Two Pair'] = 4,
	['Three of a Kind'] = 3,
	['Four of a Kind'] = 4,
}

local function trim_to_size(key, cards)
	local size = EXACT_SIZE[key]
	if not size or #cards <= size then return cards end

	local trimmed = {}
	for i = 1, size do
		trimmed[i] = cards[i]
	end
	return trimmed
end

--- Identifies a combination regardless of card order, so the same flush reached from
--- several different subsets is only recorded once.
local function combination_key(cards)
	local ids = {}
	for i, card in ipairs(cards) do
		ids[i] = card.ID or 0
	end
	table.sort(ids)
	return table.concat(ids, ',')
end

local function rank_total(cards)
	local total = 0
	for _, card in ipairs(cards) do
		total = total + card:get_id()
	end
	return total
end

--- Asks the game's own evaluator about five-card subsets, so flush/straight detection
--- stays the game's logic (and keeps honouring Four Fingers and Shortcut) instead of
--- being reimplemented here and drifting from it.
---
--- Collects *every* distinct combination rather than stopping at the first, so the
--- buttons can cycle through alternatives the way the rank-based hands already can.
local function find_subset_hands(visible, found)
	local n = #visible
	if n <= 5 or n > MAX_SUBSET_SEARCH_CARDS then return end

	-- Seed the dedupe from whatever the whole-hand pass already found. Today that pass
	-- returns nothing for these five keys (get_flush/get_straight bail above five
	-- cards), so the two passes cannot overlap -- but relying on that would make this
	-- correct only by accident, and a game patch lifting the limit would silently list
	-- every flush twice.
	local seen = {}
	for _, key in ipairs(SUBSET_ONLY) do
		if found[key] then
			seen[key] = {}
			for _, cards in ipairs(found[key]) do
				seen[key][combination_key(cards)] = true
			end
		end
	end

	local subset = {}
	local idx = { 1, 2, 3, 4, 5 }

	while true do
		for i = 1, 5 do
			subset[i] = visible[idx[i]]
		end

		local evaluated = evaluate_poker_hand(subset)
		for _, key in ipairs(SUBSET_ONLY) do
			local matches = evaluated[key]
			if matches and next(matches) then
				for _, cards in ipairs(matches) do
					cards = trim_to_size(key, cards)
					local ck = combination_key(cards)
					seen[key] = seen[key] or {}
					if not seen[key][ck] then
						seen[key][ck] = true
						-- Copy: `subset` is reused for the next combination, and the
						-- evaluator hands back references into it.
						local copy = {}
						for i, card in ipairs(cards) do
							copy[i] = card
						end
						found[key] = found[key] or {}
						found[key][#found[key] + 1] = copy
					end
				end
			end
		end

		-- Next combination in lexicographic order.
		local i = 5
		while i >= 1 and idx[i] == n - 5 + i do
			i = i - 1
		end
		if i < 1 then break end
		idx[i] = idx[i] + 1
		for j = i + 1, 5 do
			idx[j] = idx[j - 1] + 1
		end
	end

	-- Subsets are visited in hand order, which says nothing about card values. Sort so
	-- the first press gives the highest-value combination, matching what get_X_same
	-- already does for the rank-based hands.
	for _, key in ipairs(SUBSET_ONLY) do
		if found[key] then
			table.sort(found[key], function(a, b)
				return rank_total(a) > rank_total(b)
			end)
		end
	end
end

--- Every poker hand currently makeable from the *readable* cards in hand, best rank
--- first.
--- @return table entries, boolean all_hidden
function hands.available()
local visible = face_up_cards()

debug_log('whole-hand input: ' .. describe_cards(visible))

if #visible == 0 then
	local has_cards = G.hand and G.hand.cards and #G.hand.cards > 0
	debug_log('whole-hand: no visible cards')
	return {}, has_cards and true or false
	end

	local evaluated = evaluate_poker_hand(visible)
	debug_evaluate('whole-hand result', visible)

	local found = {}
	for _, key in ipairs(hands.ORDER) do
		-- These keys require five-card subset evaluation for oversized hands.
		local subset_only = false
		for _, subset_key in ipairs(SUBSET_ONLY) do
			if key == subset_key then
				subset_only = true
				break
				end
				end

				if not subset_only then
					local matches = evaluated[key]
					if matches and next(matches) then
						local combinations = {}
						for i, cards in ipairs(matches) do
							combinations[i] = trim_to_size(key, cards)
							end
							found[key] = combinations
							end
							end
							end

				find_subset_hands(visible, found)

				if found['High Card'] then
					local combinations = {}
					for i, card in ipairs(order_cards(visible, true)) do
						combinations[i] = { card }
						end
						found['High Card'] = combinations
						end

						local result = {}
						for _, key in ipairs(hands.ORDER) do
							if found[key] and #found[key] > 0 then
								result[#result + 1] = {
									key = key,
									label = localize(key, 'poker_hands'),
									combinations = found[key],
								}
								end
								end

								debug_log('available hands: ' .. table.concat(
									(function()
									local names = {}
									for i, entry in ipairs(result) do
										names[i] = entry.key
										end
										return names
										end)(),
																			  ', '
								))

								return result, false
								end

-- Cheap, allocation-free change detection. Card.ID is unique per instance, so any
-- draw, discard or transformation moves the sum; reordering does not, which is
-- correct because sorting cannot change which hands are makeable.
--
-- Facing and debuff counts are tracked as separate values rather than folded into the
-- same number: a boss flipping cards or debuffing a suit has to rebuild the buttons,
-- and adding those counts to the ID sum could cancel out against an ID change and
-- silently skip the refresh.
local last_checksum = nil
local last_hidden = nil
local last_debuffed = nil
local last_available = nil
local last_all_hidden = false

--- @return number|nil signature, table|nil entries, boolean all_hidden,
---         number debuffed_count, number face_down_count
function hands.signature()
	if not G.hand or not G.hand.cards then
		last_checksum, last_hidden, last_debuffed, last_available = nil, nil, nil, nil
		return nil, nil, false, 0, 0
	end

	local checksum = #G.hand.cards * 1e7
	local hidden, debuffed = 0, 0
	for _, card in ipairs(G.hand.cards) do
		checksum = checksum + (card.ID or 0)
		if is_face_down(card) then
			hidden = hidden + 1
		elseif card.debuff then
			debuffed = debuffed + 1
		end
	end

	if checksum ~= last_checksum or hidden ~= last_hidden or debuffed ~= last_debuffed then
		last_checksum, last_hidden, last_debuffed = checksum, hidden, debuffed
		last_available, last_all_hidden = hands.available()
		-- New cards on the table: whatever the player had set aside before an invert,
		-- and wherever they were in a hand's combination cycle, refer to a hand that
		-- no longer exists.
		hands.forget_kept()
		hands.reset_cycle()
	end

	return checksum + hidden * 3 + debuffed * 7, last_available, last_all_hidden, debuffed, hidden
end

-- What was selected immediately before the last invert. `fill` skips these, so the
-- "keep these -> invert -> top up the rest" flow never claws back the cards the
-- player set aside. Weak keys: a discard must not keep dead Cards alive through this.
local kept_before_invert = nil

-- Exposed on the module rather than kept local: signature() is defined above this
-- point and needs to clear it when the hand changes.
function hands.forget_kept()
	kept_before_invert = nil
end

--- Adds cards without clearing what is already selected.
local function add_cards(cards)
	local limit = highlight_limit()
	for i = 1, #cards do
		if #G.hand.highlighted >= limit then break end
		-- silent = true: add_to_highlighted plays a card sound per card, which turns
		-- into five overlapping clicks when a whole hand goes in at once. Callers play
		-- a single sound instead. It enforces highlighted_limit itself too, but the
		-- check above keeps the intent visible at the call site.
		G.hand:add_to_highlighted(cards[i], true)
	end
end

local function select_cards(cards)
	if not G.hand then return end
	G.hand:unhighlight_all()
	add_cards(cards)
end

-- Which hand button was pressed last, and how far into its list of combinations we
-- are. Pressing the same button again steps to the next combination; pressing
-- anything else starts over at the highest-value one.
local cycle_key = nil
local cycle_index = 1

function hands.reset_cycle()
	cycle_key = nil
	cycle_index = 1
end

--- Highlights the cards forming the given hand. Repeated presses of the same button
--- walk through the alternative combinations for that hand -- two pairs on the table
--- give the high pair first, then the low one, then back around.
---
--- `inverse` selects everything *except* that hand instead, lowest value first: the
--- same result as pressing this button and then Invert, in one action. It still walks
--- the cycle, so repeated presses invert each alternative combination in turn.
function hands.select(entry, inverse)
local combinations = entry and entry.combinations
if not combinations or #combinations == 0 then return end

	-- Picking a hand is a fresh start; the previous keep/invert intent no longer applies.
	hands.forget_kept()

	if cycle_key == entry.key then
		cycle_index = cycle_index % #combinations + 1
		else
			cycle_key = entry.key
			cycle_index = 1
			end

			local chosen = combinations[cycle_index]

			debug_log(
				'select key=' .. tostring(entry.key)
				.. ' cycle=' .. tostring(cycle_index) .. '/' .. tostring(#combinations)
				.. ' inverse=' .. tostring(not not inverse)
				.. ' cards=' .. describe_cards(chosen)
			)

			if inverse then
				local in_hand = {}
				for _, card in ipairs(chosen) do
					in_hand[card] = true
					end

					local rest = {}
					for _, card in ipairs(G.hand.cards) do
						if not in_hand[card] then
							rest[#rest + 1] = card
							end
							end

							if #rest == 0 then return end
								select_cards(order_cards(rest, false))
								else
									select_cards(chosen)
									end

									play_sound('cardSlide1', 1, 0.5)
end
--- Tops the selection up to the game's current limit with the most expendable cards
--- that are not selected (see order_cards: debuffed first, then lowest rank). The
--- limit is read from the CardArea, so jokers that raise or lower how many cards may
--- be selected are respected automatically.
---
--- Cards the player had selected right before the last invert are skipped: the
--- intended flow is "select what you want to keep -> invert -> fill the rest", and
--- re-adding the kept cards would defeat it.
--- `inverse` tops up with the highest-value cards instead of the lowest.
function hands.fill(inverse)
	if not G.hand or not G.hand.cards then return end

	-- A different button: the next press of a hand button starts its cycle over.
	hands.reset_cycle()

	local limit = highlight_limit()
	if #G.hand.highlighted >= limit then return end

	local selected = {}
	for _, card in ipairs(G.hand.highlighted) do
		selected[card] = true
	end

	local candidates = {}
	for _, card in ipairs(G.hand.cards) do
		if not selected[card]
			and not (kept_before_invert and kept_before_invert[card])
			and not (config.options.skip_face_down and is_face_down(card)) then
			candidates[#candidates + 1] = card
		end
	end

	if #candidates == 0 then return end

	add_cards(order_cards(candidates, inverse))
	play_sound('cardSlide1', 0.9, 0.5)
end

--- Clears the selection and every scrap of state the panel was carrying: which cards
--- were set aside before the last invert, and how far into a hand's combinations the
--- cycle had walked. A genuine fresh start rather than just an empty selection.
function hands.clear()
	if not G.hand then return end

	hands.reset_cycle()
	hands.forget_kept()
	G.hand:unhighlight_all()
	play_sound('cancel', 1, 0.4)
end

--- Selects cards of one suit, up to the selection limit. Best first by default; the
--- `suit_highest_first` option flips that to lowest first, for players who use these
--- buttons to clear a suit out rather than to build a flush.
---
--- `inverse` selects the lowest-value readable cards that are *not* of that suit. That
--- direction always starts from the lowest value, matching the other inverse actions,
--- and is not affected by the option above.
---
--- Face-down cards are excluded either way: their suit is exactly what the back of a
--- card hides, so they can be neither confirmed nor ruled out as members of a suit.
--- `is_suit(suit, nil, true)` is the same call get_flush makes, so Wild Cards and
--- Smeared Joker are honoured -- a Wild Card legitimately answers to every suit.
function hands.select_suit(suit, inverse)
	if not G.hand or not G.hand.cards then return end
	hands.reset_cycle()
	hands.forget_kept()

	local candidates = {}
	for _, card in ipairs(G.hand.cards) do
		if not is_face_down(card) then
			local matches = card:is_suit(suit, nil, true)
			if (not not matches) ~= (not not inverse) then
				candidates[#candidates + 1] = card
			end
		end
	end

	if #candidates == 0 then return end

	local best_first = config.options.suit_highest_first and not inverse
	select_cards(order_cards(candidates, best_first))
	play_sound('cardSlide1', 1, 0.5)
end

--- Selects the lowest-value debuffed cards. They score nothing, so they are the
--- natural first thing to throw away.
---
--- `inverse` selects the lowest-value cards that are *not* debuffed.
function hands.select_debuffed(inverse)
	if not G.hand or not G.hand.cards then return end
	hands.reset_cycle()
	hands.forget_kept()

	local candidates = {}
	for _, card in ipairs(G.hand.cards) do
		if (not not is_known_debuffed(card)) ~= (not not inverse) then
			candidates[#candidates + 1] = card
		end
	end

	if #candidates == 0 then return end

	select_cards(order_cards(candidates, false))
	play_sound('cardSlide1', 0.95, 0.5)
end

--- Selects face-down cards, in hand order. There is no "lowest" to honour here --
--- their ranks are hidden, and ordering by them would leak what the blind conceals.
---
--- `inverse` selects the lowest-value cards that are *not* face down.
function hands.select_face_down(inverse)
	if not G.hand or not G.hand.cards then return end
	hands.reset_cycle()
	hands.forget_kept()

	local candidates = {}
	for _, card in ipairs(G.hand.cards) do
		if (not not is_face_down(card)) ~= (not not inverse) then
			candidates[#candidates + 1] = card
		end
	end

	if #candidates == 0 then return end

	-- order_cards keeps face-down cards in hand order, so the non-inverse case still
	-- gets them in the order they sit in, and the inverse case sorts real ranks.
	select_cards(order_cards(candidates, false))
	play_sound('cardSlide1', 0.95, 0.5)
end

--- Selects everything that is currently *not* selected. Face-down cards are included
--- -- which of them you have selected is visible to you, so that leaks nothing.
--- When the inverted set overflows the highlight limit, order_cards decides which
--- cards win the remaining slots.
function hands.invert()
	if not G.hand or not G.hand.cards then return end

	-- A different button: the next press of a hand button starts its cycle over.
	hands.reset_cycle()

	local selected = setmetatable({}, { __mode = 'k' })
	for _, card in ipairs(G.hand.highlighted) do
		selected[card] = true
	end

	local candidates = {}
	for _, card in ipairs(G.hand.cards) do
		if not selected[card]
			and not (config.options.skip_face_down and is_face_down(card)) then
			candidates[#candidates + 1] = card
		end
	end

	select_cards(order_cards(candidates, false))

	-- Remember what was just deselected, so a following `fill` leaves it alone.
	-- Only when the player wants the "keep these -> invert -> fill the rest" flow. With
	-- the option off, fill treats every unselected card as fair game.
	kept_before_invert = config.options.remember_kept and selected or nil
	play_sound('cardSlide1', 1.1, 0.5)
end

return hands

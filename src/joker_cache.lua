-- Correct whole-hand evaluator results that can contain too many cards by rebuilding
-- those hand types from five-card subsets. Keep the game's evaluator in charge of
-- validity so Four Fingers and Shortcut remain respected.
local hands = require('quickhand.hands')

local SUBSET_ONLY = {
	'Flush Five',
	'Flush House',
	'Straight Flush',
	'Flush',
	'Straight',
	'Two Pair',
}

local SUBSET_ONLY_SET = {}
for _, key in ipairs(SUBSET_ONLY) do
	SUBSET_ONLY_SET[key] = true
end

local EXACT_SIZE = {
	['Pair'] = 2,
	['Two Pair'] = 4,
}

local MAX_SUBSET_SEARCH_CARDS = 12
local original_available = hands.available

local function visible_hand_cards()
	local visible = {}
	if not G or not G.hand or not G.hand.cards then return visible end

	for _, card in ipairs(G.hand.cards) do
		if card.facing ~= 'back' then
			visible[#visible + 1] = card
		end
	end
	return visible
end

local function trim_to_size(key, cards)
	local size = EXACT_SIZE[key]
	if not size or #cards <= size then return cards end

	local trimmed = {}
	for i = 1, size do
		trimmed[i] = cards[i]
	end
	return trimmed
end

local function combination_key(cards)
	local ids = {}
	for i, card in ipairs(cards) do
		ids[i] = card.ID or 0
	end
	table.sort(ids)
	return table.concat(ids, ',')
end

local function combination_score(cards)
	local score = 0
	for _, card in ipairs(cards) do
		-- Cache each value once per combination: Card:get_id() is not stable for Stone Cards.
		score = score + card:get_id()
	end
	return score
end

local function find_subset_combinations(visible)
	local found = {}
	local n = #visible
	local subset = {}
	local indices = { 1, 2, 3, 4, 5 }

	while true do
		for i = 1, 5 do
			subset[i] = visible[indices[i]]
		end

		local evaluated = evaluate_poker_hand(subset)
		for _, key in ipairs(SUBSET_ONLY) do
			local matches = evaluated[key]
			if matches and next(matches) then
				local seen = found[key] and found[key].seen
				if not seen then
					seen = {}
					found[key] = { seen = seen, items = {} }
				end

				for _, match in ipairs(matches) do
					local cards = trim_to_size(key, match)
					local id = combination_key(cards)
					if not seen[id] then
						seen[id] = true
						local copy = {}
						for i, card in ipairs(cards) do
							copy[i] = card
						end
						found[key].items[#found[key].items + 1] = {
							cards = copy,
							score = combination_score(copy),
						}
					end
				end
			end
		end

		local i = 5
		while i >= 1 and indices[i] == n - 5 + i do
			i = i - 1
		end
		if i < 1 then break end
		indices[i] = indices[i] + 1
		for j = i + 1, 5 do
			indices[j] = indices[j - 1] + 1
		end
	end

	for _, result in pairs(found) do
		table.sort(result.items, function(a, b)
			return a.score > b.score
		end)
	end

	return found
end

hands.available = function()
	local visible = visible_hand_cards()
	-- The game evaluator is reliable for five-card hands. Keep its original behavior
	-- above the subset-search guard rather than dropping these hand types altogether.
	if #visible <= 5 or #visible > MAX_SUBSET_SEARCH_CARDS then
		return original_available()
	end

	local original_entries, all_hidden = original_available()
	local original_by_key = {}
	for _, entry in ipairs(original_entries or {}) do
		original_by_key[entry.key] = entry
	end

	local subset_results = find_subset_combinations(visible)
	local entries = {}
	for _, key in ipairs(hands.ORDER) do
		local combinations
		if SUBSET_ONLY_SET[key] then
			local result = subset_results[key]
			if result and #result.items > 0 then
				combinations = {}
				for i, item in ipairs(result.items) do
					combinations[i] = item.cards
				end
			end
		else
			local entry = original_by_key[key]
			combinations = entry and entry.combinations
		end

		if combinations and #combinations > 0 then
			local original_entry = original_by_key[key]
			entries[#entries + 1] = {
				key = key,
				label = original_entry and original_entry.label or localize(key, 'poker_hands'),
				combinations = combinations,
			}
		end
	end

	return entries, all_hidden
end

-- The hand cache tracks card changes, but a Joker can change which hands are possible
-- without changing the hand. Include Joker identity and active state in the signature;
-- on such a change, recompute availability once and keep it cached until the next change.
local original_signature = hands.signature
local last_hand_signature
local last_joker_signature
local cached_entries
local cached_all_hidden

local function joker_signature()
	local jokers = G and G.jokers and G.jokers.cards
	if not jokers then return '' end

	local parts = {}
	for i, card in ipairs(jokers) do
		local center = card.config and card.config.center
		local edition = card.edition
		parts[i] = table.concat({
			tostring(card.ID or ''),
			tostring(center and center.key or ''),
			tostring(not not card.debuff),
			tostring(edition and edition.key or ''),
		}, ':')
	end
	return table.concat(parts, '|')
end

hands.signature = function()
	local signature, entries, all_hidden, debuffed, face_down = original_signature()
	local jokers_now = joker_signature()

	if signature == nil then
		last_hand_signature = nil
		last_joker_signature = jokers_now
		cached_entries, cached_all_hidden = nil, false
		return nil, entries, all_hidden, debuffed, face_down
	end

	if signature ~= last_hand_signature then
		last_hand_signature = signature
		cached_entries, cached_all_hidden = entries, all_hidden
	elseif jokers_now ~= last_joker_signature then
		cached_entries, cached_all_hidden = hands.available()
	end
	last_joker_signature = jokers_now

	if cached_entries == nil then
		cached_entries, cached_all_hidden = hands.available()
	end

	-- UI refresh compares this value for equality; string composition avoids checksum
	-- collisions between otherwise-identical hands with different Joker states.
	return tostring(signature) .. '|' .. jokers_now,
		cached_entries, cached_all_hidden, debuffed, face_down
end

return hands

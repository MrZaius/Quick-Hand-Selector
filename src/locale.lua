local locale = {}

-- Keys match G.SETTINGS.language exactly (game.lua's LANGUAGES table), not the
-- lowercase module names -- those are just Lovely module identifiers.
local DICTIONARIES = {
	['de'] = require('quickhand.locale.de').misc.dictionary,
	['en-us'] = require('quickhand.locale.en-us').misc.dictionary,
	['es_419'] = require('quickhand.locale.es_419').misc.dictionary,
	['es_ES'] = require('quickhand.locale.es_es').misc.dictionary,
	['fr'] = require('quickhand.locale.fr').misc.dictionary,
	['id'] = require('quickhand.locale.id').misc.dictionary,
	['it'] = require('quickhand.locale.it').misc.dictionary,
	['ja'] = require('quickhand.locale.ja').misc.dictionary,
	['ko'] = require('quickhand.locale.ko').misc.dictionary,
	['nl'] = require('quickhand.locale.nl').misc.dictionary,
	['pl'] = require('quickhand.locale.pl').misc.dictionary,
	['pt_BR'] = require('quickhand.locale.pt_br').misc.dictionary,
	['ru'] = require('quickhand.locale.ru').misc.dictionary,
	['zh_CN'] = require('quickhand.locale.zh_cn').misc.dictionary,
	['zh_TW'] = require('quickhand.locale.zh_tw').misc.dictionary,
}

function locale.translate(key)
	-- Steamodded is not required by this mod, but if it is present its localization
	-- table wins so the strings stay consistent with the rest of the UI.
	if SMODS and G.localization and G.localization.misc and G.localization.misc.dictionary
		and G.localization.misc.dictionary[key] then
		return localize(key)
	end

	local language = G.SETTINGS and G.SETTINGS.language or 'en-us'
	local dictionary = DICTIONARIES[language] or DICTIONARIES['en-us']
	return dictionary[key] or DICTIONARIES['en-us'][key] or key
end

return locale

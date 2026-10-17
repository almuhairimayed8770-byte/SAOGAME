--!strict
--[[
	Naming blocklist (section 3, D-014).

	This is the ONLY file in the repository allowed to hold names from the source franchise, and
	it exists so the naming validator (tools/validators/naming.luau) can prove none of them appear
	anywhere else: not in code, comments, data, tests, docs or the place files. It lives under
	tools/ and is never shipped: Rojo builds only src/, and the place projects never reference it.

	Entries are lowercase. `whole = true` entries match only as a whole word (word characters on
	neither side), for terms that are also ordinary English or short enough to sit inside another
	word. `whole = false` entries match as a substring, so plurals and compounds are caught.

	Do not add Skyspire terms here. Do not reference this file from src/.
]]

export type Entry = { term: string, whole: boolean }

local function sub(term: string): Entry
	return { term = term, whole = false }
end

local function whole(term: string): Entry
	return { term = term, whole = true }
end

local Blocklist: { Entry } = {
	-- The franchise, its abbreviation and its hardware
	sub("sword art online"),
	whole("sao"),
	sub("nervegear"),
	sub("nerve gear"),
	whole("link start"),

	-- The section 3 table, left column
	sub("aincrad"), -- the floating castle -> The Spire
	sub("town of beginnings"), -- -> Firstlight
	sub("sword skill"), -- -> Blade Arts (catches the plural)
	whole("col"), -- the currency -> Crowns
	sub("teleport crystal"), -- -> Gate Shard
	sub("healing crystal"), -- -> Mend Shard
	sub("corridor crystal"), -- -> Corridor Shard
	sub("dual blades"), -- -> Twin Fang / Dual Wielder
	sub("holy sword"), -- -> Aegis
	sub("knights of the blood"), -- -> The Ivory Vow
	whole("kob"), -- the knights' abbreviation
	whole("the army"), -- -> The Bulwark Legion
	sub("laughing coffin"), -- -> Hollow Grin
	whole("beater"), -- the beta-tester slur -> Trialist
	whole("beaters"),
	sub("monument of life"), -- -> The Roll of Names
	whole("cardinal"), -- the system AI -> The Warden
	sub("heathcliff"), -- the game master's alias -> The Architect / Castellan
	sub("kayaba"), -- the game master
	sub("akihiko"),
	whole("yui"), -- the child AI -> Lumi
	whole("pina"), -- the feathered dragon pet -> Plume
	sub("coat of midnight"), -- the hero's coat -> Mantle of Last Light
	sub("blackwyrm"),
	sub("elucidator"), -- the hero's swords -> Nightfall / Glacier Edge
	sub("dark repulser"),
	sub("lambent light"), -- the rapier -> Lucent Needle
	sub("anneal blade"), -- the first sword -> Tempered Edge
	sub("starburst stream"), -- the 16-hit combo -> Meteor Cascade
	whole("the eclipse"), -- the 27-hit combo -> Umbral Reign
	sub("vorpal strike"), -- the thrust skill -> Lance Thrust
	sub("illfang"), -- the floor 1 boss -> Grolak
	sub("kobold lord"),
	sub("gleam eyes"), -- the floor 74 boss -> Stareblight Colossus
	sub("skull reaper"), -- the floor 75 boss -> Ossuary Reaper
	whole("coral"), -- the floor 22 lake floor -> Mirrorlake
	sub("immortal object"), -- the popup -> Warded Object

	-- Main characters and the hero's epithet
	sub("kirito"),
	sub("kirigaya"),
	sub("kazuto"),
	sub("black swordsman"),
	sub("asuna"),
	whole("yuuki"),
	whole("klein"),
	whole("agil"),
	sub("lisbeth"),
	whole("silica"),
	whole("sachi"),
	sub("kuradeel"),
	sub("kibaou"),
	sub("diavel"),
	whole("argo"),
	sub("godfree"),
	sub("rosalia"),
	sub("nishida"),
	sub("grimlock"),
	sub("fuurinkazan"), -- the friend's guild
	sub("moonlit black cats"), -- the guild that dies
	sub("divine dragon alliance"),
	whole("argus"), -- the in-fiction developer

	-- Towns, floors and places shown in the first season (town names are invented per floor here)
	sub("tolbana"), -- floor 1's second town
	sub("horunka"), -- the floor 1 village
	whole("taft"), -- floor 11 (also an English surname)
	whole("mishe"), -- floor 35 (sits inside "skirmisher", so whole word)
	whole("floria"), -- floor 47
	sub("lindarth"), -- floor 48
	sub("algade"), -- floor 50
	sub("grandzam"), -- floor 55
	whole("danac"), -- floor 59
	sub("selmburg"), -- floor 61
	sub("kamdet"), -- floor 74
	sub("black iron palace"), -- the hall of the life monument -> the Roll of Names in Firstlight
	sub("ruby palace"), -- the floor 100 castle
	sub("alfheim"), -- the season's second world
	sub("amusphere"), -- its hardware
	sub("collinia"),

	-- Guilds, events and items
	sub("liberation force"), -- the army's full name -> The Bulwark Legion
	sub("titan's hand"),
	whole("golden apple"),
	sub("silver flags"),
	sub("legend braves"),
	sub("fatal scythe"),
	sub("nicholas the renegade"),
	sub("ragout rabbit"),
	sub("lightning flash"), -- the heroine's epithet

	-- More characters
	sub("leafa"),
	sub("suguha"),
	sub("sugou"),
	sub("nobuyuki"),
	whole("oberon"), -- also the Shakespearean king, so whole word
	sub("alicia rue"),
	sub("sakuya"),
	sub("corvatz"),
	sub("yulier"),
	sub("griselda"),
	sub("caynz"),
	sub("yolko"),
	sub("keita"),
	sub("tetsuo"),
	whole("ducker"),
}

return Blocklist

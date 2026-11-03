--!strict
--[[
	StepTakeUp: the physics steps a rendered frame is about to make, guessed from the ones it made
	(the fitted-drift accumulator, D-651; the take-up's owner call for items 448 and 530).

	The engine moves the root in whole 1/240 s physics steps, and the screen draws the pose a
	render step writes on the root that frame's physics then moves (D-343). Locomotion's take-up
	(stepTravel, D-334) reads how far the root went up to the render step, so a frame that steps
	once more or once less than the one before moves the planted foot on screen by that step. On
	the owner's PC (item 530, 97cea9d) the steps hold a pattern no clock the code reads shows:

	- The engine plans its steps on its own frame clock (PreSimulation's deltaTime is a whole
	  number of steps): 4 a frame at 60 fps, 2, 2, 1 at 144, 1 at 240.
	- It takes one step more than it plans every 64 or so planned steps: 4.063 a frame at 60 and
	  1.693 at 144. Every clock the code can read (os.clock, the render step's dt, PreSimulation's
	  deltaTime) runs about 1.5% short of the steps, so a fifth step lands about every 16th frame
	  at 60.
	- The render step's dt jitters by up to about 6 ms against the steps (r's spread over 30 rows
	  is 3.4 on the render dt against 2.0 on PreSimulation's), so a frame's own dt says little of
	  its steps.

	So the guess is two phase-locked counts:

	- The planned steps run at the mean dt of the last spanRows frames (the dt's jitter cancels
	  over a span). Their phase is fitted to the last planRows frames' counts on a grid of
	  `phases` points (the middle of the run of points that holds the most frames, a drift step
	  allowed), then carried on frame by frame; it is fitted again after refitRows frames or as
	  soon as a frame breaks it. A flip does not break it (D-661): the engine's own frame
	  jitter moving one step across a frame boundary, a frame a step over its plan next to one a
	  step under it (item 555 on d310ca7: 5 then 3 about every 45th frame at 60 fps; at 144 the
	  2, 2, 1 cycle's 1 swapped with a 2 on a fifth of the frames). A flip is no drift step either.
	- The drift's steps (the frames that stepped once more, or once less, than planned) run on the
	  planned steps' own clock. Their rate and phase are fitted every frame to the corners of their
	  staircase over the last extraSeconds of frames whose planned phase was sure (each corner
	  bounds the rate; the middle of what all allow, and the middle of the phase band it leaves).

	A guess is given while the last gateRows guesses were right on at least gateShare of gateRows,
	or (D-661), with the planned phase sure, while over the last leadRows frames the guesses
	missed at least gateLead fewer frames than the last frame's steps would have (D-334 alone's
	take-up, which moves the foot on screen by every change of steps) and at most leadShare of
	theirs, and over gateRows no more (all after minRows frames); otherwise nil, and the take-up is
	D-334's alone. A flip misses twice, so on the PC's clocks (item 555) the share gate alone never
	opened. With a guess, Locomotion moves the gait's phase on by the guess less the steps the root
	just took, so the planted foot moves on screen only by a guess's miss, and the gate opening or
	closing moves it by nothing. Clocks the fit cannot follow (item 282's 2-6 pattern, steps caught
	up on the render dt itself) keep the gate shut.

		local takeUp = StepTakeUp.new(ChoreoData.locomotion.stride.takeUp)
		takeUp:observe(steps) -- the whole steps the last frame given to guess() took
		local guess, mean = takeUp:guess(dt) -- this frame's steps (nil: not sure), the mean a frame
		takeUp:reset()

	Pure: no engine reads. StepTakeUp.spec checks it on clocks drawn to item 530's counts and on
	the PC's own rows of item 555 (tests/fixtures/PcSteps555.luau).
]]

local StepTakeUp = {}
StepTakeUp.__index = StepTakeUp

export type Config = {
	spanRows: number, -- frames the planned rate and the mean steps a frame are read over
	planRows: number, -- frames the planned steps' phase is fitted to
	phases: number, -- the planned phase's grid (points across one step)
	refitRows: number, -- frames the planned phase is carried on between fits
	extraSeconds: number, -- seconds of frames the drift's steps are fitted to
	gateRows: number, -- frames the guesses' own hit share is read over
	gateShare: number, -- the share of gateRows that must have been right for a guess to be used
	-- Or, with the planned phase sure (D-661): over the last leadRows frames a guess was made
	-- for, the guesses missed at least gateLead fewer frames than the last frame's steps would
	-- have (D-334 alone's take-up) and at most leadShare of theirs, and over gateRows no more.
	gateLead: number,
	leadRows: number,
	leadShare: number,
	minRows: number, -- frames read before the first guess
	stepHz: number, -- physics steps a second (1/240 s steps)
}

export type TakeUp = typeof(setmetatable(
	{} :: {
		config: Config,
		capacity: number,
		head: number, -- physical index of the oldest frame
		count: number,
		dts: { number },
		steps: { number },
		planned: { number }, -- the planned steps guessed for each frame (its own steps if none)
		plannedTo: { number }, -- the planned steps read up to each frame's end
		extra: { number }, -- steps less the planned guess (read only where sure)
		sure: { boolean }, -- the planned guess's phase held over a whole window
		hit: { boolean }, -- the whole guess was right
		same: { boolean }, -- the steps were the frame before's (D-334 alone moved the foot by none)
		sumDt: number,
		sumSteps: number,
		plannedTotal: number,
		rows: number, -- frames read since the last reset
		sureRun: number, -- sure frames up to the newest
		hits: number, -- right guesses over the last gateRows frames
		sames: number, -- frames over the last gateRows whose steps were the frame before's
		guessed: { boolean }, -- a guess was made for the frame (given or not)
		leadGuessed: number, -- frames over the last leadRows a guess was made for
		leadHits: number, -- right guesses over the last leadRows frames
		leadSames: number, -- frames over the last leadRows whose steps were the frame before's
		-- The last frame's steps over its plan (nil: none, or used by a flip), and whether a frame
		-- one step off the plan against the drift waits for the next to pair with it (D-661).
		lastOver: number?,
		breakDue: boolean,
		-- The frames whose steps were not the planned guess (a drift step, or a miss), oldest
		-- first in a ring: the frame's number, the planned steps up to its end, its planned
		-- steps and its steps over them.
		offHead: number,
		offCount: number,
		offRow: { number },
		offTo: { number },
		offPlanned: { number },
		offOver: { number },
		-- The planned steps' fit: the phase of the frame to guess, the step quantum, frames the
		-- phase has held for (a whole window: sure), frames since the grid fit.
		phase: number?,
		quantum: number,
		held: number,
		sincePlanFit: number,
		-- The drift's corners (planned-step clock, drift steps), reused frame to frame.
		cornerT: { number },
		cornerX: { number },
		inWindow: { number },
		-- The planned fit's frames (whole part, crossings, steps in quanta) and its grid's scores.
		planBase: { number },
		planRise: { number },
		planFall: { number },
		planWant: { number },
		planScores: { number },
		planOver: { number },
		pendingDt: number?,
		pendingPlanned: number?,
		pendingSteps: number?,
		pendingSure: boolean,
	},
	StepTakeUp
))

local function gcd(a: number, b: number): number
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local function blank(self: any)
	self.head = 1
	self.count = 0
	self.sumDt = 0
	self.sumSteps = 0
	self.plannedTotal = 0
	self.rows = 0
	self.sureRun = 0
	self.hits = 0
	self.sames = 0
	self.leadGuessed = 0
	self.leadHits = 0
	self.leadSames = 0
	self.lastOver = nil
	self.breakDue = false
	self.offHead = 1
	self.offCount = 0
	self.phase = nil
	self.quantum = 1
	self.held = 0
	self.sincePlanFit = 0
	self.pendingDt = nil
	self.pendingPlanned = nil
	self.pendingSteps = nil
	self.pendingSure = false
end

--- A take-up with no frames read.
function StepTakeUp.new(config: Config): TakeUp
	local self = {
		config = config,
		capacity = math.max(1, math.floor(config.spanRows)),
		dts = {},
		steps = {},
		planned = {},
		plannedTo = {},
		extra = {},
		sure = {},
		hit = {},
		same = {},
		guessed = {},
		offRow = {},
		offTo = {},
		offPlanned = {},
		offOver = {},
		cornerT = {},
		cornerX = {},
		inWindow = {},
		planBase = {},
		planRise = {},
		planFall = {},
		planWant = {},
		planScores = {},
		planOver = {},
	}
	blank(self)
	return setmetatable(self :: any, StepTakeUp)
end

--- Forgets every frame read (a stop, a jump, a frame whose travel is not whole steps).
function StepTakeUp.reset(self: TakeUp)
	blank(self)
end

-- The physical index of the k-th frame read, 1 the oldest.
local function at(self: TakeUp, k: number): number
	return (self.head + k - 2) % self.capacity + 1
end

local function gateRows(self: TakeUp): number
	return math.max(1, math.floor(self.config.gateRows))
end

--- The whole steps the frame last given to guess() took. Nothing before the first guess().
function StepTakeUp.observe(self: TakeUp, stepsTaken: number)
	local dt = self.pendingDt
	if dt == nil then
		return
	end
	self.pendingDt = nil
	local gate = gateRows(self)
	if self.count >= gate then
		local leaving = at(self, self.count - gate + 1)
		if self.hit[leaving] then
			self.hits -= 1
		end
		if self.same[leaving] then
			self.sames -= 1
		end
	end
	local lead = math.min(self.capacity, math.max(1, math.floor(self.config.leadRows)))
	if self.count >= lead then
		local leaving = at(self, self.count - lead + 1)
		if self.guessed[leaving] then
			self.leadGuessed -= 1
		end
		if self.hit[leaving] then
			self.leadHits -= 1
		end
		if self.same[leaving] then
			self.leadSames -= 1
		end
	end
	local before = if self.count > 0 then self.steps[at(self, self.count)] else nil
	local index
	if self.count < self.capacity then
		self.count += 1
		index = at(self, self.count)
	else
		index = self.head
		self.sumDt -= self.dts[index]
		self.sumSteps -= self.steps[index]
		self.head = self.head % self.capacity + 1
	end
	self.dts[index] = dt
	self.steps[index] = stepsTaken
	self.sumDt += dt
	self.sumSteps += stepsTaken
	local planned = self.pendingPlanned
	local hit = self.pendingSteps == stepsTaken
	local sure = planned ~= nil and self.pendingSure
	self.plannedTotal += planned or stepsTaken
	self.planned[index] = planned or stepsTaken
	self.plannedTo[index] = self.plannedTotal
	self.extra[index] = if planned ~= nil then stepsTaken - planned else 0
	self.sure[index] = sure
	self.sureRun = if sure then self.sureRun + 1 else 0
	self.hit[index] = hit
	if hit then
		self.hits += 1
		self.leadHits += 1
	end
	-- Read on the frames a guess was made for, as `hit` is, so the gate weighs both on the same
	-- frames.
	local guessed = self.pendingSteps ~= nil
	self.guessed[index] = guessed
	if guessed then
		self.leadGuessed += 1
	end
	local same = guessed and before == stepsTaken
	self.same[index] = same
	if same then
		self.sames += 1
		self.leadSames += 1
	end
	self.rows += 1
	-- A flip (D-661): one step the engine's own frame jitter moved across a frame boundary, a
	-- frame one step over its plan next to one a step under it (the PC's 5 then 3 at 60 fps, 3
	-- then 0 or 1 then 2 at 144, item 555). It is no drift step, and the plan holds through it.
	local over = if planned ~= nil then stepsTaken - planned else nil
	local flip = over ~= nil and math.abs(over) == 1 and self.lastOver == -over
	if flip then
		self.extra[index] = 0
		self.extra[at(self, self.count - 1)] = 0
		if self.offCount > 0 then
			local newest = (self.offHead + self.offCount - 2) % self.capacity + 1
			if self.offRow[newest] == self.rows - 1 then
				self.offCount -= 1
			end
		end
	elseif planned ~= nil and stepsTaken ~= planned then
		local slot
		if self.offCount < self.capacity then
			self.offCount += 1
			slot = (self.offHead + self.offCount - 2) % self.capacity + 1
		else
			slot = self.offHead
			self.offHead = self.offHead % self.capacity + 1
		end
		self.offRow[slot] = self.rows
		self.offTo[slot] = self.plannedTotal
		self.offPlanned[slot] = planned
		self.offOver[slot] = stepsTaken - planned
	end
	if over ~= nil then
		local sign = if self.sumSteps / self.count >= self.config.stepHz * self.sumDt / self.count then 1 else -1
		if flip then
			self.held += 1
			self.lastOver = nil
			self.breakDue = false
		else
			-- A frame a step off against the drift breaks the plan a frame late, unless the next
			-- one pairs with it.
			if self.breakDue then
				self.held = 0
				self.phase = nil
			end
			self.breakDue = false
			if over == 0 or over == sign then
				self.held += 1
			elseif math.abs(over) == 1 then
				self.held += 1
				self.breakDue = true
			else
				self.held = 0
				self.phase = nil
			end
			self.lastOver = over
		end
	else
		self.held = 0
		self.phase = nil
		self.lastOver = nil
		self.breakDue = false
	end
	self.sincePlanFit += 1
	self.pendingPlanned = nil
	self.pendingSteps = nil
	self.pendingSure = false
end

-- The planned steps of the frame `j` frames after the window's end (0 is the frame being
-- guessed) at `rate` steps a frame from phase `phase`, in whole `quantum`s.
local function plannedAt(rate: number, phase: number, quantum: number, j: number): number
	return quantum * (math.floor((rate * (j + 1) + phase) / quantum) - math.floor((rate * j + phase) / quantum))
end

-- The planned steps' phase over the last planRows frames, on the grid: the middle of the run of
-- points whose plan holds the most of them (a drift step of `sign` allowed). Sure when that plan
-- holds every frame, a flip allowed.
local function fitPlan(self: TakeUp, rate: number, sign: number)
	local config = self.config
	local count = self.count
	local window = math.min(math.max(1, math.floor(config.planRows)), count)
	local first = count - window + 1
	local quantum = 0
	for k = first, count do
		quantum = gcd(quantum, self.steps[at(self, k)])
	end
	quantum = math.max(quantum, 1)
	local phases = math.max(1, math.floor(config.phases))
	-- Each frame's plan as the phase runs over a quantum: its whole part, and where its end and
	-- its start cross a quantum (on a 0 .. 1 scale), so a grid point costs two compares a frame.
	local base, rises, falls, wants = self.planBase, self.planRise, self.planFall, self.planWant
	local before = rate * (first - count - 1) / quantum
	for k = first, count do
		local after = before + rate / quantum
		local i = k - first + 1
		base[i] = math.floor(after) - math.floor(before)
		rises[i] = 1 - (after - math.floor(after))
		falls[i] = 1 - (before - math.floor(before))
		wants[i] = self.steps[at(self, k)] / quantum
		before = after
	end
	local drift = sign / quantum
	local scores, overs = self.planScores, self.planOver
	local top = 0
	for p = 1, phases do
		local phase = (p - 0.5) / phases
		local score = 0
		for i = 1, window do
			local plan = base[i]
			if phase >= rises[i] then
				plan += 1
			end
			if phase >= falls[i] then
				plan -= 1
			end
			local over = wants[i] - plan
			if over == 0 or over == drift then
				score += 1
			end
		end
		scores[p] = score
		top = math.max(top, score)
	end
	local runLength, runStart = 0, 1
	for p = 1, phases do
		local before = if p == 1 then phases else p - 1
		if scores[p] == top and scores[before] ~= top then
			local length = 0
			while length < phases and scores[(p + length - 1) % phases + 1] == top do
				length += 1
			end
			if length > runLength then
				runLength, runStart = length, p
			end
		end
	end
	if runLength == 0 then
		runLength, runStart = phases, 1
	end
	local phase = ((runStart - 1 + runLength / 2) % phases) / phases
	self.phase = phase * quantum
	self.quantum = quantum
	-- Sure when the fitted plan holds every frame, a flip allowed (D-661), as is the newest
	-- frame a step off, which waits for the next to pair with it (observe).
	for i = 1, window do
		local plan = base[i]
		if phase >= rises[i] then
			plan += 1
		end
		if phase >= falls[i] then
			plan -= 1
		end
		overs[i] = wants[i] - plan
	end
	local step = 1 / quantum
	local held = true
	for i = 1, window do
		local over = overs[i]
		if
			not (
				over == 0
				or over == drift
				or (
					math.abs(over) == step
					and (i == window or overs[i + 1] == -over or (i > 1 and overs[i - 1] == -over))
				)
			)
		then
			held = false
			break
		end
	end
	self.held = if held then window else 0
	self.sincePlanFit = 0
end

-- The drift's steps this frame, from the last extraSeconds of sure frames on the planned steps'
-- clock (T = 0 at the last frame's end, the frame to guess ending at `planned`): the rate every
-- corner of their staircase allows (its middle), and the middle of the phase band the frames'
-- ends leave at that rate. 0 with no drift step among them.
local function driftAt(self: TakeUp, rate: number, mean: number, sign: number, window: number, planned: number): number
	local config = self.config
	local count = self.count
	local span = math.min(count, math.max(window, math.floor(config.extraSeconds * config.stepHz / rate + 0.5)))
	local length = math.min(span, self.sureRun)
	if length <= 0 then
		return 0
	end
	local firstRow = self.rows - length + 1
	-- The drift steps in the window, newest first, then walked oldest first.
	local inWindow = self.inWindow
	local total = 0
	for n = self.offCount, 1, -1 do
		local slot = (self.offHead + n - 2) % self.capacity + 1
		if self.offRow[slot] < firstRow then
			break
		end
		if self.offOver[slot] == sign then
			total += 1
			inWindow[total] = slot
		end
	end
	if total == 0 then
		return 0
	end
	local last = self.plannedTotal
	local firstIndex = at(self, count - length + 1)
	local firstTo = self.plannedTo[firstIndex]
	-- The corners: the window's start, each drift step's frame before and after, and its end.
	local cornerT, cornerX = self.cornerT, self.cornerX
	cornerT[1] = firstTo - self.planned[firstIndex] - last
	cornerX[1] = 0
	local corners = 1
	for n = total, 1, -1 do
		local slot = inWindow[n]
		local t = self.offTo[slot] - last
		local before = total - n
		cornerT[corners + 1] = t - self.offPlanned[slot]
		cornerX[corners + 1] = before
		cornerT[corners + 2] = t
		cornerX[corners + 2] = before + 1
		corners += 2
	end
	corners += 1
	cornerT[corners] = 0
	cornerX[corners] = total
	local low, high = 0, math.huge
	for a = 1, corners do
		for b = a + 1, corners do
			local run = cornerT[b] - cornerT[a]
			if run > 0 then
				local rise = cornerX[b] - cornerX[a]
				low = math.max(low, (rise - 1) / run)
				high = math.min(high, (rise + 1) / run)
			end
		end
	end
	local slope = if total >= 2 and low < high then (low + high) / 2 else math.abs(mean - rate) / rate
	-- The band: a flat run of frames is highest at its first frame's end and lowest at its last's,
	-- so the frames' ends that bound it are the first, each one either side of a drift step (the
	-- window's start is no frame's end) and the last.
	local firstT = firstTo - last
	local firstX = if self.extra[firstIndex] == sign then 1 else 0
	local least = firstX - slope * firstT
	local most = least
	for c = 2, corners do
		if not (c == 2 and cornerT[c] == cornerT[1]) then
			local value = cornerX[c] - slope * cornerT[c]
			least = math.min(least, value)
			most = math.max(most, value)
		end
	end
	local centre = (most + least + 1) / 2
	return sign * (math.floor(slope * planned + centre) - math.floor(centre))
end

--- This frame's steps, from its dt and the frames read: a whole number while the guesses have
--- held (nil while not sure), and the mean steps a frame over the span (0 with none read).
function StepTakeUp.guess(self: TakeUp, dt: number): (number?, number)
	local config = self.config
	self.pendingDt = dt
	self.pendingPlanned = nil
	self.pendingSteps = nil
	self.pendingSure = false
	local count = self.count
	if count == 0 then
		return nil, 0
	end
	local mean = self.sumSteps / count
	local rate = config.stepHz * self.sumDt / count
	if count < config.minRows or rate <= 0 then
		return nil, mean
	end
	local sign = if mean >= rate then 1 else -1
	local window = math.min(math.max(1, math.floor(config.planRows)), count)

	-- The planned steps: the phase carried on a frame (at this span's rate), refitted after
	-- refitRows frames or when a frame broke it.
	local phase = self.phase
	if phase ~= nil then
		phase = (phase + rate) % self.quantum
		self.phase = phase
	end
	if phase == nil or self.sincePlanFit >= math.max(1, math.floor(config.refitRows)) then
		fitPlan(self, rate, sign)
	end
	local planned = plannedAt(rate, self.phase :: number, self.quantum, 0)
	local sure = self.held >= window

	local drift = driftAt(self, rate, mean, sign, window, planned)

	local guess = planned + drift
	self.pendingPlanned = planned
	self.pendingSteps = guess
	self.pendingSure = sure
	-- The gate: the guesses right on gateShare of the last gateRows frames, or, with the plan
	-- sure, clearly ahead of the last frame's steps (D-661): over leadRows they missed gateLead
	-- fewer frames and at most leadShare as many, and over gateRows no more.
	local guessMisses = self.leadGuessed - self.leadHits
	local lastMisses = self.leadGuessed - self.leadSames
	local ahead = sure
		and lastMisses - guessMisses >= config.gateLead
		and guessMisses <= config.leadShare * lastMisses
		and self.hits >= self.sames
	if self.hits < config.gateShare * gateRows(self) and not ahead then
		return nil, mean
	end
	return guess, mean
end

return StepTakeUp

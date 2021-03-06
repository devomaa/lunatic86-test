-- 8253 PIT
-- TODO: Actually emulate it. Tough, as we only get 20 "ticks" a second on OpenComputers.
-- Maybe it's not worth to accurately emulate it?

pit_osc_freq = 1.193182

local channels = {nil, nil, nil}

function pit_channel(c)
	return channels[c]
end

local function pit_init(c,first)
	channels[c] = {
		mode=3,
		addr_mode=3,
		reload=0xFFFF,
		reload_set_lo=false,
		reload_set_hi=false,
		paused=false,
		count=0
	}
end

-- THIS IS REALLY INACCURATE OKAY
-- but that is fine as we're not using it right now anyway
function pit_tick(last_t, curr_t)
	local osc_count = math.floor((curr_t - last_t) * 1000000 * pit_osc_freq)
	for c=1,3 do
		local trig=0
		local ch=channels[c]
		local ch_ready=(not ch.paused) and ch.reload_set_lo and ch.reload_set_hi
		if (ch.mode == 0 or ch.mode == 4) and ch_ready then
			if ch.count == 0 then ch.count = ch.reload end
			ch.count = ch.count - osc_count
			if ch.count < 1 then
				trig = 1
				ch.count = 0
				ch.paused = true
			end
		elseif (ch.mode == 2 or ch.mode == 3) and ch_ready then
			ch.count = ch.count - osc_count
			while ch.count < 0 do
				ch.count = ch.count + ch.reload
				trig = trig + 1
			end
		end
		for i=1,trig do
			if c == 1 and pic_interrupt_enabled(PIC_INTERRUPT_TIMER) then
				cpu_emit_interrupt(0x08, false)
			end
		end
	end
end

local access_lohi = false

local function pit_data(n) return function(cond, val)
	local ch = channels[n]
	if not val then
		emu_debug(2, "PIT read data " .. n)
		if ch.addr_mode == 3 then
			access_lohi = not access_lohi
			if access_lohi then
				return ch.count & 0xFF
			else
				return (ch.count >> 8) & 0xFF
			end
		elseif ch.addr_mode == 1 then
			return ch.count & 0xFF
		elseif ch.addr_mode == 2 then
			return (ch.count >> 8) & 0xFF
		elseif ch.addr_mode == 0 then
			return 0x00 -- TODO
		end
	else
		emu_debug(2, "PIT write data " .. n)
		if ch.addr_mode == 3 then
			access_lohi = not access_lohi
			if access_lohi then
				ch.reload = (ch.reload & 0xFF00) | val
				ch.reload_set_lo = true
				ch.reload_set_hi = false
			else
				ch.reload = (ch.reload & 0xFF) | (val << 8)
				ch.reload_set_hi = true
			end
		elseif ch.addr_mode == 1 then
			ch.reload = (ch.reload & 0xFF00) | val
			ch.reload_set_lo = true
		elseif ch.addr_mode == 2 then
			ch.reload = (ch.reload & 0xFF) | (val << 8)
			ch.reload_set_hi = true
		elseif ch.addr_mode == 0 then
			-- TODO
		end
	end
end end

cpu_port_set(0x40, pit_data(1))
cpu_port_set(0x41, pit_data(2))
cpu_port_set(0x42, pit_data(3))
cpu_port_set(0x43, function(cond, val)
	if val then
		emu_debug(2, "PIT write control " .. val)
		local c = (val >> 6) + 1
		if c < 4 then
			pit_init(c,false)
			channels[c].mode = (val >> 1) & 0x07
			channels[c].addr_mode = (val >> 4) & 0x03
			channels[c].paused = false
			access_lohi = false
		end
	else
		emu_debug(2, "PIT read control")
		return 0xFF
	end
end)

pit_init(1,true)
pit_init(2,true)
pit_init(3,true)


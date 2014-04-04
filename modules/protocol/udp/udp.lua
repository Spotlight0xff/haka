-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local ipv4 = require("protocol/ipv4")

local function compute_checksum(pkt)
	local checksum = ipv4.inet_checksum()

	-- UDP checksum is computed using a
	-- pseudo-header made of some fields
	-- of ipv4 header

	-- size of the udp pseudo-header
	local pseudo_header = haka.vbuffer_allocate(12)
	-- source and destination ipv4 addresses
	pseudo_header:sub(0,4):setnumber(pkt.ip.src.packed)
	pseudo_header:sub(4,4):setnumber(pkt.ip.dst.packed)
	-- padding (null byte)
	pseudo_header:sub(8,1):setnumber(0)
	-- UDP protocol number
	pseudo_header:sub(9,1):setnumber(0x11)
	-- UDP message length (header + data)
	pseudo_header:sub(10,2):setnumber(pkt.length)
	checksum:process(pseudo_header)

	checksum:process(pkt._payload)
	return checksum:reduce()
end

local udp_dissector = haka.dissector.new{
	type = haka.dissector.EncapsulatedPacketDissector,
	name = 'udp'
}

udp_dissector.grammar = haka.grammar:new("udp")

udp_dissector.grammar.packet = haka.grammar.record{
	haka.grammar.field('srcport',   haka.grammar.number(16)),
	haka.grammar.field('dstport',   haka.grammar.number(16)),
	haka.grammar.field('length',    haka.grammar.number(16))
		:validate(function (self) self.len = 8 + #self.payload end),
	haka.grammar.field('checksum',  haka.grammar.number(16))
		:validate(function (self)
			self.checksum = 0
			self.checksum = compute_checksum(self)
		end),
	haka.grammar.field('payload',   haka.grammar.bytes())
}:compile()

function udp_dissector.method:next_dissector()
	return haka.dissector.get('udp-connection')
end

function udp_dissector.method:parse_payload(pkt, payload)
	self.ip = pkt
	udp_dissector.grammar.packet:parse(payload:pos("begin"), self)
end

function udp_dissector.method:create_payload(pkt, payload, init)
	self.ip = pkt
	udp_dissector.grammar.packet:create(payload:pos("begin"), self, init)
end

function udp_dissector.method:forge_payload(pkt, payload)
	if payload.modified then
		self.checksum = nil
	end

	self:validate()
end

function udp_dissector.method:verify_checksum()
	return compute_checksum(self) == 0
end

function udp_dissector:create(pkt, init)
	if not init then init = {} end
	if not init.length then init.length = 8 end
	pkt.payload:pos(0):insert(haka.vbuffer_allocate(init.length))
	pkt.proto = 17

	local udp = udp_dissector:new(pkt)
	udp:create(init, pkt)
	return udp
end

ipv4.register_protocol(17, udp_dissector)

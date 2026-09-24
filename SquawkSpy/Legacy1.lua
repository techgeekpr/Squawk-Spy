-- The addon used to be called SpyF.  Park anything saved under the old name
-- so its lists and settings can be carried over once.
if type(SpyFDB) == "table" then
	SquawkSpy_Legacy = SquawkSpy_Legacy or {}
	SquawkSpy_Legacy[#SquawkSpy_Legacy + 1] = SpyFDB
	SpyFDB = nil
end

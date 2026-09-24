-- Parks the snapshot loaded from SV2 so the next SV file cannot clobber it.
if type(SquawkSpyDB) == "table" then
	SquawkSpy_Restore = SquawkSpy_Restore or {}
	SquawkSpy_Restore[#SquawkSpy_Restore + 1] = SquawkSpyDB
	SquawkSpyDB = nil
end

use demographics.dta, clear
keep SchoolName TotalEnrollment
collapse (mean) TotalEnrollment , by(SchoolName)

egen schname = sieve(SchoolName), omit(.-:)
replace schname = lower(schname)

gen schnum = regexs(0) if regexm(schname, "[0-9]+")
destring schnum , replace

save demo.dta, replace


use FTEandPupilTeacherRatios.dta, clear
egen FTE = rowmean(FTE*)
keep SchoolName FTE ZIP

egen schname = sieve(SchoolName), omit(.-:)
replace schname = lower(schname)

gen schnum = regexs(0) if regexm(schname, "[0-9]+")
destring schnum , replace

save fte.dta, replace


capture: program drop calcdist1
program define calcdist1

	keep if schnum==schnum[1]

	* Distance based on school name 
	* To make first observation recognized as string, save value as local macro
	local schoolnamevalue = schname[1]
	strdist "`schoolnamevalue'" schname , gen(name_dist)
	
	quietly: replace _dist = name_dist 
end


capture: program drop calcdist
program define calcdist

	* Distance based on school name 
	* To make first observation recognized as string, save value as local macro
	local schoolnamevalue = schname[1]
	strdist "`schoolnamevalue'" schname , gen(name_dist)
	
	quietly: replace _dist = name_dist 
end


capture: program drop goodmatch
program define goodmatch
	if _dist[2] < (_dist[3]/2) {
		replace _match=3 in 2
		display `"Match "`= schname[1]'" to "`= schname[2]'""'
	}
end

use fte.dta, clear
set more off
discard

keep if !missing(schnum)
recmap schname schnum using demo.dta, saving(school_map.dta) distance(calcdist1)

/*
use fte.dta, clear
recmap schname using demo.dta, saving(school_map.dta) distance(calcdist) match(goodmatch)


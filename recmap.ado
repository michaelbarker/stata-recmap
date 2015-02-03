/*******************************************************************************
 Update 2014/04/30: 
 	- Keep _match variable in final data set
	- Change default value of _match to zero (indicating non-match)
	- Allow any non-zero value of _match to mark matched record from using data 
	- Fill in _dist variable for master record of each pair

 Update 2014/10/15: 
 	- Add option start(#) to set starting record number in master data set.
	- Add option saveskipped: saves records that are skipped in final mapping
		data set. Only records from the master data set are skipped. Skipped 
		records have negative _id numbers, numbered consecutively downward. 
		Values for skipped records are:
		_id = negative consecutive integers
		_dist = .
		_match = 0
		_source = 1

 Update 2015-02-03:
 	- Allow for multiple matches through match program
	- Add option to match with replacement

*******************************************************************************/


program define recmap
	syntax varlist using/ , SAving(string) [DISTance(string) MATCH(string) STart(integer 1) SAVESKipped REPLACEUSING]

quietly {
	if `start'<=0 {
		display as error `"Start option must be greater than zero"'
		error 111
	}

	if "`distance'"=="" {
		local distance _recmap_distance
	}
	else {
		capture: program list `distance'	
		if _rc!=0 {
			display as error `"Program "`distance'" not found"'
			error 111
		}
	}
		
	if "`match'"=="" {
		local match _recmap_match
	}
	else {
		capture: program list `match'	
		if _rc!=0 {
			display as error `"Program "`match'" not found"'
			error 111
		}
	}
	
	preserve

	tempfile mastname usename

	* Verify and create new variables 
	* Master 
	confirm new variable _match _source _dist _id
	gen byte  _source = 1
	gen float _dist   = .
	gen int   _match  = 0
	gen long  _id	  = .
	order _id _match _source _dist `varlist'
	save  `"`mastname'"'

	* Using
	clear
	use `"`using'"'
	confirm new variable _match _source _dist _id 
	gen byte  _source = 2
	gen float _dist   = .
	gen int   _match  = 0
	gen long  _id	  = .
	order _id _match _source _dist `varlist'
	save  `"`usename'"'
		
	* Verify file for saving matches 
	local ss : subinstr local saving ".dta" ""
	* New file name
	capture: confirm new file `"`ss'.dta"'

	if _rc==0 {
		* No existing mapping file  	
		* Look for exact matches and save in map data set
		* If no exact matches, save variable definitions only 
		clear
		use `"`mastname'"' 
		merge 1:1 `varlist' using `"`usename'"'
		keep if _merge==3
		keep _id _match _source _dist `varlist'
		replace _id = _n
		replace _match=1
		replace _dist=0

		* Save records matching to master data set
		replace _source=1
		order _id _source _match _dist, first
		save `"`ss'.dta"' 

		* Save records matching using data set, then append master.
		replace _source=2
		append using `"`ss'.dta"'  
		sort _id _source
		save `"`ss'.dta"', replace
	}

	* Error code 602: file already exists 
	else if _rc==602  {
		* Existing file name
		confirm file `"`ss'.dta"'
		display as input `"File `ss'.dta already exists: Appending new matches"'
	}

	* Any other error code returned by "confirm new file" 
	else if _rc!=602 {
		display as error `"Invalid saving() option: `saving'"'
		error _rc
	}

	* If mapping data set has any records in it...
	* Remove already matched records from master and using:
	quietly: describe using `"`ss.dta'"' , short
	if r(N)>0 { 
		* Merge matches with Master 
		clear
		use `"`ss'.dta"'
		keep if _source==1
		merge 1:1 `varlist' using `"`mastname'"'
		keep if _merge==2
		drop _merge
		order _match _source _dist `varlist'
		save `"`mastname'"' , replace
	
		quietly: count
		if r(N)==0 {
			display as error `"All master records already exist in mapping file"'
			exit(0)
		}

		* If matching with replacement, don't do this.
		* Do only if matching with replacement was not elected.
		if "`replaceusing'"=="" { 
			* Merge matches with Using
			clear
			use `"`ss.dta'"' 
			keep if _source==2
			merge 1:1 `varlist' using `"`usename'"' 
			keep if _merge==2
			drop _merge
			save `"`usename'"' , replace
		}
	}

	tempfile tempname
	* Loop through records from Master data set
	quietly: describe using `"`mastname'"' , short
	local max = r(N) 
	* Check start value
	if `start'>`max' {
		display as error `"Start obs. (`start') greater than remaining unmatched (`max')"'
		error 111
	}
	* Begin loop
	forvalues n = `start'/`max' {
		noisily: display as result "Current record: `n' of `max'"
		
		clear
		use in `n' using `"`mastname'"'
		append using `"`usename'"'
		if _N==1 {
			display as error "No potential matches in Using data."
			continue, break
		}

		* Call program to calculate distance
		capture noisily: `distance'
		if _rc!=0 {
			display as error "Error in distance program" 
			error _rc
		}

		* Check if distance program has dropped all potential matches with hard matching requirements
		if _N==1 {
			noisily: display as result "No potential matches - record skipped"
			fmore
		}
		* If potential matches exist, look for best match
		else {
			* Sort by distance with key value on top
			sort _source _dist, stable

			* Call program to choose best match 
			* Default program requires varlist
			if `"`match'"'== "_recmap_match" {
				capture noisily: `match' `varlist'
			}
			* Do not pass varlist if user supplies match program
			else capture noisily: `match' 
		}

	   * Get matched record and replace
	   if _rc==0 {
			quietly: count if _match
			local nmatch = r(N)

			if `nmatch'>=1 {
				* If match was chosen
				* Save matched records
				keep if _source==1 | _match
				sort _source _dist, stable

				* If single match, fill in match status and distance
				if `nmatch'==1 {
					replace _match = _match[2] in 1
					replace _dist  = _dist[2]  in 1
				}

				* If multiple matches, replace master record variables to . 
				else {	
					replace _match = . in 1
					replace _dist  = . in 1 
				}

				replace _id = 0 // initialize _id, so summarize command below returns a valid r(max), even if ss.dta is empty.
				keep _id _match _source _dist `varlist'
				* save `"`tempname'"' , replace

				* Append previous matches to current record and match 
				append using `"`ss'.dta"' 

				* Get id number for new matches
				quietly: summarize _id 
				local nextid = r(max)+1
				replace _id = `nextid' in 1/`++nmatch'

				* Save new match file
				order _id _source _match _dist, first
				save `"`ss'.dta"' , replace 
				
				* If matching with replacement, don't do this.
				* Do only if matching with replacement was not elected.
				if "`replaceusing'"=="" { 
					* Drop matched observation from set of potential matches
					keep in 2/`nmatch'
					merge 1:1 _source `varlist' using `"`usename'"'
					keep if _merge==2
					drop _merge 
					save `"`usename'"' , replace
				}

			} /* end if r(N)==1 */

			* No match, but user elects to save skipped records:
			else if r(N)==0 & "`saveskipped'"!="" {
				* Keep original record only 
				keep if _n==1 
				replace _match = 0 
				replace _dist  = .
				replace _id	   = 0 // initialize _id, so summarize command below returns a valid r(min), even if ss.dta is empty. 
				keep _id _match _source _dist `varlist'

				* Append previous matches to current record and match 
				append using `"`ss'.dta"' 
				* Get id number for new unmatched record 
				quietly: summarize _id 
				local nextid = r(min)-1
				replace _id = `nextid' in 1
				* Save new match file
				order _id _source _match _dist, first
				sort _id _source _dist, stable
				save `"`ss'.dta"' , replace 
			} /* end saveskipped */

		} /* end if _rc==0 */

		else if _rc==1 {
			continue, break
		} /* end if _rc==1 */

		* Else return any other error code
		else {
			display as error "Error in match program" 
			error _rc
		}

	} /* end forvalues loop */
} /* end quietly */

end
/* End recmap */


** Begin GetInput
prog _recmap_getinput
	syntax varlist, [minobs(integer 2)]

	* Display Match and Request Input
	display _n as txt "Choose Best Match or Other Command:"
	noisily: list `varlist' in 1 

	* Confirm min and max obs to display
	* Default to first observation if not specified or out of range
	* if "`minobs'"=="" local minobs 2 // Not required: default value set in syntax statement
	* else if `minobs'<2 | `minobs'>_N local minobs 2
	if `minobs'<2 | `minobs'>_N local minobs 2

	* Display twenty observations per screen
	local maxobs = `minobs'+19

	* Default to last observation if maxobs is out of range
	if `maxobs' > _N local maxobs = _N

	* Display Choices
	* Specify which variables to display
	list `varlist' _dist in `minobs'/`maxobs' , noheader

	display as txt `"Enter match number, letter choice, or any valid Stata command."'
	display as txt `"To choose match in edit window directly, choose "e" and change _match to 1 for the chosen match"'
	display as txt `"e=edit window, n=next set of choices, p=previous, s=skip current record (no match), q=quit"' _request(_choice)

	* Check if input is an integer 
	capture: confirm integer number `choice'

	** Handle Integer Input
	if !_rc {
	   if `choice'>=2 & `choice'<=_N {
			replace _match = 2 if _n==`choice' 
			exit=0
	   }
	   else {
		  display as result "Number out of range"
		  fmore
	   }
	}

	** Handle non-Integer Input
	else if _rc {

	   * Quit Program
	   if "`choice'"=="q" {
		  exit=1
	   }

	   * Skip Observation 
	   if "`choice'"=="s" {
		  exit=0
	   }

	   * Display next 20 choices
	   else if "`choice'"=="n" {
		  display as input "Your Choice: `choice'"
		  if `maxobs'==_N {
			display as result "Already at last observation"
			fmore
		  }
		  else {
			 local minobs = `minobs'+20
		  } 
	   }

	   * Display previous 20 choices
	   * Note: Out of range left checked at input
	   else if "`choice'"=="p" {
		  display as input "Your Choice: `choice'"
		  if `minobs'==2 {
			display as result "Already at first observation"
			fmore
		  }
		  else { 
			 local minobs = `minobs'-20
		  }
	   }

		* Open Edit Window
	   	else if "`choice'"=="e" {
		  display as input `"Your Choice: `choice'"'
		  edit 
		}	

		else {
			* Any valid Stata command:
			capture noisily `choice'
			if _rc!=0 {
	   			* Invalid Input
			   * Includes undefined text values and non-integer numeric values
		  		display as result "invalid input"
				fmore
			}
			* Check if command designated a match			
			quietly: count if _match
			scalar ones = r(N)
			if ones>1 {
				display as result `"Only one match may be chosen"'
				fmore
				replace _match = 0
			}	
			else if _match[1] { 
		  		display as result `"Match must come from the using data (Choose -skip- if no match)"'
				fmore
				replace _match = 0
			}
			else if ones==1 {
				exit=0
			}
		} /* end else */
	} /* end non-integer handling */

	* Call recursively until choice is made, record skipped, or program quit.
	_recmap_getinput `varlist' , minobs(`minobs')

end
** End GetInput

* Default distance calculation if user does not specify a program
program define _recmap_distance 
	replace _dist=1
	replace _dist=0 if _n==1
end

* Default matching program: interactive
program define _recmap_match
	syntax varlist
	sort _source _dist, stable
	_recmap_getinput `varlist'
end

program define fmore 
	set more on
	more
end



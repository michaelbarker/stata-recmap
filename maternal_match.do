/*******************************************************************************
	Mapping of delivery location between data sets:

	Survey Records: deliverylocation			Administrative Records: HealthCenter
           Vihiga District Hospital (1) | 31       VDH | 2,810      
               Vihiga Health Centre (2) | 17       Vihiga Health Center |   391      
 Mbale Rural Training Health Centre (3) | 21       Mbale Rural |   843      
           Lyanaginga Health Centre (4) | 15       Lyanaginga |   281      
               Enzaro Health Centre (5) | 17	   Enzaro |   188      
                  Mulele Dispensary (6) |  6       Mulele |    63      
               Bugamangi Dispensary (7) |  4       Bugamangi |    47      
                   Iduku Dispensary (8) |  1       Iduku |    57      
A government facility outside of Vihiga |  8       
               Private sector/ NGO (10) |  2       
   Home (yours, friend's, or other)(11) | 33       
                             Other (12) |  4       

*******************************************************************************/
clear
set more off

import excel using "Maternity- 4680 Records.xlsx", firstrow
* What is the difference between Date_of_Admission Date_of_Delivery Date
gen		deliverylocation = 1 if HealthCenter=="VDH" 
replace deliverylocation = 2 if HealthCenter=="Vihiga Health Center"
replace deliverylocation = 3 if HealthCenter=="Mbale Rural"
replace deliverylocation = 4 if HealthCenter=="Lyanaginga"
replace deliverylocation = 5 if HealthCenter=="Enzaro"
replace deliverylocation = 6 if HealthCenter=="Mulele"
replace deliverylocation = 7 if HealthCenter=="Bugamangi"
replace deliverylocation = 8 if HealthCenter=="Iduku"


* Not sure what these different date fields are: 
gen 	deliverydate = Date_of_Delivery
replace deliverydate = Date 				if missing(deliverydate)
replace deliverydate = Date_of_Admission	if missing(deliverydate)

rename Age age

gen name = Full_Names
* Drop if no name
drop if name==""
* Get first four words of full name in lower case
gen name1 = lower(word(name,1))
gen name2 = lower(word(name,2))
gen name3 = lower(word(name,3))
gen name4 = lower(word(name,4))

* Remove any c/o, w/o, d/o names
list name* if substr(name2,2,1)=="/"
* these names have been run together: fix below.
replace name4="" if substr(name2,2,1)=="/"
replace name3="" if substr(name2,2,1)=="/"
replace name2="" if substr(name2,2,1)=="/"

* Split names where they have run together
replace name2 = "ogadi" 	if name1=="everlyneogadi"
replace name1 = "everlyne" 	if name1=="everlyneogadi"

replace name2 = "undisa" 	if name1=="jacklyneundisa"
replace name1 = "jacklyne" 	if name1=="jacklyneundisa"

replace name2 = "kavahi " 	if name1=="liliankavahi"
replace name1 = "lilian" 	if name1=="liliankavahi"

* Continue removing c/o, w/o, d/o names
list name* if substr(name3,2,1)=="/"
replace name4="" if substr(name3,2,1)=="/"
replace name3="" if substr(name3,2,1)=="/"
replace name4="" if name3=="care" & name4=="of" 
replace name3="" if name3=="care" & name4=="" 	

list name* if substr(name4,2,1)=="/"
replace name4="" if substr(name4,2,1)=="/"

* Remove middle initials:
list name* if length(name2)<=2
replace name1 = "jescah" if name=="JESC AH MAKUNGU"
replace name2 = name3 	 if name=="JESC AH MAKUNGU"
replace name3 = "" 		 if name=="JESC AH MAKUNGU"

replace name2 = name3 	if length(name2)<=2
list name*  			if name2==name3
replace name3 = "" 		if name2==name3

* Remove third name initials:
list name* 			if length(name3)<=2
replace name3 = "" 	if length(name3)<=2

* Fix other cases where first name has been run together: 
list name* if name2=="" 
replace name1 = "leva" 		if name=="LEVAKHAREHI"
replace name2 = "kharehi" 	if name=="LEVAKHAREHI"
replace name1 = "baby" 		if name=="BABYCATHERINE"
replace name2 = "catherine"	if name=="BABYCATHERINE"
replace name1 = "joyce" 	if name=="JOYCEMWANIGA"
replace name2 = "mwaniga" 	if name=="JOYCEMWANIGA"

* Is baby an actual name? like in Dirty Dancing?
list name* if name1=="baby"

* Check for mistakes in first two names:
* tab name1
* tab name2

* duplicates examples deliverylocation deliverydate age name1 name2 
duplicates tag deliverylocation deliverydate age name1 name2 name3, gen(dups)
* br if dups
* What are these duplicate administrative records?
duplicates drop deliverylocation deliverydate age name1 name2 name3 , force
drop dups

save maternity_records.dta, replace

clear
use "endline_control_EDDbeforeSept15.dta"
tab deliverylocation
de deliverydate

/*

gen thirdname = word(name,3)
tab thirdname, m
* Many more records here with three names than in maternal records
* Which are the two relevant names?

*/

gen name1 = lower(word(name,1))
gen name2 = lower(word(name,2))
gen name3 = lower(word(name,3))
* is "none" a real name?
list name* 			if name3=="none"
replace name3="" 	if name3=="none"
* Replace initials in last name
list name* 			if length(name3)<=2 
replace name3="" 	if length(name3)<=2

save endline_records.dta, replace


/*******************************************************************************

 Program below calculates distance for matching.

 The program is called by the recmap program to calculate the matching distance
 between a single observation from the "master" data set and each possible
 match from the "using" data set. 

 The program operates on a data set consisiting of all of the "using" records
 and the current record from the "master" data set. The record from the "master"
 data set is always the first observation. 

 Any variable common to both data sets can be used in the program. 
 Changes made here are not saved, so variables can be created,
 observations dropped, etc.

 The final matching distance should be saved in the variable _dist.
 _dist will already exist in the data set, so it should be replaced, not generated

 When the program for calculating distance is complete, the program name 
 should be included in the recmap command in the "distance()" option.

 The program below requires the strdist program:
 ssc install strdist
 
*******************************************************************************/

capture: program drop calcdist
program define calcdist

	* Only consider records from the same delivery location:
	keep if deliverylocation==deliverylocation[1]

	* Distance based on date
	gen date_dist = 0.1 * abs(deliverydate - deliverydate[1])

	* Distance based on age
	gen age_dist  = abs(age - age[1])
	
	* Distance based on first name 
	* To make first observation recognized as string, save value as local macro
	local name1value = name1[1]
	strdist "`name1value'" name1 , gen(name1_dist)
	
	* Distance based on second (and third) name
	local name2value = name2[1]
	strdist "`name2value'" name2 , gen(name2_dist)

	* If endline record has three names, match second and third name
	* to second name of maternity records. Use the closer name. 
	local name3value = name3[1]
	if `"`name3value'"'!="" {
		strdist "`name3value'" name2 , gen(name3_dist)
		replace name2_dist = min(name2_dist, name3_dist)
	}

	* Total up all distances. Treat missing as zero unless all are missing.
	egen total_dist = rowtotal(date_dist age_dist name1_dist name2_dist) , missing
	
	replace _dist = total_dist 

end
	
use endline_records.dta, clear

set more off
discard
rm record_map.dta
recmap deliverylocation deliverydate age name1 name2 name3 using maternity_records.dta, saving(record_map.dta) distance(calcdist) saveskipped

/*******************************************************************************

 Matches are saved in the data set given in the "saving()" option. 
 If record_map.dta already exists, existing matches are first removed from
 the master and using data sets. Then new matches are appended to record_map.dta
 This means the matching program can be quit and re-started with no problems.

 As long as the same master, using, and saving data sets are used, the 
 matching program will continue from wherever it was last quit. 
 
 To restart the matching process from the beginning, either delete the saving
 data set (record_map.dta), or put a different file name in the saving() option. 

 In the mapping file, each match has two observations. 
 Matches are identified with _source and _id. 
 _source: record from master or using data set
 _id: unique id for that pair of records (one from master, one from using)

 To merge master and using, first merge each file with map file based on 
 the varlist from the recmap command. In this case: 
 deliverylocation deliverydate age name1 name2 name3

 Then merge the master and using files based on _id.

*******************************************************************************/

clear
use record_map.dta
keep if _source==1
merge 1:1 deliverylocation deliverydate age name1 name2 name3 using endline_records.dta 
keep if _merge==3
drop _merge
save endline_map.dta, replace

clear
use record_map.dta
keep if _source==2
merge 1:1 deliverylocation deliverydate age name1 name2 name3 using maternity_records.dta 
keep if _merge==3
drop _merge
save maternity_map.dta, replace

clear
use endline_map.dta
merge 1:1 _id using maternity_map.dta
drop _merge
save endline_matched.dta, replace



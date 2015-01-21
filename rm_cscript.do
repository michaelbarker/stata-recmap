
clear all
discard

sysuse auto

rcof "recmap" == 100

rcof "recmap make price mpg using maternity_records.dta" == 198

rcof `"recmap make price mpg using maternity_records.dta , saving(`""map2.dta""')"' == 603




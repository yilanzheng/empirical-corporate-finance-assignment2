global raw_data ~/Desktop/ecf/assignment2/raw_data
global intermediate ~/Desktop/ecf/assignment2/intermediate_data
global output ~/Desktop/ecf/assignment2/output

***clean datasets
***mutual fund links
use $raw_data/mflink2_raw.dta
keep wficn fdate fundno
*duplicates report, no duplicates
drop if wficn == .
save $intermediate/mflink2.dta


use $raw_data/mflink1_raw.dta
keep wficn crsp_fundno
*duplicates report, no duplicates
mdesc
save $intermediate/mflink1.dta


***clean crsp mutual fund summary dataset to create index fund flag
use $raw_data/crsp_mutual_fund,clear
gen name_missing = missing(fund_name)
bysort crsp_fundno (name_missing caldt): keep if _n == 1
gen passive = strmatch(fund_name, "*Index*" "*Idx*" "*Indx*" "*Ind*" "*Russell*" "*S & P*" "*S and P*" "*S&P*" "*SandP*" "*SP*" "*DOW*" "*Dow*" "*DJ*" "*MSCI*" "*Bloomberg*" "*KBW*" "*NASDAQ*" "*NYSE*" "*STOXX*" "*FTSE*" "*Wilshire*" "*Morningstar*" "*100*" "*400*" "*500*" "*600*" "*900*" "*1000*" "*1500*" "*2000*" "*5000*")
replace passive = 1 if !missing(index_fund_flag)
gen active = 1 - passive 

keep crsp_fundno fund_name passive active
save $intermediate/crsp_mutual_fund_flag.dta


****Thompson Reuters s12 dataset (impute missing value)
use $raw_data/s12.dta
gen quarter = qofd(fdate)
format %tq quarter

***sort out observations with only a gap of a quarter with the last observation
sort fundno quarter cusip
by fundno: gen gap = quarter[_n] - quarter[_n-1]
*unique fundno quarter if gap == 2
expand 2 if gap == 2

***impute data of this quarter into the last quarter that we created
*duplicates report fundno quarter cusip gap
sort fundno quarter cusip gap
by fundno quarter cusip gap: replace fdate = dofq(quarter) - 1 if gap == 2 & _n == 1
by fundno quarter cusip gap: replace quarter = quarter - 1 if gap == 2 & _n == 1
drop gap
**cusip in TR S12 is historic
gen cusip6 = substr(cusip,1,6)
duplicates report fdate fundno cusip //no duplicates
save $intermediate/s12.dta


***compute market cap
***SHROUT is recorded in thousands
***PRC negative value is bid
***calculate the total market cap of each stock as the sum of shares outstanding multiplied by price for each class of common stock associated with a firm (sum across all PERMNOs associated with each PERMCO)
use $raw_data/crsp_monthly_stock,clear
rename *,lower
replace ncusip = cusip if missing(ncusip)
gen cusip6 = substr(ncusip,1,6)
gen mkt_cap = abs(altprc) * shrout * 1000
bysort date cusip6: egen total_cap = sum(mkt_cap)
by date cusip6: egen shares_outstanding = sum(shrout * 1000)
drop if total_cap == 0

keep cusip6 date total_cap shares_outstanding
/*
bys fdate cusip6 total_cap: gen nvals = _n ==1
by fdate cusip6: replace nvals = sum(nvals)
by fdate cusip6: replace nvals = nvals[_N]
**no multiple total cap for a single company
*/
duplicates drop
save $intermediate/crsp_stock_m.dta


****calculate the end-of-May market capitalization
gen year = year(fdate)
gen month = month(fdate)
keep if month == 5
rename total_cap may_mrkt_cap
keep cusip6 year may_mrkt_cap
duplicates drop
save $intermediate/may_mrkt_cap.dta


***multiple observation with different 8-digits cusip corresponding to the same 6 digits cusip
use $raw_data/russell_all
gen year = year(dofm(yearmonth))
keep cusip6 adj_mrktvalue r2000 year
bys cusip6 year: egen mrktvalue = sum(adj_mrktvalue)
drop adj_mrktvalue
duplicates drop cusip6 year,force

gsort year r2000 -mrktvalue
bys year r2000: gen mrkt_rank = _n
drop if r2000 == 1 & mrkt_rank > 250 
sort year r2000 mrktvalue
by year r2000: replace mrkt_rank = _n
drop if r2000 == 0 & mrkt_rank > 250
save $intermediate/russell.dta


***share of independent directors
use $raw_data/iss_director
rename *,lower
rename cusip cusip6
format year %7.0g
format employment_ceo - employment_vp %4.0g
sort cusip6 year
by cusip6 year: egen director_cnt = count(classification)
by cusip6 year: egen independent_director = sum(classification == "I")
keep year cusip6 director_cnt independent_director 
duplicates drop
gen pct_ind_dir = independent_director/director_cnt * 100
save $intermediate/director.dta


***governance data: poison pill removal, greater ability to call special meeting, indicator for dual class shares 
use $raw_data/iss_governance
rename *,lower
rename cn6 cusip6
format %4.0g dualclass ppill de_inc lspmt
sort cusip6 year
by cusip6: gen poison_pill_removal = ppill == 0 & ppill[_n-1] == 1
by cusip6: gen special_meeting = lspmt == 0 & lspmt[_n-1] == 1
keep cusip6 year poison_pill_removal special_meeting dualclass
save $intermediate/governance.dta


***management proposal support and shareholder governance proposal support
use $raw_data/company_vote.dta
gen cusip6 = substr(CUSIP,1,6)
gen year = year(MeetingDate)
keep cusip6 year sponsor votedFor votedAgainst votedAbstain
sort cusip6 year sponsor
by cusip6 year sponsor: egen sum_for = sum(votedFor)
by cusip6 year sponsor: egen sum_against = sum(votedAgainst)
by cusip6 year sponsor: egen sum_abstain = sum(votedAbstain)

gen support_management = sum_for/(sum_for + sum_against + sum_abstain) * 100 if sponsor == "Management"
gen support_shareholder = sum_for/(sum_for + sum_against + sum_abstain) * 100 if sponsor == "Shareholder"

by cusip6 year: egen supp_mgmt = max(support_management)
by cusip6 year: egen supp_sh = max(support_shareholder) 
duplicates drop cusip6 year, force
keep cusip6 year supp_mgmt supp_sh
save $intermediate/vote.dta


***ROA
use $raw_data/compustat_roa.dta,clear
gen cusip6 = substr(cusip,1,6)
gen year = year(datadate)
drop if missing(at,ni)
winsor2 at ni,replace cuts(1 99)
bys cusip6 year: egen at_sum = sum(at)
bys cusip6 year: egen ni_sum = sum(ni)
gen roa = ni_sum/at_sum
keep cusip6 year roa 
duplicates drop
save $intermediate/roa.dta



******MERGE ALL DATASETS
****Merge S12 mutual fund holdings and MF Link-2 by using fundno-fdate, which gives wficn
use $intermediate/s12.dta,clear
merge m:1 fundno fdate using $intermediate/mflink2
keep if _m==3
drop _m
tempfile step1
save `step1'

****Merge CRSP Mutual fund data and MF Link-1 by using crsp_fundno, which gives wficn
use $intermediate/crsp_mutual_fund_flag
merge m:1 crsp_fundno using $intermediate/mflink1
keep if _m==3
drop _m

bys wficn: egen temp = max(passive)
drop passive 
rename temp passive
replace active = 1-passive
duplicates drop wficn,force
tempfile step2
save `step2'

****Merge S12 mutual fund holdings and CRSP Mutual fund data by using wficn
use `step1'
merge m:1 wficn using `step2'
drop if _m == 2
gen unclassified = _m == 1
drop _m
tempfile s12_crsp
save `s12_crsp'

use $intermediate/crsp_stock_m,clear
gen month = month(date)
gen year = year(date)
keep if month == 9
drop date
tempfile crsp_stock
save `crsp_stock'

use `s12_crsp',clear
gen year = year(fdate)
gen month = month(fdate)
keep if month == 9
merge m:1 cusip6 year month using `crsp_stock'
keep if _m==3
drop _m
save $intermediate/s12_new.dta

cd $intermediate
merge m:1 cusip6 year using russell
keep if _m==3
drop _m

****generate ownership variables
sort cusip6 year
by cusip6 year: egen mf_own = sum(shares)
by cusip6 year: egen passive_own = sum(shares) if passive == 1
by cusip6 year: egen passive_own_max = max(passive_own)
by cusip6 year: egen active_own = sum(shares) if active == 1
by cusip6 year: egen active_own_max = max(active_own)
by cusip6 year: egen unclassified_own = sum(shares) if unclassified == 1
by cusip6 year: egen unclassified_own_max = max(unclassified_own)

by cusip6 year: gen pct_mf_own = mf_own/shares_outstanding * 100
by cusip6 year: gen pct_passive_own = passive_own_max/shares_outstanding * 100
by cusip6 year: gen pct_active_own = active_own_max/shares_outstanding * 100
by cusip6 year: gen pct_unclassified_own = unclassified_own_max/shares_outstanding * 100

mdesc
replace pct_passive_own = 0 if pct_passive_own == .
replace pct_active_own = 0 if pct_active_own == .
replace pct_unclassified_own = 0 if pct_unclassified_own == .
keep cusip6 year r2000 mrktvalue mrkt_rank pct_mf_own pct_passive_own pct_active_own pct_unclassified_own total_cap
duplicates drop
duplicates report cusip6 year
save s12_ownership.dta


****merge with other controls
merge 1:1 cusip6 year using director
drop if _m==2
drop _m

merge 1:1 cusip6 year using governance
drop if _m==2
drop _m

merge 1:1 cusip6 year using vote
drop if _m==2
drop _m

merge 1:1 cusip6 year using roa
drop if _m==2
drop _m

tabstat pct_mf_own pct_passive_own pct_active_own pct_unclassified_own pct_ind_dir poison_pill_removal special_meeting dualclass supp_mgmt supp_sh roa, s(n mean p50 sd) col(stat) f(%7.3f)

lab var pct_mf_own "Total mutual fund ownership %"
lab var pct_passive_own "Passive ownership %"
lab var pct_active_own "Active ownership %"
lab var pct_unclassified_own "Unclassified ownership %"
lab var pct_ind_dir "Independent director %"
lab var poison_pill_removal "Poison pill removal"
lab var special_meeting "Greater ability to call special meeting"
lab var dualclass "Indicator for dual class shares"
lab var supp_mgmt "Mngt. proposal support %"
lab var supp_sh "Shareholder gov. proposal support %"
lab var roa "ROA"
lab var r2000 "R2000"

save full_data.dta
estpost sum pct_mf_own pct_passive_own pct_active_own pct_unclassified_own pct_ind_dir poison_pill_removal special_meeting dualclass supp_mgmt supp_sh roa, d
esttab using $output/table1.tex, cells("count mean(fmt(%7.3g)) p50(fmt(%7.3g)) sd(fmt(%7.3g))") label collabels("Obs." "Mean" "Median" "SD") noobs nomtitle nonumber title(Summary Statistics)


*******Table 2: Impact of index assignment on mutual fund ownership
merge 1:1 cusip6 year using $intermediate/may_mrkt_cap.dta
drop if _m==2
drop _m

gen ln_may_mrkt_cap = ln(may_mrkt_cap)
gen ln_may_mrkt_cap_2 = ln(may_mrkt_cap)^2
gen ln_may_mrkt_cap_3 = ln(may_mrkt_cap)^3
gen ln_float = log(mrktvalue)

save reg_data.dta

reg pct_mf_own r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

reg pct_passive_own r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

reg pct_active_own r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

reg pct_unclassified_own r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth 250
estadd local Polynomial 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col4

esttab col* using $output/table2.tex, keep(r2000) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N r2, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations" "R-squared")) se mtitle("All mutual funds" "Passive" "Active" "Unclassified") title("Table 2: Impact of index assignment on mutual fund ownership.") label
estimates clear


*******Table 3: First-stage estimation for ownership by passively managed funds.
sum pct_passive_own
gen pct_passive_own_scaled = pct_passive_own/`r(sd)'
lab var pct_passive_own_scaled "Passive %"

reg pct_passive_own_scaled r2000 ln_may_mrkt_cap ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

reg pct_passive_own_scaled r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

reg pct_passive_own_scaled r2000 ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float i.year, vce(cluster cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

esttab col* using $output/table3.tex, keep(r2000) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N r2, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations" "R-squared")) se nomtitle title("Table 3: First-stage estimation for ownership by passively managed funds.") label
estimates clear


*****Table 4
sum pct_ind_dir
gen pct_ind_dir_scaled = pct_ind_dir/`r(sd)'

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

esttab col* using $output/table4.tex, keep(pct_passive_own_scaled) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations")) se nomtitle title("Table 4: Ownership by passive investors and board independence.") label
estimates clear


************Table 5
ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000) if year <= 2002, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000) if year <= 2002, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000) if year <= 2002, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000) if year >= 2003, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col4

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000) if year >= 2003, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col5

ivreghdfe pct_ind_dir_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000) if year >= 2003, absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col6

esttab col* using $output/table5.tex, keep(pct_passive_own_scaled) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations")) se nomtitle mgroups("Sample years=1998–2002" "Sample years=2003–2006", pattern(0 1 0 0 1 0)) title("Table 5 Passive ownership and board independence, pre- versus post-2002 rule change.") label
estimates clear


******Table 6
sum poison_pill_removal
gen poison_pill_removal_scaled = poison_pill_removal/`r(sd)'

sum special_meeting
gen special_meeting_scaled = special_meeting/`r(sd)'

ivreghdfe poison_pill_removal_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

ivreghdfe poison_pill_removal_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

ivreghdfe poison_pill_removal_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

ivreghdfe special_meeting_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col4

ivreghdfe special_meeting_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col5

ivreghdfe special_meeting_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col6

esttab col* using $output/table6.tex, keep(pct_passive_own_scaled) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations")) se nomtitle mgroups("Poison pill removal" "Greater ability to call special meeting", pattern(0 1 0 0 1 0)) title("Table 6: Ownership by passive investors and takeover defenses.") label
estimates clear

******Table 7: Ownership by passive investors and dual class share structures.
sum dualclass
gen dualclass_scaled = dualclass/`r(sd)'

ivreghdfe dualclass_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

ivreghdfe dualclass_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

ivreghdfe dualclass_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

esttab col* using $output/table7.tex, keep(pct_passive_own_scaled) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations")) se nomtitle title("Table 7: Ownership by passive investors and dual class share structures.") label
estimates clear


**************Table 8: Ownership by passive investors and shareholder support for proposals.
sum supp_mgmt
gen supp_mgmt_scaled = supp_mgmt/`r(sd)'
sum supp_sh 
gen supp_sh_scaled = supp_sh/`r(sd)'


ivreghdfe supp_mgmt_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col1

ivreghdfe supp_mgmt_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col2

ivreghdfe supp_mgmt_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col3

ivreghdfe supp_sh_scaled ln_may_mrkt_cap ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 1
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col4

ivreghdfe supp_sh_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 2
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col5

ivreghdfe supp_sh_scaled ln_may_mrkt_cap ln_may_mrkt_cap_2 ln_may_mrkt_cap_3 ln_float (pct_passive_own_scaled = r2000), absorb(year) cluster(cusip6)
estadd local Bandwidth = 250
estadd local Polynomial = 3
estadd local float_control "Yes"
estadd local year_fixed_effect "Yes"
estimates store col6

esttab col* using $output/table8.tex, keep(pct_passive_own_scaled) stats(Bandwidth Polynomial float_control year_fixed_effect N_clust N, label("Bandwidth" "Polynomial order, N" "Float control" "Year fixed effects" "# of firms" "Observations")) se nomtitle mgroups("Management proposal support %" "Governance proposal support %", pattern(0 1 0 0 1 0)) title("Table 8: Ownership by passive investors and shareholder support for proposals.") label
estimates clear
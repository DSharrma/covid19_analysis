--data was taken on 7/6/2023
--spans from 3/1/2020 to 8/6/2023
--general overview on what the data looks like

--covid deaths
select *
from PortfolioProjects..covid_death
order by 3,4

--covid vax
select *
from PortfolioProjects..covid_vax
order by 3,4

--data is recorded on a daily basis, 1 row per day
--Let's explore some insights, particulalrly Malaysia (I'm Malaysian)

--Some numeric data was stored as nvarchar data type so we convert it to int to perform calculations
--Note: Death rate will be measured by using deaths against cases at the time.

select location,date,total_cases,total_deaths,
	(convert(float,total_deaths) /convert(float,total_cases))*100 as PercentDeath
from PortfolioProjects..covid_death
where location = 'Malaysia'
order by 2

--First case in Malaysia recorded to be at 26/1/2020
--First death in Malaysia recorded to be at 17/3/2020 after 553 recorded cases

--the death rate does increase but at what rate? When was its worse times?
-- we will be using this result multiple times so let's create a temp table from it

--drop table if exists temptbl_death
with tbldeathrate as (
	select location,date,total_cases,total_deaths,
		round((convert(float,total_deaths) /convert(float,total_cases))*100,6) as PercentDeath,
		format(date,'MMM') as Month_name,
		format(date,'yyyy') as date_year
	from PortfolioProjects..covid_death
	where location = 'Malaysia'
),
tbldeathrate2 as(
	select *,
		round(((PercentDeath-lag(PercentDeath) over (order by date))/(lag(PercentDeath) over (order by date)))*100,6) as PercentChangeDeath
	from tbldeathrate
)

select tdr.*
into temptbl_death
from tbldeathrate2 tdr

select *
from temptbl_death
order by PercentChangeDeath desc
-- as expected there were large increases in the death rate in March and April 2020
-- there does seem to be this weird spike in the 3rd quarter of 2021
-- let's group it and get a clearer picture of the frequency

select date_year,
	count(*) as PositiveDeathRateCount
from temptbl_death
where PercentChangeDeath > 0
group by date_year
order by PositiveDeathRateCount desc

-- There was increasing frequency in positive death rates in 2021(224) than 2020,2022 and 2023.

select date_year,Month_name,
	count(*) as PositiveDeathRateCount
from temptbl_death
where PercentChangeDeath > 0 and date_year='2021'
group by date_year,Month_name
order by PositiveDeathRateCount desc
-- In 2021 the highest frequency of increasing death rates were in Jun, May, Sep, Jul and Aug

--Maybe not be so grim, let's investigate the cases and the vaccinations
--The table is narrowed down to Malaysia to we can exclude location column
--Clean up the date column formating
--Save it into temp table for further analysis

if OBJECT_ID('tbl_main') is not null drop table tbl_main
go
if OBJECT_ID('#temptbl_main') is not null drop table #temptbl_main
go
with tbl_main as(
	select format(td.date, 'yyyy-MM-dd') as clean_date,td.date_year, td.Month_name,
		cd.new_cases,td.total_cases,
		cd.new_deaths,td.total_deaths,
		vx.new_vaccinations
	from temptbl_death td
	left join (select date,new_vaccinations from PortfolioProjects..covid_vax where location='Malaysia') vx
		on td.date=vx.date
	left join (select date,new_cases,new_deaths from PortfolioProjects..covid_death where location='Malaysia') cd
		on td.date=cd.date
)
select *
into #temptbl_main
from tbl_main

--take a look, add a rolling total to get total vaccinations
select *,
	sum(convert(int,new_vaccinations)) over (order by convert(date,clean_date)) as total_vaccinations
from #temptbl_main

--some data on the cases, when were they the worst?
with top10group as
(
	select date_year,Month_name,sum(new_cases) as sum_cases
	from #temptbl_main
	group by Month_name,date_year
),
top10rank as
(
	select *, ROW_NUMBER() over (order by sum_cases desc) as rn
	from top10group
)
select* 
from top10rank
where rn<=10

--seems cases in Malaysia was doing especially worse in the second half of 2021 and the first half of 2022
with avgcase as
(
	select date_year,Month_name,sum(new_cases) as sum_cases
	from #temptbl_main
	where date_year=2021 or date_year=2022
	group by Month_name, date_year
)
select date_year, avg(sum_cases) as avg_cases
from avgcase
group by date_year

--about 200,000 cases a month on average in both 2021 and 2022

--deaths stats
with top10group as
(
	select date_year,Month_name,sum(new_deaths) as sum_deaths
	from #temptbl_main
	group by Month_name,date_year
),
top10rank as
(
	select *, ROW_NUMBER() over (order by sum_deaths desc) as rn
	from top10group
)
select* 
from top10rank
where rn<=10
--coincides with the cases, death tolls were highest in second half of 2021 and first qaurter of 2022

--take a look at vaccines
select clean_date,new_vaccinations
from #temptbl_main
where new_vaccinations is not null

--the first vaccinations in Malaysia was recorded to be taken at the end of Feb 2021
with cte_vd as
(
select date_year,month(clean_date) as month_no,new_cases,new_vaccinations,new_deaths
from #temptbl_main
--where new_vaccinations is not null
)
select date_year,month_no,
	sum(convert(float,new_cases)) as sum_cases,
	sum(convert(float,new_vaccinations)) as sum_vacc,
	sum(convert(float,new_deaths)) as sum_deaths
from cte_vd
group by month_no,date_year
order by date_year,month_no

--as vaccinations increased, it took until the second quarter of 2022 before cases and deaths plateaued
--we have only analyzed this for Malaysia so far

--there does seem to be this odd part of the data where the continent column is null and the location column has the continent name
with location_sum as 
(
	select sum(new_cases_per_million) as loc_case_sum
	from PortfolioProjects..covid_death
	where continent is null and location='Africa'
)
select (select loc_case_sum from location_sum) as loc_case_sum, sum(new_cases_per_million) as cont_case_sum
from PortfolioProjects..covid_death
where continent='Africa'
--it also seems to be incorrect when measuring the same data using continent column and location column
--when developing visualization, the null rows of the continent column will be removed.

--study vaccination table in depth
select location,date,total_vaccinations,new_vaccinations,people_vaccinated,people_fully_vaccinated
from PortfolioProjects..covid_vax
order by location,date
--people_vaccinated and people_fully_vaccinated is cumulative
--people_vaccinated + people_fully_vaccinated = total_vaccinations
--tv(n) + new_vaccinations = tv(n+1)

--========================================
--Problems:
--there are some rows where new_vaccinations are not acknowledged
--columns like total_vaccinations is not continuous, only static data points

--Solutions
--create columns with filled down data points
--have to create custom interval columns
--========================================

--we can kill 2 birds with 1 stone here and save this result in a temp table
--then join the temp table with the main table to create a single result
--this result is to create a view for import to visualization platform
--further exploration of the data shall be done by visualization.

with cte_tbl as
(
	select location, date, people_vaccinated,people_fully_vaccinated,total_vaccinations,
		count(people_vaccinated) over (partition by location order by date) as pv_group,
		count(people_fully_vaccinated) over (partition by location order by date) as pfv_group,
		count(total_vaccinations) over (partition by location order by date) as tv_group
	from PortfolioProjects..covid_vax
	where location is not null
),
fill_table as 
(
	select location,date,people_vaccinated,people_fully_vaccinated,total_vaccinations,
		coalesce(first_value(convert(bigint,people_vaccinated)) over (partition by location,pv_group order by date),0) as fill_ppl_vaccinated,
		coalesce(first_value(convert(bigint,people_fully_vaccinated)) over (partition by location,pfv_group order by date),0) as fill_ppl_full_vaccinated,
		coalesce(first_value(convert(bigint,total_vaccinations)) over (partition by location,tv_group order by date),0) as fill_total_vaccinated
	from cte_tbl
)
select *
from fill_table

--created filled down values columns
--replaced beginning null values with 0

--choose which columns to be used, clean, filter accordingly and create view

select cd.iso_code,cd.continent,cd.location,
	convert(date,format(cd.date,'yyyy-MM-dd')) as clean_date,
	cd.population,
	cd.new_cases,cd.total_cases,
	cd.new_deaths,cd.total_deaths,
	cv.new_vaccinations,cv.total_vaccinations
from PortfolioProjects..covid_death cd
left join PortfolioProjects..covid_vax cv
	on cv.date=cd.date
		and cv.location=cd.location
where cd.continent is not null
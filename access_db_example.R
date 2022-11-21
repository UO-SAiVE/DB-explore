#2022-11-22
#Database tutorial/exploration session with SAiVE group

#The following commented code is created to enable us to work together line-by-line while discussing a variety of topics and methods. You can follow along using RStudio and the Access database published to https://github.com/UO-SAiVE/DB-explore
#NOTE: if you aren't able to use the Access database, skip to line 32 and use the file data.RData, also at the GitHub url above.


#Open a database connection. This isn't quite the same as loading a .csv or .xlsx in memory, as the connection remains open - you're able to browse the DB without loading it in memory, handy for large datasets.
snowCon <- odbc::dbConnect(drv = odbc::odbc(), .connection_string = "Driver={Microsoft Access Driver (*.mdb, *.accdb)};DBQ=Data/SnowDB.mdb")

#Explore a little bit by showing all of the tables in the database
DBI::dbListTables(snowCon)

#Viewing the head()s of the tables gives us an idea of how the tables relate to one another, and we can start to formulate some questions.
head(DBI::dbReadTable(snowCon, "SNOW_COURSE"))
head(DBI::dbReadTable(snowCon, "SNOW_SAMPLE"))
head(DBI::dbReadTable(snowCon, "SNOW_BASIN"))
head(DBI::dbReadTable(snowCon, "AGENCY"))

#For the sake of this tutorial, let's say that we are interested in visualizing the basin-average snow pack for the Yukon River from 2000 to now, using only currently active stations.

#We'll need to pull together data from three sheets to answer this question: SNOW_SAMPLE for the depth/SWE readings themselves, SNOW_COURSE to determine what is active, and SNOW_BASIN to filter by basin.

#Load relevant data to the Global environment. In our case the DB is small so we can load it all in memory and work from the R environment. If the DB was very large compared to available RAM we could instead load subsets of these tables.
meas <- DBI::dbReadTable(snowCon, "SNOW_SAMPLE")
courses <- DBI::dbReadTable(snowCon, "SNOW_COURSE")
basins <- DBI::dbReadTable(snowCon, "SNOW_BASIN")

#The connection has to be closed after you're done, otherwise other processes will not be able to write to or even read from the database, depending on the type of DB and options.
odbc::dbDisconnect(snowCon)

#load("Data/data.RData") Uncomment this to load the data if you weren't able to use the Access database. Make sure the path is correct!

#Now we have three tables, with a total of 44 variables(!). To make it easier to view, we can remove unnecessary columns before proceeding. We'll do this in three difference ways.
#Method 1: Base R, selecting only what we want
View(meas)
head(meas)
meas[c(1,3,4,6,8),] #Beware, specify rows before columns! This line yields rows 1,3,4,6
meas[,c(1,3,4,6,8)] #This line yields rows 1,3,4,6 : correct
meas <- meas[,c(1:4,6,8)] #Note that we're overwriting the "old" meas data.frame
head(meas)
#Method 2: Base R, dropping unnecessary columns
View(courses)
head(courses)
courses <- courses[,-c(4:23)]
head(courses)
#Method 3: dplyr::select
head(basins) #basins is only 6 columns, so easy to view using head()
basins <- dplyr::select(basins, BASIN_ID, BASIN_DESC)
basins #Note I didn't specify head(basins); head renders the first 6 rows, and there are only 6 here. There is no difference.

#But we still have 9435 observations in meas! Let's revisit this one using a different method (base::subset), and also removing the column AGENCY_ID that we don't need.
head(meas)
meas <- subset(meas, SAMPLE_DATE >= "2000-01-01", select = -AGENCY_ID)
#Let's make sure that worked for the date selection... two methods:
View(meas)
min(meas$SAMPLE_DATE)
#QUESTION! Why do we see UTC in the console output??


#Allright! Now we've dramatically trimmed bloat from our data.frames. Let's combine them now. We have two options: base::merge, and the dplyr::join family.
?merge
?dplyr::join

#Let's start by joining basins and courses on a common variable.
head(merge(basins, courses)) #NOTE!!! Here we have a single commonly named column, BASIN_ID. If we had, say, BASIN_ID and basin_id, we would have to specify the by.x and by.y parameters.
head(dplyr::inner_join(basins, courses)) #Same here for common columns
locations <- merge(basins, courses)
#That worked! Now let's merge meas to create a data.frame with everything
all <- merge(meas, locations)

#Remember the EXCLUDE_FLG column? Let's see if we have any with a TRUE flag and if so, remove them.
subset(all, EXCLUDE_FLG == TRUE) #Note the use of ==, and not =. Also, TRUE not in quotations is a logical; if "TRUE", then it's a character vector. In this case either will work, but a character vector would have to be in quotations.
all <- subset(all, EXCLUDE_FLG != TRUE)

#And since we're also only looking for stations that are currently active...
subset(all, ACTIVE_FLG != TRUE)
all <- subset(all, ACTIVE_FLG == TRUE)



#Now we have a clean data set, and have gone some ways to answering our initial question:
#.... we are interested in visualizing the basin-average snowpack for the Yukon River from 2000 to now, using only currently active stations. We also want to know where the snowiest and driest locations are within this basin.
#We've merged everything, removed observations prior to 2000 and kept only active stations. Now we just need to visualize basin-average snowpacks.


#First we need to calculate a mean snow pack value for each year, then plot it. Note how there are values for February, March, April, and May each year:
unique(all$SAMPLE_DATE)

#Now at this point you should be asking yourself a few questions about the data if you haven't already. Pitfalls abound!

#It's important to realize here that our data needs to be grouped according to year and month: in other words, we need an average for Feb 2000, March 2000, April 2000, etc. There are lots of way to do this: the data frame can be broken up into small pieces (so only March for all years, say) and calculations run that way, or it can be left as-is and rows can be grouped based on column values. We'll use for loops and break it up into year-month pieces as that's easier to think through.

#It's also essential here to think about the "look" of the object we want. To plot, we need average values (SWE or depth) for each month and year in one column, and also a column containing that year and month. One will be the Y axis and the other the X axis. This will necessarily be a new data.frame as it doesn't fit within the dimensions of the existing data.frame.
#ok, onwards:

all$year <- substr(all$SAMPLE_DATE, 1,4)#This makes a new column with only the years, necessary for grouping
all$month <- substr(all$SAMPLE_DATE, 6,7) #This makes a new column with only the months
#What about days??? Looks like mostly "01", but no!
unique(substr(all$SAMPLE_DATE, 9,10))
#Let's remove anything not on the first of the month
all <- subset(all, substr(all$SAMPLE_DATE, 9,10) == "01")  #(this shaves only 10 samples from the total, so we won't worry about it)


#Now we'll create our new data.frame using nested for loops, as they're easy to think about. There are other methods too that are more space and computing-time efficient.

basin_means <- data.frame(ymd = NA, SWE = NA, depth = NA) #the for loop below needs a data.frame to bind new data to, with the right column names.
for (i in unique(all$year)){ #First iterator is years
  for (j in unique(all$month)){ #Second iterator is months
    ymd <- paste0(i, "-", j, "-01")
    SWE  <- mean(subset(all, year == i & month == j)$SNOW_WATER_EQUIV)
    depth <- mean(subset(all, year == i & month == j)$DEPTH)
    new <- data.frame(ymd = ymd, SWE = SWE, depth = depth) #Make a data.frame of one row

    basin_means[nrow(basin_means) + 1, ] <- new #bind the new data.frame!
  }
}

View(basin_means)


#Now let's plot!
plot(basin_means$ymd, basin_means$SWE) #This fails. Why? think about how a computer would plot the ymd column if it thinks they're numbers...

basin_means$ymd <- as.Date(basin_means$ymd)
plot(basin_means$ymd, basin_means$SWE) #Better! but how about color?

basin_means$year <- substr(basin_means$ymd, 1, 4) #adding a year column so we can visualize seasons better
ggplot2::ggplot(data = basin_means, ggplot2::aes(x = ymd, y = SWE, color = year)) +
  ggplot2::scale_x_date()+
  ggplot2::geom_point()+
  ggplot2::geom_line()+
  ggplot2::theme(legend.position = "none")

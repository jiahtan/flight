read_data_from_BTS = function(datadir){
  data = read.csv(datadir, stringsAsFactors = FALSE)
  colWanted = c("Year","Quarter","Month","DayofMonth","DayOfWeek","FlightDate",
                "UniqueCarrier","TailNum", "Origin","OriginCityName","OriginState",
                "Dest","DestCityName","DestState","DepTime","CRSDepTime","DepDelay",
                "DepDelayMinutes","DepDel15","DepTimeBlk","TaxiOut","WheelsOff","WheelsOn",
                "TaxiIn","CRSArrTime","ArrTime","ArrDelay","ArrDelayMinutes","ArrDel15",
                "ArrTimeBlk","CRSElapsedTime","ActualElapsedTime","Distance","DistanceGroup","Cancelled","CancellationCode",
                "CarrierDelay","WeatherDelay","NASDelay","SecurityDelay","LateAircraftDelay","Diverted")
  data = data[,colWanted]
  
  #  data = data[data$Origin %in% allAirports & 
  #           data$Dest %in% allAirports,]
  data
}

#Merge GPS Location
getGpsLocation = function(data){
  airports = read.csv("/media/sf_Windows/FlightData/airports.dat",header = FALSE,
                      col.names = c("ID","Name","City","Country","IATA","ICAO",
                                    "Lat","Lon","Altitude","Timezone","DST","Tz","Type","Source"))
  USairports = airports[airports$Country == 'United States',c("IATA", "Lat","Lon","Timezone")]
  finaldf = merge(data, USairports, by.x = 'Origin', by.y = 'IATA', all.x = TRUE)
  names(finaldf)[names(finaldf) %in% c('Lat','Lon','Timezone')] = paste("Origin",c('Lat','Lon','Timezone'))
  finaldf = merge(finaldf, USairports, by.x = 'Dest', by.y = 'IATA', all.x = TRUE)
  names(finaldf)[names(finaldf) %in% c('Lat','Lon','Timezone')] = paste("Dest",c('Lat','Lon','Timezone'))
  # #Fix timezone. Convert UTC offset to US timezone.
  finaldf$`Dest Timezone` = factor(finaldf$`Dest Timezone`)
  levels(finaldf$`Dest Timezone`) = c("US/Hawaii","US/Eastern","US/Central","US/Mountain","US/Pacific","US/Alaska")
  finaldf$`Origin Timezone` = factor(finaldf$`Origin Timezone`)
  levels(finaldf$`Origin Timezone`) = c("US/Hawaii","US/Eastern","US/Central","US/Mountain","US/Pacific","US/Alaska")
  finaldf = finaldf[!is.na(finaldf$`Dest Timezone`) & !is.na(finaldf$`Origin Timezone`),]
  return(finaldf)
}

library(lubridate)
convertToUTC = function(row){
  row[2] = as.numeric(row[2])
  if(nchar(row[2]) == 3)
    row[2] = paste0("0",row[2])
  if(nchar(row[2]) == 2)
    row[2] = paste0("00",row[2])
  if(nchar(row[2]) == 1)
    row[2] = paste0("000",row[2])
  date = paste(row[1:2],collapse = " ")
  # date = strptime(date, format="%Y-%m-%d %H%M", tz = as.character(row[3]))
  # date = with_tz(date, tzone = 'UTC')
  return(date)
}

getDistanceFromLatLonInKm = function (lat1,lon1,lat2,lon2) {
  R = 6371;
  dLat = deg2rad(lat2-lat1)
  dLon = deg2rad(lon2-lon1) 
  a = 
    sin(dLat/2) * sin(dLat/2) +
    cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * 
    sin(dLon/2) *sin(dLon/2)
  
  c = 2 * atan2(sqrt(a), sqrt(1-a))
  d = R * c * 0.621371
  return(d)
}

deg2rad = function (deg) {
  return(deg * (pi/180))
}

#Input DataFile
#Load October
processStorm = function(dataFile) {
  stormdf = read_data_from_BTS(dataFile)

  #Identify Lon and Lat as well as timezone.
  df= getGpsLocation(stormdf)

  df$DepDateTime = apply(df[,c("FlightDate","CRSDepTime")], 1,convertToUTC)

  cols =  paste0("UTC",c("Year", "Month","DayofMonth",
                       "DayOfWeek","DepHour","CRSDepTime"))
  df[cols] = NA

  for(timezone in c("US/Hawaii","US/Eastern","US/Central",
                                                  "US/Mountain","US/Pacific","US/Alaska")){
    date = strptime(df$DepDateTime[df$`Origin Timezone` == timezone], 
                  format="%Y-%m-%d %H%M", tz = timezone)
    date = with_tz(date, tzone = 'UTC')
    newdf = data.frame(Year = year(date),Month = month(date), Day = day(date),
             DayOfWeek = weekdays(date), Hour = hour(date), Time = strftime(date, format="%Y-%m-%d %H:%M:%S"))
    newdf$Time = as.character(newdf$Time)
    newdf$DayOfWeek =as.character(newdf$DayOfWeek)
    df[df$`Origin Timezone` == timezone,cols] = newdf
  }

  #Put time in blocks
  utcTimes = strptime(df$UTCCRSDepTime, format="%Y-%m-%d %H:%M:%S", tz = 'UTC')
  SixHourBlock = cut(utcTimes, breaks = "6 hour")
  df$DepSixHourBlock = SixHourBlock 
  return(df)
}
sandy = processStorm('/media/sf_Windows/FlightData/hurricaneSandy.csv')
katrina = processStorm('/media/sf_Windows/FlightData/hurricaneKatrina.csv')
ike = processStorm('/media/sf_Windows/FlightData/hurricaneIke.csv')

bigData = rbind(sandy,katrina, ike)
#Merge with NOAA
AtlanticHurricanes = read.csv("/media/sf_Windows/AtlanticHurricanes.csv", stringsAsFactors = FALSE)

KIS = AtlanticHurricanes[AtlanticHurricanes$Name %in% c("SANDY","KATRINA","IKE"),]
#Grab days that's on Sandy
KISDays = bigData[bigData$DepSixHourBlock %in% KIS$ISO_time,]

#Do merge 
library(sqldf)
KISMerged = sqldf("SELECT * FROM KISDays s LEFT JOIN KIS  h ON s.DepSixHourBlock = h.ISO_time")
DepDistanceToStorm = getDistanceFromLatLonInKm(KISMerged$`Origin Lat`,KISMerged$`Origin Lon`,
                                            KISMerged$Latitude, KISMerged$Longitude)
ArrDistanceToStorm = getDistanceFromLatLonInKm(KISMerged$`Dest Lat`, KISMerged$`Dest Lon`,
                                               KISMerged$Latitude, KISMerged$Longitude)
KISMerged$DepDistanceToStorm = DepDistanceToStorm
KISMerged$ArrDistanceToStorm = ArrDistanceToStorm
save(KISMerged, file = "KISMerged.rda")

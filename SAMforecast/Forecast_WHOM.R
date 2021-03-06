#################################################
## Example script to run SAM forecast for WHOM ##
## Author: Vanessa Trijoulet vtri@aqua.dtu.dk  ##
#################################################

# Initialization ---------
#devtools::install_github("vtrijoulet/SAM/stockassessment", ref="master2") # Only to do once to install the right package

library(stockassessment)
library(Matrix)
library(gridExtra)
library(tidyverse)

Drive    <- "D:"
Base.dir <- file.path(Drive,"GIT")
MSE.dir <- file.path(Base.dir,"wk_WKREBUILD","EqSimWHM")
Res.dir <- file.path(MSE.dir, "Results")

# Get dropbox dir; for storing large RData files
source("EqSimWHM/R/get_dropbox.R")
dropbox.dir <- file.path(get_dropbox(), "HOM FG", "05. Data","RData")

name <- "WHOM_2019" 
fit<- fitfromweb(name, character.only = TRUE)
source("SAMforecast/HS_fit_fixBlim.R") # calculate a segmented regression with recruitment pairs, modified from original function HS_fit.R available in the package, which estimates the inflexion point


# Define function arguments ---------
## Ref pts that shape the HCRs:
Blim=611814
MSYBtrig=856540
Fmsy=0.115 # Used as Ftarget in HCR
Flow=Fmsy/5 # To choose if HCR 3-5

## Simulation assumptions: 
SRpar <- HS_fit_fixBlim(name, pair.years=1995:2017) # years for SSB-R pairs, usually the same than ones used to calculate FMSY if relevant (SR=TRUE)
Ay<-max(fit$data$years)+(-9:0) # for average for bio input (M, w, etc.)
Ry<-1995:2017 # for average for recruitment input
Sy<-max(fit$data$years)+(-9:0) # for selectivity input
TAC2018=101672
TAC2019=110381
TAC2020=83954 
#TAC <- TAC2020 # For intermediate year

# simulation periods; hardcoded !!
CU <- 2018:2020
ST <- 2021:2025
MT <- 2026:2030
LT <- 2031:2040

F_targets <- c(0.01, seq(0.05,0.15,by=0.025))
#F_targets <- c(0.05)

# To change between MS scenariosRW=TRUE
RW = FALSE # random walk on recruitment
Rdist=FALSE # recruitment with mean and sd from sampled years
F.RW=FALSE # if false no RW with increase variance in F in the forecast
SR=TRUE # for SR relationship for rec coming from SRpar
ny <- 23 # years for the forecast

#nsim=5000
nsim=1000

om = "-"
mp = "5.10"
assess = "sam"
method = "samhcr"
stock = "WHOM"
runName = paste(method, stock,assess, om,mp,nsim,ny, sep="_")
#runName = "HCR2_SR"

FC <- list()
dfy <- data.frame(stringsAsFactors = FALSE)

set.seed(12345) # same seed to repeat output
i <- 1

for (i in 1:length(F_targets)) {
  
  # Run the forecast with HCR2 and SR relationship -----
  
  ftgt <- F_targets[i]
  
  cat(i," ",ftgt,"\n")
  
  FC[[i]]       <- forecast2(fit, fscale            = c(rep(NA,ny)), 
                                  catchval          = c(TAC2018, TAC2019, TAC2020, rep(NA,ny-3)),
                                  fval              = rep(NA, ny),
                                  rec.years         = Ry, 
                                  ave.years         = Ay,
                                  overwriteSelYears = Sy, 
                                  label             = runName,
                                  nosim             = nsim,
                                  deterministic     = FALSE,
                                  Fscenario         = 2,
                                  MSYBtrig          = c(rep(NA,3), rep(MSYBtrig,ny-3)), 
                                  Blim              = c(rep(NA,3), rep(Blim,ny-3)),
                                  Fmsy              = ftgt,
                                  Flow              = Flow, #for Fscenario= 3, 4 or 5
                                  RW                = RW,
                                  Rdist             = Rdist,
                                  SR                = SR,
                                  SRpar             = SRpar,
                                  F.RW              = F.RW )   
  
  # Convert to data.frame
  for (y in 1:length(FC[[i]])) {
    for (v in names(FC[[i]][[y]])) {
      
      
      if (class(FC[[i]][[y]][[v]]) == "numeric") {
        # print(paste(v, class(FC[[i]][[y]][[v]])), sep="  ")
        t <- data.frame(
          assess   = assess,
          method   = method,
          stock    = stock,
          value    = FC[[i]][[y]][[v]],
          perfstat = tolower(v),
          year     = as.numeric(FC[[i]][[y]]$year),
          runref   = runName,
          iter     = 1:nsim,
          niters   = nsim, 
          nyrs     = ny,
          ftgt     = ftgt,
          rw       = RW, 
          sr       = SR,
          om       = om, 
          mp       = mp, 
          blim     = Blim, 
          bpa      = MSYBtrig,
          fmsy     = Fmsy,
          stringsAsFactors = FALSE) %>% 
          
          mutate(ftgt = ifelse(ftgt==0.01, 0, ftgt)) %>% 
          
          mutate(period = ifelse(year %in% CU, "CU", as.character(NA))) %>% 
          mutate(period = ifelse(year %in% ST, "ST", period)) %>% 
          mutate(period = ifelse(year %in% MT, "MT", period)) %>% 
          mutate(period = ifelse(year %in% LT, "LT", period)) %>% 
          
          mutate(unit = as.character(NA))  # temporary fix
          
        dfy <- bind_rows(dfy,t)
        
        #print(head(t))
      } # end of if statement
    } # end of v loop
  }  # end of y loop

} # end of i loop

# calculate overall statistics and add to dataset
t2 <- 
  dfy %>% 
  filter(perfstat %in% c("ssb"))  %>% 
  pivot_wider(names_from = perfstat, values_from = value)  %>% 
  group_by(assess, method, stock, year, runref,
           niters,nyrs,ftgt,rw,sr,om,mp, fmsy, period, unit) %>%
  summarize(
    pblim = sum(ssb<blim)/nsim,
    pbpa  = sum(ssb<bpa)/nsim) %>% 
  pivot_longer(c(pblim, pbpa), names_to="perfstat") %>% 
  mutate(iter = 1)

dfy <- 
  bind_rows(dfy, t2) %>% 
  mutate(ftgt = as.numeric(as.character(ftgt)))

save(dfy,file = file.path(Res.dir,"Stats",paste0(runName,"_dfy.Rdata")))

# dfy %>% filter(ftgt > 0.05 & ftgt < 0.1) %>% View()
# dfy %>% filter(ftgt > 0.05 & ftgt < 0.1) %>% View()
# dfy %>% filter(ftgt == 0.075) %>% View()
# scales::comma(unique(dfy$ftgt), accuracy=0.0001)

# Run the forecast with HCR2 with decreasing recruitment -----
# RW = TRUE  # random walk on recruitment
# drift = 0.2 # decrease in mean recruitment of 10% the sd
# SR=FALSE # for SR relationship for rec coming from SRpar

# set.seed(seed) # same seed to repeat output
# FC[[length(FC)+1]] <- forecast2(fit, fscale=c(1, rep(NA,ny-1)), 
#                                 catchval=c(NA, TAC2018, TAC2019, TAC2020, rep(NA,ny-4)),
#                                 fval=,rep(NA, ny),
#                                 rec.years=Ry, 
#                                 ave.years=Ay,
#                                 overwriteSelYears=Sy, 
#                                 label="HCR2_RWdrift",
#                                 nosim=nsim,deterministic=FALSE,
#                                 Fscenario=2,
#                                 MSYBtrig=c(rep(NA,4), rep(MSYBtrig,ny-4)), 
#                                 Blim=c(rep(NA,4), rep(Blim,ny-4)),
#                                 Fmsy=Fmsy,
#                                 Flow=Flow, #for Fscenario= 3, 4 or 5
#                                 RW=RW,
#                                 drift=drift,
#                                 Rdist=Rdist,
#                                 SR=SR,
#                                 SRpar=SRpar,
#                                 F.RW=F.RW
# )   


# Run the forecast with HCR2 with SR but high catch to decrease SSB -----
# RW = FALSE  # random walk on recruitment
# SR=TRUE # for SR relationship for rec coming from SRpar

# set.seed(seed) # same seed to repeat output
# FC[[length(FC)+1]] <- forecast2(fit, fscale=c(1, rep(NA,ny-1)), 
#                                 catchval=c(NA, TAC2018*5, TAC2019*5, TAC2020*5, rep(NA,ny-4)),
#                                 fval=,rep(NA, ny),
#                                 rec.years=Ry, 
#                                 ave.years=Ay,
#                                 overwriteSelYears=Sy, 
#                                 label="HCR2_SR_lowSSB",
#                                 nosim=nsim,deterministic=FALSE,
#                                 Fscenario=2,
#                                 MSYBtrig=c(rep(NA,4), rep(MSYBtrig,ny-4)), 
#                                 Blim=c(rep(NA,4), rep(Blim,ny-4)),
#                                 Fmsy=Fmsy,
#                                 Flow=Flow, #for Fscenario= 3, 4 or 5
#                                 RW=RW,
#                                 Rdist=Rdist,
#                                 SR=SR,
#                                 SRpar=SRpar,
#                                 F.RW=F.RW
# )   


# Looking at the outputs, example -----

# scenario_number <- 1
# name_scenario <- attr(FC[[scenario_number]], "label") # name of 1st scenario run above
# FC[[scenario_number]] # summary table of median outputs with CI
# plot(FC[[scenario_number]], main=name_scenario) # SSB, Fbar and rec plots
# forecast_year <- 1 # 1:ny
# variable_name <- ls(FC[[scenario_number]][forecast_year][[1]]) # all names of output replicates saved in FC
# FC[[scenario_number]][forecast_year][[1]][variable_name[1]] # to extract replicates of a specific output


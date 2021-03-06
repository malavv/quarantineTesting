

run_sim <- function(params){
  #Takes parameter from shiny app inputs and returns dt_raw,
  #  which is the .01, .50, and .99th percentiles of the
  #  simulations for days at risk per infected traveller
  n_sympt = 6000
  n_asympt = 1000
  print("run_sim")
  
  set.seed(params$seed)
  

  #n_iters = params$n_iters
  
  #Sample asympt duration gamma parameters
  dt_d_asympt <- data.table(
    mean = runif(params$n_iters, min = params$dur_asympt_mean_lb, max = params$dur_asympt_mean_ub),
    var = runif(params$n_iters, min = params$dur_asympt_var_lb, max = params$dur_asympt_var_ub)
  )
  dt_d_asympt[ , par1 := mean^2/var]
  dt_d_asympt[ , par2 := var/mean]
  
  #Sample sympt duration gamma parameters
  dt_d_sympt <- data.table(
    mean = runif(params$n_iters, min = params$dur_sympt_mean_lb, max = params$dur_sympt_mean_ub),
    var = runif(params$n_iters, min = params$dur_sympt_var_lb, max = params$dur_sympt_var_ub)
  )
  dt_d_sympt[ , par1 := mean^2/var]
  dt_d_sympt[ , par2 := var/mean]
  
  #Sample presympt duration gamma parameters (truncation implemented in iteration forloop below)
  dt_d_presympt <- data.table(
    mean = runif(params$n_iters, min = params$dur_presympt_mean_lb, max = params$dur_presympt_mean_ub),
    var = runif(params$n_iters, min = params$dur_presympt_var_lb, max = params$dur_presympt_var_ub)
  )
  dt_d_presympt[ , par1 := mean^2/var]
  dt_d_presympt[ , par2 := var/mean]
  
  #table to store output
  dt_raw_metrics <- data.table(
    iter = numeric(),
    quarantine_length = numeric(),
    testing = character(),
    d_presympt = numeric(),
    d_sympt = numeric(),
    d_asympt = numeric()
  )

  
  if (params$n_iters < 1000){
    dt_incubation_dists_lnorm <- dt_incubation_dists_lnorm[sample(.N, params$n_iters)]
  }
  
  withProgress(message = 'Running simulation', value = 0, {
    # Iterate over sets of duration parameters
    for (row in 1:params$n_iters){
      #print(row)
      #[PRE]SYMPOMATIC INFECTION
      #Sample all durations
      dt_sympt <-
        data.table(
          dur_presympt = rtrunc(n_sympt, "gamma", 0.8, 3, 
                                shape=dt_d_presympt[row, par1], scale=dt_d_presympt[row, par2]),
          dur_sympt = rgamma(n_sympt, 
                             shape=dt_d_sympt[row, par1], scale = dt_d_sympt[row, par2]),
          dur_incubation = rlnorm(n_sympt, 
                                  meanlog=dt_incubation_dists_lnorm[row, par1], 
                                  sdlog = dt_incubation_dists_lnorm[row, par2])
        )
      
      #Calc times. t=0 is time of infection
      dt_sympt[ , t_infectious_start := pmax(0, dur_incubation - dur_presympt)]
      dt_sympt[ , t_sympt_start := dur_incubation]
      dt_sympt[ , t_recovery := dur_incubation + dur_sympt]
      if(params$rand_u == TRUE){
        dt_sympt[ , dur_infected_prequarantine := runif(n_sympt)*t_recovery]
      } else {
        dt_sympt[ , dur_infected_prequarantine := 0]
      }
      
      
      
      #ASYMPTOMATIC INFECTION
      #Sample all durations
      dt_asympt <-
        data.table(
          dur_presympt = rtrunc(n_asympt, "gamma", 0.8, 3, 
                                shape=dt_d_presympt[row, par1], scale=dt_d_presympt[row, par2]),
          dur_infectious = rgamma(n_asympt, 
                                  shape=dt_d_asympt[row, par1], scale = dt_d_asympt[row, par2]),
          dur_incubation = rlnorm(n_asympt, 
                                  meanlog=dt_incubation_dists_lnorm[row, par1], 
                                  sdlog = dt_incubation_dists_lnorm[row, par2])
        )
      
      #Calc times
      dt_asympt[ , t_infectious_start := pmax(0, dur_incubation - dur_presympt)]
      dt_asympt[ , t_recovery := t_infectious_start + dur_infectious]
      if(params$rand_u == TRUE){
        dt_asympt[ , dur_infected_prequarantine := runif(n_asympt)*t_recovery]
      } else {
        dt_asympt[ , dur_infected_prequarantine := 0]
      }
      #BOTH
      #Calculate outcomes
      dt_metrics_this_iter <-
        rbind(
          data.table(
            iter = row,
            quarantine_length = params$dur_quarantine,
            testing = 0,
            d_presympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_presympt_days_in_community, 
                                       dt_sympt = dt_sympt, params=params, test = 0)),
            d_sympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_sympt_days_in_community, 
                                    dt_sympt = dt_sympt, params=params, test = 0)),
            d_asympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_asympt_days_in_community, 
                                     dt_asympt = dt_asympt, params=params, test = 0))),
          data.table(
            iter = row,
            quarantine_length = params$dur_quarantine,
            testing = 1,
            d_presympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_presympt_days_in_community, 
                                       dt_sympt = dt_sympt, params=params, test = 1)),
            d_sympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_sympt_days_in_community, 
                                    dt_sympt = dt_sympt, params=params, test = 1)),
            d_asympt = unlist(lapply(X = params$dur_quarantine, FUN = calc_asympt_days_in_community, 
                                     dt_asympt = dt_asympt, params=params, test = 1)))
        )
      
      dt_raw_metrics <- rbind(dt_raw_metrics,
                              dt_metrics_this_iter)
      
      #print(params$n_iters)
      #print(typeof(params$n_iters))
      incProgress(amount = 1/params$n_iters)
    }
  })


  
  
  
  dt_raw_metrics[ , d_tot := (d_asympt*params$prob_asympt +
                                (1-params$prob_asympt)*(d_sympt+d_presympt))
                  ]
  

  
  quant_probs = c(.01, .5, .99)
  dt_metrics <- dt_raw_metrics[ , list(value= quantile(d_tot, probs = quant_probs),
                                       quantile = paste0("q",quant_probs)), by = c("quarantine_length", "testing")]
  
  #print("all but fwrite")
  
  return(dt_metrics)
}







calc_presympt_days_in_community <- function(quarantine_length, dt_sympt, params, test = 0){
  if(test == 0){
    return(
      dt_sympt[ , sum(
        pmax(0,(1-params$prob_quarantine_compliance)*
               (t_sympt_start - pmax(t_infectious_start, dur_infected_prequarantine)))+
          pmax(0,params$prob_quarantine_compliance*
                 (t_sympt_start - pmax(t_infectious_start, quarantine_length+dur_infected_prequarantine))
          )
      )/nrow(dt_sympt)]
    )
  } else {
    return(
      dt_sympt[ , sum(
        #Noncompliant with quarantine, not tested
        pmax(0,(1-params$prob_quarantine_compliance)*
               (t_sympt_start - pmax(t_infectious_start, dur_infected_prequarantine)))+
          params$prob_quarantine_compliance*
          pmax(0,
               ifelse(quarantine_length+dur_infected_prequarantine-1 < t_infectious_start,
                      #tested before infectious
                      t_sympt_start - pmax(dur_infected_prequarantine+quarantine_length, t_infectious_start),
                      #tested while presymtomatic or after
                      ((1-params$sn_presympt)+params$sn_presympt*(1-params$prob_isolate_test))* #prob test neg or test pos & refuse to isolate
                        (t_sympt_start - (quarantine_length+dur_infected_prequarantine)))
          )
      )/nrow(dt_sympt)]
    )
    
  }
}


calc_sympt_days_in_community <- function(quarantine_length, dt_sympt, params, test = 0){
  if(test == 0){
    return(
      dt_sympt[ , sum(
        #probability no isolation with symptoms
        (1-params$prob_isolate_sympt)*
          (#noncompliant with quarantine
            pmax(0,(1-params$prob_quarantine_compliance)*(t_recovery - pmax(t_sympt_start, dur_infected_prequarantine)))+
              #compliant with quarantine
              params$prob_quarantine_compliance*
              pmax(0,
                   t_recovery - pmax(t_sympt_start, dur_infected_prequarantine+quarantine_length)
              )
          )
      )/nrow(dt_sympt)]
      
      
    )
  } else {
    return(
      dt_sympt[ , sum(
        #noncompliant
        (1-params$prob_quarantine_compliance)*(1-params$prob_isolate_sympt)*
          pmax(0, t_recovery - pmax(t_sympt_start, dur_infected_prequarantine))+
          params$prob_quarantine_compliance*
          pmax(0,
               ifelse((quarantine_length+dur_infected_prequarantine - 1 < t_infectious_start),
                      #tested before infectious therefore neg test
                      (t_recovery - pmax(t_sympt_start, quarantine_length+dur_infected_prequarantine))*
                        (1-params$prob_isolate_sympt),
                      ifelse((quarantine_length+dur_infected_prequarantine - 1 < t_sympt_start),
                             #tested during presymptomatic
                             #  tested negative
                             (1-params$sn_presympt)*(1-params$prob_isolate_sympt)*
                               (t_recovery - pmax(t_sympt_start, quarantine_length+dur_infected_prequarantine)) +
                               #  tested positive
                               params$sn_presympt*(1-params$prob_isolate_both)*
                               (t_recovery - pmax(t_sympt_start, quarantine_length+dur_infected_prequarantine)),
                             #tested while symptomatic or after
                             #  tested negative
                             (1-params$sn_sympt)*(1-params$prob_isolate_sympt)*
                               (t_recovery - (quarantine_length + dur_infected_prequarantine))+
                               #  tested positive
                               params$sn_sympt*(1-params$prob_isolate_both)*
                               (t_recovery - (quarantine_length + dur_infected_prequarantine))
                      )
               )
          )
        
      )/nrow(dt_sympt)]
    )
  }
}


calc_asympt_days_in_community <- function(quarantine_length, dt_asympt, params, test = 0){
  if(test == 0){
    return(
      dt_asympt[ , sum(
        pmax(0,(1-params$prob_quarantine_compliance)*
               (t_recovery - pmax(dur_infected_prequarantine, t_infectious_start)))+
          pmax(0, params$prob_quarantine_compliance*
                 (t_recovery - pmax(t_infectious_start, quarantine_length+dur_infected_prequarantine)))
      )/nrow(dt_asympt)]
    )
  } else {
    return(
      dt_asympt[ , sum(
        #No compliance & no test
        pmax(0, (1-params$prob_quarantine_compliance)*
               (t_recovery - pmax(dur_infected_prequarantine, t_infectious_start)))+
          params$prob_quarantine_compliance*pmax(0, 
                                                 ifelse(quarantine_length+dur_infected_prequarantine - 1 < t_infectious_start,
                                                        #tested before infectious/detectable
                                                        t_recovery - pmax(t_infectious_start, dur_infected_prequarantine+quarantine_length),
                                                        #tested while or after infectious
                                                        ((1-params$sn_asympt)+params$sn_asympt*(1-params$prob_isolate_test))* #Prob test neg or test pos & refuse to quarantine
                                                          (t_recovery - (quarantine_length+dur_infected_prequarantine))
                                                 )
          )
      )/nrow(dt_asympt)]
    )
    
  }
}  







make_dt_analysis <- function(
  dt_raw,
  metric,
  include_test,
  prev,
  sec_cases_per_day
) {
  #Takes raw data table and converts
  #  the value to the selected outcome and
  #  dcasts the datatable to wide format so each policy is
  #  a line and the 3 quantiles each have their own column
  

  dt_analysis <- cbind(dt_raw)
  dt_analysis[ , testing := ifelse(testing==1, "Test", "No test")]

  if (metric == "person-days"){
    dt_analysis[ , value := value*1e4*prev]
  } else if (metric == "sec-cases"){
    dt_analysis[ , value := value*1e4*prev*sec_cases_per_day]
  }

  if(include_test == FALSE){
    dt_analysis <- dt_analysis[testing == "No test"]
    dt_analysis[, testing := NULL]
    return(dcast(dt_analysis, quarantine_length~quantile, value.var = "value"))
  } else{
    return(dcast(dt_analysis, quarantine_length+testing~quantile, value.var = "value"))
  }
  

}












update_analysis <- function(dt_raw, analysis_params){
  #Convert dt_raw into dt for display
  
  
  #analysis_params is list
  #   metric %in% "days", "person-days", or "sec-cases"
  #   include_test $in$ TRUE/FALSE
  #   
  print("update_analysis")
}




# 
# dt_raw_metrics = sim_quarantine_lnorm(
#   dt_incubation_dists_lnorm = dt_incubation_dists_lnorm,
#   params = params)
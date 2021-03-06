# This new (old) approach, instead of getting a summary(e.g. median) for each occurrence of an epoch (or category),
# first pastes together the stream correspoding to each epoch and THEN calculates the summarizing function
# no results on IM
#This approach may actually flatten up the results as given synchrony high variability,
# the median of a long segment tends to be the same, independently on how much synchrony was observed.
# a better summarizing metric with this approach could be % of time synchrony is above a given threshold




#' Extract stream chunks corresponding to epochs
#' 
#' epochStream cycles through all sessions in an experiment.
#' For each session extracts a stream, then cuts it
#' according to categories epochs
#'
#' @param x 
#' @param signal  asd
#' @param sync 
#' @param streamKey 
#' @param category 
#' @param groupIndex 
#' @param artefact.rm 
#' @param mergeEpochs 
#' @param shift_start integer in seconds (e.g. -5 shifts all epoch starts by 5 seconds before )
#' @param shift_end integer in seconds (e.g. 7 shifts all epoch end by 7 seconds later )
#'
#' @return
#' @export
#'
#' @examples
epochStream = function(x, signal= "SC", sync="PMBest", streamKey="sync", category, groupIndex,
                       mergeEpochs=FALSE, artefact.rm=TRUE, shift_start = 0, shift_end = 0){
  UseMethod("epochStream", x)
}

#' @export
epochStream.DyadExperiment = function(x, signal= "SC", sync="PMBest", streamKey="sync", category, groupIndex,
                                      mergeEpochs=FALSE, artefact.rm=TRUE, shift_start = 0, shift_end = 0){
  res = Map(function(session, nSession){
    prog(nSession, length(x))
    cat("session:", attr(session,"dyadId"),"-", attr(session,"sessionId"),"\r\n")
    epochStream(session, signal, sync, streamKey, category, groupIndex,mergeEpochs, artefact.rm, shift_start, shift_end )
  },x, seq_along(x))
  classAttr(res) = classAttr(x)
  res
}

#' @export
epochStream.DyadSession = function(x, signal, sync, streamKey, category, groupIndex, mergeEpochs, artefact.rm, shift_start, shift_end){
  ##DEBUG
  # x = d$all_CC_4
  # signal="SC"
  # x$SC$artefacts = rbind(data.frame(start=c(160,300), end=c(200,400)),x[[signal]]$artefacts)
  # 
  # sync="PMdev"
  # streamKey = "sync"
  # category="PACS"
  # groupIndex="PACS"
  # mergeEpochs = F
  # artefact.rm=T
  ###
  
  if(!sync %in% c("none",names(x[[signal]]))) stop ('sync was',sync,'and should be one of: none,',names(x[[signal]]))
  resName = paste0(c(toupper(category),"_",totitle(c(if(sync=="none"){""}else{sync},streamKey))),collapse = "")
  
  #select stream according to sync and streamkey
  if(sync!="none"){
    if(length(names(x[[signal]][[sync]])) == 0) stop ("'sync' argument must point to a list containing 'streamKey'")
    if(!streamKey %in% names(x[[signal]][[sync]])) stop ('streamKey should be one of:',names(x[[signal]][[sync]]))
    stream = x[[signal]][[sync]][[streamKey]]
  } else {
    if(!streamKey %in% c("s1","s2","time")) stop ("sync none requires streamkey == s1 or s2 or time")
    stream = x[[signal]][[streamKey]]
  }
  if( artefact.rm ){
    # if(length(stream)!=length(x[[signal]]$valid)) stop("artefact.rm temporarily requires that stream has the same frequency of valid")
    ## remove Artefacts windows from stream
    for(i in 1:nrow(x[[signal]]$artefacts)){
      # asd = ts(1:101, frequency=10,start=0)
      # #i campioni da rimuovere sono dal secondo 5 al secondo 7
      # window(asd, start=5,end=7) <- NA
      # # funziona indipendentemente da frequency,
      # # es. in una ts con frequenza diversa:
      # asd2 = ts(seq(1,101,by=10),frequency = 1,start=0)
      # window(asd2,start=5,end=7) <- NA
      
      cat("\r\n",x[[signal]]$artefacts$start[i], " ", x[[signal]]$artefacts$end[i])
      window(stream, start=x[[signal]]$artefacts$start[i],end=x[[signal]]$artefacts$end[i]) <- NA
    }
    
    stream[!x[[signal]]$valid]=NA
  }
  # seleziona il dataframe della categoria e crea un oggetto per ciascun livello
  cate = x[[category]]
  cate$start = cate$start + shift_start
  cate$end = cate$end + shift_end
  if(!is.factor(cate[[groupIndex]])) stop("groupIndex should be a factor column in the epoch table")
  resList = list()
  #istanzia i contenitori vouti per ciascun livello
  for(lev in levels(cate[[groupIndex]])){
    # dur = sum((cate[cate[[groupIndex]]==lev,"end"] - cate[cate[[groupIndex]]==lev,"start"] )*frequency(stream))
    if(mergeEpochs)
      resList[[lev]]=numeric()
    else
      resList[[lev]]=list()
  }
  names(resList) = levels(cate[[groupIndex]])

  remStream = stream
  for(i in 1:nrow(cate)){ #for each epoch
    if(!is.na(cate[[groupIndex]][i]) && !is.null(cate[[groupIndex]][i])) {
      if(cate$start[i]>=end(stream)[1]){
        warning("In session ", dyadId(x),"-",sessionId(x), ", start of window ",i,": was equal to or beyond the stream end.", call.=F)
        # lres[[i]] = NA
      } else { #if start is before the end of stream, as it should...

        #if (by applying shift_start) cate$start is before the signal start, create a NA padding
        if(cate$start[i]<start(stream)[1]){
          padding = ts(start = cate$start[i],
                     end = c(start(stream)[1],0), #-> since the real signal starts at c(start(stream)[1],1)
                     frequency = frequency(stream))
          cate$start[i] = start(stream[1])
        } else padding = NULL
        
        #if end goes beyond the stream duration...
        if(cate$end[i] > end(stream)[1] ){
          message("In session ", dyadId(x),"-",sessionId(x), ", end of window ",i,": was reduced to the stream end.", call.=F)
          cate$end[i]= end(stream)[1]
        }
        
        # rimuovi la finestra dallo stream di segnale residuo remStream:
        window(remStream, start = cate$start[i], end = cate$end[i]) <- NA ## broken?
        
        # ###################### SHIT
        # asd = as.numeric(remStream)
        # asd = ts(runif(580), start = 162.5, end = 3057.5, frequency = 0.2)
        # window(asd, start = 200, end = 300) <- NA
        # 
        # 
        # x = remStream
        # xtsp <- tsp(x)
        # m <- match.call(window, call("window",remStream, start = cate$start[i], end = cate$end[i]),expand.dots = FALSE)
        # m$value <- NULL
        # m$extend <- TRUE
        # m$x <- x
        # m[[1L]] <- quote(stats::window)
        # xx <- eval.parent(m)
        # xxtsp <- tsp(xx)
        # start <- xxtsp[1L]
        # end <- xxtsp[2L]
        # 
        # 
        # 
        # asd = remStream
        # asd = as.ts(asd);class(asd)
        # window(asd, start = cate$start[i], end = cate$end[i]) <- NA
        # 
        # ####################### END
        
        #aggiungi la finestra al vettore di resList corrispondente al livello di groupIndex
        win = window(stream, start = cate$start[i], end = cate$end[i])
        if(mergeEpochs)
          resList[[cate[[groupIndex]][i]]] = c(resList[[cate[[groupIndex]][i]]], c(padding,win))
        else{
          if(!is.null(padding)){ #se c'è da aggiungere il padding
            win = ts(c(padding,win2),start=start(padding),end = end(win2),frequency = frequency(stream)) 
          }
          resList[[cate[[groupIndex]][i]]] = c(resList[[cate[[groupIndex]][i]]], list(win))
          names(resList[[cate[[groupIndex]][i]]])[length(resList[[cate[[groupIndex]][i]]])] = paste0(dyadId(x),sessionId(x),"|",cate$start[i], "-",cate$end[i])
          }
      }
    }
  }
  if(mergeEpochs)
    resList[["remaining"]] = na.omit(as.numeric(remStream))
  else resList[["remaining"]] = list(remStream)
  
  #save object
  x[[signal]][[resName]] = resList 
  x
}



#### cambia epochStreamName in sync="PMBest", streamKey="sync", category="PACS/IM"
#' @title extract epochs in a simple list
#'  This function extracts the selected epochs from every session of a "DyadExperiment" object and puts them in
#'  a simple list.
#'  In future the 'by' argument will be used to split the data by experimental group, participant, or any other relevant condition.
#' @export
extractEpochs = function(experiment, signal="SC", epochStreamName="IM_PmdevSync", by, FUN = mean, ...){
  if(!missing("by")) stop("by is not implemented yet.")
  UseMethod("extractEpochs",experiment) 
}


#' @rdname extractEpochs
#' @export
catExtractLong = function(){stop("this function has been renamed to extractEpochs ")}

#' @export
extractEpochs.DyadExperiment = function(experiment, signal, epochStreamName, by, FUN, ...){
  #check names
  keepNames = unique(unlist(lapply (experiment, function(session){
    names(session[[signal]][[epochStreamName]])
  })))
  keepNames = sort(keepNames)
  #controlla se mergeEpochs era T o F
  mergeEpochs = !any(unlist(lapply (experiment, function(session){
    lapply(session[[signal]][[epochStreamName]],is.list)
  })))
  #instanzia una lista vuota con keepNames elementi
  res = vector("list", length(keepNames))
  names(res) = keepNames

  for(session in experiment){
    if(!is.null(session[[signal]][[epochStreamName]])){
      sesNames= names(session[[signal]][[epochStreamName]])
      for(sesName in sesNames){
        newElement = session[[signal]][[epochStreamName]][[sesName]]
        newElement = if(mergeEpochs  || is.list(newElement)) newElement else list(newElement)
        res[[sesName]] = c(res[[sesName]], newElement)
      }
    }
  }
  # boxplot(res)
  # 
  # unlist(lapply(res,FUN, ...))
  res
}

# questa funzione al momento è ibrida e incompleta.
# una prima parte serve ad estrarre delle finestre random dal remaining
# allo scopo di salvarle nel EXPERIMENT
# la seconda invece ripete la procedura 1000 volte allo scopo di fare un
# test di permutazione

# probabilmente ha senso tenere solo la seconda dal momento che la prima
# porta ad un database gigante. Eventualmente la prima si può astrarre con funzioni
# diverse dalla media.

#' Title 
#' Use either mimic or mean.duration and sd.duration
#'
#' @param mimic 
#' @param n if missing and mimic is used, the same number of the mimicked category is used
#' @param mean.duration 
#' @param sd.duration 
#' @param from 
#' @param experiment 
#' @param signal 
#' @param category 
#' @param sync 
#' @param streamKey 
# 
# randomEpochs = function(mimic, n, mean.duration, sd.duration, from="remaining", experiment, signal= "SC", category,  sync="PMBest", streamKey="sync"){
#   ##debug
#   mimic = "3"
#   n
#   mean.duration
#   sd.duration
#   from="remaining"
#   experiment = d3
#   signal= "SC"
#   sync="PMdev"
#   streamKey="sync"
#   category = "IM"
#   from="remaining"
#   #-----------------------
#   mimicMode = match.arg(mimicMode)
#   resName = paste0(c(toupper(category), "_", totitle(c(sync,streamKey))),collapse = "")
#   ex = catExtractLong(experiment, signal=signal, epochStream=resName)
#   ex2 = list(IM=do.call(c,ex[1:3]))
#   ex2$remaining = do.call(c,ex$remaining)
#   dur = lapply(ex, function(x)sapply(x,length))
#   
#   if(!from %in% names(ex)) stop ("from: ",from,"was not found in experiment")
#   
# 
#   if(!missing(mimic)) {
#     if(!missing(mean.duration) || !missing(sd.duration) ) stop ("specify either mimic or duration")
#     if(!mimic %in% names(ex)) stop ("mimic: ",mimic,"was not found in experiment")
#     if(missing(n)){
#       n = length(dur[[mimic]])
#       durList = dur[[mimic]]
#     } else { #se mimic, e 'n' è missing entra in strict mode
#       # e copia esattamente la durata delle finestre originali
#       mean.duration = mean(dur[[mimic]],na.rm=T)
#       sd.duration = sd(dur[[mimic]],na.rm=T)
#     }
#   }
#   if(!exists("durList")){ #a patto che non siamo in strict-mode
#     durList = c()
#     while(length(durList)<n) {
#       durList = c(durList, rnorm(n, mean.duration, sd.duration))
#       durList = durList[durList>0]
#       durList = sample(durList, min(length(durList),n), replace = F)
#     }
#     durList = round(durList)
#   }
#   ##ora seleziona le finestre
#   lfrom = do.call(c,ex[[from]]) #collassa tutti i remaining (o altro from) in un unica serie
#   newEpochs = list()
#   for(i in 1:n){
#     start = trunc(runif(1,1,length(lfrom)-max(durList)-1))
#     end = start + durList[i]
#     newEpochs[[i]] = lfrom[start:end]
#   }
#   boxplot(sapply(newEpochs,median),sapply(ex$`3`,median),ylim=c(0,1))
#   
#   #e se invece confrontassi la media reale con 1000 di quelle random?
#   n = length(ex2$IM)
#   dur2 = lapply(ex2, function(x)sapply(x,length))
#   durList = dur2$IM
#   lfrom = ex2$remaining
#   newEpochsMean = numeric(1000)
#   for(k in 1:1000){
#     newEpochs = list()
#     for(i in 1:n){
#       start = trunc(runif(1,1,length(lfrom)-max(durList)-1))
#       end = start + durList[i]
#       newEpochs[[i]] = lfrom[start:end]
#     }
#     newEpochsMean[k] = mean(sapply(newEpochs,median))
#   }
#   boxplot(newEpochsMean,sapply(ex2$IM,median),ylim=c(0,1))
#   length(newEpochsMean[newEpochsMean<mean(sapply(ex$`3`,median),na.rm=T)])
#   
#   
#   
# }

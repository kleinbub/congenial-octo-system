##     ___                 _   ___ _
##    /   \_   _  __ _  __| | / __\ | __ _ ___ ___
##   / /\ / | | |/ _` |/ _` |/ /  | |/ _` / __/ __|
##  / /_//| |_| | (_| | (_| / /___| | (_| \__ \__ \
## /___,'  \__, |\__,_|\__,_\____/|_|\__,_|___/___/
##         |___/
############################################################################################################  
## R class dyadSignal
# Main class definitions and libraries importer
#
############################################################################################################ 
## Changelog
# v3.0 rivoluzione! tolta separazione $signals $categ; tolto $ccf e implementate classi specifiche
#      per ogni tipo di analisi
# v2.0 integrato in rIP package
# v1.6 usa la nuova versione di CCF, non backward compatibile
# v1.4 a lot of goodies :3
# v1.3 attributes instead than lists. Not backward compatible
# v1.1 added "DyadStream" concept
# v1.0 stable
#
############################################################################################################ 
## ToDo *asap*
#
# -everything should become streams. and one should add as many streams as needed, es: many ccf with various settings.
# -every class should use attributes instead of lists, where appropriate
## Categorial Love
# -DyadCategory makes sense as a dataframe. but it needs adequate methods, for instance:
# -DyadCategory to stream (category, column) : crea versione interpolata. utile principalmente solo per plottare
# -byCat(signal, category, stream=c(patient, therapist, bestCCF, bestLag,lag0), FUN) : applica una funzione es la media ai diversi livelli
#       del factor di uno stream. a seconda che input sia experiment, session o singal applica adeguatamente.
# ----> queste cose sono parzialmente applicate in DyadCategory_BETA
#
#
#
# REMEMBER: ####
# -"end" and "start" are complex. And strictly interrelated with frequency.
# -Very important! Use start = 0, otherwise things get exotheric.
# -Eg: a <- ts(runif(147), start=0, frequency = f)
# -if f = 10: end(a) == c(14, 7) means "14.7" seconds [ != tsp(a)[2L] remember!]
# -if f =  5: end(a) == c(29, 2) means "29 times full 5 items, and only the first 2 elements of the 30th cycle" (29x5 + 2 = 147)
#   since each element is 1/5 of a cycle (0.2s) the total time is 29.4 seconds
# -The code forces start = c(0,1)
# start ed end ragionano come se fossero mesi. quindi start(a) == 0 1, significa il "primo mese dell'anno zero". L'idea è che la
# frequenza abbia un significato, es 1 mese, 1 osservazione, quindi end 29 2 significa la seconda osservazione del 29 ciclo.
# siccome il mio ciclo sono i secondi, usare come frequenza 10 o 100 rappresenta decimi e centesimi di secondo, che è sensato.
# 
# 
# 
############################################################################################################ 
## Credits
# Author: Johann R. Kleinbub
# Contact: johann.kleinbub@gmail.com
############################################################################################################ 
##Development notes regarding streams
# L'idea di base è che ogni segnale è uno stream. Questo già avviene per i dati grezzi, ma non ancora per i ccf
# o per i dati categoriali. la matrice con tutti i lag, andrebbe abbandonata, o quanto meno salvata a parte e 
# bestCCF e bestLAG salvati come stream. Gli stream infatti sono time-series con un sacco di metadati utili
# che rendono molto più semplice avere sempre tutte le info a portata di mano

## STRUTTURA v3
## DyadExperiment               | <- Experiment è semplicemente il contenitore di tutti i dati
##    $DyadSession              | <- la session è l'unità logica, contiene nomi partecipanti e id
##        $DyadSignal "SC"      | <- signal è il contenitore di tutti i dati e analisi di un tipo di segnale fisio
##            $DyadStream s1    | <- i diversi dati sono in forma di stream, ossia serie temporali con 
##            $DyadStream s2    |    più metadati, tra cui elementi grafici che forse sono da eliminare
##            $artefact         | <- un data.frame contenente le epoche (start end in secondi) da escludere
##            $CCFBest          | <- contenitore di analisi sincro basato sulle windowed x-cors
##              $sync           | <- il vecchio BestCCF
##              $lag            | <- il vecchio BestLag
##              $table          | <- la vecchia ccfMatrix
##            $PMBest           | <- contenitore di analisi sincro basato sul Peak Matching
##              $sync           |
##              $lag            |
##              $xBest          |
##        $DyadSignal "PPG"     |
##            $DyadStream s1    |
##            $DyadStream s2    |
##            $DyadStream ...   |
##        $DyadCategory "PACS"  | <- oltre ai segnali, una sessione contiene le categorie, che sono dataframe contenenti
##                              |    finestre temporali di interesse


### cose che deve contenere CCF:
##BestCCF PROCEDURE
# matrice di xCor di dimensioni nLag x nWin
# stream di bestCCF a BestLag
# stream di bestLag
# valori riassuntivi bestCCF
## PPSync procedure
# tabella xbest 
# stream di sync secondo ppBest
# stream di lag secondo ppBest
# valori riassuntivi ppSync
# valori di zSync per differenti metodi

## proposta 1
#  oggetto di classe DyadSync come contenitore generico di analisi di sincronizzazinoe
## -contiene "nome" o "tipo" es: ccf, best procedure, PP procedure,
## -ha dei metodi generalizzati per questa classe es toStream() che indipendentemente dal tipo
##  restituisce uno stream interpolato alla frequenza richiesta.
## -però è brutto generalizzare i metodi sull'attributo "nome"
## proposta 2
## - creare classi diverse e definire i metodi per le diverse classi
## -ccfMatrix, vectorBestLag, peakpicking best lag,

## ----------------------------------------------------------

#' Safe Object Attribute Lists
#' @description a wrapper for \code{\link[base]{attributes}} which accesses and sets an object's attributes
#' with the exception of protected ones, currently: \code{c("names", "comment", "dim", "dimnames", "row.names", "tsp")}
#' @param x an object
#' @param value an appropriate named list of attributes, or NULL.
#' @return asd
#' @examples 
#' a <- list("a"=1,"b"=2,"c"=3)
#' attr(a, "foo") <- "bar"
#' #extracts as well names
#' attributes(a) 
#' #extracts only foo
#' classAttr(a) 
#' #overwrites only foo
#' classAttr(a) <- list("bar"="foo") 
#' 
#' @export
#' 
classAttr = function(x){
  attributes(x)[!names(attributes(x)) %in% LOCK_ATTR]
}
#' @rdname classAttr
#' @export
`classAttr<-` = function(x,value){
  if(!is.list(value)||is.null(value)) stop("attributes must be a list or NULL")
  if(!is.null(attr(x,"tsp")))
    LOCK_ATTR = c(LOCK_ATTR,"tsp") #don't overwrite new tsp, but allow inheriting if missing
  value <- value[!names(value)%in%LOCK_ATTR]
  attributes(x) <- c(attributes(x)[LOCK_ATTR],value)
  x
}
LOCK_ATTR = c("names", "dim", "dimnames", "row.names")

#' c
#'
#' @param from 
#' @param to 
#'
#' @return
#' @export

cloneAttr = function(from, to){
  classAttr(to) <- classAttr(from)
  to
}


### DYADEXPERIMENT ###########################################
## list of DyadSessions with attributes:
##   -name
##   -class: list DyadExperiment
DyadExperiment = function(name, sessionList){
  exp =  sessionList
  attr(exp, "name") = name
  class(exp) = "DyadExperiment"
  return(exp)
}
#' @export
is.DyadExperiment = function(x) inherits(x,"DyadExperiment") && length(x)

# c.DyadExperiment sostituisce experimentMerge() e permette di unire
# i segnali di esperimenti con la stessa struttura di sessioni.
#' @export
c.DyadExperiment = function (...){
  l = list(...)
  
  #######################
   # l = list(mea,sc)
  if(length(l)==1) return(l[[1]])
  
  
  #c deve unire tra di loro i segnali che hanno lo stesso sessionId, Group, dyadID
  #invece deve incollare uno dopo l'altro le diadi che non overlappano
  #se per lo stesso ID ci sono due volte lo stesso segnale, stop.
  
  #1 check if any DyadSession must be merged
  comp=lapply(l,sapply,function(session){paste(groupId(session),dyadId(session),sessionId(session),sep="_")})
  comp = lapply(comp,tolower)
  comp2 = comp
  
  
  #sort by length
  lengths = sapply(l, length)
  nOrd = sort.list(lengths,decreasing = T)
  comp = comp[nOrd]
  l = l[nOrd]

  
  newEX = list()
  joined = 0
  compN = length(unlist(comp))
  theorUnique = length(unique(unlist(comp)))
  #######################

  for(x in 1:(length(l))){ #per ciascun esperimento (dal più lungo) 
    #aggiungi all'esperimento attuale (se non è l'ultimo) le sessioni uguali degli esperimenti successivi
    if(x<length(l)){
      for(y in (x+1):length(l)){ #per tutti gli esperimenti successivi
        #to compare
        a = l[[x]]
        b = l[[y]]
        warnS1 = F
        warnS2 = F
        toRemove = c()
        for(s in 1:length(a)){#per ciascuna sessione dell'esperimento x-esimo
          # print(s)
          toJoin = which(comp[[y]] == comp[[x]][s])
          if(length(toJoin) > 1) stop("experiment ", nOrd[[y]], " had more than one session of ",comp[[x]][s])
          if(length(toJoin) ==1){ #if there was a match
            # print(paste("match found in session",s,":", names(comp[[y]][toJoin])))
            if(any(names(a[[s]]) %in% names(b[[toJoin]]) )) stop ("experiments ",nOrd[[x]]," and ",nOrd[[y]], "had the same signal")
            if(!tolower(s1Name(a[[s]])) %in% tolower(s1Name(b[[toJoin]]))) warnF1 = T 
            if(!tolower(s2Name(a[[s]])) %in% tolower(s2Name(b[[toJoin]]))) warnF2 = T
            joined = joined +1
            l[[x]][[s]] = c(a[[s]],b[[toJoin]]) #aggiungi all'exp originale
            toRemove = c(toRemove,toJoin)
          } #else print("NO MATCH")
        }
        l[[y]][toRemove] = NULL
        # str(l[[y]],max=1)
        if(warnS1) warning("experiments ",nOrd[[x]]," and ",nOrd[[y]], "had different s1Names")
        if(warnS2) warning("experiments ",nOrd[[x]]," and ",nOrd[[y]], "had different s2Names")
      }
    }
    newEX = c(newEX,l[[x]]) #aggiungi all'esperimento finale le sessioni aggiornate rimaste nell'esperimento attuale
    message("adding to newEX the following:\r\n",paste(sapply(l[[x]], function(session){paste(groupId(session),dyadId(session),sessionId(session),sep="_")}),"\r\n" ))
    
  }
  
  if(sd( c(compN - joined, theorUnique,length(newEX) ) )  !=0) warning("the number of resulting DyadSession may be wrong. Check the result manually.")
  
  comp3 = c(comp2, list(sapply(newEX, function(session){paste(groupId(session),dyadId(session),sessionId(session),sep="_")})))
  comp3 = lapply(comp3, sort)
  res = do.call(unequalCbind,comp3)
  colnames(res) = c(paste("exp", seq(1,length(l))), "res")
  row.names(res) = NULL
  print(res)
  cat ("\r\nMerge successful.",joined,"session were joined. The final DyadExperiment consists of", length(newEX),"unique sessions.")
  
  DyadExperiment(sapply(l,name),newEX)
}

### DYADSESSION ##############################################
## list of signals and categ with attributes:
##   -name
##   -sessionId
##   -dyadId
##   -groupId
##   -s1Name
##   -s2Name
##   -fileName
##   -class: list DyadSession
DyadSession = function(groupId,sessionId,dyadId, signalList=NULL, s1Name,s2Name,fileName){
  if(length(unique(sapply(signalList, "s1Name")))>1)stop("multiple s1Names are not supported")
  if(length(unique(sapply(signalList, "s2Name")))>1)stop("multiple s2Names are not supported")
  
  x = signalList
  
  if(!is.null(signalList)) names(x) = lapply(x, name)
  attributes(x) = c(attributes(x),list(
    name = paste(groupId,lead0(sessionId),dyadId,sep="_"),
    sessionId = sessionId,
    dyadId = dyadId,
    groupId = groupId,
    s1Name = s1Name,
    s2Name = s2Name,
    fileName = fileName
  ))
  class(x) = "DyadSession"
  return(x)
}
#' @export
is.DyadSession = function(x) inherits(x,"DyadSession") && length(x)

#' @export
c.DyadSession = function(...){
  l = list(...);
  x = l[[1]]
  fileNames = sapply(l, attr, "fileName")
  #check on different filenames (bad)
  # if(length(unique(sapply(l,name))) >1 ) stop("Can't combine sessions with different names:\r\n",paste(unlist(sapply(l, attr, "fileName")),collapse="\r\n"), call.=F)
  #check on same signal names (bad)
  if(length(unique(sapply(l,names)))<length(sapply(l,names))) stop("Can't combine sessions containing the same signal. Use selectSignals() to extract only different signals before merging", call.=F)
  #check on different s1 s2 names (bad)
  if(any(na.omit(sapply(l,s1Name)) %in% na.omit(sapply(l,s2Name)))) stop("Can't combine sessions mixing s1 and s2 names", call.=F)
  
  structure(NextMethod("c"),
            "name" = name(x),
            "sessionId" = sessionId(x),
            "dyadId" = dyadId(x),
            "groupId" = groupId(x),
            "s1Name" = na.omit(sapply(l,s1Name))[1], #even if one of the signals ha NA sNames
            "s2Name" = na.omit(sapply(l,s2Name))[1], #the first full value gets selected
            "fileName" = fileNames,
            "class" ="DyadSession")
}


### DYADCATEGORY ###########################################
## data.frame with attributes:
##   -name
##   -class: list DyadCategory
DyadCategory = function(name, data){
  categ = data
  attributes(categ) = c(attributes(categ),list(name = name))
  class(categ) = append(class(categ),"DyadCategory")
  return(categ)
}
#' @export
is.DyadCategory = function(x) inherits(x,"DyadCategory") && length(x)

### DYADSIGNAL ###########################################
## list of DyadStreams, time, valid with attributes:
##   -sampRate
##   -filter 
##   -ccf 
##   -s1Name
##   -s2Name
##   -start
##   -end
##   -duration
##   -class: list DyadSession
DyadSignal = function(name="some signal",s1=NULL,s2=NULL,sampRate=NULL, s1Name, s2Name){
  x = list(
    s1 = DyadStream(stream = s1, name=s1Name, frequency = sampRate),
    s2 = DyadStream(stream = s2, name=s2Name, frequency = sampRate),
    artefacts = data.frame("start"=c(),"end"=c())
  )
  attributes(x) = c(attributes(x),list(
    name = name,
    sampRate = sampRate,
    filter = "raw",
    s1Name = s1Name,
    s2Name = s2Name,
    start = start(s1), #start-end-duration of s1 and s2 are the same by design
    end = end(s1)
  ))
  class(x) = append(class(x),"DyadSignal")
  return(x)
} 
#' @export
is.DyadSignal = function(x) inherits(x,"DyadSignal") && length(x)

#' Time Windows
#'
#' @param x 
#' @param duration an alternative specification to end
#' @param ... 
#'
#' @return
#' @export
#'
#' @examples
window.DyadSignal = function(x, duration, ...){
  if(missing(duration)) duration = NULL
  l = list(...)
  l = setArg("start",attr(x,"start"),l)
  if(!is.null(duration)){
    xend =  c(l[["start"]][1] + duration-1, frequency(x)) 
  } else xend = attr(x,"end")
  l = setArg("end",xend,l)
  #1. find all time series in x and nested objects (ts)
  #2. window them all
  #3. recreate meta-data
  tss = which(unlist(lapply(x,is.ts)))
  tss = c(tss,which(unlist(lapply(x,is.sync))))
  res = x
  for(i in tss){
    if(is.ts  (res[[i]])) res[[i]] = do.call("window",c(list(res[[i]]),l))
    if(is.sync(res[[i]])){
      tss2 = which(unlist(lapply(res[[i]],is.ts)))
      for(j in tss2){
        res[[i]][[j]] = do.call("window",c(list(res[[i]][[j]]),l))
      }
    }
  }
  
  classAttr(res) = classAttr(x)
  # attr(res,"duration") = length(res)/frequency(res)
  attr(res,"start") = start(res)
  attr(res,"end") = end(res)
  res
}


### DYADSTREAM ###########################################
## time-serie ts() with additional attributes:
##   -name
##   -settings 
##   -tsp (inherited by ts)
##   -class: list DyadSession
#' DyadStream
#' 
#' @param stream a ts object or numeric vector
#' @param name 
#' @param ... arguments passed to ts(), typicaly frequency and start. Only used if stream is NOT a ts object.
## Note to self: I know that presentation and content should be separated,
## yet storing some basic graphical information in the class, allows for consistency
## and simplicity in the upcoming plotting routines.
#' @export
DyadStream = function(stream, name, ...){
  if(!is.ts(stream)){
    stream = ts(stream, ...)
    l = list(...)
    if(!all(c("start","frequency")%in%names(l)) )
      message( paste0("Stream '",name,"' was coerced to ts starting at ",
                timeMaster(start(stream)[1],out = "hour"),", with sampRate of: ",
                frequency(stream),"Hz, and duration of: ",timeMaster(end(stream)[1],out = "hour"),
               ".\r\n"),
        call.=F)
  }
  attributes(stream) = c(attributes(stream),
                         list(
                            name = name,
                            duration = length(stream)/frequency(stream)
                            # col=col,
                            # lty=lty,
                            # lwd = lwd
                        ))
  class(stream) = append("DyadStream",class(stream))
  return(stream)
}
#' @export
is.DyadStream = function(x){ inherits(x,"DyadStream") && length(x)
}


#' @export
print.DyadStream = function (x, ...) {
  #x <- as.ts(x)
  Tsp <- tsp(x)
  if (is.null(Tsp)) {
    warning("series is corrupt, with no 'tsp' attribute")
    print(unclass(x), ...)
    return(invisible(x))
  }
  nn <- 1 + round((Tsp[2L] - Tsp[1L]) * Tsp[3L])
  if (NROW(x) != nn) {
    warning(gettextf("series is corrupt: length %d with 'tsp' implying %d", 
                     NROW(x), nn), domain = NA, call. = FALSE)
    calendar <- FALSE
  }
  fr.x <- frequency(x)
  if (fr.x != 1) 
    cat0("DyadStream '",attr(x,"name"),
         "':\nStart: ", tsp(x)[1], " [",deparse(start(x)),"]",
         "\nEnd: ",      tsp(x)[2], " [",deparse(end(x)),  "]",
         "\nFrequency: ", deparse(fr.x), 
         "\n")
  else cat0("DyadStream '",attr(x,"name"),"':\nStart: ", format(tsp(x)[1L]), 
            "\nEnd: ", format(tsp(x)[2L]), "\nFrequency: ", deparse(fr.x), 
            "\n")
  cat0("Duration: ",length(x), " samples, ",length(x)/frequency(x), " seconds\n\n")
  cat(x[1:100], sep = "\t")
  cat("\n...\n")
  cat(x[(length(x)-100):length(x)], sep = "\t") 
  
}

#' Time Windows
#'
#' @param x 
#' @param duration an alternative specification to end
#' @param ... 
#'
#' @return
#' @export
#'
#' @examples
window.DyadStream = function(x, duration, ...){
  if(missing(duration)) duration = NULL
  l = list(...)
  l$duration = duration
  xstart = if(is.null(l$start)) start(x) else l$start
  xend =  if(is.null(l$end)) end(x) else l$end
  if(!is.null(l[["duration"]]) && is.null(l[["end"]])){
    xend =  c(xstart[1] + duration-1, frequency(x)) 
  }
  res = NextMethod("window",x,start= xstart, end = xend)
  classAttr(res) = classAttr(x)
  attr(res,"duration") = length(res)/frequency(res)
  res
}


#' @export
as.ts.DyadStream = function(x){class(x) = class(x)[class(x)!="DyadStream"]; x} #this is needed to fix diff.ts() on dyadstreams

library(GSEABase)
library(doParallel)
library(foreach)
library(mlr)
library(edgeR)
library(limma)
library(DT) 
library(annotate)
library(XML)
library(e1071)
library(ROCR)


GSOA_ProcessFiles <- function(dataFilePath, classFilePath, gmtFilePath, outFilePath=NA, classificationAlgorithm="svm", numCrossValidationFolds=5, numRandomIterations=100, numCores=1, removePercentLowestExpr=10, removePercentLowestVar=10, applyVoomNormalization=FALSE)
{
  print("parse path names")
  # Input paths can be a vector and/or split by commas
  dataFilePathsSplit = NULL
  for (x in dataFilePath)
    dataFilePathsSplit = c(dataFilePathsSplit, strsplit(x, ",")[[1]])

  print("loop through files and expand wildcard")
  # Loop through the input files and expand wildcards
  dataFilePaths = NULL
  for (x in dataFilePathsSplit)
    dataFilePaths = c(dataFilePaths, list.files(dirname(x), pattern=glob2rx(basename(x)), full.names=TRUE))

  print("making sure there is at least one file")
  # Make sure we have at least one file
  if (is.null(dataFilePaths) || length(dataFilePaths) == 0) {
    message(paste("No files match the specified pattern for dataFilePath: ", dataFilePath))
    stop()
  }

  message("Read data from the file(s) into a list")
  dataList = list()
  for (x in dataFilePaths)
  {
    message(paste("Read data from ", x, ".", sep=""))
    dataList[[x]] = read.table(x, sep="\t", stringsAsFactors=F, header=T, row.names=NULL, check.names=F, quote="\"")
    rNames = dataList[[x]][,1]
    dataList[[x]] = as.matrix(dataList[[x]][,-1])
    rownames(dataList[[x]]) = rNames
  }

  message("Read class data")
  classData = as.matrix(read.table(classFilePath, sep="\t", stringsAsFactors=F, header=F, row.names=1, check.names=F, quote="\""))
  print(head(classData))
  message(paste("Read the gene-set data from ", gmtFilePath, sep=""))
  geneSetDatabase <- getGmt(gmtFilePath)

  # Call the core function
  print("calling GSOA function")
  results = GSOA(dataList, classData, geneSetDatabase, classificationAlgorithm=classificationAlgorithm, numCrossValidationFolds=numCrossValidationFolds, numRandomIterations=numRandomIterations, numCores=numCores, removePercentLowestExpr=removePercentLowestExpr, removePercentLowestVar=removePercentLowestVar, applyVoomNormalization=applyVoomNormalization)

  if (!is.na(outFilePath) & !is.null(results))
  {
    message(paste("Save results to ", outFilePath, sep=""))

    if (!dir.exists(dirname(outFilePath)))
      dir.create(dirname(outFilePath), recursive=TRUE)

    write.table(results, outFilePath, sep="\t", row.names=T, col.names=NA, quote=F)
  }

  return(results)
}

GSOA <- function(dataList, classData, geneSetDatabase, classificationAlgorithm="svm", numCrossValidationFolds=5, numRandomIterations=100, numCores=1, removePercentLowestExpr=10, removePercentLowestVar=10, applyVoomNormalization=FALSE)
{
  if (is.data.frame(dataList))
    dataList <- as.matrix(dataList)
    

  # Make sure the input data is in a list. If not, put it in one.
  if (!is.list(dataList))
    dataList = list(data=dataList)

  for (x in names(dataList))
  {
    zeroVarianceRows = which(apply(dataList[[x]], 1, var)==0)
    if (length(zeroVarianceRows) > 0)
      dataList[[x]] = dataList[[x]][-zeroVarianceRows,]

    rowMedian = apply(dataList[[x]], 1, median)
    rowVariance = apply(dataList[[x]], 1, var)
    rowsToExclude = NULL

    if (removePercentLowestExpr > 0)
    {
      message("Remove lowest-expressing genes")
      medianThreshold = quantile(rowMedian, probs=c(removePercentLowestExpr / 100))
      rowsToExclude = union(rowsToExclude, which(rowMedian<=medianThreshold))
    }

    if (removePercentLowestVar > 0)
    {
      message("Remove lowest-variance genes")
      varianceThreshold = quantile(rowMedian, probs=(removePercentLowestVar / 100))
      rowsToExclude = union(rowsToExclude, which(rowVariance <= varianceThreshold))
    }

    if (!is.null(rowsToExclude) & length(rowsToExclude > 0))
        dataList[[x]] = dataList[[x]][-rowsToExclude,]
  }

  # Set up parallel processing if needed
  if (numCores > 1)
    registerDoParallel(cores=numCores)

  message("Parse gene sets and check for overlap with data files")
  geneSetList <- lapply(geneSetDatabase, function(x) { list(geneSet=setName(x), genes=geneIds(x)) })

  geneSetList2 = list()
  allGeneSetGenes = NULL
  for (i in 1:length(geneSetList))
  {
    geneSetList2[[geneSetList[[i]]$geneSet]] = geneSetList[[i]]$genes
    allGeneSetGenes = unique(c(allGeneSetGenes, geneSetList[[i]]$genes))
  }

  message("Find the maximum number of genes across all gene sets")
  maxNumGenes = max(unlist(lapply(geneSetList2, length)))

  message("Identify samples that are common across all data sets and the class data")
  overlappingSamples = rownames(classData)
  for (x in names(dataList))
    overlappingSamples = sort(unique(intersect(overlappingSamples, colnames(dataList[[x]]))))

  allDataGenes = NULL
  for (x in names(dataList))
  {
    # Filter out any genes that have at least one missing value across the samples.
    dataList[[x]] = dataList[[x]][which(apply(dataList[[x]], 1, function(x) { sum(is.na(x)) }) == 0),,drop=FALSE]

    # Transpose the data and convert it to a matrix
    dataList[[x]] = t(as.matrix(dataList[[x]][,overlappingSamples,drop=FALSE]))

    # Extract gene names
    allDataGenes = c(allDataGenes, colnames(dataList[[x]]))
  }

  overlappingGenes = intersect(allGeneSetGenes, unique(allDataGenes))

  # Filter the gene sets to include only overlapping genes
  for (geneSet in names(geneSetDatabase))
    geneSetList2[[geneSet]] = intersect(geneSetList2[[geneSet]], overlappingGenes)

  # Filter the data to include only overlapping genes
  for (x in names(dataList))
    dataList[[x]] = dataList[[x]][,intersect(colnames(dataList[[x]]), overlappingGenes)]

  # Filter the classes to only include the samples we care about
  classes = as.factor(classData[overlappingSamples,])

  # Perform various validation checks

  if (length(overlappingSamples) == 0)
  {
    message("No samples overlapped between the input data file(s) and the class file.")
    stop()
  }

  if (any(table(overlappingSamples) > 1))
  {
    message("This tool does not support duplicate samples.")
    stop()
  }

  if (length(overlappingSamples) < (numCrossValidationFolds * length(levels(classes))))
  {
    message(paste("Only ", length(overlappingSamples), " overlap between your data file and your classes file.", sep=""))
    message("Unfortunately, this tool is not designed to support a data set with so few samples.")
    stop()
  }

#  if (length(levels(classes)) > 2)
#  {
#    message("Currently, this tool supports only two classes.")
#    stop()
#  }

  if (applyVoomNormalization)
  {
    for (x in names(dataList))
    {
      dge <- DGEList(counts=t(dataList[[x]]))
      dge <- calcNormFactors(dge)

      classNames <- unique(classData[,1])
      classDesign <- matrix(nrow=nrow(classData), ncol=length(classNames))
      rownames(classDesign) <- rownames(classData)
      colnames(classDesign) <- classNames

      for (i in 1:length(classNames))
        classDesign[,i] <- as.integer(classData[,1]==classNames[i])

      #dataList[[x]] <- t(voom(dge, classDesign, plot=FALSE)$E)
      dataList[[x]] <- t(voom(t(dataList[[x]]), classDesign, plot=FALSE, normalize.method="quantile")$E)
    }
  }

  # Obtain (non-random) results
  mainResults = processGeneSetList(dataList, classes, geneSetList2, classificationAlgorithm=classificationAlgorithm, numCrossValidationFolds=numCrossValidationFolds, numCores=numCores)

  if (is.null(mainResults))
  {
    message(paste("There are no results."))
    stop()
  }

  # Obtain random results
  randomResults = getRandomResults(dataList, classes, geneSetList2, overlappingGenes, classificationAlgorithm=classificationAlgorithm, numCrossValidationFolds=numCrossValidationFolds, numRandomIterations=numRandomIterations, numCores=numCores)

  # Calculate empirical p-values (and correct for gene set size)
  empiricalPValues = NULL
  for (i in 1:nrow(mainResults))
  {
    actualAUC = mainResults[i,1]
    geneSet = rownames(mainResults)[i]
    numGenes = length(geneSetList2[[geneSet]])

    # Determine how many genes are in the random gene set assigned to the actual gene set
    bin = getBin(numGenes, randomResults$bins, maxNumGenes)

    # Get the random AUC values that have been calculated
    randomAUC = randomResults$AUC[,as.character(bin)]

    numRandomValues = nrow(randomResults$AUC)
    # Calculate p-value as proportion of random AUC greater than actual
    numRandomGreaterThanActual = sum(randomAUC >= actualAUC) + 1

    # Make sure max p-value is 1
    empiricalPValue = numRandomGreaterThanActual / numRandomValues
    if (empiricalPValue > 1)
      empiricalPValue = 1

    empiricalPValues = c(empiricalPValues, empiricalPValue)
  }

  # Calculate FDR values using Benjamini-Hochberg method
  fdrValues = p.adjust(as.numeric(empiricalPValues), method = "BH", n=length(empiricalPValues))

  # Construct final matrix
  mainResults = cbind(mainResults, empiricalPValues, fdrValues)
  mainResults = as.data.frame(mainResults)

  mainResults = mainResults[order(empiricalPValues),]
  colnames(mainResults) = c("AUC", "p.value", "FDR")

  mainResults = cbind(mainResults, rank(as.numeric(mainResults$p.value), ties.method="min"))
  colnames(mainResults)[ncol(mainResults)] = "Rank"

  return(mainResults)
}


#dataList, classes, geneSetList2, classificationAlgorithm=classificationAlgorithm, numCrossValidationFolds=numCrossValidationFolds, numCores=numCores)
processGeneSetList <- function(dataList, classes, geneSetList, classificationAlgorithm, numCrossValidationFolds, numCores)
{
  if (numCores > 1) {
    # Process each gene set in parallel
    results <- foreach(geneSet=names(geneSetList), .combine=c) %dopar% {
      processGeneSet(geneSet, dataList, classes, geneSetList, classificationAlgorithm, numCrossValidationFolds)
    }
  } else {
    #  This code can be used to execute in serial mode
    results <- NULL
    for (geneSet in names(geneSetList))
      results = c(results, processGeneSet(geneSet, dataList, classes, geneSetList, classificationAlgorithm, numCrossValidationFolds))
      #results = c(results, processGeneSet(names(geneSetList2)[3], dataList, classes, geneSetList, classificationAlgorithm, numCrossValidationFolds))

    
    }

  # Convert the results to a matrix
  if (!is.null(results) & length(results) > 0)
    results = as.matrix(results)

  return(results)
}

#geneSet = names(geneSetList2)[3]
processGeneSet <- function(geneSet, dataList, classes, geneSetList, classificationAlgorithm, numCrossValidationFolds)
{
  message(paste("Making predictions for gene set: ", geneSet, ".", sep=""))

  # Select data according to the genes in that gene set
  geneSetDataList = list()
  for (x in names(dataList))
  {
    genes = intersect(geneSetList[[geneSet]], colnames(dataList[[x]]))

    if (length(genes) < 1)
    {
      message(paste("No genes in ", x, " overlap with gene set ", geneSet, ".", sep=""))
      next
    }

    # Select values that overlap with any gene in the gene list
    geneSetDataList[[x]] = as.data.frame(dataList[[x]][,which(colnames(dataList[[x]]) %in% genes),drop=FALSE])
  }

   if (length(geneSetDataList) == 0)
  {
    message("No data are available for processing.")
    return(NULL)
  }

  # Merge multiple data sets into one, if necessary
  if (length(geneSetDataList) == 1) {
    geneSetData = geneSetDataList[[1]]
  } else {
    geneSetData = NULL

    for (x in names(geneSetDataList))
    {
      # Prefix gene names from each data set so we don't see collisions
      colnames(geneSetDataList[[x]]) = paste(x, colnames(geneSetDataList[[x]]), sep="__")

      if (is.null(geneSetData)) {
        geneSetData = geneSetDataList[[x]]
      } else {
        geneSetData = cbind(geneSetData, geneSetDataList[[x]])
      }
    }
  }

  colnames(geneSetData) = reformatGeneNames(colnames(geneSetData))

  geneSetData = cbind(geneSetData, classes)

  # Configure the machine-learning classification task
  classif.task = makeClassifTask(id = geneSet, data = geneSetData, target = "classes", positive=levels(classes)[2]) 

  # Center and scale the values for consistency across variables
  classif.task = normalizeFeatures(classif.task, method="standardize")

  # Configure the learner object
  classif.lrn = makeLearner(paste("classif.", classificationAlgorithm, sep=""), predict.type = "prob", fix.factors.prediction = TRUE)

  if (min(table(classes)) < numCrossValidationFolds)
  {
    message("Defaulting to leave-one-out cross validation because the class with the minimum number of samples was less than the number of folds.")
    numCrossValidationFolds = 1
  }

  # Use leave-one-out cross validation if we have a small number of samples
  if (numCrossValidationFolds <= 1) {
    rdesc = makeResampleDesc("LOO")
  } else {
    rdesc = makeResampleDesc("CV", iters=numCrossValidationFolds, stratify=TRUE)
  }
  
  # Perform cross validation
  set.seed(0)
  rsamp = resample(classif.lrn, task=classif.task, rdesc, measures = list(auc, ppv), show.info=FALSE)

  # Get AUC value
  auc = rsamp$aggr[1]
  names(auc) = geneSet

  return(auc)
}

getRandomResults <- function(dataList, classes, geneSetList, overlappingGenes, classificationAlgorithm, numCrossValidationFolds, numRandomIterations, numCores)
{
  # Determine which bins should be used, based on the sizes of the gene sets
  randomBins = findNumGeneBins(geneSetList)

  # Calculate AUC values for each bin
  randomAUC = NULL
  for (randomBin in randomBins)
  {
    # Create the random gene set list
    randomGeneSetList = list()
    for (randomIteration in 1:numRandomIterations)
    {
      set.seed(randomIteration)
      randomGeneSetName = paste("RandomGeneSet", randomIteration, sep="")

      # Randomly select genes from all available
      randomGeneSetList[[randomGeneSetName]] = sample(overlappingGenes, randomBin)
    }

    randomResult = processGeneSetList(dataList, classes, randomGeneSetList, classificationAlgorithm=classificationAlgorithm, numCrossValidationFolds=numCrossValidationFolds, numCores=numCores)
    randomAUC = cbind(randomAUC, randomResult)
  }

  colnames(randomAUC) = randomBins
  return(list(AUC=randomAUC, bins=randomBins))
}

findNumGeneBins = function(geneSetList)
{
  # Get all unique gene set sizes
  geneSetLengths = NULL
  for (geneSet in names(geneSetList))
    geneSetLengths = c(geneSetLengths, length(geneSetList[[geneSet]]))
  geneSetLengths = sort(unique(geneSetLengths))

  binOptions = c(0, 1, 5, 10, 25, 50, 75, 100, 125, 150, 200, 250, 300, 400, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 1000000)

  # Pick the bin that matches closest to each gene set's size
  bins = NULL
  for (i in 2:length(binOptions))
    if (sum((geneSetLengths > binOptions[i-1]) * (geneSetLengths <= binOptions[i])) > 0)
      bins = c(bins, binOptions[i])

  # If any gene set is associated with the largest (dummy) bin, set it to the size of the actual gene set
  if (binOptions[length(binOptions)] %in% bins)
    bins[length(binOptions)] = max(geneSetLengths)

  return(bins)
}

getBin = function(numGenes, bins, maxNumGenes)
{
  if (numGenes %in% bins)
    return(numGenes)

  binOptions = c(0, 1, 5, 10, 25, 50, 75, 100, 125, 150, 200, 250, 300, 400, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 1000000)

  # Find the bin that matches this gene set's size
  for (i in 2:length(binOptions))
    if (numGenes > binOptions[i-1] & numGenes <= binOptions[i])
    {
      if (i == (length(binOptions) - 1))
        return(maxNumGenes)
      return(binOptions[i])
    }
}

reformatGeneNames <- function(x)
{
  x <- gsub("\\\\", "backsl", toupper(x))
  x <- gsub("\\-", "hyphen", toupper(x))
  x <- gsub("\\.", "dot", x)
  x <- gsub("\\/", "slash", x)
  x <- gsub("\\@", "atsign", x)
  #x <- gsub("^\\d", "X", x)
  x <- paste("X", x, sep="")

  return(x)
}

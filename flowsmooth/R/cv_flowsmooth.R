# Generated from _main.Rmd: do not edit by hand

#' Cross-validation for flowsmooth(). Saves results to separate files in
#' \code{destin}.
#'
#' @param destin Directory where output files are saved.
#' @param nfold Number of cross-validation folds. Defaults to 5.
#' @param nrestart Number of repetitions.
#' @param save_meta If TRUE, save meta data.
#' @param lambda_means Regularization parameters for means.
#' @param lambda_probs Regularization parameters for probs.
#' @param folds Manually provide CV folds (list of time points of data to use
#'   as CV folds). Defaults to NULL.
#' @param mc.cores Use this many CPU cores.
#' @param blocksize Contiguous time blocks from which to form CV time folds.
#' @param refit If TRUE, estimate the model on the full data, for each pair of
#'   regularization parameters.
#' @param ... Additional arguments to flowsmooth().
#' @inheritParams flowsmooth_once
#'
#' @return No return.
#'
#' @export
cv_flowsmooth <- function(## Data
                          ylist,
                          countslist,
                          ## Define the locations to save the CV.
                          destin = ".",
                          ## Regularization parameter values
                          lambda_means,
                          lambda_probs,
                          l,
                          l_prob,
                          iimat = NULL,
                          ## Other settings
                          maxdev,
                          numclust,
                          nfold,
                          nrestart,
                          verbose = FALSE,
                          refit = FALSE,
                          save_meta = FALSE,
                          mc.cores = 1,
                          folds = NULL,
                          seedtab = NULL,
                          ...){

  ## Basic checks
  stopifnot(length(lambda_probs) == length(lambda_means))
  cv_gridsize = length(lambda_means)

  ## There's an option to input one's own iimat matrix.
  if(is.null(iimat)){
    ## Make an index of all jobs
    if(!refit) iimat = make_iimat(cv_gridsize, nfold, nrestart)
    if(refit) iimat = make_iimat_small(cv_gridsize, nrestart)
  }

  ## Define the CV folds
  ## folds = make_cv_folds(ylist = ylist, nfold = nfold, blocksize = 1)
  if(is.null(folds)){
    folds = make_cv_folds(ylist = ylist, nfold = nfold)
  } else {
    stopifnot(length(folds) == nfold)
  }

  ## Save meta information, once.
  if(save_meta){
    if(!refit){
      save(folds,
           nfold,
           nrestart, ## Added recently
           cv_gridsize,
           lambda_means,
           lambda_probs,
           ylist, countslist,
           ## Save the file
           file = file.path(destin, 'meta.Rdata'))
      print(paste0("wrote meta data to ", file.path(destin, 'meta.Rdata')))
    }
  }

  ## Run the EM algorithm many times, for each value of (iprob, imu, ifold, irestart)
  start.time = Sys.time()
  parallel::mclapply(1:nrow(iimat), function(ii){
    print_progress(ii, nrow(iimat), "Jobs (EM replicates) assigned on this computer", start.time = start.time)

    if(!refit){
      iprob = iimat[ii,"iprob"]
      imu = iimat[ii,"imu"]
      ifold = iimat[ii,"ifold"]
      irestart = iimat[ii,"irestart"]
      ## if(verbose) cat('(iprob, imu, ifold, irestart)=', c(iprob, imu, ifold, irestart), fill=TRUE)
    } else {
      iprob = iimat[ii, "iprob"]
      imu = iimat[ii, "imu"]
      ifold = 0
    }

    if(!refit){
      one_job(iprob = iprob,
              imu = imu,
              l = l,
              l_prob = l_prob,
              ifold = ifold,
              irestart = irestart,
              folds = folds,
              destin = destin,
              lambda_means = lambda_means,
              lambda_probs = lambda_probs,
              ## Arguments for flowsmooth()
              ylist = ylist, countslist = countslist, 
              ## Additional arguments for flowsmooth().
              numclust = numclust,
              maxdev = maxdev,
              verbose = FALSE,
              seedtab = seedtab)
    } else {
      one_job_refit(iprob = iprob,
                    imu = imu,
                    l = l,
                    l_prob = l_prob,
                    destin = destin,
                    lambda_means = lambda_means,
                    lambda_probs = lambda_probs,
                    ## Arguments to flowsmooth()
                    ylist = ylist, countslist = countslist, 
                    ## Additional arguments for flowsmooth().
                    numclust = numclust,
                    maxdev = maxdev,
                    nrestart = nrestart,
                    verbose = FALSE,
                    seedtab = seedtab)
    }
    return(NULL)
  }, mc.cores = mc.cores)
}

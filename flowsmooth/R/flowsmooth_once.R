# Generated from _main.Rmd: do not edit by hand

#' Estimate flowsmooth model once.
#'
#' @param ylist Data.
#' @param countslist Counts corresponding to multiplicities.
#' @param x Times, if points are not evenly spaced. Defaults to NULL, in which
#'   case the value becomes \code{1:T}, for the $T==length(ylist)$.
#' @param numclust Number of clusters.
#' @param niter Maximum number of EM iterations.
#' @param l Degree of differencing for the mean trend filtering
#' @param l_prob Degree of differencing for the probability trend filtering
#' @param mn Initial value for cluster means. Defaults to NULL, in which case
#'   initial values are randomly chosen from the data.
#' @param lambda Smoothing parameter for means
#' @param lambda_prob Smoothing parameter for probabilities
#' @param verbose Loud or not? EM iteration progress is printed.
#' @param tol_em Relative numerical improvement of the objective value at which
#'   to stop the EM algorithm
#' @param maxdev Maximum deviation of cluster means across time..
#' @param countslist_overwrite
#' @param admm_err_rel
#' @param admm_err_abs
#' @param admm_local_adapt
#' @param admm_local_adapt_niter
#'
#' @return List object with flowsmooth model estimates.
#' @export
#'
#' @examples
flowsmooth_once <- function(ylist,
                       countslist = NULL,
                       x = NULL,
                       numclust, niter = 1000, l, l_prob = NULL,
                       mn = NULL, lambda = 0, lambda_prob = NULL, verbose = FALSE,
                       tol_em = 1E-4,
                       maxdev = NULL,
                       countslist_overwrite = NULL,
                       ## beta Mstep (ADMM) settings
                       admm = TRUE,
                       admm_err_rel = 1E-3,
                       admm_err_abs = 1E-4,
                       ## Mean M step (Locally Adaptive ADMM) settings
                       admm_local_adapt = FALSE,
                       admm_local_adapt_niter = if(admm_local_adapt) 10 else 1){

  ## Basic checks
  if(!is.null(maxdev)){
    assertthat::assert_that(maxdev!=0)
  } else {
    maxdev = 1E10
  }
  assertthat::assert_that(numclust > 1)
  assertthat::assert_that(niter > 1)
  if(is.null(countslist)){
    ntlist = sapply(ylist, nrow)
    countslist = lapply(ntlist, FUN = function(nt) rep(1, nt))
  }

  ## Setup for EM algorithm
  TT = length(ylist)
  dimdat = ncol(ylist[[1]])
  if(is.null(x)) x <- 1:TT
  Dl = gen_diff_mat(n = TT, l = l+1, x = x)
  Dlm1 = gen_diff_mat(n = TT, l = l, x = x)
  Dlm1sqrd <- t(Dlm1) %*% Dlm1
  e_mat <- etilde_mat(TT = TT) # needed to generate B
  Dl_prob = gen_diff_mat(n = TT, l = l_prob+1, x = x)
  H_tf <- gen_tf_mat(n = length(countslist), k = l_prob, x = x)
  if(is.null(mn)) mn = init_mn(ylist, numclust, TT, dimdat, countslist = countslist)
  ntlist = sapply(ylist, nrow)
  N = sum(ntlist)

  ## Initialize some objects
  prob = matrix(1/numclust, nrow = TT, ncol = numclust) ## Initialize to all 1/K.
  denslist_by_clust <- NULL
  objectives = c(+1E20, rep(NA, niter-1))
  sigma_fac <- diff(range(do.call(rbind, ylist)))/8
  sigma = init_sigma(ylist, numclust, sigma_fac) ## (T x numclust x (dimdat x dimdat))
  sigma_eig_by_clust = NULL
  zero.betas = zero.alphas = list()

  ## The least elegant solution I can think of.. used only for blocked cv
  if(!is.null(countslist_overwrite)) countslist = countslist_overwrite
  #if(!is.null(countslist)) check_trim(ylist, countslist)

  vals <- vector(length = niter)
  start.time = Sys.time()
  for(iter in 2:niter){
    if(verbose){
      print_progress(iter-1, niter-1, "EM iterations.", start.time = start.time)
    }
    resp <- Estep(mn, sigma, prob, ylist = ylist, numclust = numclust,
                  denslist_by_clust = denslist_by_clust,
                  first_iter = (iter == 2), countslist = countslist)

    ## M step (three parts)

    ## 1. Means
    res.mu = Mstep_mu(resp, ylist,
                      lambda = lambda,
                      first_iter = (iter == 2),
                      l = l, Dl = Dl, Dlm1 = Dlm1,
                      Dlm1sqrd = Dlm1sqrd,
                      sigma_eig_by_clust = sigma_eig_by_clust,
                      sigma = sigma, maxdev = maxdev,
                      e_mat = e_mat,
                      Zs = NULL,
                      Ws = NULL,
                      uws = NULL,
                      uzs =  NULL,
                      x = x,
                      err_rel = admm_err_rel,
                      err_abs = admm_err_abs,
                      local_adapt = admm_local_adapt,
                      local_adapt_niter = admm_local_adapt_niter)
    mn = res.mu$mns

    ## 2. Sigma
    sigma = Mstep_sigma(resp, ylist, mn, numclust)
    # sigma_eig_by_clust <- eigendecomp_sigma_array(sigma)
    # denslist_by_clust <- make_denslist_eigen(ylist, mn, TT, dimdat, numclust,
    #                                          sigma_eig_by_clust,
    #                                          countslist)

    ## 3. Probabilities
    prob_link = Mstep_prob(resp, countslist = countslist, H_tf = H_tf,
                           lambda_prob = lambda_prob, l_prob = l_prob, x = x)
    prob = softmax(prob_link)

    objectives[iter] = objective(ylist = ylist, mu = mn, sigma = sigma, prob = prob, prob_link = prob_link,
                                 lambda = lambda, Dl = Dl, l = l, countslist = countslist,
                                 Dl_prob = Dl_prob,
                                 l_prob = l_prob,
                                 lambda_prob = lambda_prob)

    ## Check convergence
    if(check_converge_rel(objectives[iter-1], objectives[iter], tol = tol_em)) break
  }

  return(structure(list(mn = mn,
                        prob = prob,
                        sigma = sigma,
                        objectives = objectives[2:iter],
                        final.iter = iter,
                        resp = resp,
                        ## Above is output, below are data/algorithm settings.
                        dimdat = dimdat,
                        TT = TT,
                        N = N,
                        l = l,
                        x = x,
                        numclust = numclust,
                        lambda = lambda,
                        maxdev = maxdev,
                        niter = niter
  ), class = "flowsmooth"))
}

#' @title Get model formula
#' @name find_formula
#'
#' @description Get model formula
#'
#' @inheritParams find_predictors
#'
#' @return A formula that describes the model, or a list of formulas (e.g., for
#'    multivariate response models, or models with zero-inflation component).
#'
#' @examples
#' data(mtcars)
#' m <- lm(mpg ~ wt + cyl + vs, data = mtcars)
#' find_formula(m)
#'
#' @importFrom stats formula terms
#' @export
find_formula <- function(x, ...) {
  UseMethod("find_formula")
}


#' @export
find_formula.default <- function(x, ...) {
  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  tryCatch(
    {stats::formula(x)},
    error = function(x) { NULL }
  )
}


#' @export
find_formula.clm2 <- function(x, ...) {
  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  attr(x$location, "terms", exact = TRUE)
}


#' @rdname find_formula
#' @export
find_formula.glmmTMB <- function(x, component = c("all", "cond", "zi", "disp"), ...) {
  component <- match.arg(component)

  f.cond <- stats::formula(x)
  f.zi <- stats::formula(x, component = "zi")
  f.disp <- stats::formula(x, component = "disp")

  switch(
    component,
    all = compact_list(list(cond = f.cond, zi = f.zi, disp = f.disp)),
    cond = f.cond,
    zi = f.zi,
    disp = f.disp
  )
}


#' @export
find_formula.brmsfit <- function(x, ...) {
  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  ## TODO check for ZI and multivariate response models
  stats::formula(x)
}


#' @export
find_formula.MCMCglmm <- function(x, effects = c("all", "fixed", "random"), ...) {
  effects <- match.arg(effects)

  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  fm <- x$Fixed
  fmr <- x$Random

  switch(
    effects,
    fixed = fm,
    random = fmr,
    compact_list(list(fixed = fm, random = fmr))
  )
}


#' @export
find_formula.lme <- function(x, effects = c("all", "fixed", "random"), ...) {
  effects <- match.arg(effects)

  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  fm <- eval(x$call$fixed)
  fmr <- eval(x$call$random)

  switch(
    effects,
    fixed = fm,
    random = fmr,
    compact_list(list(fixed = fm, random = fmr))
  )
}


#' @rdname find_formula
#' @export
find_formula.MixMod <- function(x, effects = c("all", "fixed", "random"), component = c("all", "cond", "zi", "disp"), ...) {
  effects <- match.arg(effects)

  f.cond <- stats::formula(x)
  f.zi <- stats::formula(x, type = "zi_fixed")
  f.random <- stats::formula(x, type = "random")
  f.zirandom <- stats::formula(x, type = "zi_random")

  if (effects == "fixed") {
    f.random <- NULL
    f.zirandom <- NULL
  } else if (effects == "fixed") {
    f.cond <- NULL
    f.zi <- NULL
  }

  switch(
    component,
    all = compact_list(list(cond = f.cond, zi = f.zi, random = f.random, zi.random = f.zirandom)),
    cond = compact_list(list(cond = f.cond, random = f.random)),
    zi = compact_list(list(zi = f.zi, zi.random = f.zirandom))
  )
}


#' @export
find_formula.stanmvreg <- function(x, effects = c("all", "fixed", "random"), ...) {
  # make sure we have no invalid component request
  dots <- list(...)
  if (obj_has_name(dots, "component")) {
    if (dots$component %in% c("zi", "disp"))
      return(NULL)
  }

  ## TODO check for ZI and multivariate response models
  stats::formula(x)
}
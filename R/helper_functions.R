# remove trailing/leading spaces from character vectors
.trim <- function(x) gsub("^\\s+|\\s+$", "", x)



# remove NULL elements from lists
.compact_list <- function(x) x[!sapply(x, function(i) length(i) == 0 || is.null(i) || (!is.data.frame(i) && any(i == "NULL")) || (is.data.frame(i) && nrow(i) == 0))]



# remove empty string from character
.compact_character <- function(x) x[!sapply(x, function(i) nchar(i) == 0 || is.null(i) || any(i == "NULL"))]



# remove values from vector
.remove_values <- function(x, values) {
  remove <- x %in% values
  if (any(remove)) {
    x <- x[!remove]
  }
  x
}


# rename values in a vector
.rename_values <- function(x, old, new) {
  x[x %in% old] <- new
  x
}



# is string empty?
.is_empty_string <- function(x) {
  x <- x[!is.na(x)]
  length(x) == 0 || all(nchar(x) == 0)
}


# is string empty?
.is_empty_object <- function(x) {
  if (is.list(x)) {
    x <- tryCatch(
      {
        .compact_list(x)
      },
      error = function(x) {
        x
      }
    )
  }
  # this is an ugly fix because of ugly tibbles
  if (inherits(x, c("tbl_df", "tbl"))) x <- as.data.frame(x)
  x <- suppressWarnings(x[!is.na(x)])
  length(x) == 0 || is.null(x)
}



# does string contain pattern?
.string_contains <- function(pattern, x) {
  pattern <- paste0("\\Q", pattern, "\\E")
  grepl(pattern, x, perl = TRUE)
}



# has object an element with given name?
.obj_has_name <- function(x, name) {
  name %in% names(x)
}


# checks if a brms-models is a multi-membership-model
.is_multi_membership <- function(x) {
  if (inherits(x, "brmsfit")) {
    re <- find_random(x, split_nested = TRUE, flatten = TRUE)
    any(grepl("^(mmc|mm)\\(", re))
  } else {
    return(FALSE)
  }
}


# merge data frames, remove double columns
.merge_dataframes <- function(data, ..., replace = TRUE) {
  # check for identical column names
  tmp <- cbind(...)

  if (nrow(data) == 0) {
    return(tmp)
  }

  doubles <- colnames(tmp) %in% colnames(data)

  # keep order?
  reihenfolge <- c(which(!doubles), which(doubles))

  # remove duplicate column names, if requested
  if (replace && any(doubles)) tmp <- tmp[, !doubles, drop = FALSE]

  # bind all data
  x <- cbind(tmp, data)

  # restore order
  if (replace) {
    # check for correct length. if "data" had duplicated variables,
    # but not all variable are duplicates, add indices of regular values
    if (ncol(x) > length(reihenfolge)) {
      # get remaining indices
      xl <- seq_len(ncol(x))[-seq_len(length(reihenfolge))]
      # add to "reihefolge"
      reihenfolge <- c(reihenfolge, xl)
    }
    # sort data frame
    x <- x[, order(reihenfolge), drop = FALSE]
  }

  x
}


# removes random effects from a formula that is in lmer-notation
#' @importFrom stats terms drop.terms update
.get_fixed_effects <- function(f) {
  f_string <- .safe_deparse(f)

  # for some weird brms-models, we also have a "|" in the response.
  # in order to check for "|" only in the random effects, we have
  # to remove the response here...

  f_response <- .safe_deparse(f[[2]])
  f_predictors <- sub(f_response, "", f_string, fixed = TRUE)

  if (grepl("|", f_predictors, fixed = TRUE)) {
    if (length(f) > 2) {
      f_cond <- .safe_deparse(f[[3]])
    } else {
      f_cond <- .safe_deparse(f[[length(f)]])
    }
    # get first parentheses. for mixed models, might not be the random effects
    # e.g.: (country + cohort + country * cohort) + age + (1 + age_c | mergeid)
    first_parentheses <- gsub("^\\((.*?)\\)(.*)", "\\1", f_cond)
    has_bar <- grepl("\\|", first_parentheses)
    starts_with_parantheses <- grepl("^\\(", f_cond)
    # intercept only model, w/o "1" in formula notation?
    # e.g. "Reaction ~ (1 + Days | Subject)"
    if (length(f) > 2 && starts_with_parantheses && has_bar) {
      # check if we have any terms *after* random effects, e.g.
      # social ~ (1|school) + open + extro + agree + school
      if (.formula_empty_after_random_effect(f_predictors)) {
        # here we fix intercept only models with random effects,
        # like social ~ (1|school).
        .trim(paste0(.safe_deparse(f[[2]]), " ~ 1"))
      } else {
        # here we fix models where random effects come first,
        # like social ~ (1|school) + open + extro + agree + school
        # the regex removes "(1|school) + "
        .trim(gsub("\\((.*)\\)(\\s)*\\+(\\s)*", "", f_string))
      }
    } else if (!grepl("\\+(\\s)*\\((.*)\\)", f_string)) {
      f_terms <- stats::terms(f)
      pos_bar <- grep("|", labels(f_terms), fixed = TRUE)
      no_bars <- stats::drop.terms(f_terms, pos_bar, keep.response = TRUE)
      stats::update(f_terms, no_bars)
    } else {
      .trim(gsub("\\+(\\s)*\\((.*)\\)", "", f_string))
    }
  } else {
    .trim(gsub("\\+(\\s)*\\((.*)\\)", "", f_string))
  }
}


# check if any terms appear in the formula after random effects
# like "~ (1|school) + open + extro + agree + school"
# this regex removes "(1|school)", as well as any +, -, *, whitespace etc.
# if there are any chars left, these come from further terms that come after
# random effects...
.formula_empty_after_random_effect <- function(f) {
  nchar(gsub("(~|\\+|\\*|-|/|:)", "", gsub(" ", "", gsub("\\((.*)\\)", "", f)))) == 0
}



# extract random effects from formula
.get_model_random <- function(f, split_nested = FALSE, model) {
  is_special <- inherits(
    model,
    c(
      "MCMCglmm", "gee", "LORgee", "mixor", "clmm2", "felm", "feis", "bife",
      "BFBayesFactor", "BBmm", "glimML", "MANOVA", "RM", "cglm"
    )
  )

  if (identical(.safe_deparse(f), "~0") ||
    identical(.safe_deparse(f), "~1")) {
    return(NULL)
  }

  if (!requireNamespace("lme4", quietly = TRUE)) {
    stop("To use this function, please install package 'lme4'.")
  }

  re <- sapply(lme4::findbars(f), .safe_deparse)

  if (is_special && .is_empty_object(re)) {
    re <- all.vars(f[[2L]])
    if (length(re) > 1) {
      re <- as.list(re)
      split_nested <- FALSE
    }
  } else {
    re <- .trim(substring(re, max(gregexpr(pattern = "\\|", re)[[1]]) + 1))
  }

  # check for multi-membership models
  if (inherits(model, "brmsfit")) {
    if (grepl("mm\\((.*)\\)", re)) {
      re <- trimws(unlist(strsplit(gsub("mm\\((.*)\\)", "\\1", re), ",")))
    }
  }

  if (split_nested) {
    # remove parenthesis for nested models
    re <- unique(unlist(strsplit(re, "\\:")))

    # nested random effects, e.g. g1 / g2 / g3, deparse to "g0:(g1:g2)".
    # when we split at ":", we have "g0", "(g1" and "g2)". In such cases,
    # we need to remove the parentheses. But we need to preserve them in
    # case we have group factors in other models, like panelr, where we can
    # have "lag(union)" as group factor. In such cases, parentheses should be
    # preserved. We here check if group factors, after passing to "clean_names()",
    # still have "(" or ")" in their name, and if so, just remove parentheses
    # for these cases...

    has_parantheses <- vapply(
      clean_names(re),
      function(i) {
        grepl("[\\(\\)]", x = i)
      },
      logical(1)
    )

    if (any(has_parantheses)) {
      re[has_parantheses] <- gsub(pattern = "[\\(\\)]", replacement = "", x = re[has_parantheses])
    }

    re
  } else {
    unique(re)
  }
}



# in case we need the random effects terms as formula (symbol),
# not as character string, then call this functions instead of
# .get_model_random()
.get_group_factor <- function(x, f) {
  if (is.list(f)) {
    f <- lapply(f, function(.x) {
      .get_model_random(.x, split_nested = TRUE, x)
    })
  } else {
    f <- .get_model_random(f, split_nested = TRUE, x)
  }

  if (is.null(f)) {
    return(NULL)
  }

  if (is.list(f)) {
    f <- lapply(f, function(i) sapply(i, as.symbol))
  } else {
    f <- sapply(f, as.symbol)
  }

  f
}



# to reduce redundant code, I extract this part which is used several
# times accross this package
.get_elements <- function(effects, component) {
  elements <- c("conditional", "conditional2", "conditional3", "precision", "nonlinear", "random", "zero_inflated", "zero_inflated_random", "dispersion", "instruments", "interactions", "simplex", "smooth_terms", "sigma", "nu", "tau", "correlation", "slopes", "cluster", "extra", "scale", "marginal")

  elements <- switch(
    effects,
    all = elements,
    fixed = elements[elements %in% c("conditional", "conditional2", "conditional3", "precision", "zero_inflated", "dispersion", "instruments", "interactions", "simplex", "smooth_terms", "correlation", "slopes", "sigma", "nonlinear", "cluster", "extra", "scale", "marginal")],
    random = elements[elements %in% c("random", "zero_inflated_random")]
  )

  elements <- switch(
    component,
    all = elements,
    conditional = elements[elements %in% c("conditional", "conditional2", "conditional3", "precision", "nonlinear", "random", "slopes")],
    zi = ,
    zero_inflated = elements[elements %in% c("zero_inflated", "zero_inflated_random")],
    dispersion = elements[elements == "dispersion"],
    instruments = elements[elements == "instruments"],
    interactions = elements[elements == "interactions"],
    simplex = elements[elements == "simplex"],
    sigma = elements[elements == "sigma"],
    smooth_terms = elements[elements == "smooth_terms"],
    correlation = elements[elements == "correlation"],
    cluster = elements[elements == "cluster"],
    nonlinear = elements[elements == "nonlinear"],
    slopes = elements[elements == "slopes"],
    extra = elements[elements == "extra"],
    scale = elements[elements == "scale"],
    precision = elements[elements == "precision"],
    marginal = elements[elements == "marginal"]
  )

  elements
}



# checks if a mixed model fit is singular or not. Need own function,
# because lme4::isSingular() does not work with glmmTMB
#' @importFrom stats na.omit
.is_singular <- function(x, vals, tolerance = 1e-5) {
  if (!requireNamespace("lme4", quietly = TRUE)) {
    stop("Package `lme4` needs to be installed to compute variances for mixed models.", call. = FALSE)
  }

  tryCatch(
    {
      if (inherits(x, c("glmmTMB", "clmm", "cpglmm"))) {
        is_si <- any(sapply(vals$vc, function(.x) any(abs(diag(.x)) < tolerance)))
      } else if (inherits(x, "merMod")) {
        theta <- lme4::getME(x, "theta")
        diag.element <- lme4::getME(x, "lower") == 0
        is_si <- any(abs(theta[diag.element]) < tolerance)
      } else if (inherits(x, "MixMod")) {
        vc <- diag(x$D)
        is_si <- any(sapply(vc, function(.x) any(abs(.x) < tolerance)))
      } else if (inherits(x, "lme")) {
        is_si <- any(abs(stats::na.omit(as.numeric(diag(vals$vc))) < tolerance))
      } else {
        is_si <- FALSE
      }

      is_si
    },
    error = function(x) {
      FALSE
    }
  )
}



# Filter parameters from Stan-model fits
.filter_pars <- function(l, parameters = NULL, is_mv = NULL) {
  if (!is.null(parameters)) {
    if (is.null(is_mv)) {
      is_mv <- isTRUE(attr(l, "is_mv", exact = TRUE) == "1")
    }
    if (is_multivariate(l) || is_mv) {
      for (i in names(l)) {
        l[[i]] <- .filter_pars_univariate(l[[i]], parameters)
      }
    } else {
      l <- .filter_pars_univariate(l, parameters)
    }
    if (isTRUE(is_mv)) attr(l, "is_mv") <- "1"
  }

  l
}



.filter_pars_univariate <- function(l, parameters) {
  lapply(l, function(component) {
    unlist(unname(sapply(
      parameters,
      function(pattern) {
        component[grepl(pattern = pattern, x = component, perl = TRUE)]
      },
      simplify = FALSE
    )))
  })
}



# remove column
.remove_column <- function(data, variables) {
  data[, -which(colnames(data) %in% variables), drop = FALSE]
}



.grep_smoothers <- function(x) {
  grepl("^(s\\()", x, perl = TRUE) |
    grepl("^(ti\\()", x, perl = TRUE) |
    grepl("^(te\\()", x, perl = TRUE) |
    grepl("^(t2\\()", x, perl = TRUE) |
    grepl("^(gam::s\\()", x, perl = TRUE) |
    grepl("^(VGAM::s\\()", x, perl = TRUE) |
    grepl("^(mgcv::s\\()", x, perl = TRUE) |
    grepl("^(mgcv::ti\\()", x, perl = TRUE) |
    grepl("^(mgcv::te\\()", x, perl = TRUE) |
    grepl("^(brms::s\\()", x, perl = TRUE) |
    grepl("^(brms::t2\\()", x, perl = TRUE) |
    grepl("^(smooth_sd\\[)", x, perl = TRUE)
}



.grep_zi_smoothers <- function(x) {
  grepl("^(s\\.\\d\\()", x, perl = TRUE) |
    grepl("^(gam::s\\.\\d\\()", x, perl = TRUE) |
    grepl("^(mgcv::s\\.\\d\\()", x, perl = TRUE)
}



.grep_non_smoothers <- function(x) {
  grepl("^(?!(s\\())", x, perl = TRUE) &
    # this one captures smoothers in zi- or mv-models from gam
    grepl("^(?!(s\\.\\d\\())", x, perl = TRUE) &
    grepl("^(?!(ti\\())", x, perl = TRUE) &
    grepl("^(?!(te\\())", x, perl = TRUE) &
    grepl("^(?!(t2\\())", x, perl = TRUE) &
    grepl("^(?!(gam::s\\())", x, perl = TRUE) &
    grepl("^(?!(gam::s\\.\\d\\())", x, perl = TRUE) &
    grepl("^(?!(VGAM::s\\())", x, perl = TRUE) &
    grepl("^(?!(mgcv::s\\())", x, perl = TRUE) &
    grepl("^(?!(mgcv::s\\.\\d\\())", x, perl = TRUE) &
    grepl("^(?!(mgcv::ti\\())", x, perl = TRUE) &
    grepl("^(?!(mgcv::te\\())", x, perl = TRUE) &
    grepl("^(?!(brms::s\\())", x, perl = TRUE) &
    grepl("^(?!(brms::t2\\())", x, perl = TRUE) &
    grepl("^(?!(smooth_sd\\[))", x, perl = TRUE)
}



# .split_formula <- function(f) {
#   rhs <- if (length(f) > 2)
#     f[[3L]]
#   else
#     f[[2L]]
#
#   lapply(.extract_formula_parts(rhs), .safe_deparse)
# }
#
#
# .extract_formula_parts <- function(x, sep = "|") {
#   if (is.null(x))
#     return(NULL)
#   rval <- list()
#   if (length(x) > 1L && x[[1L]] == sep) {
#     while (length(x) > 1L && x[[1L]] == sep) {
#       rval <- c(x[[3L]], rval)
#       x <- x[[2L]]
#     }
#   }
#   c(x, rval)
# }



.safe_deparse <- function(string) {
  if (is.null(string)) {
    return(NULL)
  }
  paste0(sapply(deparse(string, width.cutoff = 500), .trim, simplify = TRUE), collapse = " ")
}



#' @importFrom stats family
.gam_family <- function(x) {
  faminfo <- tryCatch(
    {
      stats::family(x)
    },
    error = function(e) {
      NULL
    }
  )

  # try to set manually, if not found otherwise
  if (is.null(faminfo)) {
    faminfo <- tryCatch(
      {
        x$family
      },
      error = function(e) {
        NULL
      }
    )
  }

  faminfo
}



# for models with zero-inflation component, return
# required component of model-summary
.filter_component <- function(dat, component) {
  switch(
    component,
    "cond" = ,
    "conditional" = dat[dat$Component == "conditional", , drop = FALSE],
    "zi" = ,
    "zero_inflated" = dat[dat$Component == "zero_inflated", , drop = FALSE],
    "dispersion" = dat[dat$Component == "dispersion", , drop = FALSE],
    "smooth_terms" = dat[dat$Component == "smooth_terms", , drop = FALSE],
    dat
  )
}




# capitalizes the first letter in a string
.capitalize <- function(x) {
  capped <- grep("^[A-Z]", x, invert = TRUE)
  substr(x[capped], 1, 1) <- toupper(substr(x[capped], 1, 1))
  x
}



.remove_backticks_from_parameter_names <- function(x) {
  if (is.data.frame(x) && "Parameter" %in% colnames(x)) {
    x$Parameter <- gsub("`", "", x$Parameter, fixed = TRUE)
  }
  x
}


.remove_backticks_from_string <- function(x) {
  if (is.character(x)) {
    x <- gsub("`", "", x, fixed = TRUE)
  }
  x
}


.remove_backticks_from_matrix_names <- function(x) {
  if (is.matrix(x)) {
    colnames(x) <- gsub("`", "", colnames(x), fixed = TRUE)
    rownames(x) <- gsub("`", "", colnames(x), fixed = TRUE)
  }
  x
}





#' @importFrom stats reshape
#' @keywords internal
.gather <- function(x, names_to = "key", values_to = "value", columns = colnames(x)) {
  if (is.numeric(columns)) columns <- colnames(x)[columns]
  dat <- stats::reshape(
    x,
    idvar = "id",
    ids = row.names(x),
    times = columns,
    timevar = names_to,
    v.names = values_to,
    varying = list(columns),
    direction = "long"
  )

  if (is.factor(dat[[values_to]])) {
    dat[[values_to]] <- as.character(dat[[values_to]])
  }

  dat[, 1:(ncol(dat) - 1), drop = FALSE]
}

# Functions to compute counts and average counts

# Suppress CMD CHECK notes for things that look like global vars
if (getRversion() >= "2.15.1")
  utils::globalVariables(c(".", "Phenotype", "Tissue Category"))

#' Count cells within a radius for multiple tissue categories, phenotypes
#' and fields.
#'
#' This is a batch version of [count_within()]. Given the path to a directory
#' containing cell seg data files, for each given tissue category,
#' pair of
#' 'from' phenotype and 'to' phenotype, and radius, it counts the number of
#'  'from' cells
#' having a 'to' cell within `radius` microns.
#'
#' The `category` parameter may be a single category or a list of categories.
#'
#' See the tutorial
#' [Selecting cells within a cell segmentation table](https://akoyabio.github.io/phenoptr/articles/selecting_cells.html)
#'  for more on
#' the use of `pairs` and `phenotype_rules`.
#'
#' @param base_path Path to a directory containing at least
#' one `_cell_seg_data.txt` file.
#' @param pairs A list of pairs of phenotypes. Each entry is a two-element
#'   vector. The result will contain values for each pair.
#' @param radius The radius or radii to search within.
#' @param phenotype_rules (Optional) A named list.
#'   Item names are phenotype names and must match entries in `pairs`.
#'   Item values are selectors for [select_rows()].
#' @param category Optional tissue categories to restrict both `from` and
#' `to` phenotypes.
#' @param verbose If TRUE, display progress.
#' @return A `tibble` containing these columns:
#'   \describe{
#'    \item{\code{slide_id}}{Slide ID from the data files, if available.}
#'    \item{\code{source}}{Base file name of the source file with
#'    `_cell_seg_data.txt` stripped off for brevity.}
#'    \item{\code{category}}{Tissue category, if provided as a parameter,
#'    or "all".}
#'    \item{\code{from}}{From phenotype.}
#'    \item{\code{to}}{To phenotype.}
#'    \item{\code{radius}, \code{from_count}, \code{to_count},
#'    \code{from_with}, \code{within_mean}}{Results from [count_within]
#'    for this data file and tissue category.}
#'  }
#' @examples
#' base_path <- sample_cell_seg_folder()
#'
#' # Count tumor cells near macrophages, and tumor cells near CD8 separately,
#' # in tumor and stroma tissue categories separately.
#' pairs <- list(c('CK+', 'CD68+'),
#'              c('CK+', 'CD8+'))
#' radius <- c(10, 25)
#' category <- list('Tumor', 'Stroma')
#' count_within_batch(base_path, pairs, radius, category)
#'
#' # Count tumor cells near any T cell in all tissue categories.
#' # Use `phenotype_rules` to define the T cell phenotype
#' pairs <- c('CK+', 'T cell')
#' rules <- list(
#' 'T cell'=c('CD8+', 'FoxP3+'))
#' count_within_batch(base_path, pairs, radius, phenotype_rules=rules)
#' @md
#' @export
#' @family distance functions
#' @importFrom magrittr "%>%"
count_within_batch <- function(base_path, pairs, radius, category=NA,
                              phenotype_rules=NULL, verbose=TRUE) {
  files = list_cell_seg_files(base_path)
  if (length(files) == 0)
    stop('No cell seg files found in ', base_path)

  pairs = clean_pairs(pairs)

  all_phenotypes = unique(do.call(c, pairs))
  phenotype_rules = make_phenotype_rules(all_phenotypes, phenotype_rules)

  combos = purrr::cross(list(pair=pairs, category=category))

  # Loop through all the cell seg data files
  purrr::map_df(files, function(path) {
    name = basename(path) %>% sub('_cell_seg_data.txt', '', .)
    if (verbose) cat('Processing', name, '\n')

    # Read one file
    csd = read_cell_seg_data(path)

    count_within_many_impl(csd, name, combos, radius, phenotype_rules)
  })
}

#' Count cells within a radius for multiple tissue categories and phenotypes
#' in a single field.
#'
#' This is a wrapper around [count_within()] which supports counting
#' multiple phenotype pairs and tissue categories within a single field.
#' For each given tissue category, pair of
#' 'from' phenotype and 'to' phenotype, and radius, it counts the number of
#'  'from' cells
#' having a 'to' cell within `radius` microns.
#'
#' The `category` parameter may be a single category or a list of categories.
#'
#' See the tutorial
#' [Selecting cells within a cell segmentation table](https://akoyabio.github.io/phenoptr/articles/selecting_cells.html)
#'  for more on
#' the use of `pairs` and `phenotype_rules`.
#'
#' @param csd A cell seg data table.
#' @param pairs A list of pairs of phenotypes. Each entry is a two-element
#'   vector. The result will contain values for each pair.
#' @param radius The radius or radii to search within.
#' @param phenotype_rules (Optional) A named list.
#'   Item names are phenotype names and must match entries in `pairs`.
#'   Item values are selectors for [select_rows()].
#' @param category Optional tissue categories to restrict both `from` and
#' `to` phenotypes.
#' @param verbose If TRUE, display progress.
#' @return A `tibble` containing these columns:
#'   \describe{
#'    \item{\code{slide_id}}{Slide ID from the data, if available.}
#'    \item{\code{source}}{Source field name.}
#'    \item{\code{field}}{Name of the individual field, if available.}
#'    \item{\code{category}}{Tissue category, if provided as a parameter,
#'    or "all".}
#'    \item{\code{from}}{From phenotype.}
#'    \item{\code{to}}{To phenotype.}
#'    \item{\code{radius}, \code{from_count}, \code{to_count},
#'    \code{from_with}, \code{within_mean}}{Results from [count_within]
#'    for this data file and tissue category.}
#'  }
#' @examples
#' csd <- sample_cell_seg_data
#'
#' # Count tumor cells near macrophages, and tumor cells near CD8 separately,
#' # in tumor and stroma tissue categories separately.
#' pairs <- list(c('CK+', 'CD68+'),
#'              c('CK+', 'CD8+'))
#' radius <- c(10, 25)
#' category <- list('Tumor', 'Stroma')
#' count_within_many(csd, pairs, radius, category)
#'
#' # Count tumor cells near any T cell in all tissue categories.
#' # Use `phenotype_rules` to define the T cell phenotype
#' pairs <- c('CK+', 'T cell')
#' rules <- list(
#' 'T cell'=c('CD8+', 'FoxP3+'))
#' count_within_many(csd, pairs, radius, phenotype_rules=rules)
#' @md
#' @export
#' @family distance functions
#' @importFrom magrittr "%>%"
count_within_many <- function(csd, pairs, radius, category=NA,
                               phenotype_rules=NULL, verbose=TRUE) {
  # count_within_many_impl_rtree gives incorrect results if category
  # is a list than includes both NA and named categories.
  # This is not something we need to support, just disallow it
  if (any(is.na(category)) && !all(is.na(category)))
    stop('Category argument cannot include both NA and named categories.')

  pairs = clean_pairs(pairs)

  all_phenotypes = unique(do.call(c, pairs))
  phenotype_rules = make_phenotype_rules(all_phenotypes, phenotype_rules)

  combos = purrr::cross(list(pair=pairs, category=category))

  # Try to get a name for this field
  field_col = dplyr::if_else('Annotation ID' %in% names(csd),
                               'Annotation ID', 'Sample Name')
  name = ifelse(field_col %in% names(csd),
                        csd[[1, field_col]], NA_character_)

  if (verbose) cat('Processing', name, '\n')

  count_within_many_impl(csd, name, combos, radius, phenotype_rules)
}

# Helper functions for count_within_batch and count_within_many
clean_pairs = function(pairs) {
  # Allow a single pair to be specified as a plain vector
  if (is.character(pairs) && length(pairs)==2)
    pairs = list(pairs)

  stopifnot(is.list(pairs), length(pairs) > 0)
  pairs
}

#' Helper function for count_within_batch and count_within_many.
#' This does the actual work of calling count_within multiple times and
#' accumulating the result.
#' @param csd Cell seg data for a single field.
#' @param name Name associated with `csd`, for example the basename of the
#' image file.
#' @param combos List of pairs of (from phenotype name, to phenotype name)
#' and tissue category.
#' @param radii Vector of radii.
#' @param phenotype_rules Named list of phenotype rules.
#' @keywords internal
count_within_many_impl <- function(csd, name, combos, radii, phenotype_rules) {
  if (getOption('use.rtree.if.available') &&
      requireNamespace('rtree', quietly=TRUE))
    counts = count_within_many_impl_rtree(
      csd, name, combos, radii, phenotype_rules)
  else
    counts = count_within_many_impl_dist(
      csd, name, combos, radii, phenotype_rules)

  # Add columns for slide and source
  counts = counts %>%
    tibble::add_column(source=name, .before=1)

  if ('Slide ID' %in% names(csd)) {
    slide = as.character(csd[1, 'Slide ID'])
    counts = counts %>% tibble::add_column(slide_id=slide, .before=1)
  }

  counts
}

#' Distance matrix implementation of count_within_many_impl
#' @param csd Cell seg data for a single field.
#' @param name Name associated with `csd`, for example the basename of the
#' image file.
#' @param combos List of pairs of (from phenotype name, to phenotype name)
#' and tissue category.
#' @param radii Vector of radii.
#' @param phenotype_rules Named list of phenotype rules.
#' @seealso count_within_many_impl
#' @md
#' @keywords internal
count_within_many_impl_dist <- function(
    csd, name, combos, radii, phenotype_rules) {
  category = combos %>% purrr::map_chr('category') %>% unique()

  # Subset to what we care about, for faster distance calculation
  if (!anyNA(category))
    csd = csd %>% dplyr::filter(`Tissue Category` %in% category)

  # Compute the distance matrix for these cells
  dst = distance_matrix(csd)

  # Compute counts for each from, to, and category in combos
  row_count = purrr::map_df(combos, function(row) {
    # Call count_within for each item in combos
    # count_within handles multiple radii
    from = row$pair[1]
    from_sel = phenotype_rules[[from]]
    to = row$pair[2]
    to_sel = phenotype_rules[[to]]
    count_within(csd=csd, from=from_sel, to=to_sel,
                 category=row$category,
                 radius=radii, dst=dst) %>%
      # Add columns for from, to, category
      tibble::add_column(
        category = ifelse(is.na(row$category), 'all', row$category),
        from=from,
        to=to,
        .before=1)
  })
}

#' Count cells within a radius for a single field.
#'
#' Count the number of \code{from} cells having a \code{to} cell within
#' \code{radius} microns in tissue category \code{category}.
#' Compute the average number of \code{to} cells
#' within \code{radius} of \code{from} cells.
#'
#' For each \code{from} cell, count the number of \code{to} cells within
#' \code{radius} microns. Report the number of \code{from} cells containing
#' at least \emph{one} \code{to} cell within \code{radius} as \code{from_with}.
#' Report the \emph{average} number of \code{to} cells per
#' \code{from} cell as \code{within_mean}.
#'
#' \code{count_within} counts cells within a single field. It will give an
#' error if run on a merged cell seg data file. To count cells in a merged file,
#' use \code{\link[dplyr]{group_by}} and \code{\link[dplyr]{do}} to call
#' \code{count_within} for each sample in the merged file. See the Examples.
#'
#' There are some subtleties to the count calculation.
#' \itemize{
#'   \item It is not symmetric in \code{from} and \code{to}.
#'   For example the number of tumor cells with a
#'   macrophage within 25 microns is not the same as the number of macrophages
#'   with a tumor cell within 25 microns.
#'   \item \code{from_count*within_mean} is \emph{not} the number of
#'   \code{to} cells within \code{radius} of a \code{from} cell, it may
#'   count \code{to} cells multiple times.
#'   \item Surprisingly, \code{from_count*within_mean} is symmetric in
#'   \code{from} and \code{to}. The double-counting works out.
#' }
#'
#' To aggregate \code{within_mean} across multiple samples (e.g. by Slide ID)
#' see the examples below.
#'
#' If \code{category} is specified, all reported values are for cells within
#' the given tissue category. If \code{category} is NA, values are reported
#' for the entire data set.
#'
#' \code{radius} may be a vector with multiple values.
#'
#' @param csd A data frame with \code{Cell X Position},
#'        \code{Cell Y Position} and \code{Phenotype} columns,
#'        such as the result of calling \code{\link{read_cell_seg_data}}.
#' @param from,to Selection criteria for the
#' rows and columns. Accepts all formats accepted by \code{\link{select_rows}}.
#' @param radius The radius or radii to search within.
#' @param category Optional tissue category to restrict both \code{from} and
#' \code{to}.
#' @param dst Optional distance matrix corresponding to \code{csd},
#'        produced by calling \code{\link{distance_matrix}}.
#'
#' @return A \code{\link{tibble}} with five columns and one row for each
#'   value in \code{radius}:
#'   \describe{
#'    \item{\code{radius}}{The value of \code{radius} for this row.}
#'    \item{\code{from_count}}{The number of \code{from} cells found in
#'     \code{csd}.}
#'    \item{\code{to_count}}{The number of \code{to} cells found in \code{csd}.}
#'    \item{\code{from_with}}{The number of \code{from} cells with a
#'    \code{to} cell within \code{radius}.}
#'    \item{\code{within_mean}}{The average number of \code{to} cells found
#'    within \code{radius} microns of each \code{from} cell.}
#'  }
#' @export
#' @family distance functions
#' @examples
#' library(dplyr)
#' csd <- sample_cell_seg_data
#'
#' # Find the number of macrophages with a tumor cell within 10 or 25 microns
#' count_within(csd, from='CD68+', to='CK+', radius=c(10, 25))
#'
#' # Find the number of tumor cells with a macrophage within 10 or 25 microns
#' count_within(csd, from='CK+', to='CD68+', radius=c(10, 25))
#'
#' \dontrun{
#' # If 'merged' is a merged cell seg file, this will run count_within for
#' # each field:
#' distances = merged %>% group_by(`Slide ID`, `Sample Name`) %>%
#'   do(count_within(., from='CK+', to='CD68+', radius=c(10, 25)))
#'
#' # This will aggregate the fields by Slide ID:
#' distances %>% group_by(`Slide ID`, radius) %>%
#'   summarize(within=sum(from_count*within_mean, na.rm=TRUE),
#'             from_count=sum(from_count),
#'             to_count=sum(to_count),
#'             from_with=sum(from_with),
#'             within_mean=within/from_count) %>%
#'   select(-within)
#' }

count_within <- function(csd, from, to, radius, category=NA, dst=NULL) {
  # Check for multiple samples, this is probably an error
  if ('Sample Name' %in% names(csd) && length(unique(csd$`Sample Name`))>1)
    stop('Data appears to contain multiple samples.')

  stopifnot(length(radius) > 0, all(radius>0))

  # If a category is provided, subset now
  if (!is.na(category)) {
    category_cells = csd$`Tissue Category`==category
    csd = csd[category_cells, ]
    if (!is.null(dst))
      dst = dst[category_cells, category_cells, drop=FALSE]
  }

  if (is.null(dst))
    dst = distance_matrix(csd)

  dst = subset_distance_matrix(csd, dst, from, to)
  if (prod(dim(dst))>0) {
    purrr::map_df(radius, function(rad) {
      within = apply(dst, 1, function(r) sum(r>0 & r<=rad))
      tibble::tibble(
        radius = rad,
        from_count = dim(dst)[1], # Number of from cells
        to_count = dim(dst)[2],   # Number of to cells
        from_with = sum(within>0), # Number of from cells having a
                                   # to cell within radius
        within_mean = mean(within) # Mean number of to cells within
                                   # radius of a from cell
      )}
    )
  } else {
    tibble::tibble(
      radius = radius,
      from_count = dim(dst)[1],
      to_count = dim(dst)[2],
      from_with = 0L,
      within_mean = NA
    )
  }
}

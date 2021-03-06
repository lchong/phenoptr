#' Find inForm data files.
#'
#' `list_cell_seg_files` finds inForm cell seg data files in a single directory
#' or a directory hierarchy.
#'
#' @param path Path to the base directory to search.
#' @param ... Additional arguments passed to [list.files][base::list.files()].
#' Pass `recursive=TRUE` to search a directory hierarchy.
#' @return A list of  file paths.
#' @export
#' @family file readers
#' @md
list_cell_seg_files <- function(path, ...) {
  list.files(path, pattern='cell_seg_data.txt', full.names=TRUE, ...)
}

#' Read and clean an inForm data file.
#'
#' \code{read_cell_seg_data} makes it easier to use data from Akoya Biosciences'
#' inForm program. It reads data files written by inForm 2.0 and later and does
#' useful cleanup on the result.
#'
#' \code{read_cell_seg_data} reads both single-image tables and merged tables
#' and does useful cleanup on the data:
#' \itemize{
#' \item Removes columns that are all NA.
#'       These are typically unused summary columns.
#' \item Converts percent columns to numeric fractions.
#' \item Converts pixel distances to microns. The conversion factor may be
#' specified as a parameter, by setting
#' \code{options(phenoptr.pixels.per.micron)}, or by reading an associated
#' \code{component_data.tif} file.
#' \item Optionally removes units from expression names
#' \item If the file contains multiple sample names,
#'       a \code{tag} column is created
#'       containing a minimal, unique tag for each sample.
#'       This is useful when a
#'       short name is needed, for example in chart legends.
#' }
#'
#' If \code{pixels_per_micron='auto'}, \code{read_cell_seg_data} looks for
#' a \code{component_data.tif} file in the same directory as \code{path}.
#' If found, \code{pixels_per_micron} is read from the file \strong{and}
#' the cell coordinates are offset to the correct spatial location.
#'
#' @param path Path to the file to read, or NA to use a file chooser.
#' @param pixels_per_micron Conversion factor to microns
#'        (default 2 pixels/micron, the resolution of 20x MSI fields
#'        taken on Vectra Polaris and Vectra 3.).
#'        Set to NA to skip conversion. Set to \code{'auto'} to read from
#'        an associated \code{component_data.tif} file.
#' @param remove_units If TRUE (default),
#'        remove the unit name from expression columns.
#' @return A \code{\link[tibble]{tibble}}
#'         containing the cleaned-up data set.
#' @export
#' @family file readers
#' @examples
#' path <- sample_cell_seg_path()
#' csd <- read_cell_seg_data(path)
#'
#' # count all the phenotypes in the data
#' table(csd$Phenotype)
#'
#' \dontrun{
#' # Use purrr::map_df to read all cell seg files in a directory
#' # and return a single tibble.
#' paths <- list_cell_seg_files(path)
#' csd <- purrr::map_df(paths, read_cell_seg_data)
#' }
read_cell_seg_data <- function(
  path=NA,
  pixels_per_micron=getOption('phenoptr.pixels.per.micron'),
  remove_units=TRUE) {
  if (is.na(path)) {
    path <- file.choose() # nocov not going to happen...
    cat('Loading', path)  # nocov
  }
  if (path=='')
    stop("File name is missing.")

  # Figure out what we are reading
  data_types = get_col_types_and_decimal_mark(path)

  # Read the data.
  df <- readr::read_tsv(path, na=c('NA', '#N/A'),
          locale=readr::locale(decimal_mark=data_types$decimal_mark),
          col_types=data_types$col_spec)

  # If any of these fields has missing values, the file may be damaged.
  no_na_cols = c("Path", "Sample Name", "Tissue Category", "Phenotype",
                 "Cell ID", "Slide ID")

  bad_na_cols =
    purrr::keep(no_na_cols, ~(.x %in% names(df) && any(is.na(df[[.x]]))))
  if (length(bad_na_cols) > 0)
    warning('Some expected columns have missing data:\n',
            paste(bad_na_cols, collapse=', '), '\n',
            path, ' may be damaged.')
  sample_name = 'Sample Name'

  # If there are multiple sample names, make 'tag' be an abbreviated
  # Sample.Name column and insert it as the first column
  # Use the 'tag' column when you need a short name for the sample,
  # e.g. in chart legends
  if (length(unique(df[[sample_name]])) > 1 && !('tag' %in% names(df))) {
    tag <- as.factor(remove_extensions(remove_common_prefix(df[[sample_name]])))
    df <- cbind(tag, df)
  }

  # Convert percents if it is not done already. These may contain commas!!
  pcts <- grep('percent|confidence', names(df), ignore.case=TRUE)
  for (i in pcts) {
    if (is.character(df[[i]])) {
      clean_col = stringr::str_replace_all(df[[i]],
        c('\\s*%$'='', ','='.')) # Remove trailing % and change comma to period
      df[[i]] <- as.numeric(clean_col)/100
    }
  }

  # Remove columns that are all NA or all blank
  # The first condition is a preflight that speeds this up a lot
  na_columns <- purrr::map_lgl(df, function(col)
    (is.na(col[1]) | col[1]=='') && all(is.na(col) | col==''))
  df <- df[!na_columns]

  # Convert distance to microns if requested.
  # No way to tell in general if this was done already...
  # Try looking for 'micron' in column names
  if (unit_is_microns(df) && !is.na(pixels_per_micron)) {
    message('Data is already in microns, no conversion performed')
  } else if (!is.na(pixels_per_micron)) {
    if (pixels_per_micron=='auto') {
      # Get pixels_per_micron and field location from component_data.tif
      component_path = sub('_cell_seg_data.txt', '_component_data.tif', path)
      if(!file.exists(component_path))
        stop('To convert cell seg data to microns, ',
             'a matching component data file is required.')
      info = get_field_info(component_path)
      pixels_per_micron = 1/info$microns_per_pixel
      location = info$location
    } else {
      location = NA
    }

    cols = get_pixel_columns(df)
    for (col in cols) {
      # If col has a lot of NAs it may have been read as chr
      if (!is.numeric(df[[col]]))
        df[[col]] = as.numeric(df[[col]])
      df[[col]] = df[[col]] / pixels_per_micron
      names(df)[col] = sub('pixels', 'microns', names(df)[col])
    }

    # Position columns get an offset, if available
    if (!anyNA(location)) {
      df$`Cell X Position` = df$`Cell X Position` + location[1] # nolint
      df$`Cell Y Position` = df$`Cell Y Position` + location[2] # nolint
    }

    cols = get_area_columns(df)
    for (col in cols) {
      if (!is.numeric(df[[col]]))
        df[[col]] = as.numeric(df[[col]])
      df[[col]] = df[[col]] / (pixels_per_micron^2)
      names(df)[col] = sub('pixels', 'square microns', names(df)[col])
    }

    cols = get_density_columns(df)
    for (col in cols) {
      if (!is.numeric(df[[col]]))
        df[[col]] = as.numeric(df[[col]])
      df[[col]] = df[[col]] * (pixels_per_micron^2)
      names(df)[col] = sub('megapixel', 'square mm', names(df)[col])
    }
  }

  if (remove_units) {
    unit_name = stringr::str_match(names(df), 'Mean( \\(.*\\))$')[, 2]
    unit_name = unit_name[!is.na(unit_name)][1]
    if (!is.na(unit_name))
      names(df) = sub(unit_name, '', names(df), fixed=TRUE)
  }

  dplyr::as_tibble(df)
}

# Make a best effort to get column types and decimal mark from the data.
# The default imputation of column types fails if the first 1,000 rows
# contain #N/A for any column. This can happen for e.g. Distance to Category Edge
# @return A list with `col_spec` and `decimal_mark` items.
get_col_types_and_decimal_mark = function(path) {
  decimal_mark = '.' # Our default

  # Read the first 1000 lines of data.
  # Supplying col_types prevents console output of the imputed types.
  # Supplying the grouping_mark keeps readr from mis-handling commas
  # that are decimal separators.
  # See https://github.com/akoyabio/phenoptrReports/issues/31
  df <- readr::read_tsv(path, na=c('NA', '#N/A'), n_max=1000,
                        locale=readr::locale(grouping_mark=''),
                        col_types=readr::cols())

  # If columns containing "Mean" are character, check to see if the
  # file may have been written in a locale that uses comma as a decimal
  # separator. ("Mean" is not the only affected column, it is a proxy.)
  mean_cols = df %>%
    dplyr::select(dplyr::contains('Mean'))
  mean_class = mean_cols %>% purrr::map(class)

  if (any(mean_class=='character')) {
    # Try to confirm; just pick one column
    char_col = mean_cols[which(mean_class=='character')][[1]]
    if (any(stringr::str_detect(char_col, ','))) {
      message('Reading cell seg data with comma separator.')
      df <- readr::read_tsv(path, na=c('NA', '#N/A'), n_max=1000,
                            locale=readr::locale(decimal_mark=','),
                            col_types=readr::cols())
    }

    # Check again
    mean_cols = df %>%
      dplyr::select(dplyr::contains('Mean'))
    mean_class = mean_cols %>% purrr::map(class)

    if (any(mean_class=='character'))
      stop('Error reading cell seg data: ',
           'Expression columns have character values')

    decimal_mark = ','
  }

  # Now clean up the column spec. Start with the imputed types from readr.
  col_spec = readr::spec(df)$cols

  # If df has fewer than 1000 rows, we read the entire file and the
  # imputed column types should be fine.
  if (nrow(df) < 1000)
    return(list(col_spec=col_spec, decimal_mark=decimal_mark))

  # Explicitly assign column type for columns that may not be represented
  # in the first 1000 rows
  # Notes:
  # - Cell ID is "all" in summary tables, don't make it numeric here
  # - Columns such as "Total Cells which are populated in summary tables and
  #   present but unpopulated in detail tables don't need to be addressed here.
  #   They will be read correctly in the summary tables and removed from the
  #   detail tables.
  col_names = names(col_spec)
  col_spec[col_names=='Process Region ID'] = 'i'
  col_spec[stringr::str_detect(col_names, 'Distance')] = 'd'

  list(col_spec=do.call(readr::cols, col_spec), decimal_mark=decimal_mark)
}

# Convert cell locations back to pixels if possible
force_pixel_locations = function(csd, cell_seg_path) {
  if (unit_is_microns(csd)) {
    # The cell seg file's native unit is microns. Get image info
    # from the component data file and convert back to pixels
    component_path = sub('_cell_seg_data.txt', '_component_data.tif',
                         cell_seg_path)
    if(!file.exists(component_path))
      stop('For cell seg data in microns, ',
           'a matching component data file is required.')
    info = get_field_info(component_path)
    pixels_per_micron = 1/info$microns_per_pixel
    location = info$location
    csd %>% dplyr::mutate(
      `Cell X Position` = (`Cell X Position`-location[1])*pixels_per_micron,
      `Cell Y Position` = (`Cell Y Position`-location[2])*pixels_per_micron)
  } else {
    csd
  }
}

unit_is_microns = function(df) {
  any(stringr::str_detect(names(df), 'micron'))
}

get_pixel_columns = function(df) {
  rx = 'position|Distance from Process Region Edge|Distance from Tissue Category Edge|axis' # nolint
  grep(rx, names(df), ignore.case=TRUE)
}

get_area_columns = function(df) {
  rx = 'area \\(pixels\\)'
  grep(rx, names(df), ignore.case=TRUE)
}

get_density_columns = function(df) {
  rx = 'megapixel'
  grep(rx, names(df), ignore.case=TRUE)
}


# Remove the common prefix from a vector of strings
remove_common_prefix <- function(x) {
  # Lexicographic min and max
  .min <- min(x)
  .max <- max(x)
  if (.min == .max) return (x)  # All strings are the same

  # Find the first difference by comparing characters
  .split <- strsplit(c(.min, .max), split='')
  suppressWarnings(.match <- .split[[1]] == .split[[2]])
  first_diff <- match(FALSE, .match)

  substring(x, first_diff)
}

# Remove the extensions from a vector of strings
remove_extensions <- function(x) {
  sub('\\.[^.]+$', '', x)
}

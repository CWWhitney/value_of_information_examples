# Small generic helpers

# Fingerprint of everything a cached result depends on: the input table, all functions, and any `extra`
# settings (e.g. number of runs). Changing any of them invalidates the cache.
cache_key <- function(extra = "", files = c("inputs/school_garden_estimate.csv",
                                            list.files("functions", pattern = "\\.R$", full.names = TRUE))) {
  hashes <- unname(tools::md5sum(files))
  tools::md5sum(tempfile_with(paste(c(hashes, extra), collapse = "|")))[[1]]
}
tempfile_with <- function(text) { f <- tempfile(); writeLines(text, f); f }

# Reuse a saved result unless refresh = TRUE or the cache key changed: `expr` is only evaluated when the
# file is missing, its stored key (`<file>.key`) differs from `key`, or refresh = TRUE; it is then written
# to `file`. Lets the Rmd documents re-render quickly without ever serving stale results.
cached_csv <- function(file, expr, refresh = FALSE, key = cache_key()) {
  key_file <- paste0(file, ".key")
  fresh <- file.exists(file) && file.exists(key_file) && identical(readLines(key_file, warn = FALSE), key)
  if (!refresh && fresh) return(read.csv(file))
  res <- expr
  write.csv(res, file, row.names = FALSE)
  writeLines(key, key_file)
  res
}

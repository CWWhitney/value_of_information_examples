# Small generic helpers

# Reuse a saved result unless refresh = TRUE: `expr` is only evaluated when the file is missing (or
# refresh = TRUE), then written to `file`. Lets the Rmd documents re-render quickly.
cached_csv <- function(file, expr, refresh = FALSE) {
  if (!refresh && file.exists(file)) return(read.csv(file))
  res <- expr
  write.csv(res, file, row.names = FALSE)
  res
}

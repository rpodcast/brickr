#' Convert a data frame in 3D matrix format into bricks for 3D Model
#'
#' @param matrix_table A data frame of a 3D brick model desigh. Left-most column is level/height/z dimension, with rows as Y axis and columns as X axis. See example. Use \code{tribble} for ease.
#' @param color_guide A data frame linking numeric \code{.value} in \code{matrix_table} to official LEGO color names. Defaults to data frame 'lego_colors'.
#' @param .re_level Logical to reassign the Level/z dimension to layers in alphanumeric order. Set to FALSE to explicitly provide levels.
#' @param increment_level Default '0'. Use in animations. Shift  Level/z dimension by an integer.
#' @param max_level Default 'Inf'. Use in animations. Any Level/z values above this value will be cut off.
#' @param increment_x Default '0'. Use in animations. Shift x dimension by an integer.
#' @param max_x Default 'Inf'. Use in animations. Any x values above this value will be cut off.
#' @param increment_y Default '0'. Use in animations. Shift y dimension by an integer.
#' @param max_y Default 'Inf'. Use in animations. Any y values above this value will be cut off.
#' @param exclude_color Numeric array of color ID numbers to exclude.
#' @param exclude_level Numeric array of Level/z dimensions to exclude.
#' @return A list with elements \code{Img_lego} to pass to \code{collect_bricks()}.
#' @export 
#'
bricks_from_table <- function(matrix_table, color_guide = lego_colors, .re_level = TRUE,
                              increment_level = 0, max_level = Inf,
                              increment_x = 0, max_x = Inf,
                              increment_y = 0, max_y = Inf,
                              exclude_color = NULL, exclude_level = NULL){
  
  #Reformat input table to consistent format
  bricks_raw <- matrix_table
  names(bricks_raw)[1] <- "Level"
  names(bricks_raw)[-1] <- paste0("X", seq_along(names(bricks_raw)[-1]))
  
  #Color mapping
  color_guide_error_msg <- "Color guide should be a data frame with at least 2 columns: `.value` and `Color`. 
  `Color` should match official LEGO names in the data frame`lego_colors`."
  
  if(identical(color_guide, brickr::lego_colors)){
    color_map <- lego_colors %>% 
      dplyr::rename(.value = brickrID)
  } else if(is.data.frame(color_guide)){
    if(ncol(color_guide) < 2){stop(color_guide_error_msg)}
    if(!(".value" %in% names(color_guide)) | !("Color" %in% names(color_guide))){stop(color_guide_error_msg)}
    
    if(!all(color_guide$Color %in% display_colors(.names_only = TRUE))){
      stop(paste("At least one color name supplied does not match allowed brick color names. See display_colors().\n\n",
                    paste(color_guide$Color[!(color_guide$Color %in% display_colors(.names_only = TRUE))],collapse = ", ")
                    ))
      
    }
      
    color_map <- color_guide %>% 
      dplyr::mutate(Color = as.character(Color)) %>% 
      dplyr::left_join(lego_colors, by = "Color")
    
  } else{
    stop(color_guide_error_msg)
  }
  
  #Literal levels or names
  if(.re_level){
    bricks_raw <- bricks_raw %>% 
      dplyr::mutate(Level = as.numeric(as.factor(as.character(Level))))
  }
  
  #Clean up increments
  incr_level <- as.numeric(increment_level)[1]
  if(is.na(incr_level)){incr_level<-0}
  incr_x <- as.numeric(increment_x)[1]
  if(is.na(incr_x)){incr_x<-0}
  incr_y <- as.numeric(increment_y)[1]
  if(is.na(incr_y)){incr_y<-0}

  brick_set <- bricks_raw %>% 
    dplyr::mutate_all(dplyr::funs(ifelse(is.na(.), 0, .))) %>% 
    dplyr::group_by(Level) %>% 
    dplyr::mutate(y = dplyr::n() - dplyr::row_number() + 1) %>% 
    dplyr::ungroup() %>% 
    dplyr::select(Level, y, dplyr::everything()) %>% 
    tidyr::gather(x, .value, 3:ncol(.)) %>% 
    dplyr::mutate(x = as.numeric(substr(x, 2, 20))) %>% 
    dplyr::arrange(Level, x, dplyr::desc(y)) %>% 
    tidyr::drop_na(.value) %>% 
    dplyr::left_join(color_map, by = ".value") %>% 
    dplyr::mutate_at(dplyr::vars(dplyr::contains("_lego")), dplyr::funs(ifelse(is.na(.), 0, .))) %>% 
    dplyr::mutate(Lego_color = grDevices::rgb(R_lego, G_lego, B_lego)) %>% 
    dplyr::mutate(Lego_color = ifelse(is.na(Color),NA, Lego_color)) %>% 
    dplyr::rename(Lego_name = Color) %>%
    dplyr::arrange(Level) %>% 
    #Exclusions
    dplyr::filter(!(.value %in% exclude_color)) %>% 
    dplyr::filter(!(Level %in% exclude_level)) %>% 
    #Increment coordinates
    dplyr::mutate(Level = Level + incr_level,
                  x = x + incr_x, y = y + incr_y) %>% 
    dplyr::filter(Level >= 1, Level <= max_level,
                  x >= 1, x <= max_x,
                  y >= 1, y <= max_y) %>% 
    #In the end, drop empty levels
    dplyr::group_by(Level) %>% 
    dplyr::filter(!all(is.na(Lego_color))) %>% 
    dplyr::ungroup()
  
  #Return an object from collect_bricks()
  return(
    list(Img_lego =  brick_set) %>% collect_bricks
  )
}

#' Helper function to convert a level from a 3D model into a rayshader-friendly object.
#'
#' @param brick_list List output from table_to_bricks(). Contains an element \code{Img_lego}.
#' @param lev z-level of 3D model
#' @return A list with elements \code{threed_elevation} and \code{threed_hillshade} to created 3D mosiacs with the \code{rayshader} package.
#' @export 
#'
layer_from_bricks <- function(brick_list, lev=1){
  #Get previous data
  in_list <- brick_list
  
  BrickIDs <- in_list$ID_bricks%>% 
    dplyr::filter(Level == lev) 
  
  img_lego <- in_list$Img_lego %>% 
    dplyr::filter(Level == lev)
  
  #Increment elevation - a brick is 3 plates tall
  up_el = (lev-1)*3 
  
  #Number of 'pixels' on a side of a single-stud brick. I think this should be fixed for now
  ex_size <- 15
  
  lego_expand <- img_lego %>%
    dplyr::select(Level, x, y, Lego_name, Lego_color) %>% 
    dplyr::mutate(stud_id = dplyr::row_number()) 
  
  lego_expand2 <- expand.grid(x = (min(lego_expand$x)*ex_size):(max(lego_expand$x+1)*ex_size),
                              y = (min(lego_expand$y)*ex_size):(max(lego_expand$y+1)*ex_size)) %>% 
    dplyr::mutate(x_comp = x %/% ex_size,
                  y_comp = y %/% ex_size) %>% 
    dplyr::left_join(lego_expand %>% dplyr::rename(x_comp = x, y_comp = y), 
                     by = c("x_comp", "y_comp")) %>% 
    dplyr::left_join(BrickIDs %>% dplyr::select(brick_id, x_comp = x, y_comp = y), 
                     by = c("x_comp", "y_comp")) %>% 
    dplyr::select(-x_comp, -y_comp) %>% 
    dplyr::left_join(lego_colors %>% dplyr::select(Lego_name = Color, R_lego, G_lego, B_lego), 
                     by = "Lego_name") %>% 
    #Round elevation to nearest 1/height
    dplyr::mutate(elevation = ifelse(is.na(brick_id),NA, 3 + up_el),
                  elevation = ifelse(is.na(Lego_name),NA, elevation)) %>% 
    dplyr::group_by(brick_id) %>% 
    dplyr::mutate(elevation = dplyr::case_when(
      x == min(x) | x == max(x) ~ 0.1+up_el,
      y == min(y) | y == max(y) ~ 0.1+up_el,
      TRUE ~ elevation
    )) %>% 
    dplyr::ungroup() %>% 
    dplyr::mutate(y = max(y)-y) %>% 
    #Calculate stud placement... radius of 1/3 and height of 0.5 plate
    dplyr::group_by(stud_id) %>% 
    dplyr::mutate(x_mid = median(x), y_mid = median(y),
                  stud = ((x-x_mid)^2 + (y-y_mid)^2)^(1/2) < ex_size/3) %>% 
    dplyr::ungroup() %>% 
    dplyr::mutate(elevation = ifelse(stud, elevation+0.5, elevation)) %>% 
    dplyr::mutate_at(dplyr::vars(R_lego, G_lego, B_lego), dplyr::funs(ifelse(stud, .-0.1, .))) %>% 
    dplyr::mutate_at(dplyr::vars(R_lego, G_lego, B_lego), dplyr::funs(ifelse(. < 0, 0, .)))
  
  #Elevation Matrix
  lego_elmat <- lego_expand2 %>% 
    dplyr::mutate(elevation = ifelse(is.na(Lego_name), NA, elevation)) %>% 
    dplyr::select(x, y, elevation) %>% 
    tidyr::spread(y, elevation) %>% 
    dplyr::select(-x) %>% 
    as.matrix()
  
  #Hillshade matrix
  lego_hillshade_m <- array(dim = c(length(unique(lego_expand2$y)), 
                                    length(unique(lego_expand2$x)), 
                                    3))
  
  lego_expand_color <- lego_expand2 %>% 
    dplyr::group_by(brick_id) %>% 
    #This darkens the edge of each brick, to look like they are separated
    dplyr::mutate_at(dplyr::vars(R_lego, G_lego, B_lego), 
                     dplyr::funs(ifelse((x == min(x) | y == min(y) | x == max(x) | y == max(y)), .*0.75, .))) %>% 
    dplyr::ungroup()
  
  lego_hillshade_m[,,1] <- lego_expand_color %>% 
    dplyr::select(x, y, R_lego) %>% 
    tidyr::spread(x, R_lego) %>% 
    dplyr::select(-y) %>% 
    as.matrix()
  
  lego_hillshade_m[,,2] <- lego_expand_color %>% 
    dplyr::select(x, y, G_lego) %>% 
    tidyr::spread(x, G_lego) %>% 
    dplyr::select(-y) %>% 
    as.matrix()
  
  lego_hillshade_m[,,3] <- lego_expand_color %>% 
    dplyr::select(x, y, B_lego) %>% 
    tidyr::spread(x, B_lego) %>% 
    dplyr::select(-y) %>% 
    as.matrix()
  
  #Return
  in_list[["threed_elevation"]] <- lego_elmat
  in_list[["threed_hillshade"]] <- lego_hillshade_m
  
  return(in_list)
  
}

#' Build 3D brick model with rayshader.
#'
#' @param brick_list List output from collect_bricks(). Contains an element \code{Img_lego}.
#' @param view_levels Numeric array of Levels/z values to display. Leave as \code{NULL} to include all.
#' @param solidcolor Hex color of mosaic base. Only renders on bottom.
#' @param ... All other inputs from rayshader::plot_3d() EXCEPT \code{hillshade}, \code{soliddepth}, \code{zscale}, and \code{shadow}.
#' @return 3D brick model rendered in the 'rgl' package.
#' @export 
#'
display_bricks <- function(brick_list, view_levels = NULL, 
                           solidcolor = "#a3a2a4", ...){
  #Requires Rayshader
  if (!requireNamespace("rayshader", quietly = TRUE)) {
    stop("Package \"rayshader\" needed for this function to work. Please install it.",
         call. = FALSE)
  }
  
  #Get previous data
  in_list <- brick_list
  
  BrickIDs <- in_list$ID_bricks
  img_lego <- in_list$Img_lego 
  
  if(is.null(view_levels)){
    view_levels <- unique(img_lego$Level)
  }
  
  for(ii in view_levels){
    brick_layer <- brick_list %>% layer_from_bricks(ii)
    
    brick_layer$`threed_hillshade`%>%
      rayshader::plot_3d(brick_layer$`threed_elevation`, zscale=0.167, solid = FALSE,
                         solidcolor=solidcolor, shadow = FALSE, ...)
  }

}

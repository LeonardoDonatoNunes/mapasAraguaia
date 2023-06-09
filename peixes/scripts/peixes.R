library(sf)
library(tidyverse)
if (!dir.exists('peixes/shp')) {dir.create('peixes/shp')}
nome = 'peixes'

# Carrega os a shapefile com os pligonos das bacias aninhadas
bacias <- sf::read_sf('shpGeral/hidrografia_selected/bacias_ainhadas.shp')
bacias <- bacias[,1] # Mantém somente a primeira coluna que tem o ID de cada polígono
limite_bacia <- sf::read_sf('shpGeral/limite_bacia_oficial/limite_bacia_oficiala.shp')

atributos_or <- openxlsx::read.xlsx('peixes/ocorrencias/peixes_spvalidas_atributos_v4.xlsx')
ocorrencias_or <- openxlsx::read.xlsx('peixes/ocorrencias/peixes_ocorrencias_validadas_v4.xlsx', sheet = 1)
ocorrencias_invasores <- openxlsx::read.xlsx('peixes/ocorrencias/peixes_ocorrencia_invasor.xlsx')

colunas <- names(atributos_or) %>% table
colunas <- names(colunas[colunas > 1])
dup_index <- purrr::map_dbl(colunas, ~max(which(names(atributos_or) == .x)))
atributos_or <- atributos_or[, -dup_index]

rivulideos <- atributos_or %>% dplyr::filter(`Rivulidae.(>2007)` == 1) %>% dplyr::pull(BINOMIO) %>% unique()

ocorrencias_or$Obs %>% unique

ocorrencias <-
  ocorrencias_or %>%
  dplyr::filter(Obs %in% c("Listada para o Araguaia", "Não listada para o Araguaia")) %>%
  dplyr::rename(especies_validas = `Validação`) %>%
  dplyr::mutate(species = especies_validas) %>%
  dplyr::filter(species != "Moenkhausia alesis") %>%
  dplyr::mutate(
    longitude = geometry %>% purrr::map_chr(~eval(parse(text = paste0(.x, '[1]')))),
    latitude = geometry %>% purrr::map_chr(~eval(parse(text = paste0(.x, '[2]')))),
    lat = latitude,
    long = longitude) %>%
  sf::st_as_sf(coords = c('long', 'lat'), crs = st_crs(bacias))

ocorrencia_por_base <-
  ocorrencias %>%
  as.data.frame() %>%
  dplyr::count(species, base) %>%
  tidyr::pivot_wider(names_from = 'base', values_from = "n") %>%
  dplyr::mutate(dplyr::across(-species, ~ifelse(is.na(.), 0, 1)))

openxlsx::write.xlsx(ocorrencia_por_base, 'peixes/ocorrencias/ocorrencia_por_base.xlsx', overwrite = TRUE)

lista_de_especies <-
  ocorrencias %>%
  dplyr::distinct(species) %>%
  dplyr::arrange(species)

openxlsx::write.xlsx(lista_de_especies, 'C:/Users/leona/Desktop/lista_de_especies_2.xlsx', overwrite = TRUE)

ocorrencias_rivulideos <-
  ocorrencias %>%
  dplyr::filter(species %in% rivulideos)

sf::write_sf(ocorrencias_rivulideos, 'peixes/shp/peixes_ocorrencias_rivulideos.shp', delete_layer = TRUE)

ameacas <- c('CR', 'EN', 'VU')

atributos <-
  atributos_or %>%
  dplyr::select(
    iucn = CAT_IUCN,
    icmbio = `CAT_MMA/ICMBio`,
    mt = CAT_MT,
    go = CAT_GO,
    to = CAT_TO,
    pa = CAT_PA,
    species = BINOMIO,
    endemicas = `ENDÊMICAS.ARAGUAIA.(Dagosta)`,
    longa = MIGRADOR.LONGA.DISTÂNCIA,
    curta = MIGRADOR.CURTA.DISTÂNCIA,
    sedentario = `SEDENTÁRIO`) %>%
  dplyr::mutate(
    iucn = if_else(iucn %in% ameacas, 1, NA_integer_),
    icmbio = if_else(icmbio %in% ameacas, 1, NA_integer_),
    mt = if_else(mt %in% ameacas, 1, NA_integer_),
    go = if_else(go %in% ameacas, 1, NA_integer_),
    to = if_else(to %in% ameacas, 1, NA_integer_),
    pa = if_else(pa %in% ameacas, 1, NA_integer_),
    sp_ameacada = coalesce(iucn, icmbio, mt, go, to, pa)
  ) %>%
  dplyr::select(-iucn, -icmbio, -mt, -go, -to, -pa) %>%
  dplyr::distinct() %>%
  dplyr::mutate(dplyr::across(dplyr::everything(), ~replace_na(., 0)))


ocorrencias_atr <-
  ocorrencias %>%
  dplyr::left_join(atributos %>% dplyr::rename(migradores_longa_dist = longa, migradores_curta_dist = curta)) %>%
  dplyr::select(-indice) %>%
  dplyr::mutate(geometry = as.character(geometry))

openxlsx::write.xlsx(ocorrencias_atr, 'peixes/ocorrencias/peixes_ocorrencias_exportado.xlsx', overwrite = TRUE)


endemicas <- ocorrencias %>% dplyr::filter(species %in% (atributos %>% dplyr::filter(endemicas == 1) %>% dplyr::pull(species)))
longa <- ocorrencias %>% dplyr::filter(species %in% (atributos %>% dplyr::filter(longa == 1) %>% dplyr::pull(species)))
curta <- ocorrencias %>% dplyr::filter(species %in% (atributos %>% dplyr::filter(curta == 1) %>% dplyr::pull(species)))
sedentario <- ocorrencias %>% dplyr::filter(species %in% (atributos %>% dplyr::filter(sedentario == 1) %>% dplyr::pull(species)))
ameacadas <- ocorrencias %>% dplyr::filter(species %in% (atributos %>% dplyr::filter(sp_ameacada == 1) %>% dplyr::pull(species)))

dados <- list(
  total = ocorrencias,
  endemicas = endemicas,
  longa = longa,
  curta = curta,
  sedentario = sedentario,
  ameacada = ameacadas
)


for(i in seq_along(dados)) {

  tipo <- names(dados)[[i]]
  pontos_sf <- dados[[i]]
  intersects <- st_intersects(pontos_sf, bacias)
  num_species <- apply(intersects, 2, function(x) n_distinct(pontos_sf$species[x]))
  bacias$numEspecies <- num_species

  sf::write_sf(bacias, glue::glue('peixes/shp/peixes_riqueza_{tipo}.shp'), delete_layer = TRUE)


}

intersects <- st_intersects(ocorrencias, bacias)
num_species <- apply(intersects, 2, function(x) length(ocorrencias$species[x]))
bacias$numEspecies <- num_species

sf::write_sf(bacias, glue::glue('peixes/shp/peixes_ocorrencias_nativas.shp'), delete_layer = TRUE)
sf::write_sf(ocorrencias, glue::glue('peixes/shp/peixes_ocorrencias_nativas_pontos.shp'), delete_layer = TRUE)


# Ocorrências invasores -------------------------------------------------
ocorrencias_invasor <-
  ocorrencias_invasores %>%
  dplyr::mutate(
    longitude = geometry %>% purrr::map_chr(~eval(parse(text = paste0(.x, '[1]')))),
    latitude = geometry %>% purrr::map_chr(~eval(parse(text = paste0(.x, '[2]'))))) %>%
  sf::st_as_sf(coords = c('longitude', 'latitude'), crs = st_crs(bacias))

ocorrencias_invasor %>%
  dplyr::mutate(geometry = as.character(geometry)) %>%
  openxlsx::write.xlsx(., 'peixes/ocorrencias/peixes_ocorrencias_invasores_exportado.xlsx', overwrite = TRUE)



intersects <- st_intersects(ocorrencias_invasor, bacias)
num_species <- apply(intersects, 2, function(x) length(ocorrencias_invasor$species[x]))
bacias$numEspecies <- num_species

sf::write_sf(bacias, glue::glue('peixes/shp/peixes_ocorrencias_invasores.shp'), delete_layer = TRUE)
sf::write_sf(ocorrencias_invasor, glue::glue('peixes/shp/peixes_ocorrencias_invasores_pontos.shp'), delete_layer = TRUE)

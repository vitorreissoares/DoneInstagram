# =========================================================
# RODADAS E VALIDAÇÃO (ETAPA 2)
# Cada categorização vira uma "rodada": uma pasta em saidas/rodadas/
# com a base classificada, as validações e, depois, os relatórios.
#
#   saidas/rodadas/2026-09-27_a_2026-10-03/
#     rodada.json            período, % analisado, modelo
#     base_classificada.csv  saída da IA
#     validacao.csv          uma linha por validação (a mais recente vale)
# =========================================================

pasta_rodada <- function(id) file.path(PASTA_RODADAS, id)

rodada_existe <- function(id) {
  !is.null(id) && length(id) == 1 && nzchar(id) && file.exists(file.path(pasta_rodada(id), "base_classificada.csv"))
}

criar_rodada <- function(classificados, data_inicio, data_fim, proporcao, modelo) {
  id <- paste0(as.Date(data_inicio), "_a_", as.Date(data_fim))
  pasta <- pasta_rodada(id)
  dir.create(pasta, showWarnings = FALSE, recursive = TRUE)

  write_csv(classificados, file.path(pasta, "base_classificada.csv"), na = "")
  write_json(list(
    id = id,
    inicio = as.character(as.Date(data_inicio)),
    fim = as.character(as.Date(data_fim)),
    proporcao = proporcao,
    modelo = modelo,
    criada_em = format(Sys.time(), "%Y-%m-%d %H:%M"),
    remota = FALSE
  ), file.path(pasta, "rodada.json"), auto_unbox = TRUE, pretty = TRUE)

  pasta
}

# Rodadas existentes, da mais recente para a mais antiga (pela data de início)
listar_rodadas <- function() {
  if (!dir.exists(PASTA_RODADAS)) return(character())
  ids <- list.dirs(PASTA_RODADAS, full.names = FALSE, recursive = FALSE)
  ids <- ids[file.exists(file.path(PASTA_RODADAS, ids, "base_classificada.csv"))]
  if (length(ids) == 0) return(character())
  inicio <- map_chr(ids, \(id) tryCatch(ler_rodada(id)$inicio, error = function(e) "0000-00-00"))
  ids[order(inicio, ids, decreasing = TRUE)]
}

# Nome amigável: "27/09 a 03/10/2026 (rodada)" ou "Semanas 01 a 06 (histórico)"
rotulo_rodada <- function(id) {
  m <- tryCatch(ler_rodada(id), error = function(e) list())
  if (!is.null(m$rotulo)) return(m$rotulo)
  if (is.null(m$inicio)) return(id)
  sprintf("%s a %s", format(as.Date(m$inicio), "%d/%m"), format(as.Date(m$fim), "%d/%m/%Y"))
}

# Exclui a rodada inteira (classificação, validações). A mídia baixada fica em midia/.
excluir_rodada <- function(id) {
  unlink(pasta_rodada(id), recursive = TRUE)
}

ler_rodada <- function(id) {
  read_json(file.path(pasta_rodada(id), "rodada.json"))
}

atualizar_rodada <- function(id, ...) {
  meta <- modifyList(ler_rodada(id), list(...))
  write_json(meta, file.path(pasta_rodada(id), "rodada.json"), auto_unbox = TRUE, pretty = TRUE)
  invisible(meta)
}

ler_classificados <- function(id) {
  read_csv(file.path(pasta_rodada(id), "base_classificada.csv"),
           col_types = cols(.default = col_character()), show_col_types = FALSE) %>%
    mutate(likes = as.numeric(likes), comentarios = as.numeric(comentarios)) %>%
    migrar_formato_antigo() %>%
    mutate(across(starts_with("ia_"), as.integer))
}

# ---------------------------------------------------------
# Rótulos <-> chaves
# ---------------------------------------------------------

# Nomes antigos que mudaram
renomear_rotulo <- function(x) {
  x %>%
    str_replace(regex("^rela[cç][oõ]es (pessoais e )?interpessoais$", ignore_case = TRUE), "Apoio político") %>%
    str_replace(regex("^identidade$", ignore_case = TRUE), "Valores")
}

# ("Conteúdo personalista", "Identidade") -> "pers_valores"
chave_de <- function(categoria, subcategoria) {
  tab <- SUBCATEGORIAS_TAB %>% mutate(c = str_to_lower(categoria), r = str_to_lower(rotulo))
  map2_chr(str_to_lower(coalesce(categoria, "")), str_to_lower(renomear_rotulo(coalesce(subcategoria, ""))),
           \(ca, su) tab$chave[tab$c == ca & tab$r == su][1] %||% NA_character_)
}

rotulo_de <- function(chave) SUBCATEGORIAS_TAB$rotulo[match(chave, SUBCATEGORIAS_TAB$chave)]
categoria_de <- function(chave) SUBCATEGORIAS_TAB$categoria[match(chave, SUBCATEGORIAS_TAB$chave)]

# "pers_valores;pers_apoio" <-> c("pers_valores", "pers_apoio")
juntar_chaves <- function(chaves) paste(chaves, collapse = ";")
separar_chaves <- function(texto) {
  if (is.na(texto) || texto == "") return(character())
  intersect(str_split_1(texto, ";"), CHAVES)
}

# Chaves marcadas (=1) num conjunto de colunas prefixo_<chave> de uma linha
chaves_marcadas <- function(linha, prefixo) {
  cols <- paste0(prefixo, CHAVES)
  v <- unlist(linha[cols])
  CHAVES[!is.na(v) & v == 1]
}

# Rodadas criadas antes da categorização multimodal: tinham uma só categoria e
# subcategoria (da legenda) e validação em validacao_1/validacao_2.
# São convertidas na leitura: a classificação antiga vira a "legenda".
migrar_formato_antigo <- function(d) {
  if (any(startsWith(names(d), "ia_legenda_")) || !"subcategoria" %in% names(d)) return(d)
  chave <- chave_de(d$categoria, d$subcategoria)
  for (k in CHAVES) {
    v <- ifelse(is.na(chave), NA_integer_, as.integer(chave == k))
    d[[paste0("ia_legenda_", k)]] <- v
    d[[paste0("ia_imagem_", k)]] <- NA_integer_
    d[[paste0("ia_transcricao_", k)]] <- NA_integer_
    d[[paste0("ia_sugestao_", k)]] <- v
  }
  if (!"transcricao" %in% names(d)) d$transcricao <- NA_character_
  d
}

# ---------------------------------------------------------
# Validações
# ---------------------------------------------------------
# validacao.csv: uma linha por validação (a mais recente de cada postagem vale)
#   final    subcategorias escolhidas pelo avaliador, ex.: "prog_propostas;pers_apoio"
#            ("" = nenhuma subcategoria se aplica)
#   formato  formato da postagem (o original ou "Produzido por IA")

COLUNAS_VALIDACAO <- c("shortCode", "final", "formato", "avaliador", "validado_em", "origem")

ler_validacoes <- function(id) {
  arquivo <- file.path(pasta_rodada(id), "validacao.csv")
  vazio <- tibble(!!!set_names(rep(list(character()), length(COLUNAS_VALIDACAO)), COLUNAS_VALIDACAO))
  if (!file.exists(arquivo)) return(vazio)
  v <- read_csv(arquivo, col_types = cols(.default = col_character()), show_col_types = FALSE)
  if (!"final" %in% names(v)) v <- migrar_validacoes_antigas(v, id)
  v %>%
    mutate(final = coalesce(final, "")) %>%
    arrange(validado_em) %>%
    group_by(shortCode) %>%
    slice_tail(n = 1) %>%
    ungroup()
}

# validacao_1/validacao_2 ("OK" ou a correção) -> lista de chaves
migrar_validacoes_antigas <- function(v, id) {
  cl <- read_csv(file.path(pasta_rodada(id), "base_classificada.csv"),
                 col_types = cols(.default = col_character()), show_col_types = FALSE)
  v %>%
    left_join(cl %>% select(any_of(c("shortCode", "categoria", "subcategoria"))), by = "shortCode") %>%
    mutate(
      cat_final = if_else(is.na(validacao_1) | validacao_1 == "OK", categoria, validacao_1),
      sub_final = if_else(is.na(validacao_2) | validacao_2 == "OK", subcategoria, validacao_2),
      final = coalesce(chave_de(cat_final, sub_final), "")
    ) %>%
    select(any_of(COLUNAS_VALIDACAO))
}

# final: vetor de chaves (ou texto "a;b")
salvar_validacao <- function(id, shortCode, final, formato,
                             avaliador = "", origem = "app", validado_em = NULL) {
  arquivo <- file.path(pasta_rodada(id), "validacao.csv")
  if (is.list(final)) final <- map_chr(final, juntar_chaves)
  if (length(shortCode) == 1 && length(final) != 1) final <- juntar_chaves(final)  # 0 chaves = ""
  nova <- tibble(shortCode, final = coalesce(final, ""), formato,
                 avaliador = coalesce(avaliador, ""),
                 # Horário em UTC, no mesmo formato da planilha Google, para comparar qual é a mais recente
                 validado_em = validado_em %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
                 origem)
  if (file.exists(arquivo)) {
    antigo <- read_csv(arquivo, col_types = cols(.default = col_character()), show_col_types = FALSE)
    if (!"final" %in% names(antigo)) {
      # Converte o arquivo antigo para o formato novo antes de acrescentar
      write_csv(migrar_validacoes_antigas(antigo, id), arquivo, na = "")
    }
  }
  write_csv(nova, arquivo, append = file.exists(arquivo), na = "")
}

# Uma linha por postagem: classificação da IA (ia_*) + validação humana
#   validada  TRUE/FALSE
#   final_<chave>  0/1 (NA se ainda não validada)
#   categorias / subcategorias  rótulos finais em texto, ex.: "Valores · Apoio político"
base_validada_rodada <- function(id) {
  val <- ler_validacoes(id) %>% select(shortCode, final, fmt = formato, avaliador, validado_em)
  d <- ler_classificados(id) %>%
    select(-any_of(c("final", "avaliador", "validado_em"))) %>%
    left_join(val, by = "shortCode")

  # CSVs importados já validados podem trazer final_<chave>
  importado <- if (all(paste0("final_", CHAVES) %in% names(d))) d[paste0("final_", CHAVES)] else NULL
  validada <- !is.na(d$final)
  for (k in CHAVES) {
    marcado <- map_lgl(d$final, \(f) k %in% separar_chaves(f))
    col <- paste0("final_", k)
    d[[col]] <- ifelse(validada, as.integer(marcado),
                       if (!is.null(importado)) suppressWarnings(as.integer(importado[[col]])) else NA_integer_)
  }
  d %>%
    mutate(
      validada = !is.na(.data[[paste0("final_", CHAVES[1])]]),
      formato = if_else(!is.na(fmt) & fmt != "", fmt, formato),
      subcategorias = pmap_chr(across(all_of(paste0("final_", CHAVES))), \(...) {
        v <- c(...); paste(rotulo_de(CHAVES[!is.na(v) & v == 1]), collapse = " · ")
      }),
      categorias = pmap_chr(across(all_of(paste0("final_", CHAVES))), \(...) {
        v <- c(...); paste(unique(categoria_de(CHAVES[!is.na(v) & v == 1])), collapse = " · ")
      })
    ) %>%
    select(-fmt, -final)
}

progresso_rodada <- function(id) {
  b <- base_validada_rodada(id)
  list(total = nrow(b), feitas = sum(b$validada))
}

# Base validada em formato "longo": uma linha por postagem x subcategoria final
para_longo <- function(d) {
  d %>%
    select(-any_of(c("categoria", "subcategoria"))) %>%
    pivot_longer(all_of(paste0("final_", CHAVES)), names_to = "chave", values_to = "marcada",
                 names_prefix = "final_") %>%
    filter(marcada == 1) %>%
    mutate(categoria = categoria_de(chave), subcategoria = rotulo_de(chave)) %>%
    select(-marcada)
}

# ---------------------------------------------------------
# Acurácia da IA (só postagens já validadas)
# ---------------------------------------------------------
# Para cada fonte (legenda, imagem, transcrição e a sugestão combinada):
#   acuracia  % das subcategorias marcadas pela IA que a validação manteve
#   cobertura % das subcategorias finais que a IA tinha marcado
#   exatas    % de postagens em que a IA acertou exatamente o conjunto final
acuracia <- function(d) {
  d <- d %>% filter(validada)
  final <- as.matrix(d[paste0("final_", CHAVES)])
  fontes <- c(sugestao = "IA combinada", FONTES)
  map(names(fontes), \(f) {
    ia <- as.matrix(d[paste0("ia_", f, "_", CHAVES)])
    disp <- rowSums(!is.na(ia)) > 0
    ia_d <- ia[disp, , drop = FALSE]; fi_d <- final[disp, , drop = FALSE]
    marcadas <- sum(ia_d == 1, na.rm = TRUE)
    acertos <- sum(ia_d == 1 & fi_d == 1, na.rm = TRUE)
    finais <- sum(fi_d == 1, na.rm = TRUE)
    tibble(
      fonte = fontes[[f]], postagens = sum(disp), marcadas, acertos,
      acuracia = if (marcadas > 0) acertos / marcadas else NA_real_,
      cobertura = if (finais > 0) acertos / finais else NA_real_,
      exatas = if (sum(disp) > 0) mean(rowSums(ia_d != fi_d, na.rm = TRUE) == 0) else NA_real_
    )
  }) %>% bind_rows()
}

# Acurácia da sugestão combinada por subcategoria
acuracia_por_subcategoria <- function(d) {
  d <- d %>% filter(validada)
  map(CHAVES, \(k) {
    ia <- d[[paste0("ia_sugestao_", k)]]; fi <- d[[paste0("final_", k)]]
    ok <- !is.na(ia)
    tibble(
      categoria = categoria_de(k), subcategoria = rotulo_de(k),
      ia_marcou = sum(ia[ok] == 1), confirmadas = sum(ia[ok] == 1 & fi[ok] == 1),
      acrescentadas = sum(ia[ok] == 0 & fi[ok] == 1),
      acuracia = if (sum(ia[ok] == 1) > 0) sum(ia[ok] == 1 & fi[ok] == 1) / sum(ia[ok] == 1) else NA_real_
    )
  }) %>% bind_rows()
}

# CSV da base validada (para guardar ou usar fora do app)
exportar_base_validada <- function(id, arquivo) {
  base_validada_rodada(id) %>%
    select(any_of(COLUNAS_SAIDA), validada, categorias, subcategorias, starts_with("final_"),
           starts_with("ia_"), everything()) %>%
    write_csv(arquivo, na = "")
}

# Transforma um CSV já validado (exportado do app ou de versões antigas) numa rodada
importar_csv_validado <- function(arquivos, proporcao = PROPORCAO_TOP_PADRAO, modelo = MODELO_PADRAO) {
  d <- map(arquivos, \(a) read_csv(a, col_types = cols(.default = col_character()), show_col_types = FALSE)) %>%
    bind_rows() %>%
    distinct(shortCode, .keep_all = TRUE) %>%
    mutate(data = as.Date(data), candidato = nome_completo(candidato), semana = calcular_semana(data))
  pasta <- criar_rodada(d %>% mutate(data = as.character(data)), min(d$data), max(d$data), proporcao, modelo)
  id <- basename(pasta)

  # Formato antigo: validacao_1/validacao_2 -> validação no formato novo
  if ("validacao_1" %in% names(d) && !any(startsWith(names(d), "final_"))) {
    v <- d %>% filter(!is.na(validacao_1) & validacao_1 != "") %>%
      select(shortCode, validacao_1, validacao_2, formato) %>%
      mutate(avaliador = "importado", validado_em = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
             origem = "csv importado")
    write_csv(migrar_validacoes_antigas(v, id), file.path(pasta, "validacao.csv"), na = "")
  }
  id
}

# ---------------------------------------------------------
# Todas as rodadas juntas (para o relatório "tudo junto")
# ---------------------------------------------------------

# Postagens validadas de todas as rodadas; se a mesma postagem estiver em duas
# rodadas, vale a da rodada mais recente
base_validada_todas <- function(rodadas = listar_rodadas()) {
  map(rodadas, \(id) base_validada_rodada(id) %>% filter(validada) %>% mutate(rodada = id)) %>%
    bind_rows() %>%
    distinct(shortCode, .keep_all = TRUE)
}

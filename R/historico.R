# =========================================================
# SEMANAS ANTIGAS (relatório final anterior)
# As semanas que estavam dentro do relatório final antigo
# (config/relatorio_final.html) viram uma rodada "histórico",
# já validada, e os textos de cada semana viram períodos salvos.
# Os dados entram no relatório único (botões Semana, Mês, Ano e Tudo).
# A importação acontece uma vez só, quando o app abre.
# =========================================================

ARQUIVO_RELATORIO_FINAL <- "config/relatorio_final.html"
ID_HISTORICO <- "historico_relatorio_final"

ler_texto_arquivo <- function(arquivo) {
  paste(readLines(arquivo, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

# Variáveis JSON embutidas no HTML (ex.: WEEK_CSV_TEXT)
ler_json_embutido <- function(html, nome) {
  linha <- str_match(html, paste0("\\n\\s*const ", nome, " = (.*?);\\n"))[, 2]
  if (is.na(linha)) return(set_names(list(), character()))
  fromJSON(linha, simplifyVector = FALSE)
}

# Lista de semanas do relatório antigo: id, rótulo e período escrito
semanas_relatorio_antigo <- function(html) {
  m <- str_match_all(html, '\\n\\s*"(\\d+)": criarConfigSemana\\("([^"]+)", "([^"]+)"\\)')[[1]]
  tibble(id = m[, 2], rotulo = m[, 3], periodo = m[, 4]) %>% distinct(id, .keep_all = TRUE)
}

importar_historico <- function(arquivo = ARQUIVO_RELATORIO_FINAL) {
  if (!file.exists(arquivo) || dir.exists(pasta_rodada(ID_HISTORICO))) return(invisible(NULL))
  html <- ler_texto_arquivo(arquivo)
  csvs <- ler_json_embutido(html, "WEEK_CSV_TEXT")
  meta <- ler_json_embutido(html, "WEEK_METADATA_FALLBACK")
  if (length(csvs) == 0) return(invisible(NULL))
  semanas <- semanas_relatorio_antigo(html)

  dados <- imap(csvs, \(texto, semana) {
    read_csv(I(texto), col_types = cols(.default = col_character()), show_col_types = FALSE) %>%
      mutate(semana_antiga = semana)
  }) %>%
    bind_rows() %>%
    filter(!is.na(shortCode)) %>%
    distinct(shortCode, .keep_all = TRUE) %>%
    mutate(
      data = as.Date(parse_date_time(data, c("Ymd HMS", "Ymd", "mdY"), quiet = TRUE)),
      candidato = nome_completo(candidato),
      likes = parse_number(likes),
      comentarios = parse_number(comentarios),
      chave = chave_de(categoria, subcategoria)
    ) %>%
    filter(!is.na(data))

  # Base "classificada": sem classificação da IA (só a classificação final publicada)
  classificados <- dados %>%
    transmute(candidato, url, caption, transcricao = NA_character_, likes, shortCode, comentarios,
              semana = calcular_semana(data), data = as.character(data), formato)
  for (col in c(COLUNAS_IA, paste0("ia_sugestao_", CHAVES))) classificados[[col]] <- NA_integer_

  pasta <- pasta_rodada(ID_HISTORICO)
  dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
  write_csv(classificados, file.path(pasta, "base_classificada.csv"), na = "")
  write_csv(tibble(shortCode = dados$shortCode, final = coalesce(dados$chave, ""),
                   formato = dados$formato, avaliador = "relatório final anterior",
                   validado_em = "2026-01-01T00:00:00.000Z", origem = "histórico"),
            file.path(pasta, "validacao.csv"), na = "")
  write_json(list(
    id = ID_HISTORICO, inicio = as.character(min(dados$data)), fim = as.character(max(dados$data)),
    proporcao = PROPORCAO_TOP_PADRAO, modelo = "histórico", historico = TRUE, remota = FALSE,
    rotulo = sprintf("Semanas antigas (%s a %s)", format(min(dados$data), "%d/%m"), format(max(dados$data), "%d/%m/%Y")),
    criada_em = format(Sys.time(), "%Y-%m-%d %H:%M")
  ), file.path(pasta, "rodada.json"), auto_unbox = TRUE, pretty = TRUE)

  # Cada semana antiga vira um período salvo, com o texto publicado
  for (s in unique(dados$semana_antiga)) {
    ds <- dados %>% filter(semana_antiga == s)
    rotulo <- semanas$periodo[semanas$id == s][1] %|NA|% periodo_extenso(min(ds$data), max(ds$data))
    salvar_periodo("periodo", min(ds$data), max(ds$data), rotulo,
                   html = meta[[s]]$analysisHtml %||% NA_character_, origem = "histórico")
  }
  invisible(ID_HISTORICO)
}

`%|NA|%` <- function(a, b) if (length(a) == 0 || is.na(a)) b else a

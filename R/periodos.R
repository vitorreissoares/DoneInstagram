# =========================================================
# PERÍODOS DE ANÁLISE
# O relatório tem os botões Semana, Mês, Ano e Tudo. Cada um mostra o
# trecho mais recente da base (última semana, último mês, último ano
# ou tudo). O pesquisador pode salvar as considerações finais de cada um.
#
# config/periodos.json: uma entrada por texto salvo
#   id      "semana:2026-10-14_2026-10-20", "mes:...", "ano:...", "tudo:..."
#           ("p:..." = análises antigas, por datas)
#   rotulo  como aparece no relatório
#   texto   considerações finais em texto (parágrafos separados por linha em branco)
#   html    o mesmo texto em HTML (usado no relatório)
# =========================================================

ARQUIVO_PERIODOS <- "config/periodos.json"

periodos_vazio <- function() {
  tibble(id = character(), tipo = character(), inicio = character(), fim = character(),
         rotulo = character(), texto = character(), html = character(),
         origem = character(), salvo_em = character())
}

ler_periodos <- function() {
  if (!file.exists(ARQUIVO_PERIODOS)) return(periodos_vazio())
  p <- read_json(ARQUIVO_PERIODOS, simplifyVector = TRUE)
  if (length(p) == 0) return(periodos_vazio())
  p <- as_tibble(p)
  for (col in names(periodos_vazio())) if (!col %in% names(p)) p[[col]] <- NA_character_
  p %>% select(all_of(names(periodos_vazio()))) %>% arrange(inicio)
}

gravar_periodos <- function(p) {
  dir.create(dirname(ARQUIVO_PERIODOS), showWarnings = FALSE)
  write_json(p, ARQUIVO_PERIODOS, pretty = TRUE, na = "null", auto_unbox = TRUE)
}

# tipo: "semana", "mes", "ano", "tudo" (botões do relatório) ou "periodo"
# (análises antigas, por datas). O texto fica preso às datas do período.
id_periodo <- function(tipo, inicio, fim) {
  prefixo <- if (tipo == "periodo") "p" else tipo
  paste0(prefixo, ":", as.Date(inicio), "_", as.Date(fim))
}

# Inclui ou substitui um período (pelo id)
salvar_periodo <- function(tipo, inicio, fim, rotulo, texto = NA_character_, html = NULL,
                           origem = "app") {
  id <- id_periodo(tipo, inicio, fim)
  novo <- tibble(id = id, tipo = tipo, inicio = as.character(as.Date(inicio)),
                 fim = as.character(as.Date(fim)), rotulo = rotulo, texto = texto,
                 html = html %||% (if (is.na(texto)) NA_character_ else html_paragrafos(texto)),
                 origem = origem, salvo_em = format(Sys.time(), "%Y-%m-%d %H:%M"))
  p <- ler_periodos() %>% filter(id != !!id) %>% bind_rows(novo) %>% arrange(inicio)
  gravar_periodos(p)
  invisible(id)
}

excluir_periodo <- function(id) {
  gravar_periodos(ler_periodos() %>% filter(id != !!id))
}

# Texto salvo de um período (ou NULL). Textos que só existem em HTML
# (semanas antigas do relatório final) são convertidos para texto
texto_salvo <- function(id) {
  p <- ler_periodos() %>% filter(id == !!id)
  if (nrow(p) == 0) return(NULL)
  if (!is.na(p$texto) && nzchar(p$texto)) return(p$texto)
  if (!is.na(p$html) && nzchar(p$html)) return(html_para_texto(p$html))
  NULL
}

html_para_texto <- function(html) {
  str_split_1(html, regex("</p>", ignore_case = TRUE)) %>%
    str_remove_all("<[^>]+>") %>%
    map_chr(\(x) textutils_unescape(str_squish(x))) %>%
    discard(~ .x == "") %>%
    paste(collapse = "\n\n")
}

textutils_unescape <- function(x) {
  x %>% str_replace_all(fixed("&quot;"), "\"") %>% str_replace_all(fixed("&#39;"), "'") %>%
    str_replace_all(fixed("&#039;"), "'") %>% str_replace_all(fixed("&lt;"), "<") %>%
    str_replace_all(fixed("&gt;"), ">") %>% str_replace_all(fixed("&amp;"), "&")
}

# ---------------------------------------------------------
# Períodos do relatório (o que os botões Semana/Mês/Ano/Tudo mostram)
# Cada botão mostra o trecho mais recente do que já foi analisado:
# os últimos 7 dias, o último mês e o último ano até a data mais recente
# da base, ou tudo. As datas saem da própria base; não há escolha manual.
# ---------------------------------------------------------

MESES_TITULO <- str_to_title(MESES)

rotulo_mes <- function(data) sprintf("%s de %s", MESES_TITULO[month(data)], year(data))

MODOS_RELATORIO <- c(semana = "Semana", mes = "Mês", ano = "Ano", tudo = "Tudo")

TITULO_MODO <- c(semana = "Última semana", mes = "Último mês", ano = "Último ano", tudo = "Todo o período")

# Início e fim de cada botão, a partir das datas da base
janela_relatorio <- function(datas, modo) {
  datas <- as.Date(datas)
  datas <- datas[!is.na(datas)]
  if (!length(datas)) return(NULL)
  fim <- max(datas)
  inicio <- switch(modo,
                   semana = fim - 6,
                   mes = fim %m-% months(1) + 1,
                   ano = fim %m-% years(1) + 1,
                   tudo = min(datas))
  inicio <- max(inicio, min(datas))  # não começa antes do primeiro dado
  list(modo = modo, inicio = inicio, fim = fim,
       texto_periodo = periodo_extenso(inicio, fim),
       rotulo = paste0(TITULO_MODO[[modo]], ": ", periodo_extenso(inicio, fim)))
}

# Texto salvo para estas datas (id ou NULL): primeiro o do mesmo botão,
# depois qualquer outro com as mesmas datas (ex.: semanas antigas do relatório final)
id_salvo <- function(salvos, modo, inicio, fim) {
  s <- salvos %>% filter(inicio == as.character(!!inicio), fim == as.character(!!fim),
                         (!is.na(html) & nzchar(html)) | (!is.na(texto) & nzchar(texto))) %>%
    arrange(desc(tipo == modo), desc(salvo_em))
  if (nrow(s)) s$id[1] else NULL
}

# Texto automático (só números, sem os lembretes entre [colchetes]) para os
# períodos que não têm texto salvo
analise_automatica <- function(d, rotulo) {
  if (nrow(d) == 0) return("")
  gerar_rascunho(d, rotulo) %>%
    str_remove_all("\\s*\\[[^\\]]*\\]") %>%
    html_paragrafos()
}

# d: base validada (uma linha por postagem) com tudo o que entra no relatório.
# Devolve list(semana, mes, ano, tudo), um período por botão (NULL se não há dados)
periodos_relatorio <- function(d) {
  d <- d %>% mutate(data = as.Date(data))
  salvos <- ler_periodos()
  html_de <- function(id) {
    h <- salvos$html[salvos$id %in% id]
    if (length(h) && !is.na(h[1]) && nzchar(h[1])) h[1] else NULL
  }
  map(set_names(names(MODOS_RELATORIO)), \(modo) {
    j <- janela_relatorio(d$data, modo)
    if (is.null(j)) return(NULL)
    sub <- d %>% filter(data >= j$inicio, data <= j$fim)
    list(id = id_periodo(modo, j$inicio, j$fim), rotulo = j$rotulo,
         inicio = as.character(j$inicio), fim = as.character(j$fim),
         analise = html_de(id_salvo(salvos, modo, j$inicio, j$fim)) %||% analise_automatica(sub, j$texto_periodo))
  })
}

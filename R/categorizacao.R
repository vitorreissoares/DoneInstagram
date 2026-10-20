# =========================================================
# ETAPA 1 — CATEGORIZAÇÃO
# Lê os arquivos coletados, seleciona as postagens mais curtidas
# de cada candidato no período escolhido, baixa imagens e vídeos, transcreve
# os vídeos e classifica legenda, imagem e transcrição com IA.
# =========================================================

library(httr2)
# Os pacotes do tidyverse que o projeto usa (os mesmos que library(tidyverse) carrega)
for (pacote in c("dplyr", "tidyr", "purrr", "stringr", "readr", "lubridate", "tibble")) {
  suppressPackageStartupMessages(library(pacote, character.only = TRUE))
}
library(readxl)
library(jsonlite)

# ---------------------------------------------------------
# 1. Ler os arquivos coletados (Excel do Instagram)
# ---------------------------------------------------------

# Valor especial para arquivos com vários candidatos misturados:
# o candidato é identificado pela coluna "alt" de cada postagem
CANDIDATO_PELA_ALT <- "__alt__"

ler_xlsx <- function(arquivo) {
  dados <- read_excel(arquivo) %>%
    # Tudo como texto para os arquivos se juntarem mesmo com colunas diferentes
    mutate(across(everything(), as.character))

  obrigatorias <- c("caption", "timestamp", "likesCount", "commentsCount",
                    "shortCode", "url", "type")
  faltando <- setdiff(obrigatorias, names(dados))
  if (length(faltando) > 0) {
    stop(basename(arquivo), ": faltam as colunas ", paste(faltando, collapse = ", "))
  }
  dados
}

# Junta os arquivos; `candidatos` diz de quem é cada arquivo (mesma ordem de `arquivos`)
ler_base <- function(arquivos, candidatos) {

  stopifnot(length(arquivos) == length(candidatos))

  map2(arquivos, candidatos, \(arquivo, candidato) {
    dados <- ler_xlsx(arquivo)
    if (identical(candidato, CANDIDATO_PELA_ALT)) {
      dados$candidato <- identificar_candidato(dados$alt %||% rep(NA_character_, nrow(dados)))
    } else {
      dados$candidato <- candidato
    }
    dados
  }) %>%
    bind_rows() %>%
    # A mesma postagem pode vir em dois arquivos (ex.: collab entre perfis)
    distinct(shortCode, .keep_all = TRUE) %>%
    # Links das imagens (carrossel) num só campo, na ordem images/0, images/1, ...
    juntar_urls_imagens() %>%
    mutate(data = as.Date(ymd_hms(timestamp, quiet = TRUE))) %>%
    rename(
      likes = likesCount,
      comentarios = commentsCount,
      formato = type
    ) %>%
    mutate(across(c(likes, comentarios), as.numeric))
}

juntar_urls_imagens <- function(dados) {
  colunas <- grep("^images/[0-9]+$", names(dados), value = TRUE)
  colunas <- colunas[order(as.integer(sub("images/", "", colunas)))]
  dados$urls_imagens <- if (length(colunas) == 0) NA_character_ else
    apply(dados[colunas], 1, \(u) paste(u[!is.na(u) & u != ""], collapse = " | "))
  for (col in c("displayUrl", "videoUrl")) if (!col %in% names(dados)) dados[[col]] <- NA_character_
  dados %>% select(-matches("^images", ignore.case = TRUE))
}

normalizar_nome <- function(x) {
  x %>% stringi::stri_trans_general("Latin-ASCII") %>% str_to_lower() %>% str_squish()
}

# Procura cada padrão de CANDIDATOS na coluna alt (primeira correspondência vence)
identificar_candidato <- function(alt) {
  resultado <- rep(NA_character_, length(alt))
  for (id in names(CANDIDATOS)) {
    achou <- is.na(resultado) &
      str_detect(coalesce(alt, ""), regex(CANDIDATOS[[id]], ignore_case = TRUE))
    resultado[achou] <- id
  }
  nome_completo(resultado)
}

# Sugere o candidato de um arquivo pelo nome do arquivo ou pela coluna alt.
# Devolve "" quando não reconhece (aí a pessoa digita).
sugerir_candidato <- function(arquivo, nome_arquivo = basename(arquivo)) {
  info <- ler_candidatos_info()
  chaves <- tibble(nome = info$nome, chave = normalizar_nome(info$id)) %>%
    bind_rows(tibble(nome = info$nome, chave = normalizar_nome(info$nome))) %>%
    filter(nchar(chave) >= 3)

  nome_arq <- normalizar_nome(nome_arquivo)
  pelo_arquivo <- chaves$nome[str_detect(nome_arq, fixed(chaves$chave))]
  if (length(unique(pelo_arquivo)) == 1) return(pelo_arquivo[1])

  alt <- tryCatch(read_excel(arquivo, n_max = 200)$alt, error = function(e) NULL)
  if (length(alt) > 0) {
    encontrados <- identificar_candidato(alt) %>% discard(is.na)
    if (length(encontrados) > 0) {
      contagem <- sort(table(encontrados), decreasing = TRUE)
      # Mais de um candidato com presença relevante: arquivo misturado
      if (length(contagem) > 1 && contagem[2] >= 0.2 * sum(contagem)) return(CANDIDATO_PELA_ALT)
      return(names(contagem)[1])
    }
  }
  ""
}

calcular_semana <- function(data) {
  n <- as.integer(floor_date(data, unit = "week") - INICIO_SEMANA_01) %/% 7 + 1
  sprintf("semana_%02d", n)
}

# Quantas postagens entram por candidato: proporção arredondada para cima
# (garante ao menos 1 postagem por candidato) ou para baixo
quantas_no_topo <- function(n, proporcao) {
  if (ARREDONDAMENTO_TOP == "baixo") floor(n * proporcao) else ceiling(n * proporcao)
}

# Filtra o período escolhido (alguns dias, uma semana, um mês, um ano...) e mantém
# os X% mais curtidos de CADA candidato em todo esse período.
# Postagens sem legenda também entram: imagens e vídeos são analisados.
preparar_dados <- function(dados, data_inicio, data_fim, proporcao = PROPORCAO_TOP_PADRAO) {

  dados %>%
    filter(
      !is.na(candidato), candidato != "",
      data >= as.Date(data_inicio),
      data <= as.Date(data_fim)
    ) %>%
    mutate(semana = calcular_semana(data)) %>%
    group_by(candidato) %>%
    arrange(desc(likes), .by_group = TRUE) %>%
    filter(row_number() <= quantas_no_topo(n(), proporcao)) %>%
    ungroup() %>%
    arrange(candidato, data)
}

# Resumo para conferência: postagens e selecionadas por candidato no período
resumo_selecao <- function(dados, selecionados, data_inicio, data_fim) {
  dados %>%
    filter(!is.na(candidato), candidato != "",
           data >= as.Date(data_inicio), data <= as.Date(data_fim)) %>%
    group_by(candidato) %>%
    summarise(postagens = n(), primeira = min(data), ultima = max(data), .groups = "drop") %>%
    left_join(count(selecionados, candidato, name = "selecionadas"), by = "candidato") %>%
    mutate(selecionadas = coalesce(selecionadas, 0L))
}

# ---------------------------------------------------------
# 2. Chamada à IA (OpenRouter)
# ---------------------------------------------------------

# A chave pode ficar salva na pasta do projeto (config/chave_openrouter.txt, pelo app)
# ou no .Renviron do computador. "Apagar chave" remove dos dois lugares,
# para a pasta poder ser compartilhada sem a chave.
ARQUIVO_CHAVE <- "config/chave_openrouter.txt"
arquivo_renviron <- function() Sys.getenv("R_ENVIRON_USER", path.expand("~/.Renviron"))

carregar_chave <- function() {
  if (file.exists(ARQUIVO_CHAVE)) {
    chave <- str_trim(paste(readLines(ARQUIVO_CHAVE, warn = FALSE), collapse = ""))
    if (nzchar(chave)) Sys.setenv(OPENROUTER_API_KEY = chave)
  }
  invisible(Sys.getenv("OPENROUTER_API_KEY"))
}

salvar_chave <- function(chave) {
  chave <- str_trim(chave)
  stopifnot(nzchar(chave))
  dir.create(dirname(ARQUIVO_CHAVE), showWarnings = FALSE)
  writeLines(chave, ARQUIVO_CHAVE)
  Sys.setenv(OPENROUTER_API_KEY = chave)
}

# Onde a chave atual está guardada: "projeto", "renviron", "sessao" ou "" (nenhuma)
origem_chave <- function() {
  if (Sys.getenv("OPENROUTER_API_KEY") == "") return("")
  if (file.exists(ARQUIVO_CHAVE)) return("projeto")
  ren <- arquivo_renviron()
  if (file.exists(ren) && any(grepl("^\\s*OPENROUTER_API_KEY\\s*=", readLines(ren, warn = FALSE)))) return("renviron")
  "sessao"
}

apagar_chave <- function() {
  if (file.exists(ARQUIVO_CHAVE)) file.remove(ARQUIVO_CHAVE)
  ren <- arquivo_renviron()
  if (file.exists(ren)) {
    linhas <- readLines(ren, warn = FALSE)
    manter <- !grepl("^\\s*OPENROUTER_API_KEY\\s*=", linhas)
    if (!all(manter)) writeLines(linhas[manter], ren)
  }
  Sys.unsetenv("OPENROUTER_API_KEY")
}

# "sk-or-v1-...abcd" -> "••••abcd" (para mostrar sem revelar a chave)
chave_mascarada <- function() {
  k <- Sys.getenv("OPENROUTER_API_KEY")
  if (k == "") "" else paste0("••••", substr(k, nchar(k) - 3, nchar(k)))
}

# "conteudo" pode ser um texto ou uma lista de partes (texto, imagem, áudio)
chamar_ia <- function(conteudo, modelo, timeout = 300) {

  chave <- Sys.getenv("OPENROUTER_API_KEY")
  if (chave == "") {
    stop("Chave do OpenRouter não encontrada. Informe a chave na aba 1 (Categorização), ",
         "no quadro \"Chave da IA\".")
  }

  resposta <- request("https://openrouter.ai/api/v1/chat/completions") |>
    req_headers(Authorization = paste("Bearer", chave)) |>
    req_body_json(list(
      model = modelo,
      messages = list(list(role = "user", content = conteudo))
    )) |>
    req_timeout(timeout) |>
    # Erros temporários (limite de uso, servidor fora) são repetidos com espera crescente
    req_retry(
      max_tries = 6,
      is_transient = \(resp) resp_status(resp) %in% c(408, 429, 500, 502, 503, 504),
      backoff = \(tentativa) min(60, 5 * 2^(tentativa - 1))
    ) |>
    req_perform()

  conteudo <- resp_body_json(resposta)$choices[[1]]$message$content
  if (is.null(conteudo)) "" else trimws(conteudo)
}

ler_texto <- function(arquivo) {
  paste(readLines(arquivo, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

# Prompt de uma fonte ("legenda", "imagem" ou "transcricao")
montar_prompt <- function(fonte, texto = "") {
  ler_texto(PROMPTS[[fonte]]) %>%
    sub("{definicoes}", ler_texto(PROMPTS$definicoes), x = ., fixed = TRUE) %>%
    sub("{instrucao}", ler_texto(PROMPTS$instrucao), x = ., fixed = TRUE) %>%
    sub("{texto}", texto, x = ., fixed = TRUE)
}

vazio_rotulos <- function() set_names(rep(NA_integer_, length(CHAVES)), CHAVES)

# Converte a resposta da IA ({"prog_pautas": 0, ...}) num vetor 0/1 com as 10 chaves.
# Resposta fora do formato -> NA (é pedida de novo)
ler_rotulos <- function(resposta) {
  json <- str_extract(resposta %||% "", "\\{[\\s\\S]*\\}")
  if (is.na(json)) return(vazio_rotulos())
  lista <- tryCatch(fromJSON(json), error = function(e) NULL)
  if (is.null(lista)) return(vazio_rotulos())
  names(lista) <- normalizar_nome(names(lista))
  valores <- map_int(CHAVES, \(k) {
    v <- suppressWarnings(as.integer(lista[[k]] %||% NA))
    if (length(v) == 1 && v %in% c(0L, 1L)) v else NA_integer_
  })
  if (anyNA(valores)) vazio_rotulos() else set_names(valores, CHAVES)
}

# Pede a classificação até obter uma resposta válida (até 3 vezes)
classificar_conteudo <- function(conteudo, modelo) {
  for (tentativa in 1:3) {
    rotulos <- ler_rotulos(chamar_ia(conteudo, modelo))
    if (!anyNA(rotulos)) return(rotulos)
    Sys.sleep(2)
  }
  vazio_rotulos()
}

texto_vazio <- function(texto) {
  is.na(texto) || trimws(texto) == "" || texto %in% c("[SEM ÁUDIO]", "[SEM FALA]")
}

classificar_legenda <- function(legenda, modelo) {
  if (texto_vazio(legenda)) return(vazio_rotulos())
  classificar_conteudo(montar_prompt("legenda", legenda), modelo)
}

classificar_transcricao <- function(transcricao, modelo) {
  if (texto_vazio(transcricao)) return(vazio_rotulos())
  classificar_conteudo(montar_prompt("transcricao", transcricao), modelo)
}

imagem_data_uri <- function(arquivo) {
  paste0("data:image/jpeg;base64,",
         base64_enc(readBin(arquivo, "raw", file.info(arquivo)$size)) %>% str_remove_all("\n"))
}

# Todas as imagens da postagem; carrosséis grandes vão em lotes e o resultado
# é combinado (a subcategoria vale 1 se aparecer em qualquer lote)
classificar_imagens <- function(shortCode, modelo) {
  arquivos <- arquivos_imagens(shortCode)
  if (length(arquivos) == 0) return(vazio_rotulos())
  lotes <- split(arquivos, ceiling(seq_along(arquivos) / MAX_IMAGENS_POR_REQUISICAO))
  resultados <- map(lotes, \(lote) {
    partes <- c(
      list(list(type = "text", text = montar_prompt("imagem"))),
      map(lote, \(a) list(type = "image_url", image_url = list(url = imagem_data_uri(a))))
    )
    classificar_conteudo(partes, modelo)
  })
  m <- do.call(rbind, resultados)
  if (anyNA(m)) return(vazio_rotulos())
  set_names(as.integer(apply(m, 2, max)), CHAVES)
}

# ---------------------------------------------------------
# 3. Imagens e vídeos
#    Imagem única: midia/postagens/SHORTCODE.jpg
#    Carrossel:    midia/postagens/SHORTCODE_1.jpg, SHORTCODE_2.jpg, ...
#    Vídeo:        midia/videos/SHORTCODE.mp4 (+ capa em postagens/SHORTCODE.jpg)
# ---------------------------------------------------------

criar_pastas_midia <- function() {
  for (p in c(PASTA_IMAGENS, PASTA_VIDEOS, PASTA_AUDIOS)) dir.create(p, showWarnings = FALSE, recursive = TRUE)
}

arquivos_imagens <- function(shortCode) {
  arquivos <- list.files(PASTA_IMAGENS, full.names = TRUE,
                         pattern = paste0("^", str_escape(shortCode), "(_[0-9]+)?\\.jpg$"))
  ordem <- suppressWarnings(as.integer(str_match(arquivos, "_([0-9]+)\\.jpg$")[, 2]))
  arquivos[order(coalesce(ordem, 0L))]
}

arquivo_video <- function(shortCode) {
  v <- file.path(PASTA_VIDEOS, paste0(shortCode, ".mp4"))
  if (file.exists(v)) v else NA_character_
}

baixar_arquivo <- function(url, destino) {
  if (file.exists(destino) && file.size(destino) > 0) return("já existia")
  if (is.na(url) || url == "") return("sem url")
  status <- tryCatch({
    request(url) |>
      req_user_agent("Mozilla/5.0") |>
      req_timeout(120) |>
      req_retry(max_tries = 3) |>
      req_perform(path = destino)
    "ok"
  }, error = function(e) {
    if (file.exists(destino)) file.remove(destino)
    paste("erro:", conditionMessage(e))
  })
  Sys.sleep(runif(1, min = 0.5, max = 1.5))
  status
}

# Baixa imagens e vídeo de uma postagem; devolve o registro dos downloads
baixar_midia <- function(post) {
  criar_pastas_midia()
  sc <- post$shortCode
  tipo <- post$formato %||% ""

  if (tipo == "Sidecar") {
    urls <- str_split_1(coalesce(post$urls_imagens, ""), fixed(" | "))
    urls <- urls[urls != ""]
    if (length(urls) == 0) urls <- post$displayUrl
  } else if (tipo == "Image" || (tipo == "Video" && BAIXAR_CAPAS_VIDEOS)) {
    urls <- post$displayUrl
  } else {
    urls <- character(0)
  }
  urls <- urls[!is.na(urls) & urls != ""]
  nomes <- if (length(urls) == 1) paste0(sc, ".jpg") else paste0(sc, "_", seq_along(urls), ".jpg")

  registro <- map2(urls, nomes, \(u, nome) {
    destino <- file.path(PASTA_IMAGENS, nome)
    tibble(shortCode = sc, arquivo = destino, status = baixar_arquivo(u, destino))
  })
  if (tipo == "Video") {
    destino <- file.path(PASTA_VIDEOS, paste0(sc, ".mp4"))
    registro <- c(registro, list(tibble(shortCode = sc, arquivo = destino,
                                        status = baixar_arquivo(post$videoUrl, destino))))
  }
  log <- bind_rows(registro, tibble(shortCode = character(), arquivo = character(), status = character()))
  if (nrow(log) > 0) {
    arquivo_log <- file.path(PASTA_MIDIA, "log_downloads.csv")
    write_csv(log %>% mutate(quando = format(Sys.time())), arquivo_log, append = file.exists(arquivo_log))
  }
  log
}

# Extrai o áudio do vídeo (pacote av) e pede a transcrição ao modelo de áudio
# Extração do áudio dos vídeos: pelo pacote av ou, se ele não estiver
# instalado (ex.: programa no Mac com chip Apple), pelo programa ffmpeg
programa_ffmpeg <- function() {
  f <- Sys.which("ffmpeg")
  if (nzchar(f)) unname(f) else NA_character_
}

pode_extrair_audio <- function() requireNamespace("av", quietly = TRUE) || !is.na(programa_ffmpeg())

# Devolve TRUE se gravou o áudio e FALSE se o vídeo não tem som
extrair_audio <- function(video, audio) {
  if (requireNamespace("av", quietly = TRUE)) {
    info <- tryCatch(av::av_media_info(video), error = function(e) NULL)
    if (is.null(info) || is.null(info$audio) || NROW(info$audio) == 0) return(FALSE)
    av::av_audio_convert(video, audio, channels = 1, sample_rate = 16000,
                         bit_rate = 48000, verbose = FALSE)
    return(TRUE)
  }
  ffmpeg <- programa_ffmpeg()
  if (is.na(ffmpeg)) {
    stop("Para transcrever vídeos, instale o pacote av: install.packages(\"av\")")
  }
  saida <- suppressWarnings(system2(ffmpeg, c("-hide_banner", "-y", "-i", shQuote(video), "-vn", "-ac", "1",
                                              "-ar", "16000", "-b:a", "48k", shQuote(audio)),
                                    stdout = TRUE, stderr = TRUE))
  if (file.exists(audio) && file.info(audio)$size > 0) return(TRUE)
  if (any(grepl("does not contain any stream|matches no streams", saida))) return(FALSE)
  stop("Não foi possível extrair o áudio do vídeo: ", paste(tail(saida, 3), collapse = " "))
}

transcrever_video <- function(shortCode, modelo = MODELO_TRANSCRICAO) {
  video <- arquivo_video(shortCode)
  if (is.na(video)) return(NA_character_)

  audio <- file.path(PASTA_AUDIOS, paste0(shortCode, ".mp3"))
  if (!file.exists(audio) && !extrair_audio(video, audio)) return("[SEM ÁUDIO]")
  conteudo <- list(
    list(type = "text", text = ler_texto(PROMPTS$transcrever)),
    list(type = "input_audio", input_audio = list(
      data = base64_enc(readBin(audio, "raw", file.info(audio)$size)) %>% str_remove_all("\n"),
      format = "mp3"
    ))
  )
  texto <- chamar_ia(conteudo, modelo)
  if (texto == "") NA_character_ else texto
}

# ---------------------------------------------------------
# 4. Classificar a base inteira (com cache para retomar)
# ---------------------------------------------------------

colunas_fonte <- function(fonte) paste0("ia_", fonte, "_", CHAVES)
COLUNAS_IA <- unlist(map(names(FONTES), colunas_fonte))

ler_cache <- function() {
  if (!file.exists(ARQUIVO_CACHE)) return(tibble(shortCode = character()))
  read_csv(ARQUIVO_CACHE, col_types = cols(.default = col_character()), show_col_types = FALSE) %>%
    group_by(shortCode) %>% slice_tail(n = 1) %>% ungroup() %>%
    mutate(across(any_of(COLUNAS_IA), as.integer))
}

salvar_no_cache <- function(linha) {
  dir.create(dirname(ARQUIVO_CACHE), showWarnings = FALSE, recursive = TRUE)
  linha <- linha %>% mutate(across(everything(), as.character), quando = format(Sys.time()))
  if (file.exists(ARQUIVO_CACHE)) {
    # mantém as colunas na mesma ordem do arquivo
    cab <- names(read_csv(ARQUIVO_CACHE, n_max = 0, show_col_types = FALSE))
    for (col in setdiff(cab, names(linha))) linha[[col]] <- NA_character_
    write_csv(linha[cab], ARQUIVO_CACHE, append = TRUE, na = "")
  } else {
    write_csv(linha, ARQUIVO_CACHE, na = "")
  }
}

# Sugestão combinada da IA: subcategorias marcadas por pelo menos metade
# das fontes disponíveis (legenda, imagem, transcrição)
sugestao_combinada <- function(dados) {
  for (k in CHAVES) {
    m <- as.matrix(dados[paste0("ia_", names(FONTES), "_", k)])
    n <- rowSums(!is.na(m))
    soma <- rowSums(m, na.rm = TRUE)
    dados[[paste0("ia_sugestao_", k)]] <- ifelse(n == 0, NA_integer_, as.integer(soma / n >= 0.5))
  }
  dados
}

# Fontes que ainda faltam classificar numa postagem (as que ela tem e ainda não foram feitas)
fontes_pendentes <- function(post, cache_linha, fontes) {
  transcricao <- if (nrow(cache_linha) > 0) cache_linha$transcricao %||% NA_character_ else NA_character_
  sem_fala <- !is.na(transcricao) && transcricao %in% c("[SEM ÁUDIO]", "[SEM FALA]")
  esperadas <- c(
    legenda = !texto_vazio(post$caption),
    imagem = length(arquivos_imagens(post$shortCode)) > 0,
    transcricao = !is.na(arquivo_video(post$shortCode)) || !texto_vazio(transcricao)
  )
  feitas <- map_lgl(names(FONTES), \(f) {
    cols <- colunas_fonte(f)
    nrow(cache_linha) > 0 && all(cols %in% names(cache_linha)) && !anyNA(unlist(cache_linha[cols]))
  }) %>% set_names(names(FONTES))
  feitas["transcricao"] <- feitas["transcricao"] || sem_fala
  intersect(fontes, names(FONTES)[esperadas & !feitas])
}

# modelos: list(texto = , imagem = , transcricao = )
# fontes: quais fontes analisar (por padrão as três)
# progresso: função opcional chamada a cada passo, progresso(i, total, mensagem)
classificar_base <- function(dados, modelos = list(texto = MODELO_PADRAO, imagem = MODELO_PADRAO,
                                                   transcricao = MODELO_TRANSCRICAO),
                             fontes = names(FONTES), baixar = TRUE, progresso = NULL) {
  cache <- ler_cache()
  total <- nrow(dados)
  avisar <- function(i, msg) if (is.function(progresso)) progresso(i, total, msg)
  linhas <- vector("list", total)

  for (i in seq_len(total)) {
    post <- dados[i, ]
    sc <- post$shortCode
    anterior <- cache %>% filter(shortCode == sc)

    pendentes <- fontes_pendentes(post, anterior, fontes)
    linha <- if (nrow(anterior) > 0) anterior else tibble(shortCode = sc)
    for (col in c("transcricao", COLUNAS_IA)) if (!col %in% names(linha)) linha[[col]] <- NA

    if (length(pendentes) == 0) {
      avisar(i, "já classificada (cache)")
    } else {
      if (baixar && any(c("imagem", "transcricao") %in% fontes)) {
        avisar(i, "baixando imagens e vídeo")
        baixar_midia(post)
        pendentes <- fontes_pendentes(post, anterior, fontes)
      }
      if ("transcricao" %in% pendentes && is.na(linha$transcricao) && !is.na(arquivo_video(sc))) {
        avisar(i, "transcrevendo o vídeo")
        linha$transcricao <- transcrever_video(sc, modelos$transcricao)
      }
      if ("legenda" %in% pendentes) {
        avisar(i, "classificando a legenda")
        linha[colunas_fonte("legenda")] <- as.list(classificar_legenda(post$caption, modelos$texto))
      }
      if ("imagem" %in% pendentes) {
        avisar(i, "classificando as imagens")
        linha[colunas_fonte("imagem")] <- as.list(classificar_imagens(sc, modelos$imagem))
      }
      if ("transcricao" %in% pendentes) {
        avisar(i, "classificando a transcrição")
        linha[colunas_fonte("transcricao")] <- as.list(classificar_transcricao(linha$transcricao, modelos$texto))
      }
      salvar_no_cache(linha %>% select(shortCode, transcricao, all_of(COLUNAS_IA)))
    }
    linhas[[i]] <- linha %>% select(shortCode, transcricao, all_of(COLUNAS_IA)) %>%
      mutate(transcricao = as.character(transcricao), across(all_of(COLUNAS_IA), as.integer))
  }

  resultado <- bind_rows(linhas)
  dados %>%
    select(-any_of(c("transcricao", COLUNAS_IA))) %>%
    left_join(resultado, by = "shortCode") %>%
    mutate(
      n_imagens = map_int(shortCode, \(s) length(arquivos_imagens(s))),
      tem_video = map_lgl(shortCode, \(s) !is.na(arquivo_video(s))),
      data = as.character(data)
    ) %>%
    sugestao_combinada() %>%
    select(any_of(COLUNAS_SAIDA), any_of(c("videoUrl", "displayUrl", "urls_imagens", "n_imagens", "tem_video")),
           starts_with("ia_"))
}

# ---------------------------------------------------------
# 5. Tudo de uma vez, sem a interface (uso no console)
# ---------------------------------------------------------
# Exemplo:
#   source("R/carregar.R")
#   rodar_categorizacao(c("dados/lula.xlsx", "dados/cury.xlsx"), c("Lula", "Augusto Cury"),
#                       "2026-09-27", "2026-10-03")

rodar_categorizacao <- function(arquivos, candidatos, data_inicio, data_fim,
                                proporcao = PROPORCAO_TOP_PADRAO, modelo = MODELO_PADRAO) {

  dados <- ler_base(arquivos, candidatos) %>%
    preparar_dados(data_inicio, data_fim, proporcao)

  message(nrow(dados), " postagens para classificar.")

  classificados <- classificar_base(
    dados, list(texto = modelo, imagem = modelo, transcricao = MODELO_TRANSCRICAO),
    progresso = \(i, n, msg) message(sprintf("[%d/%d] %s", i, n, msg))
  )

  pasta <- criar_rodada(classificados, data_inicio, data_fim, proporcao, modelo)
  message("Pronto! Rodada salva em ", pasta)
  invisible(pasta)
}

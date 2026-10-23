# =========================================================
# VALIDAÇÃO COMPARTILHADA (Planilha Google + Apps Script)
# O app envia as postagens da rodada para a planilha e,
# depois, traz de volta as validações feitas pelo link.
# =========================================================

ARQUIVO_CONFIG_REMOTA <- "config/validacao_remota.json"

ler_config_remota <- function() {
  if (!file.exists(ARQUIVO_CONFIG_REMOTA)) return(list(url = "", token = ""))
  read_json(ARQUIVO_CONFIG_REMOTA)
}

salvar_config_remota <- function(url = ler_config_remota()$url, token = ler_config_remota()$token) {
  write_json(list(url = str_trim(url %||% ""), token = str_trim(token %||% "")),
             ARQUIVO_CONFIG_REMOTA, auto_unbox = TRUE, pretty = TRUE)
}

# Token criado automaticamente na primeira vez (vai embutido no Codigo.gs)
token_remoto <- function() {
  cfg <- ler_config_remota()
  if (nzchar(cfg$token %||% "")) return(cfg$token)
  token <- paste(sample(c(letters, LETTERS, 0:9), 24, replace = TRUE), collapse = "")
  salvar_config_remota(cfg$url, token)
  token
}

# Codigo.gs já com o token preenchido, pronto para colar no Apps Script
codigo_apps_script <- function() {
  ler_texto(arquivo_app("apps_script/Codigo.gs")) %>%
    sub("'TROQUE-ESTE-TOKEN'", paste0("'", token_remoto(), "'"), x = ., fixed = TRUE)
}

remota_configurada <- function() {
  cfg <- ler_config_remota()
  nzchar(cfg$url %||% "") && nzchar(cfg$token %||% "")
}

# Interpreta a resposta do Apps Script e transforma {ok: false} em erro
resposta_remota <- function(req) {
  resp <- tryCatch(
    req |> req_timeout(120) |> req_retry(max_tries = 3) |> req_perform(),
    error = function(e) stop("não consegui abrir o link da planilha. Confira se ele foi copiado inteiro ",
                             "(termina em /exec) e se o computador está conectado à internet.", call. = FALSE)
  )
  corpo <- tryCatch(resp_body_json(resp, check_type = FALSE, simplifyVector = TRUE),
                    error = function(e) stop("a planilha não respondeu como esperado. ",
                                             "Confira se o link termina em /exec e se a implantação ",
                                             "está com acesso para \"Qualquer pessoa\"."))
  if (!isTRUE(corpo$ok)) {
    erro <- corpo$erro %||% "resposta inesperada."
    if (grepl("Token inválido", erro, fixed = TRUE)) {
      stop("a planilha já está ligada a outro computador (ou a outra instalação do programa). ",
           "Para autorizar este: no Apps Script, escolha a função autorizarOutroComputador no topo ",
           "do editor e clique em Executar. Depois, clique de novo em Conectar e testar. ",
           "Se o código do Apps Script for de uma versão antiga, cole o Codigo.gs novo e publique uma nova versão ",
           "(Implantar → Gerenciar implantações → Editar → Versão: Nova versão).", call. = FALSE)
    }
    if (grepl("Ação desconhecida", erro, fixed = TRUE)) {
      stop("o código do Apps Script está desatualizado. Cole o Codigo.gs e o Validador.html novos e publique uma ",
           "nova versão (Implantar → Gerenciar implantações → Editar → Versão: Nova versão).", call. = FALSE)
    }
    stop("Planilha Google: ", erro, call. = FALSE)
  }
  corpo
}

# Postagens da rodada + o que a IA marcou em cada fonte + validações já feitas no app
corpo_envio_google <- function(id, token) {
  feitas <- ler_validacoes(id) %>% select(shortCode, final, formato_validado = formato, avaliador, validado_em)
  cl <- ler_classificados(id)
  ia_texto <- function(prefixo) map_chr(seq_len(nrow(cl)), \(i) {
    linha <- cl[i, ]
    if (all(is.na(unlist(linha[paste0(prefixo, CHAVES)])))) "" else juntar_chaves(chaves_marcadas(linha, prefixo))
  })
  fontes <- map_chr(seq_len(nrow(cl)), \(i) {
    juntar_chaves(names(FONTES)[map_lgl(names(FONTES), \(f) !all(is.na(unlist(cl[i, paste0("ia_", f, "_", CHAVES)]))))])
  })
  linhas <- cl %>%
    mutate(fontes = fontes,
           ia_legenda = ia_texto("ia_legenda_"), ia_imagem = ia_texto("ia_imagem_"),
           ia_transcricao = ia_texto("ia_transcricao_"), ia_sugestao = ia_texto("ia_sugestao_")) %>%
    left_join(feitas, by = "shortCode") %>%
    transmute(candidato, url, caption, transcricao, likes, comentarios, data, semana, shortCode,
              formato_original = formato, fontes, ia_legenda, ia_imagem, ia_transcricao, ia_sugestao,
              final, formato = formato_validado, avaliador, validado_em) %>%
    mutate(across(everything(), \(x) coalesce(as.character(x), "")))
  toJSON(list(token = token, acao = "enviar", rodada = id, linhas = linhas,
              subcategorias = SUBCATEGORIAS_TAB),
         auto_unbox = TRUE, dataframe = "rows")
}

# Envia as postagens da rodada (as que já estão lá são mantidas, com suas validações)
enviar_rodada_google <- function(id) {
  cfg <- ler_config_remota()
  corpo <- resposta_remota(
    request(cfg$url) |> req_body_raw(corpo_envio_google(id, cfg$token), type = "text/plain")
  )
  atualizar_rodada(id, remota = TRUE)
  corpo
}

# total, feitas e quantas cada avaliador fez (rodada ativa da planilha)
status_google <- function() {
  cfg <- ler_config_remota()
  resposta_remota(request(cfg$url) |> req_url_query(acao = "status", token = cfg$token))
}

# Traz as validações da planilha para a rodada local; devolve quantas eram novas
sincronizar_google <- function(id) {
  cfg <- ler_config_remota()
  corpo <- resposta_remota(
    request(cfg$url) |> req_url_query(acao = "exportar", token = cfg$token, rodada = id)
  )
  importar_validacoes_google(id, corpo$linhas)
}

importar_validacoes_google <- function(id, linhas) {
  remotas <- as_tibble(linhas %||% tibble())
  if (nrow(remotas) == 0 || !"validado_em" %in% names(remotas)) return(0L)

  remotas <- remotas %>% filter(validado_em != "")
  locais <- ler_validacoes(id)
  novas <- remotas %>%
    anti_join(locais %>% select(shortCode, validado_em), by = c("shortCode", "validado_em"))

  if (nrow(novas) > 0) {
    salvar_validacao(id, novas$shortCode, coalesce(novas$final, ""), novas$formato,
                     avaliador = novas$avaliador, origem = "planilha google",
                     validado_em = novas$validado_em)
  }
  nrow(novas)
}

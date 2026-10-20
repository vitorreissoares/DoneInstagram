# Carrega configurações e funções do projeto (usado pelo app e no console)
#
# PASTA_APP: onde estão os arquivos do programa (R/, prompts/, templates/...).
# No programa instalado, os dados de cada pessoa (config/, saidas/, midia/,
# assets/) ficam em outra pasta, indicada em DONEINSTAGRAM_DADOS.
if (!exists("PASTA_APP")) PASTA_APP <- normalizePath(Sys.getenv("DONEINSTAGRAM_APP", getwd()))
arquivo_app <- function(...) file.path(PASTA_APP, ...)

for (arquivo in c("R/config.R", "R/categorizacao.R", "R/rodadas.R", "R/validacao_remota.R",
                  "R/relatorio.R", "R/periodos.R", "R/historico.R")) {
  source(arquivo_app(arquivo), encoding = "UTF-8", local = environment())
}

# Passa a trabalhar na pasta de dados (se houver uma). Na primeira vez, copia para
# ela as configurações e imagens iniciais do programa, sem sobrescrever nada.
usar_pasta_dados <- function(pasta = Sys.getenv("DONEINSTAGRAM_DADOS")) {
  if (!nzchar(pasta)) return(invisible(getwd()))
  dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
  pessoais <- c("chave_openrouter.txt", "validacao_remota.json")   # nunca vêm do programa
  for (sub in c("config", "assets")) {
    origem <- arquivo_app(sub)
    if (normalizePath(origem, mustWork = FALSE) == normalizePath(file.path(pasta, sub), mustWork = FALSE)) next
    for (a in list.files(origem, recursive = TRUE)) {
      destino <- file.path(pasta, sub, a)
      if (basename(a) %in% pessoais || file.exists(destino)) next
      dir.create(dirname(destino), recursive = TRUE, showWarnings = FALSE)
      file.copy(file.path(origem, a), destino)
    }
  }
  setwd(pasta)
  invisible(pasta)
}

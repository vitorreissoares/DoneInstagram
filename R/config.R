# =========================================================
# CONFIGURAÇÕES DO MONITORAMENTO
# Edite aqui o que muda de uma rodada para outra.
# =========================================================

# Modelo usado no OpenRouter
MODELO_PADRAO <- "openai/gpt-5.6-luna"
# Como o modelo aparece escrito no texto de metodologia do relatório
MODELO_ROTULO <- "GPT-5.6 Luna"

# Domingo que inicia a "semana_01" (as semanas vão de domingo a sábado)
INICIO_SEMANA_01 <- as.Date("2026-08-16")

# Percentual de postagens mais curtidas de cada candidato, no período escolhido na aba 1
PROPORCAO_TOP_PADRAO <- 0.20
# "cima": 20% de 7 postagens = 2 (garante ao menos 1 por candidato)
# "baixo": 20% de 7 postagens = 1 (pode zerar candidatos com poucas postagens)
ARREDONDAMENTO_TOP <- "cima"

# Candidatos (nome, partido, intenção de voto, seguidores, foto) ficam em
# config/candidatos.csv e podem ser editados pelo app.
#
# Os padrões abaixo só servem para SUGERIR o candidato de cada arquivo
# (pela coluna "alt") e para arquivos que misturam vários candidatos.
# id em config/candidatos.csv  =  texto procurado na coluna "alt"
CANDIDATOS <- c(
  "Renan"  = "Renan",
  "Flavio" = "Bolsonaro",
  "Lula"   = "Lula",
  "Cury"   = "Cury",
  "Caiado" = "Caiado"
)

# ---------------------------------------------------------
# Categorias e subcategorias
# ---------------------------------------------------------
# Cada postagem pode receber quantas subcategorias forem necessárias, dos dois tipos ao mesmo tempo.
# "chave" é o nome usado pela IA (JSON) e nas colunas da base; não mude as chaves.
# "rotulo" é o que aparece no app e nos relatórios (pode mudar).
SUBCATEGORIAS_TAB <- tibble::tribble(
  ~chave,              ~categoria,              ~rotulo,
  "prog_pautas",       "Conteúdo programático", "Pautas e problemas públicos",
  "prog_propostas",    "Conteúdo programático", "Propostas e soluções",
  "prog_prestacao",    "Conteúdo programático", "Prestação de contas",
  "prog_mobilizacao",  "Conteúdo programático", "Mobilização política",
  "prog_negativa",     "Conteúdo programático", "Campanha negativa",
  "pers_competencia",  "Conteúdo personalista", "Competência",
  "pers_valores",      "Conteúdo personalista", "Valores",
  "pers_vida_privada", "Conteúdo personalista", "Vida privada",
  "pers_apoio",        "Conteúdo personalista", "Apoio político",
  "pers_negativa",     "Conteúdo personalista", "Campanha negativa"
)
CHAVES <- SUBCATEGORIAS_TAB$chave
CATEGORIAS <- c("Conteúdo personalista", "Conteúdo programático")
SUBCATEGORIAS <- split(SUBCATEGORIAS_TAB$rotulo, SUBCATEGORIAS_TAB$categoria)

# Fontes analisadas pela IA em cada postagem
FONTES <- c(legenda = "Legenda", imagem = "Imagem", transcricao = "Vídeo (transcrição)")

# Modelos (OpenRouter). O de imagem precisa aceitar imagens; o de transcrição, áudio.
MODELO_TRANSCRICAO <- "google/gemini-2.5-flash"

# Máximo de imagens por requisição (carrosséis maiores são divididos em lotes)
MAX_IMAGENS_POR_REQUISICAO <- 10

# Arquivos de prompt (pasta prompts/)
PROMPTS <- list(
  definicoes = arquivo_app("prompts/definicoes.txt"),
  instrucao  = arquivo_app("prompts/instrucao_saida.txt"),
  legenda    = arquivo_app("prompts/legenda.txt"),
  imagem     = arquivo_app("prompts/imagem.txt"),
  transcricao = arquivo_app("prompts/transcricao.txt"),
  transcrever = arquivo_app("prompts/transcrever_audio.txt")
)

# Ordem das colunas principais da base classificada/validada
COLUNAS_SAIDA <- c(
  "candidato", "url", "caption", "transcricao", "likes", "shortCode", "comentarios",
  "data", "semana", "formato"
)

# Mídia baixada (imagens: SHORTCODE.jpg ou SHORTCODE_1.jpg, _2.jpg... em carrosséis;
# vídeos: SHORTCODE.mp4; capa dos vídeos também em postagens/SHORTCODE.jpg)
PASTA_MIDIA <- "midia"
PASTA_IMAGENS <- file.path(PASTA_MIDIA, "postagens")
PASTA_VIDEOS <- file.path(PASTA_MIDIA, "videos")
PASTA_AUDIOS <- file.path(PASTA_MIDIA, "audios")
BAIXAR_CAPAS_VIDEOS <- TRUE

# Pastas de trabalho
PASTA_RODADAS <- "saidas/rodadas"
# Relatório único (pronto para publicar: index.html + dados + fotos)
PASTA_RELATORIO <- "saidas/relatorio"

# Cache de classificações (evita pagar duas vezes pela mesma postagem
# e permite retomar se a classificação for interrompida)
ARQUIVO_CACHE <- "saidas/cache_classificacoes_multimodal.csv"

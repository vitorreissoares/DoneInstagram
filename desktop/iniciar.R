# Inicia o DoneInstagram para o programa de computador (chamado pelo Electron).
# DONEINSTAGRAM_APP: pasta do programa · DONEINSTAGRAM_DADOS: pasta de dados
# DONEINSTAGRAM_PORTA: porta local que a janela do programa vai abrir
options(shiny.launch.browser = FALSE, warn = 1)
porta <- as.integer(Sys.getenv("DONEINSTAGRAM_PORTA", "8765"))
pasta_app <- Sys.getenv("DONEINSTAGRAM_APP")

# O app é carregado como objeto (e não como pasta) para que o Shiny não troque
# a pasta de trabalho: tudo o que o app grava vai para a pasta de dados
app <- source(file.path(pasta_app, "app.R"), local = new.env(), encoding = "UTF-8")$value
cat("DoneInstagram: dados em", getwd(), "\n")
shiny::runApp(app, port = porta, host = "127.0.0.1", launch.browser = FALSE)

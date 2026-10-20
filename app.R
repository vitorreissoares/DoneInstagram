# =========================================================
# DONEINSTAGRAM — monitoramento de postagens no Instagram
#   1 · Categorização    arquivos .xlsx -> postagens classificadas pela IA
#   2 · Validação        conferência humana (aqui no app ou pela Planilha Google)
#   3 · Relatório        um relatório só, com os botões Semana, Mês, Ano e Tudo
#
# Para abrir: no RStudio, abra este arquivo e clique em "Run App"
# =========================================================

library(shiny)
library(bslib)
library(DT)

PASTA_APP <- normalizePath(Sys.getenv("DONEINSTAGRAM_APP", getwd()))
source(file.path(PASTA_APP, "R/carregar.R"), encoding = "UTF-8")
usar_pasta_dados()   # programa instalado: dados na pasta do usuário

options(shiny.maxRequestSize = 500 * 1024^2)

`%|%` <- function(a, b) if (length(a) == 0 || is.na(a[1]) || identical(a[1], "")) b else a

# Imagens e vídeos baixados ficam acessíveis no app em "midia/..."
criar_pastas_midia()
addResourcePath("midia", normalizePath(PASTA_MIDIA))

# Chave do OpenRouter salva no projeto (se houver) e semanas antigas do relatório final
carregar_chave()
tryCatch(importar_historico(), error = function(e) message("Não foi possível importar as semanas antigas: ", conditionMessage(e)))

estilos <- tags$head(
  tags$script(src = "https://www.instagram.com/embed.js", async = NA),
  tags$script(HTML("
    Shiny.addCustomMessageHandler('instagram', function(msg) {
      setTimeout(function() { if (window.instgrm) window.instgrm.Embeds.process(); }, 300);
    });
    // Tabela de validação: envia ao servidor as subcategorias ligadas
    function enviarFinal() {
      var tab = document.getElementById('tabela-validacao');
      if (!tab) return;
      var marcadas = Array.from(tab.querySelectorAll('input.final:checked')).map(function(x) { return x.value; });
      var cont = document.getElementById('contador-final');
      if (cont) { cont.textContent = marcadas.length + (marcadas.length === 1 ? ' selecionada' : ' selecionadas'); }
      tab.querySelectorAll('tr[data-chave]').forEach(function(tr) { tr.classList.toggle('escolhida', tr.querySelector('input.final').checked); });
      Shiny.setInputValue('v_final', { sc: tab.dataset.sc, chaves: marcadas }, { priority: 'event' });
    }
    $(document).on('change', '#tabela-validacao input.final', enviarFinal);
    $(document).on('click', '#v_nenhuma', function() {
      document.querySelectorAll('#tabela-validacao input.final').forEach(function(x) { x.checked = false; }); enviarFinal();
    });
    $(document).on('click', '#v_sugestao', function() {
      document.querySelectorAll('#tabela-validacao input.final').forEach(function(x) { x.checked = x.dataset.sugestao === '1'; }); enviarFinal();
    });
    // Miniaturas do carrossel
    $(document).on('click', '.miniatura', function() {
      document.getElementById('imagem-grande').src = this.src;
      document.querySelectorAll('.miniatura').forEach(function(m) { m.classList.remove('ativa'); });
      this.classList.add('ativa');
    });
    // Ao mostrar uma nova postagem, já calcula o contador e envia a seleção inicial
    $(document).on('shiny:value', function(e) { if (e.name === 'cartao_validacao') setTimeout(enviarFinal, 150); });
    // Copiar para a área de transferência
    Shiny.addCustomMessageHandler('copiar', function(msg) {
      navigator.clipboard.writeText(msg.texto).then(function() {}, function() { prompt('Copie o texto:', msg.texto); });
    });
  ")),
  tags$style(HTML("
    /* ---------- base ---------- */
    :root { --linha: #eceef2; --suave: #8a90a0; --texto2: #5b6170; --fundo: #f7f8fa; }
    body { background: var(--fundo); }
    .navbar { background: #fff !important; border-bottom: 1px solid var(--linha); box-shadow: none; }
    .navbar-brand { font-weight: 700; letter-spacing: -.02em; font-size: 1.05rem; display: flex; align-items: center; gap: 8px; }
    .navbar-brand .marca { width: 26px; height: 26px; border-radius: 8px; display: inline-flex; align-items: center; justify-content: center;
                           background: linear-gradient(135deg, #3f5bd8, #8b5cf6); color: #fff; font-size: .8rem; }
    .navbar .nav-link { font-size: .86rem; font-weight: 500; color: var(--texto2); }
    .navbar .nav-link.active { color: var(--bs-primary) !important; }
    .nav-num { display: inline-flex; width: 20px; height: 20px; border-radius: 50%; background: #eef0f4; color: var(--texto2);
               font-size: .68rem; font-weight: 600; align-items: center; justify-content: center; margin-right: 6px; }
    .nav-link.active .nav-num { background: var(--bs-primary); color: #fff; }
    h4, h5 { letter-spacing: -.01em; }
    .btn { font-weight: 500; border-radius: 9px; }
    .btn-sm { font-size: .78rem; border-radius: 8px; }
    .table { font-size: .82rem; }
    a { text-decoration: none; } a:hover { text-decoration: underline; }
    .nav-link:hover, .accordion-button:hover, .btn:hover { text-decoration: none; }
    .form-control, .form-select { font-size: .86rem; padding: .4rem .65rem; }
    .selectize-input { font-size: .86rem; padding: .4rem .65rem; }
    .form-label, .control-label { font-size: .8rem; font-weight: 500; color: var(--texto2); }
    .table th { font-weight: 600; color: var(--texto2); }
    .shiny-notification { border-radius: 10px; font-size: .85rem; }
    .modal-content { border-radius: 14px; border: none; }

    /* ---------- barra lateral ---------- */
    .bslib-sidebar-layout > .sidebar { background: #fff; border-right: 1px solid var(--linha); font-size: .84rem; }
    .sidebar .form-label, .sidebar .control-label, .sidebar label { font-size: .77rem; font-weight: 500; color: var(--texto2); }
    .sidebar .form-control, .sidebar .form-select, .sidebar .selectize-input, .sidebar .input-group .btn { font-size: .83rem; }
    .sidebar .form-group, .sidebar .shiny-input-container { margin-bottom: .7rem; }
    .sidebar .accordion { --bs-accordion-border-color: var(--linha); }
    .sidebar .accordion-button { font-size: .82rem; font-weight: 600; padding: .7rem 1rem; color: #2a2f3a; }
    .sidebar .accordion-button:not(.collapsed) { color: var(--bs-primary); }
    .sidebar .accordion-body { padding: .1rem 1rem .9rem; }
    .sidebar .form-control, .sidebar .form-select { padding: .35rem .6rem; }
    .sidebar .selectize-input { padding: .35rem .6rem; min-height: 0; box-shadow: none; }
    .sidebar .selectize-input, .sidebar .selectize-input input, .sidebar .selectize-dropdown { font-size: .83rem !important; }
    .sidebar .input-group .btn, .sidebar .input-group .form-control { padding: .3rem .6rem; font-size: .8rem; }
    .sidebar .shiny-input-container:has(input[type=file]) { margin-bottom: .4rem; }
    .sidebar .shiny-file-input-progress { display: none !important; }
    .sidebar .accordion-button .accordion-icon { color: var(--suave); }
    .sidebar .irs--shiny .irs-bar { background: var(--bs-primary); border-color: var(--bs-primary); }
    .dica { font-size: .75rem; color: var(--suave); line-height: 1.45; }
    .titulo-lateral { font-size: .68rem; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; color: var(--suave); margin: .2rem 0 .5rem; }
    .acao-final { position: sticky; bottom: 0; background: #fff; padding: .7rem 0 .3rem; z-index: 5;
                  box-shadow: 0 -10px 12px -10px rgba(16, 24, 40, .08); }
    .status-linha { display: flex; align-items: center; gap: 6px; font-size: .78rem; }
    .bolinha { width: 7px; height: 7px; border-radius: 50%; display: inline-block; background: #12b76a; }
    .bolinha.off { background: #f04438; }

    /* ---------- cartões e indicadores ---------- */
    .card { border: 1px solid var(--linha); box-shadow: none; border-radius: 14px; }
    .card-header { background: transparent; font-weight: 600; font-size: .88rem; border-bottom: 1px solid #f1f2f5; }
    .card-header.ok { color: #067647; background: #f0fdf4; }
    .cabecalho-acoes { display: flex; justify-content: space-between; align-items: center; gap: 8px; flex-wrap: wrap; }
    .indicadores { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin-bottom: 1rem; }
    .indicador { background: #fff; border: 1px solid var(--linha); border-radius: 12px; padding: 12px 14px; }
    .indicador .titulo { font-size: .68rem; text-transform: uppercase; letter-spacing: .06em; color: var(--suave); font-weight: 600;
                         display: flex; gap: 6px; align-items: center; }
    .indicador .valor { font-size: 1.45rem; font-weight: 650; line-height: 1.2; margin-top: 4px; color: #1f2430; }
    .indicador .detalhe { font-size: .74rem; color: var(--suave); margin-top: 2px; }
    .indicador.destaque .valor { color: var(--bs-primary); }
    .indicador.aviso .valor { color: #b54708; }
    .indicador.ok .valor { color: #067647; }
    .vazio { text-align: center; padding: 48px 20px; }
    .vazio .icone { width: 52px; height: 52px; border-radius: 16px; background: #eef1fd; color: var(--bs-primary);
                    display: inline-flex; align-items: center; justify-content: center; font-size: 1.3rem; margin-bottom: 12px; }
    .vazio h5 { font-weight: 650; } .vazio p { color: var(--suave); max-width: 520px; margin: 0 auto; font-size: .88rem; }
    .etapas { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; margin-top: 22px; }
    .etapa { border: 1px solid var(--linha); border-radius: 12px; padding: 10px 14px; font-size: .8rem; color: var(--texto2); background: #fff;
             display: flex; align-items: center; gap: 8px; }
    .etapa b { color: #1f2430; }
    .accordion.principal { --bs-accordion-border-color: var(--linha); --bs-accordion-border-radius: 14px; margin-bottom: 1rem; }
    .accordion.principal .accordion-button { font-size: .88rem; font-weight: 600; }
    .accordion.principal .accordion-item { background: #fff; }
    .nav-underline .nav-link, .card-header .nav-link { font-size: .84rem; }

    /* ---------- validação ---------- */
    .legenda { white-space: pre-wrap; line-height: 1.55; max-height: 240px; overflow: auto;
               background: var(--bs-tertiary-bg); padding: 12px 14px; border-radius: 10px; font-size: .9rem; }
    .rotulo-secao { font-size: .7rem; font-weight: 700; text-transform: uppercase; letter-spacing: .06em;
                    color: var(--suave); margin: 12px 0 6px; }
    details > summary { cursor: pointer; }
    .pill { display: inline-block; background: var(--bs-tertiary-bg); padding: 4px 10px;
            border-radius: 99px; margin-right: 6px; font-size: .82rem; text-decoration: none; color: inherit; }
    .midia { background: #f8fafc; border-radius: 12px; padding: 10px; text-align: center; }
    .midia img#imagem-grande, .midia video { max-width: 100%; max-height: 460px; border-radius: 8px; }
    .miniaturas { display: flex; gap: 6px; justify-content: center; flex-wrap: wrap; margin-top: 8px; }
    .miniatura { width: 58px; height: 58px; object-fit: cover; border-radius: 6px; cursor: pointer; opacity: .6; border: 2px solid transparent; }
    .miniatura.ativa { opacity: 1; border-color: var(--bs-primary); }
    .instagram-wrap { display: flex; justify-content: center; max-height: 600px; overflow: auto; }
    .instagram-wrap .instagram-media { min-width: 300px !important; max-width: 460px !important; }
    .tabela-validacao { width: 100%; border-collapse: collapse; font-size: .88rem; }
    .tabela-validacao th { font-size: .66rem; text-transform: uppercase; letter-spacing: .05em; color: var(--suave);
                           text-align: center; padding: 6px 4px; font-weight: 600; }
    .tabela-validacao th:first-child, .tabela-validacao td:first-child { text-align: left; }
    .tabela-validacao td { padding: 6px 4px; border-top: 1px solid var(--linha); text-align: center; }
    .tabela-validacao tr.grupo td { background: var(--bs-tertiary-bg); font-weight: 700; font-size: .7rem;
                                    text-transform: uppercase; letter-spacing: .05em; }
    .tabela-validacao tr.grupo.prog td { color: #c2410c; } .tabela-validacao tr.grupo.pers td { color: #7c3aed; }
    .tabela-validacao tr.escolhida td { background: #eef4ff; }
    .ponto { display: inline-block; width: 13px; height: 13px; border-radius: 50%; border: 2px solid #cfd4dc; }
    .ponto.on { background: var(--bs-primary); border-color: var(--bs-primary); }
    .sem-fonte { color: #c0c6cf; }
    .interruptor { position: relative; display: inline-block; width: 40px; height: 22px; margin: 0; }
    .interruptor input { opacity: 0; width: 0; height: 0; }
    .interruptor span { position: absolute; inset: 0; background: #d0d5dd; border-radius: 99px; transition: .2s; cursor: pointer; }
    .interruptor span:before { content: ''; position: absolute; width: 16px; height: 16px; left: 3px; top: 3px;
                               background: #fff; border-radius: 50%; transition: .2s; }
    .interruptor input:checked + span { background: #087443; }
    .interruptor input:checked + span:before { transform: translateX(18px); }
    #contador-final { font-weight: 700; }

    /* ---------- listas ---------- */
    .lista-arquivos { list-style: none; padding: 0; margin: 0 0 .5rem; }
    .lista-arquivos li { display: flex; justify-content: space-between; gap: 8px; align-items: center;
                         border: 1px solid var(--linha); border-radius: 10px; padding: 7px 10px; margin-bottom: 6px; font-size: .82rem; }
    .lista-arquivos .nome-arquivo { font-size: .72rem; color: var(--suave); overflow-wrap: anywhere; }
    .lista-arquivos .remover { color: var(--suave); cursor: pointer; } .lista-arquivos .remover:hover { color: var(--bs-danger); }
    .quadro-sobre textarea, .quadro-sobre input { font-size: .85rem; }
    #texto_rel { font-size: .9rem; line-height: 1.6; }

    /* ---------- passos da validação compartilhada ---------- */
    .passos .accordion-button { font-size: .88rem; font-weight: 600; }
    .passos .num { display: inline-flex; width: 22px; height: 22px; border-radius: 50%; background: #eef0f4; color: var(--texto2);
                   align-items: center; justify-content: center; font-size: .72rem; margin-right: 10px; flex-shrink: 0; }
    .passos .feito .num { background: #dcfae6; color: #067647; }
    .passos .accordion-body { font-size: .85rem; }
  "))
)

# Tabela de validação: uma linha por subcategoria, com o que cada fonte da IA marcou
# e um interruptor para a classificação final
tabela_validacao <- function(r, selecionadas) {
  fontes_disp <- names(FONTES)[map_lgl(names(FONTES), \(f) !all(is.na(unlist(r[paste0("ia_", f, "_", CHAVES)]))))]
  sugestao <- chaves_marcadas(r, "ia_sugestao_")
  linhas <- list()
  for (cat in unique(SUBCATEGORIAS_TAB$categoria)) {
    linhas[[length(linhas) + 1]] <- tags$tr(class = paste("grupo", if (grepl("program", cat)) "prog" else "pers"),
                                            tags$td(colspan = 5, cat))
    for (k in SUBCATEGORIAS_TAB$chave[SUBCATEGORIAS_TAB$categoria == cat]) {
      pontos <- map(names(FONTES), \(f) {
        if (!f %in% fontes_disp) return(tags$td(class = "sem-fonte", title = "A postagem não tem esta fonte", "—"))
        on <- identical(as.integer(r[[paste0("ia_", f, "_", k)]]), 1L)
        tags$td(span(class = paste("ponto", if (on) "on"), title = if (on) "A IA marcou" else "A IA não marcou"))
      })
      escolhida <- k %in% selecionadas
      linhas[[length(linhas) + 1]] <- tags$tr(
        `data-chave` = k, class = if (escolhida) "escolhida",
        tags$td(rotulo_de(k)), pontos,
        tags$td(tags$label(class = "interruptor",
                           tags$input(type = "checkbox", class = "final", value = k,
                                      `data-sugestao` = as.integer(k %in% sugestao),
                                      checked = if (escolhida) NA),
                           tags$span()))
      )
    }
  }
  tags$table(
    class = "tabela-validacao", id = "tabela-validacao", `data-sc` = r$shortCode,
    tags$tr(tags$th("Subcategoria"), map(FONTES, \(n) tags$th(sub(" \\(.*", "", n))), tags$th("Final")),
    linhas
  )
}

# Imagens/vídeo baixados da postagem (ou a prévia do Instagram, se não houver)
midia_postagem <- function(r) {
  imagens <- arquivos_imagens(r$shortCode)
  video <- arquivo_video(r$shortCode)
  web <- function(arq) paste0("midia/", sub(paste0("^", PASTA_MIDIA, "/"), "", arq))
  if (!is.na(video)) {
    return(div(class = "midia",
               tags$video(src = web(video), controls = NA, preload = "metadata",
                          poster = if (length(imagens)) web(imagens[1]))))
  }
  if (length(imagens) > 0) {
    return(div(class = "midia",
               tags$img(id = "imagem-grande", src = web(imagens[1])),
               if (length(imagens) > 1)
                 div(class = "miniaturas",
                     imap(imagens, \(a, i) tags$img(class = paste("miniatura", if (i == 1) "ativa"), src = web(a)))),
               if (length(imagens) > 1) div(class = "small text-muted mt-1", sprintf("Carrossel com %d imagens", length(imagens)))))
  }
  if (!is.na(r$url)) {
    return(div(class = "instagram-wrap",
               tags$blockquote(class = "instagram-media", `data-instgrm-permalink` = r$url,
                               `data-instgrm-version` = "14",
                               tags$a(href = r$url, target = "_blank", "Ver no Instagram"))))
  }
  div(class = "midia text-muted", "Sem imagem ou vídeo")
}

# Indicadores compactos (substituem os value boxes grandes)
indicador <- function(titulo, valor, detalhe = NULL, icone = NULL, tom = NULL) {
  div(class = paste("indicador", tom),
      div(class = "titulo", if (!is.null(icone)) icon(icone), titulo),
      div(class = "valor", valor),
      if (!is.null(detalhe)) div(class = "detalhe", detalhe))
}
indicadores <- function(...) div(class = "indicadores", ...)

# Tela vazia com ícone, título e texto
vazio <- function(icone, titulo, ...) {
  div(class = "vazio", div(class = "icone", icon(icone)), h5(titulo), ...)
}

# Passo da validação compartilhada (painel que abre e fecha)
passo <- function(numero, titulo, feito = FALSE, ...) {
  accordion_panel(
    title = span(class = paste("d-flex align-items-center", if (feito) "feito"),
                 span(class = "num", if (feito) icon("check") else numero), titulo),
    value = paste0("passo", numero), ...
  )
}

aba <- function(numero, titulo) tagList(span(class = "nav-num", numero), titulo)

ui <- page_navbar(
  id = "abas",
  title = span(span(class = "marca", icon("chart-simple")), "DoneInstagram"),
  window_title = "DoneInstagram",
  theme = bs_theme(
    version = 5, primary = "#3f5bd8", font_scale = 0.92,
    base_font = font_collection(font_google("Inter", local = FALSE), "system-ui", "-apple-system", "Segoe UI", "sans-serif"),
    "border-radius" = "0.6rem"
  ),
  header = estilos,

  # =======================================================
  # 1 · CATEGORIZAÇÃO
  # =======================================================
  nav_panel(
    aba(1, "Categorização"), value = "categorizacao",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        width = 330,
        uiOutput("status_chave"),
        accordion(
          id = "acc_cat", multiple = TRUE, open = "arquivos",
          accordion_panel(
            "Chave da IA", value = "chave", icon = icon("key"),
            uiOutput("painel_chave")
          ),
          accordion_panel(
            "Arquivos coletados", value = "arquivos", icon = icon("file-excel"),
            p(class = "dica mb-2", "Um arquivo por vez: escolha o .xlsx, confira o candidato e clique em Adicionar."),
            uiOutput("campo_arquivo"),
            selectizeInput("candidato_novo", "Candidato deste arquivo", choices = NULL,
                           options = list(create = TRUE, placeholder = "Escolha ou digite o nome")),
            actionButton("adicionar_arquivo", "Adicionar à lista", icon = icon("plus"),
                         class = "btn-outline-primary btn-sm w-100 mb-3"),
            uiOutput("lista_arquivos")
          ),
          accordion_panel(
            "Período e seleção", value = "periodo", icon = icon("calendar"),
            dateRangeInput("periodo", "Período", language = "pt-BR",
                           format = "dd/mm/yyyy", separator = "até"),
            sliderInput("proporcao", "% mais curtidas de cada candidato no período",
                        min = 5, max = 100, value = PROPORCAO_TOP_PADRAO * 100, step = 5, post = "%")
          ),
          accordion_panel(
            "O que a IA analisa", value = "fontes", icon = icon("eye"),
            checkboxGroupInput("fontes", NULL,
                               choices = c("Legenda" = "legenda", "Imagens (todas as do carrossel)" = "imagem",
                                           "Vídeos (o áudio é transcrito)" = "transcricao"),
                               selected = names(FONTES)),
            p(class = "dica", "Imagens e vídeos são baixados para a pasta ", code("midia/"), ", com o nome do shortcode."),
            uiOutput("aviso_av")
          ),
          accordion_panel(
            "Modelos de IA", value = "modelos", icon = icon("gear"),
            textInput("modelo", "Legenda e transcrição", MODELO_PADRAO),
            textInput("modelo_imagem", "Imagens (precisa aceitar imagens)", MODELO_PADRAO),
            textInput("modelo_transcricao", "Transcrição de áudio (precisa aceitar áudio)", MODELO_TRANSCRICAO)
          )
        ),
        div(class = "acao-final",
            actionButton("rodar", "Categorizar postagens", class = "btn-primary w-100", icon = icon("play")))
      ),

      uiOutput("resumo"),
      uiOutput("resultado"),
      conditionalPanel(
        "output.tem_arquivos",
        navset_card_underline(
          title = "Prévia da seleção",
          nav_panel("Por candidato", tableOutput("tabela_selecao")),
          nav_panel("Postagens", DTOutput("tabela_previa"))
        )
      )
    )
  ),

  # =======================================================
  # 2 · VALIDAÇÃO
  # =======================================================
  nav_panel(
    aba(2, "Validação"), value = "validacao",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        width = 290,
        selectInput("rodada_val", "Rodada", choices = NULL),
        uiOutput("progresso_val"),
        textInput("avaliador", "Seu nome", placeholder = "Fica registrado em cada validação"),
        checkboxInput("so_pendentes", "Navegar só pelas pendentes", TRUE),
        accordion(
          open = FALSE,
          accordion_panel(
            "Mais opções", icon = icon("ellipsis"),
            downloadButton("baixar_validada", "Baixar base validada (.csv)", class = "btn-sm w-100 mb-2"),
            actionLink("excluir_rodada", tagList(icon("trash-can"), " Excluir esta rodada"), class = "small text-danger")
          )
        )
      ),
      navset_card_underline(
        id = "sub_validacao",
        nav_panel(
          "Validar", icon = icon("list-check"),
          div(uiOutput("conclusao_val"),
              uiOutput("aviso_remoto"),
              uiOutput("cartao_validacao"))
        ),
        nav_panel(
          "Acurácia da IA", icon = icon("bullseye"),
          uiOutput("painel_acuracia")
        ),
        nav_panel(
          "Validação compartilhada", icon = icon("people-group"),
          uiOutput("painel_remoto")
        )
      )
    )
  ),

  # =======================================================
  # 3 · RELATÓRIO
  # =======================================================
  nav_panel(
    aba(3, "Relatório"), value = "relatorio",
    layout_sidebar(
      fillable = FALSE,
      sidebar = sidebar(
        width = 300,
        accordion(
          id = "acc_rel", multiple = TRUE, open = c("base", "periodo"),
          accordion_panel(
            "Base validada", value = "base", icon = icon("database"),
            radioButtons("base_modo", NULL,
                         c("Tudo junto (todas as rodadas)" = "tudo", "Uma rodada" = "rodada")),
            conditionalPanel("input.base_modo == 'rodada'",
                             selectInput("rodada_rel", NULL, choices = NULL)),
            fileInput("csv_validado", "…ou importar um CSV já validado", accept = ".csv",
                      multiple = TRUE, buttonLabel = "Escolher", placeholder = ".csv")
          ),
          accordion_panel(
            "Período", value = "periodo", icon = icon("calendar"),
            p(class = "dica mb-2", "Os mesmos botões do relatório. As datas saem da base: o trecho mais recente analisado."),
            radioButtons("periodo_tipo", NULL,
                         c("Semana (últimos 7 dias)" = "semana", "Mês (último mês)" = "mes",
                           "Ano (último ano)" = "ano", "Tudo" = "tudo")),
            uiOutput("periodo_datas_txt")
          )
        ),
        div(class = "acao-final",
            actionButton("gerar_rel", "Gerar relatório", class = "btn-primary w-100", icon = icon("file-lines")),
            p(class = "dica mt-2 mb-0", "O relatório abre no botão escolhido acima."))
      ),

      uiOutput("resumo_rel"),
      uiOutput("resultado_rel"),
      card(
        card_header(
          class = "cabecalho-acoes",
          span("Considerações finais deste período"),
          div(class = "d-flex gap-1 flex-wrap",
              actionButton("rascunho", "Rascunho", icon = icon("rotate"), class = "btn-sm btn-light",
                           title = "Refazer o rascunho automático com os números do período"),
              actionButton("redigir_ia", "Redigir com IA", icon = icon("wand-magic-sparkles"), class = "btn-sm btn-light"),
              actionButton("salvar_periodo", "Salvar texto", icon = icon("floppy-disk"), class = "btn-sm btn-outline-primary"))
        ),
        p(class = "dica mb-1",
          "Os números vêm da base validada. Complete os trechos entre [colchetes] e separe os parágrafos com uma linha em branco. ",
          "Botões sem texto salvo recebem um texto automático só com os números."),
        textAreaInput("texto_rel", NULL, width = "100%", rows = 12, resize = "vertical")
      ),
      accordion(
        class = "principal", open = FALSE, multiple = TRUE,
        accordion_panel(
          "Análises salvas", value = "salvas", icon = icon("bookmark"),
          uiOutput("lista_periodos")
        ),
        accordion_panel(
          "Candidatos", value = "candidatos", icon = icon("user"),
          p(class = "dica", "Clique duas vezes numa célula para editar. As mudanças ficam salvas para as próximas análises."),
          DTOutput("tabela_candidatos"),
          layout_columns(
            col_widths = c(4, 5, 3),
            selectInput("foto_candidato", "Trocar a foto de", choices = NULL),
            fileInput("foto_arquivo", "Nova foto (.jpg ou .png)", accept = c(".jpg", ".jpeg", ".png"),
                      buttonLabel = "Escolher", placeholder = "Nenhuma foto"),
            div(class = "pt-4",
                textInput("novo_candidato", NULL, placeholder = "Nome do novo candidato"),
                actionButton("adicionar_candidato", "Adicionar candidato", icon = icon("plus"),
                             class = "btn-sm btn-light"))
          ),
          p(class = "dica", "As fotos ficam em ", code("assets/img_cand/"), ".")
        ),
        accordion_panel(
          "Sobre a pesquisa", value = "sobre", icon = icon("circle-info"),
          p(class = "dica",
            "Os 7 quadros da seção “Sobre a pesquisa”. {proporcao} e {modelo} são preenchidos ",
            "automaticamente. Parágrafos são separados por uma linha em branco; links podem ser ",
            "escritos como <a href=\"...\">texto</a>."),
          textInput("modelo_rotulo", "Modelo citado na metodologia ({modelo})", MODELO_ROTULO),
          uiOutput("quadros_sobre"),
          actionButton("salvar_sobre", "Salvar textos", icon = icon("floppy-disk"), class = "btn-sm btn-outline-primary")
        )
      )
    )
  )
)

server <- function(input, output, session) {

  # Lista de rodadas compartilhada entre as abas
  rodadas <- reactiveVal(listar_rodadas())
  atualizar_listas <- function(selecionar = NULL) {
    ids <- listar_rodadas()
    rodadas(ids)
    escolhas <- set_names(ids, map_chr(ids, rotulo_rodada))
    sel <- selecionar %||% ids[1]
    updateSelectInput(session, "rodada_val", choices = escolhas, selected = sel)
    updateSelectInput(session, "rodada_rel", choices = escolhas, selected = sel)
  }
  atualizar_listas()

  notificar_erro <- function(prefixo) {
    function(e) {
      showNotification(paste(prefixo, conditionMessage(e)), type = "error", duration = NULL)
      NULL
    }
  }

  # =======================================================
  # 1 · CATEGORIZAÇÃO
  # =======================================================

  # Lista de arquivos adicionados, um por vez (arquivo + candidato)
  arquivos <- reactiveVal(tibble(nome = character(), caminho = character(),
                                 candidato = character(), postagens = integer()))
  arquivo_pendente <- reactiveVal(NULL)
  contador_arquivo <- reactiveVal(0)   # recria o campo de arquivo vazio após cada adição

  output$campo_arquivo <- renderUI({
    contador_arquivo()
    fileInput("arquivo_novo", NULL, accept = ".xlsx", multiple = FALSE,
              buttonLabel = "Escolher .xlsx", placeholder = "Nenhum arquivo")
  })

  opcoes_candidatos <- function() {
    nomes <- ler_candidatos_info()$nome
    c(set_names(nomes, nomes), "Vários candidatos (pela coluna alt)" = CANDIDATO_PELA_ALT)
  }

  observe({
    updateSelectizeInput(session, "candidato_novo", choices = opcoes_candidatos(), selected = "",
                         options = list(create = TRUE, placeholder = "Escolha ou digite o nome"))
  })

  # Ao escolher o arquivo, sugere o candidato (pelo nome do arquivo ou pelo conteúdo)
  observeEvent(input$arquivo_novo, {
    arq <- input$arquivo_novo
    arquivo_pendente(arq)
    updateSelectizeInput(session, "candidato_novo", choices = opcoes_candidatos(),
                         selected = sugerir_candidato(arq$datapath, arq$name),
                         options = list(create = TRUE, placeholder = "Escolha ou digite o nome"))
  })

  observeEvent(input$adicionar_arquivo, {
    arq <- arquivo_pendente()
    candidato <- str_squish(input$candidato_novo %||% "")
    if (is.null(arq)) return(showNotification("Escolha primeiro o arquivo .xlsx.", type = "warning"))
    if (!nzchar(candidato)) return(showNotification("Escreva o nome do candidato.", type = "warning"))

    dados <- tryCatch(ler_xlsx(arq$datapath), error = notificar_erro("Não foi possível ler o arquivo:"))
    req(dados)
    arquivos(bind_rows(arquivos(), tibble(nome = arq$name, caminho = arq$datapath,
                                          candidato = candidato, postagens = nrow(dados))))
    arquivo_pendente(NULL)
    contador_arquivo(contador_arquivo() + 1)
    updateSelectizeInput(session, "candidato_novo", choices = opcoes_candidatos(), selected = "",
                         options = list(create = TRUE, placeholder = "Escolha ou digite o nome"))
    showNotification(sprintf("%s adicionado (%d postagens). Escolha o próximo arquivo.",
                             if (candidato == CANDIDATO_PELA_ALT) arq$name else candidato,
                             nrow(dados)), type = "message")
  })

  output$lista_arquivos <- renderUI({
    a <- arquivos()
    if (nrow(a) == 0) return(p(class = "dica", "Nenhum arquivo adicionado ainda."))
    tagList(
      div(class = "titulo-lateral", sprintf("%d arquivo(s) na lista", nrow(a))),
      tags$ul(class = "lista-arquivos",
        map(seq_len(nrow(a)), \(i) {
          tags$li(
            div(tags$b(if (a$candidato[i] == CANDIDATO_PELA_ALT) "Vários candidatos" else a$candidato[i]),
                div(class = "nome-arquivo", sprintf("%s · %d postagens", a$nome[i], a$postagens[i]))),
            tags$span(class = "remover", title = "Remover da lista", icon("xmark"),
                      onclick = sprintf("Shiny.setInputValue('remover_arquivo', %d, {priority: 'event'})", i))
          )
        })
      )
    )
  })

  observeEvent(input$remover_arquivo, {
    arquivos(arquivos()[-input$remover_arquivo, ])
  })

  base <- reactive({
    a <- arquivos()
    req(nrow(a) > 0)
    tryCatch(ler_base(a$caminho, a$candidato), error = notificar_erro("Erro ao ler os arquivos:"))
  })

  # Período = da data mais antiga à mais recente dos arquivos da lista
  observeEvent(arquivos(), {
    b <- base()
    req(b, nrow(b) > 0)
    updateDateRangeInput(session, "periodo", start = min(b$data, na.rm = TRUE),
                         end = max(b$data, na.rm = TRUE))
  }, ignoreInit = TRUE)

  previa <- reactive({
    b <- req(base())
    req(input$periodo[1], input$periodo[2])
    preparar_dados(b, input$periodo[1], input$periodo[2], input$proporcao / 100)
  })

  # ---- Chave do OpenRouter -------------------------------
  versao_chave <- reactiveVal(0)
  trocar_chave <- reactiveVal(FALSE)

  output$painel_chave <- renderUI({
    versao_chave()
    origem <- origem_chave()
    if (nzchar(origem) && !trocar_chave()) {
      onde <- switch(origem,
                     projeto = "salva nesta pasta do projeto",
                     renviron = "salva no .Renviron deste computador",
                     sessao = "usada só nesta sessão")
      return(tagList(
        div(class = "text-success small mb-1", icon("circle-check"),
            sprintf(" Chave %s (%s).", chave_mascarada(), onde)),
        div(class = "d-flex gap-3 mb-1",
            actionLink("trocar_chave", tagList(icon("pen"), " Trocar"), class = "small"),
            actionLink("apagar_chave", tagList(icon("trash-can"), " Apagar chave"), class = "small text-danger")),
        p(class = "small text-muted", "Apague a chave antes de compartilhar a pasta com outra pessoa.")
      ))
    }
    tagList(
      if (!nzchar(origem)) div(class = "text-danger small mb-1", icon("triangle-exclamation"), " Nenhuma chave informada."),
      passwordInput("chave_nova", NULL, placeholder = "Cole a chave (sk-or-...)"),
      div(class = "d-flex gap-2 align-items-center",
          actionButton("salvar_chave", "Salvar chave", icon = icon("floppy-disk"), class = "btn-sm btn-primary"),
          if (trocar_chave()) actionLink("cancelar_chave", "Cancelar", class = "small"),
          tags$a(href = "https://openrouter.ai/keys", target = "_blank", class = "small ms-auto", "Onde consigo uma chave?"))
    )
  })

  observeEvent(input$trocar_chave, trocar_chave(TRUE))
  observeEvent(input$cancelar_chave, trocar_chave(FALSE))

  observeEvent(input$salvar_chave, {
    chave <- str_trim(input$chave_nova %||% "")
    if (!nzchar(chave)) return(showNotification("Cole a chave antes de salvar.", type = "warning"))
    salvar_chave(chave)
    trocar_chave(FALSE)
    versao_chave(versao_chave() + 1)
    showNotification("Chave salva nesta pasta do projeto.", type = "message")
  })

  observeEvent(input$apagar_chave, {
    showModal(modalDialog(
      title = "Apagar a chave do OpenRouter?",
      p("A chave será removida desta pasta do projeto e do .Renviron deste computador. ",
        "Para categorizar de novo, será preciso informar uma chave."),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("confirmar_apagar_chave", "Apagar chave", class = "btn-danger")),
      easyClose = TRUE
    ))
  })
  observeEvent(input$confirmar_apagar_chave, {
    apagar_chave()
    removeModal()
    versao_chave(versao_chave() + 1)
    showNotification("Chave apagada.", type = "message")
  })

  output$resumo <- renderUI({
    if (nrow(arquivos()) == 0) {
      return(card(vazio(
        "cloud-arrow-up", "Comece pelos arquivos coletados",
        p("Adicione um .xlsx por candidato na barra ao lado. O app junta tudo, seleciona as postagens mais ",
          "curtidas de cada candidato no período e as analisa com IA: legenda, imagens e vídeos."),
        div(class = "etapas",
            div(class = "etapa", icon("file-excel"), tags$b("1"), "Adicione os arquivos"),
            div(class = "etapa", icon("calendar"), tags$b("2"), "Escolha período e %"),
            div(class = "etapa", icon("play"), tags$b("3"), "Categorize"))
      )))
    }
    p <- req(previa())
    b <- req(base())
    novas <- sum(!p$shortCode %in% ler_cache()$shortCode)
    indicadores(
      indicador("Postagens nos arquivos", num(nrow(b)),
                tagList(sprintf("%d arquivo(s) · ", nrow(arquivos())),
                        downloadLink("baixar_unificada", "baixar base unificada")), "database"),
      indicador("Selecionadas", num(nrow(p)),
                sprintf("%d%% mais curtidas de cada candidato", input$proporcao), "filter", "destaque"),
      # ~8 s por fonte analisada + download e transcrição
      indicador("A classificar", num(novas),
                sprintf("~%d min · %d já no cache", ceiling(novas * (8 * length(input$fontes) + 10) / 60), nrow(p) - novas),
                "robot")
    )
  })

  # Mostra a prévia só quando há arquivos na lista
  output$tem_arquivos <- reactive(nrow(arquivos()) > 0)
  outputOptions(output, "tem_arquivos", suspendWhenHidden = FALSE)

  # Linha de status da chave no topo da barra lateral (abre o painel ao clicar)
  output$status_chave <- renderUI({
    versao_chave()
    tem <- nzchar(origem_chave())
    div(class = "status-linha mb-2",
        span(class = paste("bolinha", if (!tem) "off")),
        if (tem) "Chave da IA configurada" else "Falta a chave da IA",
        tags$a(href = "#", class = "ms-auto small",
               onclick = "Shiny.setInputValue('abrir_chave', Date.now()); return false;",
               if (tem) "ver" else "informar"))
  })
  observeEvent(input$abrir_chave, accordion_panel_open("acc_cat", "chave"))
  # Sem chave: o painel já abre sozinho
  observeEvent(versao_chave(), {
    if (!nzchar(origem_chave())) accordion_panel_open("acc_cat", "chave")
  })
  # Depois do primeiro arquivo, abre o painel de período
  observeEvent(nrow(arquivos()), {
    if (nrow(arquivos()) == 1) accordion_panel_open("acc_cat", "periodo")
  }, ignoreInit = TRUE)

  output$tabela_selecao <- renderTable({
    resumo_selecao(req(base()), req(previa()), input$periodo[1], input$periodo[2]) %>%
      transmute(Candidato = candidato,
                `Postagens no período` = postagens,
                `Primeira` = format(primeira, "%d/%m/%Y"), `Última` = format(ultima, "%d/%m/%Y"),
                Selecionadas = selecionadas)
  }, digits = 0)

  output$tabela_previa <- renderDT({
    datatable(
      previa() %>% select(candidato, data, likes, comentarios, formato, caption),
      options = list(pageLength = 10, scrollX = TRUE,
                     language = list(url = "https://cdn.datatables.net/plug-ins/1.13.6/i18n/pt-BR.json")),
      rownames = FALSE
    )
  })

  output$baixar_unificada <- downloadHandler(
    filename = function() "base_unificada.csv",
    content = function(file) write_excel_csv(base(), file, na = "")
  )

  output$aviso_av <- renderUI({
    if ("transcricao" %in% input$fontes && !pode_extrair_audio()) {
      div(class = "alert alert-warning small p-2",
          icon("triangle-exclamation"), " Para transcrever vídeos, instale o pacote ", code("av"),
          ": rode ", code('install.packages("av")'), " no R e abra o app de novo.")
    }
  })

  ultima_rodada <- reactiveVal(NULL)

  observeEvent(input$rodar, {
    dados <- req(previa())
    if (nrow(dados) == 0) {
      showNotification("Nenhuma postagem no período escolhido.", type = "warning")
      return()
    }
    if (length(input$fontes) == 0) {
      showNotification("Marque pelo menos uma fonte para a IA analisar.", type = "warning")
      return()
    }
    completar_candidatos_info(unique(dados$candidato))

    resultado <- tryCatch(
      withProgress(message = "Categorizando postagens", value = 0, {
        classificar_base(
          dados,
          modelos = list(texto = input$modelo, imagem = input$modelo_imagem,
                         transcricao = input$modelo_transcricao),
          fontes = input$fontes,
          progresso = \(i, n, msg) setProgress(i / n, detail = sprintf("Postagem %d de %d — %s", i, n, msg))
        )
      }),
      error = notificar_erro("A categorização parou (o que já foi feito está salvo; clique de novo para continuar):")
    )
    req(resultado)

    id <- basename(criar_rodada(resultado, input$periodo[1], input$periodo[2],
                                input$proporcao / 100, input$modelo))
    ultima_rodada(list(id = id, dados = resultado))
    atualizar_listas(id)
    showNotification("Categorização concluída!", type = "message")
  })

  output$resultado <- renderUI({
    r <- req(ultima_rodada())
    d <- r$dados
    sem_sugestao <- sum(rowSums(as.matrix(d[paste0("ia_sugestao_", CHAVES)]) == 1, na.rm = TRUE) == 0)
    card(
      card_header(class = "ok", icon("circle-check"), " Categorização concluída"),
      card_body(
        p("Rodada ", code(r$id), " com ", nrow(d), " postagens · ",
          sum(d$n_imagens), " imagens e ", sum(d$tem_video), " vídeos salvos em ", code("midia/"), "."),
        if (sem_sugestao > 0)
          p(class = "text-muted small", sem_sugestao, " postagem(ns) sem nenhuma subcategoria sugerida pela IA; ",
            "confira-as na validação."),
        div(actionButton("ir_validacao", "Ir para a validação", icon = icon("arrow-right"),
                         class = "btn-primary")),
        tags$details(
          class = "mt-3",
          tags$summary(class = "small text-muted", "Ver a sugestão da IA por candidato"),
          p(class = "dica mt-2", "Subcategorias marcadas por pelo menos metade das fontes."),
          tableOutput("tabela_categorias"))
      )
    )
  })

  output$tabela_categorias <- renderTable({
    d <- req(ultima_rodada())$dados
    map(CHAVES, \(k) d %>% filter(.data[[paste0("ia_sugestao_", k)]] == 1) %>% count(candidato) %>%
          mutate(Categoria = categoria_de(k), Subcategoria = rotulo_de(k))) %>%
      bind_rows() %>%
      pivot_wider(names_from = candidato, values_from = n, values_fill = 0) %>%
      mutate(Total = rowSums(across(where(is.numeric))))
  }, digits = 0)

  observeEvent(input$ir_validacao, nav_select("abas", "validacao"))

  # =======================================================
  # 2 · VALIDAÇÃO
  # =======================================================

  versao_val <- reactiveVal(0)   # muda a cada validação salva/sincronizada
  posicao <- reactiveVal(1)

  dados_val <- reactive({
    versao_val()
    req(rodada_existe(input$rodada_val))
    base_validada_rodada(input$rodada_val) %>% arrange(candidato, data)
  })

  pendente <- function(d) !d$validada

  # Ao trocar de rodada: vai para a primeira pendente (e sincroniza se for remota)
  observeEvent(input$rodada_val, {
    req(rodada_existe(input$rodada_val))
    if (isTRUE(ler_rodada(input$rodada_val)$remota) && remota_configurada()) {
      tryCatch(sincronizar_google(input$rodada_val), error = function(e) NULL)
      versao_val(versao_val() + 1)
    }
    posicao(which(pendente(isolate(dados_val())))[1] %|% 1)
  })

  output$progresso_val <- renderUI({
    d <- dados_val()
    feitas <- sum(!pendente(d))
    tagList(
      div(class = "d-flex justify-content-between small mb-1",
          span(class = "text-muted", "Progresso"), span(tags$b(feitas), sprintf(" de %d", nrow(d)))),
      div(class = "progress mb-3", style = "height: 6px",
          div(class = "progress-bar", style = sprintf("width: %d%%", round(100 * feitas / max(1, nrow(d))))))
    )
  })

  ir_para <- function(direcao) {
    d <- dados_val()
    opcoes <- if (isTRUE(input$so_pendentes)) which(pendente(d)) else seq_len(nrow(d))
    atual <- posicao()
    destino <- if (direcao > 0) opcoes[opcoes > atual][1] else tail(opcoes[opcoes < atual], 1)
    if (length(destino) == 0 || is.na(destino)) {
      # Sem mais à frente: volta para a primeira pendente, se ainda houver
      primeira <- which(pendente(d))[1]
      if (direcao > 0 && !is.na(primeira) && primeira != atual) {
        posicao(primeira)
      } else {
        showNotification(if (direcao > 0) "Não há mais postagens pendentes." else "Esta é a primeira.",
                         type = "message")
      }
    } else {
      posicao(destino)
    }
  }
  observeEvent(input$val_proxima, ir_para(1))
  observeEvent(input$val_anterior, ir_para(-1))

  postagem_atual <- reactive({
    d <- dados_val()
    req(nrow(d) > 0)
    d[min(posicao(), nrow(d)), ]
  })

  # Seleção inicial: a validação já salva ou, se pendente, a sugestão da IA
  selecao_inicial <- function(r) {
    if (isTRUE(r$validada)) chaves_marcadas(r, "final_") else chaves_marcadas(r, "ia_sugestao_")
  }

  # Quando não há mais pendentes: aviso com o caminho para o relatório
  output$conclusao_val <- renderUI({
    d <- dados_val()
    req(nrow(d) > 0, !any(pendente(d)))
    div(class = "alert alert-success d-flex justify-content-between align-items-center flex-wrap gap-2",
        div(icon("circle-check"), tags$b(" Validação concluída: "),
            sprintf("as %d postagens desta rodada foram validadas. ", nrow(d)),
            actionLink("ver_acuracia", "Ver a acurácia da IA")),
        actionButton("ir_relatorio", "Ir para o relatório", icon = icon("arrow-right"),
                     class = "btn-success"))
  })

  ir_para_relatorio <- function() {
    removeModal()
    m <- ler_rodada(input$rodada_val)
    updateRadioButtons(session, "periodo_tipo", selected = "semana")
    nav_select("abas", "relatorio")
  }
  observeEvent(input$ir_relatorio, ir_para_relatorio())
  observeEvent(input$ir_relatorio_modal, ir_para_relatorio())
  observeEvent(input$ver_acuracia, { removeModal(); nav_select("sub_validacao", "Acurácia da IA") })
  observeEvent(input$ver_acuracia_modal, { removeModal(); nav_select("sub_validacao", "Acurácia da IA") })

  output$aviso_remoto <- renderUI({
    id <- req(input$rodada_val)
    req(rodada_existe(id))
    if (!isTRUE(ler_rodada(id)$remota)) return(NULL)
    div(class = "alert alert-info small",
        icon("people-group"), " Esta rodada também está na Planilha Google. As validações feitas pelo link ",
        "aparecem aqui ao clicar em ", tags$b("Trazer validações"), " (aba Validação compartilhada).")
  })

  output$cartao_validacao <- renderUI({
    if (length(rodadas()) == 0) {
      return(div(class = "p-4 text-muted", "Nenhuma rodada ainda. Faça a categorização na aba 1."))
    }
    d <- dados_val()
    r <- postagem_atual()
    i <- min(posicao(), nrow(d))
    transcricao <- if (!texto_vazio(r$transcricao)) r$transcricao else NULL

    session$sendCustomMessage("instagram", list())

    tagList(
      div(class = "d-flex justify-content-between align-items-center flex-wrap gap-2 mb-3",
          div(tags$b(r$candidato), " · ", format(as.Date(r$data), "%d/%m/%Y"), " · ",
              span(class = "text-muted", r$shortCode, " · ", r$formato)),
          div(sprintf("%d de %d", i, nrow(d)),
              if (r$validada) span(class = "badge bg-success ms-2", "validada") else
                span(class = "badge bg-secondary ms-2", "pendente"))),
      layout_columns(
        col_widths = c(5, 7),
        div(midia_postagem(r),
            div(class = "mt-2",
                span(class = "pill", "♥ ", num(r$likes)),
                span(class = "pill", "💬 ", num(r$comentarios)),
                if (!is.na(r$url)) tags$a(class = "pill", href = r$url, target = "_blank", "Instagram ↗"))),
        div(
          div(class = "rotulo-secao", "Legenda"),
          div(class = "legenda", r$caption %|% "Sem legenda"),
          if (!is.null(transcricao))
            tags$details(tags$summary(class = "rotulo-secao", "Transcrição do vídeo"),
                         div(class = "legenda", transcricao))
          else if (!is.na(r$transcricao))
            div(class = "rotulo-secao", "Vídeo: ", span(class = "text-muted", r$transcricao)),
          div(class = "rotulo-secao d-flex justify-content-between",
              span("Classificação"), span(id = "contador-final")),
          tabela_validacao(r, selecao_inicial(r)),
          div(class = "small text-muted mt-1",
              span(class = "ponto on"), " = a IA marcou nesta fonte · — = a postagem não tem esta fonte · ",
              "Os interruptores começam com a sugestão da IA (o que pelo menos metade das fontes marcou).")
        )
      ),
      div(class = "d-flex justify-content-between align-items-center flex-wrap gap-2 mt-3 pt-3 border-top",
          div(radioButtons("v_fmt", "Formato", inline = TRUE,
                           c(set_names("manter", paste0("Manter (", r$formato %|% "—", ")")),
                             "Produzido por IA" = "ia"),
                           selected = if (identical(r$formato, "Produzido por IA")) "ia" else "manter")),
          div(class = "d-flex gap-2 flex-wrap",
              tags$button(id = "v_sugestao", type = "button", class = "btn btn-outline-secondary btn-sm",
                          icon("wand-magic-sparkles"), " Sugestão da IA"),
              tags$button(id = "v_nenhuma", type = "button", class = "btn btn-outline-secondary btn-sm",
                          "Nenhuma se aplica"))),
      div(class = "d-flex justify-content-between mt-3",
          actionButton("val_anterior", "Anterior", icon = icon("chevron-left")),
          div(actionButton("val_proxima", "Pular", icon = icon("forward")),
              actionButton("val_confirmar", "Confirmar e próxima", icon = icon("check"),
                           class = "btn-primary")))
    )
  })

  observeEvent(input$val_confirmar, {
    r <- postagem_atual()
    escolha <- input$v_final
    final <- if (!is.null(escolha) && identical(escolha$sc, r$shortCode)) unlist(escolha$chaves) else selecao_inicial(r)
    final <- intersect(final %||% character(), CHAVES)
    formato_original <- ler_classificados(input$rodada_val) %>% filter(shortCode == r$shortCode) %>% pull(formato)
    salvar_validacao(
      input$rodada_val, r$shortCode, final,
      formato = if (identical(input$v_fmt, "ia")) "Produzido por IA" else formato_original[1],
      avaliador = input$avaliador
    )
    versao_val(versao_val() + 1)

    # Acabaram as pendentes: oferece ver a acurácia e ir para o relatório
    if (!any(pendente(dados_val()))) {
      showModal(modalDialog(
        title = tagList(icon("circle-check"), " Validação concluída"),
        sprintf("Todas as %d postagens da rodada foram validadas.", nrow(dados_val())),
        footer = tagList(
          modalButton("Continuar revisando"),
          actionButton("ver_acuracia_modal", "Ver acurácia da IA", icon = icon("bullseye")),
          actionButton("ir_relatorio_modal", "Ir para o relatório",
                       icon = icon("arrow-right"), class = "btn-primary")
        ),
        easyClose = TRUE
      ))
      return()
    }
    ir_para(1)
  })

  output$baixar_validada <- downloadHandler(
    filename = function() paste0("base_validada_", input$rodada_val, ".csv"),
    content = function(file) exportar_base_validada(input$rodada_val, file)
  )

  # ---- Acurácia da IA ------------------------------------
  output$painel_acuracia <- renderUI({
    d <- dados_val()
    if (sum(d$validada) == 0) {
      return(div(class = "p-4 text-muted", "A acurácia aparece aqui assim que houver postagens validadas."))
    }
    a <- acuracia(d)
    comb <- a %>% filter(fonte == "IA combinada")
    pct0 <- function(x) if (is.na(x)) "—" else paste0(round(100 * x), "%")
    tagList(
      p(class = "text-muted",
        "Calculada sobre as ", tags$b(sum(d$validada)), " postagens já validadas desta rodada. ",
        tags$b("Acurácia"), " = de tudo o que a IA marcou, quanto a validação humana manteve."),
      indicadores(
        indicador("Acurácia (IA combinada)", pct0(comb$acuracia),
                  sprintf("%d de %d marcações confirmadas", comb$acertos, comb$marcadas), "bullseye", "destaque"),
        indicador("Cobertura", pct0(comb$cobertura),
                  "das subcategorias finais a IA já tinha marcado", "magnifying-glass"),
        indicador("Postagens 100% certas", pct0(comb$exatas),
                  "a IA acertou exatamente o conjunto final", "circle-check")
      ),
      accordion(
        class = "principal", open = "fontes", multiple = TRUE,
        accordion_panel(
          "Por fonte", value = "fontes", icon = icon("layer-group"),
          tableOutput("tabela_acuracia_fontes"),
          p(class = "dica",
            "IA combinada = subcategorias marcadas por pelo menos metade das fontes (é a sugestão que já vem ligada na validação).")),
        accordion_panel("Por subcategoria (IA combinada)", value = "subs", icon = icon("list"),
                        tableOutput("tabela_acuracia_subs"))
      ),
      div(downloadButton("baixar_acuracia", "Baixar acurácia (.csv)", class = "btn-sm btn-light"))
    )
  })

  formatar_pct <- function(x) ifelse(is.na(x), "—", paste0(round(100 * x, 1), "%"))

  output$tabela_acuracia_fontes <- renderTable({
    acuracia(dados_val()) %>%
      transmute(Fonte = fonte, `Postagens` = postagens, `Marcações da IA` = marcadas,
                `Confirmadas` = acertos, `Acurácia` = formatar_pct(acuracia),
                `Cobertura` = formatar_pct(cobertura), `Postagens 100% certas` = formatar_pct(exatas))
  }, digits = 0)

  output$tabela_acuracia_subs <- renderTable({
    acuracia_por_subcategoria(dados_val()) %>%
      transmute(Categoria = categoria, Subcategoria = subcategoria, `IA marcou` = ia_marcou,
                `Confirmadas` = confirmadas, `Acrescentadas pela validação` = acrescentadas,
                `Acurácia` = formatar_pct(acuracia))
  }, digits = 0)

  output$baixar_acuracia <- downloadHandler(
    filename = function() paste0("acuracia_", input$rodada_val, ".csv"),
    content = function(file) {
      d <- dados_val()
      bind_rows(acuracia(d) %>% mutate(nivel = "fonte"),
                acuracia_por_subcategoria(d) %>% mutate(nivel = "subcategoria")) %>%
        write_csv(file, na = "")
    }
  )

  # ---- Excluir rodada --------------------------------------
  observeEvent(input$excluir_rodada, {
    id <- req(input$rodada_val)
    prog <- progresso_rodada(id)
    showModal(modalDialog(
      title = "Excluir esta rodada?",
      p(tags$b(rotulo_rodada(id)), sprintf(" — %d postagens, %d validadas.", prog$total, prog$feitas)),
      p("A classificação e as validações desta rodada serão apagadas. As imagens e vídeos baixados ",
        "continuam em ", code("midia/"), ". Esta ação não pode ser desfeita."),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("confirmar_excluir_rodada", "Excluir rodada", class = "btn-danger")),
      easyClose = TRUE
    ))
  })
  observeEvent(input$confirmar_excluir_rodada, {
    excluir_rodada(input$rodada_val)
    removeModal()
    atualizar_listas()
    versao_val(versao_val() + 1)
    showNotification("Rodada excluída.", type = "message")
  })

  # ---- Validação compartilhada (Planilha Google) ---------
  versao_remota <- reactiveVal(0)
  status_remoto <- reactiveVal(NULL)

  output$painel_remoto <- renderUI({
    versao_remota()
    cfg <- ler_config_remota()
    configurada <- remota_configurada()
    id <- input$rodada_val
    enviada <- rodada_existe(id) && isTRUE(ler_rodada(id)$remota)
    st <- status_remoto()

    feitos <- c(configurada, enviada, FALSE, FALSE)
    tagList(
      p(class = "text-muted small",
        "Para várias pessoas validarem ao mesmo tempo, cada uma no seu computador, por um link. ",
        "As postagens e as respostas ficam numa Planilha Google no seu Drive. Clique num passo para abri-lo."),

      accordion(
      class = "principal passos", multiple = TRUE,
      # Abre o primeiro passo que falta (e o 4, quando já há andamento para mostrar)
      open = unique(c(paste0("passo", which(!feitos)[1]), if (enviada) c("passo3", "passo4"))),
      passo(1, "Preparar a planilha (só na primeira vez)", feito = configurada,
            if (configurada) p(class = "small mb-2", "Planilha conectada. ",
                               actionLink("refazer_config", "Refazer a configuração")),
            if (!configurada || isTRUE(input$refazer_config > 0)) tagList(
              tags$ol(class = "small",
                tags$li("No Google Drive, crie uma ", tags$b("Planilha Google"), " nova."),
                tags$li("Na planilha, abra ", tags$b("Extensões → Apps Script"), "."),
                tags$li("Apague o que estiver em ", code("Código.gs"), " e cole o conteúdo do arquivo ",
                        downloadLink("baixar_codigo_gs", "Codigo.gs"), " (já vem com a sua senha)."),
                tags$li("Clique em ", tags$b("+ → HTML"), ", dê o nome ", code("Validador"),
                        " e cole o conteúdo de ", downloadLink("baixar_validador_html", "Validador.html"), "."),
                tags$li("Clique em ", tags$b("Implantar → Nova implantação → App da Web"), ", com ",
                        tags$b("Executar como: Eu"), " e ", tags$b("Quem pode acessar: Qualquer pessoa"),
                        ". Autorize quando o Google pedir."),
                tags$li("Copie o ", tags$b("URL do App da Web"), " (termina em /exec) e cole abaixo.")
              ),
              div(class = "d-flex gap-2 align-items-end flex-wrap",
                  div(style = "flex: 1; min-width: 260px",
                      textInput("remota_url", NULL, cfg$url %||% "", width = "100%",
                                placeholder = "https://script.google.com/macros/s/.../exec")),
                  div(class = "mb-3", actionButton("salvar_remota", "Conectar e testar", icon = icon("plug"),
                                                   class = "btn-primary")))
            )),

      passo(2, "Enviar a rodada para a planilha", feito = enviada,
            p(class = "small", "Rodada escolhida na barra lateral: ", code(id %||% "—"),
              ". O que você já validou aqui vai junto, marcado como feito."),
            if (configurada)
              actionButton("enviar_remota", if (enviada) "Reenviar (acrescenta postagens novas)" else "Enviar esta rodada",
                           icon = icon("cloud-arrow-up"), class = if (enviada) "btn-sm" else "btn-primary")
            else p(class = "small text-muted", "Disponível depois do passo 1.")),

      passo(3, "Convidar os pesquisadores", feito = FALSE,
            if (configurada) tagList(
              div(class = "input-group mb-2",
                  tags$input(type = "text", class = "form-control", readonly = NA, value = cfg$url),
                  actionButton("copiar_link", "Copiar link", icon = icon("copy"), class = "btn-outline-primary")),
              actionButton("copiar_convite", "Copiar mensagem de convite", icon = icon("envelope"), class = "btn-sm"),
              tags$a(href = cfg$url, target = "_blank", class = "btn btn-sm btn-link", "Abrir o validador ↗"),
              p(class = "small text-muted mt-2",
                "Cada pessoa digita o nome e valida uma postagem por vez. Ninguém recebe a mesma postagem ao mesmo tempo.")
            ) else p(class = "small text-muted", "Disponível depois do passo 1.")),

      passo(4, "Acompanhar e trazer as validações", feito = FALSE,
            if (!enviada) p(class = "small text-muted", "Disponível depois de enviar a rodada (passo 2).")
            else div(class = "d-flex gap-2 flex-wrap mb-2",
                     actionButton("atualizar_status", "Ver andamento", icon = icon("rotate"), class = "btn-sm"),
                     actionButton("sincronizar", "Trazer validações para o app", icon = icon("cloud-arrow-down"),
                                  class = "btn-primary btn-sm")),
            if (!is.null(st)) tagList(
              div(class = "small mb-1", sprintf("Rodada no link: %s · %d de %d validadas", st$rodada, st$feitas, st$total)),
              div(class = "progress mb-2", style = "height: 8px",
                  div(class = "progress-bar bg-success", style = sprintf("width: %d%%", round(100 * st$feitas / max(1, st$total))))),
              if (length(st$avaliadores) > 0)
                tags$table(class = "table table-sm small w-auto",
                           tags$tr(tags$th("Pesquisador(a)"), tags$th("Validadas")),
                           imap(st$avaliadores, \(n, nome) tags$tr(tags$td(nome), tags$td(n))))
            ))
      )
    )
  })

  output$baixar_codigo_gs <- downloadHandler(
    filename = function() "Codigo.gs",
    content = function(file) writeLines(codigo_apps_script(), file, useBytes = TRUE)
  )
  output$baixar_validador_html <- downloadHandler(
    filename = function() "Validador.html",
    content = function(file) file.copy(arquivo_app("apps_script/Validador.html"), file)
  )

  observeEvent(input$salvar_remota, {
    salvar_config_remota(input$remota_url, token_remoto())
    resultado <- tryCatch(status_google(), error = notificar_erro("Não consegui falar com a planilha:"))
    if (!is.null(resultado)) {
      showNotification("Planilha Google conectada!", type = "message")
      status_remoto(resultado)
    }
    versao_remota(versao_remota() + 1)
  })

  observeEvent(input$enviar_remota, {
    id <- req(input$rodada_val)
    r <- tryCatch(
      withProgress(message = "Enviando postagens para a planilha…", enviar_rodada_google(id)),
      error = notificar_erro("Não foi possível enviar:")
    )
    req(r)
    showNotification(sprintf("Planilha atualizada: %d postagens novas (%d já estavam lá). O link agora abre esta rodada.",
                             r$inseridas, r$ja_existiam), type = "message", duration = 10)
    status_remoto(tryCatch(status_google(), error = function(e) NULL))
    versao_remota(versao_remota() + 1)
  })

  observeEvent(input$copiar_link, {
    session$sendCustomMessage("copiar", list(texto = ler_config_remota()$url))
    showNotification("Link copiado!", type = "message")
  })
  observeEvent(input$copiar_convite, {
    texto <- paste0(
      "Olá! Preciso da sua ajuda para validar a classificação das postagens desta rodada.\n\n",
      "1. Abra o link: ", ler_config_remota()$url, "\n",
      "2. Digite o seu nome e clique em Começar.\n",
      "3. Para cada postagem, confira o que a IA encontrou na legenda, na imagem e no vídeo, ",
      "ligue ou desligue as subcategorias e clique em Confirmar e próxima.\n\n",
      "Você pode parar quando quiser e voltar depois. Obrigado!"
    )
    session$sendCustomMessage("copiar", list(texto = texto))
    showNotification("Mensagem de convite copiada! Cole no WhatsApp ou no e-mail.", type = "message")
  })

  observeEvent(input$atualizar_status, {
    status_remoto(tryCatch(status_google(), error = notificar_erro("Não foi possível ver o andamento:")))
  })

  observeEvent(input$sincronizar, {
    n <- tryCatch(
      withProgress(message = "Buscando validações na planilha…", sincronizar_google(input$rodada_val)),
      error = notificar_erro("Não foi possível sincronizar:")
    )
    req(!is.null(n))
    versao_val(versao_val() + 1)
    status_remoto(tryCatch(status_google(), error = function(e) NULL))
    showNotification(sprintf("%d validação(ões) nova(s) trazida(s) da planilha.", n), type = "message")
  })

  # =======================================================
  # 3 · RELATÓRIO
  # =======================================================

  versao_rel <- reactiveVal(0)   # muda quando análises/relatório são salvos ou excluídos

  observeEvent(input$csv_validado, {
    id <- tryCatch(importar_csv_validado(input$csv_validado$datapath),
                   error = notificar_erro("Não foi possível importar o CSV:"))
    req(id)
    atualizar_listas(id)
    showNotification(paste("CSV importado como a rodada", rotulo_rodada(id)), type = "message")
  })

  # Postagens validadas da base escolhida (uma rodada ou todas)
  base_rel <- reactive({
    versao_val()
    rodadas()
    d <- if (identical(input$base_modo, "rodada")) {
      req(rodada_existe(input$rodada_rel))
      base_validada_rodada(input$rodada_rel) %>% mutate(rodada = input$rodada_rel)
    } else {
      base_validada_todas(rodadas())
    }
    if (nrow(d) == 0) return(d)
    tryCatch(aplicar_validacao(d), error = notificar_erro("Erro ao ler a base:"))
  })

  # Postagens ainda não validadas na base escolhida
  pendentes_rel <- reactive({
    versao_val()
    ids <- if (identical(input$base_modo, "rodada")) req(input$rodada_rel) else rodadas()
    ids <- keep(ids, rodada_existe)
    sum(map_int(ids, \(id) { p <- progresso_rodada(id); p$total - p$feitas }))
  })

  # Período escolhido: um dos botões do relatório, com as datas tiradas da base
  periodo_sel <- reactive({
    d <- base_rel()
    req(nrow(d) > 0)
    modo <- req(input$periodo_tipo)
    j <- janela_relatorio(d$data, modo)
    list(tipo = modo, inicio = j$inicio, fim = j$fim, id = id_periodo(modo, j$inicio, j$fim),
         rotulo = j$rotulo, frase = j$texto_periodo)
  })

  # Datas atuais de cada botão (para saber quais textos salvos entram no relatório)
  botoes_atuais <- reactive({
    d <- base_rel()
    if (nrow(d) == 0) return(list())
    map(set_names(names(MODOS_RELATORIO)), \(m) {
      j <- janela_relatorio(d$data, m)
      list(inicio = as.character(j$inicio), fim = as.character(j$fim))
    })
  })

  output$periodo_datas_txt <- renderUI({
    p <- periodo_sel()
    div(class = "dica", icon("calendar"), " ", p$rotulo)
  })

  d_periodo <- reactive({
    p <- periodo_sel()
    base_rel() %>% filter(data >= p$inicio, data <= p$fim)
  })

  # Ao mudar de período: rótulo e texto (o salvo, se houver; senão o rascunho automático)
  ultimo_periodo <- reactiveVal("")
  carregar_texto_periodo <- function(forcar_rascunho = FALSE) {
    p <- periodo_sel()
    d <- d_periodo()
    rascunho <- if (nrow(d) > 0) gerar_rascunho(d, p$frase) else ""
    salvo <- id_salvo(ler_periodos(), p$tipo, p$inicio, p$fim)
    texto <- if (forcar_rascunho || is.null(salvo)) rascunho else texto_salvo(salvo) %||% rascunho
    updateTextAreaInput(session, "texto_rel", value = texto)
  }
  observe({
    p <- periodo_sel()
    if (identical(p$id, isolate(ultimo_periodo()))) return()
    ultimo_periodo(p$id)
    isolate(carregar_texto_periodo())
  })
  observeEvent(input$rascunho, carregar_texto_periodo(forcar_rascunho = TRUE))

  observeEvent(input$redigir_ia, {
    d <- d_periodo()
    req(nrow(d) > 0)
    texto <- tryCatch(
      withProgress(message = "A IA está redigindo as considerações finais…", value = 0.3, {
        redigir_com_ia(d, input$texto_rel, MODELO_PADRAO)
      }),
      error = notificar_erro("Não foi possível redigir com IA:")
    )
    req(texto)
    updateTextAreaInput(session, "texto_rel", value = texto)
    showNotification("Texto redigido. Revise antes de salvar.", type = "message")
  })

  texto_periodo_atual <- function() {
    p <- periodo_sel()
    salvo <- id_salvo(ler_periodos(), p$tipo, p$inicio, p$fim)
    if (is.null(salvo)) NULL else texto_salvo(salvo)
  }

  salvar_texto_atual <- function() {
    p <- periodo_sel()
    salvar_periodo(p$tipo, p$inicio, p$fim, p$rotulo, texto = input$texto_rel)
    versao_rel(versao_rel() + 1)
  }
  observeEvent(input$salvar_periodo, {
    req(nzchar(str_trim(input$texto_rel)))
    salvar_texto_atual()
    showNotification("Texto salvo. Ele aparece no relatório na próxima vez que você gerar.", type = "message")
  })

  output$resumo_rel <- renderUI({
    if (length(rodadas()) == 0) {
      return(card(vazio("file-lines", "Nenhuma rodada ainda",
                        p("Faça a categorização (aba 1) ou importe um CSV já validado na barra ao lado."))))
    }
    d <- d_periodo()
    pend <- pendentes_rel()
    ac <- if (nrow(d) > 0) acuracia(d) %>% filter(fonte == "IA combinada") else NULL
    indicadores(
      indicador("Postagens no período", num(nrow(d)), periodo_sel()$rotulo, "database"),
      indicador("Ainda sem validação", num(pend),
                if (pend > 0) "não entram no relatório" else "tudo validado", "user-check",
                if (pend > 0) "aviso" else "ok"),
      indicador("Acurácia da IA no período",
                if (is.null(ac) || is.na(ac$acuracia)) "—" else paste0(round(100 * ac$acuracia), "%"),
                "das marcações da IA mantidas na validação", "bullseye", "destaque")
    )
  })

  # ---- Análises salvas -------------------------------------
  output$lista_periodos <- renderUI({
    versao_rel()
    p <- ler_periodos() %>% arrange(desc(fim), desc(salvo_em))
    if (nrow(p) == 0) return(p(class = "text-muted small", "Nenhuma análise salva ainda."))
    atuais <- botoes_atuais()
    tipo <- c(periodo = "Datas", MODOS_RELATORIO)
    tagList(
    p(class = "small text-muted",
      "Aparecem no relatório os textos cujas datas são as do trecho mais recente de cada botão. ",
      "Os demais ficam guardados como registro."),
    tags$table(
      class = "table table-sm align-middle small",
      tags$tr(tags$th("Botão"), tags$th("Período"), tags$th("Texto"), tags$th("No relatório"), tags$th("")),
      map(seq_len(nrow(p)), \(i) {
        r <- p[i, ]
        resumo <- str_trunc(str_squish(texto_salvo(r$id) %||% ""), 90)
        no_rel <- names(atuais)[map_lgl(atuais, \(a) identical(a$inicio, r$inicio) && identical(a$fim, r$fim))]
        tags$tr(
          tags$td(tipo[[r$tipo]] %||% r$tipo), tags$td(r$rotulo), tags$td(class = "text-muted", resumo),
          tags$td(if (length(no_rel)) tags$span(class = "badge bg-success", paste(MODOS_RELATORIO[no_rel], collapse = ", "))
                  else tags$span(class = "text-muted", "registro")),
          tags$td(class = "text-nowrap",
                  if (length(no_rel)) tags$a(href = "#", class = "me-2",
                         onclick = sprintf("Shiny.setInputValue('editar_periodo', '%s', {priority: 'event'}); return false;", r$id),
                         icon("pen"), " Editar"),
                  tags$a(href = "#", class = "text-danger",
                         onclick = sprintf("Shiny.setInputValue('excluir_periodo', '%s', {priority: 'event'}); return false;", r$id),
                         icon("trash-can"), " Excluir"))
        )
      })
    ))
  })

  # Editar: escolhe o período salvo no formulário (o texto salvo é carregado)
  observeEvent(input$editar_periodo, {
    r <- ler_periodos() %>% filter(id == input$editar_periodo)
    req(nrow(r) == 1)
    atuais <- botoes_atuais()
    modo <- names(atuais)[map_lgl(atuais, \(a) identical(a$inicio, r$inicio) && identical(a$fim, r$fim))]
    req(length(modo) > 0)
    updateRadioButtons(session, "periodo_tipo", selected = if (r$tipo %in% modo) r$tipo else modo[1])
    ultimo_periodo("")   # força recarregar o texto salvo
  })

  observeEvent(input$excluir_periodo, {
    r <- ler_periodos() %>% filter(id == input$excluir_periodo)
    req(nrow(r) == 1)
    showModal(modalDialog(
      title = "Excluir esta análise?",
      p(tags$b(r$rotulo)),
      p("O texto deste período será apagado e ele deixa de aparecer no relatório ",
        "(os dados validados continuam guardados). Gere o relatório de novo para atualizar o arquivo."),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("confirmar_excluir_periodo", "Excluir análise", class = "btn-danger")),
      easyClose = TRUE
    ))
  })
  observeEvent(input$confirmar_excluir_periodo, {
    excluir_periodo(input$excluir_periodo)
    removeModal()
    versao_rel(versao_rel() + 1)
    ultimo_periodo("")
    showNotification("Análise excluída.", type = "message")
  })

  # ---- Candidatos ----------------------------------------
  candidatos_info <- reactiveVal(ler_candidatos_info())

  observe({
    updateSelectInput(session, "foto_candidato", choices = candidatos_info()$nome)
  })

  output$tabela_candidatos <- renderDT({
    datatable(candidatos_info() %>% select(-id),
              colnames = c("Nome", "Partido · número", "Intenção de voto", "Seguidores IG", "Arquivo da foto"),
              editable = list(target = "cell"),
              rownames = FALSE, options = list(dom = "t", ordering = FALSE, pageLength = 50))
  })

  observeEvent(input$tabela_candidatos_cell_edit, {
    info <- candidatos_info()
    e <- input$tabela_candidatos_cell_edit
    info[e$row, e$col + 2] <- e$value   # +2: coluna "id" escondida e índice começando em 0
    salvar_candidatos_info(info)
    candidatos_info(info)
  })

  observeEvent(input$foto_arquivo, {
    nome <- req(input$foto_candidato)
    info <- candidatos_info()
    extensao <- tolower(tools::file_ext(input$foto_arquivo$name))
    base_nome <- normalizar_nome(info$id[info$nome == nome][1]) %>% str_replace_all("[^a-z0-9]+", "_")
    arquivo <- paste0(base_nome, ".", if (extensao == "jpeg") "jpg" else extensao)
    dir.create("assets/img_cand", showWarnings = FALSE, recursive = TRUE)
    file.copy(input$foto_arquivo$datapath, file.path("assets/img_cand", arquivo), overwrite = TRUE)
    info$foto[info$nome == nome] <- arquivo
    salvar_candidatos_info(info)
    candidatos_info(info)
    showNotification(paste("Foto de", nome, "atualizada."), type = "message")
  })

  observeEvent(input$adicionar_candidato, {
    nome <- str_squish(input$novo_candidato)
    req(nzchar(nome))
    candidatos_info(completar_candidatos_info(nome))
    updateTextInput(session, "novo_candidato", value = "")
  })

  # ---- Sobre a pesquisa ----------------------------------
  output$quadros_sobre <- renderUI({
    quadros <- ler_sobre()
    do.call(layout_columns, c(
      list(col_widths = 6),
      imap(quadros, \(q, i) {
        div(class = "quadro-sobre mb-2",
            textInput(paste0("sobre_titulo_", i), NULL, q$titulo),
            textAreaInput(paste0("sobre_texto_", i), NULL, q$texto, rows = 5, width = "100%"))
      })
    ))
  })

  # Os campos ficam num painel recolhido: são criados mesmo com o painel fechado
  outputOptions(output, "quadros_sobre", suspendWhenHidden = FALSE)

  # Textos da tela; se um campo ainda não existir, mantém o texto salvo
  sobre_atual <- function() {
    salvos <- ler_sobre()
    imap(salvos, \(q, i) list(titulo = input[[paste0("sobre_titulo_", i)]] %||% q$titulo,
                              texto = input[[paste0("sobre_texto_", i)]] %||% q$texto))
  }

  observeEvent(input$salvar_sobre, {
    salvar_sobre(sobre_atual())
    showNotification("Textos do “Sobre a pesquisa” salvos.", type = "message")
  })

  # ---- Gerar ---------------------------------------------
  observeEvent(input$gerar_rel, {
    d <- base_rel()
    if (nrow(d) == 0) {
      showNotification("Ainda não há postagens validadas. Valide na aba 2 antes de gerar o relatório.",
                       type = "warning", duration = 8)
      return()
    }
    if (str_detect(input$texto_rel, "\\[[^\\]]+\\]")) {
      showNotification("Atenção: o texto ainda tem lembretes entre [colchetes].", type = "warning", duration = 8)
    }
    # Salva o texto do período só se ele mudou (preserva a formatação dos textos antigos)
    texto_atual <- str_trim(input$texto_rel)
    if (nzchar(texto_atual) && !identical(texto_atual, str_trim(texto_periodo_atual() %||% ""))) {
      salvar_texto_atual()
    }
    sobre <- sobre_atual()
    salvar_sobre(sobre)
    # % de postagens analisadas: o da rodada mais recente (não histórica)
    recentes <- keep(rodadas(), \(id) !isTRUE(ler_rodada(id)$historico))
    proporcao <- if (length(recentes)) ler_rodada(recentes[1])$proporcao %||% PROPORCAO_TOP_PADRAO else PROPORCAO_TOP_PADRAO
    ok <- tryCatch({
      withProgress(message = "Gerando o relatório…", value = 0.5,
                   gerar_relatorio(d, periodo_inicial = periodo_sel()$id, proporcao = proporcao,
                                   modelo_rotulo = input$modelo_rotulo, sobre = sobre))
      TRUE
    }, error = notificar_erro("Erro ao gerar o relatório:"))
    req(ok)
    candidatos_info(ler_candidatos_info())
    versao_rel(versao_rel() + 1)
    showNotification("Relatório gerado!", type = "message")
  })

  output$resultado_rel <- renderUI({
    versao_rel()
    arquivo <- file.path(PASTA_RELATORIO, "index.html")
    if (!file.exists(arquivo)) return(NULL)
    card(
      card_header(class = "ok cabecalho-acoes",
                  span(icon("circle-check"), " Relatório gerado em ", format(file.mtime(arquivo), "%d/%m/%Y %H:%M")),
                  actionLink("excluir_rel", tagList(icon("trash-can"), " Excluir"), class = "small text-danger")),
      card_body(
        div(class = "d-flex gap-2 flex-wrap",
            actionButton("abrir_rel", "Abrir no navegador", icon = icon("up-right-from-square"), class = "btn-sm btn-primary"),
            downloadButton("baixar_rel", "Baixar (.html com as fotos)", class = "btn-sm btn-light"),
            downloadButton("baixar_monit", "Dados (.csv)", class = "btn-sm btn-light")),
        p(class = "dica mt-2 mb-0",
          "A pasta ", code(PASTA_RELATORIO), " (index.html, dados e ", code("assets/img_cand"),
          ") está pronta para publicar, por exemplo no GitHub Pages.")
      )
    )
  })

  output$baixar_rel <- downloadHandler(
    filename = function() "relatorio.html",
    # Arquivo único: as fotos de assets/img_cand vão dentro do HTML
    content = function(file) {
      html <- paste(readLines(file.path(PASTA_RELATORIO, "index.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      writeLines(embutir_imagens(html), file, useBytes = TRUE)
    }
  )
  output$baixar_monit <- downloadHandler(
    filename = function() "monitoramento.csv",
    content = function(file) file.copy(file.path(PASTA_RELATORIO, "dados", "monitoramento.csv"), file)
  )
  observeEvent(input$abrir_rel, browseURL(normalizePath(file.path(PASTA_RELATORIO, "index.html"))))

  observeEvent(input$excluir_rel, {
    showModal(modalDialog(
      title = "Excluir o relatório gerado?",
      p("A pasta ", code(PASTA_RELATORIO), " (relatório, dados e fotos copiadas) será apagada. ",
        "As análises salvas e as validações continuam guardadas; dá para gerar de novo quando quiser."),
      footer = tagList(modalButton("Cancelar"),
                       actionButton("confirmar_excluir_rel", "Excluir relatório", class = "btn-danger")),
      easyClose = TRUE
    ))
  })
  observeEvent(input$confirmar_excluir_rel, {
    excluir_relatorio()
    removeModal()
    versao_rel(versao_rel() + 1)
    showNotification("Relatório excluído.", type = "message")
  })
}

shinyApp(ui, server)

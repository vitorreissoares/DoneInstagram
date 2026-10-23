/**
 * VALIDADOR COMPARTILHADO — Google Apps Script
 *
 * Fica dentro de uma Planilha Google (no seu Drive). A planilha guarda as
 * postagens e as validações; o link do "App da Web" abre o validador para
 * quantos pesquisadores forem necessários, ao mesmo tempo.
 *
 * Senha entre o app e a planilha: não precisa configurar nada. O primeiro
 * computador que se conectar (botão "Conectar e testar" no app) fica autorizado.
 * Para autorizar outro computador, escolha a função autorizarOutroComputador
 * no topo do editor, clique em Executar e, em até 30 minutos, conecte pelo app.
 */

// Versões anteriores traziam a senha escrita aqui; se houver uma, ela continua valendo.
const TOKEN = 'TROQUE-ESTE-TOKEN';
const MINUTOS_PARA_AUTORIZAR = 30;

const ABA = 'postagens';
const RESERVA_MINUTOS = 20; // tempo que uma postagem fica reservada para quem a abriu

const COLUNAS = [
  'id', 'rodada', 'candidato', 'url', 'caption', 'transcricao', 'likes', 'comentarios',
  'data', 'semana', 'shortCode', 'formato_original', 'fontes',
  'ia_legenda', 'ia_imagem', 'ia_transcricao', 'ia_sugestao',
  'final', 'formato', 'avaliador', 'validado_em', 'reservado_por', 'reservado_em'
];
const COL = Object.fromEntries(COLUNAS.map((c, i) => [c, i + 1]));


/* ---------------------------------------------------------
   Entradas do App da Web
   --------------------------------------------------------- */

// Sem parâmetros: abre o validador. Com ?acao=...: API usada pelo app em R.
function doGet(e) {
  const p = (e && e.parameter) || {};
  if (!p.acao) {
    return HtmlService.createHtmlOutputFromFile('Validador')
      .setTitle('Validador de classificação')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  }
  try {
    conferirToken_(p.token);
    if (p.acao === 'exportar') {
      const linhas = lerLinhas_().filter(l => !p.rodada || l.rodada === p.rodada);
      return json_({ ok: true, linhas: linhas.map(limpar_) });
    }
    if (p.acao === 'status') return json_(Object.assign({ ok: true }, progresso()));
    throw new Error('Ação desconhecida: ' + p.acao);
  } catch (err) {
    return json_({ ok: false, erro: err.message });
  }
}

// Recebe as postagens de uma rodada enviadas pelo app em R
function doPost(e) {
  try {
    const corpo = JSON.parse(e.postData.contents);
    conferirToken_(corpo.token);
    if (corpo.acao === 'enviar') return json_(Object.assign({ ok: true }, enviar_(corpo)));
    throw new Error('Ação desconhecida: ' + corpo.acao);
  } catch (err) {
    return json_({ ok: false, erro: err.message });
  }
}


/* ---------------------------------------------------------
   Autorização dos computadores que usam o app
   --------------------------------------------------------- */

// Aceita a senha de um computador já autorizado. Se a planilha ainda não tem
// nenhum (primeira conexão) ou se autorizarOutroComputador foi executada há
// pouco, o computador que está se conectando passa a ser autorizado.
function conferirToken_(token) {
  token = String(token || '');
  if (token.length < 12) throw new Error('Token inválido.');
  if (TOKEN !== 'TROQUE-ESTE-TOKEN' && token === TOKEN) return;
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const props = PropertiesService.getScriptProperties();
    const autorizados = JSON.parse(props.getProperty('tokens') || '[]');
    if (autorizados.indexOf(token) >= 0) return;
    const liberadoAte = Number(props.getProperty('liberar_ate') || 0);
    if (autorizados.length === 0 || Date.now() < liberadoAte) {
      autorizados.push(token);
      props.setProperty('tokens', JSON.stringify(autorizados));
      props.deleteProperty('liberar_ate');
      return;
    }
  } finally {
    lock.releaseLock();
  }
  throw new Error('Token inválido: este computador ainda não está autorizado nesta planilha.');
}

// Execute no editor do Apps Script para autorizar mais um computador
// (o próximo que se conectar nos próximos 30 minutos)
function autorizarOutroComputador() {
  PropertiesService.getScriptProperties()
    .setProperty('liberar_ate', String(Date.now() + MINUTOS_PARA_AUTORIZAR * 60 * 1000));
  Logger.log('Pronto. Agora, em até ' + MINUTOS_PARA_AUTORIZAR + ' minutos, clique em "Conectar e testar" no app do outro computador.');
}


/* ---------------------------------------------------------
   Funções chamadas pela página do validador (google.script.run)
   --------------------------------------------------------- */

function configuracao() {
  const props = PropertiesService.getScriptProperties();
  return {
    rodada: props.getProperty('rodada_ativa') || '',
    subcategorias: JSON.parse(props.getProperty('subcategorias') || '[]')
  };
}

// Entrega a próxima postagem pendente e a reserva para o avaliador,
// para que dois pesquisadores não validem a mesma postagem ao mesmo tempo
function proximaPostagem(avaliador) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const rodada = configuracao().rodada;
    const agora = new Date();
    const limite = RESERVA_MINUTOS * 60 * 1000;
    const linhas = lerLinhas_().filter(l => l.rodada === rodada);

    const livre = l => {
      if (l.validado_em) return false;
      if (!l.reservado_por || l.reservado_por === avaliador) return true;
      const quando = new Date(l.reservado_em);
      return isNaN(quando) || agora - quando > limite;
    };
    // Primeiro o que já estava reservado para esta pessoa, depois o resto
    const postagem = linhas.find(l => !l.validado_em && l.reservado_por === avaliador) || linhas.find(livre);

    if (postagem) {
      aba_().getRange(postagem._linha, COL.reservado_por, 1, 2)
        .setValues([[avaliador, agora.toISOString()]]);
    }
    return { postagem: postagem ? limpar_(postagem) : null, progresso: contar_(linhas, avaliador) };
  } finally {
    lock.releaseLock();
  }
}

// final: chaves separadas por ";" ("" = nenhuma subcategoria se aplica)
function salvarValidacao(id, final, formato, avaliador) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const linha = lerLinhas_().find(l => l.id === id);
    if (!linha) throw new Error('Postagem não encontrada: ' + id);
    aba_().getRange(linha._linha, COL.final, 1, 6).setValues([[
      final || '', formato || '', avaliador, new Date().toISOString(), '', ''
    ]]);
    const rodada = configuracao().rodada;
    return contar_(lerLinhas_().filter(l => l.rodada === rodada), avaliador);
  } finally {
    lock.releaseLock();
  }
}

function progresso() {
  const rodada = configuracao().rodada;
  return Object.assign({ rodada: rodada }, contar_(lerLinhas_().filter(l => l.rodada === rodada)));
}


/* ---------------------------------------------------------
   Auxiliares
   --------------------------------------------------------- */

function enviar_(corpo) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const aba = aba_();
    const existentes = new Set(lerLinhas_().map(l => l.id));
    const novas = (corpo.linhas || [])
      .map(l => Object.assign({}, l, { id: corpo.rodada + '|' + l.shortCode, rodada: corpo.rodada }))
      .filter(l => !existentes.has(l.id))
      .map(l => COLUNAS.map(c => texto_(l[c])));

    if (novas.length) {
      const inicio = aba.getLastRow() + 1;
      const intervalo = aba.getRange(inicio, 1, novas.length, COLUNAS.length);
      intervalo.setNumberFormat('@');
      intervalo.setValues(novas);
    }

    const props = PropertiesService.getScriptProperties();
    props.setProperty('rodada_ativa', corpo.rodada);
    if (corpo.subcategorias) props.setProperty('subcategorias', JSON.stringify(corpo.subcategorias));

    return { inseridas: novas.length, ja_existiam: (corpo.linhas || []).length - novas.length };
  } finally {
    lock.releaseLock();
  }
}

function aba_() {
  const planilha = SpreadsheetApp.getActiveSpreadsheet();
  let aba = planilha.getSheetByName(ABA);
  if (!aba) {
    aba = planilha.insertSheet(ABA);
    aba.getRange(1, 1, 1, COLUNAS.length).setValues([COLUNAS]).setFontWeight('bold');
    aba.setFrozenRows(1);
  }
  return aba;
}

function lerLinhas_() {
  const valores = aba_().getDataRange().getValues();
  const cabecalho = valores.shift() || [];
  return valores.map((v, i) => {
    const obj = { _linha: i + 2 };
    cabecalho.forEach((c, j) => { obj[c] = v[j] instanceof Date ? v[j].toISOString() : String(v[j] ?? ''); });
    return obj;
  });
}

// Totais da rodada e quantas cada avaliador já validou
function contar_(linhas, avaliador) {
  const porAvaliador = {};
  linhas.filter(l => l.validado_em).forEach(l => {
    porAvaliador[l.avaliador] = (porAvaliador[l.avaliador] || 0) + 1;
  });
  return {
    total: linhas.length,
    feitas: linhas.filter(l => l.validado_em).length,
    minhas: avaliador ? (porAvaliador[avaliador] || 0) : undefined,
    avaliadores: porAvaliador
  };
}

function limpar_(l) {
  const r = Object.assign({}, l);
  delete r._linha;
  return r;
}

// Textos que começam com = + - @ seriam lidos como fórmula pela planilha
function texto_(valor) {
  const s = valor === null || valor === undefined ? '' : String(valor);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

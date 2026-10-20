// =========================================================
// DONEINSTAGRAM — programa de computador
// Abre uma janela própria, inicia o R que vem junto com o programa
// (pasta resources/r) e mostra o app quando ele estiver pronto.
// Os dados de cada pessoa ficam em Documentos/DoneInstagram.
// =========================================================

const { app, BrowserWindow, Menu, shell, dialog } = require("electron");
const { spawn, execFile } = require("child_process");
const path = require("path");
const fs = require("fs");
const net = require("net");
const http = require("http");

const NOME = "DoneInstagram";
const TEMPO_MAXIMO_MS = 180000; // a primeira abertura pode demorar (antivírus, disco lento)

let janela = null;
let processoR = null;
let saindo = false;

// ---------------------------------------------------------
// Pastas
// ---------------------------------------------------------

// Em desenvolvimento (npm start), usa as pastas do repositório
const recursos = app.isPackaged ? process.resourcesPath : path.join(__dirname, "build", "recursos-dev");
const pastaApp = app.isPackaged ? path.join(recursos, "app") : path.join(__dirname, "..");
const pastaR = app.isPackaged ? path.join(recursos, "r") : path.join(__dirname, "r-env");
const scriptInicio = app.isPackaged ? path.join(recursos, "iniciar.R") : path.join(__dirname, "iniciar.R");
const pastaDados = process.env.DONEINSTAGRAM_DADOS || path.join(app.getPath("documents"), NOME);
const arquivoRegistro = path.join(pastaDados, "registro.txt");

// ---------------------------------------------------------
// Como chamar o R em cada sistema
// ---------------------------------------------------------

function comandoR(porta) {
  const sep = path.delimiter;
  const env = {
    ...process.env,
    DONEINSTAGRAM_APP: pastaApp,
    DONEINSTAGRAM_DADOS: pastaDados,
    DONEINSTAGRAM_PORTA: String(porta),
    R_LIBS_USER: "",          // usa só os pacotes que vêm com o programa
    R_PROFILE_USER: "",
    R_ENVIRON_USER: ""
  };
  delete env.R_HOME;
  delete env.R_LIBS;
  delete env.ELECTRON_RUN_AS_NODE;

  if (process.platform === "win32") {
    const certificados = path.join(pastaR, "Library", "ssl", "cacert.pem");
    env.PATH = [pastaR, path.join(pastaR, "Library", "mingw-w64", "bin"), path.join(pastaR, "Library", "usr", "bin"),
                path.join(pastaR, "Library", "bin"), path.join(pastaR, "Scripts"), path.join(pastaR, "bin"),
                process.env.PATH || ""].join(sep);
    if (fs.existsSync(certificados)) env.CURL_CA_BUNDLE = env.SSL_CERT_FILE = certificados;
    const rscript = [path.join(pastaR, "Lib", "R", "bin", "x64", "Rscript.exe"),
                     path.join(pastaR, "Lib", "R", "bin", "Rscript.exe"),
                     path.join(pastaR, "Scripts", "Rscript.exe")].find(f => fs.existsSync(f));
    return { exe: rscript, args: ["--no-save", "--no-restore", scriptInicio], env };
  }

  // macOS e Linux: chama o executável do R diretamente, indicando onde ele está
  const rHome = path.join(pastaR, "lib", "R");
  Object.assign(env, {
    R_HOME: rHome,
    R_SHARE_DIR: path.join(rHome, "share"),
    R_INCLUDE_DIR: path.join(rHome, "include"),
    R_DOC_DIR: path.join(rHome, "doc"),
    R_BROWSER: process.platform === "darwin" ? "open" : "xdg-open"
  });
  // Os arquivos do projeto têm acentos: o R precisa rodar em UTF-8.
  // No Linux, C.UTF-8 existe em todas as distribuições atuais; no Mac, en_US.UTF-8.
  const utf8 = process.platform === "darwin"
    ? (/utf-?8/i.test(process.env.LANG || "") ? process.env.LANG : "en_US.UTF-8")
    : "C.UTF-8";
  env.LANG = env.LC_ALL = utf8;
  env.PATH = [path.join(pastaR, "bin"), process.env.PATH || ""].join(sep);
  const certificados = path.join(pastaR, "ssl", "cacert.pem");
  if (fs.existsSync(certificados)) env.CURL_CA_BUNDLE = env.SSL_CERT_FILE = certificados;
  if (process.platform === "linux") {
    env.LD_LIBRARY_PATH = [path.join(pastaR, "lib"), path.join(rHome, "lib"), process.env.LD_LIBRARY_PATH || ""].join(sep);
  }
  return { exe: path.join(rHome, "bin", "exec", "R"),
           args: ["--no-save", "--no-restore", "--no-echo", "-f", scriptInicio], env };
}

// ---------------------------------------------------------
// Iniciar e encerrar o R
// ---------------------------------------------------------

function portaLivre() {
  return new Promise((resolve, reject) => {
    const servidor = net.createServer();
    servidor.unref();
    servidor.on("error", reject);
    servidor.listen(0, "127.0.0.1", () => {
      const { port } = servidor.address();
      servidor.close(() => resolve(port));
    });
  });
}

function respondendo(url) {
  return new Promise(resolve => {
    const req = http.get(url, res => { res.resume(); resolve(res.statusCode < 500); });
    req.on("error", () => resolve(false));
    req.setTimeout(2000, () => { req.destroy(); resolve(false); });
  });
}

function iniciarR(porta) {
  fs.mkdirSync(pastaDados, { recursive: true });
  const registro = fs.createWriteStream(arquivoRegistro, { flags: "w" });
  registro.write(`${NOME} ${app.getVersion()} · ${new Date().toISOString()} · ${process.platform}-${process.arch}\n`);
  const { exe, args, env } = comandoR(porta);
  if (!exe || !fs.existsSync(exe)) throw new Error(`Não encontrei o R do programa em ${pastaR}.`);
  processoR = spawn(exe, args, { env, cwd: pastaDados, windowsHide: true });
  processoR.stdout.pipe(registro);
  processoR.stderr.pipe(registro);
  processoR.on("exit", codigo => {
    processoR = null;
    if (!saindo) mostrarErro(`O R foi encerrado (código ${codigo}).`);
  });
}

function encerrarR() {
  if (!processoR) return;
  const pid = processoR.pid;
  if (process.platform === "win32") {
    execFile("taskkill", ["/pid", String(pid), "/T", "/F"], () => {});
  } else {
    processoR.kill("SIGTERM");
  }
  processoR = null;
}

// ---------------------------------------------------------
// Janela
// ---------------------------------------------------------

function ultimasLinhasRegistro() {
  try {
    return fs.readFileSync(arquivoRegistro, "utf8").split(/\r?\n/).slice(-25).join("\n");
  } catch (e) {
    return "";
  }
}

function mostrarErro(motivo) {
  if (!janela || janela.isDestroyed()) return;
  const detalhes = encodeURIComponent(`${motivo}\n\n${ultimasLinhasRegistro()}`);
  janela.loadFile(path.join(__dirname, "carregando.html"), { query: { erro: detalhes, registro: arquivoRegistro } });
}

function criarMenu() {
  const modelo = [
    ...(process.platform === "darwin" ? [{ role: "appMenu" }] : []),
    {
      label: "Arquivo",
      submenu: [
        { label: "Abrir pasta de dados", click: () => shell.openPath(pastaDados) },
        { label: "Recarregar", accelerator: "CmdOrCtrl+R", click: () => janela && janela.reload() },
        { type: "separator" },
        { role: "quit", label: "Sair" }
      ]
    },
    { role: "editMenu", label: "Editar" },
    {
      label: "Exibir",
      submenu: [
        { role: "zoomIn", label: "Aumentar" }, { role: "zoomOut", label: "Diminuir" },
        { role: "resetZoom", label: "Tamanho original" }, { type: "separator" },
        { role: "togglefullscreen", label: "Tela cheia" }
      ]
    },
    {
      label: "Ajuda",
      submenu: [
        { label: "Guia de uso (LEIA-ME)", click: () => shell.openPath(path.join(pastaApp, "LEIA-ME.md")) },
        { label: "Registro do programa", click: () => shell.openPath(arquivoRegistro) },
        { label: `Sobre o ${NOME}`, click: () => dialog.showMessageBox(janela, {
            type: "info", title: NOME, message: `${NOME} ${app.getVersion()}`,
            detail: `Seus dados ficam em:\n${pastaDados}` }) }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(modelo));
}

async function abrir() {
  criarMenu();
  janela = new BrowserWindow({
    width: 1440, height: 920, minWidth: 980, minHeight: 640,
    title: NOME, backgroundColor: "#f7f8fa", autoHideMenuBar: true, show: false,
    icon: path.join(__dirname, "build", "icon.png"),
    webPreferences: { contextIsolation: true, nodeIntegration: false, spellcheck: true }
  });
  janela.once("ready-to-show", () => janela.show());
  janela.on("page-title-updated", e => e.preventDefault());

  // Links externos (Instagram, OpenRouter, Planilha Google) abrem no navegador
  janela.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
  janela.webContents.on("will-navigate", (e, url) => {
    if (!url.startsWith("http://127.0.0.1") && !url.startsWith("file:")) {
      e.preventDefault();
      shell.openExternal(url);
    }
  });

  await janela.loadFile(path.join(__dirname, "carregando.html"));

  try {
    const porta = await portaLivre();
    iniciarR(porta);
    const url = `http://127.0.0.1:${porta}`;
    const inicio = Date.now();
    while (Date.now() - inicio < TEMPO_MAXIMO_MS) {
      if (!processoR) return;               // o R parou: o erro já foi mostrado
      if (await respondendo(url)) {
        await janela.loadURL(url);
        return;
      }
      await new Promise(r => setTimeout(r, 500));
    }
    mostrarErro("O programa demorou demais para abrir.");
  } catch (e) {
    mostrarErro(e.message);
  }
}

// Uma janela só: abrir o programa de novo traz a janela existente para a frente
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (janela) { if (janela.isMinimized()) janela.restore(); janela.focus(); }
  });
  app.whenReady().then(abrir);
  app.on("before-quit", () => { saindo = true; encerrarR(); });
  app.on("window-all-closed", () => { saindo = true; encerrarR(); app.quit(); });
}

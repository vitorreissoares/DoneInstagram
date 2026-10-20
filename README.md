# DoneInstagram

Programa para monitorar as postagens de candidatos no Instagram. Ele reúne as três etapas da pesquisa:

| Etapa | O que faz |
|---|---|
| **1 · Categorização** | Lê as planilhas coletadas, seleciona as postagens mais curtidas de cada candidato e as classifica com IA (legenda, imagens e vídeos) |
| **2 · Validação** | Confere a classificação da IA, sozinho ou com outros pesquisadores, e mostra a acurácia da IA |
| **3 · Relatório** | Gera o relatório com os botões Semana, Mês, Ano e Tudo |

## Baixar e instalar

Baixe o instalador do seu sistema na página de **[versões (Releases)](../../releases/latest)**:

| Sistema | Arquivo |
|---|---|
| **Windows** 10 ou 11 | `DoneInstagram-…-win-x64.exe` |
| **Mac com chip Apple** (M1, M2, M3, M4…) | `DoneInstagram-…-mac-arm64.dmg` |
| **Mac com Intel** | `DoneInstagram-…-mac-x64.dmg` |
| **Linux** | `DoneInstagram-…-linux-x86_64.AppImage` (qualquer distribuição) ou `….deb` (Ubuntu, Debian) |

O instalador já traz tudo o que o programa precisa, inclusive o R. Não é preciso instalar mais nada.

> **Por que aparece um aviso de segurança?** O programa não tem assinatura digital paga da Microsoft ou da Apple. Por isso, o sistema pede uma confirmação na primeira vez. É só seguir os passos abaixo.

### Windows

1. Dê dois cliques no arquivo `.exe`.
2. Se aparecer **"O Windows protegeu o computador"**, clique em **Mais informações → Executar assim mesmo**.
3. Siga o instalador. No fim, o atalho **DoneInstagram** fica na área de trabalho e no Menu Iniciar.

### Mac

1. Abra o arquivo `.dmg` e arraste o **DoneInstagram** para a pasta **Aplicativos**.
2. Na primeira vez, abra a pasta Aplicativos, clique no DoneInstagram com o **botão direito → Abrir** e confirme em **Abrir**.
3. Se o Mac não deixar abrir:
   - vá em **Ajustes do Sistema → Privacidade e Segurança**;
   - desça até a mensagem sobre o DoneInstagram e clique em **Abrir Mesmo Assim**.
4. Se aparecer **"está danificado"**, abra o **Terminal**, cole o comando abaixo e tente de novo:
   ```
   xattr -dr com.apple.quarantine /Applications/DoneInstagram.app
   ```

### Linux

- **AppImage:** clique com o botão direito no arquivo → **Propriedades → Permissões → Permitir executar como programa**. Depois, dê dois cliques. No Ubuntu 22.04 ou mais novo, talvez seja preciso instalar antes o pacote `libfuse2`:
  ```
  sudo apt install libfuse2
  ```
- **.deb:** dê dois cliques ou use `sudo apt install ./DoneInstagram-…-linux-amd64.deb`.

## Primeiro uso

1. Abra o **DoneInstagram**. A primeira abertura pode levar até um minuto.
2. Na aba **1 · Categorização**, informe a **sua chave do OpenRouter** no painel **Chave da IA** (crie uma em [openrouter.ai/keys](https://openrouter.ai/keys)).
3. Cada pessoa usa a **própria chave**. Ela fica guardada só no computador de quem a informou, e o botão **Apagar chave** a remove quando quiser.

O guia completo de uso está no [LEIA-ME](LEIA-ME.md). No programa, ele também está em **Ajuda → Guia de uso**.

## Onde ficam os dados

Rodadas, validações, imagens e vídeos baixados, relatórios e a chave ficam na pasta **Documentos/DoneInstagram** de cada usuário. Para abri-la, use o menu **Arquivo → Abrir pasta de dados**.

Instalar uma versão nova ou desinstalar o programa **não apaga** essa pasta.

## Para quem mantém o projeto

### Publicar uma versão nova

1. Mude o número em `desktop/package.json` (por exemplo, `"version": "1.1.0"`).
2. Crie a tag correspondente e envie:
   ```
   git tag v1.1.0
   git push origin v1.1.0
   ```
3. O GitHub monta os instaladores das três plataformas, em cerca de 20 a 30 minutos (aba **Actions**), e os publica em **Releases**.

Para testar sem publicar, use **Actions → Programa de computador → Run workflow**. Os instaladores ficam em **Artifacts**, na página da execução.

### Rodar pelo R, sem instalar

Com o R instalado, abra `app.R` no RStudio e clique em **Run App**. No Windows, também dá para usar `Abrir DoneInstagram.bat`. Veja a seção "Preparação" do [LEIA-ME](LEIA-ME.md).

### Como o programa é montado

| Parte | Onde |
|---|---|
| App (R/Shiny) | `app.R`, `R/`, `prompts/`, `templates/`, `apps_script/` |
| Textos e configurações iniciais | `config/`, `padrao/`, `assets/img_cand/` (fotos dos candidatos e logo) |
| Janela do programa (Electron) | `desktop/main.js`, `desktop/carregando.html` |
| Pacotes do R que vão no instalador | `desktop/build/pacotes_r.txt` |
| Montagem automática no GitHub | `.github/workflows/programa.yml` |

Fotos colocadas em `assets/img_cand/` no repositório vão junto no instalador e aparecem para todos.

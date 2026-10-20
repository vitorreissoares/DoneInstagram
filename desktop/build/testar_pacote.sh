#!/usr/bin/env bash
# Testa o programa empacotado: inicia o R que vai dentro dele (do mesmo jeito que
# o programa faz) e confere se o app responde e cria a pasta de dados.
# Uso: testar_pacote.sh <pasta "resources" do programa empacotado>
set -uo pipefail
REC="$(cd "$1" && pwd)"
DADOS="$(mktemp -d)/dados teste"
PORTA=8799
REGISTRO="$(mktemp)"
export DONEINSTAGRAM_APP="$REC/app" DONEINSTAGRAM_DADOS="$DADOS" DONEINSTAGRAM_PORTA=$PORTA
export R_LIBS_USER="" R_PROFILE_USER="" R_ENVIRON_USER=""

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    R="$REC/r"
    export PATH="$R:$R/Library/mingw-w64/bin:$R/Library/usr/bin:$R/Library/bin:$R/Scripts:$R/bin:$PATH"
    export CURL_CA_BUNDLE="$R/Library/ssl/cacert.pem"
    RS="$R/Lib/R/bin/x64/Rscript.exe"; [ -f "$RS" ] || RS="$R/Lib/R/bin/Rscript.exe"
    export DONEINSTAGRAM_APP="$(cygpath -w "$REC/app")" DONEINSTAGRAM_DADOS="$(cygpath -w "$DADOS")"
    CMD=("$RS" --no-save --no-restore "$(cygpath -w "$REC/iniciar.R")") ;;
  *)
    RH="$REC/r/lib/R"
    export R_HOME="$RH" R_SHARE_DIR="$RH/share" R_INCLUDE_DIR="$RH/include" R_DOC_DIR="$RH/doc"
    export CURL_CA_BUNDLE="$REC/r/ssl/cacert.pem"
    if [ "$(uname -s)" = "Darwin" ]; then export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; else export LANG=C.UTF-8 LC_ALL=C.UTF-8; fi
    CMD=("$RH/bin/exec/R" --no-save --no-restore --no-echo -f "$REC/iniciar.R") ;;
esac

"${CMD[@]}" > "$REGISTRO" 2>&1 &
PID=$!
OK=0
for i in $(seq 1 240); do
  if curl -s "http://127.0.0.1:$PORTA" | grep -q "DoneInstagram"; then OK=1; break; fi
  kill -0 $PID 2>/dev/null || break
  sleep 1
done
grep -v "^ \|masked\|Attaching" "$REGISTRO" | tail -25
kill $PID 2>/dev/null || true
taskkill //PID $PID //T //F >/dev/null 2>&1 || true

if [ $OK = 1 ] && [ -f "$DADOS/config/sobre_a_pesquisa.json" ]; then
  echo "OK: o programa abriu e criou a pasta de dados."
else
  echo "FALHOU: o programa não respondeu."
  exit 1
fi

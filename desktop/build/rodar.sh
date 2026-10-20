#!/usr/bin/env bash
# Roda um passo da montagem guardando a saída. Se o passo falhar, as últimas
# linhas aparecem como erro no resumo da execução (aba Actions), sem precisar
# abrir o registro completo. Uso: rodar.sh "Título" comando [argumentos...]
titulo="$1"; shift
saida="$(mktemp)"
"$@" 2>&1 | tee "$saida"
codigo=${PIPESTATUS[0]}
if [ "$codigo" -ne 0 ]; then
  trecho="$(grep -v '^\s*$' "$saida" | tail -n 60)"
  trecho="${trecho//'%'/'%25'}"
  trecho="${trecho//$'\r'/'%0D'}"
  trecho="${trecho//$'\n'/'%0A'}"
  echo "::error title=${titulo} (código ${codigo})::${trecho}"
fi
exit "$codigo"

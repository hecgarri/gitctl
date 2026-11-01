# Escribir un adaptador de agente

Un adaptador es un fichero Bash en `lib/adapters/<nombre>.sh` o, sin tocar gitctl,
en `~/.config/gitctl/adapters/<nombre>.sh`. Se descubre automáticamente.

## Contrato

```bash
adapter_<nombre>_available() { command -v mi-agente >/dev/null 2>&1; }
adapter_<nombre>_version()   { mi-agente --version; }   # opcional

# MODO: implement (puede escribir en DIR) | review (solo lectura)
adapter_<nombre>_run() {
	local mode="$1" agent="$2" dir="$3" prompt="$4" log="$5" result="$6"
	local -a extra
	agent_extra_args extra "$agent" "$mode"   # agent.<agente>.<modo>.args, etc.
	case "$mode" in
	implement) mi-agente --auto-edit "${extra[@]}" <"$prompt" >"$result" 2>>"$log" ;;
	review)    mi-agente --read-only "${extra[@]}" <"$prompt" >"$result" 2>>"$log" ;;
	esac
}
```

- Se ejecuta con el directorio actual en `DIR` y `stdin` en `/dev/null`.
- Debe dejar el **mensaje final** del agente en `RESULT` (en revisión, ahí se busca
  el bloque JSON del veredicto) y toda la salida diagnóstica en `LOG`.
- El código de salida es el del agente. gitctl aplica el límite de tiempo
  (`timeout`); no hace falta implementarlo.
- En modo `review` usa siempre el modo más restrictivo que ofrezca la CLI. Aun así,
  si el revisor modifica ficheros, gitctl invalida la revisión.
- No hagas commits ni push desde el adaptador: el commit de huella lo hace gitctl.

## Variables disponibles

`GITCTL_TASK`, `GITCTL_AGENT` y, en ejecuciones de implementación, `GITCTL_RUN_ID`.

## Probar

El adaptador `fake` (`lib/adapters/fake.sh`) es la referencia mínima y lo usan los
tests. Para probar uno nuevo:

```bash
gitctl agents
gitctl task new "prueba" && gitctl task assign t1 <nombre> && gitctl run t1 --wait
gitctl run show t1/<nombre>
```

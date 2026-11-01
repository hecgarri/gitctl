# shellcheck shell=bash
# gitctl init y gitctl doctor

_conf_example() {
	cat <<'EOF2'
# Configuración de gitctl para este repositorio («clave = valor»; nunca se ejecuta
# como código). Se lee siempre del worktree principal.

# Rama en la que se crean e integran los worktrees (por defecto: origin/HEAD o
# la rama actual del principal).
# base = main

# Archivos ignorados por git que se copian del principal a cada worktree nuevo.
# copy = .env .env.local

# Comando que se ejecuta en cada worktree nuevo, sin preguntar.
# setup = npm ci
EOF2
}

cmd_init() {
	if want_help "$@"; then
		echo "Uso: gitctl init   — crea un .gitctl.conf de ejemplo en el worktree principal"
		return
	fi
	require_repo
	local conf
	conf="$(git_main_root)/.gitctl.conf"
	if [[ -f "$conf" ]]; then
		info "ya existe $conf (no se modifica)"
	else
		_conf_example >"$conf"
		ok "creado $conf"
	fi
	info "worktrees en $(wt_root)"
	[[ -n "${GITCTL_SHELL:-}" ]] ||
		info "para que gitctl cambie de carpeta, añade a tu ~/.bashrc: eval \"\$(gitctl shell-init bash)\""
}

cmd_doctor() {
	if want_help "$@"; then
		echo "Uso: gitctl doctor   — comprueba git, el repositorio, la configuración y el shell"
		return
	fi
	local bad=0
	echo "Herramientas:"
	if command -v git >/dev/null 2>&1; then
		if git_version_ok; then
			mark ok "$(git --version)"
		else
			mark fail "$(git --version) — se necesita git >= 2.38"
			bad=1
		fi
	else
		mark fail "git — OBLIGATORIO"
		return 1
	fi
	echo "Shell:"
	if [[ -n "${GITCTL_SHELL:-}" ]]; then
		mark ok "integración activa (cd automático)"
	else
		mark warn "sin integración: añade eval \"\$(gitctl shell-init bash)\" a tu ~/.bashrc"
	fi
	echo "Repositorio:"
	if in_git_repo; then
		mark ok "$(git_main_root)"
		mark ok "worktrees en $(wt_root)"
		local b
		b="$(git_default_branch)"
		if git_branch_exists "$b"; then mark ok "rama por defecto: $b"; else mark warn "rama por defecto «$b» no existe en local"; fi
		local k
		for k in copy setup; do
			if [[ -n "$(cfg "$k")" ]]; then mark ok "$k = $(cfg "$k")"; else mark skip "$k sin definir"; fi
		done
	else
		mark skip "no estás en un repositorio Git"
	fi
	return "$bad"
}

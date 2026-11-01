#!/usr/bin/env bats
load test_helper

# gh falso: registra las llamadas y simula el estado de una única PR.
#   $GH_STATE  archivo con «OPEN» o «MERGED» (no existe = no hay PR)
setup() {
	setup_repo
	export GIT_PAGER=cat GITCTL_PICKER=basic
	export GH_LOG="$TEST_TMP/gh.log" GH_STATE="$TEST_TMP/gh.state"
	export PR_URL="https://github.com/u/repo/pull/7"
	mkdir -p "$TEST_TMP/bin"
	cat >"$TEST_TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
"pr view")
	[[ -f "$GH_STATE" ]] || exit 1
	echo "$(cat "$GH_STATE") $PR_URL"
	;;
"pr create")
	echo OPEN >"$GH_STATE"
	echo "Creating pull request..."
	echo "$PR_URL"
	;;
*) exit 1 ;;
esac
GH
	chmod +x "$TEST_TMP/bin/gh"
	export PATH="$TEST_TMP/bin:$PATH"
	git init -q --bare "$TEST_TMP/remote.git"
	git remote add origin "$TEST_TMP/remote.git"
	git push -q origin main
	gitctl new feat/a >/dev/null 2>&1
	commit_in "$(wt_path feat-a)" f.txt contenido
}

@test "pr sube la rama, crea la PR con el commit como título y guarda la URL" {
	run gitctl -y pr feat-a
	assert_success
	assert_output_contains "PR creada: $PR_URL"
	git ls-remote --exit-code --heads origin feat/a >/dev/null
	grep -q -- "pr create --base main --head feat/a --title cambio f.txt" "$GH_LOG"
	grep -q -- "- cambio f.txt" "$GH_LOG"
	[[ "$(git config branch.feat/a.gitctl-pr)" == "$PR_URL" ]]
}

@test "pr con varios commits propone el nombre de la rama y acepta --title" {
	commit_in "$(wt_path feat-a)" g.txt otro
	run gitctl -y pr feat-a
	assert_success
	grep -q -- "--title feat/a " "$GH_LOG"
	rm -f "$GH_STATE" "$GH_LOG"
	git push -q origin --delete feat/a
	run gitctl -y pr feat-a --title "Mi título"
	assert_success
	grep -q -- "--title Mi título " "$GH_LOG"
}

@test "pr pregunta el título y si dices que no, no sube nada" {
	run bash -c 'printf "Otro título\nn\n" | GITCTL_ASSUME_TTY=1 gitctl pr feat-a'
	assert_failure
	assert_output_contains "Título: Otro título"
	assert_output_contains "no se ha subido nada"
	refute git ls-remote --exit-code --heads origin feat/a
}

@test "pr con una PR abierta solo sube los commits nuevos" {
	gitctl -y pr feat-a >/dev/null 2>&1
	commit_in "$(wt_path feat-a)" g.txt otro
	run gitctl -y pr feat-a
	assert_success
	assert_output_contains "PR actualizada"
	[[ "$(grep -c "pr create" "$GH_LOG")" == 1 ]]
	[[ "$(git ls-remote --heads origin feat/a | cut -f1)" == "$(git rev-parse feat/a)" ]]
}

@test "pr se niega con cambios sin commitear o sin commits nuevos" {
	echo x >"$(wt_path feat-a)/sucio"
	run gitctl -y pr feat-a
	assert_failure
	assert_output_contains "haz commit primero"
	gitctl new vacia >/dev/null 2>&1
	run gitctl -y pr vacia
	assert_failure
	assert_output_contains "no hay nada que proponer"
}

@test "pr sin remoto o con la base sin subir lo explica" {
	git push -q origin --delete main
	run gitctl -y pr feat-a
	assert_failure
	assert_output_contains "git push origin main"
	git remote remove origin
	run gitctl -y pr feat-a
	assert_failure
	assert_output_contains "no tiene el remoto «origin»"
}

@test "clean borra el worktree cuando su PR está integrada en GitHub" {
	gitctl -y pr feat-a >/dev/null 2>&1
	run gitctl -y clean
	assert_success
	assert_output_contains "nada que limpiar"
	echo MERGED >"$GH_STATE"
	run gitctl -y clean
	assert_success
	assert_output_contains "PR integrada en GitHub"
	assert_output_contains "git pull"
	[[ ! -d "$(wt_path feat-a)" ]]
	refute git show-ref --verify -q refs/heads/feat/a
}

@test "menú: Integrar ofrece pull request o merge local" {
	run bash -c 'printf "4\n1\n1\n\ns\n\n0\n" | GITCTL_ASSUME_TTY=1 GITCTL_SHELL=1 GITCTL_CD_FILE="$1" gitctl' _ "$CD_FILE"
	assert_success
	assert_output_contains "Pull request en GitHub"
	assert_output_contains "PR creada: $PR_URL"
	[[ -d "$(wt_path feat-a)" ]]
	[[ ! -f "$REPO/f.txt" ]]
}

@test "menú: Integrar con merge local sigue funcionando con remoto" {
	run bash -c 'printf "4\n1\n2\ns\n\n0\n" | GITCTL_ASSUME_TTY=1 GITCTL_SHELL=1 GITCTL_CD_FILE="$1" gitctl' _ "$CD_FILE"
	assert_success
	[[ -f "$REPO/f.txt" ]]
	[[ ! -d "$(wt_path feat-a)" ]]
	refute grep -q "pr create" "$GH_LOG"
}

#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	gitctl new x >/dev/null 2>&1
	WT="$(wt_path x)"
}

conflict() {
	commit_in "$WT" README.md "desde la rama"
	commit_in "$REPO" README.md "desde main"
}

@test "merge limpio: commit de merge, limpieza y vuelta al principal" {
	commit_in "$WT" f.txt f
	cd "$WT"
	run env GITCTL_CD_FILE="$CD_FILE" gitctl -y merge
	assert_success
	[[ -n "$(git -C "$REPO" log -1 --merges --format=%H main)" ]]
	[[ -f "$REPO/f.txt" ]]
	[[ ! -d "$WT" ]]
	refute git -C "$REPO" show-ref -q refs/heads/x
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]
}

@test "merge por nombre desde el principal" {
	commit_in "$WT" f.txt f
	run gitctl -y merge x
	assert_success
	[[ -f "$REPO/f.txt" ]]
}

@test "merge sin -y ni TTY integra pero conserva el worktree" {
	commit_in "$WT" f.txt f
	run gitctl merge x </dev/null
	assert_success
	[[ -f "$REPO/f.txt" ]]
	[[ -d "$WT" ]]
	assert_output_contains "se conserva"
}

@test "merge falla si el worktree tiene cambios" {
	commit_in "$WT" f.txt f
	echo s >"$WT/sucio"
	run gitctl -y merge x
	assert_failure
	assert_output_contains "sin commitear"
	[[ ! -f "$REPO/f.txt" ]]
}

@test "merge falla si el principal tiene cambios" {
	commit_in "$WT" f.txt f
	echo cambio >>"$REPO/README.md"
	run gitctl -y merge x
	assert_failure
	assert_output_contains "principal"
}

@test "merge falla si el principal no está en la base" {
	commit_in "$WT" f.txt f
	git -C "$REPO" switch -q -c otra
	run gitctl -y merge x
	assert_failure
	assert_output_contains "no en main"
}

@test "merge desde el principal sin nombre falla" {
	run gitctl -y merge
	assert_failure
	assert_output_contains "principal"
}

@test "merge usa la base guardada" {
	git branch dev
	gitctl new y --base dev >/dev/null 2>&1
	commit_in "$(wt_path y)" g.txt g
	git switch -q dev
	run gitctl -y merge y
	assert_success
	git cat-file -e dev:g.txt
	refute git cat-file -e main:g.txt
}

@test "merge de un worktree creado a mano integra en la rama por defecto" {
	git worktree add -q -b manual "$TEST_TMP/manual"
	commit_in "$TEST_TMP/manual" m.txt m
	run gitctl -y merge manual
	assert_success
	git cat-file -e main:m.txt
}

@test "merge sin nada nuevo solo ofrece limpiar" {
	run gitctl -y merge x
	assert_success
	assert_output_contains "nada nuevo"
	[[ ! -d "$WT" ]]
}

@test "conflicto con --on-conflict=abort deja main intacto" {
	conflict
	before="$(git rev-parse main)"
	run gitctl -y merge x --on-conflict=abort
	assert_failure
	assert_output_contains "README.md"
	[[ "$(git rev-parse main)" == "$before" ]]
	refute git rev-parse -q --verify MERGE_HEAD

	[[ -z "$(git status --porcelain)" ]]
	[[ -d "$WT" ]]
}

@test "conflicto sin TTY y sin flag aborta" {
	conflict
	run gitctl -y merge x </dev/null
	assert_failure
	assert_output_contains "se aborta"
	refute git rev-parse -q --verify MERGE_HEAD
}

@test "conflicto con keep y después merge --continue" {
	conflict
	run env GITCTL_CD_FILE="$CD_FILE" gitctl -y merge x --on-conflict=keep
	assert_failure
	git rev-parse -q --verify MERGE_HEAD
	[[ "$(git config gitctl.merging)" == "x" ]]
	[[ "$(cat "$CD_FILE")" == "$REPO" ]]

	run gitctl -y merge x
	assert_failure
	assert_output_contains "--continue"

	run gitctl -y merge --continue
	assert_failure
	assert_output_contains "sin resolver"

	echo resuelto >README.md
	git add README.md
	run gitctl -y merge --continue
	assert_success
	[[ -n "$(git log -1 --merges --format=%H)" ]]
	refute git config --get gitctl.merging
	[[ ! -d "$WT" ]]
}

@test "merge --continue sin merge en curso falla" {
	run gitctl merge --continue
	assert_failure
	assert_output_contains "no hay ningún merge"
}

@test "merge --continue tras abortar a mano limpia el estado" {
	conflict
	gitctl -y merge x --on-conflict=keep >/dev/null 2>&1 || true
	git merge --abort
	run gitctl merge --continue
	assert_failure
	assert_output_contains "no se ha integrado"
	refute git config --get gitctl.merging
}

# --push: remoto bare con main ya subido.
with_remote() {
	git init -q --bare "$TEST_TMP/remote.git"
	git remote add origin "$TEST_TMP/remote.git"
	git push -q origin main
}

@test "merge --push integra y sube la base al remoto" {
	with_remote
	commit_in "$WT" f.txt f
	run gitctl -y merge x --push
	assert_success
	assert_output_contains "main subida a origin"
	[[ "$(git ls-remote --heads origin main | cut -f1)" == "$(git rev-parse main)" ]]
	git -C "$TEST_TMP/remote.git" cat-file -e main:f.txt
}

@test "merge sin --push avisa de que la base quedó por delante del remoto" {
	with_remote
	commit_in "$WT" f.txt f
	run gitctl -y merge x
	assert_success
	assert_output_contains "por delante de origin/main"
	assert_output_contains "gitctl merge --push"
	[[ "$(git ls-remote --heads origin main | cut -f1)" != "$(git rev-parse main)" ]]
}

@test "merge sin --push ni remoto no menciona el push" {
	commit_in "$WT" f.txt f
	run gitctl -y merge x
	assert_success
	[[ "$output" != *"push"* ]]
}

@test "merge --push sin -y ni TTY integra pero no sube" {
	with_remote
	commit_in "$WT" f.txt f
	run gitctl merge x --push </dev/null
	assert_failure
	assert_output_contains "no se ha subido main"
	[[ -f "$REPO/f.txt" ]]
	[[ "$(git ls-remote --heads origin main | cut -f1)" != "$(git rev-parse main)" ]]
}

@test "merge --push pregunta y respeta el no" {
	with_remote
	commit_in "$WT" f.txt f
	run bash -c 'printf "n\nn\n" | GITCTL_ASSUME_TTY=1 gitctl merge x --push'
	assert_failure
	assert_output_contains "Se subirá main a origin"
	assert_output_contains "cambio f.txt"
	[[ "$(git ls-remote --heads origin main | cut -f1)" != "$(git rev-parse main)" ]]
}

@test "merge --push sin remoto integra y falla al subir" {
	commit_in "$WT" f.txt f
	run gitctl -y merge x --push
	assert_failure
	assert_output_contains "no tiene el remoto"
	[[ -f "$REPO/f.txt" ]]
	[[ ! -d "$WT" ]]
}

@test "merge --push con la rama ya integrada solo sube lo pendiente" {
	with_remote
	commit_in "$WT" f.txt f
	gitctl -y merge x >/dev/null 2>&1
	gitctl new x >/dev/null 2>&1
	run gitctl -y merge x --push
	assert_success
	assert_output_contains "nada nuevo"
	assert_output_contains "main subida a origin"
	[[ "$(git ls-remote --heads origin main | cut -f1)" == "$(git rev-parse main)" ]]
}

@test "merge --push con la base al día no sube nada" {
	with_remote
	run gitctl -y merge x --push
	assert_success
	assert_output_contains "al día"
}

@test "merge --continue --push sube tras resolver el conflicto" {
	with_remote
	conflict
	gitctl -y merge x --on-conflict=keep --push >/dev/null 2>&1 || true
	echo resuelto >README.md
	git add README.md
	run gitctl -y merge --continue --push
	assert_success
	assert_output_contains "main subida a origin"
	[[ "$(git ls-remote --heads origin main | cut -f1)" == "$(git rev-parse main)" ]]
}

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

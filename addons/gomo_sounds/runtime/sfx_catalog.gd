@tool
extends Resource

## What Gomo Sounds installed in the project, in the plugin's memory. On disk it becomes a plain Resource
## with the data in a metadata entry (InstallCatalog.save): the exported game doesn't depend on this script. It
## stays here (and at this path) because catalogs saved on 2026-09-26 point to it.
##
## `sounds` is what the game reads to play: one entry per key, with the files of each variation.
## `files` is the plugin's record: EVERY file it wrote, with the hash of what it wrote. This is what
## stops the plugin from overwriting or deleting a file that isn't its own, or that someone edited.

const FORMAT := "gomo-sounds/catalog@1"

@export var format := FORMAT
@export var game_id := ""
## {key, event, entity, externalId, section, files: [path], uids: ["uid://…"], loops: [bool]}
## (`section` = the tab on the site: ambience, effects, interface, music; older catalogs have none.)
@export var sounds: Array[Dictionary] = []
## {slot: "<key>#<n>", path, uid, sha256, version, loop, pinned, bpm}. `pinned` = the user moved the file
## in Godot: the plugin never moves it from there again. `bpm` = the tempo of a music file as the site
## generated it (float), null when unknown or not music; catalogs from before 0.7.0 have none (= unknown).
@export var files: Array[Dictionary] = []

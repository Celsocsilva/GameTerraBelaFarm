extends SceneTree
## ENV-002 — Gera data/river/river_tile_meta.json a partir dos PNGs de rio.
##
## Uso (na raiz do projeto):
##   godot --headless --path . -s tools/river_tile_bake.gd
##
## Para cada tile em res://assets/river_tiles/ mede, sem alterar o PNG:
## - as aberturas de água (borda, linha da água junto à borda e trecho ocupado);
## - uma máscara de água em células de CELL px, usada pelas colisões do rio.
## A água é reconhecida pela mesma regra do shader (azul - vermelho > limiar).

const TILE_DIR := "res://assets/river_tiles/"
const OUTPUT := "res://data/river/river_tile_meta.json"
const CELL := 8
const WATER_THRESHOLD := 0.12
## Uma abertura precisa encostar (até este número de px) na borda da imagem.
const OPENING_BORDER_PX := 20
const MIN_OPENING_PX := 30

func _initialize() -> void:
    var result := {"cell_px": CELL, "water_threshold": WATER_THRESHOLD, "tiles": {}}
    var files := DirAccess.get_files_at(TILE_DIR)
    files.sort()
    for file in files:
        if file.get_extension() != "png":
            continue
        var path := TILE_DIR + file
        var image := Image.load_from_file(ProjectSettings.globalize_path(path))
        if image == null or image.is_empty():
            push_error("Could not read " + path)
            quit(1)
            return
        image.convert(Image.FORMAT_RGBA8)
        var meta := _measure(image)
        result["tiles"][file.get_basename()] = meta
        print("RIVER_BAKE ", file.get_basename(), " size=", meta["size"], " openings=", (meta["openings"] as Dictionary).keys(), " water_cells=", meta["water_cells"])
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
    var out := FileAccess.open(OUTPUT, FileAccess.WRITE)
    out.store_string(JSON.stringify(result, "  ", true))
    out.close()
    print("RIVER_BAKE_OK tiles=", (result["tiles"] as Dictionary).size(), " -> ", OUTPUT)
    quit(0)

func _is_water(image: Image, x: int, y: int) -> bool:
    var c := image.get_pixel(x, y)
    return c.a > 0.5 and c.b - c.r > WATER_THRESHOLD

func _measure(image: Image) -> Dictionary:
    var w := image.get_width()
    var h := image.get_height()
    var water := PackedByteArray()
    water.resize(w * h)
    var min_x := w
    var max_x := -1
    var min_y := h
    var max_y := -1
    for y in h:
        for x in w:
            if _is_water(image, x, y):
                water[y * w + x] = 1
                min_x = mini(min_x, x)
                max_x = maxi(max_x, x)
                min_y = mini(min_y, y)
                max_y = maxi(max_y, y)
    var openings := {}
    if min_y <= OPENING_BORDER_PX:
        _add_opening(openings, "top", min_y, _longest_run_row(water, w, min_y + 2))
    if h - 1 - max_y <= OPENING_BORDER_PX:
        _add_opening(openings, "bottom", max_y, _longest_run_row(water, w, max_y - 2))
    if min_x <= OPENING_BORDER_PX:
        _add_opening(openings, "left", min_x, _longest_run_col(water, w, h, min_x + 2))
    if w - 1 - max_x <= OPENING_BORDER_PX:
        _add_opening(openings, "right", max_x, _longest_run_col(water, w, h, max_x - 2))
    # Máscara em células: 1 quando ao menos metade da célula é água.
    var cols := int(ceil(float(w) / CELL))
    var rows := int(ceil(float(h) / CELL))
    var mask_rows: Array[String] = []
    var water_cells := 0
    for row in rows:
        var line := ""
        for col in cols:
            var count := 0
            var total := 0
            for y in range(row * CELL, mini((row + 1) * CELL, h)):
                for x in range(col * CELL, mini((col + 1) * CELL, w)):
                    total += 1
                    count += water[y * w + x]
            var is_water := total > 0 and count * 2 >= total
            line += "1" if is_water else "0"
            water_cells += 1 if is_water else 0
        mask_rows.append(line)
    return {
        "size": [w, h],
        "water_bbox": [min_x, min_y, max_x, max_y],
        "openings": openings,
        "mask_cols": cols,
        "mask_rows": rows,
        "mask": mask_rows,
        "water_cells": water_cells
    }

func _add_opening(openings: Dictionary, edge: String, line: int, run: Vector2i) -> void:
    if run.y - run.x + 1 < MIN_OPENING_PX:
        return
    openings[edge] = {"line": line, "from": run.x, "to": run.y}

func _longest_run_row(water: PackedByteArray, w: int, y: int) -> Vector2i:
    var best := Vector2i(0, -1)
    var start := -1
    for x in w + 1:
        var on := x < w and water[y * w + x] == 1
        if on and start < 0:
            start = x
        elif not on and start >= 0:
            if x - 1 - start > best.y - best.x:
                best = Vector2i(start, x - 1)
            start = -1
    return best

func _longest_run_col(water: PackedByteArray, w: int, h: int, x: int) -> Vector2i:
    var best := Vector2i(0, -1)
    var start := -1
    for y in h + 1:
        var on := y < h and water[y * w + x] == 1
        if on and start < 0:
            start = y
        elif not on and start >= 0:
            if y - 1 - start > best.y - best.x:
                best = Vector2i(start, y - 1)
            start = -1
    return best

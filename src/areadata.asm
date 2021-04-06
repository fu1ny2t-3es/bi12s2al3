;;;=========================================================================;;;
;;; Copyright 2020 Matthew D. Steele <mdsteele@alum.mit.edu>                ;;;
;;;                                                                         ;;;
;;; This file is part of Big2Small.                                         ;;;
;;;                                                                         ;;;
;;; Big2Small is free software: you can redistribute it and/or modify it    ;;;
;;; under the terms of the GNU General Public License as published by the   ;;;
;;; Free Software Foundation, either version 3 of the License, or (at your  ;;;
;;; option) any later version.                                              ;;;
;;;                                                                         ;;;
;;; Big2Small is distributed in the hope that it will be useful, but        ;;;
;;; WITHOUT ANY WARRANTY; without even the implied warranty of              ;;;
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       ;;;
;;; General Public License for more details.                                ;;;
;;;                                                                         ;;;
;;; You should have received a copy of the GNU General Public License along ;;;
;;; with Big2Small.  If not, see <http://www.gnu.org/licenses/>.            ;;;
;;;=========================================================================;;;

INCLUDE "src/areamap.inc"
INCLUDE "src/charmap.inc"
INCLUDE "src/color.inc"
INCLUDE "src/hardware.inc"
INCLUDE "src/macros.inc"
INCLUDE "src/save.inc"
INCLUDE "src/tileset.inc"

;;;=========================================================================;;;

;;; The number of puzzles in each area:
NUM_FOREST_PUZZLES EQU 8
NUM_FARM_PUZZLES EQU 7
NUM_MOUNTAIN_PUZZLES EQU 7
NUM_SEASIDE_PUZZLES EQU 2
NUM_SEWER_PUZZLES EQU 2
NUM_CITY_PUZZLES EQU 2
NUM_SPACE_PUZZLES EQU 3

;;; The puzzle number of the first puzzle in each area:
FIRST_FOREST_PUZZLE EQU 0
FIRST_FARM_PUZZLE EQU (FIRST_FOREST_PUZZLE + NUM_FOREST_PUZZLES)
FIRST_MOUNTAIN_PUZZLE EQU (FIRST_FARM_PUZZLE + NUM_FARM_PUZZLES)
FIRST_SEASIDE_PUZZLE EQU (FIRST_MOUNTAIN_PUZZLE + NUM_MOUNTAIN_PUZZLES)
FIRST_SEWER_PUZZLE EQU (FIRST_SEASIDE_PUZZLE + NUM_SEASIDE_PUZZLES)
FIRST_CITY_PUZZLE EQU (FIRST_SEWER_PUZZLE + NUM_SEWER_PUZZLES)
FIRST_SPACE_PUZZLE EQU (FIRST_CITY_PUZZLE + NUM_CITY_PUZZLES)
ASSERT FIRST_SPACE_PUZZLE + NUM_SPACE_PUZZLES == NUM_PUZZLES

;;;=========================================================================;;;

;;; Declares a 3-byte banked pointer to the given label.
;;;
;;; Example:
;;;     D_BPTR DataX_Foo
D_BPTR: MACRO
    DB BANK(\1), LOW(\1), HIGH(\1)
ENDM

;;; Declares a title string for an AREA or NODE struct.  The first argument
;;; gives the size of the field in bytes, and the second argument gives the
;;; title string (which will be centered with spaces within the field).
;;;
;;; Example:
;;;     D_TITLE 16, "Foo Bar"
D_TITLE: MACRO
    ASSERT _NARG == 2
    ASSERT STRLEN(\2) <= (\1)
    DS ((\1) - STRLEN(\2)) / 2, " "
    DB \2
    DS (1 + (\1) - STRLEN(\2)) / 2, " "
ENDM

;;;=========================================================================;;;

;;; Constants for D_TRAIL arguments:
TN1 EQU (TRAIL_NORTH | 1)
TS1 EQU (TRAIL_SOUTH | 1)
TE1 EQU (TRAIL_EAST  | 1)
TW1 EQU (TRAIL_WEST  | 1)
TN2 EQU (TRAIL_NORTH | 2)
TS2 EQU (TRAIL_SOUTH | 2)
TE2 EQU (TRAIL_EAST  | 2)
TW2 EQU (TRAIL_WEST  | 2)
UN1 EQU (TRAIL_NORTH | 1 | TRAILF_UNDER)
US1 EQU (TRAIL_SOUTH | 1 | TRAILF_UNDER)
UE1 EQU (TRAIL_EAST  | 1 | TRAILF_UNDER)
UW1 EQU (TRAIL_WEST  | 1 | TRAILF_UNDER)
UN2 EQU (TRAIL_NORTH | 2 | TRAILF_UNDER)
US2 EQU (TRAIL_SOUTH | 2 | TRAILF_UNDER)
UE2 EQU (TRAIL_EAST  | 2 | TRAILF_UNDER)
UW2 EQU (TRAIL_WEST  | 2 | TRAILF_UNDER)
UN3 EQU (TRAIL_NORTH | 3 | TRAILF_UNDER)
US3 EQU (TRAIL_SOUTH | 3 | TRAILF_UNDER)
UE3 EQU (TRAIL_EAST  | 3 | TRAILF_UNDER)
UW3 EQU (TRAIL_WEST  | 3 | TRAILF_UNDER)

;;; Declares a Trail/ExitTrail field within a NODE/AREA struct.  There should
;;; be 1 to MAX_TRAIL_LENGTH arguments (inclusive), with each being one of the
;;; above T?? constants.  The last entry will automatically be marked with
;;; TRAILB_END, and the field will automatically be padded to MAX_TRAIL_LENGTH
;;; bytes.
;;;
;;; Example:
;;;     D_TRAIL TS1, TS1, TS1, TE1, TE2, TE1
D_TRAIL: MACRO
_TRAIL_LENGTH = _NARG
    ASSERT _TRAIL_LENGTH >= 1 && _TRAIL_LENGTH <= MAX_TRAIL_LENGTH
    REPT _TRAIL_LENGTH - 1
    DB \1
    SHIFT
    ENDR
    DB (\1) | (1 << TRAILB_END)
    DS MAX_TRAIL_LENGTH - _TRAIL_LENGTH
ENDM

;;;=========================================================================;;;

SECTION "AreaFunctions", ROM0

;;; An array that maps from AREA_* enum values to pointers to AREA structs
;;; stored in BANK("AreaData").
Data_AreaTable_area_ptr_arr:
    .begin
    ASSERT @ - .begin == 2 * AREA_FOREST
    DW DataX_Forest_area
    ASSERT @ - .begin == 2 * AREA_FARM
    DW DataX_Farm_area
    ASSERT @ - .begin == 2 * AREA_MOUNTAIN
    DW DataX_Mountain_area
    ASSERT @ - .begin == 2 * AREA_SEASIDE
    DW DataX_Seaside_area
    ASSERT @ - .begin == 2 * AREA_SEWER
    DW DataX_Sewer_area
    ASSERT @ - .begin == 2 * AREA_CITY
    DW DataX_City_area
    ASSERT @ - .begin == 2 * AREA_SPACE
    DW DataX_Space_area

;;; Returns a pointer to the specified AREA struct in BANK("AreaData").  Note
;;; that this function does *not* set the ROM bank.
;;; @param c The area number (one of the AREA_* enum values).
;;; @return hl A pointer to the specified AREA struct.
;;; @preserve de
Func_GetAreaData_hl::
    sla c
    ld b, 0
    ld hl, Data_AreaTable_area_ptr_arr
    add hl, bc
    deref hl
    ret

;;; Returns the area that a given puzzle is in.
;;; @param c The puzzle number.
;;; @return c The AREA_* enum value for the area that the puzzle is in.
Func_GetPuzzleArea_c::
    ld a, c
    if_ge FIRST_SEASIDE_PUZZLE, jr, .seasideOrGreater
    if_ge FIRST_FARM_PUZZLE, jr, .farmOrMountain
    ld c, AREA_FOREST
    ret
    .farmOrMountain
    if_ge FIRST_MOUNTAIN_PUZZLE, jr, .mountain
    ld c, AREA_FARM
    ret
    .mountain
    ld c, AREA_MOUNTAIN
    ret
    .seasideOrGreater
    if_ge FIRST_CITY_PUZZLE, jr, .cityOrGreater
    if_ge FIRST_SEWER_PUZZLE, jr, .sewer
    ld c, AREA_SEASIDE
    ret
    .sewer
    ld c, AREA_SEWER
    ret
    .cityOrGreater
    if_ge FIRST_SPACE_PUZZLE, jr, .space
    ld c, AREA_CITY
    ret
    .space
    ld c, AREA_SPACE
    ret

;;;=========================================================================;;;

SECTION "AreaData", ROMX

DataX_Forest_area:
    .begin
    D_BPTR DataX_TitleMusic_song
    DB COLORSET_SUMMER
    DB TILESET_MAP_FOREST
    D_BPTR DataX_ForestTileMap_start
    D_TITLE 20, "GIANT'S FOREST"
    D_TRAIL TN1, TN1, TN1
    DB FIRST_FOREST_PUZZLE
    DB NUM_FOREST_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Forest_Node0:
    .begin
    DB 9, 3  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_DOWN | 1           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Peanut Pathway"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node1:
    .begin
    DB 13, 7  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1, TN1, TN1, TN1, TN1
    DB PADF_LEFT | 0           ; prev
    DB PADF_RIGHT | 2          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Goat Grove"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node2:
    .begin
    DB 13, 13  ; row/col
    D_TRAIL TW1, UW3, TW1, TW1
    DB PADF_LEFT | 1           ; prev
    DB PADF_RIGHT | 3          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Forest2"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node3:
    .begin
    DB 11, 17  ; row/col
    D_TRAIL TW1, TW1, TS1, TS1, TW1, TW1
    DB PADF_LEFT | 2           ; prev
    DB PADF_UP | 4             ; next
    DB 0                       ; bonus
    D_TITLE 16, "Forest3"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node4:
    .begin
    DB 6, 15  ; row/col
    D_TRAIL TE1, TE1, TS1, TS1, TS1, TS1, TS1
    DB PADF_RIGHT | 3          ; prev
    DB PADF_LEFT | 5           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Forest4"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node5:
    .begin
    DB 8, 12  ; row/col
    D_TRAIL TN1, TN1, TE1, TE1, TE1
    DB PADF_UP | 4             ; prev
    DB PADF_LEFT | 7           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Forest5"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node6:
    .begin
    DB 4, 1  ; row/col
    D_TRAIL TE1, UE3, TE1, TE1, TE1, TE1
    DB PADF_RIGHT | 7          ; prev
    DB 0                       ; next
    DB 0                       ; bonus
    D_TITLE 16, "Forest Bonus"
    ASSERT @ - .begin == sizeof_NODE
_Forest_Node7:
    .begin
    DB 4, 9  ; row/col
    D_TRAIL TS1, TS1, TS1, TS1, TE1, TE1, TE1
    DB PADF_DOWN | 5           ; prev
    DB PADF_UP | EXIT_NODE     ; next
    DB PADF_LEFT | 6           ; bonus
    D_TITLE 16, "Forest7"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Forest_Node0 == NUM_FOREST_PUZZLES * sizeof_NODE

DataX_Farm_area:
    .begin
    D_BPTR DataX_RestYe_song
    DB COLORSET_AUTUMN
    DB TILESET_MAP_FOREST
    D_BPTR DataX_FarmTileMap_start
    D_TITLE 20, "HUGESON FARMS"
    D_TRAIL TE1, TE1, TE1, TE1
    DB FIRST_FARM_PUZZLE
    DB NUM_FARM_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Farm_Node0:
    .begin
    DB 12, 5  ; row/col
    D_TRAIL TS1, TS1, TS1, US1
    DB PADF_DOWN | EXIT_NODE   ; prev
    DB PADF_UP | 1             ; next
    DB 0                       ; bonus
    D_TITLE 16, "Farm0"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node1:
    .begin
    DB 7, 5  ; row/col
    D_TRAIL TS1, TS1, TS1, TS1, TS1
    DB PADF_DOWN | 0           ; prev
    DB PADF_RIGHT | 2          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Farm1"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node2:
    .begin
    DB 5, 10  ; row/col
    D_TRAIL TW1, TW1, TS1, TS1, TW1, TW1, TW1
    DB PADF_LEFT | 1           ; prev
    DB PADF_RIGHT | 3          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Farm2"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node3:
    .begin
    DB 4, 17  ; row/col
    D_TRAIL TW1, TW1, TW1, TS1, TW1, TW1, TW1, TW1
    DB PADF_LEFT | 2           ; prev
    DB PADF_DOWN | 4           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Farm3"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node4:
    .begin
    DB 8, 15  ; row/col
    D_TRAIL TE1, TE1, TN1, TN1, TN1, TN1
    DB PADF_RIGHT | 3          ; prev
    DB PADF_DOWN | 6           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Farm4"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node5:
    .begin
    DB 12, 11  ; row/col
    D_TRAIL TS1, TS1, TE1, TE1, TE1, TE1, TE1, TN1, TN1
    DB PADF_DOWN | 6           ; prev
    DB 0                       ; next
    DB 0                       ; bonus
    D_TITLE 16, "Don't Have a Cow"
    ASSERT @ - .begin == sizeof_NODE
_Farm_Node6:
    .begin
    DB 12, 16  ; row/col
    D_TRAIL TW1, TN1, TN1, TN1, TN1
    DB PADF_LEFT | 4           ; prev
    DB PADF_RIGHT | EXIT_NODE  ; next
    DB PADF_DOWN | 5           ; bonus
    D_TITLE 16, "Farm6"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Farm_Node0 == NUM_FARM_PUZZLES * sizeof_NODE

DataX_Mountain_area:
    .begin
    D_BPTR DataX_TitleMusic_song
    DB COLORSET_SUMMER
    DB TILESET_MAP_FOREST
    D_BPTR DataX_MountainTileMap_start
    D_TITLE 20, "MT. BIGHORN"
    D_TRAIL TS1, TS2, TS1, US1
    DB FIRST_MOUNTAIN_PUZZLE
    DB NUM_MOUNTAIN_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Mountain_Node0:
    .begin
    DB 14, 3  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_UP | 1             ; next
    DB 0                       ; bonus
    D_TITLE 16, "Rocky Hills"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node1:
    .begin
    DB 10, 5  ; row/col
    D_TRAIL TW1, TW1, TS1, TS2, TS1
    DB PADF_LEFT | 0           ; prev
    DB PADF_UP | 2             ; next
    DB 0                       ; bonus
    D_TITLE 16, "Mountain1"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node2:
    .begin
    DB 4, 7  ; row/col
    D_TRAIL TW1, TW1, TS1, TS2, TS2, TS1
    DB PADF_LEFT | 1           ; prev
    DB PADF_RIGHT | 3          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Mountain2"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node3:
    .begin
    DB 8, 11  ; row/col
    D_TRAIL TW1, TW1, TW1, TN1, TN2, TN1, TW1
    DB PADF_LEFT | 2           ; prev
    DB PADF_DOWN | 4           ; next
    DB 0                       ; bonus
    D_TITLE 16, "Mountain3"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node4:
    .begin
    DB 9, 15  ; row/col
    D_TRAIL TW1, TS1, TS1, TS1, TW1, TW1, TW1, TN1, TN2, TN1
    DB PADF_LEFT | 3           ; prev
    DB PADF_RIGHT | 6          ; next
    DB PADF_UP | 5             ; bonus
    D_TITLE 16, "Mountain4"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node5:
    .begin
    DB 2, 15  ; row/col
    D_TRAIL TS2, TS2, TS1, TS1, TS1
    DB PADF_DOWN | 4           ; prev
    DB 0                       ; next
    DB 0                       ; bonus
    D_TITLE 16, "Mountain Bonus"
    ASSERT @ - .begin == sizeof_NODE
_Mountain_Node6:
    .begin
    DB 11, 17  ; row/col
    D_TRAIL TN1, TN1, TW1, TW1
    DB PADF_UP | 4             ; prev
    DB PADF_DOWN | EXIT_NODE   ; next
    DB 0                       ; bonus
    D_TITLE 16, "Mountain6"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Mountain_Node0 == NUM_MOUNTAIN_PUZZLES * sizeof_NODE

DataX_Seaside_area:
    .begin
    D_BPTR DataX_RestYe_song
    DB COLORSET_AUTUMN
    DB TILESET_MAP_WORLD
    D_BPTR DataX_FarmTileMap_start  ; TODO: use seaside tile map
    D_TITLE 20, "MIDDLING LAKE"
    D_TRAIL TN1, TN1, TN1, TN1, TN1, TN1, TN1, TN1
    DB FIRST_SEASIDE_PUZZLE
    DB NUM_SEASIDE_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Seaside_Node0:
    .begin
    DB 8, 4  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_RIGHT | 1          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Seaside0"
    ASSERT @ - .begin == sizeof_NODE
_Seaside_Node1:
    .begin
    DB 8, 12  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | 0           ; prev
    DB PADF_UP | EXIT_NODE     ; next
    DB 0                       ; bonus
    D_TITLE 16, "Seaside1"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Seaside_Node0 == NUM_SEASIDE_PUZZLES * sizeof_NODE

DataX_Sewer_area:
    .begin
    D_BPTR DataX_RestYe_song
    DB COLORSET_SEWER
    DB TILESET_MAP_SEWER
    D_BPTR DataX_SewerTileMap_start
    D_TITLE 20, "DEMI SEWERS"
    D_TRAIL TN1, TN2, TN1
    DB FIRST_SEWER_PUZZLE
    DB NUM_SEWER_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Sewer_Node0:
    .begin
    DB 8, 3  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_RIGHT | 1          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Pipe Playground"
    ASSERT @ - .begin == sizeof_NODE
_Sewer_Node1:
    .begin
    DB 13, 5  ; row/col
    D_TRAIL TN1, TN1, TN1, TN1, TN1, TW1, TW1
    DB PADF_UP | 0             ; prev
    DB PADF_RIGHT | EXIT_NODE  ; next
    DB 0                       ; bonus
    D_TITLE 16, "Blocked Drain"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Sewer_Node0 == NUM_SEWER_PUZZLES * sizeof_NODE

DataX_City_area:
    .begin
    D_BPTR DataX_RestYe_song
    DB COLORSET_AUTUMN
    DB TILESET_MAP_WORLD
    D_BPTR DataX_FarmTileMap_start  ; TODO: use city tile map
    D_TITLE 20, "MICROVILLE"
    D_TRAIL TN1, TN1, TN1, TN1, TN1, TN1, TN1, TN1
    DB FIRST_CITY_PUZZLE
    DB NUM_CITY_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_City_Node0:
    .begin
    DB 8, 4  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_RIGHT | 1          ; next
    DB 0                       ; bonus
    D_TITLE 16, "City0"
    ASSERT @ - .begin == sizeof_NODE
_City_Node1:
    .begin
    DB 8, 12  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | 0           ; prev
    DB PADF_UP | EXIT_NODE     ; next
    DB 0                       ; bonus
    D_TITLE 16, "City1"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _City_Node0 == NUM_CITY_PUZZLES * sizeof_NODE

DataX_Space_area:
    .begin
    D_BPTR DataX_RestYe_song
    DB COLORSET_SPACE
    DB TILESET_MAP_SPACE
    D_BPTR DataX_SpaceTileMap_start
    D_TITLE 20, "NEUTRINO STATION"
    D_TRAIL TN1, TN1, TN1, TN1, TN1, TN1, TN1, TN1
    DB FIRST_SPACE_PUZZLE
    DB NUM_SPACE_PUZZLES
    ASSERT @ - .begin == AREA_Nodes_node_arr
_Space_Node0:
    .begin
    DB 8, 4  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1, TW1
    DB PADF_LEFT | EXIT_NODE   ; prev
    DB PADF_RIGHT | 1          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Warp Speedway"
    ASSERT @ - .begin == sizeof_NODE
_Space_Node1:
    .begin
    DB 8, 8  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | 0           ; prev
    DB PADF_RIGHT | 2          ; next
    DB 0                       ; bonus
    D_TITLE 16, "Space1"
    ASSERT @ - .begin == sizeof_NODE
_Space_Node2:
    .begin
    DB 8, 12  ; row/col
    D_TRAIL TW1, TW1, TW1, TW1
    DB PADF_LEFT | 1           ; prev
    DB PADF_UP | EXIT_NODE     ; next
    DB 0                       ; bonus
    D_TITLE 16, "Space2"
    ASSERT @ - .begin == sizeof_NODE
ASSERT @ - _Space_Node0 == NUM_SPACE_PUZZLES * sizeof_NODE

;;;=========================================================================;;;

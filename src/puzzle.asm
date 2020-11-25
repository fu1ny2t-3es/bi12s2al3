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

INCLUDE "src/hardware.inc"
INCLUDE "src/macros.inc"
INCLUDE "src/puzzle.inc"

;;;=========================================================================;;;

ELEPHANT_SL1_TILEID EQU 0
ELEPHANT_NL1_TILEID EQU 8
ELEPHANT_WL1_TILEID EQU 16

GOAT_SL1_TILEID EQU 24
GOAT_NL1_TILEID EQU 32
GOAT_WL1_TILEID EQU 40

MOUSE_SL1_TILEID EQU 48
MOUSE_NL1_TILEID EQU 56
MOUSE_WL1_TILEID EQU 64

ARROW_NS_TILEID EQU 72
STOP_NS_TILEID  EQU 74
ARROW_EW_TILEID EQU 76
STOP_EW_TILEID  EQU 78

;;;=========================================================================;;;

SECTION "PuzzleState", WRAM0, ALIGN[8]

;;; A 256-byte-aligned in-RAM copy of the current puzzle's ROM data, possibly
;;; mutated from its original state.
Ram_PuzzleState_puzz:
    DS sizeof_PUZZ

;;;=========================================================================;;;

SECTION "PuzzleUiState", WRAM0

;;; A pointer to the original PUZZ struct ROM for the current puzzle.
Ram_PuzzleRom_ptr:
    DW

;;; This should be set to one of the ANIMAL_* constants.
Ram_SelectedAnimal_u8:
    DB

;;; A bitfield indicating in which directions the currently-selected animal can
;;;   move.  This uses the DIRB_* and DIRF_* constants.
Ram_MoveDirs_u8:
    DB

;;; A counter that is incremented once per frame and that can be used to drive
;;; looping animations.
Ram_AnimationClock_u8:
    DB

;;; How far forward from its current position the selected animal has moved.
Ram_MovedPixels_u8:
    DB

;;;=========================================================================;;;

SECTION "MainPuzzleScreen", ROM0

;;; @prereq LCD is off.
Main_ResetPuzzle::
    ld a, [Ram_PuzzleRom_ptr + 0]
    ld e, a
    ld a, [Ram_PuzzleRom_ptr + 1]
    ld d, a
    jr _BeginPuzzle_Init

;;; @prereq LCD is off.
;;; @param c Current puzzle number.
Main_BeginPuzzle::
    ;; Store pointer to current PUZZ struct in de...
    sla c
    ld b, 0
    ld hl, Data_PuzzlePtrs_start
    add hl, bc
    ld a, [hl+]
    ld d, [hl]
    ld e, a
    ;; ... and also in Ram_PuzzleRom_ptr.
    ld [Ram_PuzzleRom_ptr + 0], a
    ld a, d
    ld [Ram_PuzzleRom_ptr + 1], a
_BeginPuzzle_Init:
    ;; Copy current puzzle into RAM.
    ld hl, Ram_PuzzleState_puzz  ; dest
    ld bc, sizeof_PUZZ           ; count
    call Func_MemCopy
    ;; Load terrain map.
    ASSERT LOW(Ram_PuzzleState_puzz) == 0
    ld d, HIGH(Ram_PuzzleState_puzz)
    call Func_LoadTerrainIntoVram
    ;; Initialize state.
    xor a
    ld [Ram_AnimationClock_u8], a
    ld [Ram_MovedPixels_u8], a
    ;; Set up animal objects.
    call Func_ClearOam
    ld a, ANIMAL_MOUSE
    ld [Ram_SelectedAnimal_u8], a
    call Func_UpdateSelectedAnimalObjs
    ld a, ANIMAL_GOAT
    ld [Ram_SelectedAnimal_u8], a
    call Func_UpdateSelectedAnimalObjs
    ld a, ANIMAL_ELEPHANT
    ld [Ram_SelectedAnimal_u8], a
    call Func_UpdateSelectedAnimalObjs
    ;; Set up arrow objects.
    ld a, OAMF_PAL1
    ld [Ram_ArrowN_oama + OAMA_FLAGS], a
    ld [Ram_ArrowE_oama + OAMA_FLAGS], a
    ld a, OAMF_PAL1 | OAMF_XFLIP
    ld [Ram_ArrowW_oama + OAMA_FLAGS], a
    ld a, OAMF_PAL1 | OAMF_YFLIP
    ld [Ram_ArrowS_oama + OAMA_FLAGS], a
    call Func_UpdateMoveDirs
    ;; Set up window.
    ld hl, Vram_WindowMap + 2 + 1 * SCRN_VX_B                       ; dest
    ld de, Data_PauseMenuString1_start                              ; src
    ld bc, Data_PauseMenuString1_end - Data_PauseMenuString1_start  ; count
    call Func_MemCopy
    ld hl, Vram_WindowMap + 2 + 2 * SCRN_VX_B                       ; dest
    ld de, Data_PauseMenuString2_start                              ; src
    ld bc, Data_PauseMenuString2_end - Data_PauseMenuString2_start  ; count
    call Func_MemCopy
    ld hl, Vram_WindowMap + 2 + 3 * SCRN_VX_B                       ; dest
    ld de, Data_PauseMenuString3_start                              ; src
    ld bc, Data_PauseMenuString3_end - Data_PauseMenuString3_start  ; count
    call Func_MemCopy
    ;; Initialize music.
    ld c, BANK(Data_TitleMusic_song)
    ld hl, Data_TitleMusic_song
    call Func_MusicStart
    ;; Turn on the LCD and fade in.
    call Func_PerformDma
    xor a
    ld [rSCX], a
    ld [rSCY], a
    call Func_FadeIn
    ld a, %11010000
    ldh [rOBP1], a
    ;; fall through to Main_PuzzleCommand

Main_PuzzleCommand::
    ld hl, Ram_AnimationClock_u8
    inc [hl]
    call Func_UpdateArrowObjs
    call Func_MusicUpdate
    call Func_WaitForVBlankAndPerformDma
    call Func_UpdateButtonState
    ld a, [Ram_ButtonsPressed_u8]
    ld b, a
_PuzzleCommand_HandleButtonStart:
    bit PADB_START, b
    jr z, .noPress
    jp Main_BeginPause
    .noPress
_PuzzleCommand_HandleButtonA:
    bit PADB_A, b
    jr z, .noPress
    ld a, [Ram_SelectedAnimal_u8]
    inc a
    if_lt 3, jr, .noOverflow
    xor a
    .noOverflow
    jr _PuzzleCommand_SelectAnimal
    .noPress
_PuzzleCommand_HandleButtonB:
    bit PADB_B, b
    jr z, .noPress
    ld a, [Ram_SelectedAnimal_u8]
    sub 1
    jr nc, .noUnderflow
    ld a, 2
    .noUnderflow
    jr _PuzzleCommand_SelectAnimal
    .noPress
_PuzzleCommand_HandleButtonUp:
    bit PADB_UP, b
    jr z, .noPress
    ld d, DIRF_NORTH
    jr _PuzzleCommand_TryMove
    .noPress
_PuzzleCommand_HandleButtonDown:
    bit PADB_DOWN, b
    jr z, .noPress
    ld d, DIRF_SOUTH
    jr _PuzzleCommand_TryMove
    .noPress
_PuzzleCommand_HandleButtonLeft:
    bit PADB_LEFT, b
    jr z, .noPress
    ld d, DIRF_WEST
    jr _PuzzleCommand_TryMove
    .noPress
_PuzzleCommand_HandleButtonRight:
    bit PADB_RIGHT, b
    jr z, Main_PuzzleCommand
    ld d, DIRF_EAST
    jr _PuzzleCommand_TryMove

_PuzzleCommand_SelectAnimal:
    ld [Ram_SelectedAnimal_u8], a
    call Func_UpdateMoveDirs
    jr Main_PuzzleCommand

_PuzzleCommand_TryMove:
    ;; Check if we can move in the DIRF_* direction that's stored in d.
    ld a, [Ram_MoveDirs_u8]
    and d
    jr z, _PuzzleCommand_CannotMove
    ;; We can move, so store d in ANIM_Facing_u8 and switch to AnimalMoving
    ;; mode.
    call Func_GetSelectedAnimalPtr_hl  ; preserves d
    ASSERT ANIM_Facing_u8 == 1
    inc hl
    ld a, d
    ld [hl], a
    jp Main_AnimalMoving

_PuzzleCommand_CannotMove:
    ld a, %00101101
    ldh [rAUD1SWEEP], a
    ld a, %10010000
    ldh [rAUD1LEN], a
    ld a, %11000010
    ldh [rAUD1ENV], a
    ld a, %11000000
    ldh [rAUD1LOW], a
    ld a, %10000111
    ldh [rAUD1HIGH], a
    jp Main_PuzzleCommand

;;;=========================================================================;;;

;;; Returns a pointer to the ANIM struct of the currently selected animal.
;;; @return hl A pointer to an ANIM struct.
;;; @preserve bc, de
Func_GetSelectedAnimalPtr_hl:
    ld a, [Ram_SelectedAnimal_u8]
    if_eq ANIMAL_MOUSE, jr, .mouseSelected
    if_eq ANIMAL_GOAT, jr, .goatSelected
    .elephantSelected
    ld hl, Ram_PuzzleState_puzz + PUZZ_Elephant_anim
    ret
    .goatSelected
    ld hl, Ram_PuzzleState_puzz + PUZZ_Goat_anim
    ret
    .mouseSelected
    ld hl, Ram_PuzzleState_puzz + PUZZ_Mouse_anim
    ret

;;;=========================================================================;;;

;;; Updates Ram_MoveDirs_u8 for the currently selected animal.
Func_UpdateMoveDirs:
    ;; Store the animal's current position in l.
    call Func_GetSelectedAnimalPtr_hl
    ASSERT ANIM_Position_u8 == 0
    ld l, [hl]
    ;; Make hl point to the terrain cell for the animal's current position.
    ASSERT LOW(Ram_PuzzleState_puzz) == 0
    ld h, HIGH(Ram_PuzzleState_puzz)
    ;; We'll track the new value for Ram_MoveDirs_u8 in b.  To start with,
	;; initialize it to allow all four dirations.
    ld b, DIRF_NORTH | DIRF_SOUTH | DIRF_EAST | DIRF_WEST
_UpdateMoveDirs_West:
    ;; Check if we're on the west edge of the screen.
    ld a, l
    and $0f
    jr nz, .noEdge
    res DIRB_WEST, b
    jr .done
    .noEdge
    ;; If not, then check if we're blocked to the west.
    dec l
    call Func_IsPositionBlocked_fz  ; preserves b and hl
    jr nz, .unblocked
    res DIRB_WEST, b
    .unblocked
    inc l
    .done
_UpdateMoveDirs_East:
    ;; Check if we're on the east edge of the screen.
    ld a, l
    and $0f
    if_lt (TERRAIN_COLS - 1), jr, .noEdge
    res DIRB_EAST, b
    jr .done
    .noEdge
    ;; If not, then check if we're blocked to the east.
    inc l
    call Func_IsPositionBlocked_fz  ; preserves b and hl
    jr nz, .unblocked
    res DIRB_EAST, b
    .unblocked
    dec l
    .done
_UpdateMoveDirs_North:
    ;; Check if we're on the north edge of the screen.
    ld a, l
    and $f0
    jr nz, .noEdge
    res DIRB_NORTH, b
    jr .done
    .noEdge
    ;; If not, then check if we're blocked to the north.
    ld a, l
    sub 16
    ld l, a
    call Func_IsPositionBlocked_fz  ; preserves b and hl
    jr nz, .unblocked
    res DIRB_NORTH, b
    .unblocked
    ld a, l
    add 16
    ld l, a
    .done
_UpdateMoveDirs_South:
    ;; Check if we're on the south edge of the screen.
    ld a, l
    and $f0
    if_lt (16 * (TERRAIN_ROWS - 1)), jr, .noEdge
    res DIRB_SOUTH, b
    jr .done
    .noEdge
    ;; If not, then check if we're blocked to the south.
    ld a, l
    add 16
    ld l, a
    call Func_IsPositionBlocked_fz  ; preserves b
    jr nz, .unblocked
    res DIRB_SOUTH, b
    .unblocked
    .done
_UpdateMoveDirs_Finish:
    ld a, b
    ld [Ram_MoveDirs_u8], a
    ret


;;; Determines whether the specified position is blocked for the selected
;;; animal.
;;; @param hl A pointer to the terrain cell in Ram_PuzzleState_puzz to check.
;;; @return fz True if the position is blocked by a wall or animal.
;;; @preserve b, hl
Func_IsPositionBlocked_fz:
    ;; Check for a wall:
    ld a, [hl]
    if_ge W_MIN, jr, .blocked
    ;; Check for a mousehole:
    if_lt M_MIN, jr, .noMousehole
    ld a, [Ram_SelectedAnimal_u8]
    if_ne ANIMAL_MOUSE, jr, .blocked
    .noMousehole
    ;; Otherwise, check for an animal:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Elephant_anim + ANIM_Position_u8]
    cp l
    ret z
    ld a, [Ram_PuzzleState_puzz + PUZZ_Goat_anim + ANIM_Position_u8]
    cp l
    ret z
    ld a, [Ram_PuzzleState_puzz + PUZZ_Mouse_anim + ANIM_Position_u8]
    cp l
    ret
    ;; We jump here if the position is definitely blocked.
    .blocked
    xor a  ; set z flag
    ret

;;;=========================================================================;;;

;;; Updates the OAMA struct for the currently selected animal.
;;; @preserve hl
Func_UpdateSelectedAnimalObjs:
    ld a, [Ram_SelectedAnimal_u8]
    if_eq ANIMAL_MOUSE, jp, _UpdateSelectedAnimalObjs_Mouse
    if_eq ANIMAL_GOAT, jp, _UpdateSelectedAnimalObjs_Goat
_UpdateSelectedAnimalObjs_Elephant:
    ld a, [Ram_MovedPixels_u8]
    ld c, a
    ld a, [Ram_PuzzleState_puzz + PUZZ_Elephant_anim + ANIM_Facing_u8]
    ld b, a
_UpdateSelectedAnimalObjs_ElephantYPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Elephant_anim + ANIM_Position_u8]
    and $f0
    add 16
    bit DIRB_NORTH, b
    jr z, .notNorth
    sub c
    jr .notSouth
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .notSouth
    add c
    .notSouth
    ld [Ram_ElephantL_oama + OAMA_Y], a
    ld [Ram_ElephantR_oama + OAMA_Y], a
_UpdateSelectedAnimalObjs_ElephantXPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Elephant_anim + ANIM_Position_u8]
    and $0f
    swap a
    add 8
    bit DIRB_WEST, b
    jr z, .notWest
    sub c
    jr .notEast
    .notWest
    bit DIRB_EAST, b
    jr z, .notEast
    add c
    .notEast
    ld [Ram_ElephantL_oama + OAMA_X], a
    add 8
    ld [Ram_ElephantR_oama + OAMA_X], a
_UpdateSelectedAnimalObjs_ElephantTileAndFlags:
    ld a, c
    and %00001000
    rrca
    bit DIRB_EAST, b
    jr z, .notEast
    add ELEPHANT_WL1_TILEID
    ld [Ram_ElephantR_oama + OAMA_TILEID], a
    add 2
    ld [Ram_ElephantL_oama + OAMA_TILEID], a
    ld a, OAMF_XFLIP
    ld [Ram_ElephantL_oama + OAMA_FLAGS], a
    ld [Ram_ElephantR_oama + OAMA_FLAGS], a
    ret
    .notEast
    bit DIRB_WEST, b
    jr z, .notWest
    add ELEPHANT_WL1_TILEID
    jr .finish
    .notWest
    bit DIRB_NORTH, b
    jr z, .notNorth
    add ELEPHANT_NL1_TILEID
    jr .finish
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .finish
    add ELEPHANT_SL1_TILEID
    .finish
    ld [Ram_ElephantL_oama + OAMA_TILEID], a
    add 2
    ld [Ram_ElephantR_oama + OAMA_TILEID], a
    xor a
    ld [Ram_ElephantL_oama + OAMA_FLAGS], a
    ld [Ram_ElephantR_oama + OAMA_FLAGS], a
    ret

_UpdateSelectedAnimalObjs_Goat:
    ld a, [Ram_MovedPixels_u8]
    ld c, a
    ld a, [Ram_PuzzleState_puzz + PUZZ_Goat_anim + ANIM_Facing_u8]
    ld b, a
_UpdateSelectedAnimalObjs_GoatYPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Goat_anim + ANIM_Position_u8]
    and $f0
    add 16
    bit DIRB_NORTH, b
    jr z, .notNorth
    sub c
    jr .notSouth
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .notSouth
    add c
    .notSouth
    ld [Ram_GoatL_oama + OAMA_Y], a
    ld [Ram_GoatR_oama + OAMA_Y], a
_UpdateSelectedAnimalObjs_GoatXPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Goat_anim + ANIM_Position_u8]
    and $0f
    swap a
    add 8
    bit DIRB_WEST, b
    jr z, .notWest
    sub c
    jr .notEast
    .notWest
    bit DIRB_EAST, b
    jr z, .notEast
    add c
    .notEast
    ld [Ram_GoatL_oama + OAMA_X], a
    add 8
    ld [Ram_GoatR_oama + OAMA_X], a
_UpdateSelectedAnimalObjs_GoatTileAndFlags:
    ld a, c
    and %00001000
    rrca
    bit DIRB_EAST, b
    jr z, .notEast
    add GOAT_WL1_TILEID
    ld [Ram_GoatR_oama + OAMA_TILEID], a
    add 2
    ld [Ram_GoatL_oama + OAMA_TILEID], a
    ld a, OAMF_PAL1 | OAMF_XFLIP
    ld [Ram_GoatL_oama + OAMA_FLAGS], a
    ld [Ram_GoatR_oama + OAMA_FLAGS], a
    ret
    .notEast
    bit DIRB_WEST, b
    jr z, .notWest
    add GOAT_WL1_TILEID
    jr .finish
    .notWest
    bit DIRB_NORTH, b
    jr z, .notNorth
    add GOAT_NL1_TILEID
    jr .finish
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .finish
    add GOAT_SL1_TILEID
    .finish
    ld [Ram_GoatL_oama + OAMA_TILEID], a
    add 2
    ld [Ram_GoatR_oama + OAMA_TILEID], a
    ld a, OAMF_PAL1
    ld [Ram_GoatL_oama + OAMA_FLAGS], a
    ld [Ram_GoatR_oama + OAMA_FLAGS], a
    ret

_UpdateSelectedAnimalObjs_Mouse:
    ld a, [Ram_MovedPixels_u8]
    ld c, a
    ld a, [Ram_PuzzleState_puzz + PUZZ_Mouse_anim + ANIM_Facing_u8]
    ld b, a
_UpdateSelectedAnimalObjs_MouseYPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Mouse_anim + ANIM_Position_u8]
    and $f0
    add 16
    bit DIRB_NORTH, b
    jr z, .notNorth
    sub c
    jr .notSouth
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .notSouth
    add c
    .notSouth
    ld [Ram_MouseL_oama + OAMA_Y], a
    ld [Ram_MouseR_oama + OAMA_Y], a
_UpdateSelectedAnimalObjs_MouseXPosition:
    ld a, [Ram_PuzzleState_puzz + PUZZ_Mouse_anim + ANIM_Position_u8]
    and $0f
    swap a
    add 8
    bit DIRB_WEST, b
    jr z, .notWest
    sub c
    jr .notEast
    .notWest
    bit DIRB_EAST, b
    jr z, .notEast
    add c
    .notEast
    ld [Ram_MouseL_oama + OAMA_X], a
    add 8
    ld [Ram_MouseR_oama + OAMA_X], a
_UpdateSelectedAnimalObjs_MouseTileAndFlags:
    ld a, c
    and %00000100
    bit DIRB_EAST, b
    jr z, .notEast
    add MOUSE_WL1_TILEID
    ld [Ram_MouseR_oama + OAMA_TILEID], a
    add 2
    ld [Ram_MouseL_oama + OAMA_TILEID], a
    ld a, OAMF_XFLIP
    ld [Ram_MouseL_oama + OAMA_FLAGS], a
    ld [Ram_MouseR_oama + OAMA_FLAGS], a
    ret
    .notEast
    bit DIRB_WEST, b
    jr z, .notWest
    add MOUSE_WL1_TILEID
    jr .finish
    .notWest
    bit DIRB_NORTH, b
    jr z, .notNorth
    add MOUSE_NL1_TILEID
    jr .finish
    .notNorth
    bit DIRB_SOUTH, b
    jr z, .finish
    add MOUSE_SL1_TILEID
    .finish
    ld [Ram_MouseL_oama + OAMA_TILEID], a
    add 2
    ld [Ram_MouseR_oama + OAMA_TILEID], a
    xor a
    ld [Ram_MouseL_oama + OAMA_FLAGS], a
    ld [Ram_MouseR_oama + OAMA_FLAGS], a
    ret

;;;=========================================================================;;;

;;; Updates the X, Y, and TILEID fields for all four Ram_Arrow?_oama objects,
;;; based on the Position/MoveDirs of the currently selected animal.
Func_UpdateArrowObjs:
    ;; Store selected animal's position in b and movedirs in d.
    call Func_GetSelectedAnimalPtr_hl
    ASSERT ANIM_Position_u8 == 0
    ld b, [hl]
    ld a, [Ram_MoveDirs_u8]
    ld d, a
    ;; Store the animal's obj left in c and top in b.
    ld a, b
    and $0f
    swap a
    add 8
    ld c, a
    add 4
    ld [Ram_ArrowN_oama + OAMA_X], a
    ld [Ram_ArrowS_oama + OAMA_X], a
    ld a, b
    and $f0
    add 16
    ld b, a
    ld [Ram_ArrowE_oama + OAMA_Y], a
    ld [Ram_ArrowW_oama + OAMA_Y], a
    ;; Store (clock % 32 >= 16 ? 1 : 0) in e.
    ld a, [Ram_AnimationClock_u8]
    and %00010000
    swap a
    ld e, a
_UpdateArrowObjs_North:
    bit DIRB_NORTH, d
    jr z, .shapeStop
    ld a, ARROW_NS_TILEID
    jr .endShape
    .shapeStop
    ld a, STOP_NS_TILEID
    .endShape
    ld [Ram_ArrowN_oama + OAMA_TILEID], a
    ld a, b
    sub 16
    sub e
    ld [Ram_ArrowN_oama + OAMA_Y], a
_UpdateArrowObjs_South:
    bit DIRB_SOUTH, d
    jr z, .shapeStop
    ld a, ARROW_NS_TILEID
    jr .endShape
    .shapeStop
    ld a, STOP_NS_TILEID
    .endShape
    ld [Ram_ArrowS_oama + OAMA_TILEID], a
    ld a, b
    add 16
    add e
    ld [Ram_ArrowS_oama + OAMA_Y], a
_UpdateArrowObjs_East:
    bit DIRB_EAST, d
    jr z, .shapeStop
    ld a, ARROW_EW_TILEID
    jr .endShape
    .shapeStop
    ld a, STOP_EW_TILEID
    .endShape
    ld [Ram_ArrowE_oama + OAMA_TILEID], a
    ld a, c
    add 17
    add e
    ld [Ram_ArrowE_oama + OAMA_X], a
_UpdateArrowObjs_West:
    bit DIRB_WEST, d
    jr z, .shapeStop
    ld a, ARROW_EW_TILEID
    jr .endShape
    .shapeStop
    ld a, STOP_EW_TILEID
    .endShape
    ld [Ram_ArrowW_oama + OAMA_TILEID], a
    ld a, c
    sub 9
    sub e
    ld [Ram_ArrowW_oama + OAMA_X], a
    ret

;;;=========================================================================;;;

SECTION "MainAnimalMoving", ROM0

Main_AnimalMoving:
    xor a
    ld [Ram_ArrowN_oama + OAMA_Y], a
    ld [Ram_ArrowS_oama + OAMA_Y], a
    ld [Ram_ArrowE_oama + OAMA_Y], a
    ld [Ram_ArrowW_oama + OAMA_Y], a
    ld [Ram_MovedPixels_u8], a
_AnimalMoving_RunLoop:
    ld hl, Ram_AnimationClock_u8
    inc [hl]
    call Func_MusicUpdate
    call Func_WaitForVBlankAndPerformDma
    ;; Move animal forward by 1-2 pixels.
    ld a, [Ram_SelectedAnimal_u8]
    if_eq ANIMAL_MOUSE, jr, .fast
    if_eq ANIMAL_ELEPHANT, jr, .slow
    ld a, [Ram_MovedPixels_u8]
    bit 1, a
    jr nz, .fast
    .slow
    ld b, 1
    jr .move
    .fast
    ld b, 2
    .move
    ld a, [Ram_MovedPixels_u8]
    add b
    ;; Check if we've reached the next square.
    if_eq 16, jr, _AnimalMoving_ChangePosition
    ld [Ram_MovedPixels_u8], a
    call Func_UpdateSelectedAnimalObjs
    jr _AnimalMoving_RunLoop

_AnimalMoving_ChangePosition:
    xor a
    ld [Ram_MovedPixels_u8], a
    ;; Store selected animal's ANIM_Facing_u8 in a, and ANIM ptr in hl.
    call Func_GetSelectedAnimalPtr_hl
    ASSERT ANIM_Facing_u8 == 1
    inc hl
    ld a, [hl-]
    ;; Move the animal forward by one square, updating its ANIM_Position_u8.
    if_eq DIRF_WEST, jr, .facingWest
    if_eq DIRF_EAST, jr, .facingEast
    if_eq DIRF_SOUTH, jr, .facingSouth
    .facingNorth
    ld d, $f0
    jr .changePos
    .facingSouth
    ld d, $10
    jr .changePos
    .facingEast
    ld d, $01
    jr .changePos
    .facingWest
    ld d, $ff
    .changePos
    ASSERT ANIM_Position_u8 == 0
    ld a, [hl]
    add d
    ld [hl+], a
    ASSERT ANIM_Facing_u8 == 1
_AnimalMoving_TerrainActions:
    ;; Store the terrain type the animal is standing on in a.
    ASSERT LOW(Ram_PuzzleState_puzz) == 0
    ld d, HIGH(Ram_PuzzleState_puzz)
    ld e, a
    ld a, [de]
    ;; Check for terrain actions.
    if_ne A_NOR, jr, .notNorthArrow
    ld [hl], DIRF_NORTH
    jr _AnimalMoving_Update
    .notNorthArrow
    if_ne A_SOU, jr, .notSouthArrow
    ld [hl], DIRF_SOUTH
    jr _AnimalMoving_Update
    .notSouthArrow
    if_ne A_EST, jr, .notEastArrow
    ld [hl], DIRF_EAST
    jr _AnimalMoving_Update
    .notEastArrow
    if_ne A_WST, jr, .notWestArrow
    ld [hl], DIRF_WEST
    jr _AnimalMoving_Update
    .notWestArrow
_AnimalMoving_Update:
    call Func_UpdateSelectedAnimalObjs  ; preserves hl
    ;; Check if we can keep going.
    push hl
    call Func_UpdateMoveDirs
    pop hl
    ld d, [hl]
    ld a, [Ram_MoveDirs_u8]
    and d
    jp nz, _AnimalMoving_RunLoop
_AnimalMoving_DoneMoving:
    ;; Time to check if we've solved the puzzle.
    ASSERT LOW(Ram_PuzzleState_puzz) == 0
    ld h, HIGH(Ram_PuzzleState_puzz)
    ;; If the elephant isn't on the peanut, we haven't solved the puzzle.
    ld a, [Ram_PuzzleState_puzz + PUZZ_Elephant_anim + ANIM_Position_u8]
    ld l, a
    ld a, [hl]
    if_ne G_PNT, jp, Main_PuzzleCommand
    ;; If the goat isn't on the apple, we haven't solved the puzzle.
    ld a, [Ram_PuzzleState_puzz + PUZZ_Goat_anim + ANIM_Position_u8]
    ld l, a
    ld a, [hl]
    if_ne G_APL, jp, Main_PuzzleCommand
    ;; If the mouse isn't on the cheese, we haven't solved the puzzle.
    ld a, [Ram_PuzzleState_puzz + PUZZ_Mouse_anim + ANIM_Position_u8]
    ld l, a
    ld a, [hl]
    if_ne G_CHS, jp, Main_PuzzleCommand
    ;; We've solved the puzzle, so go to victory mode.
    jp Main_Victory

;;;=========================================================================;;;

SECTION "MainVictory", ROM0

Main_Victory:
    ;; TODO: Play victory music, animate animals.
    call Func_FadeOut
    ld c, 1  ; is victory (1=true)
    jp Main_WorldMapScreen

;;;=========================================================================;;;

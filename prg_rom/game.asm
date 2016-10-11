init_game_state:
.(
lda DIRECTION_LEFT
sta player_b_direction

lda DIRECTION_RIGHT
sta player_a_direction

lda HITBOX_DISABLED
sta player_a_hitbox_enabled
sta player_b_hitbox_enabled

lda #$00
sta player_a_y_low
sta player_b_y_low
sta player_a_x_low
sta player_b_x_low
lda #$80
sta player_a_y
sta player_b_y
sta player_a_hurtbox_top
sta player_b_hurtbox_top
lda #$40
sta player_a_x
sta player_a_hurtbox_left
lda #$a0
sta player_b_x
sta player_a_hurtbox_left
lda #$88
sta player_a_hurtbox_bottom
sta player_b_hurtbox_bottom
lda #$48
sta player_a_hurtbox_right
lda #$a8
sta player_b_hurtbox_right

ldx #$00
jsr start_standing_player
ldx #$01
jsr start_standing_player

rts
.)

update_players:
.(
; Remove processed nametable buffers
lda #$00
sta nametable_buffers

; Check hitbox collisions
ldx #$00
hitbox_one_player:
jsr check_player_hit
inx
cpx #$02
bne hitbox_one_player

; Update both players
ldx #$00 ; player number
update_one_player:

; Call the state update routine
lda #<sinbad_state_update_routines
sta tmpfield1
lda #>sinbad_state_update_routines
sta tmpfield2
jsr player_state_action

; Call generic update routines
jsr move_player
jsr check_player_position
jsr write_player_damages

inx
cpx #$02
bne update_one_player

rts
.)

; Calls a subroutine depending on player's state
;  register X - Player number
;  tmpfield1 - Jump table address (low byte)
;  tmpfield2 - Jump table address (high bute)
player_state_action:
.(
jump_table = tmpfield1

; Convert player state number to vector address (relative to table begining)
lda player_a_state, x       ; Y = state * 2
asl                         ; (as each element is 2 bytes long)
tay                         ;

; Push the state's routine address to the stack
lda (jump_table), y
pha
iny
lda (jump_table), y
pha

; Return to the state's routine, it will itself return to player_state_action's caller
rts
.)

check_player_hit:
.(
current_player = tmpfield10
opponent_player = tmpfield11
force_h = tmpfield12
force_v = tmpfield13
force_h_low = tmpfield14
force_v_low = tmpfield15

.(
; Store current player number
stx current_player

; Check that player's hitbox is enabled
lda player_a_hitbox_enabled, x
beq end

; Store current player's hitbox
lda player_a_hitbox_left, x
sta tmpfield1
lda player_a_hitbox_right, x
sta tmpfield2
lda player_a_hitbox_top, x
sta tmpfield3
lda player_a_hitbox_bottom, x
sta tmpfield4

; Switch current player to select the opponent
jsr switch_selected_player

; Store opponent player number
stx opponent_player

; Store opponent's hurtbox
lda player_a_hurtbox_left, x
sta tmpfield5
lda player_a_hurtbox_right, x
sta tmpfield6
lda player_a_hurtbox_top, x
sta tmpfield7
lda player_a_hurtbox_bottom, x
sta tmpfield8

; Check collisions between hitbox and hurtbox
jsr boxes_overlap
lda tmpfield9
bne end

; Apply force vector to the opponent
jsr apply_force_vector

; Apply damages to the opponent
ldx current_player
lda player_a_hitbox_damages, x ; Put hitbox damages in A
ldx opponent_player
clc                     ;
adc player_a_damages, x ;
cmp #200                ;
bcs cap_damages         ; Apply damages, capped to 199
jmp apply_damages:      ;
cap_damages:            ;
lda #199                ;
apply_damages:          ;
sta player_a_damages, x ;

; Set opponent to thrown state
jsr start_thrown_player

; Disable the hitbox to avoid multi-hits
ldx current_player
lda HITBOX_DISABLED
sta player_a_hitbox_enabled, x

end:
; Reset register X to the current player
ldx current_player
rts
.)

; Apply force in current player's hitbox to it's opponent
;
; Overwrites every tmpfields except "current_player" and "opponent_player".
; Overwrites registers A and  X (set to the opponent player's number).
apply_force_vector:
.(
base_h_low = tmpfield6
base_h_high = tmpfield7
base_v_low = tmpfield8
base_v_high = tmpfield9

; Apply force vector to the opponent
ldx current_player
lda player_a_hitbox_force_h, x     ;
sta force_h                        ;
lda player_a_hitbox_force_h_low, x ;
sta force_h_low                    ; Save force vector to a player independent
lda player_a_hitbox_force_v, x     ; location
sta force_v                        ;
lda player_a_hitbox_force_v_low, x ;
sta force_v_low                    ;
lda player_a_hitbox_base_knock_up_h_high, x ;
sta base_h_high                             ;
lda player_a_hitbox_base_knock_up_h_low, x  ;
sta base_h_low                              ; Save base knock up to a player independent
lda player_a_hitbox_base_knock_up_v_high, x ; location
sta base_v_high                             ;
lda player_a_hitbox_base_knock_up_v_low, x  ;
sta base_v_low                              ;
ldx opponent_player
lda player_a_damages, x ; Get force multiplier
clc                     ; "damages + 1"
adc #$01                ;
sta tmpfield3           ;
lda force_h     ;
sta tmpfield2   ;
lda force_h_low ;
sta tmpfield1   ;
jsr multiply    ; Push "force_h * multiplier + base_h"
lda base_h_low  ;
clc             ;
adc tmpfield4   ;
sta tmpfield4   ;
lda base_h_high ;
adc tmpfield5   ;
pha             ;
lda tmpfield4   ;
pha             ;
lda force_v      ;
sta tmpfield2    ;
lda force_v_low  ;
sta tmpfield1    ;
jsr multiply     ; Push "force_v * multiplier + base_v"
lda base_v_low   ;
clc              ;
adc tmpfield4    ;
lda base_v_high  ;
adc tmpfield5    ;
pha              ;
lda tmpfield4    ;
pha              ;
jsr add_to_player_velocity ; Apply force vector from stack

rts
.)
.)

; Move the player according to it's velocity and collisions with obstacles
;  register X - player number
;
;  When returning player's position is updated, tmpfield1 contains it's old X
;  and tmpfield2 contains it's old Y
move_player:
.(
; Save old position
lda player_a_x, x
sta tmpfield1
lda player_a_y, x
sta tmpfield2

; Apply velocity to position
lda player_a_velocity_h_low, x
clc
adc player_a_x_low, x
sta tmpfield9
lda player_a_velocity_h, x
adc player_a_x, x
sta tmpfield3

lda player_a_velocity_v_low, x
clc
adc player_a_y_low, x
sta tmpfield10
lda player_a_velocity_v, x
adc player_a_y, x
sta tmpfield4

; Check collisions with stage plaform
lda STAGE_EDGE_LEFT
sta tmpfield5
lda STAGE_EDGE_TOP
sta tmpfield6
lda STAGE_EDGE_RIGHT
sta tmpfield7
lda STAGE_EDGE_BOTTOM
sta tmpfield8

jsr check_collision
lda tmpfield3
sta player_a_x, x
lda tmpfield4
sta player_a_y, x
lda tmpfield9
sta player_a_x_low, x
lda tmpfield10
sta player_a_y_low, x

rts
.)

; Check the player's position and modify the current state accordingly
;  register X - player number
;  tmpfield1 - player's old X
;  tmpfield2 - player's old Y
;
;  Overwrites tmpfield1 and tmpfield2
check_player_position:
.(
old_x = tmpfield1
old_y = tmpfield2

; Check death
lda player_a_velocity_h, x
bpl check_right_blast
lda old_x           ; Horizontal velocity is negative
cmp player_a_x, x   ; die if "old X < new X"
bcc set_death_state ;
jmp check_vertical_blasts
check_right_blast:
lda player_a_x, x   ; Horizontal velocity is positive
cmp old_x           ; die if "new X < old X"
bcc set_death_state ;
check_vertical_blasts
lda player_a_velocity_v, x
bpl check_bottom_blast
lda old_y           ; Vertical velocity is negative
cmp player_a_y, x   ; die if "old Y < new Y"
bcc set_death_state ;
jmp end_death_checks
check_bottom_blast:
lda player_a_y, x   ; Vertical velocity is positive
cmp old_y           ; die if "new Y < old Y"
bcc set_death_state ;
end_death_checks:

; Check if on ground
lda player_a_x, x
cmp STAGE_EDGE_LEFT
bcc offground
lda STAGE_EDGE_RIGHT
cmp player_a_x, x
bcc offground
lda player_a_y, x
cmp STAGE_EDGE_TOP
bne offground
lda player_a_y_low, x
bne offground

; On ground
lda #<sinbad_state_onground_routines
sta tmpfield1
lda #>sinbad_state_onground_routines
sta tmpfield2
jsr player_state_action
jmp end

offground:
lda #<sinbad_state_offground_routines
sta tmpfield1
lda #>sinbad_state_offground_routines
sta tmpfield2
jsr player_state_action
jmp end

set_death_state:
jsr start_respawn_player

end:
rts
.)

; Show on screen player's damages
;  register X must contain the player number
write_player_damages:
.(
ppu_position = tmpfield4

; Save X
txa
pha

; Set on-screen text position depending on the player
cpx #$00
beq prepare_player_a
lda #$91
sta ppu_position
jmp end_player_variables
prepare_player_a:
lda #$88
sta ppu_position
end_player_variables:

; Put damages value parameter for number_to_tile_indexes
lda player_a_damages, x
sta tmpfield1

; Write the begining of the buffer
jsr last_nt_buffer
lda #$01                 ; Continuation byte
sta nametable_buffers, x ;
inx
lda #$23                 ; PPU address MSB
sta nametable_buffers, x ;
inx
lda ppu_position         ; PPU address LSB
sta nametable_buffers, x ;
inx
lda #$03                 ; Tiles count
sta nametable_buffers, x ;
inx

; Store the tiles address as destination parameter for number_to_tile_indexes
txa
sta tmpfield2
lda #>nametable_buffers
sta tmpfield3

; Set the next continuation byte to 0
inx
inx
inx
lda #$00
sta nametable_buffers, x

; Populate tiles data
jsr number_to_tile_indexes

; Restore X
pla
tax

rts
.)

update_sprites:
.(
; Pretty names
animation_vector = tmpfield3   ; Not movable - Used as parameter for draw_anim_frame subroutine
first_sprite_index = tmpfield5 ; Not movable - Used as parameter for draw_anim_frame subroutine
last_sprite_index = tmpfield6  ; Not movable - Used as parameter for draw_anim_frame subroutine

.(
ldx #$00

player_animation:
ldy #$00
lda #$00
sta tmpfield1

; Store current player's animation information to a player independent location
jsr store_player_anim_parameters

; New frame (search for the frame on time with clock)
new_frame:
lda (animation_vector), y ; Load frame duration
beq loop_animation ; Frame of duration 0 means end of animation
clc           ;
adc tmpfield1 ; Store current frame clock end in tmpfield1
sta tmpfield1 ;

; If the current frame ends after the clock time, draw it
lda player_a_anim_clock, x
cmp tmpfield1
bcc draw_current_frame

; Search the next frame
lda #$01
jsr add_to_anim_vector
skip_sprite:
lda (animation_vector), y ; Check current sprite continuation byte
beq end_skip_frame        ;
sta tmpfield8  ;
lda #$05       ;
sta tmpfield7  ; Set data length in tmpfield7
lda #%00001000 ; hitbox data is 15 bytes long
bit tmpfield8  ; other data are 5 bytes long
beq inc_cursor ; (counting the continuation byte)
lda #15        ;
sta tmpfield7  ;
inc_cursor:
lda tmpfield7          ; Add data length to the animation vector, to point
jsr add_to_anim_vector ; on the next continuation byte
jmp skip_sprite
end_skip_frame:
lda #$01               ; Skip the last continuation byte
jsr add_to_anim_vector ;
jmp new_frame

draw_current_frame:
; Animation location is player's location
lda player_a_x, x
sta tmpfield1
lda player_a_y, x
sta tmpfield2

; Increment animation_vector to skip the frame duration field
lda #$01
jsr add_to_anim_vector

txa
pha
jsr draw_anim_frame
pla
tax

tick_clock:
inc player_a_anim_clock, x
jmp next_player

loop_animation:
lda #$00
sta player_a_anim_clock, x

next_player:
inx
cpx #$02
bne player_animation

;jsr show_hitboxes

rts
.)

store_player_anim_parameters:
.(
cpx #$00
bne select_anim_player_b
lda player_a_animation
sta animation_vector
lda player_a_animation+1
sta animation_vector+1
lda #$00
sta first_sprite_index
lda #$07
sta last_sprite_index
jmp end
select_anim_player_b:
lda player_b_animation
sta animation_vector
lda player_b_animation+1
sta animation_vector+1
lda #$08
sta first_sprite_index
lda #$0f
sta last_sprite_index
end:
rts
.)

add_to_anim_vector:
.(
clc
adc animation_vector
sta animation_vector
lda #$00
adc animation_vector+1
sta animation_vector+1
rts
.)

.)

; Draw an animation frame on screen
;  tmpfield1 - Position X
;  tmpfield2 - Position Y
;  tmpfield3, tmpfield4 - Vector pointing to the frame to draw
;  tmpfield5 - First sprite index to use
;  tmpfield6 - Last sprite index to use
;  X register - player number
;
; Overwrites tmpfield5, tmpfield7, tmpfield8, tmpfield9, tmpfield10 and all registers
draw_anim_frame:
.(
; Pretty names
anim_pos_x = tmpfield1
anim_pos_y = tmpfield2
frame_vector = tmpfield3
sprite_index = tmpfield5
last_sprite_index = tmpfield6
player_number = tmpfield7
sprite_orig_x = tmpfield8
sprite_orig_y = tmpfield9
continuation_byte = tmpfield10
got_hitbox = tmpfield11

.(
ldy #$00
stx player_number
lda #$00
sta got_hitbox

; Check continuation byte - zero value means end of data
draw_one_sprite:
lda (frame_vector), y
beq clear_unused_sprites
iny

; Check positioning mode from continuation byte
sta continuation_byte
lda #%00000010
bit continuation_byte
beq set_relative
lda #$00
sta sprite_orig_x
sta sprite_orig_y
jmp check_hurtbox
set_relative:
lda anim_pos_x
sta sprite_orig_x
lda anim_pos_y
sta sprite_orig_y

; Check if next data is hurtbox position, hitbox definition or sprite data from continuation byte
check_hurtbox:
lda #%00000100
bit continuation_byte
beq check_hitbox
jsr anim_frame_move_hurtbox
jmp draw_one_sprite

check_hitbox:
lda #%00001000
bit continuation_byte
beq move_sprite
jsr anim_frame_move_hitbox
lda #$01
sta got_hitbox
jmp draw_one_sprite

move_sprite:
jsr anim_frame_move_sprite
jmp draw_one_sprite

; Place unused sprites off screen
clear_unused_sprites:
lda last_sprite_index
cmp sprite_index
bcc clear_unused_hitbox

lda sprite_index ;
asl              ; Set X to the byte offset of the sprite in OAM memory
asl              ;
tax              ;

lda #$fe
sta oam_mirror, x
inx
sta oam_mirror, x
inx
sta oam_mirror, x
inx
sta oam_mirror, x

inc sprite_index
jmp clear_unused_sprites

; Deactivate the hitbox if it was not placed by this frame
clear_unused_hitbox:
lda got_hitbox
cmp #$01
beq end
ldx player_number
sta player_a_hitbox_enabled, x

end:
rts
.)

anim_frame_move_sprite:
.(
; Copy sprite data
lda sprite_index
asl
asl
tax
; Y value, must be relative to animation Y position
lda (frame_vector), y
clc
adc sprite_orig_y
sta oam_mirror, x
inx
iny
; Tile number
lda (frame_vector), y
sta oam_mirror, x
inx
iny
; Attributes (add "2 * player_num" to select 3rd and 4th palette for player B)
lda player_number
asl
clc
adc (frame_vector), y
sta oam_mirror, x
inx
iny
; X value, must be relative to animation X position
lda (frame_vector), y
clc
adc sprite_orig_x
sta oam_mirror, x
iny

; Next sprite
inc sprite_index

rts
.)

anim_frame_move_hurtbox:
.(
; Left
ldx player_number
lda (frame_vector), y
clc
adc sprite_orig_x
sta player_a_hurtbox_left, x
iny
; Right
lda (frame_vector), y
clc
adc sprite_orig_x
sta player_a_hurtbox_right, x
iny
; Top
lda (frame_vector), y
clc
adc sprite_orig_y
sta player_a_hurtbox_top, x
iny
; Top
lda (frame_vector), y
clc
adc sprite_orig_y
sta player_a_hurtbox_bottom, x
iny

rts
.)

anim_frame_move_hitbox:
.(
ldx player_number
; Enabled
lda (frame_vector), y
ora player_a_hitbox_enabled, x
sta player_a_hitbox_enabled, x
iny
; Damages
lda (frame_vector), y
sta player_a_hitbox_damages, x
iny
; Base_h
lda (frame_vector), y
sta player_a_hitbox_base_knock_up_h_high, x
iny
lda (frame_vector), y
sta player_a_hitbox_base_knock_up_h_low, x
iny
; Base_v
lda (frame_vector), y
sta player_a_hitbox_base_knock_up_v_high, x
iny
lda (frame_vector), y
sta player_a_hitbox_base_knock_up_v_low, x
iny
; Force_h
lda (frame_vector), y
sta player_a_hitbox_force_h, x
iny
lda (frame_vector), y
sta player_a_hitbox_force_h_low, x
iny
; Force_v
lda (frame_vector), y
sta player_a_hitbox_force_v, x
iny
lda (frame_vector), y
sta player_a_hitbox_force_v_low, x
iny
; Left
ldx player_number
lda (frame_vector), y
clc
adc sprite_orig_x
sta player_a_hitbox_left, x
iny
; Right
lda (frame_vector), y
clc
adc sprite_orig_x
sta player_a_hitbox_right, x
iny
; Top
lda (frame_vector), y
clc
adc sprite_orig_y
sta player_a_hitbox_top, x
iny
; Top
lda (frame_vector), y
clc
adc sprite_orig_y
sta player_a_hitbox_bottom, x
iny

rts
.)

.)

; Debug subroutine to show hitboxes and hurtboxes
show_hitboxes:
.(
pha
txa
pha
tya
pha

; Player A hurtbox
ldx #$fc
lda player_a_hurtbox_top
sta oam_mirror, x
inx
lda #$0d
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_a_hurtbox_left
sta oam_mirror, x
inx
ldx #$f8
lda player_a_hurtbox_bottom
sec
sbc #$08
sta oam_mirror, x
inx
lda #$0d
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_a_hurtbox_right
sec
sbc #$08
sta oam_mirror, x
inx

; Player B hurtbox
ldx #$f4
lda player_b_hurtbox_top
sta oam_mirror, x
inx
lda #$0d
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_b_hurtbox_left
sta oam_mirror, x
inx
ldx #$f0
lda player_b_hurtbox_bottom
sec
sbc #$08
sta oam_mirror, x
inx
lda #$0d
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_b_hurtbox_right
sec
sbc #$08
sta oam_mirror, x
inx

; Player A hitbox
lda player_a_hitbox_enabled
bne show_player_a_hitbox
lda #$fe  ;
sta $02e8 ;
sta $02e9 ;
sta $02ea ;
sta $02eb ; Hide disabled hitbox
sta $02ec ;
sta $02ed ;
sta $02ee ;
sta $02ef ;
jmp end_player_a_hitbox
show_player_a_hitbox:
ldx #$ec
lda player_a_hitbox_top
sta oam_mirror, x
inx
lda #$0e
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_a_hitbox_left
sta oam_mirror, x
inx
ldx #$e8
lda player_a_hitbox_bottom
sec
sbc #$08
sta oam_mirror, x
inx
lda #$0e
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_a_hitbox_right
sec
sbc #$08
sta oam_mirror, x
inx
end_player_a_hitbox

; Player B hitbox
lda player_b_hitbox_enabled
bne show_player_b_hitbox
lda #$fe  ;
sta $02e0 ;
sta $02e1 ;
sta $02e2 ;
sta $02e3 ; Hide disabled hitbox
sta $02e4 ;
sta $02e5 ;
sta $02e6 ;
sta $02e7 ;
jmp end_player_b_hitbox
show_player_b_hitbox:
ldx #$e4
lda player_b_hitbox_top
sta oam_mirror, x
inx
lda #$0e
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_b_hitbox_left
sta oam_mirror, x
inx
ldx #$e8
lda player_b_hitbox_bottom
sec
sbc #$08
sta oam_mirror, x
inx
lda #$0e
sta oam_mirror, x
inx
lda #$03
sta oam_mirror, x
inx
lda player_b_hitbox_right
sec
sbc #$08
sta oam_mirror, x
inx
end_player_b_hitbox

pla
tay
pla
tax
pla
rts
.)

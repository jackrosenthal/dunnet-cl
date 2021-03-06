;;; dunnet.lisp -- a port of dunnet.el to Common Lisp

;; Copyright (C) 1992-1993, 2001-2018 Free Software Foundation, Inc.
;; Copyright (C) 2019 Jack Rosenthal

;; Author: Ron Schnell <ronnie@driver-aces.com>
;; Created: 25 Jul 1992
;; Version: 2.02
;; Keywords: games

;; This file was part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;;;
;;;; This section defines the globals that are used in dunnet.
;;;;
;;;; IMPORTANT
;;;; All globals which can change must be saved from 'save-game.  Add
;;;; all new globals to bottom of this section.

#+sbcl (declaim (sb-ext:muffle-conditions style-warning))

(defmacro while (pred &rest body)
  `(loop while ,pred
      do ,@body))

(defmacro match (valform &rest clauses)
  (labels ((expand-match-clauses (valsym clauses)
             (if (not clauses)
                 '#'(lambda () nil)
                 (destructuring-bind ((lambda-list . body) . rest) clauses
                   (cond
                     ((null lambda-list)
                      `(if (null ,valsym)
                           #'(lambda () ,@body)
                           ,(expand-match-clauses valsym rest)))
                     ((symbolp lambda-list)
                      `(let ((,lambda-list ,valsym))
                         #'(lambda () ,@body)))
                     ((consp lambda-list)
                      `(handler-case
                           (destructuring-bind ,lambda-list ,valsym
                             #'(lambda () ,@body))
                         (condition ()
                           ,(expand-match-clauses valsym rest)))))))))
    (let ((valsym (gensym "val-")))
      `(let ((,valsym ,valform))
         (funcall ,(expand-match-clauses valsym clauses))))))

;; based on SO post: 15393797
(defun split-string (str delimiters)
  (labels ((delim-p (char)
             (member char delimiters)))
    (loop for start = (position-if-not #'delim-p str)
       then (position-if-not #'delim-p str :start (1+ end))
       for end = (and start (position-if #'delim-p str :start start))
       when start
       collect (subseq str start end)
       while end)))

(defvar dun-visited '(27))
(defvar dun-current-room 1)
(defvar dun-exitf nil)
(defvar dun-badcd nil)
(defvar dun-computer nil)
(defvar dun-floppy nil)
(defvar dun-key-level 0)
(defvar dun-hole nil)
(defvar dun-correct-answer nil)
(defvar dun-lastdir 0)
(defvar dun-numsaves 0)
(defvar dun-jar nil)
(defvar dun-dead nil)
(defvar dun-room 0)
(defvar dun-numcmds 0)
(defvar dun-wizard nil)
(defvar dun-endgame-question nil)
(defvar dun-logged-in nil)
(defvar dungeon-mode 'dungeon)

(defconstant dun-unix-verbs
  '((ls . dun-ls) (ftp . dun-ftp) ;; (echo . dun-echo)
    (exit . dun-uexit) (cd . dun-cd) (pwd . dun-pwd)
    (rlogin . dun-rlogin) (ssh . dun-rlogin)
    (uncompress . dun-uncompress) (cat . dun-cat)))

(defconstant dun-ftp-verbs
  '((type . dun-ftptype) (binary . dun-bin) (bin . dun-bin)
    (send . dun-send) (put . dun-send) (quit . dun-ftpquit)
    (help . dun-ftphelp) (ascii . dun-fascii)))

(defconstant dun-dos-verbs
  '((dir . dun-dos-dir) (type . dun-dos-type)
    (exit . dun-dos-exit) (command . dun-dos-spawn)
    (|B:| . dun-dos-invd) (|C:| . dun-dos-invd)
    (|A:| . dun-dos-nil)))

(defvar dun-cdpath "/usr/toukmond")
(defvar dun-cdroom -10)
(defvar dun-uncompressed nil)
(defvar dun-ethernet t)
(defconstant dun-restricted
  '(dun-room-objects
    dungeon-map dun-rooms
    dun-room-silents
    dun-combination))
(defvar dun-ftptype 'ascii)
(defvar dun-endgame nil)
(defvar dun-gottago t)
(defvar dun-black nil)

(defconstant dun-rooms
  '(
    (
     "You are in the treasure room.  A door leads out to the north."
     "Treasure room"
     )
    (
     "You are at a dead end of a dirt road.  The road goes to the east.
In the distance you can see that it will eventually fork off.  The
trees here are very tall royal palms, and they are spaced equidistant
from each other."
     "Dead end"
     )
    (
     "You are on the continuation of a dirt road.  There are more trees on
both sides of you.  The road continues to the east and west."
     "E/W Dirt road"
     )
    (
     "You are at a fork of two passages, one to the northeast, and one to the
southeast.  The ground here seems very soft. You can also go back west."
     "Fork"
     )
    (
     "You are on a northeast/southwest road."
     "NE/SW road"
     )
    (
     "You are at the end of the road.  There is a building in front of you
to the northeast, and the road leads back to the southwest."
     "Building front"
     )
    (
     "You are on a southeast/northwest road."
     "SE/NW road"
     )
    (
     "You are standing at the end of a road.  A passage leads back to the
northwest."
     "Bear hangout"
     )
    (
     "You are in the hallway of an old building.  There are rooms to the east
and west, and doors leading out to the north and south."
     "Old Building hallway"
     )
    (
     "You are in a mailroom.  There are many bins where the mail is usually
kept.  The exit is to the west."
     "Mailroom"
     )
    (
     "You are in a computer room.  It seems like most of the equipment has
been removed.  There is a VAX 11/780 in front of you, however, with
one of the cabinets wide open.  A sign on the front of the machine
says: This VAX is named 'pokey'.  To type on the console, use the
'type' command.  The exit is to the east."
     "Computer room"
     )
    (
     "You are in a meadow in the back of an old building.  A small path leads
to the west, and a door leads to the south."
     "Meadow"
     )
    (
     "You are in a round, stone room with a door to the east.  There
is a sign on the wall that reads: 'receiving room'."
     "Receiving room"
     )
    (
     "You are at the south end of a hallway that leads to the north.  There
are rooms to the east and west."
     "Northbound Hallway"
     )
    (
     "You are in a sauna.  There is nothing in the room except for a dial
on the wall.  A door leads out to west."
     "Sauna"
     )
    (
     "You are at the end of a north/south hallway.  You can go back to the south,
or off to a room to the east."
     "End of N/S Hallway"
     )
    (
     "You are in an old weight room.  All of the equipment is either destroyed
or completely broken.  There is a door out to the west, and there is a ladder
leading down a hole in the floor."
     "Weight room"                 ;16
     )
    (
     "You are in a maze of twisty little passages, all alike.
There is a button on the ground here."
     "Maze button room"
     )
    (
     "You are in a maze of little twisty passages, all alike."
     "Maze"
     )
    (
     "You are in a maze of thirsty little passages, all alike."
     "Maze"    ;19
     )
    (
     "You are in a maze of twenty little passages, all alike."
     "Maze"
     )
    (
     "You are in a daze of twisty little passages, all alike."
     "Maze"   ;21
     )
    (
     "You are in a maze of twisty little cabbages, all alike."
     "Maze"   ;22
     )
    (
     "You are in a reception area for a health and fitness center.  The place
appears to have been recently ransacked, and nothing is left.  There is
a door out to the south, and a crawlspace to the southeast."
     "Reception area"
     )
    (
     "You are outside a large building to the north which used to be a health
and fitness center.  A road leads to the south."
     "Health Club front"
     )
    (
     "You are at the north side of a lake.  On the other side you can see
a road which leads to a cave.  The water appears very deep."
     "Lakefront North"
     )
    (
     "You are at the south side of a lake.  A road goes to the south."
     "Lakefront South"
     )
    (
     "You are in a well-hidden area off to the side of a road.  Back to the
northeast through the brush you can see the bear hangout."
     "Hidden area"
     )
    (
     "The entrance to a cave is to the south.  To the north, a road leads
towards a deep lake.  On the ground nearby there is a chute, with a sign
that says 'put treasures here for points'."
     "Cave Entrance"                      ;28
     )
    (
     "You are in a misty, humid room carved into a mountain.
To the north is the remains of a rockslide.  To the east, a small
passage leads away into the darkness."              ;29
     "Misty Room"
     )
    (
     "You are in an east/west passageway.  The walls here are made of
multicolored rock and are quite beautiful."
     "Cave E/W passage"                   ;30
     )
    (
     "You are at the junction of two passages. One goes north/south, and
the other goes west."
     "N/S/W Junction"                     ;31
     )
    (
     "You are at the north end of a north/south passageway.  There are stairs
leading down from here.  There is also a door leading west."
     "North end of cave passage"         ;32
     )
    (
     "You are at the south end of a north/south passageway.  There is a hole
in the floor here, into which you could probably fit."
     "South end of cave passage"         ;33
     )
    (
     "You are in what appears to be a worker's bedroom.  There is a queen-
sized bed in the middle of the room, and a painting hanging on the
wall.  A door leads to another room to the south, and stairways
lead up and down."
     "Bedroom"                          ;34
     )
    (
     "You are in a bathroom built for workers in the cave.  There is a
urinal hanging on the wall, and some exposed pipes on the opposite
wall where a sink used to be.  To the north is a bedroom."
     "Bathroom"        ;35
     )
    (
     "This is a marker for the urinal.  User will not see this, but it
is a room that can contain objects."
     "Urinal"          ;36
     )
    (
     "You are at the northeast end of a northeast/southwest passageway.
Stairs lead up out of sight."
     "NE end of NE/SW cave passage"       ;37
     )
    (
     "You are at the junction of northeast/southwest and east/west passages."
     "NE/SW-E/W junction"                      ;38
     )
    (
     "You are at the southwest end of a northeast/southwest passageway."
     "SW end of NE/SW cave passage"        ;39
     )
    (
     "You are at the east end of an E/W passage.  There are stairs leading up
to a room above."
     "East end of E/W cave passage"    ;40
     )
    (
     "You are at the west end of an E/W passage.  There is a hole on the ground
which leads down out of sight."
     "West end of E/W cave passage"    ;41
     )
    (
     "You are in a room which is bare, except for a horseshoe shaped boulder
in the center.  Stairs lead down from here."     ;42
     "Horseshoe boulder room"
     )
    (
     "You are in a room which is completely empty.  Doors lead out to the north
and east."
     "Empty room"                      ;43
     )
    (
     "You are in an empty room.  Interestingly enough, the stones in this
room are painted blue.  Doors lead out to the east and south."  ;44
     "Blue room"
     )
    (
     "You are in an empty room.  Interestingly enough, the stones in this
room are painted yellow.  Doors lead out to the south and west."    ;45
     "Yellow room"
     )
    (
     "You are in an empty room.  Interestingly enough, the stones in this room
are painted red.  Doors lead out to the west and north."
     "Red room"                                 ;46
     )
    (
     "You are in the middle of a long north/south hallway."     ;47
     "Long n/s hallway"
     )
    (
     "You are 3/4 of the way towards the north end of a long north/south hallway."
     "3/4 north"                                ;48
     )
    (
     "You are at the north end of a long north/south hallway.  There are stairs
leading upwards."
     "North end of long hallway"                 ;49
     )
    (
     "You are 3/4 of the way towards the south end of a long north/south hallway."
     "3/4 south"                                 ;50
     )
    (
     "You are at the south end of a long north/south hallway.  There is a hole
to the south."
     "South end of long hallway"                 ;51
     )
    (
     "You are at a landing in a stairwell which continues up and down."
     "Stair landing"                             ;52
     )
    (
     "You are at the continuation of an up/down staircase."
     "Up/down staircase"                         ;53
     )
    (
     "You are at the top of a staircase leading down.  A crawlway leads off
to the northeast."
     "Top of staircase."                        ;54
     )
    (
     "You are in a crawlway that leads northeast or southwest."
     "NE crawlway"                              ;55
     )
    (
     "You are in a small crawlspace.  There is a hole in the ground here, and
a small passage back to the southwest."
     "Small crawlspace"                         ;56
     )
    (
     "You are in the Gamma Computing Center.  An IBM 3090/600s is whirring
away in here.  There is an ethernet cable coming out of one of the units,
and going through the ceiling.  There is no console here on which you
could type."
     "Gamma computing center"                   ;57
     )
    (
     "You are near the remains of a post office.  There is a mail drop on the
face of the building, but you cannot see where it leads.  A path leads
back to the east, and a road leads to the north."
     "Post office"                             ;58
     )
    (
     "You are at the intersection of Main Street and Maple Ave.  Main street
runs north and south, and Maple Ave runs east off into the distance.
If you look north and east you can see many intersections, but all of
the buildings that used to stand here are gone.  Nothing remains except
street signs.
There is a road to the northwest leading to a gate that guards a building."
     "Main-Maple intersection"                       ;59
     )
    (
     "You are at the intersection of Main Street and the west end of Oaktree Ave."
     "Main-Oaktree intersection"   ;60
     )
    (
     "You are at the intersection of Main Street and the west end of Vermont Ave."
     "Main-Vermont intersection"  ;61
     )
    (
     "You are at the north end of Main Street at the west end of Sycamore Ave." ;62
     "Main-Sycamore intersection"
     )
    (
     "You are at the south end of First Street at Maple Ave." ;63
     "First-Maple intersection"
     )
    (
     "You are at the intersection of First Street and Oaktree Ave."  ;64
     "First-Oaktree intersection"
     )
    (
     "You are at the intersection of First Street and Vermont Ave."  ;65
     "First-Vermont intersection"
     )
    (
     "You are at the north end of First Street at Sycamore Ave."  ;66
     "First-Sycamore intersection"
     )
    (
     "You are at the south end of Second Street at Maple Ave."  ;67
     "Second-Maple intersection"
     )
    (
     "You are at the intersection of Second Street and Oaktree Ave."  ;68
     "Second-Oaktree intersection"
     )
    (
     "You are at the intersection of Second Street and Vermont Ave."  ;69
     "Second-Vermont intersection"
     )
    (
     "You are at the north end of Second Street at Sycamore Ave."  ;70
     "Second-Sycamore intersection"
     )
    (
     "You are at the south end of Third Street at Maple Ave."  ;71
     "Third-Maple intersection"
     )
    (
     "You are at the intersection of Third Street and Oaktree Ave."  ;72
     "Third-Oaktree intersection"
     )
    (
     "You are at the intersection of Third Street and Vermont Ave."  ;73
     "Third-Vermont intersection"
     )
    (
     "You are at the north end of Third Street at Sycamore Ave."  ;74
     "Third-Sycamore intersection"
     )
    (
     "You are at the south end of Fourth Street at Maple Ave."  ;75
     "Fourth-Maple intersection"
     )
    (
     "You are at the intersection of Fourth Street and Oaktree Ave."  ;76
     "Fourth-Oaktree intersection"
     )
    (
     "You are at the intersection of Fourth Street and Vermont Ave."  ;77
     "Fourth-Vermont intersection"
     )
    (
     "You are at the north end of Fourth Street at Sycamore Ave."  ;78
     "Fourth-Sycamore intersection"
     )
    (
     "You are at the south end of Fifth Street at the east end of Maple Ave."  ;79
     "Fifth-Maple intersection"
     )
    (
     "You are at the intersection of Fifth Street and the east end of Oaktree Ave.
There is a cliff off to the east."
     "Fifth-Oaktree intersection"  ;80
     )
    (
     "You are at the intersection of Fifth Street and the east end of Vermont Ave."
     "Fifth-Vermont intersection"  ;81
     )
    (
     "You are at the north end of Fifth Street and the east end of Sycamore Ave."
     "Fifth-Sycamore intersection"  ;82
     )
    (
     "You are in front of the Museum of Natural History.  A door leads into
the building to the north, and a road leads to the southeast."
     "Museum entrance"                  ;83
     )
    (
     "You are in the main lobby for the Museum of Natural History.  In the center
of the room is the huge skeleton of a dinosaur.  Doors lead out to the
south and east."
     "Museum lobby"                     ;84
     )
    (
     "You are in the geological display.  All of the objects that used to
be on display are missing.  There are rooms to the east, west, and
north."
     "Geological display"               ;85
     )
    (
     "You are in the marine life area.  The room is filled with fish tanks,
which are filled with dead fish that have apparently died due to
starvation.  Doors lead out to the south and east."
     "Marine life area"                   ;86
     )
    (
     "You are in some sort of maintenance room for the museum.  There is a
switch on the wall labeled 'BL'.  There are doors to the west and north."
     "Maintenance room"                   ;87
     )
    (
     "You are in a classroom where school children were taught about natural
history.  On the blackboard is written, 'No children allowed downstairs.'
There is a door to the east with an 'exit' sign on it.  There is another
door to the west."
     "Classroom"                          ;88
     )
    (
     "You are at the Vermont St. subway station.  A train is sitting here waiting."
     "Vermont station"                    ;89
     )
    (
     "You are at the Museum subway stop.  A passage leads off to the north."
     "Museum station"                     ;90
     )
    (
     "You are in a north/south tunnel."
     "N/S tunnel"                          ;91
     )
    (
     "You are at the north end of a north/south tunnel.  Stairs lead up and
down from here.  There is a garbage disposal here."
     "North end of N/S tunnel"             ;92
     )
    (
     "You are at the top of some stairs near the subway station.  There is
a door to the west."
     "Top of subway stairs"           ;93
     )
    (
     "You are at the bottom of some stairs near the subway station.  There is
a room to the northeast."
     "Bottom of subway stairs"       ;94
     )
    (
     "You are in another computer room.  There is a computer in here larger
than you have ever seen.  It has no manufacturers name on it, but it
does have a sign that says: This machine's name is 'endgame'.  The
exit is to the southwest.  There is no console here on which you could
type."
     "Endgame computer room"         ;95
     )
    (
     "You are in a north/south hallway."
     "Endgame N/S hallway"           ;96
     )
    (
     "You have reached a question room.  You must answer a question correctly in
order to get by.  Use the 'answer' command to answer the question."
     "Question room 1"              ;97
     )
    (
     "You are in a north/south hallway."
     "Endgame N/S hallway"           ;98
     )
    (
     "You are in a second question room."
     "Question room 2"               ;99
     )
    (
     "You are in a north/south hallway."
     "Endgame N/S hallway"           ;100
     )
    (
     "You are in a third question room."
     "Question room 3"               ;101
     )
    (
     "You are in the endgame treasure room.  A door leads out to the north, and
a hallway leads to the south."
     "Endgame treasure room"         ;102
     )
    (
     "You are in the winner's room.  A door leads back to the south."
     "Winner's room"                 ;103
     )
    (
     "You have reached a dead end.  There is a PC on the floor here.  Above
it is a sign that reads:
          Type the 'reset' command to type on the PC.
A hole leads north."
     "PC area"                       ;104
     )
    ))

(defconstant dun-light-rooms
  '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 24 25 26 27 28 58 59
      60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76
      77 78 79 80 81 82 83))

(defconstant dun-verblist
  '((die . dun-die) (ne . dun-ne) (north . dun-n)
    (south . dun-s) (east . dun-e) (west . dun-w)
    (u . dun-up) (d . dun-down) (i . dun-inven)
    (inventory . dun-inven) (look . dun-examine) (n . dun-n)
    (s . dun-s) (e . dun-e) (w . dun-w) (se . dun-se)
    (nw . dun-nw) (sw . dun-sw) (up . dun-up)
    (down . dun-down) (in . dun-in) (out . dun-out)
    (go . dun-go) (drop . dun-drop) (southeast . dun-se)
    (southwest . dun-sw) (northeast . dun-ne)
    (northwest . dun-nw)
    ;; (save . dun-save-game)
    ;; (restore . dun-restore)
    (long . dun-long) (dig . dun-dig)
    (shake . dun-shake) (wave . dun-shake)
    (examine . dun-examine) (describe . dun-examine)
    (climb . dun-climb) (eat . dun-eat) (put . dun-put)
    (type . dun-type)  (insert . dun-put)
    (score . dun-score) (help . dun-help) (quit . dun-quit)
    (read . dun-examine) (verbose . dun-long)
    (urinate . dun-piss) (piss . dun-piss)
    (flush . dun-flush) (sleep . dun-sleep) (lie . dun-sleep)
    (x . dun-examine) (break . dun-break) (drive . dun-drive)
    (board . dun-in) (enter . dun-in) (turn . dun-turn)
    (press . dun-press) (push . dun-press) (swim . dun-swim)
    (on . dun-in) (off . dun-out) (chop . dun-break)
    (switch . dun-press) (cut . dun-break) (exit . dun-out)
    (leave . dun-out) (reset . dun-power) (flick . dun-press)
    (superb . dun-superb) (answer . dun-answer)
    (throw . dun-drop) (l . dun-examine) (take . dun-take)
    (get . dun-take) (feed . dun-feed)))

(defvar dun-inbus nil)
(defvar dun-nomail nil)
(defconstant ignored-words '(the to at))
(defvar dun-mode 'moby)
(defvar dun-sauna-level 0)

(defconstant dun-movement-alist
  '((north . 0)
    (south . 1)
    (east . 2)
    (west . 3)
    (northeast . 4)
    (southeast . 5)
    (northwest . 6)
    (southwest . 7)
    (up . 8)
    (down . 9)
    (in . 10)
    (out . 11))
  "Alist enumerating movement directions.")

(defconstant dungeon-map
  ;;  no  so  ea  we  ne  se  nw  sw  up  do  in  ot
  '(( 96  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;0
    ( -1  -1   2  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;1
    ( -1  -1   3   1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;2
    ( -1  -1  -1   2   4   6  -1  -1  -1  -1  -1  -1 ) ;3
    ( -1  -1  -1  -1   5  -1  -1   3  -1  -1  -1  -1 ) ;4
    ( -1  -1  -1  -1  255 -1  -1   4  -1  -1  255 -1 ) ;5
    ( -1  -1  -1  -1  -1   7   3  -1  -1  -1  -1  -1 ) ;6
    ( -1  -1  -1  -1  -1  255  6  27  -1  -1  -1  -1 ) ;7
    ( 255  5   9  10  -1  -1  -1   5  -1  -1  -1   5 ) ;8
    ( -1  -1  -1   8  -1  -1  -1  -1  -1  -1  -1  -1 ) ;9
    ( -1  -1   8  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;10
    ( -1   8  -1  58  -1  -1  -1  -1  -1  -1  -1  -1 ) ;11
    ( -1  -1  13  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;12
    ( 15  -1  14  12  -1  -1  -1  -1  -1  -1  -1  -1 ) ;13
    ( -1  -1  -1  13  -1  -1  -1  -1  -1  -1  -1  -1 ) ;14
    ( -1  13  16  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;15
    ( -1  -1  -1  15  -1  -1  -1  -1  -1  17  16  -1 ) ;16
    ( -1  -1  17  17  17  17 255  17 255  17  -1  -1 ) ;17
    ( 18  18  18  18  18  -1  18  18  19  18  -1  -1 ) ;18
    ( -1  18  18  19  19  20  19  19  -1  18  -1  -1 ) ;19
    ( -1  -1  -1  18  -1  -1  -1  -1  -1  21  -1  -1 ) ;20
    ( -1  -1  -1  -1  -1  20  22  -1  -1  -1  -1  -1 ) ;21
    ( 18  18  18  18  16  18  23  18  18  18  18  18 ) ;22
    ( -1 255  -1  -1  -1  19  -1  -1  -1  -1  -1  -1 ) ;23
    ( 23  25  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;24
    ( 24 255  -1  -1  -1  -1  -1  -1  -1  -1 255  -1 ) ;25
    (255  28  -1  -1  -1  -1  -1  -1  -1  -1 255  -1 ) ;26
    ( -1  -1  -1  -1   7  -1  -1  -1  -1  -1  -1  -1 ) ;27
    ( 26 255  -1  -1  -1  -1  -1  -1  -1  -1  255 -1 ) ;28
    ( -1  -1  30  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;29
    ( -1  -1  31  29  -1  -1  -1  -1  -1  -1  -1  -1 ) ;30
    ( 32  33  -1  30  -1  -1  -1  -1  -1  -1  -1  -1 ) ;31
    ( -1  31  -1  255 -1  -1  -1  -1  -1  34  -1  -1 ) ;32
    ( 31  -1  -1  -1  -1  -1  -1  -1  -1  35  -1  -1 ) ;33
    ( -1  35  -1  -1  -1  -1  -1  -1  32  37  -1  -1 ) ;34
    ( 34  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;35
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;36
    ( -1  -1  -1  -1  -1  -1  -1  38  34  -1  -1  -1 ) ;37
    ( -1  -1  40  41  37  -1  -1  39  -1  -1  -1  -1 ) ;38
    ( -1  -1  -1  -1  38  -1  -1  -1  -1  -1  -1  -1 ) ;39
    ( -1  -1  -1  38  -1  -1  -1  -1  42  -1  -1  -1 ) ;40
    ( -1  -1  38  -1  -1  -1  -1  -1  -1  43  -1  -1 ) ;41
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  40  -1  -1 ) ;42
    ( 44  -1  46  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;43
    ( -1  43  45  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;44
    ( -1  46  -1  44  -1  -1  -1  -1  -1  -1  -1  -1 ) ;45
    ( 45  -1  -1  43  -1  -1  -1  -1  -1  255 -1  -1 ) ;46
    ( 48  50  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;47
    ( 49  47  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;48
    ( -1  48  -1  -1  -1  -1  -1  -1  52  -1  -1  -1 ) ;49
    ( 47  51  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;50
    ( 50  104 -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;51
    ( -1  -1  -1  -1  -1  -1  -1  -1  53  49  -1  -1 ) ;52
    ( -1  -1  -1  -1  -1  -1  -1  -1  54  52  -1  -1 ) ;53
    ( -1  -1  -1  -1  55  -1  -1  -1  -1  53  -1  -1 ) ;54
    ( -1  -1  -1  -1  56  -1  -1  54  -1  -1  -1  54 ) ;55
    ( -1  -1  -1  -1  -1  -1  -1  55  -1  31  -1  -1 ) ;56
    ( -1  -1  32  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;57
    ( 59  -1  11  -1  -1  -1  -1  -1  -1  -1  255 255) ;58
    ( 60  58  63  -1  -1  -1  255 -1  -1  -1  255 255) ;59
    ( 61  59  64  -1  -1  -1  -1  -1  -1  -1  255 255) ;60
    ( 62  60  65  -1  -1  -1  -1  -1  -1  -1  255 255) ;61
    ( -1  61  66  -1  -1  -1  -1  -1  -1  -1  255 255) ;62
    ( 64  -1  67  59  -1  -1  -1  -1  -1  -1  255 255) ;63
    ( 65  63  68  60  -1  -1  -1  -1  -1  -1  255 255) ;64
    ( 66  64  69  61  -1  -1  -1  -1  -1  -1  255 255) ;65
    ( -1  65  70  62  -1  -1  -1  -1  -1  -1  255 255) ;66
    ( 68  -1  71  63  -1  -1  -1  -1  -1  -1  255 255) ;67
    ( 69  67  72  64  -1  -1  -1  -1  -1  -1  255 255) ;68
    ( 70  68  73  65  -1  -1  -1  -1  -1  -1  255 255) ;69
    ( -1  69  74  66  -1  -1  -1  -1  -1  -1  255 255) ;70
    ( 72  -1  75  67  -1  -1  -1  -1  -1  -1  255 255) ;71
    ( 73  71  76  68  -1  -1  -1  -1  -1  -1  255 255) ;72
    ( 74  72  77  69  -1  -1  -1  -1  -1  -1  255 255) ;73
    ( -1  73  78  70  -1  -1  -1  -1  -1  -1  255 255) ;74
    ( 76  -1  79  71  -1  -1  -1  -1  -1  -1  255 255) ;75
    ( 77  75  80  72  -1  -1  -1  -1  -1  -1  255 255) ;76
    ( 78  76  81  73  -1  -1  -1  -1  -1  -1  255 255) ;77
    ( -1  77  82  74  -1  -1  -1  -1  -1  -1  255 255) ;78
    ( 80  -1  -1  75  -1  -1  -1  -1  -1  -1  255 255) ;79
    ( 81  79  255 76  -1  -1  -1  -1  -1  -1  255 255) ;80
    ( 82  80  -1  77  -1  -1  -1  -1  -1  -1  255 255) ;81
    ( -1  81  -1  78  -1  -1  -1  -1  -1  -1  255 255) ;82
    ( 84  -1  -1  -1  -1  59  -1  -1  -1  -1  255 255) ;83
    ( -1  83  85  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;84
    ( 86  -1  87  84  -1  -1  -1  -1  -1  -1  -1  -1 ) ;85
    ( -1  85  88  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;86
    ( 88  -1  -1  85  -1  -1  -1  -1  -1  -1  -1  -1 ) ;87
    ( -1  87 255  86  -1  -1  -1  -1  -1  -1  -1  -1 ) ;88
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 255  -1 ) ;89
    ( 91  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;90
    ( 92  90  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;91
    ( -1  91  -1  -1  -1  -1  -1  -1  93  94  -1  -1 ) ;92
    ( -1  -1  -1  88  -1  -1  -1  -1  -1  92  -1  -1 ) ;93
    ( -1  -1  -1  -1  95  -1  -1  -1  92  -1  -1  -1 ) ;94
    ( -1  -1  -1  -1  -1  -1  -1  94  -1  -1  -1  -1 ) ;95
    ( 97   0  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;96
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;97
    ( 99  97  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;98
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;99
    ( 101 99  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;100
    ( -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;101
    ( 103 101 -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;102
    ( -1  102 -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ) ;103
    ( 51  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1  -1 ));104
  ;; no  so  ea  we  ne  se  nw  sw  up  do  in  ot
  )

(defmacro dun-set-objnames (&rest objnames)
  `(progn
     ,@(loop for (sym . id) in objnames
          collect
            `(defparameter ,(intern (format nil "OBJ-~A" sym)) ,id))
     (defconstant dun-objnames (quote ,objnames))))

;;; How the user references *all* objects, permanent and regular.
(dun-set-objnames
 (shovel . 0)
 (lamp . 1)
 (cpu . 2) (board . 2) (card . 2) (chip . 2)
 (food . 3)
 (key . 4)
 (paper . 5) (slip . 5)
 (rms . 6) (statue . 6) (statuette . 6)  (stallman . 6)
 (diamond . 7)
 (weight . 8)
 (life . 9) (preserver . 9)
 (bracelet . 10) (emerald . 10)
 (gold . 11)
 (platinum . 12)
 (towel . 13) (beach . 13)
 (axe . 14)
 (silver . 15)
 (license . 16)
 (coins . 17)
 (egg . 18)
 (jar . 19)
 (bone . 20)
 (acid . 21) (nitric . 21)
 (glycerine . 22)
 (ruby . 23)
 (amethyst . 24)
 (mona . 25)
 (bill . 26)
 (floppy . 27) (disk . 27)
 (boulder . -1)
 (tree . -2) (trees . -2) (palm . -2)
 (bear . -3)
 (bin . -4) (bins . -4)
 (cabinet . -5) (computer . -5) (vax . -5) (ibm . -5)
 (protoplasm . -6)
 (dial . -7)
 (button . -8)
 (chute . -9)
 (painting . -10)
 (bed . -11)
 (urinal . -12)
 (URINE . -13)
 (pipes . -14) (pipe . -14)
 (box . -15) (slit . -15)
 (cable . -16) (ethernet . -16)
 (mail . -17) (drop . -17)
 (bus . -18)
 (gate . -19)
 (cliff . -20)
 (skeleton . -21) (dinosaur . -21)
 (fish . -22)
 (tanks . -23) (tank . -23)
 (switch . -24)
 (blackboard . -25)
 (disposal . -26) (garbage . -26)
 (ladder . -27)
 (subway . -28) (train . -28)
 (pc . -29) (drive . -29) (coconut . -30) (coconuts . -30)
 (lake . -32) (water . -32))

(defun obj->num (obj)
  (cdr (assoc obj dun-objnames)))

(defun dun-objnum-from-args-std (args)
  (match args
         (() (format t "You must supply an object.~%"))
         ((obj . rest)
          (let ((objnum (obj->num obj)))
            (if objnum
                objnum
                (format t "I don't know what that is.~%"))))))

(defvar dun-inventory '(1))

(defun obj-in-inventory-p (obj)
  (if (symbolp obj)
      (obj-in-inventory-p (obj->num obj))
      (member obj dun-inventory :test #'eql)))

(defconstant obj-special 255)

;;; The initial setup of what objects are in each room.
;;; Regular objects have whole numbers lower than 255.
;;; Objects that cannot be taken but might move and are
;;; described during room description are negative.
;;; Stuff that is described and might change are 255, and are
;;; handled specially by 'dun-describe-room.

(defvar dun-room-objects
  (list nil
        (list obj-shovel)                     ;; treasure-room
        (list obj-boulder)                    ;; dead-end
        nil nil nil
        (list obj-food)                       ;; se-nw-road
        (list obj-bear)                       ;; bear-hangout
        nil nil
        (list obj-special)                    ;; computer-room
        (list obj-lamp obj-license obj-silver);; meadow
        nil nil
        (list obj-special)                    ;; sauna
        nil
        (list obj-weight obj-life)            ;; weight-room
        nil nil
        (list obj-rms obj-floppy)             ;; thirsty-maze
        nil nil nil nil nil nil nil
        (list obj-emerald)                    ;; hidden-area
        nil
        (list obj-gold)                       ;; misty-room
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        (list obj-towel obj-special)          ;; red-room
        nil nil nil nil nil
        (list obj-box)                        ;; stair-landing
        nil nil nil
        (list obj-axe)                        ;; small-crawlspace
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        nil nil nil nil nil
        (list obj-special)                    ;; fourth-vermont-intersection
        nil nil
        (list obj-coins)                      ;; fifth-oaktree-intersection
        nil
        (list obj-bus)                        ;; fifth-sycamore-intersection
        nil
        (list obj-bone)                       ;; museum-lobby
        nil
        (list obj-jar obj-special obj-ruby)   ;; marine-life-area
        (list obj-nitric)                     ;; maintenance-room
        (list obj-glycerine)                  ;; classroom
        nil nil nil nil nil
        (list obj-amethyst)                   ;; bottom-of-subway-stairs
        nil nil
        (list obj-special)                    ;; question-room-1
        nil
        (list obj-special)                    ;; question-room-2
        nil
        (list obj-special)                    ;; question-room-three
        nil
        (list obj-mona)                       ;; winner's-room
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        nil))

;;; These are objects in a room that are only described in the
;;; room description.  They are permanent.

(defconstant dun-room-silents
  (list nil
        (list obj-tree obj-coconut)            ;; dead-end
        (list obj-tree obj-coconut)            ;; e-w-dirt-road
        nil nil nil nil nil nil
        (list obj-bin)                         ;; mailroom
        (list obj-computer)                    ;; computer-room
        nil nil nil
        (list obj-dial)                        ;; sauna
        nil
        (list obj-ladder)                      ;; weight-room
        (list obj-button obj-ladder)           ;; maze-button-room
        nil nil nil
        nil nil nil nil
        (list obj-lake)                        ;; lakefront-north
        (list obj-lake)                        ;; lakefront-south
        nil
        (list obj-chute)                       ;; cave-entrance
        nil nil nil nil nil
        (list obj-painting obj-bed)            ;; bedroom
        (list obj-urinal obj-pipes)            ;; bathroom
        nil nil nil nil nil nil
        (list obj-boulder)                     ;; horseshoe-boulder-room
        nil nil nil nil nil nil nil nil nil nil nil nil nil nil
        (list obj-computer obj-cable)          ;; gamma-computing-center
        (list obj-mail)                        ;; post-office
        (list obj-gate)                        ;; main-maple-intersection
        nil nil nil nil nil nil nil nil nil nil nil nil nil
        nil nil nil nil nil nil nil
        (list obj-cliff)                       ;; fifth-oaktree-intersection
        nil nil nil
        (list obj-dinosaur)                    ;; museum-lobby
        nil
        (list obj-fish obj-tanks)              ;; marine-life-area
        (list obj-switch)                      ;; maintenance-room
        (list obj-blackboard)                  ;; classroom
        (list obj-train)                       ;; vermont-station
        nil nil
        (list obj-disposal)                    ;; north-end-of-n-s-tunnel
        nil nil
        (list obj-computer)                    ;; endgame-computer-room
        nil nil nil nil nil nil nil nil
        (list obj-pc)                          ;; pc-area
        nil nil nil nil nil nil))

(defun obj-in-room-p (obj &optional (room dun-current-room))
  (if (symbolp obj)
      (obj-in-room-p (obj->num obj) room)
      (or (member obj (nth room dun-room-objects) :test #'eql)
          (member obj (nth room dun-room-silents) :test #'eql))))

;;; Descriptions of objects, as they appear in the room description, and
;;; the inventory.

(defconstant dun-objects
  '(("There is a shovel here." "A shovel")                ;0
    ("There is a lamp nearby." "A lamp")                  ;1
    ("There is a CPU card here." "A computer board")      ;2
    ("There is some food here." "Some food")              ;3
    ("There is a shiny brass key here." "A brass key")    ;4
    ("There is a slip of paper here." "A slip of paper")  ;5
    ("There is a wax statuette of Richard Stallman here." ;6
     "An RMS statuette")
    ("There is a shimmering diamond here." "A diamond")   ;7
    ("There is a 10 pound weight here." "A weight")       ;8
    ("There is a life preserver here." "A life preserver");9
    ("There is an emerald bracelet here." "A bracelet")   ;10
    ("There is a gold bar here." "A gold bar")            ;11
    ("There is a platinum bar here." "A platinum bar")    ;12
    ("There is a beach towel on the ground here." "A beach towel")
    ("There is an axe here." "An axe") ;14
    ("There is a silver bar here." "A silver bar")  ;15
    ("There is a bus driver's license here." "A license") ;16
    ("There are some valuable coins here." "Some valuable coins")
    ("There is a jewel-encrusted egg here." "A valuable egg") ;18
    ("There is a glass jar here." "A glass jar") ;19
    ("There is a dinosaur bone here." "A bone") ;20
    ("There is a packet of nitric acid here." "Some nitric acid")
    ("There is a packet of glycerine here." "Some glycerine") ;22
    ("There is a valuable ruby here." "A ruby") ;23
    ("There is a valuable amethyst here." "An amethyst") ;24
    ("The Mona Lisa is here." "The Mona Lisa") ;25
    ("There is a 100 dollar bill here." "A $100 bill") ;26
    ("There is a floppy disk here." "A floppy disk"))) ;27

;;; Weight of objects

(defconstant dun-object-lbs
  '(2 1 1 1 1 0 2 2 10 3 1 1 1 0 1 1 0 1 1 1 1 0 0 2 2 1 0 0))
(defconstant dun-object-pts
  '(0 0 0 0 0 0 0 10 0 0 10 10 10 0 0 10 0 10 10 0 0 0 0 10 10 10 10 0))

;;; Unix representation of objects.
(defconstant dun-objfiles
  '("shovel.o" "lamp.o" "cpu.o" "food.o" "key.o" "paper.o"
    "rms.o" "diamond.o" "weight.o" "preserver.o" "bracelet.o"
    "gold.o" "platinum.o" "towel.o" "axe.o" "silver.o" "license.o"
    "coins.o" "egg.o" "jar.o" "bone.o" "nitric.o" "glycerine.o"
    "ruby.o" "amethyst.o"))

;;; These are the descriptions for the negative numbered objects from
;;; dun-room-objects

(defconstant dun-perm-objects
  '(nil
    ("There is a large boulder here.")
    nil
    ("There is a ferocious bear here!")
    nil nil
    ("There is a worthless pile of protoplasm here.")
    nil nil nil nil nil nil
    ("There is a strange smell in this room.")
    nil
    ("There is a box with a slit in it, bolted to the wall here.")
    nil nil
    ("There is a bus here.")
    nil nil nil))


;;; These are the descriptions the user gets when regular objects are
;;; examined.

(defconstant dun-physobj-desc
  '(
    "It is a normal shovel with a price tag attached that says $19.99."
    "The lamp is hand-crafted by Geppetto."
    "The CPU board has a VAX chip on it.  It seems to have
2 Megabytes of RAM onboard."
    "It looks like some kind of meat.  Smells pretty bad."
    nil
    "The paper says: Don't forget to type 'help' for help.  Also, remember
this word: 'worms'"
    "The statuette is of the likeness of Richard Stallman, the author of the
famous EMACS editor.  You notice that he is not wearing any shoes."
    nil
    "You observe that the weight is heavy."
    "It says S. S. Minnow."
    nil nil nil
    "It has a picture of snoopy on it."
    nil nil
    "It has your picture on it!"
    "They are old coins from the 19th century."
    "It is a valuable Fabrege egg."
    "It is a plain glass jar."
    nil nil nil nil nil))

;;; These are the descriptions the user gets when non-regular objects
;;; are examined.

(defconstant dun-permobj-desc
  '(nil
    "It is just a boulder.  It cannot be moved."
    "They are palm trees with a bountiful supply of coconuts in them."
    "It looks like a grizzly to me."
    "All of the bins are empty.  Looking closely you can see that there
are names written at the bottom of each bin, but most of them are
faded away so that you cannot read them.  You can only make out three
names:
                   Jeffrey Collier
                   Robert Toukmond
                   Thomas Stock
"
    nil
    "It is just a garbled mess."
    "The dial points to a temperature scale which has long since faded away."
    nil nil
    "It is a velvet painting of Elvis Presley.  It seems to be nailed to the
wall, and you cannot move it."
    "It is a queen sized bed, with a very firm mattress."
    "The urinal is very clean compared with everything else in the cave.  There
isn't even any rust.  Upon close examination you realize that the drain at the
bottom is missing, and there is just a large hole leading down the
pipes into nowhere.  The hole is too small for a person to fit in.  The
flush handle is so clean that you can see your reflection in it."
    nil nil
    "The box has a slit in the top of it, and on it, in sloppy handwriting, is
written: 'For key upgrade, put key in here.'"
    nil
    "It says 'express mail' on it."
    "It is a 35 passenger bus with the company name 'mobytours' on it."
    "It is a large metal gate that is too big to climb over."
    "It is a HIGH cliff."
    "Unfortunately you do not know enough about dinosaurs to tell very much about
it.  It is very big, though."
    "The fish look like they were once quite beautiful."
    nil nil nil nil
    "It is a normal ladder that is permanently attached to the hole."
    "It is a passenger train that is ready to go."
    "It is a personal computer that has only one floppy disk drive."))

(defconstant dun-diggables
  (list nil nil nil (list obj-cpu) nil nil nil nil nil nil nil
        nil nil nil nil nil nil nil nil nil nil      ;11-20
        nil nil nil nil nil nil nil nil nil nil      ;21-30
        nil nil nil nil nil nil nil nil nil nil      ;31-40
        nil (list obj-platinum) nil nil nil nil nil nil nil nil))

(defconstant dun-room-shorts
  (loop for (desc name) in dun-rooms
     collect (substitute-if #\- (lambda (c) (member c '(#\SPACE #\/)))
                            (string-downcase name))))

(defmacro add-room-short-bindings ()
  `(progn
     ,@(loop for name in dun-room-shorts
          for a from 0
          collect `(defvar ,(intern (string-upcase name)) ,a))))
(add-room-short-bindings)

(defvar dun-endgame-questions
  '(("What is your password on the machine called 'pokey'?" "robert")
    ("What password did you use during anonymous ftp to gamma?" "foo")
    ("Excluding the endgame, how many places are there where you can put
treasures for points?" "4" "four")
    ("What is your login name on the 'endgame' machine?" "toukmond")
    ("What is the nearest whole dollar to the price of the shovel?"
     "20" "twenty")
    ("What is the name of the bus company serving the town?" "mobytours")
    ("Give either of the two last names in the mailroom, other than your own."
     "collier" "stock")
    ("What cartoon character is on the towel?" "snoopy")
    ("What is the last name of the author of EMACS?" "stallman")
    ("How many megabytes of memory is on the CPU board for the Vax?" "2")
    ("Which street in town is named after a U.S. state?" "vermont")
    ("How many pounds did the weight weigh?" "ten" "10")
    ("Name the STREET which runs right over the subway stop."
     "fourth" "4" "4th")
    ("How many corners are there in town (excluding the one with the Post Office)?"
     "24" "twentyfour" "twenty-four")
    ("What type of bear was hiding your key?" "grizzly")
    ("Name either of the two objects you found by digging."
     "cpu" "card" "vax" "board" "platinum")
    ("What network protocol is used between pokey and gamma?"
     "tcp/ip" "ip" "tcp")))

(defconstant dun-combination (format nil "~A" (+ 100 (random 899))))

;; TODO: This is only an approximation of the original behavior
(defun dun-get-path (dirstring startlist)
  (append startlist (split-string dirstring '(#\/))))

(defun dun-mprincl (&rest args)
  (format t "~{~A~}~%" args))

(defun dun-replace (list n number)
  (rplaca (nthcdr n list) number))

(defun input (&optional prompt-string)
  (when prompt-string
    (princ prompt-string)
    (force-output))
  (read-line))

(defun input-list (&optional prompt-string (delimiters '(#\SPACE #\, #\: #\;)))
  (mapcar #'(lambda (str)
              (intern (string-upcase str)))
          (split-string (input prompt-string) delimiters)))

;;;;
;;;; This section contains all of the verbs and commands.
;;;;

;;; Give long description of room if haven't been there yet.  Otherwise
;;; short.  Also give long if we were called with negative room number.

(defun dun-describe-room (room)
  (if (and (not (member (abs room) dun-light-rooms :test #'eql))
           (not (obj-in-inventory-p 'lamp))
           (not (obj-in-room-p 'lamp)))
      (dun-mprincl "It is pitch dark.  You are likely to be eaten by a grue.")
      (progn
        (dun-mprincl (cadr (nth (abs room) dun-rooms)))
        (if (and (and (or (member room dun-visited :test #'eql)
                          (eq dun-mode 'dun-superb))
                      (> room 0))
                 (not (eq dun-mode 'long)))
            nil
            (dun-mprincl (car (nth (abs room) dun-rooms))))
        (when (and (not (eq dun-mode 'long))
                   (not (member (abs room) dun-visited :test #'eql)))
          (setq dun-visited (append (list (abs room)) dun-visited)))
        (dolist (xobjs (nth dun-current-room dun-room-objects))
          (cond
            ((= xobjs obj-special)
             (dun-special-object))
            ((>= xobjs 0)
             (dun-mprincl (car (nth xobjs dun-objects))))
            ((not (and (= xobjs obj-bus) dun-inbus))
             (dun-mprincl (car (nth (abs xobjs) dun-perm-objects)))))
          (when (and (= xobjs obj-jar) dun-jar)
            (dun-mprincl "The jar contains:")
            (dolist (x dun-jar)
              (dun-mprincl "     " (car (nth x dun-objects))))))
        (when (and (obj-in-room-p 'bus) dun-inbus)
          (dun-mprincl "You are on the bus.")))))

;;; There is a special object in the room.  This object's description,
;;; or lack thereof, depends on certain conditions.

(defun dun-special-object ()
  (cond
    ((= dun-current-room computer-room)
     (if dun-computer
         (dun-mprincl
          "The panel lights are flashing in a seemingly organized pattern.")
         (dun-mprincl "The panel lights are steady and motionless.")))

    ((and (= dun-current-room red-room)
          (not (obj-in-room-p 'towel)))
     (dun-mprincl "There is a hole in the floor here."))

    ((and (= dun-current-room marine-life-area) dun-black)
     (dun-mprincl
      "The room is lit by a black light, causing the fish, and some of
your objects, to give off an eerie glow."))
    ((and (= dun-current-room fourth-vermont-intersection) dun-hole)
     (if (not dun-inbus)
         (progn
           (dun-mprincl "You fall into a hole in the ground.")
           (setq dun-current-room vermont-station)
           (dun-describe-room vermont-station))
         (progn
           (dun-mprincl "The bus falls down a hole in the ground and explodes.")
           (dun-die "burning"))))

    ((> dun-current-room endgame-computer-room)
     (if (not dun-correct-answer)
         (dun-endgame-question)
         (progn
           (dun-mprincl "Your question is:")
           (dun-mprincl dun-endgame-question))))

    ((= dun-current-room sauna)
     (dun-mprincl (nth dun-sauna-level
                       '("It is normal room temperature in here."
                         "It is luke warm in here."
                         "It is comfortably hot in here."
                         "It is refreshingly hot in here."
                         "You are dead now.")))
     (when (= dun-sauna-level 3)
       (when (or (obj-in-inventory-p 'rms) (obj-in-room-p 'rms))
         (dun-mprincl
          "You notice the wax on your statuette beginning to melt, until it completely
melts off.  You are left with a beautiful diamond!")
         (if (obj-in-inventory-p 'rms)
             (progn
               (dun-remove-obj-from-inven obj-rms)
               (setq dun-inventory (append dun-inventory
                                           (list obj-diamond))))
             (progn
               (dun-remove-obj-from-room dun-current-room obj-rms)
               (dun-replace dun-room-objects dun-current-room
                            (append (nth dun-current-room dun-room-objects)
                                    (list obj-diamond))))))
       (when (or (obj-in-inventory-p 'floppy) (obj-in-room-p 'floppy))
         (dun-mprincl
          "You notice your floppy disk beginning to melt.  As you grab for it, the
disk bursts into flames, and disintegrates.")
         (dun-remove-obj-from-inven obj-floppy)
         (dun-remove-obj-from-room dun-current-room obj-floppy))))))

(defun dun-die (murderer)
  (dun-mprincl)
  (when murderer
    (dun-mprincl "You are dead."))
  ;; (dun-do-logfile 'dun-die murderer)
  (dun-score nil)
  (setq dun-dead t))

(defun dun-quit (_args)
  (declare (ignore _args))
  (dun-die nil))

;;; Print every object in player's inventory.  Special case for the jar,
;;; as we must also print what is in it.

(defun dun-inven (_args)
  (declare (ignore _args))
  (dun-mprincl "You currently have:")
  (dolist (curobj dun-inventory)
    (when curobj
      (dun-mprincl (cadr (nth curobj dun-objects)))
      (when (and (= curobj obj-jar) dun-jar)
        (dun-mprincl "The jar contains:")
        (dolist (x dun-jar)
          (dun-mprincl "     " (cadr (nth x dun-objects))))))))

(defun dun-shake (args)
  (let ((objnum (dun-objnum-from-args-std args)))
    (when objnum
      (cond
        ((obj-in-inventory-p objnum)
         ;; Shaking does nothing in dunnet
         (format t "Shaking the ~(~A~) seems to have no effect.~%"
                 (car args)))
        ((not (obj-in-room-p objnum))
         (format t "I don't see that here.~%"))
        ;; Shaking trees can be deadly
        ((= objnum obj-tree)
         (princ
          "You begin to shake a tree, and notice a coconut begin to fall from the air.
As you try to get your hand up to block it, you feel the impact as it lands
on your head.")
         (dun-die "a coconut"))
        ((= objnum obj-bear)
         (princ
          "As you go up to the bear, it removes your head and places it on the ground.")
         (dun-die "a bear"))
        ((< objnum 0) (dun-mprincl "You cannot shake that."))
        (t (dun-mprincl "You don't have that."))))))

(defun dun-drop (args)
  (if dun-inbus
      (dun-mprincl "You can't drop anything while on the bus.")
      (let ((objnum (dun-objnum-from-args-std args)))
        (when objnum
          (if (not (obj-in-inventory-p objnum))
              (dun-mprincl "You don't have that.")
              (progn
                (dun-remove-obj-from-inven objnum)
                (dun-replace dun-room-objects dun-current-room
                             (append (nth dun-current-room dun-room-objects)
                                     (list objnum)))
                (dun-mprincl "Done.")
                (when (member objnum (list obj-food obj-weight obj-jar)
                              :test #'eql)
                  (dun-drop-check objnum))))))))

;;; Dropping certain things causes things to happen.

(defun dun-drop-check (objnum)
  (cond
    ((and (= objnum obj-food) (= dun-room bear-hangout)
          (obj-in-room-p 'bear))
     (dun-mprincl
      "The bear takes the food and runs away with it. He left something behind.")
     (dun-remove-obj-from-room dun-current-room obj-bear)
     (dun-remove-obj-from-room dun-current-room obj-food)
     (dun-replace dun-room-objects dun-current-room
                  (append (nth dun-current-room dun-room-objects)
                          (list obj-key))))

    ((and (= objnum obj-jar)
          (member obj-nitric dun-jar :test #'eql)
          (member obj-glycerine dun-jar :test #'eql))
     (dun-mprincl "As the jar impacts the ground it explodes into many pieces.")
     (setq dun-jar nil)
     (dun-remove-obj-from-room dun-current-room obj-jar)
     (when (= dun-current-room fourth-vermont-intersection)
       (setq dun-hole t)
       (setq dun-current-room vermont-station)
       (dun-mprincl
        "The explosion causes a hole to open up in the ground, which you fall
through.")))

    ((and (= objnum obj-weight) (= dun-current-room maze-button-room))
     (dun-mprincl "A passageway opens."))))

;;; Give long description of current room, or an object.

(defun dun-examine (args)
  (match args
         (() (dun-describe-room (* dun-current-room -1)))
         ((obj . rest)
          (let ((objnum (obj->num obj)))
            (cond
              ((and (eq objnum obj-computer)
                    (member obj-pc (nth dun-current-room dun-room-silents)))
               (dun-examine '(pc)))
              ((null objnum)
               (dun-mprincl "I don't know what that is."))
              ((and (not (member objnum (nth dun-current-room dun-room-objects)))
                    (not (and (member obj-jar dun-inventory)
                              (member objnum dun-jar)))
                    (not (member objnum (nth dun-current-room dun-room-silents)))
                    (not (member objnum dun-inventory)))
               (dun-mprincl "I don't see that here."))
              ((>= objnum 0)
               (if (and (= objnum obj-bone)
                        (= dun-current-room marine-life-area) dun-black)
                   (dun-mprincl
                    "In this light you can see some writing on the bone.  It says:
For an explosive time, go to Fourth St. and Vermont.")
                   (if (nth objnum dun-physobj-desc)
                       (dun-mprincl (nth objnum dun-physobj-desc))
                       (dun-mprincl "I see nothing special about that."))))
              ((nth (abs objnum) dun-permobj-desc)
               (dun-mprincl (nth (abs objnum) dun-permobj-desc)))
              (t (dun-mprincl "I see nothing special about that.")))))))

(defun dun-take (args)
  (match args
         (() (format t "You must supply an object.~%"))
         ((obj . rest)
          (if (eq obj 'all)
              (let ((gotsome nil))
                (if dun-inbus
                    (dun-mprincl "You can't take anything while on the bus.")
                    (progn
                      (dolist (x (nth dun-current-room dun-room-objects))
                        (when (and (>= x 0) (not (= x obj-special)))
                          (setq gotsome t)
                          (format t "~A: " (cadr (nth x dun-objects)))
                          (dun-take-object x)))
                      (when (not gotsome)
                        (dun-mprincl "Nothing to take.")))))
              (let ((objnum (obj->num obj)))
                (if (null objnum)
                    (dun-mprincl "I don't know what that is.")
                    (if (and dun-inbus
                             (not (and (member objnum dun-jar :test #'eql)
                                       (member obj-jar dun-inventory :test #'eql))))
                        (dun-mprincl "You can't take anything while on the bus.")
                        (dun-take-object objnum))))))))

(defun dun-take-object (objnum)
  (cond
    ((and (member objnum dun-jar :test #'eql)
          (member obj-jar dun-inventory :test #'eql))
     (let ((newjar nil))
       (dun-mprincl "You remove it from the jar.")
       (dolist (x dun-jar)
         (if (not (= x objnum))
             (setq newjar (append newjar (list x)))))
       (setq dun-jar newjar)
       (setq dun-inventory (append dun-inventory (list objnum)))))
    (t (if (not (member objnum (nth dun-current-room dun-room-objects)))
           (if (not (member objnum (nth dun-current-room dun-room-silents)))
               (format t "I do not see that here.")
               (dun-try-take objnum))
           (if (>= objnum 0)
               (progn
                 (if (and (car dun-inventory)
                          (> (+ (dun-inven-weight) (nth objnum dun-object-lbs)) 11))
                     (format t "Your load would be too heavy.")
                     (progn
                       (setq dun-inventory (append dun-inventory (list objnum)))
                       (dun-remove-obj-from-room dun-current-room objnum)
                       (format t "Taken.  ")
                       (when (and (= objnum obj-towel)
                                  (= dun-current-room red-room))
                         (princ
                          "Taking the towel reveals a hole in the floor.")))))
               (dun-try-take objnum)))
       (dun-mprincl))))

(defun dun-inven-weight ()
  (labels ((obj-weight (num)
             (nth num dun-object-lbs)))
    (+ (apply #'+ (mapcar #'obj-weight dun-jar))
       (apply #'+ (mapcar #'obj-weight dun-inventory)))))

;;; We try to take an object that is untakable.  Print a message
;;; depending on what it is.

(defun dun-try-take (_obj)
  (declare (ignore _obj))
  (format t "You cannot take that."))

(defun dun-dig (_args)
  (declare (ignore _args))
  (cond
    (dun-inbus (dun-mprincl "Digging here reveals nothing."))
    ((not (obj-in-inventory-p 'shovel))
     (dun-mprincl "You have nothing with which to dig."))
    ((not (nth dun-current-room dun-diggables))
     (dun-mprincl "Digging here reveals nothing."))
    (t (dun-mprincl "I think you found something.")
       (dun-replace dun-room-objects dun-current-room
                    (append (nth dun-current-room dun-room-objects)
                            (nth dun-current-room dun-diggables)))
       (dun-replace dun-diggables dun-current-room nil))))

(defun dun-climb (args)
  (match args
         (() (if (obj-in-room-p 'tree)
                 (dun-climb '(tree))
                 (format t "There is nothing here to climb.~%")))
         ((obj . rest)
          (princ
           (cond
             ((and (not (obj-in-room-p obj))
                   (not (obj-in-inventory-p obj)))
              "I don't see that here.")
             ((not (eq obj 'tree))
              "You can't climb that.")
             (t "You manage to get about two feet up the tree but fall down. You
notice that the tree is very unsteady.")))
          (terpri))))

(defun dun-eat (args)
  (match args
         (() (format t "Eat what?~%"))
         ((obj . rest)
          (cond
            ((not (obj-in-inventory-p obj))
             (format t "You don't have that.~%"))
            ((eq obj 'food)
             (format t "That tasted horrible.%")
             (dun-remove-obj-from-inven obj-food))
            (t (format t "You forcefully shove the ~(~A~) down your throat and start choking.~%"
                       obj)
               (dun-die "choking"))))))

(defun dun-put-objs (obj1 obj2)
  (when (and (= obj2 obj-drop)
             (not dun-nomail))
    (setq obj2 obj-chute))

  (when (= obj2 obj-disposal)
    (setq obj2 obj-chute))

  (cond
    ((and (= obj1 obj-cpu) (= obj2 obj-computer))
     (dun-remove-obj-from-inven obj-cpu)
     (setq dun-computer t)
     (dun-mprincl
      "As you put the CPU board in the computer, it immediately springs to life.
The lights start flashing, and the fans seem to startup."))
    ((and (= obj1 obj-weight) (= obj2 obj-button))
     (dun-drop '(weight)))
    ((= obj2 obj-jar)                    ; Put something in jar
     (if (not (member obj1 (list obj-paper obj-diamond obj-emerald
                                 obj-license obj-coins obj-egg
                                 obj-nitric obj-glycerine)))
         (dun-mprincl "That will not fit in the jar.")
         (progn
           (dun-remove-obj-from-inven obj1)
           (setq dun-jar (append dun-jar (list obj1)))
           (dun-mprincl "Done."))))
    ((= obj2 obj-chute)                  ; Put something in chute
     (dun-remove-obj-from-inven obj1)
     (dun-mprincl "You hear it slide down the chute and off into the distance.")
     (dun-put-objs-in-treas (list obj1)))
    ((= obj2 obj-box)                    ; Put key in key box
     (if (/= obj1 obj-key)
         (dun-mprincl "You can't put that in the key box!")
         (progn
           (dun-mprincl
            "As you drop the key, the box begins to shake.  Finally it explodes
with a bang.  The key seems to have vanished!")
           (dun-remove-obj-from-inven obj1)
           (dun-replace dun-room-objects computer-room (append
                                                        (nth computer-room
                                                             dun-room-objects)
                                                        (list obj1)))
           (dun-remove-obj-from-room dun-current-room obj-box)
           (setq dun-key-level (1+ dun-key-level)))))

    ((and (= obj1 obj-floppy) (= obj2 obj-pc))
     (setq dun-floppy t)
     (dun-remove-obj-from-inven obj1)
     (dun-mprincl "Done."))

    ((= obj2 obj-urinal)                 ; Put object in urinal
     (dun-remove-obj-from-inven obj1)
     (dun-replace dun-room-objects urinal (append
                                           (nth urinal dun-room-objects)
                                           (list obj1)))
     (dun-mprincl "You hear it plop down in some water below."))
    ((= obj2 obj-mail)
     (dun-mprincl "The mail chute is locked."))
    ((obj-in-inventory-p obj1)
     (dun-mprincl
      "I don't know how to combine those objects.  Perhaps you should
just try dropping it."))
    (t (dun-mprincl "You can't put that there."))))

(defun dun-put (args)
  (match args
         (() (format t "You must supply an object~%"))
         ((obj)
          (format t "You must supply an indirect object.~%"))
         ((obj indirect . rest)
          (destructuring-bind (objnum objnum2)
              (mapcar #'obj->num (list obj indirect))
            (cond
              ((not objnum)
               (format t "I don't know what that object is.~%"))
              ((not (obj-in-inventory-p obj))
               (format t "You don't have that.~%"))
              (t (when (and (eql objnum2 obj-computer)
                            (= dun-current-room pc-area))
                   (setq objnum2 obj-pc))
                 (cond
                   ((not objnum2)
                    (format t "I don't know what that indirect object is.~%"))
                   ((and (not (obj-in-inventory-p objnum2))
                         (not (obj-in-room-p objnum2)))
                    (format t "That indirect object is not here.~%"))
                   (t (dun-put-objs objnum objnum2)))))))))

(defun dun-type (_args)
  (declare (ignore _args))
  (cond
    ((not (= dun-current-room computer-room))
     (dun-mprincl "There is nothing here on which you could type."))
    ((not dun-computer)
     (dun-mprincl
      "You type on the keyboard, but your characters do not even echo."))
    (t (dun-unix-interface))))

;;; Uses the dungeon-map to figure out where we are going.  If the
;;; requested direction yields 255, we know something special is
;;; supposed to happen, or perhaps you can't go that way unless
;;; certain conditions are met.

(defun dun-move (dir)
  (if (and (not (member dun-current-room dun-light-rooms :test #'eql))
           (not (obj-in-inventory-p 'lamp))
           (not (obj-in-room-p 'lamp)))
      (progn
        (princ
         "You trip over a grue and fall into a pit and break every bone in your
body.")
        (dun-die "a grue"))
      (progn
        (setq dir (dun-movement dir))
        (let (newroom)
          (setq newroom (nth dir (nth dun-current-room dungeon-map)))
          (if (eq newroom -1)
              (dun-mprincl "You can't go that way.")
              (if (eq newroom 255)
                  (dun-special-move dir)
                  (progn
                    (setq dun-room -1)
                    (setq dun-lastdir dir)
                    (if dun-inbus
                        (if (or (< newroom 58) (> newroom 83))
                            (dun-mprincl "The bus cannot go this way.")
                            (progn
                              (dun-mprincl
                               "The bus lurches ahead and comes to a screeching halt.")
                              (dun-remove-obj-from-room dun-current-room obj-bus)
                              (setq dun-current-room newroom)
                              (dun-replace dun-room-objects newroom
                                           (append (nth newroom dun-room-objects)
                                                   (list obj-bus)))))
                        (setq dun-current-room newroom)))))))))

;;; Various movement directions

(defun dun-movement (dir)
  "Return number associated with movement symbol DIR."
  (cdr (assoc dir dun-movement-alist)))

(defun dun-n (_args)
  (declare (ignore _args))
  (dun-move 'north))

(defun dun-s (_args)
  (declare (ignore _args))
  (dun-move 'south))

(defun dun-e (_args)
  (declare (ignore _args))
  (dun-move 'east))

(defun dun-w (_args)
  (declare (ignore _args))
  (dun-move 'west))

(defun dun-ne (_args)
  (declare (ignore _args))
  (dun-move 'northeast))

(defun dun-se (_args)
  (declare (ignore _args))
  (dun-move 'southeast))

(defun dun-nw (_args)
  (declare (ignore _args))
  (dun-move 'northwest))

(defun dun-sw (_args)
  (declare (ignore _args))
  (dun-move 'southwest))

(defun dun-up (_args)
  (declare (ignore _args))
  (dun-move 'up))

(defun dun-down (_args)
  (declare (ignore _args))
  (dun-move 'down))

(defun dun-in (_args)
  (declare (ignore _args))
  (dun-move 'in))

(defun dun-out (_args)
  (declare (ignore _args))
  (dun-move 'out))

(defun dun-go (args)
  (doverb args
          :error-handler
          #'(lambda (verb)
              (declare (ignore verb))
              (format t "I don't understand where you want me to go.~%"))))

;;; Movement in this direction causes something special to happen if the
;;; right conditions exist.  It may be that you can't go this way unless
;;; you have a key, or a passage has been opened.

;;; coding note: Each check of the current room is on the same 'if' level,
;;; i.e. there aren't else's.  If two rooms next to each other have
;;; specials, and they are connected by specials, this could cause
;;; a problem.  Be careful when adding them to consider this, and
;;; perhaps use else's.

(defun dun-special-move (dir)
  (if (= dun-current-room building-front)
      (if (not (obj-in-inventory-p 'key))
          (dun-mprincl "You don't have a key that can open this door.")
          (setq dun-current-room old-building-hallway))
      (progn
        (if (= dun-current-room north-end-of-cave-passage)
            (let (combo)
              (dun-mprincl
               "You must type a 3 digit combination code to enter this room.")
              (setq combo (input "Enter it here: "))
              (if (string= combo dun-combination)
                  (setq dun-current-room gamma-computing-center)
                  (dun-mprincl "Sorry, that combination is incorrect."))))

        (if (= dun-current-room bear-hangout)
            (if (obj-in-room-p 'bear)
                (progn
                  (princ
                   "The bear is very annoyed that you would be so presumptuous as to try
and walk right by it.  He tells you so by tearing your head off.
")
                  (dun-die "a bear"))
                (dun-mprincl "You can't go that way.")))

        (if (= dun-current-room vermont-station)
            (progn
              (dun-mprincl
               "As you board the train it immediately leaves the station.  It is a very
bumpy ride.  It is shaking from side to side, and up and down.  You
sit down in one of the chairs in order to be more comfortable.")
              (dun-mprincl)
              (dun-mprincl
               "Finally the train comes to a sudden stop, and the doors open, and some
force throws you out.  The train speeds away.")
              (dun-mprincl)
              (setq dun-current-room museum-station)))

        (if (= dun-current-room old-building-hallway)
            (if (and (obj-in-inventory-p 'key)
                     (> dun-key-level 0))
                (setq dun-current-room meadow)
                (dun-mprincl "You don't have a key that can open this door.")))

        (if (and (= dun-current-room maze-button-room)
                 (= dir (dun-movement 'northwest)))
            (if (obj-in-room-p 'weight)
                (setq dun-current-room 18)
                (dun-mprincl "You can't go that way.")))

        (if (and (= dun-current-room maze-button-room)
                 (= dir (dun-movement 'up)))
            (if (obj-in-room-p 'weight)
                (dun-mprincl "You can't go that way.")
                (setq dun-current-room weight-room)))

        (if (= dun-current-room classroom)
            (dun-mprincl "The door is locked."))

        (if (or (= dun-current-room lakefront-north)
                (= dun-current-room lakefront-south))
            (dun-swim nil))

        (if (= dun-current-room reception-area)
            (if (not (= dun-sauna-level 3))
                (setq dun-current-room health-club-front)
                (progn
                  (dun-mprincl
                   "As you exit the building, you notice some flames coming out of one of the
windows.  Suddenly, the building explodes in a huge ball of fire.  The flames
engulf you, and you burn to death.")
                  (dun-die "burning"))))

        (when (= dun-current-room red-room)
          (if (not (obj-in-room-p 'towel))
              (setq dun-current-room long-n-s-hallway)
              (dun-mprincl "You can't go that way.")))

        (if (and (> dir (dun-movement 'down))
                 (> dun-current-room gamma-computing-center)
                 (< dun-current-room museum-lobby))
            (if (not (obj-in-room-p 'bus))
                (dun-mprincl "You can't go that way.")
                (if (= dir (dun-movement 'in))
                    (if dun-inbus
                        (dun-mprincl
                         "You are already in the bus!")
                        (if (obj-in-inventory-p 'license)
                            (progn
                              (dun-mprincl
                               "You board the bus and get in the driver's seat.")
                              (setq dun-nomail t)
                              (setq dun-inbus t))
                            (dun-mprincl "You are not licensed for this type of vehicle.")))
                    (if (not dun-inbus)
                        (dun-mprincl "You are already off the bus!")
                        (progn
                          (dun-mprincl "You hop off the bus.")
                          (setq dun-inbus nil)))))
            (progn
              (if (= dun-current-room fifth-oaktree-intersection)
                  (if (not dun-inbus)
                      (progn
                        (dun-mprincl "You fall down the cliff and land on your head.")
                        (dun-die "a cliff"))
                      (progn
                        (dun-mprincl
                         "The bus flies off the cliff, and plunges to the bottom, where it explodes.")
                        (dun-die "a bus accident"))))
              (when (= dun-current-room main-maple-intersection)
                (if (not dun-inbus)
                    (dun-mprincl "The gate will not open.")
                    (progn
                      (dun-mprincl
                       "As the bus approaches, the gate opens and you drive through.")
                      (dun-remove-obj-from-room main-maple-intersection obj-bus)
                      (dun-replace dun-room-objects museum-entrance
                                   (append (nth museum-entrance dun-room-objects)
                                           (list obj-bus)))
                      (setq dun-current-room museum-entrance))))))
        (when (= dun-current-room cave-entrance)
          (dun-mprincl
           "As you enter the room you hear a rumbling noise.  You look back to see
huge rocks sliding down from the ceiling, and blocking your way out.")
          (dun-mprincl)
          (setq dun-current-room misty-room)))))

(defun dun-long (_args)
  (declare (ignore _args))
  (setq dun-mode 'long))

(defun dun-turn (args)
  (match args
         (() (format t "What do you want to turn?~%"))
         ((obj)
          ;; at minimum, see if it's the dial and here... this will fail
          (dun-turn (list obj nil)))
         ((obj direction . rest)
          (cond
            ((not (obj-in-room-p obj))
             (format t "I don't see that here.~%"))
            ((not (eq obj 'dial))
             (format t "You can't turn that.~%"))
            ((not (member direction '(clockwise counterclockwise)))
             (format t "You must indicate clockwise or counterclockwise.~%"))
            (t (setq dun-sauna-level
                     (case direction
                       (clockwise (1+ dun-sauna-level))
                       (counterclockwise (1- dun-sauna-level))))
               (if (< dun-sauna-level 0)
                   (progn
                     (format t "The dial will not turn further in that direction.~%")
                     (setq dun-sauna-level 0))
                   (dun-sauna-heat dun-sauna-level)))))))

(defun dun-sauna-heat (level)
  (cond
    ((= level 0)
     (dun-mprincl "The temperature has returned to normal room temperature."))
    ((= level 1)
     (dun-mprincl "It is now luke warm in here.  You are perspiring."))
    ((= level 2)
     (dun-mprincl "It is pretty hot in here.  It is still very comfortable."))
    ((= level 3)
     (dun-mprincl
      "It is now very hot.  There is something very refreshing about this.")
     (when (or (obj-in-inventory-p 'rms)
               (obj-in-room-p 'rms))
       (dun-mprincl
        "You notice the wax on your statuette beginning to melt, until it completely
melts off.  You are left with a beautiful diamond!")
       (if (obj-in-inventory-p 'rms)
           (progn
             (dun-remove-obj-from-inven obj-rms)
             (setq dun-inventory (append dun-inventory
                                         (list obj-diamond))))
           (progn
             (dun-remove-obj-from-room dun-current-room obj-rms)
             (dun-replace dun-room-objects dun-current-room
                          (append (nth dun-current-room dun-room-objects)
                                  (list obj-diamond))))))
     (when (or (obj-in-inventory-p 'floppy)
               (obj-in-room-p 'floppy))
       (dun-mprincl
        "You notice your floppy disk beginning to melt.  As you grab for it, the
disk bursts into flames, and disintegrates.")
       (if (obj-in-inventory-p 'floppy)
           (dun-remove-obj-from-inven obj-floppy)
           (dun-remove-obj-from-room dun-current-room obj-floppy))))

    ((= level 4)
     (dun-mprincl "As the dial clicks into place, you immediately burst into flames.")
     (dun-die "burning"))))

(defun dun-press (obj)
  (let ((objnum (dun-objnum-from-args-std obj)))
    (cond
      ((not (obj-in-room-p objnum))
       (dun-mprincl "I don't see that here."))
      ((not (member objnum (list obj-button obj-switch)
                    :test #'eql))
       ;; TODO: previously showed the typed verb
       (dun-mprincl "You can't " "press" " that."))
      ((= objnum obj-button)
       (dun-mprincl
        "As you press the button, you notice a passageway open up, but
as you release it, the passageway closes."))
      ((= objnum obj-switch)
       (if dun-black
           (progn
             (dun-mprincl "The button is now in the off position.")
             (setq dun-black nil))
           (progn
             (dun-mprincl "The button is now in the on position.")
             (setq dun-black t)))))))

(defun dun-swim (_args)
  (declare (ignore _args))
  (cond
    ((not (member dun-current-room (list lakefront-north lakefront-south)
                  :test #'eql))
     (dun-mprincl "I see no water!"))
    ((not (obj-in-inventory-p 'life))
     (dun-mprincl
      "You dive in the water, and at first notice it is quite cold.  You then
start to get used to it as you realize that you never really learned how
to swim.")
     (dun-die "drowning"))
    ((= dun-current-room lakefront-north)
     (setq dun-current-room lakefront-south))
    (t (setq dun-current-room lakefront-north))))

(defun dun-score (_args)
  (declare (ignore _args))
  (if (not dun-endgame)
      (let (total)
        (setq total (dun-reg-score))
        (dun-mprincl "You have scored " total " out of a possible 90 points.")
        total)
      (progn
        (format t "You have scored ~A endgame points out of a possible of 110.~%"
                (dun-endgame-store))
        (when (= (dun-endgame-score) 110)
          (dun-mprincl)
          (dun-mprincl)
          (dun-mprincl
           "Congratulations.  You have won.  The wizard password is 'moby'")))))

(defun dun-help (_args)
  (declare (ignore _args))
  (dun-mprincl
   "Welcome to dunnet (2.02), by Ron Schnell (ronnie@driver-aces.com - @RonnieSchnell).

**************************************************************************
* This is a port to Common Lisp, and is not the official implementation. *
* Ported by Jack Rosenthal (jack@rosenth.al)                             *
**************************************************************************

Here is some useful information (read carefully because there are one
or more clues in here):
- If you have a key that can open a door, you do not need to explicitly
  open it.  You may just use 'in' or walk in the direction of the door.

- If you have a lamp, it is always lit.

- You will not get any points until you manage to get treasures to a certain
  place.  Simply finding the treasures is not good enough.  There is more
  than one way to get a treasure to the special place.  It is also
  important that the objects get to the special place *unharmed* and
  *untarnished*.  You can tell if you have successfully transported the
  object by looking at your score, as it changes immediately.  Note that
  an object can become harmed even after you have received points for it.
  If this happens, your score will decrease, and in many cases you can never
  get credit for it again.

- You can save your game with the 'save' command, and restore it
  with the 'restore' command.

- There are no limits on lengths of object names.

- Directions are: north,south,east,west,northeast,southeast,northwest,
                  southwest,up,down,in,out.

- These can be abbreviated: n,s,e,w,ne,se,nw,sw,u,d,in,out.

- If you go down a hole in the floor without an aid such as a ladder,
  you probably won't be able to get back up the way you came, if at all.

If you have questions or comments, please contact ronnie@driver-aces.com
My home page is http://www.driver-aces.com/ronnie.html
"))

(defun dun-flush (_args)
  (declare (ignore _args))
  (if (not (= dun-current-room bathroom))
      (dun-mprincl "I see nothing to flush.")
      (progn
        (dun-mprincl "Whoooosh!!")
        (dun-put-objs-in-treas (nth urinal dun-room-objects))
        (dun-replace dun-room-objects urinal nil))))

(defun dun-piss (_args)
  (declare (ignore _args))
  (cond
    ((not (= dun-current-room bathroom))
     (dun-mprincl "You can't do that here, don't even bother trying."))
    ((not dun-gottago)
     (dun-mprincl "I'm afraid you don't have to go now."))
    (t (dun-mprincl "That was refreshing.")
       (setq dun-gottago nil)
       (dun-replace dun-room-objects urinal (append
                                             (nth urinal dun-room-objects)
                                             (list obj-URINE))))))

(defun dun-sleep (_args)
  (declare (ignore _args))
  (if (not (= dun-current-room bedroom))
      (dun-mprincl
       "You try to go to sleep while standing up here, but can't seem to do it.")
      (progn
        (setq dun-gottago t)
        (dun-mprincl
         "As soon as you start to doze off you begin dreaming.  You see images of
workers digging caves, slaving in the humid heat.  Then you see yourself
as one of these workers.  While no one is looking, you leave the group
and walk into a room.  The room is bare except for a horseshoe
shaped piece of stone in the center.  You see yourself digging a hole in
the ground, then putting some kind of treasure in it, and filling the hole
with dirt again.  After this, you immediately wake up."))))

(defun dun-break (obj)
  (if (not (obj-in-inventory-p 'axe))
      (dun-mprincl "You have nothing you can use to break things.")
      (let ((objnum (dun-objnum-from-args-std obj)))
        (when objnum
          (cond
            ((obj-in-inventory-p objnum)
             (dun-mprincl
              "You take the object in your hands and swing the axe.  Unfortunately, you miss
the object and slice off your hand.  You bleed to death.")
             (dun-die "an axe"))
            ((not (obj-in-room-p objnum))
             (dun-mprincl "I don't see that here."))
            ((= objnum obj-cable)
             (dun-mprincl
              "As you break the ethernet cable, everything starts to blur.  You collapse
for a moment, then straighten yourself up.")
             (dun-mprincl)
             (dun-replace dun-room-objects gamma-computing-center
                          (append
                           (nth gamma-computing-center dun-room-objects)
                           dun-inventory))
             (if (obj-in-inventory-p 'key)
                 (progn
                   (setq dun-inventory (list obj-key))
                   (dun-remove-obj-from-room gamma-computing-center obj-key))
                 (setq dun-inventory nil))
             (setq dun-current-room computer-room)
             (setq dun-ethernet nil)
             (dun-mprincl "Connection closed.")
             (dun-unix-interface))
            ((< objnum 0)
             (dun-mprincl "Your axe shatters into a million pieces.")
             (dun-remove-obj-from-inven obj-axe))
            (t
             (dun-mprincl "Your axe breaks it into a million pieces.")
             (dun-remove-obj-from-room dun-current-room objnum)))))))

(defun dun-drive (_args)
  (declare (ignore _args))
  (if (not dun-inbus)
      (dun-mprincl "You cannot drive when you aren't in a vehicle.")
      (dun-mprincl "To drive while you are in the bus, just give a direction.")))

(defun dun-superb (_args)
  (declare (ignore _args))
  (setq dun-mode 'dun-superb))

(defun dun-reg-score ()
  (let (total)
    (setq total 0)
    (dolist (x (nth treasure-room dun-room-objects))
      (setq total (+ total (nth x dun-object-pts))))
    (when (obj-in-room-p obj-URINE treasure-room)
      (setq total 0))
    total))

(defun dun-endgame-score ()
  (let (total)
    (setq total 0)
    (dolist (x (nth endgame-treasure-room dun-room-objects))
      (setq total (+ total (nth x dun-object-pts)))) total))

(defun dun-answer (args)
  (if (not dun-correct-answer)
      (dun-mprincl "I don't believe anyone asked you anything.")
      (progn
        (setq args (car args))
        (if (not args)
            (dun-mprincl "You must give the answer on the same line.")
            (if (member args dun-correct-answer)
                (progn
                  (dun-mprincl "Correct.")
                  (if (= dun-lastdir 0)
                      (setq dun-current-room (1+ dun-current-room))
                      (setq dun-current-room (- dun-current-room 1)))
                  (setq dun-correct-answer nil))
                (dun-mprincl "That answer is incorrect."))))))

(defun dun-endgame-question ()
  (let ((questions dun-endgame-questions))
    (if (null questions)
        (progn
          (dun-mprincl "Your question is:")
          (setq dun-correct-answer '(foo)))
        (let* ((which (random (length questions)))
               (question (nth which questions)))
          (dun-mprincl "Your question is:")
          (dun-mprincl (setq dun-endgame-question (car question)))
          (setq dun-correct-answer (cdr question))
          (let ((i 0) res)
            (dolist (q questions)
              (when (/= i which)
                (push q res))
              (setq i (1+ i)))
            (setq dun-endgame-questions (nreverse res)))))))

(defun dun-power (_args)
  (declare (ignore _args))
  (if (not (= dun-current-room pc-area))
      (dun-mprincl "That operation is not applicable here.")
      (if (not dun-floppy)
          (dun-dos-no-disk)
          (dun-dos-interface))))

(defun dun-feed (args)
  (let ((objnum (dun-objnum-from-args-std args)))
    (when objnum
      (if (and (= objnum obj-bear) (obj-in-room-p 'bear))
          (progn
            (if (not (obj-in-inventory-p 'food))
                (dun-mprincl "You have nothing with which to feed it.")
                (dun-drop '(food))))
          (if (not (or (obj-in-room-p objnum)
                       (obj-in-inventory-p objnum)))
              (dun-mprincl "I don't see that here.")
              (dun-mprincl "You cannot feed that."))))))

;;; Function which takes a verb and a list of other words.  Calls proper
;;; function associated with the verb, and passes along the other words.

(defun doverb (words &key
                       (verblist dun-verblist)
                       (ignore ignored-words)
                       (error-handler
                        #'(lambda (verb)
                            (declare (ignore verb))
                            (format t "I don't understand that.~%"))))
  ;; do nothing when words is nil
  (when words
    (let ((words (remove-if (lambda (word)
                              (member word ignore))
                            words)))
      (if (not words)
          ;; only ignored words were given
          (funcall error-handler nil)
          (destructuring-bind (verb . args) words
            (let ((fcn (cdr (assoc verb verblist))))
              (if fcn
                  (progn
                    ;; log number of commands run
                    (incf dun-numcmds)
                    (funcall fcn args))
                  (funcall error-handler verb))))))))

;;; Function to put objects in the treasure room.  Also prints current
;;; score to let user know he has scored.

(defun dun-put-objs-in-treas (objlist)
  (let (oscore newscore)
    (setq oscore (dun-reg-score))
    (dun-replace dun-room-objects 0 (append (nth 0 dun-room-objects) objlist))
    (setq newscore (dun-reg-score))
    (when (not (= oscore newscore))
      (dun-score nil))))

;;; Load an encrypted file, and eval it.

;; (defun dun-load-d (filename)
;;   (let ((result t))
;;     (with-temp-buffer
;;       (condition-case nil
;;           (insert-file-contents filename)
;;         (error (setq result nil)))
;;       (when result
;;         (condition-case nil
;;             (dun-rot13)
;;           (error (yank)))
;;         (eval-buffer)))
;;     result))

;; ;;; Functions to remove an object either from a room, or from inventory.

(defun dun-remove-obj-from-room (room objnum)
  (let (newroom)
    (dolist (x (nth room dun-room-objects))
      (if (not (= x objnum))
          (setq newroom (append newroom (list x)))))
    (rplaca (nthcdr room dun-room-objects) newroom)))

(defun dun-remove-obj-from-inven (objnum)
  (let (new-inven)
    (dolist (x dun-inventory)
      (if (not (= x objnum))
          (setq new-inven (append new-inven (list x)))))
    (setq dun-inventory new-inven)))

;; (defun dun-rot13 ()
;;   (rot13-region (point-min) (point-max)))

;;;;
;;;; This section defines the UNIX emulation functions for dunnet.
;;;;

;; (defun dun-doassign (line esign)
;;   (if (not dun-wizard)
;;       (let (passwd)
;; 	(dun-mprinc "Enter wizard password: ")
;; 	(setq passwd (dun-read-line))
;; 	(if (string= passwd "moby")
;; 	    (progn
;; 	      (setq dun-wizard t)
;; 	      (dun-doassign line esign))
;; 	    (dun-mprincl "Incorrect.")))

;;       (let (varname epoint afterq i value)
;;         (setq varname (replace-regexp-in-string " " "" (substring line 0 esign)))

;;         (if (or (= (length varname) 0) (< (- (length line) esign) 2))
;; 	    (progn
;; 	      (dun-mprinc line)
;; 	      (dun-mprincl " : not found."))

;; 	    (if (not (setq epoint (string-match ")" line)))
;; 	        (if (string= (substring line (1+ esign) (+ esign 2))
;; 			     "\"")
;; 		    (progn
;; 		      (setq afterq (substring line (+ esign 2)))
;; 		      (setq epoint (+
;; 				    (string-match "\"" afterq)
;; 				    (+ esign 3))))

;; 	            (if (not (setq epoint (string-match " " line)))
;; 		        (setq epoint (length line))))
;; 	        (setq epoint (1+ epoint))
;; 	        (while (and
;; 		        (not (= epoint (length line)))
;; 		        (setq i (string-match ")" (substring line epoint))))
;; 	          (setq epoint (+ epoint i 1))))
;; 	    (setq value (substring line (1+ esign) epoint))
;; 	    (dun-eval varname value)))))

;; (defun dun-eval (varname value)
;;   (with-temp-buffer
;;     (insert "(setq " varname " " value ")")
;;     (condition-case nil
;;         (eval-buffer)
;;       (error (dun-mprincl "Invalid syntax.")))))

(defun dun-login (tries-left)
  (when (and (not dun-logged-in)
             (> tries-left 0))
    (format t "~%~%UNIX System V, Release 2.2 (pokey)~%~%")
    (let ((username (input "login: "))
          (password (input "password: ")))
      (if (or (not (string= username "toukmond"))
              (not (string= password "robert")))
          (progn
            (format t "login incorrect~%")
            (dun-login (1- tries-left)))
          (progn
            (setq dun-logged-in t)
            (format t "
Welcome to Unix~%
Please clean up your directories.  The filesystem is getting full.
Our tcp/ip link to gamma is a little flaky, but seems to work.
The current version of ftp can only send files from your home
directory, and deletes them after they are sent!  Be careful.

Note: Restricted bourne shell in use.~%")))))
  (setq dungeon-mode 'dungeon))

(defun dun-ls (args)
  (let ((ocdroom dun-cdroom))
    (if (car args)
        (let ((ocdpath dun-cdpath))
          (if (not (eq (dun-cd args) -2))
              (dun-ls nil))
          (setq dun-cdpath ocdpath)
          (setq dun-cdroom ocdroom))
        (cond
          ((= ocdroom -10) (dun-ls-inven))
          ((= ocdroom -2) (dun-ls-rooms))
          ((= ocdroom -3) (dun-ls-root))
          ((= ocdroom -4) (dun-ls-usr))
          ((> ocdroom 0) (dun-ls-room))))))

(defun dun-ls-root ()
  (format t "total 4
drwxr-xr-x  3 root     staff           512 Jan 1 1970 .
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 ..
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 usr
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 rooms~%"))

(defun dun-ls-usr ()
  (format t "total 4
drwxr-xr-x  3 root     staff           512 Jan 1 1970 .
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 ..
drwxr-xr-x  3 toukmond restricted      512 Jan 1 1970 toukmond~%"))

(defun dun-ls-rooms ()
  (format t "total 16
drwxr-xr-x  3 root     staff           512 Jan 1 1970 .
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 ..~%")
  (dolist (x dun-visited)
    (format t
            "drwxr-xr-x  3 root     staff           512 Jan 1 1970 ~(~A~)~%"
            (nth x dun-room-shorts))))

(defun dun-ls-room ()
  (format t "total 4
drwxr-xr-x  3 root     staff           512 Jan 1 1970 .
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 ..
-rwxr-xr-x  3 root     staff          2048 Jan 1 1970 description~%")
  (loop for x in (nth dun-cdroom dun-room-objects)
     when (and (>= x 0) (not (= x 255)))
     do (format t "-rwxr-xr-x  1 toukmond restricted        0 Jan 1 1970 ~(~A~)~%"
                (nth x dun-objfiles))))

(defun dun-ls-inven ()
  (format t "total 467
drwxr-xr-x  3 toukmond restricted      512 Jan 1 1970 .
drwxr-xr-x  3 root     staff          2048 Jan 1 1970 ..~%")
  (loop for x in dun-unix-verbs
     when (not (eq (car x) 'impossible))
     do (format t "-rwxr-xr-x  1 toukmond restricted    10423 Jan 1 1970 ~(~A~)~%"
                (car x)))
  (unless dun-uncompressed
    (format t "-rwxr-xr-x  1 toukmond restricted        0 Jan 1 1970 paper.o.Z~%"))
  (loop for x in dun-inventory
     do (format t "-rwxr-xr-x  1 toukmond restricted        0 Jan 1 1970 ~(~A~)~%"
                (nth x dun-objfiles))))

;; (defun dun-echo (args)
;;   (let (nomore var)
;;     (setq nomore nil)
;;     (dolist (x args)
;;       (when (not nomore)
;;         (if (not (string= (substring x 0 1) "$"))
;;             (progn
;;               (dun-mprinc x)
;;               (dun-mprinc " "))
;;             (progn
;;               (setq var (intern (string-upcase (substring x 1))))
;;               (if (not (boundp var))
;;                   (dun-mprinc " ")
;;                   (if (member var dun-restricted)
;;                       (progn
;;                         (dun-mprinc var)
;;                         (dun-mprinc ": Permission denied")
;;                         (setq nomore t))
;;                       (progn
;;                         (dun-mprinc var)
;;                         (dun-mprinc " "))))))))
;;     (dun-mprincl)))

(defun dun-ftp (args)
  (let (host username ident newlist)
    (if (not (car args))
        (dun-mprincl "ftp: hostname required on command line.")
        (progn
          (setq host (car args))
          (if (not (member host '(gamma dun-endgame)))
              (dun-mprincl "ftp: Unknown host.")
              (if (eq host 'dun-endgame)
                  (dun-mprincl "ftp: connection to endgame not allowed")
                  (if (not dun-ethernet)
                      (dun-mprincl "ftp: host not responding.")
                      (progn
                        (dun-mprincl "Connected to gamma. FTP ver 0.9 00:00:00 01/01/70")
                        (setq username (input "Username: "))
                        (if (string= username "toukmond")
                            (dun-mprincl "toukmond ftp access not allowed.")
                            (progn
                              (if (string= username "anonymous")
                                  (dun-mprincl
                                   "Guest login okay, send your user ident as password.")
                                  (dun-mprincl "Password required for " username))
                              (setq ident (input "Password: "))
                              (if (not (string= username "anonymous"))
                                  (dun-mprincl "Login failed.")
                                  (if (= (length ident) 0)
                                      (dun-mprincl "Password is required.")
                                      (progn
                                        (dun-mprincl
                                         "Guest login okay, user access restrictions apply.")
                                        (dun-ftp-commands)
                                        (setq newlist
                                              '("What password did you use during anonymous ftp to gamma?"))
                                        (setq newlist (append newlist (list ident)))
                                        (rplaca (nthcdr 1 dun-endgame-questions) newlist))))))))))))))

(defun dun-ftp-commands ()
  (setq dun-exitf nil)
  (while (not dun-exitf)
    (doverb (input-list "ftp> " '(#\SPACE))
            :verblist dun-ftp-verbs
            :ignore nil
            :error-handler
            #'(lambda (word)
                (declare (ignore word))
                (format t "No such command. Try help."))))
  (setq dun-ftptype 'ascii))

(defun dun-ftptype (args)
  (cond
    ((equal args '(binary))
     (dun-bin nil))
    ((equal args '(ascii))
     (dun-fascii nil))
    (t (format t "Usage: type [binary | ascii]~%"))))

(defun dun-bin (_args)
  (declare (ignore _args))
  (dun-mprincl "Type set to binary.")
  (setq dun-ftptype 'binary))

(defun dun-fascii (_args)
  (declare (ignore _args))
  (dun-mprincl "Type set to ascii.")
  (setq dun-ftptype 'ascii))

(defun dun-ftpquit (_args)
  (declare (ignore _args))
  (setq dun-exitf t))

(defun dun-send (args)
  (match args
         ((filename)
          (let (counter foo)
            (setq foo nil)
            (setq counter 0)

;;; User can send commands!  Stupid user.

            (if (assoc filename dun-unix-verbs)
                (progn
                  (rplaca (assoc filename dun-unix-verbs) 'IMPOSSIBLE)
                  (format t "Sending ~A file for ~A~%" dun-ftptype filename)
                  (format t "Transfer complete.~%"))
                (progn
                  (dolist (x dun-objfiles)
                    (if (eq filename x)
                        (progn
                          (if (not (member counter dun-inventory))
                              (progn
                                (dun-mprincl "No such file.")
                                (setq foo t))
                              (progn
                                (format t "Sending ~A file for ~A, (0 bytes)~%"
                                        dun-ftptype
                                        (cadr (nth counter dun-objects)))
                                (format t "Transfer complete.~%")
                                (if (not (eq dun-ftptype 'binary))
                                    (progn
                                      (if (not (obj-in-room-p 'protoplasm receiving-room))
                                          (dun-replace dun-room-objects receiving-room
                                                       (append (nth receiving-room
                                                                    dun-room-objects)
                                                               (list obj-protoplasm))))
                                      (dun-remove-obj-from-inven counter))
                                    (progn
                                      (dun-remove-obj-from-inven counter)
                                      (dun-replace dun-room-objects receiving-room
                                                   (append (nth receiving-room dun-room-objects)
                                                           (list counter)))))
                                (setq foo t)
                                (dun-mprincl "Transfer complete.")))))
                    (incf counter))
                  (if (not foo)
                      (dun-mprincl "No such file."))))))
         (_ (format t "Usage: send <filename>~%"))))

(defun dun-ftphelp (_args)
  (declare (ignore _args))
  (dun-mprincl "Possible commands are:")
  (dun-mprincl "send    quit    type   ascii  binary   help"))

(defun dun-uexit (_args)
  (declare (ignore _args))
  (setq dungeon-mode 'dungeon)
  (dun-mprincl)
  (dun-mprincl "You step back from the console."))

(defun dun-pwd (_args)
  (declare (ignore _args))
  (dun-mprincl dun-cdpath))

(defun dun-uncompress (args)
  (if (not (car args))
      (dun-mprincl "Usage: uncompress <filename>")
      (progn
        (setq args (car args))
        (if (or dun-uncompressed
                (and (not (string= args "paper.o"))
                     (not (string= args "paper.o.z"))))
            (dun-mprincl "Uncompress command failed.")
            (progn
              (setq dun-uncompressed t)
              (setq dun-inventory (append dun-inventory (list obj-paper))))))))

(defun dun-rlogin (args)
  (let (passwd)
    (if (not (car args))
        (dun-mprincl "Usage: rlogin <hostname>")
        (progn
          (setq args (car args))
          (if (string= args "endgame")
              (dun-rlogin-endgame)
              (if (not (string= args "gamma"))
                  (if (string= args "pokey")
                      (dun-mprincl "Can't rlogin back to localhost")
                      (dun-mprincl "No such host."))
                  (if (not dun-ethernet)
                      (dun-mprincl "Host not responding.")
                      (progn
                        (setq passwd (input "Password: "))
                        (if (not (string= passwd "worms"))
                            (format t "~%login incorrect~%")
                            (progn
                              (dun-mprincl)
                              (princ
                               "You begin to feel strange for a moment, and you lose your items.")
                              (dun-replace dun-room-objects computer-room
                                           (append (nth computer-room dun-room-objects)
                                                   dun-inventory))
                              (setq dun-inventory nil)
                              (setq dun-current-room receiving-room)
                              (dun-uexit nil)))))))))))

(defun dun-cd (args)
  (if (not (car args))
      (dun-mprincl "Usage: cd <path>")
      (let ((tcdpath dun-cdpath)
            (tcdroom dun-cdroom)
            path-elements)
        (setq dun-badcd nil)
        (setq path-elements (dun-get-path (car args) nil))
        (dolist (pe path-elements)
          (when (and (not dun-badcd)
                     (not (string= pe ".")))
            (cond
              ((string= pe "..")
               (cond
                 ((> tcdroom 0)             ;In a room
                  (setq tcdpath "/rooms")
                  (setq tcdroom -2))
                 ((member tcdroom '(-2 -3 -4)
                          :test #'eql) ; In /rooms,/usr,root
                  (setq tcdpath "/")
                  (setq tcdroom -3))
                 ((= tcdroom -10)
                  (setq tcdpath "/usr")
                  (setq tcdroom -4))))
              ((string= pe "/")
               (setq tcdpath "/")
               (setq tcdroom -3))
              ((= tcdroom -4)
               (if (not (string= pe "toukmond"))
                   (dun-nosuchdir)
                   (progn
                     (setq tcdpath "/usr/toukmond")
                     (setq tcdroom -10))))
              ((or (= tcdroom -10) (> tcdroom 0)) (dun-nosuchdir))
              ((= tcdroom -3)
               (cond
                 ((string= pe "rooms")
                  (setq tcdpath "/rooms")
                  (setq tcdroom -2))
                 ((string= pe "usr")
                  (setq tcdpath "/usr")
                  (setq tcdroom -4))
                 (t (dun-nosuchdir))))
              ((= tcdroom -2)
               (let (room-check)
                 (dolist (x dun-visited)
                   (setq room-check (nth x dun-room-shorts))
                   (when (string= room-check pe)
                     (setq tcdpath
                           (format nil "/rooms/~A" room-check))
                     (setq tcdroom x))))
               (when (= tcdroom -2)
                 (dun-nosuchdir))))))
        (if dun-badcd
            -2
            (progn
              (setq dun-cdpath tcdpath)
              (setq dun-cdroom tcdroom)
              0)))))

(defun dun-nosuchdir ()
  (dun-mprincl "No such directory.")
  (setq dun-badcd t))

(defun dun-cat (args)
  (cond
    ((null (setq args (car args)))
     (dun-mprincl "Usage: cat <ascii-file-name>"))
    ((eq args '/)
     (dun-mprincl "cat: only files in current directory allowed."))
    ((and (> dun-cdroom 0) (string= args "description"))
     (dun-mprincl (car (nth dun-cdroom dun-rooms))))
    ((string-match "\\.o" args)
     (let ((doto (match-beginning 0)) checklist)
       (if (= dun-cdroom -10)
           (setq checklist dun-inventory)
           (setq checklist (nth dun-cdroom dun-room-objects)))
       (if (member (cdr (assoc (intern (substring args 0 doto)) dun-objnames))
                   checklist)
           (dun-mprincl "Ascii files only.")
           (dun-mprincl "File not found."))))
    ((assoc args dun-unix-verbs)
     (dun-mprincl "Ascii files only."))
    (t (dun-mprincl "File not found."))))

(defun dun-rlogin-endgame ()
  (if (not (= (dun-score nil) 90))
      (dun-mprincl
       "You have not achieved enough points to connect to endgame.")
      (progn
        (dun-mprincl)
        (dun-mprincl "Welcome to the endgame.  You are a truly noble adventurer.")
        (setq dun-current-room treasure-room)
        (setq dun-endgame t)
        (dun-replace dun-room-objects endgame-treasure-room (list obj-bill))
        (dun-uexit nil))))

(let ((tloc (+ 60 (random 18))))
  (dun-replace dun-room-objects tloc
               (append (nth tloc dun-room-objects) (list 18))))

;;;;
;;;; This section defines the DOS emulation functions for dunnet
;;;;

(defun dun-dos-type (args)
  (sleep 2)
  (if (setq args (car args))
      (if (string= args "foo.txt")
          (dun-dos-show-combination)
          (if (string= args "command.com")
              (dun-mprincl "Cannot type binary files")
              (format t "File not found - ~A~%" args)))
      (dun-mprincl "Must supply file name")))

(defun dun-dos-invd (_args)
  (declare (ignore _args))
  (sleep 1)
  (dun-mprincl "Invalid drive specification"))

(defun dun-dos-dir (args)
  (sleep 1)
  (if (or (not (setq args (car args))) (string= args "\\"))
      (dun-mprincl "
 Volume in drive A is FOO
 Volume Serial Number is 1A16-08C9
 Directory of A:\\

COMMAND  COM     47845 04-09-91   2:00a
FOO      TXT        40 01-20-93   1:01a
        2 file(s)      47845 bytes
                     1065280 bytes free
")
      (dun-mprincl "
 Volume in drive A is FOO
 Volume Serial Number is 1A16-08C9
 Directory of A:\\

File not found")))

(defun dun-dos-boot-msg ()
  (sleep 3)
  (format t "Current time is 00:00:00~%")
  (input "Enter new time: "))

(defun dun-dos-spawn (_args)
  (declare (ignore _args))
  (sleep 1)
  (dun-mprincl "Cannot spawn subshell"))

(defun dun-dos-exit (_args)
  (declare (ignore _args))
  (setq dungeon-mode 'dungeon)
  (dun-mprincl)
  (dun-mprincl "You power down the machine and step back."))

(defun dun-dos-no-disk ()
  (sleep 3)
  (dun-mprincl "Boot sector not found"))

(defun dun-dos-show-combination ()
  (sleep 2)
  (dun-mprincl)
  (dun-mprincl "The combination is " dun-combination "."))

(defun dun-dos-nil (_args)
  (declare (ignore _args))
  nil)

;;;;
;;;; This section defines the save and restore game functions for dunnet.
;;;;

;; (defun dun-save-game (filename)
;;   (if (not (setq filename (car filename)))
;;       (dun-mprincl "You must supply a filename for the save.")
;;     (when (file-exists-p filename) (delete-file filename))
;;     (setq dun-numsaves (1+ dun-numsaves))
;;     (with-temp-buffer
;;       (dun-save-val "dun-current-room")
;;       (dun-save-val "dun-computer")
;;       (dun-save-val "dun-combination")
;;       (dun-save-val "dun-visited")
;;       (dun-save-val "dun-diggables")
;;       (dun-save-val "dun-key-level")
;;       (dun-save-val "dun-floppy")
;;       (dun-save-val "dun-numsaves")
;;       (dun-save-val "dun-numcmds")
;;       (dun-save-val "dun-logged-in")
;;       (dun-save-val "dungeon-mode")
;;       (dun-save-val "dun-jar")
;;       (dun-save-val "dun-lastdir")
;;       (dun-save-val "dun-black")
;;       (dun-save-val "dun-nomail")
;;       (dun-save-val "dun-unix-verbs")
;;       (dun-save-val "dun-hole")
;;       (dun-save-val "dun-uncompressed")
;;       (dun-save-val "dun-ethernet")
;;       (dun-save-val "dun-sauna-level")
;;       (dun-save-val "dun-room-objects")
;;       (dun-save-val "dun-room-silents")
;;       (dun-save-val "dun-inventory")
;;       (dun-save-val "dun-endgame-questions")
;;       (dun-save-val "dun-endgame")
;;       (dun-save-val "dun-cdroom")
;;       (dun-save-val "dun-cdpath")
;;       (dun-save-val "dun-correct-answer")
;;       (dun-save-val "dun-inbus")
;;       (if (dun-compile-save-out filename)
;;           (dun-mprincl "Error saving to file.")
;;         (dun-do-logfile 'save nil)))
;;     (princ "")
;;     (dun-mprincl "Done.")))

;; (defun dun-compile-save-out (filename)
;;   (let (ferror)
;;     (setq ferror nil)
;;     (condition-case nil
;; 	(dun-rot13)
;;       (error (setq ferror t)))
;;     (if (not ferror)
;; 	(progn
;; 	  (goto-char (point-min))))
;;     (condition-case nil
;;         (write-region 1 (point-max) filename nil 1)
;;       (error (setq ferror t)))
;;     (kill-buffer (current-buffer))
;;     ferror))


;; (defun dun-save-val (varname)
;;   (let ((value (symbol-value (intern varname))))
;;     (dun-minsert "(setq " varname " ")
;;     (if (or (listp value)
;; 	    (symbolp value))
;; 	(dun-minsert "'"))
;;     (if (stringp value)
;; 	(dun-minsert "\""))
;;     (dun-minsert value)
;;     (if (stringp value)
;; 	(dun-minsert "\""))
;;     (dun-minsertl ")")))


;; (defun dun-restore (args)
;;   (let (file)
;;     (if (not (setq file (car args)))
;; 	(dun-mprincl "You must supply a filename.")
;;         (if (not (dun-load-d file))
;; 	    (dun-mprincl "Could not load restore file.")
;; 	    (dun-mprincl "Done.")
;; 	    (setq dun-room 0)))))


;; See gamegrid-add-score; but that only handles a single integer score.
;; (defun dun-do-logfile (type how)
;;   (let (ferror)
;;     (with-temp-buffer
;;       (condition-case err
;;           (if (file-exists-p dun-log-file)
;; 	      (insert-file-contents dun-log-file)
;; 	      (let ((dir (file-name-directory dun-log-file)))
;; 	        (if dir (make-directory dir t))))
;;         (error
;;          (setq ferror t)
;;          (dun-mprincl (error-message-string err))))
;;       (when (null ferror)
;;         (goto-char (point-max))
;;         (dun-minsert (current-time-string) " " (user-login-name) " ")
;;         (if (eq type 'save)
;;             (dun-minsert "saved ")
;;             (if (= (dun-endgame-score) 110)
;;                 (dun-minsert "won ")
;;                 (if (not how)
;;                     (dun-minsert "quit ")
;;                     (dun-minsert "killed by " how " "))))
;;         (dun-minsert "at " (cadr (nth (abs dun-room) dun-rooms)) ". score: ")
;;         (if (> (dun-endgame-score) 0)
;;             (dun-minsert (+ 90 (dun-endgame-score)))
;;             (dun-minsert (dun-reg-score)))
;;         (dun-minsertl " saves: " dun-numsaves " commands: " dun-numcmds)
;;         (write-region 1 (point-max) dun-log-file nil 1)))))

(defun main-loop ()
  (setq dun-dead nil)
  (setq dun-room 0)
  (while (not dun-dead)
    (when (eq dungeon-mode 'dungeon)
      (when (not (= dun-room dun-current-room))
        (dun-describe-room dun-current-room)
        (setq dun-room dun-current-room))
      (doverb (input-list ">")))))

(defun dun-dos-interface ()
  (dun-dos-boot-msg)
  (setq dungeon-mode 'dos)
  (while (eq dungeon-mode 'dos)
    (doverb (input-list "A> " '(#\SPACE))
            :ignore nil
            :verblist dun-dos-verbs
            :error-handler
            #'(lambda (verb)
                (declare (ignore verb))
                (sleep 1)
                (format t "Bad command or file name~%"))))
  (dun-mprincl))

(defun dun-unix-interface ()
  (dun-login 4)
  (when dun-logged-in
    (setq dungeon-mode 'unix)
    (while (eq dungeon-mode 'unix)
      (doverb (input-list "$ " '(#\SPACE))
              :ignore nil
              :verblist dun-unix-verbs
              :error-handler
              #'(lambda (verb)
                  (format t "~(~A~): not found.~%" verb))))
    (dun-mprincl)))

(defun dungeon-nil (_arg)
  (declare (ignore _arg))
  nil)

(defun dun-dungeon ()
  (setq dun-visited '(27))
  (dun-mprincl)
  (main-loop))

(main-loop)

breed [cars car]
breed [scooters scooter]
breed [customers customer]

globals                    ;; Setup global variables
[
  grid-size-x              ;; Number of grids of streets in x direction
  grid-size-y              ;; Number of grids of streets in y direction
  grid-x-inc               ;; the amount of patches in between two roads in the x direction
  grid-y-inc               ;; the amount of patches in between two roads in the y direction
  roads                    ;; agentset containing the patches that are roads
  ; optimizations
  min-trip-length
]

turtles-own [
  origin                   ;; where originally found
  distance-traveled
]

customers-own[
  destination
  wait-time
]

cars-own [
  paid-distance
]

;;;;;;;;;;;;;;;;;;;;;;
;; Setup Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;
to setup
  clear-all
  setup-globals
  setup-patches
  setup-cars num-cars
  if enable-scooters [setup-scooters num-scooters]
  setup-customers num-customers ; for now no new customers
  reset-ticks
end

to setup-globals
  set grid-size-x 9           ;; road grid-size-x for enviornment
  set grid-size-y 9           ;; road grid-size-y for enviornment
  set grid-x-inc world-width / grid-size-x
  set grid-y-inc world-height / grid-size-y
  ; optimizations
  set min-trip-length 20
end

to setup-patches
  ask patches [
    set pcolor brown + 3
  ]
  set roads patches with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  ask roads [ set pcolor white ]
end

; place cars on road
to setup-cars [_num-cars]
  create-cars _num-cars [
    set shape "car"
    move-to one-of roads with [ not any? turtles-on self ]
  ]
end

; place scooters on road (with valets)
to setup-scooters [_num-scooters]
  create-scooters _num-scooters [
    set shape "flag"
    move-to one-of roads with [ not any? turtles-on self ]
  ]
end

; generate customers each with a trip
to setup-customers [ _num-customers ]
  create-customers _num-customers [
    set shape "person"
    let _trip gen-trip
    set origin item 0 _trip
    set destination item 1 _trip
    move-to origin
  ]
end

; recursively generate a random trip exceeding minimum distance
to-report gen-trip
  ; Find all patches where there can be a be a source or destination (not on road)
  let goal-candidates patches with [ pcolor = 38 and any? neighbors with [ pcolor = white ] ]
  ;; choose at random a source location
  let src one-of goal-candidates
  ;; choose at random a location for the destination
  let dst one-of goal-candidates with [ self != src ]
  let trip ( list src dst )
  while [trip-length trip < min-trip-length] [set trip gen-trip]
  report trip
end

; get length of trip generated in gen-trip
to-report trip-length [trip]
  report [distance item 0 trip] of item 1 trip
end

;;;;;;;;;;;;;;;;;;;;;;;;
;; Runtime Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;

to go
  links-to-cars
  ask scooters [
    move-to next-scooter-patch
  ]
  ask customers [
    move-to next-customer-patch
    ; remove customers that have completed trips
    if member? destination neighbors [die]
  ]
  ask cars [
    move-to next-car-patch
  ]
  tick ; for gathering stats?
end

; link scooters to cars and link customers to cars
to links-to-cars
  ; a carless scooter is a scooter with no link (to a car)
  let carless-scooters scooters with [not any? link-neighbors]
  ; a scooterless car is a car with no link to a scooter (and no customer on-board)
  let scooterless-cars cars with [count link-neighbors = 0]
  ; link a scooter to closest car (only if there is an unlinked customer)
  ; a carless customer is a customer with no link to a car
  let carless-customers customers with [not any? link-neighbors]
  if any? carless-scooters and any? scooterless-cars and any? carless-customers
    [ask one-of carless-scooters [
      create-link-with min-one-of scooterless-cars [distance myself]
    ]
  ]
  ; a customerless car is a car with a link to a scooter but no link to a customer
  let customerless-cars cars with [count link-neighbors = 1 and is-scooter? one-of link-neighbors]
  ; link a customer to closest car
  if any? carless-customers and any? customerless-cars [ask one-of carless-customers [
    create-link-with min-one-of customerless-cars [distance myself]
  ]]
end

; move scooter
; move toward linked car, then move toward linked customer
; remove link when arrived at customer
to-report next-scooter-patch ; scooter method
  let choice patch-here
  let choices neighbors with [ pcolor = white ]
  ask link-neighbors [ ; get the car linked to the scooter (only 0 or 1 links)
    ; only move if there is a customer (todo: optimization: move to car )
    let linked-customer one-of link-neighbors with [is-customer? self]
    if linked-customer != nobody [
      let on-board? patch-here = [patch-here] of myself
      let car-in-range? member? [patch-here] of myself [ neighbors ] of patch-here
      ; if on board car, move towards origin
      ifelse car-in-range? or on-board? [
;        show (word myself " moving toward " linked-customer)
        set choice min-one-of choices [ distance [patch-here] of linked-customer ]
      ]
      [
        ; move towards car
;        show (word myself " moving toward car " self)
        set choice min-one-of choices [ distance myself ]
      ]
      ; remove link to car if arrived at customer
      let near-customer? member? [patch-here] of linked-customer [ neighbors ] of patch-here
      if near-customer? [
        let scooter-self myself
;        show word "removing link to " scooter-self
        ask links with [member? scooter-self both-ends] [ die ]
      ]
    ]
  ]
;  show (word "choice=" choice " choices=" choices )
  report choice
end

; move car
; follow linked scooter or customer once in range
to-report next-car-patch ; car method
  let choice patch-here
  ask link-neighbors [ ; linked to 0 or 1 customer and 0 or 1 scooter
    let in-range-of-car? member? patch-here [ neighbors ] of [patch-here] of myself
    let on-board? patch-here = [patch-here] of myself
;    show ( word "in-range-of-car?=" in-range-of-car? " on-board?=" on-board? )
    if in-range-of-car? or on-board? [
;      show (word myself " following " self)
      set choice patch-here
    ]
  ]
;  show (word "choice=" choice )
  report choice
end

; move customer
; if car in range, move to car (onboard)
; if onboard, move towards destination
; if customer arrives at destination, release customer
to-report next-customer-patch ; customer method
  let choice patch-here
  let choices neighbors with [ pcolor = white ]
  let dest destination
  ask link-neighbors [ ; linked to only 0 or 1 car
    let on-board? patch-here = [patch-here] of myself
    ifelse on-board? [
      set choice min-one-of choices [ distance  dest]
    ][
      let car-in-range? member? patch-here [ neighbors ] of [patch-here] of myself
      if car-in-range? [ ; move to car
        set choice patch-here
      ]
    ]
    ; remove customer (and link to car) if arrived at destination
    let dest-in-range? member? dest neighbors
    if dest-in-range? [
      let customer-self myself
;      show word "removing link to " customer-self
      ask links with [member? customer-self both-ends] [ die ]
    ]
  ]
;  show (word "choice=" choice )
  report choice
end

;; car must have a brain to move
;; ie, a scooter or customer on board
;to-report has-brain? ; car method
;  let is-brained false
;  ask link-neighbors [
;;      show self
;      if patch-here = [patch-here] of myself [set is-brained true]
;  ]
;  report is-brained
;end
;
;; get turtle providing brain
;to-report get-brain ; car method
;  let brain nobody
;  ask link-neighbors [
;;      show self
;      if patch-here = [patch-here] of myself [set brain self]
;  ]
;  report brain
;end

; get goal of car from customer trip
to-report get-goal ; car method
  let goal patch-here
  ask link-neighbors [
    if patch-here = [patch-here] of myself [ ; brain on board
      ifelse is-scooter? self [
        ; find customer origin
        set goal [origin] of one-of [link-neighbors with [is-customer? self]] of myself
      ][
        set goal destination ; customer destination
      ]
    ]
  ]
  report goal
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
699
500
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-18
18
-18
18
0
0
1
ticks
30.0

BUTTON
12
67
78
100
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
11
148
183
181
num-cars
num-cars
0
100
2.0
1
1
NIL
HORIZONTAL

SLIDER
11
183
183
216
num-scooters
num-scooters
0
50
1.0
1
1
NIL
HORIZONTAL

SWITCH
12
10
174
43
enable-scooters
enable-scooters
0
1
-1000

SLIDER
11
114
183
147
num-customers
num-customers
0
100
2.0
1
1
NIL
HORIZONTAL

BUTTON
143
67
206
100
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
79
67
142
100
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@

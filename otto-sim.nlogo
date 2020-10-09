extensions [ gis nw ]
breed [ points point ]
breed [cars car]
cars-own [speed ; mph
  available? location]
undirected-link-breed [segments segment]
segments-own [ seg-length ] ; used to find shortest route
; customers, valets and carowners have a location that is initialized to a point
breed [customers customer]
breed [valets valet]
breed [carowners carowner]
customers-own [location wait-time payments]
valets-own [available? delivery earnings location wait-time valet-step-num]
carowners-own [owner-cars earnings location]
undirected-link-breed [trips trip]
trips-own [trip-route]

globals [
  city-dataset
  route-car ; for moving along route
  step-length ; miles
]

; called at model load
to startup
  init-model
end

to init-model
  no-display
  clear-all
  ask patches [set pcolor black + 2]
  load-map
  build-road-network
  display
end

to load-map
  ; GIS file downloaded from https://www.santamonica.gov/isd/gis
  ; https://gis-smgov.opendata.arcgis.com/datasets/street-centerlines
  ; Map must consist of one layer containing a list of one or more intersecting polylines
  ; with or without metadata.
  let city "santa_monica"
  let project "Street_Centerlines"
  let path (word "data/" city "/" project)
  ; Note that setting the coordinate system here is optional, as
  ; long as all of your datasets use the same coordinate system.
  gis:load-coordinate-system (word path ".prj")
  ; Load all of our datasets
  set city-dataset gis:load-dataset (word path ".shp")
  ; Set the world envelope to the union of all of our dataset's envelopes
  gis:set-world-envelope (gis:envelope-of city-dataset)
end

to clear-setup
  clear-globals
  clear-ticks
;  clear-turtles
  ask valets [die]
  ask customers [die]
  ask cars [die]
  ask trips [die]
;  clear-patches
;  clear-links
  ask points with [hidden? = false] [
  set hidden? true
  set color grey]
  ask segments [set color grey]
  clear-drawing
  clear-all-plots
  clear-output
end

to setup
  clear-setup
  set step-length .2
  create-valets num-valets [
    set shape "flag"
    set color grey
    set location one-of points
    setxy [xcor] of location [ycor] of location
    set available? true
    set earnings 0
  ]
  create-customers num-customers [
    set shape "person"
    set color black
    set location one-of points
    setxy [xcor] of location [ycor] of location
    set hidden? true
  ]
  ; create cars last to use end2 for direction (until adopt directional links)
  create-cars num-carowners [
    set shape "car top"
    set speed 20
    set color grey
    set location one-of points
    setxy [xcor] of location [ycor] of location
  ]
;  set route-car one-of cars ; for now
;  ask route-car [set color white]

  reset-ticks
end

;*********************************************************************************************
; go
;*********************************************************************************************

to go
  ask customers [
    ; randomly create a trip
    if create-trip?
    [if create-trip = false [increment-wait 10]] ; estimated time penalty for no cars available
    ; if trip created and not delivered, wait for car
    if waiting-for-car? [increment-wait 1]
    ; if in car, take step to destination
    if customer-in-car? [take-step-on-route]
    ; if arrived at destination, pay and remove trip
    if customer-arrived? [end-customer-trip]
  ]

  ask valets[
    ; if deliveries available, pick one otherwise wait
    ifelse deliveries-available?
    [ if valet-picked-car? = false [ increment-wait 1 ] ]
    [ increment-wait 1 ]
    ; if in-delivery, either scooter to car, or drive to customer
    if valet-on-scooter? [valet-step-to-car]
;    if valet-in-car? [valet-step-to-customer]
;    ; if arrived at customer, complete delivery
;    if valet-arrived-at-customer? [complete-delivery]
  ]

  ask cars [
    ; if route available, step towards destination, otherwise wait
  ]

  ask carowners [
    ; if car unavailable, randomly make available
    ; if car available, randomly make unavailable
    ; if car active, randomly request return
    ; if return requested, wait
    ; if car returned, make unavailable
  ]

  tick

end
;*********************************************************************************************

to-report valet-on-scooter?
  report delivery-selected? and not valet-arrived-at-car?
end

to valet-step-to-car
  let route [trip-route] of one-of my-links
  let route-length route-distance route
  let num-steps round(route-length / step-length)
  if num-steps > valet-step-num [
      take-step route valet-step-num
  ]
  set valet-step-num valet-step-num + 1
end

to-report valet-in-car?
  report delivery-selected? and valet-arrived-at-car?
end

to valet-step-to-customer

end

; check that valet has an active delivery
to-report delivery-selected?
  report count my-links = 1
end

to-report valet-arrived-at-car?
  let car-to-deliver [end2] of one-of my-links ; valet has one link
  let car-location [location] of car-to-deliver
  report distance-between location car-location = 0
end

to-report valet-arrived-at-customer?
  let car-to-deliver [end2] of one-of my-links ; valet has one link
  let car-location [location] of car-to-deliver
  report distance-between location car-location = 0
end

to complete-delivery

end

to take-step [route step-num]
  let current-distance step-num * step-length
  let current-segment find-segment route current-distance
  ; find point on route to position car
  let next-pointXY point-at-distance-on-segment current-segment step-length
  let x item 0 next-pointXY
  let y item 1 next-pointXY
  let end-point [end2] of current-segment
  face end-point
  setxy x y
end

to drive-route [src dst]
  ask segments with [color = white or color = red] [set color gray]
  ask route-car [set hidden? false]
  let route calc-route src dst
  ifelse route = false [stop][
    display-route route red
    let rdistance route-distance route
    ; move a car a fixed distance along route
    ; speed is in MPH
    ; distance is in miles
    let route-speed [speed] of route-car
    ; tick is equivalent to distance/speed = .2/20 = 2/200 = 0.01 hours = 0.6 minutes = 36 seconds
    let num-steps round(rdistance / step-length)
    let duration rdistance / route-speed ; hours

    show (word "rdistance:" rdistance " num steps:" num-steps " duration:" duration )
    let remaining-steps num-steps
    while [remaining-steps >= 0] [
      let current-distance (num-steps - remaining-steps) * step-length
      let current-segment find-segment route current-distance
      ask current-segment [set color white]
      ; find point on route to position car
      ; TODO add route stepper to avoid overstep
      let carXY point-at-distance-on-segment current-segment step-length
      let x item 0 carXY
      let y item 1 carXY
      let end-point [end2] of current-segment
      ask route-car [face end-point]
;      let x [xcor] of end-point
;      let y [ycor] of end-point
      ask route-car [setxy x y]

        set remaining-steps remaining-steps - 1
  ;      let remaining-distance route-distance - num-steps * step-length
  ;      let remaining-duration duration - remaining-distance / route-speed
  ;      show (word "current-distance: " current-distance  " remaining-distance: " remaining-distance " remaining-duration: " remaining-duration)
;      show (word "current-distance: " current-distance )
      ; TODO add tick to update analytics
    ]
  ]
end

to-report deliveries-available?
  ; count cars with customer trips that have not been claimed by valets
  report count cars with [count my-links = 1] > 0
end

; should be valet-pick-car, but because some segments of road are not connected,
; we have to do it this way until fixed
to-report valet-picked-car?
  let nearest-car find-nearest-valet-car
  let route calc-route location [location] of nearest-car
  ifelse route = false
  [ report false]
  [ create-trip-with nearest-car
    [ set trip-route route
      set shape "trip"
      display-route trip-route yellow
    ]
    set color yellow
    report true
  ]
end

; condidition to create a trip randomly
; may expand to simulate a demand curve
to-report create-trip?
  report not trip-created? and ticks mod 20 = 0 and random-float 1 <= trip-frequency
end

; trip created
to-report trip-created?
  report  count my-links > 0
end

; waiting for car
to-report waiting-for-car?
  report trip-created? and not customer-in-car?
end

; customer in car
to-report customer-in-car?
  ifelse trip-created? [
    let my-car [end2] of one-of my-trips
    report not in-car? my-car
  ][report false]
end

to-report customer-arrived?
  ; check if reached end-of-route
  ifelse trip-created? [
    let my-route [trip-route] of one-of my-trips
    let dst [end2] of last my-route
    report equal-points? location dst
  ][report false]
end

; may not correspond to actual time
to increment-wait [time]
  set wait-time wait-time + time
end

to-report create-trip
  let nearest-car find-nearest-customer-car
  ifelse nearest-car = false
  [ report false]
  [ ask nearest-car [set color white]
    create-trip-with nearest-car
    [ set trip-route calc-route-with-rnd-dst [location] of myself
      set shape "trip"
      display-route trip-route red
    ]
    set color white
    set hidden? false
    report true
  ]
end

to-report find-nearest-customer-car
  ; sometimes there is no route to nearest car, so go on to next closest car in the hope that
  ; some cars will not be isolated (until problem found)
  let available-cars filter-cars-by-link-count sort-cars-by-increasing-distance 0
  ifelse empty? available-cars [report false][report first available-cars]
;  report min-one-of cars [distance-between location [location] of myself] may restore this when problem solved
end

to-report find-nearest-valet-car
  let available-cars filter-cars-by-link-count sort-cars-by-increasing-distance 1
  ifelse empty? available-cars [report false][report first available-cars]
end

; link-count means 0: available, 1: customer selected, 2: valet selected
; used to prevent a car from getting selected by more than one customer and valet (and in the right order)
to-report filter-cars-by-link-count [unfiltered-cars link-count]
  report filter [ unfiltered-car -> (count [my-links] of unfiltered-car) = link-count ] unfiltered-cars
end

to-report sort-cars-by-increasing-distance
  report sort-by [ [car1 car2] ->
    distance-between location [location] of car1 <
    distance-between location [location] of car2
  ] [self] of cars
end

to end-customer-trip
  ; cleanup and pay
  ask my-trips [die]
  set wait-time 0
  set hidden? true
  set payments payments + 1
end

; Load network of GIS polyline data into points connected by segments
; A segment is used to link points along a polyline
; A single point is used where one or more polylines intersect
to build-road-network
  ask points [ die ]
  ; only one vector feature (I think)
  foreach gis:feature-list-of city-dataset [ vector-feature ->
    foreach gis:vertex-lists-of vector-feature [ vertex ->
      ; a vertex contains 2 or more points (like a polyline)
      let first-point nobody ; used at beginning of polyline
      let previous-point nobody
      foreach vertex [ latlng ->
        ; a location has 2 coordinates (x and y)
        let coord gis:location-of latlng
        ; coord will be an empty list if it lies outside the
        ; bounds of the current NetLogo world, as defined by our
        ; current GIS coordinate transformation
        if not empty? coord
        [ let x item 0 coord
          let y item 1 coord
          ; find if a point already exists at this coord
          let existing-point one-of points with [xcor = x and ycor = y]
          ifelse existing-point = nobody
          [ ifelse first-point = nobody
            [ ; start of polyline
              create-points 1
              [ set hidden? true
                setxy x y
                set first-point self
                set previous-point self
              ]
            ][ ; end of segment
              create-points 1
              [ set hidden? true
                setxy x y
                create-segment-with previous-point [ set seg-length link-length ]
                set previous-point self
              ]
            ]
          ][ifelse first-point = nobody
            [
              ; first point already exists so no need to create a point
              set first-point existing-point
              set previous-point existing-point
            ][
              ; connect previous segment end to existing point
              ask existing-point [create-segment-with previous-point [set seg-length link-length]]
              set previous-point existing-point
            ]
          ]
        ]
      ]
    ]
  ]
end



; take a step to destination
to take-step-on-route
  ; TBD
end

; returns a list of segments or false if no route found
to-report calc-route [src dst]
  ; route will sometimes fail (maybe due to breaks in network)
  let route false
  ask src [set route nw:weighted-path-to dst seg-length]
  report route
end

; generate a list of points along a route from points [src] to [dst]
; if no route founds returns the empty list
; this is useful because segments have implicit direction and may not be in the correct order
; plus it makes it easier to step along the route using points instead of segments
; and in other operations on routes
to-report calc-route-points [src dst]
  let route false
  ask src [set route nw:turtles-on-weighted-path-to dst seg-length]
  ifelse route = false
  [report []]
  [report route]
;  ifelse route = false [report []]
;  [
;    ; extract the route's points from the segments
;    let route-points []
;    let previous-point src
;    foreach route [seg ->
;      ; find which end of segment comes next
;      let seg-start [end1] of seg
;      let seg-end [end2] of seg
;      ifelse seg-start = previous-point
;      [ set route-points lput seg-start route-points
;        set previous-point seg-start
;      ]
;      [ set route-points lput seg-end route-points
;        set previous-point seg-end
;      ]
;    ]
;    set route-points lput dst route-points
;    report route-points
;  ]
end

;*********************************************************************************************
; helpers
;*********************************************************************************************

to-report distance-between [src dst]
  let route calc-route src dst
  ; some number larger than any possible other route distance in this world
  ; (because some route calcs fail and this method is expected to be used to find a min)
  if route = false [report 1000000000]
  report route-distance route
end

; reports road point underlying x,y
to-report road-pointxy-here [x y]
  report one-of points with [xcor = x and ycor = y] ; expect only none or one
end

to-report equal-points? [p1 p2]
  let p1X [xcor] of p1
  let p1Y [ycor] of p1
  let p2X [xcor] of p2
  let p2y [ycor] of p2
  report p1X = p2Y and p1Y = p2Y
end

; report if car in same spot as this agent
to-report in-car? [this-car]
  let carX [xcor] of this-car
  let carY [ycor] of this-car
  report xcor = carX and ycor = carY
end

to-report calc-route-with-rnd-dst [src]
  let route false
  while [route = false][
    let dst other-point src
    set route calc-route src dst
  ]
  report route
end

; guarantee a different point
to-report other-point [src]
  let dst one-of points
  while [src = dst] [set dst one-of points]
  report dst
end

to-report route-distance [route]
  report sum map [seg -> [seg-length] of seg] route
end

to display-route [route route-color]
  let src [end1] of first route
  let dst [end2] of last route
  ask src [
  set hidden? false
  set shape "circle 3"
  set color red]
ask dst [
  set hidden? false
  set shape "square 3"
  set color red]
  foreach route [seg -> ask seg [set color route-color]]
end

to hide-route [route]
  foreach route [seg -> ask seg [set color grey]]
end

; find segment at [distance-along] [route]
to-report find-segment [route distance-along]
  let found-seg nobody
  let current-distance 0
  foreach route [seg ->
    set found-seg seg
    set current-distance current-distance + [seg-length] of seg
    if current-distance > distance-along [report found-seg ]
  ]
  report found-seg
end

; get point at a distance along a segment
to-report point-at-distance-on-segment [ seg dist ]
  let seg-len [seg-length] of seg
  let start-point [end1] of seg
  let end-point [end2] of seg
  let startx [xcor] of start-point
  let starty [ycor] of start-point
  let endx [xcor] of end-point
  let endy [ycor] of end-point
  let x startx + (endx - startx) * dist / seg-len
  let y starty + (endy - starty) * dist / seg-len
  report list x y
end

;*********************************************************************************************
; debug
;*********************************************************************************************

to show-route
  ; get two random points and calculate route
  ; Note: still get some unroutable points. May need to smooth out data before import
  ask points with [hidden? = false] [
    set hidden? true
    set color grey]
  ask segments with [color = red] [set color gray]
  let src one-of points
  let dst other-point src
  let route calc-route src dst
  if route != false [display-route route red]
end

to show-route-using-points
    ask points with [hidden? = false] [
    set hidden? true
    set color grey]
  ask segments with [color = red] [set color gray]
  let src one-of points
  let dst other-point src
  let route calc-route-points src dst
  display-route-by-points route red
end

; find segments at [route-point]
to-report find-segments-at-point [route-point]
  report [my-segments] of route-point
end

; find the set of segments intersecting route
to-report find-segments-intersecting-route [candidate-segments route]
  ; find segments where both ends are on route
  let intersecting-segments []
  ask candidate-segments [
    if member? end1 route and member? end2 route
    [set intersecting-segments fput self intersecting-segments]
  ]
  report links with [member? self intersecting-segments]
end

to display-route-by-points [route route-color]
  if not empty? route [
    let src first route
    let dst last route
    ask src [
      set hidden? false
      set shape "circle 3"
      set color red]
    ask dst [
      set hidden? false
      set shape "square 3"
      set color red]
    foreach route [route-point ->
      ; find segments at point of route
      let segs find-segments-at-point route-point
      ; find which segmens are on route
      let intersecting-segs find-segments-intersecting-route segs route
      ask intersecting-segs [set color route-color]
    ]
  ]
end

; show points with num connections (debug)
to show-edge-points [num-links]
  ask points [if count my-links = num-links [set hidden? false]]
end

; show links connected to center-point for link-distance (debug)
to show-links [center-point link-distance]
  let point-links [my-links] of center-point
  ask point-links [
    set color white
    ; recursively show next level of links
   if link-distance >= 0 [
;      show-links end1 link-distance - 1
      show-links end2 link-distance - 1
    ]
  ]
end

; unused

;to-report distance-to-car [src] ; car reporter
;  report distance-between src location
;  let route-to-car calc-route src location
;  ; some number larger than any possible other route distance in this world
;  if route-to-car = false [report 1000000000]
;  report route-distance route-to-car
;end

; road point here?
;to-report road-point-here? [this-point]
;  let x [xcor] of this-point
;  let y [ycor] of this-point
;  report road-pointxy-here x y != nobody
;end

;to-report calc-route-rnd
;  let route false
;  while [route = false][
;    let src one-of points
;    let dst other-point src
;    show word src dst
;    set route calc-route src dst
;  ]
;  report route
;end

;to-report calc-route-rnd-src [dst]
;  let route false
;  while [route = false][
;    let src other-point dst
;    set route calc-route src dst
;  ]
;  report route
;end
@#$#@#$#@
GRAPHICS-WINDOW
215
10
1016
630
-1
-1
13.0
1
10
1
1
1
0
0
0
1
-30
30
-23
23
0
0
1
ticks
30.0

BUTTON
35
160
95
193
Setup
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

BUTTON
40
365
159
399
NIL
show-route
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
15
115
187
148
num-carowners
num-carowners
0
100
1.0
1
1
NIL
HORIZONTAL

SLIDER
15
80
187
113
num-valets
num-valets
0
100
1.0
1
1
NIL
HORIZONTAL

SLIDER
15
10
187
43
num-customers
num-customers
0
100
1.0
1
1
NIL
HORIZONTAL

BUTTON
100
160
165
193
Go
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

TEXTBOX
795
75
1195
100
Santa Monica, CA
20
7.0
1

SLIDER
15
45
187
78
trip-frequency
trip-frequency
0
1
1.0
0.1
1
NIL
HORIZONTAL

PLOT
1085
85
1285
235
Average Wait Time
Time
Wait Time
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"C" 1.0 0 -16777216 true "" "plot mean [wait-time] of customers"
"V" 1.0 0 -1184463 true "" "plot mean [wait-time] of valets"

BUTTON
70
300
133
333
Step
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

BUTTON
10
405
202
438
NIL
show-route-using-points
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

car top
true
15
Polygon -1 true true 151 8 119 10 98 25 86 48 82 225 90 270 105 289 150 294 195 291 210 270 219 225 214 47 201 24 181 11
Polygon -16777216 true false 210 195 195 210 195 135 210 105
Polygon -16777216 true false 105 255 120 270 180 270 195 255 195 225 105 225
Polygon -16777216 true false 90 195 105 210 105 135 90 105
Polygon -1 true true 205 29 180 30 181 11
Line -7500403 false 210 165 195 165
Line -7500403 false 90 165 105 165
Polygon -16777216 true false 121 135 180 134 204 97 182 89 153 85 120 89 98 97
Line -16777216 false 210 90 195 30
Line -16777216 false 90 90 105 30
Polygon -1 true true 95 29 120 30 119 11

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

circle 3
false
0
Circle -1 false false 90 90 118

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

square 3
false
0
Rectangle -1 false false 90 90 210 210

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

trip
10.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@

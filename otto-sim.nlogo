extensions [ gis nw ]

; road map is a netork of points linked by segments
breed [ points point ]
points-own [
  in-network? ; member of road network
]
undirected-link-breed [segments segment]
segments-own [
  seg-length ; Used by nw extension to find shortest route thru points on the road network.
]

; cars travel along the road network
; a car can be reserved by:
;  1. a customer, if available by car owner, in-service, not claimed by a valet and not in use (ie, on a trip), for a ride to a random destination
;  2. the operator, if available by car owner, not claimed by a valet, and not in use, for repositioning or returning to car-owner
; when reserved a route is recorded, if requested by a customer, the customer is recorded
; if reserved by a customer the destination is the same location as the customer (to confirm delivery)
; a valet can claim a car if reserved and unclaimed by other valets
; the car moves when the route is loaded into a trip
; a car can have one out-going trip (and one in-coming trip from valet)
; a car owner can set availability randomly
; if made available the car can be taken in and out of service by operator based on demand
; if not available and in service, the operator will reserve a trip to car owner
; if not available and in service and delivered to car owner, car is taken out of service
breed [cars car]
cars-own [
  speed ; mph
  available-by-car-owner? ; set by car-owner to add/remove fleet in service
  in-service? ; set by car-owner and used by operator
  reserved? ; when booked by a customer (or the operator)
  car-route ; required when reserving
  car-customer ; if reserved by customer we need to know who to hand-off to at destination
  car-owner ; when reserved for return, who to return car to (set on creation)
  valet-claimed? ; used by valet
  car-passenger ; either the customer, the valet or nobody
  car-step-num ; current step along a route (for simulating speed)
  wait-time ; time spent waiting while in service
  location
]

; the start of a trip is a customer, car, or valet
; the end of a trip is a customer or a random customer destination
directed-link-breed [trips trip]
; a trip has a route
trips-own [trip-route]

; a customer can have one out-going trip to a random destination
; and one in-comming trip from a car
breed [customers customer]
customers-own [location wait-time payments]
; a valet can have one out-going trip to a car or to a customer
breed [valets valet]
valets-own [available?
  delivery-status ; 'to-car' or 'to-customer', used when intransit (during a delivery)
  earnings wait-time
  valet-step-num ; current step along a route (during delivery)
]
breed [carowners carowner]
carowners-own [owner-cars earnings location]

globals [
  city-dataset
  step-length ; miles
]

; called at model load
to startup
  init-model
end

to init-model
;  no-display
  clear-all
  ask patches [set pcolor black + 2]
  load-map
  build-road-network
;  display
end

to load-map
  ; GIS file downloaded from https://www.santamonica.gov/isd/gis
  ; https://gis-smgov.opendata.arcgis.com/datasets/street-centerlines
  ; Map must consist of one layer containing a list of one or more intersecting polylines
  ; with or without metadata.
  ; used https://mapshaper.org/ console to 'clean' and 'dissolve'. Also use simplify feature.
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

; clear without removing road network
to clear-setup
  clear-globals
  clear-ticks
;  clear-turtles
  ask valets [die]
  ask customers [die]
  ask carowners [die]
  ask cars [die]
  ask trips [die]
;  clear-patches
;  clear-links
  ask points with [hidden? = false and color != grey] [
    set hidden? true
    set color grey]
  ask segments with [color != grey] [set color grey]
  clear-drawing
  clear-all-plots
  clear-output
end

; setup model starting scenario
; color coding:
;  customer: red
;  valet: yellow
;  cars: yellow if used by valet, red if by customer
;  all start out grey
to setup
  clear-setup
  set step-length .2
  create-valets num-valets [
    set color grey
    set shape "person"
    let src random-road-point
    setxy [xcor] of src [ycor] of src
    set available? true
    set earnings 0
    set valet-step-num 0
  ]
  create-customers num-customers [
    set hidden? true
    set color grey
    set shape "person"
    set location random-road-point
    setxy [xcor] of location [ycor] of location
  ]
  create-carowners num-carowners[
    set hidden? true
    set color grey
    set shape "person"
    let car-point random-road-point
    setxy [xcor] of car-point [ycor] of car-point
  ]
  car-creator ; each car owner has one car (for now)

  reset-ticks
end

to car-creator
  ask carowners[
    hatch-cars 1 [ ; each car owner has one car (for now)
      set color grey
      set shape "car top"
      set hidden? false
      set location random-road-point
      setxy [xcor] of location [ycor] of location
      set speed 20
      set available-by-car-owner? true
      set in-service? true
      set reserved? false
      set car-route []
      set car-customer nobody
      set car-owner myself
      set valet-claimed? false
      set car-passenger nobody
      set car-step-num 0
      set wait-time 0
    ]
  ]
end

;*********************************************************************************************
; go
;*********************************************************************************************

to go
  ask customers [
    ; randomly create a trip
    if create-customer-trip?
    [if create-customer-trip = false [increment-wait 10]] ; estimated time penalty for no cars available
    ; if trip created and not delivered, wait for car
    if customer-waiting-for-car? [increment-wait 1]
;    ; if in car, take step to destination
;    if car-at-customer? [take-step-on-route]
    ; if arrived at destination, pay and remove trip
;    if customer-arrived? [end-customer-trip]
  ]

  ask valets[
    ; if deliveries available, pick one or wait
    ifelse deliveries-available?
    [ if valet-picked-car? = false [ increment-wait 1 ] ]
    [ increment-wait 1 ]
    ; if in-delivery, scooter to car (or ride car to customer)
    if valet-on-scooter? [valet-step-to-car]
;    if valet-in-car? [valet-step-to-customer]
;    ; if arrived at customer, complete delivery
;    if valet-arrived-at-customer? [complete-delivery]
  ]

  ask cars [
    ; if route available, step towards destination, otherwise wait
    ifelse car-routed? [car-step][increment-wait 1]
    ; if arrived at destination, reset to waiting mode
    if car-arrived? [car-idled]
  ]
;
;  ask carowners [
;    ; if car unavailable, randomly make available
;    ; if car available, randomly make unavailable
;    ; if car active, randomly request return
;    ; if return requested, wait
;    ; if car returned, make unavailable
;  ]

  tick

end

;*********************************************************************************************
; car methods

; when car knows where to go it starts moving
to-report car-routed?
  report count my-out-trips = 1
end

; move to destination with or without 'passenger' (who is really the driver)
to car-step
  let route [trip-route] of one-of my-out-trips  ; car has one link
  let route-length route-distance route
  let num-steps round(route-length / step-length)
  ifelse car-step-num < num-steps [
    take-step route car-step-num car-passenger
    set car-step-num car-step-num + 1
  ][
    move-to last route
;    print "car arrived"
    if car-passenger != nobody
    [ask car-passenger
      [ set hidden? false
        move-to last route
      ]
    ]
  ]
end

; check if current position is destination
to-report car-arrived?
  report car-routed? and agent-here? last [trip-route] of one-of my-out-trips ; car has one out-going trip
;  let agent-at-destination one-of out-link-neighbors ; car has one link
;;  let car-location [location] of car-to-deliver
;;  report distance-between self car-location = 0
;  report agent-here? agent-at-destination
end

; reset to waiting mode
to car-idled
  ask my-trips [die]
end

;*********************************************************************************************
; valet methods

; valet has no trip to a car
to-report valet-on-scooter?
  report count my-out-trips = 0
;  report delivery-selected? and not valet-arrived-at-car?
end

; ride scooter to a car using a trip with a route
; when arrived at car give car a route and become a passenger
to valet-step-to-car
  let route [trip-route] of one-of my-trips ; only one trip
  let route-length route-distance route
  let num-steps round(route-length / step-length)
  ifelse valet-step-num < num-steps [
    take-step route valet-step-num nobody
    set valet-step-num valet-step-num + 1
  ][
    ; arrived at car
;    set delivery-status "to-car"
    set hidden? true ; since getting in car now
    set valet-step-num 0 ; reset for next trip to car
    move-to last route

    ; set the car's trip to activate the car to travel to customer
    ; become passenger in car

    let car-to-deliver one-of out-trip-neighbors ; valet has one outgoing trip
    ask my-out-trips [die] ; remove existing trip to car
    ; car is currently reserved so has a route and a customer
;    set route [car-route] of car-to-deliver
;    let dst last route
    let current-customer [car-customer] of car-to-deliver
    create-trip-to current-customer [
      set shape "trip"
      set color yellow - 3
      set hidden? true
    ]
    ask car-to-deliver [
      create-trip-to current-customer [
        set shape "trip"
        set color yellow - 3
        set hidden? false
      ]
      set car-passenger myself
    ]

;    ; get new route from car's trip
;;    let car-to-deliver [other-end] of one-of my-out-trips
;    let car-to-deliver one-of out-trip-neighbors
;    let car-trip-to-customer one-of [my-in-trips] of car-to-deliver ; car has one outgoing trip
;    let car-route-to-customer [trip-route] of car-trip-to-customer
;    let current-customer [end2] of car-trip-to-customer
;    ; valet is 'driven' to customer
;    ask car-to-deliver [set car-passenger myself]
;
;    ; replace existing trip with the car's trip to customer
;    ask my-trips [die]
;    create-trip-to current-customer [
;      set trip-route car-route-to-customer
;      set shape "trip"
;      set color yellow - 3
;      set hidden? true
;    ]
  ]
end

;to valet-step-to-customer
;print "valet-step-to-customer"
;  let route [trip-route] of one-of my-trips ; only one trip
;  let route-length route-distance route
;  let num-steps round(route-length / step-length)
;
;
;  ; get route from car's trip
;  let car-to-deliver [end2] of one-of my-trips
;  let car-trip one-of [my-trips] of car-to-deliver
;  let route  [trip-route] of car-trip
;end

to-report valet-in-car?
  report delivery-selected? and valet-arrived-at-car?
end

; check that valet has an active delivery
to-report delivery-selected?
  report count my-links = 1
end

; check if current position is destination (and a car)
to-report valet-arrived-at-car?
  report car-here? one-of cars with [car-passenger = myself]
;  let car-to-deliver [end2] of one-of my-trips ; valet has one trip
;  let arrived? car-here? car-to-deliver
;  if arrived? [
;;    ; get new route from car's trip
;;    let car-trip one-of [my-trips] of car-to-deliver; car has one trip
;;    ; create trip to customer using car's route
;;    create-trip-to [end2] of car-trip [
;;      set trip-route [trip-route] of car-trip
;;    ]
;  ]
;  report arrived?
end

; is valet and customer in same place with car?
to-report valet-arrived-at-customer?
  ; valet is linked to customer by a trip
  let current-customer one-of out-trip-neighbors ; valet has one trip
;  print word "current-customer " current-customer
  ; valet is a passenger in car
  let car-to-deliver one-of cars with [car-passenger = myself]
;  print word "car-to-deliver " car-to-deliver
  report at-customer? current-customer and car-here? car-to-deliver

;  ; valet is linked to car which is linked to customer
;  let car-to-deliver [end2] of one-of my-links
;  let car-links [my-links] of car-to-deliver
;  let customer-delivering-to nobody
;  ask car-to-deliver [set customer-delivering-to first [other-end] of my-trips with [trip-route != 0]]
;  print word "customer-deliverying-to " customer-delivering-to
;;  let car-location [location] of car-to-deliver
;;  report distance-between self car-location = 0
;  report at-customer? customer-delivering-to
end

to complete-delivery

end

to-report deliveries-available?
  ; count unreserved cars that have not been claimed by valets
  report count cars with [not valet-car-reserved? self and not valet-claimed?] > 0
end

to-report valet-picked-car?
  let nearest-car find-nearest-valet-car
  let route calc-route point-here xcor ycor [location] of nearest-car
  ifelse route = false
  [ report false]
  [ create-trip-to nearest-car
    [ set trip-route route
      set shape "trip"
      set color yellow - 3
      display-route trip-route yellow
    ]
    set color yellow
    report true
  ]
end

;*********************************************************************************************
; customer methods

; condition to create a trip randomly
; may expand to simulate a demand curve
to-report create-customer-trip?
  report not customer-trip-created? and ticks mod 20 = 0 and random-float 1 <= trip-frequency
end

; trip created by reserving car
to-report customer-trip-created?
  report customer-reserved-car != nobody
end

; customer waiting for car
to-report customer-waiting-for-car?
  report customer-trip-created? and not car-at-customer?
end

; customer at car
to-report car-at-customer?
  ifelse customer-trip-created? [
    let my-car customer-reserved-car
    report car-here? my-car
  ][report false]
end

; get car reserved by this customer
to-report customer-reserved-car
  report one-of cars with [car-customer = myself]
end

to-report customer-arrived?
  ; check if reached end-of-route
  ifelse customer-trip-created? [
    let my-route [trip-route] of one-of my-trips
    let dst last my-route
    report agent-here? dst
  ][report false]
end

; create customer trip
to-report create-customer-trip
  let nearest-car find-nearest-customer-car
  if nearest-car = nobody [report false]
  let route-from-car calc-route [location] of nearest-car location
  ; should not create trip if there is no route to car
;  if route-from-car = false [report false]

  ; create trip to random destination
  let random-route calc-route-with-rnd-dst location
  let random-dst last random-route

  ; reserve the car
  ask nearest-car [
    set car-route route-from-car
    display-route car-route yellow
    set car-customer myself
    set color yellow
  ]
;  create-trip-from nearest-car
;  [ set trip-route route-from-car
;    set shape "trip"
;    set color yellow - 3
;    display-route trip-route yellow
;  ]
  set color red
  set hidden? false

;  ask nearest-car [set color yellow]
  report true

end

to end-customer-trip
  ; cleanup and pay
  ask my-trips [die]
  set wait-time 0
  set hidden? true
  set payments payments + 1
end

; take a step to destination
to take-step-on-route
  ; TBD
end

;*********************************************************************************************
; helpers
;*********************************************************************************************

; may not correspond to actual time
to increment-wait [time]
  set wait-time wait-time + time
end

; a reserved car from perspective of a valet
to-report valet-car-reserved? [a-car]
  report [car-route] of a-car != []
end

; a reserved car from perspective of a customer
to-report customer-car-reserved? [a-car]
  report [car-route] of a-car != [] and [car-customer] of a-car != nobody
end

; find nearest customer car or return nobody
to-report find-nearest-customer-car
  let available-cars filter-unreserved-customer-cars cars-sorted-by-ascending-distance
  ; sometimes there is no route to nearest car, so go on to next closest car in the hope that
  ; some cars will not be isolated (until problem found)
;  let available-cars filter-cars-by-link-count cars-sorted-by-ascending-distance 0
  ifelse empty? available-cars [report nobody][report first available-cars]
;  report min-one-of cars [distance-between location [location] of myself] may restore this when problem solved
end

; find nearest reserved car or return nobody
to-report find-nearest-valet-car
  let available-cars filter-unreserved-valet-cars cars-sorted-by-ascending-distance
;  let available-cars filter-cars-by-link-count cars-sorted-by-ascending-distance 1
  ifelse empty? available-cars [report nobody][report first available-cars]
end

to-report filter-unreserved-valet-cars [a-cars]
  report filter [ a-car -> not valet-car-reserved? a-car ] a-cars
end

to-report filter-unreserved-customer-cars [a-cars]
  report filter [ a-car -> not customer-car-reserved? a-car = nobody ] a-cars
end

; link-count means 0: available, 1: customer selected, 2: valet selected
; used to prevent a car from getting selected by more than one customer and valet (and in the right order)
;to-report filter-cars-by-link-count [unfiltered-cars link-count]
;  report filter [ unfiltered-car -> (count [my-links] of unfiltered-car) = link-count ] unfiltered-cars
;end

; all cars sorted by distance from current position of agent
to-report cars-sorted-by-ascending-distance
  let agent-point point-here xcor ycor
  ; store car distance as a list of [car distance]
  let all-car-distances []
  ask cars[
    let src agent-point
    let dst point-here xcor ycor
    let distance-to-car distance-between src dst
    let car-distance list self distance-to-car
    set all-car-distances fput car-distance all-car-distances
  ]
  let sorted-car-distances sort-by [ [car1 car2] ->
    item 1 car1 < item 1 car2
  ] all-car-distances
  report map [ car-distance -> item 0 car-distance ] sorted-car-distances
;  report sort-by [ [car1 car2] ->
;    distance-between point-here xcor ycor [location] of car1 <
;    distance-between point-here xcor ycor [location] of car2
;  ] [self] of cars
end

; TODO handle overstep
to take-step [route step-num passenger]
  let current-distance step-num * step-length
  let line find-line-on-route route current-distance
  ; find point on route to position car
  let xy xy-at-distance-on-line line step-length
  let x item 0 xy
  let y item 1 xy
  let end-point item 1 line
  face end-point
  setxy x y
  if passenger != nobody [
;    print passenger
    ask passenger [
      face end-point
      setxy x y
    ]
  ]
end

; Generate a list of [point]s along a [route] from the [point]s [src] to [dst].
; If no [route] found returns [false] (like an exception).
;
; Representing a route as a list of points instead of segments is useful because
; segments have implicit direction and may not be in the correct direction.
; Plus it makes it easier to step along the route using points instead of segments
; and in other operations on routes.
to-report calc-route [src dst]
  let route false
  ask src [set route nw:turtles-on-weighted-path-to dst seg-length]
  report route
end

;to-report distance-between [src dst]
;  let route calc-route src dst
;  ; some number larger than any possible other route distance in this world
;  ; (because some route calcs fail and this method is expected to be used to find a min)
;  if route = false [report 1000000000]
;  report route-distance route
;end

to-report distance-between [src dst]
  let calc-distance 0
  ask src [set calc-distance nw:weighted-distance-to dst seg-length]
  report calc-distance
end

; reports road point at x,y
to-report point-here [x y]
  report one-of points with [xcor = x and ycor = y] ; expect only none or one
end

;to-report equal-points? [p1 p2]
;  let p1x [xcor] of p1
;  let p1y [ycor] of p1
;  let p2x [xcor] of p2
;  let p2y [ycor] of p2
;  report p1x = p2x and p1y = p2y
;end

; is a car in the same spot as this agent?
to-report car-here? [a-car]
  report is-car? a-car and agent-here? a-car
end

; is a customer in the same spot as this agent?
to-report at-customer? [a-customer]
  report is-customer? a-customer and agent-here? a-customer
end

; is this agent here?
to-report agent-here? [agent]
  report xcor = [xcor] of agent and ycor = [ycor] of agent
end

; find a random route
; (guaranteed not to fail)
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
  let dst random-road-point
  while [src = dst] [set dst random-road-point]
  report dst
end

; get length of route
to-report route-distance [route]
  let dist 0
  let previous-point first route
  foreach but-first route [ current-point ->
    let seg get-segment-between-points previous-point current-point
    set dist dist + [seg-length] of seg
    set previous-point current-point
  ]
  report dist
end

; find segment, in the form of [src,dst,length] at [dist] along [route]
to-report find-line-on-route [route dist]
  let crnt-dist 0
  let prev first route
  foreach but-first route [crnt ->
    let seg-len [link-length] of get-segment-between-points prev crnt
    set crnt-dist crnt-dist + seg-len
    if crnt-dist > dist [report (list prev crnt seg-len) ]
    set prev crnt
  ]
  report []
end

; get one segment between two points
to-report get-segment-between-points [src dst]
;  print word src dst
  report first [self] of n-of 1 segments with [
    (end1 = src and end2 = dst) or
    (end1 = dst and end2 = src)
  ]
end

; get point at a distance along a line
to-report xy-at-distance-on-line [ line dist ]
  let start-point item 0 line
  let end-point item 1 line
  let line-len item 2 line
  let startx [xcor] of start-point
  let starty [ycor] of start-point
  let endx [xcor] of end-point
  let endy [ycor] of end-point
  let x startx + (endx - startx) * dist / line-len
  let y starty + (endy - starty) * dist / line-len
  report list x y
end

to display-route [route route-color]
  if route != false and not empty? route [
    let src first route
    let dst last route
    ask src [
      set hidden? false
      set shape "circle 3"
      set color route-color]
    ask dst [
      set hidden? false
      set shape "square 3"
      set color route-color]
    let previous-point first route
    foreach but-first route [current-point ->
      let seg get-segment-between-points previous-point current-point
      ask seg [set color route-color]
      set previous-point current-point
    ]
  ]
end

to hide-route [route]
  let src first route
  let dst last route
  ask src [
    set hidden? true
    set shape ifelse-value junction? src ["square 3"]["circle 3"]
    set color grey]
  ask dst [
    set hidden? true
    set shape ifelse-value junction? src ["square 3"]["circle 3"]
    set color grey]
  let previous-point first route
  foreach but-first route [current-point ->
    let seg get-segment-between-points previous-point current-point
    ask seg [set color grey]
    set previous-point current-point
  ]
end

; point is a junction if it has more than 2 segments
to-report junction? [a-point]
  report count [my-segments] of a-point > 2
end

; Load network of GIS polyline data into points connected by segments.
; A segment is used to link points along a polyline.
; A single point is used where one or more polylines intersect.
; Segment length is the length between the points in world coordinates.
; GIS data should represent a single network. If it is not a single network
; then the result is a collection of disconnected networks (not good for a road network).
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
          ; Tip: reducing the precision of input data may result in finding
          ; more intersections
          let existing-point one-of points with [xcor = x and ycor = y]
          ifelse existing-point = nobody
          [ ifelse first-point = nobody
            [ ; start of polyline
              create-points 1
              [ set hidden? true
                setxy x y
                set first-point self
                set previous-point self
                set shape "circle 3"
                set color grey
                set in-network? false ; in a road network?
              ]
            ][ ; end of segment
              create-points 1
              [ set hidden? true
                setxy x y
                create-segment-with previous-point [ set seg-length link-length ]
                set previous-point self
                set shape "circle 3"
                set color grey
                set in-network? false ; in a road network?
              ]
            ]
          ][
            ; existing point found so this is an intersection
            ask existing-point [set shape "square 3"]
            ifelse first-point = nobody
            [
              ; first point already exists so no need to create a point
              set first-point existing-point
              set previous-point existing-point
            ][
              ; connect previous segment end to existing point
              ask previous-point [create-segment-with existing-point [set seg-length link-length]]
              set previous-point existing-point
            ]
          ]
        ]
      ]
    ]
  ]
  ; scan for and set members of road network
  while [not valid-road-network?][
    scan-road-network one-of points
  ]
end

; expect member rate of greater than 90%
to-report valid-road-network?
  report count points with [in-network? = true] > count points * 0.9
end

; scan road network and mark points as members
to scan-road-network [any-point]
  ask any-point [
    if not in-network?
    [ set in-network? true
      ask my-segments [
        if other-end != any-point [
          ask other-end [scan-road-network self]
        ]
      ]
    ]
  ]
end

; get a random road network point
to-report random-road-point
  report one-of points with [in-network? = true]
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
  let src random-road-point
  let dst other-point src
  let route calc-route src dst
  if route != false [display-route route red]
end

to show-route-using-points
    ask points with [hidden? = false] [
    set hidden? true
    set color grey]
  ask segments with [color = red] [set color gray]
  let src random-road-point
  let dst other-point src
  let route calc-route src dst
  display-route route red
end

;; find segments at [route-point] (debug)
;to-report segments-of-point [a-point]
;  report [my-segments] of a-point
;end

; show points with num connections (debug)
to show-edge-points [num-links]
  ask points [if count my-links = num-links [set hidden? false]]
end

; show all segments in road network
to show-network
;  clear-setup
;  build-road-network
  init-model
;  let a-point random-road-point
;  ask a-point [set in-network? true]
;  ask a-point [
;    set hidden? false
;    set color yellow
;  ]
  ; visit every other point in network
  while [not valid-road-network?][
    let any-point random-road-point
    ask any-point [
      set hidden? false
      set color yellow
    ]
    print any-point
    scan-road-network any-point
  ]
  ; display segments
  ask points with [in-network? = true]
    [ask my-segments [set color red]]

  let in-network count points with [in-network? = true]
  let total-points count points
  print (word "found " in-network " points in network out of " total-points " (" precision (in-network / total-points * 100) 2 "%)")
end

; show links connected to center-point for link-distance (debug)
to show-links [center-point link-distance]
  print link-distance
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

to show-points-with-no-route
  build-road-network
  ; for random point find route to every other point
  let points-with-no-route []
  ask one-of points [
    set hidden? false
    ask points [
      if self != myself [
        let src myself
        let dst self
        let route calc-route src dst
        ifelse route = false or empty? route
        [ set points-with-no-route lput dst points-with-no-route
;          set hidden? false
;          ifelse route = false [set color red][set color green]
        ][
          display-route route black + 2
        ]

      ]
    ]
;    display
  ]
  foreach points-with-no-route [ bad-point -> ask bad-point[ set hidden? false set color red]]
  print "show-points-with-no-route: done"
end

; old but good
;to drive-route [src dst]
;  ask segments with [color = white or color = red] [set color gray]
;  ask route-car [set hidden? false]
;  let route calc-route src dst
;  ifelse route = false [stop][
;    display-route route red
;    let rdistance route-distance-by-point route
;    ; move a car a fixed distance along route
;    ; speed is in MPH
;    ; distance is in miles
;    let route-speed [speed] of route-car
;    ; tick is equivalent to distance/speed = .2/20 = 2/200 = 0.01 hours = 0.6 minutes = 36 seconds
;    let num-steps round(rdistance / step-length)
;    let duration rdistance / route-speed ; hours
;
;    show (word "rdistance:" rdistance " num steps:" num-steps " duration:" duration )
;    let remaining-steps num-steps
;    while [remaining-steps >= 0] [
;      let current-distance (num-steps - remaining-steps) * step-length
;      let current-segment find-line-on-route route current-distance
;      ask current-segment [set color white]
;      ; find point on route to position car
;      ; TODO add route stepper to avoid overstep
;      let carXY xy-at-distance-on-line current-segment step-length
;      let x item 0 carXY
;      let y item 1 carXY
;      let end-point [end2] of current-segment
;      ask route-car [face end-point]
;;      let x [xcor] of end-point
;;      let y [ycor] of end-point
;      ask route-car [setxy x y]
;
;        set remaining-steps remaining-steps - 1
;  ;      let remaining-distance route-distance - num-steps * step-length
;  ;      let remaining-duration duration - remaining-distance / route-speed
;  ;      show (word "current-distance: " current-distance  " remaining-distance: " remaining-distance " remaining-duration: " remaining-duration)
;;      show (word "current-distance: " current-distance )
;      ; TODO add tick to update analytics
;    ]
;  ]
;end

;*********************************************************************************************
; unit-tests
;*********************************************************************************************
; run after setup
to unit-tests
  let success? true
  ; calc-route
;  if success? [
;    ; route returns first and last
;    let src random-road-point
;    let dst other-point src
;    let route calc-route src dst
;    while [route = false][
;      set dst other-point src
;      set route calc-route src dst
;    ]
;    set success? src = first route and dst = last route
;  ]
;  ; get-segment-between-points
;  if success? [
;    let src random-road-point
;    let route calc-route-with-rnd-dst src
;    set success? get-segment-between-points src first but-first route != nobody
;  ]
;  ; display-route
;  if success? [
;    let src random-road-point
;    let route calc-route-with-rnd-dst src
;    display-route route red
;    hide-route route
;  ]
;  ; route-distance
;  if success? [
;    let src random-road-point
;    let route calc-route-with-rnd-dst src
;    set success? route-distance route > 0
;  ]
;  ; find-line-on-route
;  if success? [
;    let src random-road-point
;    let route calc-route-with-rnd-dst src
;    let line find-line-on-route route 0.0000000001
;    set success? length line = 3 and item 0 line != nobody and item 1 line != nobody and item 2 line > 0
;  ]
;  ; xy-at-distance-on-line
;  if success? [
;    let src random-road-point
;    let dst other-point src
;    let line (list src dst 0.0000000001)
;    let xy xy-at-distance-on-line line 0.0000000001
;    set success? num-within-range? item 0 xy min-pxcor max-pxcor and num-within-range? item 1 xy min-pycor max-pycor
;  ]
;  ; take-step
;  if success? [
;    setup
;    let src random-road-point
;    hatch-valet-at src
;    let valet-id valet-who-at src
;    let route calc-route-with-rnd-dst src
;    display-route route yellow
;    ask valet valet-id [
;      let route-len route-distance route
;      let num-steps round(route-len / step-length)
;      foreach but-first range num-steps [step-num ->
;        take-step route step-num nobody
;      ]
;      let dst last route
;      move-to dst
;      set success? agent-here? dst
;    ]
;  ]
;  ; valet-step-to-car
;  if success? [
;    setup
;    let src random-road-point
;    hatch-valet-at src
;    let test-valet valet valet-who-at src
;    let route calc-route-with-rnd-dst src
;    display-route route yellow
;    let dst last route
;    hatch-car-at dst
;    let test-car car car-who-at dst
;    let customer-location random-road-point
;    hatch-customer-at customer-location
;    let test-customer customer customer-who-at customer-location
;    ; reserve the car
;    ask test-car [
;      set car-customer test-customer
;      set car-route route
;    ]
;    ask test-valet [
;      create-trip-to test-car
;      [ set trip-route route
;        set shape "trip"
;        set color yellow - 3
;      ]
;      ; start moving
;      let route-len route-distance route
;      let num-steps round(route-len / step-length)
;      foreach but-first range num-steps [ ->
;        valet-step-to-car
;      ]
;      valet-step-to-car
;      valet-step-to-car
;      set success? valet-arrived-at-car?
;      if not success? [
;        ; sanity check
;        let expected-car one-of cars with [car-passenger = test-valet]
;        print (word "car " test-car " = "  expected-car)
;        print (word "destination " dst " = " last [car-route] of expected-car)
;        print (word "at a car? " expected-car " = "  car-here? expected-car)
;        print (word "is a car? " expected-car " = "  is-car? expected-car)
;        print (word "is a turtle? " expected-car " = "  is-turtle? expected-car)
;        print (word "is agent here? " expected-car " = "  agent-here? expected-car)
;        inspect test-customer
;        inspect test-valet
;        inspect test-car
;        inspect dst
;        inspect one-of my-out-trips
;      ]
;    ]
;  ]
;  ; car-step
;  if success? [
;    setup
;    ; create a car linked to a customer
;    ; create a valet at the car, linked to the car
;    ; car drives valet, as a 'passenger' to customer
;    let src random-road-point
;    let route-to-customer calc-route-with-rnd-dst src
;    let dst last route-to-customer
;    hatch-customer-at dst
;    let test-customer customer customer-who-at dst
;    hatch-car-at src
;    let test-car car car-who-at src
;    ; reserve the car
;    ask test-car [
;      set car-customer test-customer
;      set car-route route-to-customer
;    ]
;    ask test-customer [
;      create-trip-from test-car
;      [ set trip-route route-to-customer
;        set shape "trip"
;        set color red
;        display-route trip-route yellow
;      ]
;    ]
;    hatch-valet-at src
;    let test-valet valet valet-who-at src
;    ask test-valet [
;      ; construct a fake route to src
;      let valet-fake-src nobody
;      ask src [set valet-fake-src [other-end] of one-of my-segments]
;      let valet-route-to-car list valet-fake-src src
;      create-trip-to test-car [set trip-route valet-route-to-car]
;      set valet-step-num 1000000000
;      valet-step-to-car ; at end of valet trip to car, ride car to customer
;    ]
;    ask test-car [
;      let route-length route-distance route-to-customer
;      let num-steps round(route-length / step-length)
;      foreach but-first range num-steps [ ->
;        car-step
;      ]
;      car-step
;      car-step
;      let valet-arrived? false
;      ask test-valet [set valet-arrived? valet-arrived-at-customer?]
;
;      set success? car-arrived? and valet-arrived?
;      if not success? [print "test: car_step failed"
;        print word "valet-arrived? " valet-arrived?
;        print word "car-arrived? " car-arrived?
;      ]
;    ]
;  ]
;
;  ; find-nearest-customer-car
;  if success? [
;    setup
;    let nearest-car nobody
;    car-creator 100
;    ask cars [set color white]
;    let test-customer one-of customers
;    ask test-customer [
;      set hidden? false
;      set color red
;      set nearest-car find-nearest-customer-car
;      ask nearest-car [set color red]
;    ]
;    set success? nearest-car != nobody
;    if not success? [print "find-nearest-customer-car failed"]
;  ]

  ; find-nearest-valet-car
  if success? [
    setup
    let nearest-car nobody
    ask one-of carowners[
      hatch-carowners 100
    ]
    car-creator
    ask cars [set color white]
    let test-valet one-of valets
    ask test-valet [
      set hidden? false
      set color yellow
      set nearest-car find-nearest-valet-car
      ask nearest-car [set color yellow]
    ]
    set success? nearest-car != nobody
    if not success? [print "find-nearest-valet-car failed"]
  ]

;
;  ; create-customer-trip,
;  if success? [
;    setup
;    let test-customer one-of customers
;    ask test-customer [
;      set success? create-customer-trip
;    ]
;    if not success? [print "create-customer-trip failed"]
;  ]

  ifelse success? [print "passed"][print "failed"]
;  clear-setup
end

;*********************************************************************************************
; test helpers
;*********************************************************************************************

; num within range inclusive
to-report num-within-range? [num range-min range-max]
  report num >= range-min and num <= range-max
end

to hatch-valet-at [a-point]
  ask one-of valets [hatch-valets 1 [
      setxy [xcor] of a-point [ycor] of a-point
      set color yellow
      set hidden? false
    ]
  ]
end

to hatch-car-at [a-point]
  ask one-of cars [hatch-cars 1 [
      setxy [xcor] of a-point [ycor] of a-point
      set color yellow
;      set hidden? false
    ]
  ]
end

to hatch-customer-at [a-point]
  ask one-of customers [hatch-customers 1 [
      setxy [xcor] of a-point [ycor] of a-point
      set color red
      set hidden? false
    ]
  ]
end

; get who of valet at this location
to-report valet-who-at [src]
  report [who] of one-of valets with [xcor = [xcor] of src and ycor = [ycor] of src]
end

to-report car-who-at [src]
  report [who] of one-of cars with [xcor = [xcor] of src and ycor = [ycor] of src]
end

to-report customer-who-at [src]
  report [who] of one-of customers with [xcor = [xcor] of src and ycor = [ycor] of src]
end
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
15
155
70
188
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
1
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
1
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
1
100
1.0
1
1
NIL
HORIZONTAL

BUTTON
145
155
210
188
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
75
155
138
188
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

BUTTON
50
505
122
538
restart
init-model
NIL
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
100
1075
120
https://www.santamonica.gov/isd/gis
8
7.0
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
15
Circle -1 false true 90 90 118

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
15
Rectangle -1 false true 90 90 210 210

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

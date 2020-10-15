extensions [ gis nw ]

; road map is a network of points linked by segments
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
;  speed ; mph
  car-available-by-car-owner? ; set by car-owner to add/remove fleet in service
  car-in-service? ; set by car-owner and used by operator
  car-owner ; when reserved for return, who to return car to (set on creation)
;  reserved? ; when booked by a customer (or the operator)
  car-pending-route ; required when reserving (could be a customer or the operator/observer)
  car-pending-route-owner ; need to know who to hand-off to at destination (could be a customer or a carowner) and also inform them
;  car-claimed-by-valet? ; has the valet claimed the delivery
  car-valet ; valet that has claimed this delivery
  car-passenger ; either the customer or the valet
  car-step-num ; current step along a route (for simulating speed)
  wait-time ; time spent waiting while in service
]
; a valet uses a bike to get to a car
breed [bikes bike]
bikes-own [
  bike-owner ; a valet
]

; The car moves when it has an out-going trip link
; Also used for display purposes
; (not sure yet where else to use it)
directed-link-breed [trips trip]
; a trip has a route
trips-own [trip-route]

breed [customers customer]
customers-own [
  cust-active? ; can be controlled by a demand curve, currently default to active
  cust-reserved-car ; the car that has been reserved
  cust-route ; the route the customer intends to take
  cust-car-delivered? ; has car been delivered?
  cust-arrived? ; has customer reached destination?
  cust-car-time ; time spent using car
  cust-payments ; accumulated amount paid for access to cars
  wait-time ; time spent waiting for an available car or for delivery of car
]
; a valet can have one out-going trip to a car or to a customer
breed [valets valet]
valets-own [
  valet-available? ; is valet available?
  valet-car ; the car the valet has reserved
;  valet-route-to-car; the route the valet takes to the car
  valet-route-to-customer; the route the valet takes to the customer
;  valet-arrived-at-car? ; has the valet arrived at the car?
;  valet-arrived-at-customer? ; has the valet arrived at the customer?
  valet-earnings ; accumulated amount earned for delivering cars
  valet-step-num ; current step along a route (during delivery)
  wait-time ; time spent waiting between deliveries while available
]
breed [carowners carowner]
carowners-own [
  carowner-cars ; cars owned by the car owner (probably not used)
  carowner-earnings ; accumulated amount earned while car is used by a customer (and a valet?)
]

globals [
  city-dataset ; holds the GIS polylines
  step-length ; used to calculate speed and time (in miles)
  speed ; used to calculate distance and time (in mph)
  time-unit ; time passed in each tick, used to correlate to distance travelled and meaning of some counters (calculated as distance/speed?)
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
  ask bikes [die]
  ask customers [die]
  carowners-die
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
;  cars: yellow if used by valet, red if by customer, otherwise white
;  all start out grey
to setup
  clear-setup
  ; only consider points and segments as part of a network
  nw:set-context points segments
  set step-length .2 ; miles
  set speed 20 ; mph
  set time-unit step-length / speed ; hours

  customers-builder num-customers
  valets-builder num-valets
  carowners-builder num-carowners ; also builds cars

  reset-ticks
end

to customers-builder [num]
  create-customers num [
    set hidden? true
    set color grey
    set shape "person"
    let point-x a-point
    setxy [xcor] of point-x [ycor] of point-x
    set cust-active? true
    set cust-reserved-car nobody
    set cust-route []
    set cust-car-delivered? false
    set cust-arrived? false
    set cust-car-time 0
    set cust-payments 0
    set wait-time 0
  ]
end

to valets-builder [num]
  create-valets num [
    set color grey
    set shape "person"
    let point-x a-point
    setxy [xcor] of point-x [ycor] of point-x
    set valet-available? false
    set valet-car nobody
;    set valet-route-to-car []
    set valet-route-to-customer []
;    set valet-arrived-at-car? false
;    set valet-arrived-at-customer? false
    set valet-earnings 0
    set valet-step-num 0
    set wait-time 0
    hatch-bikes 1 [
      set shape "wheels"
      set color yellow
      set hidden? true
      set bike-owner myself
    ]
  ]
end

to carowners-builder [num]
  create-carowners num [
    set hidden? true
    set color grey
    set shape "person"
    let point-x a-point
    setxy [xcor] of point-x [ycor] of point-x
    set carowner-cars []
    set carowner-earnings 0
    cars-builder 1 ; each car owner has one car (for now)
  ]
end

; called by carowner
to cars-builder [num]
  hatch-cars num [
    set color grey
    set shape "car top"
    set hidden? false
    let point-x a-point
    setxy [xcor] of point-x [ycor] of point-x
    set car-available-by-car-owner? true
    set car-in-service? true
    set car-owner myself
    set car-pending-route []
    set car-pending-route-owner nobody
;    set car-claimed-by-valet? false
    set car-valet nobody
    set car-passenger nobody
    set car-step-num 0
    set wait-time 0
  ]
end

to carowners-die
  ask cars [die]
  ask carowners [die]
end

;*********************************************************************************************
; go
;*********************************************************************************************

to go
  ask customers[
    ; customers become active/inactive based on a demand curve, currently all are active
    if cust-active?[
      ; randomly create a trip
      ; (randomly returns true when reserving or skipping, returns false when attempted and failed)
      ; if cannot create a trip because no cars available, wait and try again at another random time
      if not customer-reserved-car? and not customer-randomly-reserve-car? [increment-wait 10]
      ; if trip created and not in car, wait
      if customer-reserved-car? [
        if not customer-in-car? [increment-wait 1]
        ; if car arrived start ride of car, taking customer to destination
        if customer-reserved-car-arrived? [
          customer-start-car
        ]
        ; if customer arrived at destination, pay for trip
        if customer-arrived-at-destination? [
          customer-complete-trip
        ]
      ]
    ]
  ]

  ask valets [
    if valet-available? [
      ifelse valet-car-available? and not valet-claimed-car?
      [ ; if car available claim it
        valet-claim-car
      ][; otherwise wait
        increment-wait 1
      ]
      if valet-claimed-car? [
        ; if not in car, step to car
        if not valet-in-car? and not valet-arrived-at-customer? [
          valet-step-to-car
          ; if arrived at car, get in car and start ride of car to customer
          if valet-arrived-at-car? [
            valet-start-car-to-customer
          ]
        ]
        ; if car arrived at customer, inform customer and become available for new reservations
        if valet-arrived-at-customer? [
          valet-complete-delivery
        ]
      ]
    ]
  ]

  ask cars [
    ; a car must be available by car owner and in service
    ; for now, just in-service is required
    if car-available-by-car-owner? and car-in-service? [
      ; if car is reserved by customer (or valet) and not moving, it is waiting (for now)
      ; may modify to be waiting when not moving
      if car-reserved? and not car-in-motion? [increment-wait 1]
      if car-in-motion? [
        car-step-to-destination
        ; if car arrived at destination, release passenger (if any) and remove reservation
        if car-arrived-at-destination? [
          car-complete-trip
        ]
      ]
    ]
  ]
  tick
end

;*********************************************************************************************
; car methods

; car states
to-report car-reserved?
  report car-pending-route != [] and car-pending-route-owner != nobody
end

to-report car-in-motion?
  report count my-out-links = 1
end

to-report car-arrived-at-destination?
  report point-of self = last [trip-route] of one-of my-out-trips
end

; car state transitions/actions
to car-step-to-destination
  let route-to-destination [trip-route] of one-of my-out-trips
  let route-length route-distance route-to-destination
  let num-steps round(route-length / step-length)
  ifelse car-step-num < num-steps
  [ take-step route-to-destination car-step-num car-passenger
    set car-step-num car-step-num + 1
  ][; arrived at destination
    let dst last route-to-destination
    move-to dst ; TODO route stepper removes this
    if car-passenger != nobody [ask car-passenger [move-to dst]]
 ]
end

to car-complete-trip
  hide-route [trip-route] of one-of my-out-trips
  ask my-out-trips [die]
  set car-step-num 0
  if not is-valet? car-passenger [
    ; release the reservation
    set color grey
    set car-pending-route []
    set car-pending-route-owner nobody
    set car-valet nobody
  ]
  if car-passenger != nobody [ask car-passenger [set hidden? false]]
  set car-passenger nobody
end


; car helpers

;*********************************************************************************************
; valet methods

; valet states
to-report valet-car-available?
  report valet-car-available != nobody
end

to-report valet-claimed-car?
  report valet-claimed-car != nobody
end

to-report valet-arrived-at-car?
  report point-of self = point-of valet-claimed-car
end

to-report valet-in-car?
  report one-of cars with [car-passenger = self] != nobody
end

to-report valet-arrived-at-customer?
  let current-customer [car-pending-route-owner] of valet-claimed-car
  report point-of self = point-of current-customer
end

; valet state transitions/actions
to valet-claim-car
  set color yellow
;  set size 0.75
  ask one-of bikes with [bike-owner = myself] [set hidden? false]
  let easiest-car-to-deliver valet-car-available
  let route-to-car calc-route point-of self point-of easiest-car-to-deliver
  display-route route-to-car yellow
  let route-to-customer calc-route point-of easiest-car-to-deliver point-of [car-pending-route-owner] of easiest-car-to-deliver
  display-route route-to-customer yellow
  ask easiest-car-to-deliver [
    set car-valet myself
    set color yellow
  ]
  create-trip-to last route-to-car [
    set trip-route route-to-car
    set shape "trip"
    set color yellow - 2
  ]
end

to valet-step-to-car
  let route [trip-route] of one-of my-out-trips
  let route-length route-distance route
  let num-steps round(route-length / step-length)
  ifelse valet-step-num < num-steps
  [ take-step route valet-step-num one-of bikes with [bike-owner = myself]
    set valet-step-num valet-step-num + 1
  ][; arrived at car
;    set shape "person" ; from bike
    move-to last route ; TODO route stepper removes this
    set valet-step-num 0
    hide-route route
 ]
end

to valet-start-car-to-customer
  ask my-out-trips [die]
  set hidden? true ; since getting in car now
;  set size 1
  ask one-of bikes with [bike-owner = myself] [set hidden? true]
  ask valet-claimed-car [
    let route-to-customer calc-route point-of self point-of car-pending-route-owner
    display-route route-to-customer yellow
    create-trip-to car-pending-route-owner [
      set trip-route [route-to-customer] of myself
      set shape "trip"
      set color yellow - 2
    ]
    set car-passenger myself
  ]
end

to valet-complete-delivery
  set color grey
  ; inform customer of delivery
  let current-customer [car-pending-route-owner] of valet-claimed-car
  ask current-customer [
    set cust-car-delivered? true
  ]
end

; valet helpers
; todo change to nearest car with minimum combined route-from-valet-to-car plus route-from-car-to-customer
to-report valet-car-available
  report find-nearest-valet-car
end
to-report valet-claimed-car
  report one-of cars with [car-valet = myself]
end
to-report valet-car-reserved?
  report car-pending-route != [] and car-pending-route-owner != nobody and car-valet = nobody
end
;*********************************************************************************************
; customer methods

; customer states
to-report customer-reserved-car?
  report customer-reserved-car != nobody
end

to-report customer-in-car?
  report customer-in-car != nobody
end

to-report customer-reserved-car-arrived?
  report point-of customer-reserved-car = point-of self
end

to-report customer-arrived-at-destination?
  report last cust-route = point-of self
end

; customer state transitions/actions
to-report customer-randomly-reserve-car?
  ; define some kind of distribution and create a reservation
  ifelse ticks mod 20 = 0 and random-float 1 <= trip-frequency
  ; create reservation
  [
;    let nearest-car customer-reserved-car
    let nearest-car find-nearest-customer-car
    if nearest-car = nobody [report false]
    ; create trip to random destination
    set cust-route calc-route-with-rnd-dst point-of self
    display-route cust-route red
    ; reserve the car
    ask nearest-car [
      set car-pending-route [cust-route] of myself
      set car-pending-route-owner myself
      set color red
    ]
    set color red
    set hidden? false
    report true
  ]
  [report true] ; skip creating reservation
end

to customer-start-car
  ask customer-reserved-car [
    set color red
    set car-passenger myself
    display-route car-pending-route red
;    set car-pending-route cust-route ; for the record
;    set car-pending-route-owner self ; for the record
    create-trip-to last car-pending-route [
      set trip-route [car-pending-route] of myself
      set shape "trip"
      set color red - 2
    ]
  ]
  set hidden? true ; since in car now
end

to customer-complete-trip
  set hidden? false
  set cust-payments cust-payments + 1
end

; customer helpers
to-report customer-reserved-car
  report one-of cars with [car-pending-route = [cust-route] of myself and car-pending-route-owner = myself]
end
to-report customer-in-car
  report one-of cars with [car-passenger = self]
end


;  ask customers [
;    ; randomly create a trip
;    if create-customer-trip?
;    [if create-customer-trip = false [increment-wait 10]] ; estimated time penalty for no cars available
;    ; if trip created and not delivered, wait for car
;    if customer-waiting-for-car? [increment-wait 1]
;;    ; if in car, take step to destination
;;    if car-at-customer? [take-step-on-route]
;    ; if arrived at destination, pay and remove trip
;;    if customer-arrived? [end-customer-trip]
;  ]
;
;  ask valets[
;    ; if deliveries available, pick one or wait
;    ifelse deliveries-available?
;    [ if valet-picked-car = false [ increment-wait 1 ] ]
;    [ increment-wait 1 ]
;    ; if in-delivery, scooter to car (or ride car to customer)
;    if delivery-selected? [valet-step-to-car]
;;;    if valet-in-car? [valet-step-to-customer]
;    ; if arrived at customer, complete delivery
;    if valet-arrived-at-customer? [valet-delivery-complete]
;  ]
;
;  ask cars [
;    ; if route available, step towards destination, otherwise wait
;    ifelse car-routed? [car-step][increment-wait 1]
;    ; if arrived at destination, reset to waiting mode
;    ; Valet will load customer into car and reset route
;    ; Customer will reset route
;;    if car-arrived? [car-idled]
;  ]
;
;  ask carowners [
;    ; if car unavailable, randomly make available
;    ; if car available, randomly make unavailable
;    ; if car active, randomly request return
;    ; if return requested, wait
;    ; if car returned, make unavailable
;  ]



;;*********************************************************************************************
;; car methods
;
;; when car knows where to go it starts moving
;to-report car-routed?
;  report count my-out-trips = 1
;end
;
;; move to destination with or without 'passenger' (who is really the driver)
;to car-step
;  let route [trip-route] of one-of my-out-trips  ; car has one link
;  let route-length route-distance route
;  let num-steps round(route-length / step-length)
;  ifelse car-step-num < num-steps [
;    take-step route car-step-num car-passenger
;    set car-step-num car-step-num + 1
;  ][
;    move-to last route
;;    print "car arrived"
;    if car-passenger != nobody
;    [ask car-passenger
;      [
;;        set hidden? false
;        move-to last route
;      ]
;    ]
;    set color white
;;    set car-step-num 0
;  ]
;end
;
;; check if current position is destination
;to-report car-arrived?
;  ; route destination is always either a customer, valet, or carowner
;  report car-routed? and _agent-here? last [trip-route] of one-of my-out-trips ; car has one out-going trip
;end
;
;; reset to waiting mode
;to car-idled
;  ask my-trips [die]
;end

;;*********************************************************************************************
;; valet methods
;
;; check that valet has an active delivery
;to-report delivery-selected?
;  report count my-out-links = 1
;end
;
;; check for deliveries available for this valet
;to-report deliveries-available?
;  ; count available reserved cars
;  ; don't check if delivery selected
;  report delivery-selected? or (count cars with [valet-car-reserved?] > 0)
;end
;
;;to-report valet-in-car?
;;  ; on arrival, valet rides in car until delivered
;;  report delivery-selected? and valet-arrived-at-car?
;;end
;
;; valet has no trip to a car, therefore is available
;to-report valet-on-scooter?
;  report not delivery-selected? and count my-out-trips = 0
;end
;
; check if current position is destination (and a car)
;to-report valet-arrived-at-car?
;  report delivery-selected? and at-this-car? one-of cars with [car-passenger = myself]
;end

; is valet and customer in same place with car?
;to-report valet-arrived-at-customer?
;  ; valet is linked to customer by a trip
;  let current-customer one-of out-trip-neighbors ; valet has one trip
;;  print word "current-customer " current-customer
;  ; valet is a passenger in car
;  let car-to-deliver one-of cars with [car-passenger = myself]
;;  print word "car-to-deliver " car-to-deliver
;  report delivery-selected? and at-customer? current-customer and at-this-car? car-to-deliver
;end

;; this is a command that returns true/false
;to-report valet-picked-car
;  ifelse delivery-selected? [report true]
;  [
;    let nearest-car find-nearest-valet-car
;    let route calc-route point-of self point-of nearest-car
;    ifelse route = false
;    [ report false]
;    [
;;      ask nearest-car [set valet-claimed? true]
;;      create-trip-to nearest-car
;;      [ set trip-route route
;;        set shape "trip"
;;        set color yellow - 3
;;        display-route trip-route yellow
;;      ]
;      set color yellow
;      set shape "wheels"
;      report true
;    ]
;  ]
;end

; ride scooter to a car using a trip with a route
; when arrived at car give car a route and become a passenger
; change valet trip-to-car to trip-to-customer (even though riding in car)
;to valet-step-to-car
;  if not valet-arrived-at-car? [
;   let route [trip-route] of one-of my-out-trips ; valet has one outgoing trip
;   let route-length route-distance route
;   let num-steps round(route-length / step-length)
;   ifelse valet-step-num < num-steps [
;     take-step route valet-step-num nobody
;     set valet-step-num valet-step-num + 1
;   ][
;     ; arrived at car
;     set hidden? true ; since getting in car now
;     set shape "person"
;     move-to last route ; TODO route stepper removes this
;
;     ; set the car's trip to activate the car to travel to customer
;     ; become passenger in car
;     let car-to-deliver one-of out-trip-neighbors ; valet has one outgoing trip
;     ; car is currently reserved so has a route and a customer
;     let current-customer [car-customer] of car-to-deliver
;;      print current-customer
;     let route-to-customer calc-route point-of self point-of current-customer
;     ask my-out-trips [die] ; remove existing trip to car
;     create-trip-to current-customer [
;       set trip-route route-to-customer
;       set shape "trip"
;       set color yellow - 3
;       set hidden? false
;     ]
;     ; tell the car to move along route
;     ask car-to-deliver [
;       create-trip-to current-customer [
;         set trip-route route-to-customer
;         set shape "trip"
;         set color yellow - 3
;         set hidden? false
;       ]
;       ; valet is 'driven' to customer
;       set car-passenger myself
;     ]
;      ; cleanup route-to-car
;      hide-route route
;    ]
;  ]
;end

;; make self available again
;to valet-delivery-complete
;  ask my-out-trips [hide-route trip-route]
;  set hidden? false
;  set color grey
;  ; put passenger in car and enable car
;  let current-customer one-of out-trip-neighbors
;  let current-customer-route [trip-route] of one-of [my-out-trips] of current-customer
;  let car-to-deliver car-with-passenger self
;  send-car car-to-deliver current-customer-route current-customer red - 2
;  ask my-trips [die]
;end
;
;; send a car along a route
;to send-car [a-car route passenger a-color]
;  ask a-car [
;    ask my-out-trips [die]
;    create-trip-to last route [
;      set trip-route route
;      set shape "trip"
;      set color a-color
;      set hidden? false
;    ]
;    if passenger != nobody [set car-passenger passenger]
;  ]
;end
;
;; get car I'm a passenger of
;to-report car-with-passenger [passenger]
;  report one-of cars with [car-passenger = passenger]
;end
;
;;*********************************************************************************************
;; customer methods
;
;; condition to create a trip randomly
;; may expand to simulate a demand curve
;to-report create-customer-trip?
;  report not customer-trip-created? and ticks mod 20 = 0 and random-float 1 <= trip-frequency
;end
;
;; trip created by reserving car
;to-report customer-trip-created?
;  report customer-reserved-car != nobody
;end
;
;; customer waiting for car
;to-report customer-waiting-for-car?
;  report customer-trip-created? and not car-at-customer?
;end
;
;; customer at car
;to-report car-at-customer?
;  ifelse customer-trip-created? [
;    let my-car customer-reserved-car
;    report at-this-car? my-car
;  ][report false]
;end
;
;; get car reserved by this customer
;;to-report customer-reserved-car
;;  report one-of cars with [car-customer = myself]
;;end
;
;to-report customer-arrived?
;  ; check if reached end-of-route
;  ifelse customer-trip-created? [
;    let my-route [trip-route] of one-of my-trips
;    let dst last my-route
;    report _agent-here? dst
;  ][report false]
;end
;
;; create customer trip
;to-report create-customer-trip
;  let nearest-car find-nearest-customer-car
;  if nearest-car = nobody [report false]
;  let route-from-car calc-route point-of nearest-car point-of self
;  ; create trip to random destination
;;  let random-route calc-route-with-rnd-dst location
;;  display-route random-route red
;;  create-trip-to last random-route
;;  [ set trip-route random-route
;;    set shape "trip"
;;    set color red + 0.5
;;  ]
;;  ; reserve the car
;;  ask nearest-car [
;;    set car-route route-from-car
;;    display-route car-route yellow
;;    set car-customer myself
;;    set color yellow
;;  ]
;  set color red
;  set hidden? false
;  report true
;end
;
;to end-customer-trip
;  ; cleanup and pay
;  let route [trip-route] of one-of my-out-links
;  hide-route route
;  ask my-trips [die]
;  set wait-time 0
;  set hidden? true
;;  set payments payments + 1
;end

;*********************************************************************************************
; helpers
;*********************************************************************************************

; may not correspond to actual time
to increment-wait [time-increment]
  set wait-time wait-time + time-increment * time-unit
end

; a reserved car from the perspective of a customer
to-report customer-a-reserved-car? [a-car]
  report [car-pending-route] of a-car != [] and [car-pending-route-owner] of a-car != nobody
end

; a reserved car from the perspective of a valet
to-report valet-a-reserved-car? [a-car]
  report [customer-a-reserved-car? self] of a-car and [car-valet] of a-car = nobody
end

; find nearest customer car or return nobody
to-report find-nearest-customer-car
  let available-cars filter-unreserved-customer-cars cars-by-ascending-distance
  ifelse empty? available-cars [report nobody][report first available-cars]
;  report min-one-of cars [distance-between location [location] of myself] may restore this when problem solved
end

; find nearest valet car or return nobody
; TODO add distance from car to customer to get shortest overall trip
to-report find-nearest-valet-car
  let available-cars filter-reserved-valet-cars cars-by-ascending-distance
  ifelse empty? available-cars [report nobody][report first available-cars]
end

to-report filter-reserved-valet-cars [some-cars]
  report filter [ a-car -> valet-a-reserved-car? a-car ] some-cars
end

to-report filter-unreserved-customer-cars [some-cars]
  report filter [ a-car -> not customer-a-reserved-car? a-car ] some-cars
end

to-report customer-closest-car [src]
  report min-one-of cars [
    ifelse-value customer-a-reserved-car? self
    [1000000000][distance-between point-of myself point-of self]
  ]
end

to-report valet-closest-car [src]
  report min-one-of cars [
    ifelse-value valet-a-reserved-car? self
    [1000000000][distance-between point-of myself point-of self]
  ]
end

; all cars sorted by distance from current position of agent
to-report cars-by-ascending-distance
  let agent-point point-at xcor ycor
  ; store car distance as a list of [car distance]
  let all-car-distances []
  ask cars[
    let src agent-point
    let dst point-at xcor ycor
    let distance-to-car distance-between src dst
    let car-distance list self distance-to-car
    set all-car-distances fput car-distance all-car-distances
  ]
  let sorted-car-distances sort-by [ [car1 car2] ->
    item 1 car1 < item 1 car2
  ] all-car-distances
  report map [ car-distance -> item 0 car-distance ] sorted-car-distances
end

; move one step along a route
; TODO handle overstep
to take-step [route step-num passenger]
  let current-distance step-num * step-length
  let line find-line-on-route route current-distance
  ; find point on route to position self (car or valet)
  let xy xy-at-distance-on-line line step-length
  let x item 0 xy
  let y item 1 xy
  let end-point item 1 line
  face end-point
;  if shape = "wheels"[right 90]
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

; get route in segments
; (used to display segments)
to-report calc-route-segments [src dst]
  let route false
  ask src [set route nw:weighted-path-to dst seg-length]
  report route
end

to-report distance-between [src dst]
  let calc-distance 0
  ask src [set calc-distance nw:weighted-distance-to dst seg-length]
  report calc-distance
end

; get length of route
to-report route-distance [route]
  report distance-between first route last route
end

; start of pointy things section

; get a random road network point
to-report a-point
  report one-of points with [in-network? = true]
end

; guarantee a different point
to-report other-point [src]
  let dst a-point
  while [src = dst] [set dst a-point]
  report dst
end

; reports road point at x,y
to-report point-at [x y]
  report one-of points with [xcor = x and ycor = y and in-network? = true] ; expect only none or one
end

; reports the point under the agent
to-report point-of [agent]
  report point-at [xcor] of agent [ycor] of agent
end
; end of pointy things section

; start of breed type checking section

; is a car in the same spot as calling agent?
to-report at-this-car? [a-potential-car]
  report is-car? a-potential-car and _agent-here? a-potential-car
end

; is a customer in the same spot as calling agent?
to-report at-this-customer? [a-potential-customer]
  report is-customer? a-potential-customer and _agent-here? a-potential-customer
end

; is this agent in same spot as calling agent?
; should not be called directly except in this section
to-report _agent-here? [a-potential-agent]
  report xcor = [xcor] of a-potential-agent and ycor = [ycor] of a-potential-agent
end
; end of breed type checking section

; find a random route
to-report calc-route-with-rnd-dst [src]
  report calc-route src other-point src
end

; find segment, in the form of [src,dst,length] at [dist] along [route]
to-report find-line-on-route [route dist]
  let route-segs calc-route-segments first route last route
  let crnt-dist 0
  let prev first route
  (foreach route-segs (but-first route) [[seg crnt] ->
    let seg-len [link-length] of seg
    set crnt-dist crnt-dist + seg-len
    if crnt-dist > dist [report (list prev crnt seg-len) ]
    set prev crnt
  ])
  report []
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
  if display-routes = true and route != false and not empty? route [
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
    let route-segments calc-route-segments src dst
    ask link-list-to-set route-segments [set color route-color]
;    foreach route-segments [seg -> ask seg [set color route-color]]
  ]
end

to hide-route [route]
  if display-routes = true [
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
    let route-segments calc-route-segments src dst
    ask link-list-to-set route-segments [set color grey]
;    foreach route-segments [seg -> ask seg [set color grey]]
  ]
end

; point is a junction if it has more than 2 segments
to-report junction? [point-x]
  report count [my-segments] of point-x > 2
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
          ][; existing point found so this is an intersection
            ask existing-point [set shape "square 3"]
            ifelse first-point = nobody
            [ ; first point already exists so no need to create a point
              set first-point existing-point
              set previous-point existing-point
            ][; connect previous segment end to existing point
              ask previous-point [create-segment-with existing-point [set seg-length link-length]]
              set previous-point existing-point
            ]
          ]
        ]
      ]
    ]
    ; scan for and set members of road network
    ; expect member rate of greater than 94%
    discover-network 0.94
  ]
end

; discover road network and mark points as members
; this may halt for high min member rate
to discover-network [min-member-rate]
  let num-points count points
  let max-retries round(num-points * (1 - min-member-rate)) + 1
  let retries 0
  while [retries < max-retries and not valid-network? min-member-rate][
    ask points [set in-network? false]
    add-to-network one-of points false
    set retries retries + 1
  ]
  if retries = max-retries [
    user-message (word "No network found at min member rate of " min-member-rate ". \nRecommend halting. \nTry reducing min member rate or improve quality of input data.")
  ]
end

to-report valid-network? [min-member-rate]
  report count points with [in-network? = true] / count points > min-member-rate
end

; recursively visits every point in candidate network
to add-to-network [next-point show-segments?]
  ask next-point [
    if not in-network?
    [ set in-network? true
      if show-segments? [ask my-segments [set color red]]
      ask segment-neighbors [
        add-to-network self show-segments?]
    ]
  ]
end

; here's how to convert an agentset to a list of agents:
to-report set-to-list [a-set]
  report [self] of a-set
end

; here's how to convert a list of agents to an agentset:
to-report turtle-list-to-set [a-list]
;  report turtles with [member? self a-list]
  report turtle-set a-list
end

to-report link-list-to-set [a-list]
;  report links with [member? self a-list]
  report link-set a-list
end

;*********************************************************************************************
; debug
;*********************************************************************************************

to show-route
  ; get two random points and calculate route
  ask points with [hidden? = false] [
    set hidden? true
    set color grey]
  ask segments with [color = red] [set color gray]
  let src a-point
  let dst other-point src
  let route calc-route src dst
  if route != false [display-route route red]
end

to show-route-using-points
  ask points with [hidden? = false] [
  set hidden? true
  set color grey]
  ask segments with [color = red] [set color gray]
  let src a-point
  let dst other-point src
  let route calc-route src dst
  display-route route red
end

; show points with num connections (debug)
to show-edge-points [num-links]
  ask points [if count my-links = num-links [set hidden? false]]
end

; show all segments in road network
to show-network
  init-model
  ask points [set in-network? false]
  while [not valid-network? 0.5][
    let any-point one-of points
    ask any-point [
      set hidden? false
      set color yellow
    ]
    print any-point
    add-to-network any-point true
  ]
  let in-network-points count points with [in-network? = true]
  let total-points count points
  print (word "found " in-network-points " points in network out of " total-points " (" precision (in-network-points / total-points * 100) 2 "%)")
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
  if success? [set success? test-calc-route]
  if success? [set success? test-display-route]
  if success? [set success? test-route-distance]
  if success? [set success? test-find-line-on-route]
  if success? [set success? test-xy-at-distance-on-line]
  if success? [set success? test-take-step]
  if success? [set success? test-valet-step-to-car]
  if success? [set success? test-car-step]
  if success? [set success? test-customer-randomly-reserve-car?]
  if success? [set success? test-cars-by-ascending-distance]
  if success? [set success? test-find-nearest-customer-car]
  if success? [set success? test-find-nearest-valet-car]
;  if success? [set success? test-deliveries-available?]
  if success? [set success? test-full-customer-trip]
  ifelse success? [print "passed" clear-setup][print "failed"]
end

to-report test-calc-route
  let success? false
  ; route returns first and last
  let src a-point
  let dst other-point src
  ifelse is-point? src and is-point? dst [
    let route calc-route src dst
    while [route = false][
      set dst other-point src
      set route calc-route src dst
    ]
    set success? src = first route and dst = last route
  ][
    print (word "error src: " src ", dst: " dst)
  ]
  if not success? [print "calc-route failed"]
  report success?
end

to-report test-display-route
  let success? false
  let src a-point
  let route calc-route-with-rnd-dst src
  display-route route red
  set success? ([my-links] of src) with [color = red] != nobody
  if not success? [print "display-route failed"]
  hide-route route
  report success?
end

to-report test-route-distance
  let success? false
  let src a-point
  let route calc-route-with-rnd-dst src
  set success? route-distance route > 0
  if not success? [print "route-distance failed"]
  report success?
end

to-report test-find-line-on-route
  let success? false
  let src a-point
  let route calc-route-with-rnd-dst src
  let line find-line-on-route route 0.0000000001
  set success? length line = 3 and item 0 line != nobody and item 1 line != nobody and item 2 line > 0
  if not success? [print "find-line-on-route failed"]
  report success?
end

to-report test-xy-at-distance-on-line
  let success? false
  let src a-point
  let dst other-point src
  let line (list src dst 0.0000000001)
  let xy xy-at-distance-on-line line 0.0000000001
  set success? num-within-range? item 0 xy min-pxcor max-pxcor and num-within-range? item 1 xy min-pycor max-pycor
  if not success? [print "fxy-at-distance-on-line failed"]
  report success?
end

to-report test-take-step
  let success? false
  clear-setup
  set step-length 0.000000001
  valets-builder 1
  customers-builder 1
  let test-valet one-of valets
  let test-customer one-of customers
  let src a-point
  ask test-valet [move-to src]
  ask test-customer [move-to src]
  let route calc-route-with-rnd-dst src
  display-route route yellow
  ask test-valet [take-step route 1 test-customer]
  set success? point-of test-valet != src and point-of test-customer != src
  if not success? [print "take-step failed"]
  report success?
end

to-report test-valet-step-to-car
  ; create a trip link on the valet
  ; the stepper looks for the route on the trip link
  let success? false
  setup
  let src a-point
  hatch-valet-at src
  let test-valet valet valet-who-at src
  let route calc-route-with-rnd-dst src
  display-route route yellow
  let dst last route
  hatch-car-at dst
  let test-car car car-who-at dst
;  let customer-location a-point
;  hatch-customer-at customer-location
;  let test-customer customer-who-at customer-location
  ; reserve the car
  ask test-car [
;    set car-pending-route-owner test-customer
;    set car-pending-route route
    set car-valet test-valet
  ]
  ask test-valet [
    create-trip-to dst
    [ set trip-route route
      set shape "trip"
      set color yellow - 3
    ]
    ; start moving
    let route-len route-distance route
    test-helper-steps-to-dst [ -> valet-step-to-car] route-len
;    let num-steps round(route-len / step-length)
;    foreach but-first range num-steps [ ->
;      valet-step-to-car
;    ]
;    valet-step-to-car
;    valet-step-to-car
    set success? valet-arrived-at-car?
    if not success? [
      print "valet-step-to-car failed"
      ; sanity check
      let expected-car one-of cars with [car-passenger = test-valet]
      print (word "car " test-car " = "  expected-car)
      print (word "destination " dst " = " last [car-pending-route] of expected-car)
      print (word "at a car? " expected-car " = "  at-this-car? expected-car)
;      inspect test-customer
      inspect test-valet
      inspect test-car
      inspect dst
      inspect one-of my-out-trips
    ]
  ]
  report success?
end

to-report test-car-step
  let success? false
  setup
  ; create a car linked to a customer
  ; create a valet at the car, linked to the car
  ; car drives valet, as a 'passenger' to customer
  let src a-point
  let route-to-customer calc-route-with-rnd-dst src
  let dst last route-to-customer
  hatch-customer-at dst
  let test-customer customer customer-who-at dst
  hatch-car-at src
  let test-car car car-who-at src
  hatch-valet-at src
  let test-valet valet valet-who-at src
  ; reserve the car
  ask test-car [
    set car-pending-route-owner test-customer
    set car-pending-route route-to-customer
    set car-valet test-valet
  ]
  ask test-customer [
    create-trip-from test-car
    [ set trip-route route-to-customer
      set shape "trip"
      set color red
      display-route trip-route yellow
    ]
  ]
  ask test-valet [
    ; construct a fake route to src
    let valet-fake-src nobody
    ask src [set valet-fake-src [other-end] of one-of my-segments]
    let valet-fake-route-to-car list valet-fake-src src
    create-trip-to test-car [set trip-route valet-fake-route-to-car]
    set valet-step-num 1000000000
    valet-step-to-car ; at end of valet trip to car, ride car to customer
  ]
  ask test-car [
    set car-passenger test-valet
    let route-length route-distance route-to-customer
    test-helper-steps-to-dst [ -> car-step-to-destination] route-length
    let valet-arrived? false
    ask test-valet [set valet-arrived? valet-arrived-at-customer?]

    set success? car-arrived-at-destination? and valet-arrived?
    if not success? [print "test: car_step failed"
      print word "valet-arrived? " valet-arrived?
      print word "car-arrived? " car-arrived-at-destination?
    ]
  ]
  report success?
end

to-report test-customer-randomly-reserve-car?
  let success? false
  setup
  let test-customer one-of customers
  ask test-customer [
    set success? customer-randomly-reserve-car?
  ]
  if not success? [print "customer-randomly-reserve-car? failed"]
  report success?
end

to-report test-cars-by-ascending-distance
  let success? false
  clear-setup
  carowners-builder 10
  valets-builder 1
  ask cars [set color white]
  let nearest-car nobody
  ask turtle 1 [
    let sorted-cars cars-by-ascending-distance
    set success? length sorted-cars = count cars
    set hidden? true
    set color red
    ask first sorted-cars [set color red]
    set success? length sorted-cars = count cars
  ]
  if not success? [print "cars-by-ascending-distance failed"]
  report success?
end

to-report test-find-nearest-customer-car
  let success? false
  clear-setup
  carowners-builder 10
  customers-builder 1
  ask cars [set color white]
  let nearest-car nobody
  ask one-of customers [
    set hidden? false
    set color red
    set nearest-car find-nearest-customer-car
    set success? nearest-car != nobody
    if success? [ask nearest-car [set color red]]
  ]
  if not success? [print "find-nearest-customer-car failed"]
  report success?
end

to-report test-find-nearest-valet-car
  let success? false
  clear-setup
  carowners-builder 10
  valets-builder 1
  let test-valet one-of valets
  ; make all cars available to valet
  ask cars [
    set color white
    set car-pending-route (list a-point)
    set car-pending-route-owner test-valet
    set car-valet nobody
  ]
;  ; customer reserves a car
;  let test-car one-of cars
;  ask test-car [set car-pending-route (list one-of points)]
  let nearest-car nobody
  ask test-valet [
    set hidden? false
    set color yellow
    set nearest-car find-nearest-valet-car
    set success? nearest-car != nobody
    if success? [ask nearest-car [set color yellow]]
  ]
  if not success? [
    print "find-nearest-valet-car failed"
    ask test-valet [
      print cars-by-ascending-distance
      print filter-reserved-valet-cars cars-by-ascending-distance
    ]
  ]
  report success?
end

;to-report test-deliveries-available?
;  ; need one car and one valet for this test
;  let success? false
;  clear-setup
;  carowners-builder 1
;  valets-builder 1
;  let test1 true
;  let test2 true
;  let test3 true
;  let test4 true
;  let test-valet one-of valets
;  ; initially no deliveries available
;  ask test-valet [set test1 not deliveries-available?]
;  ; customer reserves a car
;  ask one-of cars [set car-pending-route (list one-of points)]
;  ; one delivery available
;  ask test-valet [set test2 deliveries-available?]
;  ; another valet claims it
;  ask one-of cars [set car-valet one-of valets]
;  ; delivery not available
;  ask test-valet [set test3 not deliveries-available?]
;  ; re-init
;  ; valet has existing delivery, so should return true
;  ask test-valet [
;    create-trip-to one-of turtles
;    set test4 deliveries-available?
;  ]
;  set success? test1 and test2 and test3 and test4
;  if not success? [print "deliveries-available? failed"]
;  report success?
;end

to-report test-full-customer-trip
  let success? false
  ; try to get thru first trip
  clear-setup
  customers-builder 1
  valets-builder 1
  carowners-builder 1
  let test-customer one-of customers
  let test-valet one-of valets
  let test-car one-of cars
  ; customer reserves a car
  reset-ticks
  repeat 20 [tick]
  set step-length 0.2
  let test2-customer-randomly-reserve-car? false
  ask test-customer [
    set test2-customer-randomly-reserve-car? customer-randomly-reserve-car?
  ]
  let test-valet-car-available? false
  let test-valet-claimed-car? false
  let test-valet-arrived-at-car? false
  let test-valet-in-car? false
  let test-valet-arrived-at-customer? false
  ask test-valet [
    valet-claim-car
    set test-valet-car-available? not valet-car-available?
    ; move valet to car
    test-helper-steps-to-dst [ -> valet-step-to-car ] nobody
    ; start moving to car
    valet-start-car-to-customer
  ]
  ask test-car [
    ; move car to destination
    test-helper-steps-to-dst [ -> car-step-to-destination ] nobody
    car-complete-trip
  ]
  ask test-valet [
    valet-complete-delivery
  ]
  ask test-customer [
    customer-start-car
  ]
  ask test-car [
    test-helper-steps-to-dst [ -> car-step-to-destination ] nobody
    car-complete-trip
  ]
  ask test-customer [
    set success? customer-arrived-at-destination?
  ]
  set success? success? and
    test2-customer-randomly-reserve-car? and
    test-valet-car-available?
  if not success? [print "test-full-customer-trip failed"]
  report success?
end

;*********************************************************************************************
; test helpers
;*********************************************************************************************
to test-helper-steps-to-dst [step-command route-length]
  let route-len 0
  ifelse route-length = nobody [
    set route-len route-distance [trip-route] of one-of my-out-links
  ][
    set route-len route-length
  ]
  let num-steps round(route-len / step-length) + 2 ; add 2 since num-steps needs min of 2
  foreach but-first range num-steps [run step-command]
;  run step-command
;  run step-command
end

; num within range inclusive
to-report num-within-range? [num range-min range-max]
  report num >= range-min and num <= range-max
end

to hatch-valet-at [point-x]
  ask one-of valets [hatch-valets 1 [
      setxy [xcor] of point-x [ycor] of point-x
      set color yellow
      set hidden? false
    ]
  ]
end

to hatch-car-at [point-x]
  ask one-of cars [hatch-cars 1 [
      setxy [xcor] of point-x [ycor] of point-x
      set color yellow
;      set hidden? false
    ]
  ]
end

to hatch-customer-at [point-x]
  ask one-of customers [hatch-customers 1 [
      setxy [xcor] of point-x [ycor] of point-x
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
"Cu" 1.0 0 -16777216 true "" "plot mean [wait-time] of customers"
"Va" 1.0 0 -1184463 true "" "plot mean [wait-time] of valets"
"Ca" 1.0 0 -7500403 true "" "plot mean [wait-time] of cars"

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

SWITCH
30
215
177
248
display-routes
display-routes
0
1
-1000

@#$#@#$#@
## WHAT IS IT?

A car on demand service that allows customers to order a car, receive it within minutes, and drive anywhere with no need to return. 

Demonstrate a new mode of transportation at the intersection of rideshare and car rental.
Show profit performance when compared to rideshare and/or rental.

## HOW IT WORKS

A CUSTOMER orders a CAR. A VALET travels to the CAR and delivers the CAR to the CUSTOMER.
The CUSTOMER drives the CAR to a destination and pays for TRIP.

## HOW TO USE IT

Change the number of CUSTOMERS, CARS and VALETS. The CUSTOMER demand can be adjusted using trip-frequency.

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

Uses GIS extension to import a shapefile of polylines which is converted to POINTS and SEGMENTS. Uses the NW extension to calculate discover shortest routes.

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

wheels
true
0
Circle -7500403 false true 86 11 127
Circle -7500403 false true 86 161 127
Circle -7500403 false true 88 13 122
Circle -7500403 false true 88 163 122

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

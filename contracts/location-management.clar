;; Location Management Contract
;; Manages multi-location inventory coordination and transfers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-LOCATION-NOT-FOUND (err u501))
(define-constant ERR-TRANSFER-NOT-FOUND (err u502))
(define-constant ERR-INVALID-TRANSFER (err u503))
(define-constant ERR-INSUFFICIENT-STOCK (err u504))
(define-constant ERR-SAME-LOCATION (err u505))

;; Data Variables
(define-data-var next-transfer-id uint u1)
(define-data-var next-zone-id uint u1)

;; Data Maps
(define-map authorized-users
  { user: principal }
  { role: (string-ascii 20) }
)

(define-map location-zones
  { zone-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 200),
    manager: principal,
    active: bool,
    created-at: uint
  }
)

(define-map zone-locations
  { location-id: uint }
  { zone-id: uint }
)

(define-map transfer-requests
  { transfer-id: uint }
  {
    product-id: uint,
    from-location: uint,
    to-location: uint,
    quantity: uint,
    status: (string-ascii 20),
    requested-by: principal,
    approved-by: principal,
    requested-at: uint,
    approved-at: uint,
    completed-at: uint,
    reason: (string-ascii 200)
  }
)

(define-map location-capacity
  { location-id: uint }
  {
    max-capacity: uint,
    current-utilization: uint,
    storage-cost-per-unit: uint,
    handling-cost-per-unit: uint,
    last-updated: uint
  }
)

(define-map inter-location-routes
  { from-location: uint, to-location: uint }
  {
    distance: uint,
    transit-time-hours: uint,
    cost-per-unit: uint,
    preferred-carrier: (string-ascii 100),
    active: bool
  }
)

(define-map location-demand-patterns
  { location-id: uint, product-id: uint }
  {
    average-daily-demand: uint,
    peak-demand: uint,
    seasonal-factor: uint,
    demand-volatility: uint,
    last-calculated: uint
  }
)

;; Authorization check
(define-private (is-authorized (user principal))
  (or
    (is-eq user CONTRACT-OWNER)
    (is-some (map-get? authorized-users { user: user }))
  )
)

;; Zone Management Functions
(define-public (create-zone (name (string-ascii 100)) (description (string-ascii 200)) (manager principal))
  (let ((zone-id (var-get next-zone-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set location-zones
      { zone-id: zone-id }
      {
        name: name,
        description: description,
        manager: manager,
        active: true,
        created-at: block-height
      }
    )

    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

(define-public (assign-location-to-zone (location-id uint) (zone-id uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? location-zones { zone-id: zone-id })) ERR-LOCATION-NOT-FOUND)

    (map-set zone-locations
      { location-id: location-id }
      { zone-id: zone-id }
    )
    (ok true)
  )
)

;; Transfer Management Functions
(define-public (request-transfer (product-id uint) (from-location uint) (to-location uint) (quantity uint) (reason (string-ascii 200)))
  (let (
    (transfer-id (var-get next-transfer-id))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq from-location to-location)) ERR-SAME-LOCATION)
    (asserts! (> quantity u0) ERR-INVALID-TRANSFER)

    (map-set transfer-requests
      { transfer-id: transfer-id }
      {
        product-id: product-id,
        from-location: from-location,
        to-location: to-location,
        quantity: quantity,
        status: "pending",
        requested-by: tx-sender,
        approved-by: tx-sender,
        requested-at: block-height,
        approved-at: u0,
        completed-at: u0,
        reason: reason
      }
    )

    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

(define-public (approve-transfer (transfer-id uint))
  (let ((transfer (unwrap! (map-get? transfer-requests { transfer-id: transfer-id }) ERR-TRANSFER-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status transfer) "pending") ERR-INVALID-TRANSFER)

    (map-set transfer-requests
      { transfer-id: transfer-id }
      (merge transfer {
        status: "approved",
        approved-by: tx-sender,
        approved-at: block-height
      })
    )
    (ok true)
  )
)

(define-public (execute-transfer (transfer-id uint))
  (let ((transfer (unwrap! (map-get? transfer-requests { transfer-id: transfer-id }) ERR-TRANSFER-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status transfer) "approved") ERR-INVALID-TRANSFER)

    (map-set transfer-requests
      { transfer-id: transfer-id }
      (merge transfer {
        status: "completed",
        completed-at: block-height
      })
    )
    (ok true)
  )
)

;; Location Capacity Management
(define-public (set-location-capacity (location-id uint) (max-capacity uint) (storage-cost uint) (handling-cost uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> max-capacity u0) ERR-INVALID-TRANSFER)

    (map-set location-capacity
      { location-id: location-id }
      {
        max-capacity: max-capacity,
        current-utilization: (calculate-current-utilization location-id),
        storage-cost-per-unit: storage-cost,
        handling-cost-per-unit: handling-cost,
        last-updated: block-height
      }
    )
    (ok true)
  )
)

;; Route Management
(define-public (create-route (from-location uint) (to-location uint) (distance uint) (transit-time uint) (cost-per-unit uint) (carrier (string-ascii 100)))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq from-location to-location)) ERR-SAME-LOCATION)
    (asserts! (> distance u0) ERR-INVALID-TRANSFER)
    (asserts! (> transit-time u0) ERR-INVALID-TRANSFER)
    (asserts! (> cost-per-unit u0) ERR-INVALID-TRANSFER)

    (map-set inter-location-routes
      { from-location: from-location, to-location: to-location }
      {
        distance: distance,
        transit-time-hours: transit-time,
        cost-per-unit: cost-per-unit,
        preferred-carrier: carrier,
        active: true
      }
    )
    (ok true)
  )
)

;; Demand Pattern Analysis
(define-public (update-demand-pattern (location-id uint) (product-id uint) (avg-daily-demand uint) (peak-demand uint) (seasonal-factor uint) (volatility uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> avg-daily-demand u0) ERR-INVALID-TRANSFER)
    (asserts! (>= peak-demand avg-daily-demand) ERR-INVALID-TRANSFER)
    (asserts! (> seasonal-factor u0) ERR-INVALID-TRANSFER)
    (asserts! (> volatility u0) ERR-INVALID-TRANSFER)

    (map-set location-demand-patterns
      { location-id: location-id, product-id: product-id }
      {
        average-daily-demand: avg-daily-demand,
        peak-demand: peak-demand,
        seasonal-factor: seasonal-factor,
        demand-volatility: volatility,
        last-calculated: block-height
      }
    )
    (ok true)
  )
)

;; Optimization Functions
(define-public (optimize-inventory-distribution (product-id uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (ok (list))
  )
)

(define-public (suggest-rebalancing (zone-id uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? location-zones { zone-id: zone-id })) ERR-LOCATION-NOT-FOUND)
    (ok (list))
  )
)

;; Helper Functions
(define-private (calculate-current-utilization (location-id uint))
  u50
)

(define-private (calculate-transfer-cost (from-location uint) (to-location uint) (quantity uint))
  (match (map-get? inter-location-routes { from-location: from-location, to-location: to-location })
    route-data (* quantity (get cost-per-unit route-data))
    u0
  )
)

;; Read-only Functions
(define-read-only (get-zone (zone-id uint))
  (map-get? location-zones { zone-id: zone-id })
)

(define-read-only (get-location-zone (location-id uint))
  (map-get? zone-locations { location-id: location-id })
)

(define-read-only (get-transfer-request (transfer-id uint))
  (map-get? transfer-requests { transfer-id: transfer-id })
)

(define-read-only (get-location-capacity (location-id uint))
  (map-get? location-capacity { location-id: location-id })
)

(define-read-only (get-route (from-location uint) (to-location uint))
  (map-get? inter-location-routes { from-location: from-location, to-location: to-location })
)

(define-read-only (get-demand-pattern (location-id uint) (product-id uint))
  (map-get? location-demand-patterns { location-id: location-id, product-id: product-id })
)

(define-read-only (get-transfer-cost-estimate (from-location uint) (to-location uint) (quantity uint))
  (ok (calculate-transfer-cost from-location to-location quantity))
)

;; Analytics Functions
(define-read-only (get-zone-summary (zone-id uint))
  (let ((zone (map-get? location-zones { zone-id: zone-id })))
    (ok {
      zone-info: zone,
      total-locations: u0,
      total-inventory-value: u0,
      utilization-rate: u0
    })
  )
)

(define-read-only (get-location-performance (location-id uint))
  (let (
    (capacity (map-get? location-capacity { location-id: location-id }))
    (zone (map-get? zone-locations { location-id: location-id }))
  )
    (ok {
      capacity-info: capacity,
      zone-assignment: zone,
      pending-transfers-in: u0,
      pending-transfers-out: u0
    })
  )
)

;; Emergency Functions
(define-public (emergency-transfer (product-id uint) (from-location uint) (to-location uint) (quantity uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    ;; Create and immediately execute emergency transfer
    (match (request-transfer product-id from-location to-location quantity "Emergency transfer")
      transfer-id (begin
        (unwrap-panic (approve-transfer transfer-id))
        (execute-transfer transfer-id)
      )
      error (err error)
    )
  )
)

;; Admin Functions
(define-public (add-authorized-user (user principal) (role (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-users { user: user } { role: role })
    (ok true)
  )
)

(define-public (remove-authorized-user (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-delete authorized-users { user: user })
    (ok true)
  )
)

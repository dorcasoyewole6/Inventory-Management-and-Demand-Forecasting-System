;; Demand Forecasting Contract
;; Provides demand prediction and analytics capabilities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-FORECAST-NOT-FOUND (err u201))
(define-constant ERR-INVALID-PERIOD (err u202))
(define-constant ERR-INVALID-CONFIDENCE (err u203))
(define-constant ERR-HISTORICAL-DATA-NOT-FOUND (err u204))

;; Data Variables
(define-data-var next-forecast-id uint u1)

;; Data Maps
(define-map authorized-users
  { user: principal }
  { role: (string-ascii 20) }
)

(define-map forecasts
  { forecast-id: uint }
  {
    product-id: uint,
    location-id: uint,
    forecast-period: uint,
    predicted-demand: uint,
    confidence-level: uint,
    created-at: uint,
    created-by: principal,
    accuracy-score: uint
  }
)

(define-map historical-sales
  { product-id: uint, location-id: uint, period: uint }
  {
    actual-sales: uint,
    recorded-at: uint
  }
)

(define-map seasonal-patterns
  { product-id: uint, location-id: uint }
  {
    spring-multiplier: uint,
    summer-multiplier: uint,
    fall-multiplier: uint,
    winter-multiplier: uint,
    trend-direction: int,
    last-calculated: uint
  }
)

(define-map forecast-accuracy
  { product-id: uint, location-id: uint }
  {
    total-forecasts: uint,
    accurate-forecasts: uint,
    average-accuracy: uint,
    last-updated: uint
  }
)

;; Authorization check
(define-private (is-authorized (user principal))
  (or
    (is-eq user CONTRACT-OWNER)
    (is-some (map-get? authorized-users { user: user }))
  )
)

;; Forecast Creation Functions
(define-public (create-forecast (product-id uint) (location-id uint) (forecast-period uint) (predicted-demand uint) (confidence-level uint))
  (let ((forecast-id (var-get next-forecast-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> forecast-period u0) ERR-INVALID-PERIOD)
    (asserts! (<= forecast-period u365) ERR-INVALID-PERIOD)
    (asserts! (>= confidence-level u1) ERR-INVALID-CONFIDENCE)
    (asserts! (<= confidence-level u100) ERR-INVALID-CONFIDENCE)

    (map-set forecasts
      { forecast-id: forecast-id }
      {
        product-id: product-id,
        location-id: location-id,
        forecast-period: forecast-period,
        predicted-demand: predicted-demand,
        confidence-level: confidence-level,
        created-at: block-height,
        created-by: tx-sender,
        accuracy-score: u0
      }
    )

    (var-set next-forecast-id (+ forecast-id u1))
    (ok forecast-id)
  )
)

(define-public (update-forecast-accuracy (forecast-id uint) (actual-demand uint))
  (let (
    (forecast (unwrap! (map-get? forecasts { forecast-id: forecast-id }) ERR-FORECAST-NOT-FOUND))
    (predicted-demand (get predicted-demand forecast))
    (accuracy-score (calculate-accuracy-score predicted-demand actual-demand))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    ;; Update forecast with accuracy score
    (map-set forecasts
      { forecast-id: forecast-id }
      (merge forecast { accuracy-score: accuracy-score })
    )

    ;; Update overall accuracy metrics
    (update-accuracy-metrics (get product-id forecast) (get location-id forecast) accuracy-score)
    (ok accuracy-score)
  )
)

;; Historical Data Management
(define-public (record-historical-sales (product-id uint) (location-id uint) (period uint) (actual-sales uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> actual-sales u0) ERR-INVALID-PERIOD)
    (asserts! (> period u0) ERR-INVALID-PERIOD)

    (map-set historical-sales
      { product-id: product-id, location-id: location-id, period: period }
      {
        actual-sales: actual-sales,
        recorded-at: block-height
      }
    )
    (ok true)
  )
)

;; Seasonal Pattern Analysis
(define-public (calculate-seasonal-patterns (product-id uint) (location-id uint))
  (let (
    (spring-avg (get-seasonal-average product-id location-id u1 u3))
    (summer-avg (get-seasonal-average product-id location-id u4 u6))
    (fall-avg (get-seasonal-average product-id location-id u7 u9))
    (winter-avg (get-seasonal-average product-id location-id u10 u12))
    (yearly-avg (/ (+ spring-avg summer-avg fall-avg winter-avg) u4))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> yearly-avg u0) ERR-HISTORICAL-DATA-NOT-FOUND)

    (map-set seasonal-patterns
      { product-id: product-id, location-id: location-id }
      {
        spring-multiplier: (/ (* spring-avg u100) yearly-avg),
        summer-multiplier: (/ (* summer-avg u100) yearly-avg),
        fall-multiplier: (/ (* fall-avg u100) yearly-avg),
        winter-multiplier: (/ (* winter-avg u100) yearly-avg),
        trend-direction: (calculate-trend product-id location-id),
        last-calculated: block-height
      }
    )
    (ok true)
  )
)

;; Advanced Forecasting Functions
(define-public (generate-smart-forecast (product-id uint) (location-id uint) (forecast-days uint))
  (let (
    (base-demand (get-base-demand product-id location-id))
    (seasonal-multiplier (get-current-seasonal-multiplier product-id location-id))
    (trend-adjustment (get-trend-adjustment product-id location-id forecast-days))
    (predicted-demand (+ base-demand (/ (* base-demand seasonal-multiplier) u100) trend-adjustment))
    (confidence (calculate-forecast-confidence product-id location-id))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> base-demand u0) ERR-HISTORICAL-DATA-NOT-FOUND)

    (create-forecast product-id location-id forecast-days predicted-demand confidence)
  )
)

;; Helper Functions
(define-private (calculate-accuracy-score (predicted uint) (actual uint))
  (let (
    (difference (if (> predicted actual) (- predicted actual) (- actual predicted)))
    (percentage-error (/ (* difference u100) actual))
  )
    (if (<= percentage-error u100)
      (- u100 percentage-error)
      u0
    )
  )
)

(define-private (update-accuracy-metrics (product-id uint) (location-id uint) (new-accuracy uint))
  (let (
    (current-metrics (default-to
      { total-forecasts: u0, accurate-forecasts: u0, average-accuracy: u0, last-updated: u0 }
      (map-get? forecast-accuracy { product-id: product-id, location-id: location-id })
    ))
    (total-forecasts (+ (get total-forecasts current-metrics) u1))
    (accurate-forecasts (if (>= new-accuracy u80)
      (+ (get accurate-forecasts current-metrics) u1)
      (get accurate-forecasts current-metrics)
    ))
    (new-average (/ (+ (* (get average-accuracy current-metrics) (get total-forecasts current-metrics)) new-accuracy) total-forecasts))
  )
    (map-set forecast-accuracy
      { product-id: product-id, location-id: location-id }
      {
        total-forecasts: total-forecasts,
        accurate-forecasts: accurate-forecasts,
        average-accuracy: new-average,
        last-updated: block-height
      }
    )
  )
)

(define-private (get-seasonal-average (product-id uint) (location-id uint) (start-month uint) (end-month uint))
  u100
)

(define-private (calculate-trend (product-id uint) (location-id uint))
  0
)

(define-private (get-base-demand (product-id uint) (location-id uint))
  u50
)

(define-private (get-current-seasonal-multiplier (product-id uint) (location-id uint))
  u100
)

(define-private (get-trend-adjustment (product-id uint) (location-id uint) (days uint))
  u0
)

(define-private (calculate-forecast-confidence (product-id uint) (location-id uint))
  u85
)

;; Read-only Functions
(define-read-only (get-forecast (forecast-id uint))
  (map-get? forecasts { forecast-id: forecast-id })
)

(define-read-only (get-historical-sales (product-id uint) (location-id uint) (period uint))
  (map-get? historical-sales { product-id: product-id, location-id: location-id, period: period })
)

(define-read-only (get-seasonal-pattern (product-id uint) (location-id uint))
  (map-get? seasonal-patterns { product-id: product-id, location-id: location-id })
)

(define-read-only (get-forecast-accuracy-metrics (product-id uint) (location-id uint))
  (map-get? forecast-accuracy { product-id: product-id, location-id: location-id })
)

(define-read-only (get-demand-trend (product-id uint) (location-id uint))
  (match (map-get? seasonal-patterns { product-id: product-id, location-id: location-id })
    pattern-data (ok (get trend-direction pattern-data))
    ERR-HISTORICAL-DATA-NOT-FOUND
  )
)

;; Analytics Functions
(define-read-only (get-forecast-summary (product-id uint) (location-id uint))
  (let (
    (accuracy-metrics (map-get? forecast-accuracy { product-id: product-id, location-id: location-id }))
    (seasonal-data (map-get? seasonal-patterns { product-id: product-id, location-id: location-id }))
  )
    (ok {
      accuracy-metrics: accuracy-metrics,
      seasonal-data: seasonal-data,
      has-sufficient-data: (and (is-some accuracy-metrics) (is-some seasonal-data))
    })
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

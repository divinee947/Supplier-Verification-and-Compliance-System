;; Audit Trail Contract
;; Provides transparency and immutable logging for all system activities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-LOG-NOT-FOUND (err u502))

;; Event Types
(define-constant EVENT-SUPPLIER-REGISTERED u1)
(define-constant EVENT-CERTIFICATION-ADDED u2)
(define-constant EVENT-COMPLIANCE-UPDATED u3)
(define-constant EVENT-RISK-ASSESSED u4)
(define-constant EVENT-VIOLATION-REPORTED u5)
(define-constant EVENT-AUDIT-COMPLETED u6)

;; Data Variables
(define-data-var next-log-id uint u1)
(define-data-var total-logs uint u0)

;; Data Maps
(define-map audit-logs uint {
  timestamp: uint,
  event-type: uint,
  actor: principal,
  supplier-id: uint,
  description: (string-ascii 200),
  data-hash: (string-ascii 64),
  previous-state: (string-ascii 100),
  new-state: (string-ascii 100)
})

(define-map supplier-activity uint (list 100 uint))
(define-map event-counts uint uint)
(define-map daily-activity uint (list 50 {date: uint, events: uint}))

;; Authorization Functions
(define-private (is-authorized (user principal))
  (is-eq user CONTRACT-OWNER))

;; Logging Functions
(define-public (log-event
  (event-type uint)
  (supplier-id uint)
  (description (string-ascii 200))
  (data-hash (string-ascii 64))
  (previous-state (string-ascii 100))
  (new-state (string-ascii 100)))
  (let ((log-id (var-get next-log-id)))
    (begin
      (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
      (asserts! (<= event-type u6) ERR-INVALID-INPUT)
      (asserts! (> supplier-id u0) ERR-INVALID-INPUT)
      (asserts! (> (len description) u0) ERR-INVALID-INPUT)

      (map-set audit-logs log-id {
        timestamp: block-height,
        event-type: event-type,
        actor: tx-sender,
        supplier-id: supplier-id,
        description: description,
        data-hash: data-hash,
        previous-state: previous-state,
        new-state: new-state
      })

      ;; Add to supplier activity
      (let ((current-activity (default-to (list) (map-get? supplier-activity supplier-id))))
        (map-set supplier-activity supplier-id
          (unwrap! (as-max-len? (append current-activity log-id) u100) ERR-INVALID-INPUT)))

      ;; Update event counts
      (let ((current-count (default-to u0 (map-get? event-counts event-type))))
        (map-set event-counts event-type (+ current-count u1)))

      (var-set next-log-id (+ log-id u1))
      (var-set total-logs (+ (var-get total-logs) u1))

      (ok log-id))))

(define-public (log-supplier-registration (supplier-id uint) (supplier-name (string-ascii 100)))
  (log-event
    EVENT-SUPPLIER-REGISTERED
    supplier-id
    (concat "Supplier registered: " supplier-name)
    "registration-hash"
    "none"
    "registered"))

(define-public (log-certification-added (supplier-id uint) (cert-type (string-ascii 50)) (cert-id uint))
  (log-event
    EVENT-CERTIFICATION-ADDED
    supplier-id
    (concat "Certification added: " cert-type)
    "cert-hash"
    "no-certification"
    "certified"))

(define-public (log-compliance-update (supplier-id uint) (regulation-type (string-ascii 50)) (status (string-ascii 20)))
  (log-event
    EVENT-COMPLIANCE-UPDATED
    supplier-id
    (concat "Compliance updated for: " regulation-type)
    "compliance-hash"
    "previous-status"
    status))

(define-public (log-risk-assessment (supplier-id uint) (risk-score uint) (risk-level (string-ascii 20)))
  (log-event
    EVENT-RISK-ASSESSED
    supplier-id
    (concat "Risk assessed - Level: " risk-level)
    "risk-hash"
    "previous-risk"
    risk-level))

(define-public (log-violation (supplier-id uint) (violation-type (string-ascii 50)) (severity (string-ascii 20)))
  (log-event
    EVENT-VIOLATION-REPORTED
    supplier-id
    (concat "Violation reported: " violation-type)
    "violation-hash"
    "compliant"
    "violation"))

(define-public (log-audit-completion (supplier-id uint) (audit-type (string-ascii 50)) (result (string-ascii 20)))
  (log-event
    EVENT-AUDIT-COMPLETED
    supplier-id
    (concat "Audit completed: " audit-type)
    "audit-hash"
    "pending-audit"
    result))

;; Read-only Functions
(define-read-only (get-audit-log (log-id uint))
  (map-get? audit-logs log-id))

(define-read-only (get-supplier-activity (supplier-id uint))
  (map-get? supplier-activity supplier-id))

(define-read-only (get-recent-activity (supplier-id uint) (limit uint))
  (let ((activity (default-to (list) (map-get? supplier-activity supplier-id))))
    (if (<= (len activity) limit)
      activity
      (unwrap-panic (slice? activity (- (len activity) limit) (len activity))))))

(define-read-only (get-event-count (event-type uint))
  (default-to u0 (map-get? event-counts event-type)))

(define-read-only (get-total-events)
  (var-get total-logs))

(define-read-only (get-activity-summary (supplier-id uint))
  (let ((activity (default-to (list) (map-get? supplier-activity supplier-id))))
    {
      total-events: (len activity),
      registrations: (count-registrations activity),
      certifications: (count-certifications activity),
      compliance-updates: (count-compliance-updates activity),
      risk-assessments: (count-risk-assessments activity),
      violations: (count-violations activity),
      audits: (count-audits activity)
    }))

;; Helper functions for counting specific event types
(define-private (count-registrations (activity (list 100 uint)))
  (fold count-registration-events activity u0))

(define-private (count-registration-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-SUPPLIER-REGISTERED)
      (+ count u1)
      count)
    count))

(define-private (count-certifications (activity (list 100 uint)))
  (fold count-certification-events activity u0))

(define-private (count-certification-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-CERTIFICATION-ADDED)
      (+ count u1)
      count)
    count))

(define-private (count-compliance-updates (activity (list 100 uint)))
  (fold count-compliance-events activity u0))

(define-private (count-compliance-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-COMPLIANCE-UPDATED)
      (+ count u1)
      count)
    count))

(define-private (count-risk-assessments (activity (list 100 uint)))
  (fold count-risk-events activity u0))

(define-private (count-risk-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-RISK-ASSESSED)
      (+ count u1)
      count)
    count))

(define-private (count-violations (activity (list 100 uint)))
  (fold count-violation-events activity u0))

(define-private (count-violation-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-VIOLATION-REPORTED)
      (+ count u1)
      count)
    count))

(define-private (count-audits (activity (list 100 uint)))
  (fold count-audit-events activity u0))

(define-private (count-audit-events (log-id uint) (count uint))
  (match (map-get? audit-logs log-id)
    log-entry (if (is-eq (get event-type log-entry) EVENT-AUDIT-COMPLETED)
      (+ count u1)
      count)
    count))

(define-read-only (verify-audit-trail (log-id uint) (expected-hash (string-ascii 64)))
  (match (map-get? audit-logs log-id)
    log-entry (is-eq (get data-hash log-entry) expected-hash)
    false))

(define-read-only (get-logs-by-timeframe (start-block uint) (end-block uint))
  (ok "Query not implemented - use off-chain indexing"))

(define-read-only (get-logs-by-actor (actor principal))
  (ok "Query not implemented - use off-chain indexing"))

(define-read-only (get-system-statistics)
  {
    total-logs: (var-get total-logs),
    supplier-registrations: (get-event-count EVENT-SUPPLIER-REGISTERED),
    certifications-added: (get-event-count EVENT-CERTIFICATION-ADDED),
    compliance-updates: (get-event-count EVENT-COMPLIANCE-UPDATED),
    risk-assessments: (get-event-count EVENT-RISK-ASSESSED),
    violations-reported: (get-event-count EVENT-VIOLATION-REPORTED),
    audits-completed: (get-event-count EVENT-AUDIT-COMPLETED)
  })

(define-read-only (is-log-tampered (log-id uint))
  ;; In a real implementation, this would verify cryptographic integrity
  false)

(define-read-only (get-compliance-timeline (supplier-id uint))
  (let ((activity (default-to (list) (map-get? supplier-activity supplier-id))))
    (filter is-compliance-event activity)))

(define-private (is-compliance-event (log-id uint))
  (match (map-get? audit-logs log-id)
    log-entry (or
      (is-eq (get event-type log-entry) EVENT-COMPLIANCE-UPDATED)
      (is-eq (get event-type log-entry) EVENT-VIOLATION-REPORTED)
      (is-eq (get event-type log-entry) EVENT-AUDIT-COMPLETED))
    false))

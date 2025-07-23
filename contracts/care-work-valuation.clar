;; Care Work Valuation Contract
;; Recognizes and compensates traditionally unpaid care labor

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-PROVIDER-NOT-FOUND (err u302))
(define-constant ERR-INSUFFICIENT-FUNDS (err u303))
(define-constant ERR-WORK-LOG-NOT-FOUND (err u304))

;; Data Variables
(define-data-var next-provider-id uint u1)
(define-data-var next-log-id uint u1)
(define-data-var community-fund uint u0)
(define-data-var base-hourly-rate uint u10)

;; Data Maps
(define-map care-providers uint {
    provider: principal,
    name: (string-ascii 100),
    care-types: (list 10 (string-ascii 50)),
    verified: bool,
    total-hours: uint,
    total-compensation: uint,
    rating: uint
})

(define-map provider-lookup principal uint)

(define-map care-work-logs uint {
    provider-id: uint,
    care-type: (string-ascii 50),
    hours-worked: uint,
    beneficiaries: uint,
    description: (string-ascii 300),
    verified: bool,
    compensation-paid: uint,
    logged-at: uint
})

(define-map community-contributions principal uint)
(define-map care-recipients principal (list 20 uint))

;; Public Functions

;; Register as care provider
(define-public (register-care-provider (name (string-ascii 100)) (care-types (list 10 (string-ascii 50))))
    (let ((provider-id (var-get next-provider-id)))
        (asserts! (> (len name) u0) ERR-INVALID-INPUT)
        (asserts! (> (len care-types) u0) ERR-INVALID-INPUT)

        (map-set care-providers provider-id {
            provider: tx-sender,
            name: name,
            care-types: care-types,
            verified: false,
            total-hours: u0,
            total-compensation: u0,
            rating: u0
        })

        (map-set provider-lookup tx-sender provider-id)
        (var-set next-provider-id (+ provider-id u1))
        (ok provider-id)
    )
)

;; Log care work
(define-public (log-care-work (care-type (string-ascii 50)) (hours-worked uint) (beneficiaries uint) (description (string-ascii 300)))
    (let ((provider-id (unwrap! (map-get? provider-lookup tx-sender) ERR-PROVIDER-NOT-FOUND))
          (log-id (var-get next-log-id)))
        (asserts! (> hours-worked u0) ERR-INVALID-INPUT)
        (asserts! (> beneficiaries u0) ERR-INVALID-INPUT)

        (map-set care-work-logs log-id {
            provider-id: provider-id,
            care-type: care-type,
            hours-worked: hours-worked,
            beneficiaries: beneficiaries,
            description: description,
            verified: false,
            compensation-paid: u0,
            logged-at: block-height
        })

        (var-set next-log-id (+ log-id u1))
        (ok log-id)
    )
)

;; Verify care work (community validation)
(define-public (verify-care-work (log-id uint))
    (let ((work-log (unwrap! (map-get? care-work-logs log-id) ERR-WORK-LOG-NOT-FOUND))
          (provider (unwrap! (map-get? care-providers (get provider-id work-log)) ERR-PROVIDER-NOT-FOUND)))
        (asserts! (not (is-eq tx-sender (get provider provider))) ERR-NOT-AUTHORIZED)
        (asserts! (not (get verified work-log)) ERR-INVALID-INPUT)

        ;; Mark work as verified
        (map-set care-work-logs log-id (merge work-log {
            verified: true
        }))

        ;; Calculate and pay compensation
        (let ((compensation (* (get hours-worked work-log) (var-get base-hourly-rate))))
            (if (>= (var-get community-fund) compensation)
                (begin
                    ;; Pay compensation
                    (map-set care-work-logs log-id (merge work-log {
                        verified: true,
                        compensation-paid: compensation
                    }))

                    ;; Update provider totals
                    (map-set care-providers (get provider-id work-log) (merge provider {
                        total-hours: (+ (get total-hours provider) (get hours-worked work-log)),
                        total-compensation: (+ (get total-compensation provider) compensation)
                    }))

                    ;; Deduct from community fund
                    (var-set community-fund (- (var-get community-fund) compensation))
                    (ok compensation)
                )
                (ok u0) ;; No compensation available
            )
        )
    )
)

;; Contribute to community fund
(define-public (contribute-to-fund (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-INPUT)

        ;; Add to community fund
        (var-set community-fund (+ (var-get community-fund) amount))

        ;; Track contributor
        (map-set community-contributions tx-sender
            (+ (default-to u0 (map-get? community-contributions tx-sender)) amount))

        (ok true)
    )
)

;; Rate care provider
(define-public (rate-provider (provider-id uint) (rating uint))
    (let ((provider (unwrap! (map-get? care-providers provider-id) ERR-PROVIDER-NOT-FOUND)))
        (asserts! (<= rating u5) ERR-INVALID-INPUT)
        (asserts! (> rating u0) ERR-INVALID-INPUT)
        (asserts! (not (is-eq tx-sender (get provider provider))) ERR-NOT-AUTHORIZED)

        ;; Simple rating update (could be enhanced with weighted averages)
        (map-set care-providers provider-id (merge provider {
            rating: rating
        }))

        (ok true)
    )
)

;; Read-only Functions

(define-read-only (get-care-provider (provider-id uint))
    (map-get? care-providers provider-id)
)

(define-read-only (get-provider-by-principal (provider principal))
    (match (map-get? provider-lookup provider)
        provider-id (map-get? care-providers provider-id)
        none
    )
)

(define-read-only (get-care-work-log (log-id uint))
    (map-get? care-work-logs log-id)
)

(define-read-only (get-community-fund-balance)
    (var-get community-fund)
)

(define-read-only (get-user-contribution (user principal))
    (default-to u0 (map-get? community-contributions user))
)

(define-read-only (get-base-hourly-rate)
    (var-get base-hourly-rate)
)

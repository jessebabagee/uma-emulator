;; uma-verification.clar
;; UMA Verification Platform

;; This contract manages the certification and verification of smart contracts on the Stacks blockchain.
;; It provides functionality for:
;; 1. Registering and managing qualified auditors
;; 2. Submitting contracts for certification
;; 3. Issuing certifications with metadata
;; 4. Verifying contract certification status
;; 5. Managing auditor reputation and trust scores

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-REGISTERED (err u102))
(define-constant ERR-INVALID-RATING (err u103))
(define-constant ERR-ALREADY-CERTIFIED (err u104))
(define-constant ERR-NOT-CERTIFIED (err u105))
(define-constant ERR-INVALID-STATUS (err u106))
(define-constant ERR-INVALID-PARAMETERS (err u107))
(define-constant ERR-CONTRACT-NOT-FOUND (err u108))

;; Platform admin control
(define-data-var platform-admin principal tx-sender)

;; Auditor registry: maps auditor principal to their details and status
(define-map uma-auditors
  principal
  {
    name: (string-ascii 64),
    organization: (string-ascii 64),
    website: (string-ascii 128),
    trust-score: uint,
    certification-count: uint,
    status: (string-ascii 10),
    approved-timestamp: uint
  }
)

;; Certification requests tracking
(define-map certification-submissions
  {
    contract-id: principal,
    version: (string-ascii 16)
  }
  {
    owner: principal,
    description: (string-ascii 256),
    repository-url: (string-ascii 128),
    submission-time: uint,
    review-status: (string-ascii 10)
  }
)

;; Issued certifications
(define-map uma-certifications
  {
    contract-id: principal,
    version: (string-ascii 16)
  }
  {
    auditor: principal,
    security-rating: uint,
    audit-report-url: (string-ascii 128),
    certification-timestamp: uint,
    valid-until: uint,
    additional-notes: (string-ascii 256)
  }
)

;; Certification historical tracking
(define-map certification-audit-log
  { 
    contract-id: principal,
    log-index: uint 
  }
  {
    version: (string-ascii 16),
    auditor: principal,
    security-rating: uint,
    certification-timestamp: uint
  }
)

;; Counter tracking certifications per contract
(define-map certification-counts principal uint)

;; Global platform statistics
(define-data-var total-registered-auditors uint u0)
(define-data-var total-issued-certifications uint u0)
(define-data-var total-certified-contracts uint u0)

;; Private helper functions

(define-private (is-platform-admin)
  (is-eq tx-sender (var-get platform-admin))
)

(define-private (is-active-auditor (auditor principal))
  (match (map-get? uma-auditors auditor)
    auditor-details (is-eq (get status auditor-details) "active")
    false
  )
)

(define-private (increment-certification-count (contract-id principal))
  (let ((current-count (default-to u0 (map-get? certification-counts contract-id))))
    (map-set certification-counts contract-id (+ current-count u1))
    (+ current-count u1)
  )
)

(define-private (log-certification-audit 
                  (contract-id principal) 
                  (version (string-ascii 16)) 
                  (auditor principal) 
                  (security-rating uint))
  (let ((index (increment-certification-count contract-id)))
    (map-set certification-audit-log
      { contract-id: contract-id, log-index: index }
      {
        version: version,
        auditor: auditor,
        security-rating: security-rating,
        certification-timestamp: block-height
      }
    )
  )
)

;; Read-only query functions

(define-read-only (is-contract-certified (contract-id principal) (version (string-ascii 16)))
  (is-some (map-get? uma-certifications { contract-id: contract-id, version: version }))
)

(define-read-only (get-auditor-profile (auditor principal))
  (map-get? uma-auditors auditor)
)

(define-read-only (get-certification-details (contract-id principal) (version (string-ascii 16)))
  (map-get? uma-certifications { contract-id: contract-id, version: version })
)

(define-read-only (get-certification-submission (contract-id principal) (version (string-ascii 16)))
  (map-get? certification-submissions { contract-id: contract-id, version: version })
)

(define-read-only (get-certification-audit-log (contract-id principal) (index uint))
  (map-get? certification-audit-log { contract-id: contract-id, log-index: index })
)

(define-read-only (get-contract-certification-count (contract-id principal))
  (default-to u0 (map-get? certification-counts contract-id))
)

(define-read-only (get-platform-statistics)
  {
    total-auditors: (var-get total-registered-auditors),
    total-certifications: (var-get total-issued-certifications),
    total-certified-contracts: (var-get total-certified-contracts)
  }
)

;; Public management functions

(define-public (transfer-platform-admin (new-admin principal))
  (begin
    (asserts! (is-platform-admin) ERR-NOT-AUTHORIZED)
    (ok (var-set platform-admin new-admin))
  )
)

(define-public (submit-auditor-application
                (name (string-ascii 64))
                (organization (string-ascii 64))
                (website (string-ascii 128))
                (credentials (string-ascii 256)))
  (begin
    (asserts! (is-none (map-get? uma-auditors tx-sender)) ERR-ALREADY-REGISTERED)
    
    (map-set certification-submissions tx-sender
      {
        name: name,
        organization: organization,
        website: website,
        credentials: credentials,
        submission-time: block-height,
        review-status: "pending"
      }
    )
    (ok true)
  )
)

(define-public (approve-auditor-application (auditor principal))
  (begin
    (asserts! (is-platform-admin) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? uma-auditors auditor)) ERR-ALREADY-REGISTERED)
    
    (let ((application (unwrap! (map-get? certification-submissions auditor) ERR-NOT-REGISTERED)))
      (map-set uma-auditors auditor
        {
          name: (get name application),
          organization: (get organization application),
          website: (get website application),
          trust-score: u5,
          certification-count: u0,
          status: "active",
          approved-timestamp: block-height
        }
      )
      (var-set total-registered-auditors (+ (var-get total-registered-auditors) u1))
      (map-delete certification-submissions auditor)
      (ok true)
    )
  )
)

(define-public (request-contract-certification 
                (contract-id principal) 
                (version (string-ascii 16)) 
                (description (string-ascii 256))
                (repository-url (string-ascii 128)))
  (begin
    (asserts! (is-none (map-get? certification-submissions 
                          { contract-id: contract-id, version: version })) 
              ERR-ALREADY-REGISTERED)
    
    (map-set certification-submissions
      { contract-id: contract-id, version: version }
      {
        owner: tx-sender,
        description: description,
        repository-url: repository-url,
        submission-time: block-height,
        review-status: "pending"
      }
    )
    (ok true)
  )
)

(define-public (verify-contract-status (contract-id principal) (version (string-ascii 16)))
  (ok (is-contract-certified contract-id version))
)

(define-public (get-verification-details (contract-id principal) (version (string-ascii 16)))
  (match (map-get? uma-certifications { contract-id: contract-id, version: version })
    cert-details
      (let ((auditor-profile (default-to 
                              { 
                                name: "", organization: "", website: "", trust-score: u0,
                                certification-count: u0, status: "", approved-timestamp: u0
                              }
                              (map-get? uma-auditors (get auditor cert-details)))))
        (ok {
          certified: true,
          auditor: (get auditor cert-details),
          auditor-name: (get name auditor-profile),
          auditor-organization: (get organization auditor-profile),
          security-rating: (get security-rating cert-details),
          certification-time: (get certification-timestamp cert-details),
          valid-until: (get valid-until cert-details),
          auditor-trust-score: (get trust-score auditor-profile)
        }))
    (ok { certified: false, auditor: tx-sender, auditor-name: "", auditor-organization: "",
          security-rating: u0, certification-time: u0, valid-until: u0, auditor-trust-score: u0 })
  )
)
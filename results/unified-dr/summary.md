# Disaster Recovery Report: LIVE-RUN-20261018-230436

## 1. Executive Summary

- **RUN_ID**: `LIVE-RUN-20261018-230436`
- **Execution Scope**: `unified`
- **Operation Type**: `planned`
- **Failure Start (T0)**: `2026-10-18T23:05:15.101Z`
- **Primary Region**: `ap-southeast-1` (Singapore)
- **Recovery Region**: `ap-northeast-1` (Tokyo)
- **Overall Outcome**: **SUCCESS**
- **Orchestration Execution Time**: N/A

## 2. Quantitative RTO and RPO Metrics

| Metric | Target | Measured | Uncertainty | Objective Outcome | Integrity Outcome | Evidence Reference |
|---|---|---|---|---|---|---|
| **Database RTO (Aurora Tokyo Writer)** | `≤ 240s` | 47.43s | `±0.5s` | **PASS** | N/A | [`database/rto.json`](../database/rto.json) |
| **Database RPO (Lost Records: 0)** | `≤ 60s` | 0.00s | `±0.5s` | **PASS** | **PASS** | [`database/rpo.json`](../database/rpo.json) |
| **Storage RTO (FSx User-Visible)** | `≤ 300s` | 6.40s | `±0.5s` | **PASS** | N/A | [`storage/rto.json`](../storage/rto.json) |
| **Storage RPO (Lost Files: 0)** | `≤ 300s` | 0.00s | `±0.5s` | **PASS** | **PASS** | [`storage/rpo.json`](../storage/rpo.json) |
| **Overall End-to-End RTO** | `≤ 300s` | 47.43s | `±0.5s` | **PASS** | N/A | [`overall/recovery.json`](recovery.json) |
| **Database Data Integrity** | VERIFIED_INTACT | VERIFIED_INTACT | N/A | N/A | **PASS** | [`database/integrity.json`](../database/integrity.json) |
| **Storage Data Integrity** | VERIFIED_INTACT | VERIFIED_INTACT | N/A | N/A | **PASS** | [`storage/integrity.json`](../storage/integrity.json) |

## 3. Data Integrity & Sequence Analysis

- **Database Last Acked Sequence**: `SEQ-000005`
- **Database Recovered Sequence**: `SEQ-000005`
- **Database Missing Gap Ranges**: `None (Contiguous)`
- **Database RPO Calculation Method**: `ZERO_LOSS_VERIFIED`
- **Storage Last Acked Sequence**: `SEQ-000005`
- **Storage Recovered Sequence**: `SEQ-000005`
- **Storage Missing Gap Ranges**: `None (Contiguous)`
- **Storage RPO Calculation Method**: `ZERO_LOSS_VERIFIED`
- **Storage SHA-256 Checksum Verified**: `YES`

## 4. Evidence References

- Database RTO Details: [`database/rto.json`](../database/rto.json)
- Database RPO Details: [`database/rpo.json`](../database/rpo.json)
- Storage RTO Details: [`storage/rto.json`](../storage/rto.json)
- Storage RPO Details: [`storage/rpo.json`](../storage/rpo.json)
- Execution Timeline: [`timeline.csv`](timeline.csv)
- Raw Machine Data: [`result.json`](result.json)

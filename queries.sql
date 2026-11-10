-- Замените YOUR_PROJECT_ID на ID своего проекта BigQuery.
-- Таблица: YOUR_PROJECT_ID.text_ranking.wikiqa_scores

-- Проверка загруженного CSV
SELECT
  COUNT(*) AS rows_count,
  COUNT(DISTINCT question_id) AS questions,
  SUM(label) AS positives,
  COUNT(DISTINCT IF(label = 1, question_id, NULL)) AS questions_with_answer
FROM `YOUR_PROJECT_ID.text_ranking.wikiqa_scores`;

-- NDCG@5 для BM25 варианта 1
DECLARE k INT64 DEFAULT 5;
WITH ranked AS (
  SELECT
    question_id,
    label,
    ROW_NUMBER() OVER (
      PARTITION BY question_id
      ORDER BY score_bm25_variant DESC, cand_order
    ) AS pos,
    ROW_NUMBER() OVER (
      PARTITION BY question_id
      ORDER BY label DESC, cand_order
    ) AS ideal_pos
  FROM `YOUR_PROJECT_ID.text_ranking.wikiqa_scores`
),
per_query AS (
  SELECT
    question_id,
    SUM(IF(pos <= k, (POW(2, label) - 1) / LOG(pos + 1, 2), 0)) AS dcg,
    SUM(IF(ideal_pos <= k, (POW(2, label) - 1) / LOG(ideal_pos + 1, 2), 0)) AS idcg
  FROM ranked
  GROUP BY question_id
)
SELECT
  COUNT(*) AS queries,
  ROUND(AVG(dcg), 4) AS mean_dcg,
  ROUND(AVG(dcg / idcg), 4) AS mean_ndcg
FROM per_query
WHERE idcg > 0;

-- Сравнение методов при k=5 и k=10
WITH long_scores AS (
  SELECT question_id, cand_order, label, method, score
  FROM `YOUR_PROJECT_ID.text_ranking.wikiqa_scores`
  UNPIVOT (
    score FOR method IN (
      score_overlap, score_tfidf, score_bm25_default, score_bm25_variant
    )
  )
),
ranked AS (
  SELECT
    method,
    question_id,
    label,
    ROW_NUMBER() OVER (
      PARTITION BY method, question_id ORDER BY score DESC, cand_order
    ) AS pos,
    ROW_NUMBER() OVER (
      PARTITION BY method, question_id ORDER BY label DESC, cand_order
    ) AS ideal_pos
  FROM long_scores
),
per_query AS (
  SELECT
    method,
    question_id,
    k,
    SUM(IF(pos <= k, (POW(2, label) - 1) / LOG(pos + 1, 2), 0)) AS dcg,
    SUM(IF(ideal_pos <= k, (POW(2, label) - 1) / LOG(ideal_pos + 1, 2), 0)) AS idcg
  FROM ranked
  CROSS JOIN UNNEST([5, 10]) AS k
  GROUP BY method, question_id, k
)
SELECT
  method,
  k,
  COUNT(*) AS queries,
  ROUND(AVG(dcg), 4) AS mean_dcg,
  ROUND(AVG(dcg / idcg), 4) AS mean_ndcg
FROM per_query
WHERE idcg > 0
GROUP BY method, k
ORDER BY k, mean_ndcg DESC;

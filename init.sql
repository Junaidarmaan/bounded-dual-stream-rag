
-- Enable pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- Store accepted coaching knowledge
CREATE TABLE IF NOT EXISTS knowledge_vault (
    id BIGSERIAL PRIMARY KEY,
    session_id TEXT NOT NULL,
    stream_type TEXT NOT NULL
        CHECK (stream_type IN ('framework', 'voice_sample')),
    content TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}',
    embedding VECTOR(1536) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- HNSW index for cosine similarity search
CREATE INDEX IF NOT EXISTS knowledge_vault_embedding_idx
ON knowledge_vault
USING hnsw (embedding vector_cosine_ops);

-- Archive rejected meetings without embeddings
CREATE TABLE IF NOT EXISTS rejected_meetings (
    session_id TEXT PRIMARY KEY,
    title TEXT,
    meeting_type TEXT,
    confidence_score NUMERIC(4,3),
    summary TEXT,
    rejection_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}',
    archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
